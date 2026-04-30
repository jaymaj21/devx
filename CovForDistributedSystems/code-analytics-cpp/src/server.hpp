#pragma once
#include <thread>
#include <vector>
#include <atomic>
#include <cstring>
#include <iostream>
#include <sstream>
#include <mutex>
#include <condition_variable>
#include <unordered_map>
#include <functional>
#include <algorithm>
#include <csignal>
#include <deque>

#ifdef _WIN32
  #ifndef NOMINMAX
  #define NOMINMAX
  #endif
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #pragma comment(lib, "ws2_32.lib")
#else
  #include <sys/types.h>
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #include <unistd.h>
  #define INVALID_SOCKET -1
  #define SOCKET_ERROR   -1
  using SOCKET = int;
#endif

#include "util.hpp"
#include "trace_writer.hpp"
#include "context_manager.hpp"

struct ServerConfig {
    uint16_t udpPort = 8083;
    uint16_t tcpPort = 8084;
    std::string tracePath;
};

class Server {
public:
    explicit Server(ServerConfig cfg) : cfg_(std::move(cfg)) {}
    ~Server(){ stop(); }

    bool start(){
#ifdef _WIN32
        WSADATA wsa;
        if (WSAStartup(MAKEWORD(2,2), &wsa) != 0) {
            std::cerr << "WSAStartup failed\n"; return false;
        }
#endif
        running_.store(true);
        if (!cfg_.tracePath.empty()) trace_.open(cfg_.tracePath);

        // Spawn UDP parse workers
        unsigned hw = std::thread::hardware_concurrency();
        unsigned workers = hw ? (std::max)(2u, hw) : 2u;
        for (unsigned i=0; i<workers; ++i) {
            udpParsers_.emplace_back(&Server::udpParserLoop, this);
        }

        udpThread_ = std::thread(&Server::udpLoop, this);
        tcpThread_ = std::thread(&Server::tcpLoop, this);
        tsThread_  = std::thread(&Server::tsLoop,  this);
        return true;
    }

    void stop(){
        bool expected=true;
        if (!running_.compare_exchange_strong(expected, false)) return; // already stopped
        // join threads
        if (udpThread_.joinable()) udpThread_.join();
        {
            std::unique_lock<std::mutex> lk(qmtx_);
            qcv_.notify_all();
        }
        for (auto &t : udpParsers_) if (t.joinable()) t.join();
        if (tcpThread_.joinable()) tcpThread_.join();
        if (tsThread_.joinable()) tsThread_.join();
#ifdef _WIN32
        WSACleanup();
#endif
        trace_.close();
    }

    ContextManager& ctx(){ return ctx_; }

