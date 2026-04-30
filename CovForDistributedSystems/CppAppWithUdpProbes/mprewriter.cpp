#include <iostream>
#include <vector>
#include <queue>
#include <thread>
#include <mutex>
#include <atomic>
#include <cstring>
#include <condition_variable>
#include <chrono>
#include <string>
#include <cstdint>
#include <memory>

#include "mprewriter.hpp"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "Ws2_32.lib")
#else
#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#endif

// --- Configuration ---
constexpr const char* RECEIVER_HOST = "127.0.0.1";
constexpr uint16_t UDP_PORT = 8083;
constexpr uint16_t APPLICATION_ID = 12345;
constexpr int INSTANCE_ID = 2;
constexpr int MAX_HITS_PER_PACKET = 72; // 72*20 = 1440 bytes (fits typical MTU without fragmentation)
constexpr int MAX_LOG_BYTES = 1184;
constexpr int BATCH_INTERVAL_MS = 5;

// --- Types ---
struct LogRecord {
    int32_t threadId;
    std::vector<uint8_t> utf8_bytes; // UTF-8 encoded log message
};

// --- Queues and control ---
// Lock-free MPSC ring buffer for hits
namespace {
    constexpr size_t HIT_RING_CAP = 1u << 20; // 1,048,576 slots
    struct alignas(64) HitSlot {
        std::atomic<int> ready{0};
        struct { uint8_t bytes[20]; } frame; // prepacked 20-byte network-order frame
    };
    std::unique_ptr<HitSlot[]> hitRing;
    std::atomic<uint64_t> hitHead{0};
    std::atomic<uint64_t> hitTail{0};
}

std::queue<LogRecord> logQueue; // logs are rare; keep simple
std::atomic<size_t> logCount{0}; // lock-free visibility for presence check
std::mutex queueMutex;
std::atomic<bool> running(true);

// Thread-local depth definition
thread_local int g_mpr_stack_depth = 0;
thread_local int g_mpr_thread_id = []{
    return static_cast<int>(std::hash<std::thread::id>{}(std::this_thread::get_id()) & 0x7FFFFFFF);
}();

// Background sender thread handle
static std::thread g_senderThread;

// --- UTF-8 Encoding Helper ---
std::vector<uint8_t> encode_utf8(const std::string& s) {
    // For most environments, std::string is UTF-8 already.
    return std::vector<uint8_t>(s.begin(), s.end());
}

// --- Sender Thread ---
void senderThreadFunc() {
#ifdef _WIN32
    SOCKET sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sockfd == INVALID_SOCKET) {
        std::cerr << "socket() failed: " << WSAGetLastError() << std::endl;
        exit(1);
    }
    // Increase send buffer to reduce drops under burst load
    {
        int sndbuf = 1 << 20;
        setsockopt(sockfd, SOL_SOCKET, SO_SNDBUF, reinterpret_cast<const char*>(&sndbuf), sizeof(sndbuf));
    }
#else
    int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) { perror("socket"); exit(1); }
    // Increase send buffer to reduce drops under burst load
    {
        int sndbuf = 1 << 20;
        setsockopt(sockfd, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));
    }
#endif

    sockaddr_in server_addr{};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(UDP_PORT);
#ifdef _WIN32
    inet_pton(AF_INET, RECEIVER_HOST, &server_addr.sin_addr);
#else
    inet_pton(AF_INET, RECEIVER_HOST, &server_addr.sin_addr);
#endif

    std::vector<uint8_t> sendBuffer(20 * MAX_HITS_PER_PACKET);

    while (running || (hitHead.load(std::memory_order_acquire) != hitTail.load(std::memory_order_acquire)) || (logCount.load(std::memory_order_acquire) > 0)) {
        // 1. Send batched hits from lock-free ring
        int hitsProcessed = 0;
        uint8_t* out = sendBuffer.data();
        while (hitsProcessed < MAX_HITS_PER_PACKET) {
            uint64_t h = hitHead.load(std::memory_order_relaxed);
            if (h == hitTail.load(std::memory_order_relaxed)) break; // empty
            HitSlot &slot = hitRing[h & (HIT_RING_CAP - 1)];
            if (slot.ready.load(std::memory_order_acquire) == 0) {
                // If shutting down and a slot is unfilled, skip it to avoid hang
                if (!running.load(std::memory_order_relaxed)) {
                    hitHead.store(h + 1, std::memory_order_release);
                    continue;
                }
                break; // wait for producer to fill
            }
            // Copy prepacked 20-byte frame into send buffer
            memcpy(out, slot.frame.bytes, 20);
            out += 20;
            slot.ready.store(0, std::memory_order_release);
            hitHead.store(h + 1, std::memory_order_release);

            ++hitsProcessed;
        }
        if (hitsProcessed > 0) {
            int packetLen = hitsProcessed * 20;
#ifdef _WIN32
            sendto(sockfd, reinterpret_cast<const char*>(sendBuffer.data()), packetLen, 0,
                reinterpret_cast<sockaddr*>(&server_addr), sizeof(server_addr));
#else
            sendto(sockfd, sendBuffer.data(), packetLen, 0, (sockaddr*)&server_addr, sizeof(server_addr));
#endif
        }

        // 2. Send logs (rare)
        while (true) {
            LogRecord lr;
            {
                std::lock_guard<std::mutex> lk(queueMutex);
                if (logQueue.empty()) break;
                lr = logQueue.front();
                logQueue.pop();
                logCount.fetch_sub(1, std::memory_order_release);
            }

            size_t logLen = lr.utf8_bytes.size();
            if (logLen > MAX_LOG_BYTES) logLen = MAX_LOG_BYTES; // Just in case

            std::vector<uint8_t> logPacket(18 + logLen);
            uint16_t type = htons(2);
            uint16_t appId = htons(APPLICATION_ID);
            uint32_t instId = htonl(INSTANCE_ID);
            uint32_t threadId = htonl(lr.threadId);
            uint32_t stackDepth = htonl(g_mpr_stack_depth);
            uint16_t logLenShort = htons(static_cast<uint16_t>(logLen));

            size_t offset = 0;
            memcpy(&logPacket[offset], &type, 2);         offset += 2;
            memcpy(&logPacket[offset], &appId, 2);        offset += 2;
            memcpy(&logPacket[offset], &instId, 4);       offset += 4;
            memcpy(&logPacket[offset], &threadId, 4);     offset += 4;
            memcpy(&logPacket[offset], &stackDepth, 4);   offset += 4;
            memcpy(&logPacket[offset], &logLenShort, 2);  offset += 2;
            memcpy(&logPacket[offset], lr.utf8_bytes.data(), logLen);

#ifdef _WIN32
            sendto(sockfd, reinterpret_cast<const char*>(logPacket.data()), static_cast<int>(logPacket.size()), 0,
                reinterpret_cast<sockaddr*>(&server_addr), sizeof(server_addr));
#else
            sendto(sockfd, logPacket.data(), logPacket.size(), 0, (sockaddr*)&server_addr, sizeof(server_addr));
#endif
        }
        // Small pause to avoid busy-spin when no work
        if (hitsProcessed == 0) {
            std::this_thread::sleep_for(std::chrono::microseconds(200));
        }
    }
