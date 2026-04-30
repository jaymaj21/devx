// Standalone HITTRC01 trace dumper (legacy format with stack-depth digits)
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <cstdlib>
#include <ctime>

static uint64_t be64(const uint8_t* p){
    return (uint64_t(p[0])<<56)|(uint64_t(p[1])<<48)|(uint64_t(p[2])<<40)|(uint64_t(p[3])<<32)|
           (uint64_t(p[4])<<24)|(uint64_t(p[5])<<16)|(uint64_t(p[6])<<8)|uint64_t(p[7]);
}

static uint16_t be16(const uint8_t* p){ return (uint16_t(p[0])<<8) | uint16_t(p[1]); }
static uint32_t be32(const uint8_t* p){ return (uint32_t(p[0])<<24)|(uint32_t(p[1])<<16)|(uint32_t(p[2])<<8)|uint32_t(p[3]); }

static std::string depth_digits(uint32_t depth){
    if (depth==0) return std::string(":<");
    std::string s(":"); s.reserve(depth+2);
    for (uint32_t i=1;i<=depth;i++) s.push_back(char('0' + (i%10)));
    s.push_back('<');
    return s;
}

static bool parse_iso8601_ns(const char* s, uint64_t& out){
    // Accept: YYYY-MM-DDTHH:MM:SS[.fffffffff]Z (UTC)
    std::string str(s);
    if (str.empty()) return false;
    if (str.find('T')==std::string::npos) return false;
    char last = str.back(); if (last!='Z' && last!='z') return false;
    std::string main = str.substr(0, str.size()-1);
    std::string frac;
    size_t dot = main.find('.');
    if (dot != std::string::npos) { frac = main.substr(dot+1); main = main.substr(0, dot); }
    if (main.size() != 19) return false; // YYYY-MM-DDTHH:MM:SS
    std::tm tm{};
    try{
        tm.tm_year = std::stoi(main.substr(0,4)) - 1900;
        tm.tm_mon  = std::stoi(main.substr(5,2)) - 1;
        tm.tm_mday = std::stoi(main.substr(8,2));
        tm.tm_hour = std::stoi(main.substr(11,2));
        tm.tm_min  = std::stoi(main.substr(14,2));
        tm.tm_sec  = std::stoi(main.substr(17,2));
    }catch(...){ return false; }
#ifdef _WIN32
    time_t secs = _mkgmtime(&tm);
#else
    time_t secs = timegm(&tm);
#endif
    if (secs < 0) return false;
    uint64_t ns = uint64_t(secs) * UINT64_C(1000000000);
    if (!frac.empty()){
        if (frac.size() > 9) frac.resize(9);
        while (frac.size() < 9) frac.push_back('0');
        uint64_t f = 0; for (char c: frac){ if (c<'0'||c>'9') return false; f = f*10 + uint64_t(c - '0'); }
        ns += f;
    }
    out = ns; return true;
}