    // Expose a tiny helper for flushing trace via REPL
    void flushTrace(){ trace_.flush(); }
    void persistTrace(){ trace_.persist(); }

private:
    void tsLoop(){
        using namespace std::chrono;
        while (running_.load()){
            std::this_thread::sleep_for(std::chrono::seconds(10));
            // payload: u64 epochMillis (big-endian), flag=9
            uint64_t ms = duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
            std::vector<uint8_t> payload; payload.reserve(8);
            for (int i=7;i>=0;--i) payload.push_back(uint8_t((ms >> (i*8)) & 0xFF));
            trace_.writeFrame(9, TraceWriter::INTERNAL, payload);
        }
    }
    void udpLoop(){
        SOCKET s = ::socket(AF_INET, SOCK_DGRAM, 0);
        if (s==INVALID_SOCKET) { std::cerr << "[UDP] socket() failed\n"; return; }

        // Increase receive buffer to reduce drops under burst load
        int rcvbuf = 1<<24; // ~16 MiB, best-effort
#ifdef _WIN32
        setsockopt(s, SOL_SOCKET, SO_RCVBUF, reinterpret_cast<const char*>(&rcvbuf), sizeof(rcvbuf));
#else
        setsockopt(s, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
#endif

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons(cfg_.udpPort);

        if (bind(s, (sockaddr*)&addr, sizeof(addr))==SOCKET_ERROR) {
            std::cerr << "[UDP] bind() failed\n";
#ifdef _WIN32
            closesocket(s);
#else
            close(s);
#endif
            return;
        }

        std::vector<uint8_t> buf(65536);
        while (running_.load()) {
            sockaddr_in src{}; socklen_t slen = sizeof(src);
            int n = recvfrom(s, (char*)buf.data(), (int)buf.size(), 0, (sockaddr*)&src, &slen);
            if (n<=0) continue;
            std::vector<uint8_t> payload(buf.begin(), buf.begin()+n);
            // Hand off to parser queue
            {
                std::unique_lock<std::mutex> lk(qmtx_);
                udpQueue_.push_back(std::move(payload));
            }
            qcv_.notify_one();
        }

#ifdef _WIN32
        closesocket(s);
#else
        close(s);
#endif
    }

    void udpParserLoop(){
        while (running_.load()) {
            std::vector<uint8_t> payload;
            {
                std::unique_lock<std::mutex> lk(qmtx_);
                qcv_.wait(lk, [&]{ return !running_.load() || !udpQueue_.empty(); });
                if (!udpQueue_.empty()) {
                    payload = std::move(udpQueue_.front());
                    udpQueue_.pop_front();
                } else if (!running_.load()) {
                    break;
                }
            }
            if (!payload.empty()) {
                // parse and trace
                parseBuffer(payload, TraceWriter::UDP);
            }
        }
        // Drain any remaining packets on shutdown
        for (;;) {
            std::vector<uint8_t> payload;
            {
                std::lock_guard<std::mutex> lk(qmtx_);
                if (udpQueue_.empty()) break;
                payload = std::move(udpQueue_.front());
                udpQueue_.pop_front();
            }
            if (!payload.empty()) parseBuffer(payload, TraceWriter::UDP);
        }
    }

    void tcpClient(SOCKET c){
        std::vector<uint8_t> buf(8192);
        std::vector<uint8_t> stream;
        while (running_.load()) {
            int n = recv(c, (char*)buf.data(), (int)buf.size(), 0);
            if (n<=0) break;
            stream.insert(stream.end(), buf.begin(), buf.begin()+n);
            // parse as stream
            size_t consumed = parseStream(stream, TraceWriter::TCP);
            if (consumed>0) {
                stream.erase(stream.begin(), stream.begin()+consumed);
            }
        }
#ifdef _WIN32
        closesocket(c);
#else
        close(c);
#endif
    }

    void tcpLoop(){
        SOCKET s = ::socket(AF_INET, SOCK_STREAM, 0);
        if (s==INVALID_SOCKET) { std::cerr << "[TCP] socket() failed\n"; return; }
        int opt=1;
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (char*)&opt, sizeof(opt));
        sockaddr_in addr{}; addr.sin_family=AF_INET; addr.sin_addr.s_addr=htonl(INADDR_ANY); addr.sin_port=htons(cfg_.tcpPort);
        if (bind(s, (sockaddr*)&addr, sizeof(addr))==SOCKET_ERROR){ std::cerr << "[TCP] bind failed\n";
#ifdef _WIN32
            closesocket(s);
#else
            close(s);
#endif
            return; }
        if (listen(s, 8)==SOCKET_ERROR){ std::cerr << "[TCP] listen failed\n";
#ifdef _WIN32
            closesocket(s);
#else
            close(s);
#endif
            return; }

        while (running_.load()) {
            sockaddr_in cli{}; socklen_t clen=sizeof(cli);
            SOCKET c = accept(s, (sockaddr*)&cli, &clen);
            if (c==INVALID_SOCKET) continue;
            std::thread(&Server::tcpClient, this, c).detach();
        }
#ifdef _WIN32
        closesocket(s);
#else
        close(s);
#endif
    }

    // Return bytes consumed (for tcp stream parsing)
    size_t parseStream(const std::vector<uint8_t>& data, TraceWriter::Src src){
        size_t pos=0, n=data.size();
        while (pos + 2 <= n) { // need at least type
            uint16_t type = be16(&data[pos]);
            // Each hit frame should be exactly 20 bytes: type(2) appId(2) instId(4) threadId(4) stackDepth(4) locId(4)
            if (type==1) {
                if (pos + 20 <= n) {
                    uint16_t appId = be16(&data[pos+2]);
                    // Quick validation: appId should be 12345 for JavaAppWithUdpProbes
                    
                    handleHit(&data[pos], 20, src);
                    
                    pos += 20;
                } else break;
            } else if (type==2) {
                if (pos + 18 <= n) {
                    uint16_t msgLen = be16(&data[pos+16]);
                    if (pos + 18 + msgLen <= n) {
                        handleLog(&data[pos], 18 + msgLen, src);
                        pos += 18 + msgLen;
                    } else break;
                } else break;
            } else if (type==3 || type==4) {
                // treat the rest of buffer as one context command
                handleContext(&data[pos], n - pos, src);
                pos = n; // consume all
                break;
            } else {
                // unknown -> stop (avoid infinite loop)
                break;
            }
        }
        return pos;
    }