#ifdef _WIN32
    closesocket(sockfd);
#else
    close(sockfd);
#endif
}

// --- Public Interface ---
void scope_record_hit(int locationId, int stackDepth) {
    while (true) {
        uint64_t t = hitTail.load(std::memory_order_relaxed);
        // Check capacity
        if (t - hitHead.load(std::memory_order_acquire) >= HIT_RING_CAP) {
            std::this_thread::yield();
            continue;
        }
        // Try to claim a slot by advancing tail
        if (!hitTail.compare_exchange_weak(t, t + 1, std::memory_order_acq_rel, std::memory_order_relaxed)) {
            std::this_thread::yield();
            continue;
        }
        HitSlot &slot = hitRing[t & (HIT_RING_CAP - 1)];
        // Ensure slot is free (consumer resets ready to 0)
        while (slot.ready.load(std::memory_order_acquire) != 0) { std::this_thread::yield(); }
        // Prepack 20-byte frame: type(2), appId(2), instId(4), threadId(4), stackDepth(4), locationId(4)
        uint8_t* b = slot.frame.bytes;
        uint16_t type_be = htons(1);
        uint16_t app_be  = htons(APPLICATION_ID);
        uint32_t inst_be = htonl(INSTANCE_ID);
        uint32_t tid_be  = htonl(g_mpr_thread_id);
        uint32_t sd_be   = htonl(stackDepth);
        uint32_t loc_be  = htonl(locationId);
        memcpy(b + 0, &type_be, 2);
        memcpy(b + 2, &app_be,  2);
        memcpy(b + 4, &inst_be, 4);
        memcpy(b + 8, &tid_be,  4);
        memcpy(b + 12, &sd_be,  4);
        memcpy(b + 16, &loc_be, 4);
        slot.ready.store(1, std::memory_order_release);
        break;
    }
}

// Legacy function for callers that can't use the macro yet.
void scope_START(int locationId) {
    ++g_mpr_stack_depth;
    scope_record_hit(locationId, g_mpr_stack_depth);
    --g_mpr_stack_depth;
}

void log_message(const std::string& log) {
    int threadId = static_cast<int>(std::hash<std::thread::id>{}(std::this_thread::get_id()) & 0x7FFFFFFF);
    // Truncate safely to MAX_LOG_BYTES UTF-8 bytes
    std::vector<uint8_t> utf8 = encode_utf8(log);
    if (utf8.size() > MAX_LOG_BYTES) utf8.resize(MAX_LOG_BYTES);
    std::lock_guard<std::mutex> lock(queueMutex);
    logQueue.push(LogRecord{ threadId, utf8 });
    logCount.fetch_add(1, std::memory_order_release);
}

void close_probe() {
    running = false;
}

void mpr_start_sender() {
#ifdef _WIN32
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        std::cerr << "WSAStartup failed." << std::endl;
        std::exit(1);
    }
#endif
    // Initialize ring before producers start enqueuing
    hitRing = std::make_unique<HitSlot[]>(HIT_RING_CAP);
    hitHead.store(0, std::memory_order_relaxed);
    hitTail.store(0, std::memory_order_relaxed);
    running = true;
    g_senderThread = std::thread(senderThreadFunc);
}

void mpr_join_sender() {
    if (g_senderThread.joinable()) g_senderThread.join();
#ifdef _WIN32
    WSACleanup();
#endif
}

// --- Example usage ---
#ifndef MPREWRITER_STANDALONE
#define MPREWRITER_STANDALONE 0
#endif

#if MPREWRITER_STANDALONE
int main() {
    mpr_start_sender();

    // Test: Send hits with RAII-based stack depth
    for (int i = 0; i < 30; ++i) {
        mprewriter_scope_START(100 + i);
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    // Test: Send a log message
    log_message("Hello from C++!");

    // Give it a moment, then close
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    close_probe();
    mpr_join_sender();
    return 0;
}
#endif
