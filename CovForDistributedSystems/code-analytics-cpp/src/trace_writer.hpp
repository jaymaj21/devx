#pragma once
#include <string>
#include <vector>
#include <mutex>
#include <fstream>
#include <cstdint>
#include <chrono>
#include "util.hpp"

class TraceWriter {
public:
    // Align with Java/Rust: 0=UDP, 1=TCP, 2=INTERNAL
    enum Src : uint8_t { UDP=0, TCP=1, INTERNAL=2 };

    bool open(const std::string& path){
        std::lock_guard<std::mutex> lk(mtx_);
        if (ofs_.is_open()) ofs_.close();
        path_ = path;
        ofs_.open(path, std::ios::binary);
        if(!ofs_) return false;
        // HITTRC01 header: magic(8) + endian(1, 0=big) + fileStartEpochMillis(8)
        ofs_.write("HITTRC01", 8);
        uint8_t endian = 0;
        ofs_.put(char(endian));
        uint64_t ms = now_millis();
        uint8_t bms[8]; for (int i=7;i>=0;--i) { bms[7-i] = uint8_t((ms >> (i*8)) & 0xFF); }
        ofs_.write(reinterpret_cast<char*>(bms), 8);
        return true;
    }
    void close(){
        std::lock_guard<std::mutex> lk(mtx_);
        if (ofs_.is_open()) ofs_.close();
    }

    // Write a single frame with flag (u16), source (u8), nanos (u64), len (u32), payload
    void writeFrame(uint16_t flag, Src src, const std::vector<uint8_t>& payload){
        std::lock_guard<std::mutex> lk(mtx_);
        if (!ofs_.is_open()) return;
        uint64_t tns = now_nanos();
        uint32_t len = (uint32_t)payload.size();
        // Build header
        uint8_t hdr[2+1+8+4];
        hdr[0] = uint8_t((flag>>8)&0xFF); hdr[1] = uint8_t(flag & 0xFF);
        hdr[2] = uint8_t(src);
        for (int i=0;i<8;i++){ hdr[3+i] = uint8_t((tns >> (56 - 8*i)) & 0xFF); }
        hdr[11] = uint8_t((len>>24)&0xFF); hdr[12] = uint8_t((len>>16)&0xFF);
        hdr[13] = uint8_t((len>>8)&0xFF); hdr[14] = uint8_t(len & 0xFF);
        ofs_.write(reinterpret_cast<const char*>(hdr), sizeof(hdr));
        if (len) ofs_.write(reinterpret_cast<const char*>(payload.data()), len);
        ofs_.flush();
    }

    void flush(){
        std::lock_guard<std::mutex> lk(mtx_);
        if (ofs_.is_open()) ofs_.flush();
    }

    void persist(){
        std::lock_guard<std::mutex> lk(mtx_);
        if (!ofs_.is_open()) return;
        ofs_.flush();
#ifdef _WIN32
        HANDLE h = CreateFileA(path_.c_str(), GENERIC_WRITE, FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
                               NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h != INVALID_HANDLE_VALUE) {
            FlushFileBuffers(h);
            CloseHandle(h);
        }
#else
        int fd = ::open(path_.c_str(), O_WRONLY);
        if (fd >= 0) { ::fsync(fd); ::close(fd); }
#endif
    }

private:
    std::mutex mtx_;
    std::ofstream ofs_;
    std::string path_;
};