    void parseBuffer(const std::vector<uint8_t>& payload, TraceWriter::Src src){
        // For UDP we can parse a whole datagram possibly containing multiple records
        size_t pos=0, n=payload.size();
        while (pos + 2 <= n) {
            uint16_t type = be16(&payload[pos]);
            // Each hit frame should be exactly 20 bytes: type(2) appId(2) instId(4) threadId(4) stackDepth(4) locId(4)
            if (type==1) {
                if (pos + 20 <= n) {
                    uint16_t appId = be16(&payload[pos+2]);
                    // Quick validation: appId should be 12345 for JavaAppWithUdpProbes
                   
                     handleHit(&payload[pos], 20, src);
                 
                    pos += 20;
                } else break;
            } else if (type==2) {
                if (pos + 18 <= n) {
                    uint16_t msgLen = be16(&payload[pos+16]);
                    if (pos + 18 + msgLen <= n) {
                        handleLog(&payload[pos], 18 + msgLen, src);
                        pos += 18 + msgLen;
                    } else break;
                } else break;
            } else if (type==3 || type==4) {
                // context consumes the rest of datagram
                handleContext(&payload[pos], n - pos, src);
                pos = n;
            } else {
                break;
            }
        }
    }

    void handleHit(const uint8_t* p, size_t len, TraceWriter::Src src){
        if (len < 20) return;  // Require exactly 20 bytes for hit records
        // write to trace with HIT flag
        trace_.writeFrame(1, src, std::vector<uint8_t>(p, p+len));
        uint16_t type = be16(p);
        uint16_t appId = be16(p+2);
        uint32_t instanceId = be32(p+4);
        uint32_t threadId = be32(p+8);
        uint32_t stackDepth = be32(p+12);
        uint32_t locationId = be32(p+16);
        (void)stackDepth; // currently unused, parsed to consume bytes
        ctx_.recordHit(appId, instanceId, threadId, locationId);
    }

    void handleLog(const uint8_t* p, size_t len, TraceWriter::Src src){
        trace_.writeFrame(2, src, std::vector<uint8_t>(p, p+len));
        uint16_t appId = be16(p+2);
        uint32_t instanceId = be32(p+4);
        uint32_t threadId = be32(p+8);
        uint32_t stackDepth = be32(p+12);
        uint16_t mlen = be16(p+16);
        std::string msg((const char*)(p+18), (const char*)(p+18+mlen));
        std::cout << "[LOG] app="<<appId<<" inst="<<instanceId<<" thr="<<threadId<<" sd="<<stackDepth<<": "<<msg<<"\n";
    }

    void handleContext(const uint8_t* p, size_t len, TraceWriter::Src src){
        uint16_t type = be16(p);
        uint16_t flag = (type==3 ? 3 : 4);
        trace_.writeFrame(flag, src, std::vector<uint8_t>(p, p+len));
        uint16_t type = be16(p);
        std::string name;
        if (len>2) name.assign((const char*)(p+2), (const char*)(p+len));
        if (type==3) { ctx_.attach(name); std::cout<<"[CTX] attach "<<name<<"\n"; }
        else if (type==4) { ctx_.withdraw(name); std::cout<<"[CTX] withdraw "<<name<<"\n"; }
    }

private:
    ServerConfig cfg_;
    std::atomic<bool> running_{false};
    std::thread udpThread_, tcpThread_, tsThread_;
    std::vector<std::thread> udpParsers_;
    std::mutex qmtx_;
    std::condition_variable qcv_;
    std::deque<std::vector<uint8_t>> udpQueue_;
    TraceWriter trace_;
    ContextManager ctx_;
};