int main(int argc, char** argv){
    if (argc<2){
        std::fprintf(stderr, "Usage: %s <hits.trace> [-start <nanos|RFC3339>] [-end <nanos|RFC3339>] > out.txt\n", argv[0]);
        return 2;
    }
    const char* path = argv[1];
    uint64_t start_ns = 0; // comparison value (file-clock nanos or epoch ns)
    uint64_t end_ns = UINT64_C(0xFFFFFFFFFFFFFFFF);
    bool start_is_epoch = false;
    bool end_is_epoch = false;
    for (int i=2;i+1<argc;i++){
        if (std::strcmp(argv[i],"-start")==0){
            uint64_t tmp; if (parse_iso8601_ns(argv[i+1], tmp)) { start_ns = tmp; start_is_epoch = true; } else { start_ns = std::strtoull(argv[i+1], nullptr, 10); }
            i++;
        }
        else if (std::strcmp(argv[i],"-end")==0){
            uint64_t tmp; if (parse_iso8601_ns(argv[i+1], tmp)) { end_ns = tmp; end_is_epoch = true; } else { end_ns = std::strtoull(argv[i+1], nullptr, 10); }
            i++;
        }
    }
    std::FILE* f = std::fopen(path, "rb");
    if (!f){ std::perror("open"); return 1; }

    // Header: magic(8) "HITTRC01" + endian(1) + startMillis(u64)
    uint8_t header[17];
    if (std::fread(header,1,17,f)!=17){ std::fprintf(stderr,"bad header\n"); return 1; }
    if (std::memcmp(header, "HITTRC01", 8)!=0){ std::fprintf(stderr,"warning: unknown magic\n"); }
    uint64_t start_millis = (uint64_t(header[9])<<56)|(uint64_t(header[10])<<48)|(uint64_t(header[11])<<40)|(uint64_t(header[12])<<32)|
                            (uint64_t(header[13])<<24)|(uint64_t(header[14])<<16)|(uint64_t(header[15])<<8)|uint64_t(header[16]);
    bool use_epoch = start_is_epoch || end_is_epoch;
    uint64_t first_nano = 0; bool have_first=false;

    // Frames: flag:u16, src:u8, nanos:u64, len:u32, data:len
    for (;;){
        uint8_t fhdr[15];
        size_t r = std::fread(fhdr,1,sizeof(fhdr),f);
        if (r==0) break; if (r<sizeof(fhdr)){ std::fprintf(stderr,"truncated frame header\n"); break; }
        uint16_t flag = be16(fhdr);
        uint64_t nanos = be64(fhdr+3);
        uint32_t len = be32(fhdr+11);
        std::string payload(len, '\0');
        if (len>0){ if (std::fread(payload.data(),1,len,f)!=len){ std::fprintf(stderr,"truncated payload\n"); break; } }

        uint64_t cmp = nanos;
        if (use_epoch) {
            if (!have_first){ first_nano = nanos; have_first=true; }
            cmp = start_millis*1000000ULL + (nanos - first_nano);
        }
        if (!(cmp >= start_ns && cmp <= end_ns)) {
            // Allow TS frames (flag==9) to be printed regardless of filter to aid inspection
            if (!(flag==9 && len==8)) { continue; }
        }

        if (flag==9 && len==8) {
            const uint8_t* p = reinterpret_cast<const uint8_t*>(payload.data());
            uint32_t hi = be32(p); uint32_t lo = be32(p+4);
            uint64_t ms = (uint64_t(hi)<<32) | uint64_t(lo);
            std::time_t secs = (std::time_t)(ms/1000);
            std::tm t{};
#if defined(_WIN32)
            gmtime_s(&t, &secs);
#else
            gmtime_r(&secs, &t);
#endif
            char bufdt[64]; std::strftime(bufdt,sizeof(bufdt),"%Y-%m-%dT%H:%M:%SZ", &t);
            std::printf("TS %s\n", bufdt);
            continue;
        }
        if (len<2) continue;
        const uint8_t* p = reinterpret_cast<const uint8_t*>(payload.data());
        uint16_t mt = be16(p);
        if (mt==1 && len>=20){
            uint16_t app = be16(p+2);
            uint32_t inst = be32(p+4);
            uint32_t thr = be32(p+8);
            uint32_t depth = be32(p+12);
            uint32_t loc = be32(p+16);
            auto pref = depth_digits(depth);
            std::printf("%s%u> %u, %u, %u\n", pref.c_str(), loc, app, inst, thr);
        } else if (mt==2 && len>=18){
            uint16_t msglen = be16(p+16);
            size_t take = (size_t)msglen; if (18+take>len) take = len-18;
            std::string msg(payload.data()+18, payload.data()+18+take);
            for (auto& c: msg){ if (c=='\n'||c=='\r'||c=='\t') c=' '; }
            std::printf("LOG %s\n", msg.c_str());
        }
    }
    std::fclose(f);
    return 0;
}
