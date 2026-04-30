#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include <chrono>

inline uint16_t be16(const uint8_t* p) {
    return (uint16_t(p[0]) << 8) | uint16_t(p[1]);
}
inline uint32_t be32(const uint8_t* p) {
    return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | uint32_t(p[3]);
}
inline uint64_t be64(const uint8_t* p) {
    uint64_t r=0;
    for(int i=0;i<8;i++){ r = (r<<8) | p[i]; }
    return r;
}

inline void put_be16(std::vector<uint8_t>& out, uint16_t v){
    out.push_back(uint8_t((v>>8)&0xFF)); out.push_back(uint8_t(v&0xFF));
}
inline void put_be32(std::vector<uint8_t>& out, uint32_t v){
    out.push_back(uint8_t((v>>24)&0xFF));
    out.push_back(uint8_t((v>>16)&0xFF));
    out.push_back(uint8_t((v>>8)&0xFF));
    out.push_back(uint8_t(v&0xFF));
}
inline void put_be64(std::vector<uint8_t>& out, uint64_t v){
    for(int i=7;i>=0;--i) out.push_back(uint8_t((v>>(8*i))&0xFF));
}

inline uint64_t now_nanos(){
    using namespace std::chrono;
    return duration_cast<nanoseconds>(steady_clock::now().time_since_epoch()).count();
}
