#pragma once
#include <cstdint>
#include <cstdio>
#include <cstring>

namespace rf_fusion3 {

static constexpr uint8_t kProtocolVersion = 1;

enum class Role : uint8_t { Unknown=0, Coordinator=1, Anchor=2, Target=3 };
enum class NodeState : uint8_t { Offline=0, Idle=1, Ready=2, Ranging=3, Error=4 };
enum class LosState : uint8_t { Unknown=0, Los=1, Nlos=2 };

struct RangeResult {
    const char* session_id = "-";
    uint32_t sequence = 0;
    const char* from = "-";
    const char* to = "-";
    const char* target_id = "-";
    uint32_t timestamp_ms = 0;
    int32_t raw_mm = 0;
    int32_t calibrated_mm = 0;
    uint32_t sigma_mm = 1500;
    uint16_t quality_milli = 1000;
    int16_t rssi_dbm = -127;
    int8_t tx_power_dbm = 0;
    LosState los = LosState::Unknown;
    const char* calibration_id = "-";
    const char* flags = "";
};

struct HostCommand {
    enum class Type : uint8_t { Invalid=0, Hello, Session, Range, Cal, Stop } type = Type::Invalid;
    char session_id[33] = {};
    char target_id[33] = {};
    char from[9] = {};
    char to[9] = {};
    char device_id[33] = {};
    char calibration_id[65] = {};
    uint16_t count = 1;
};

inline const char* losText(LosState s) {
    switch (s) {
        case LosState::Los: return "LOS";
        case LosState::Nlos: return "NLOS";
        default: return "UNKNOWN";
    }
}

inline bool safeToken(const char* s, size_t max_len) {
    if (!s || !*s) return false;
    size_t n = 0;
    for (; s[n]; ++n) {
        if (n >= max_len) return false;
        const unsigned char c = static_cast<unsigned char>(s[n]);
        const bool ok = (c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.'||c==':';
        if (!ok) return false;
    }
    return n > 0;
}

inline int formatRange(char* out, size_t cap, const RangeResult& r) {
    if (!out || cap < 32) return -1;
    if (!safeToken(r.from,8) || !safeToken(r.to,8) || !safeToken(r.target_id,32)) return -2;
    return std::snprintf(out, cap,
        "F3,RANGE,%s,%lu,%s,%s,%s,%lu,%ld,%ld,%lu,%u,%d,%d,%s,%s,%s",
        r.session_id ? r.session_id : "-",
        static_cast<unsigned long>(r.sequence),
        r.from,r.to,r.target_id,
        static_cast<unsigned long>(r.timestamp_ms),
        static_cast<long>(r.raw_mm),
        static_cast<long>(r.calibrated_mm),
        static_cast<unsigned long>(r.sigma_mm),
        static_cast<unsigned>(r.quality_milli),
        static_cast<int>(r.rssi_dbm),
        static_cast<int>(r.tx_power_dbm),
        losText(r.los),
        r.calibration_id ? r.calibration_id : "-",
        r.flags ? r.flags : "");
}

inline int formatHello(char* out,size_t cap,const char* device_id,const char* role,const char* fw,const char* session_id,const char* caps) {
    if (!safeToken(device_id,32)) return -1;
    return std::snprintf(out,cap,"F3,HELLO,%u,%s,%s,%s,%s,%s",
        static_cast<unsigned>(kProtocolVersion),device_id,role?role:"UNKNOWN",fw?fw:"0",session_id?session_id:"-",caps?caps:"");
}

inline bool copyField(char* dst,size_t cap,const char* src) {
    if (!dst || !cap || !src) return false;
    const size_t n=std::strlen(src); if(n>=cap) return false;
    std::memcpy(dst,src,n+1); return true;
}

inline HostCommand parseHostCommand(const char* line) {
    HostCommand c;
    if (!line || std::strncmp(line,"F3,C,",5)!=0) return c;
    char buf[256]; const size_t len=std::strlen(line); if(len>=sizeof(buf))return c;
    std::memcpy(buf,line,len+1);
    char* fields[8] = {}; size_t count=0;
    char* p=buf;
    while(p && count<8){fields[count++]=p;char* q=std::strchr(p,',');if(!q)break;*q='\0';p=q+1;}
    if(count<3)return c;
    const char* cmd=fields[2];
    if(std::strcmp(cmd,"HELLO")==0){c.type=HostCommand::Type::Hello;return c;}
    if(std::strcmp(cmd,"STOP")==0){c.type=HostCommand::Type::Stop;return c;}
    if(std::strcmp(cmd,"SESSION")==0 && count>=5){
        if(!copyField(c.session_id,sizeof(c.session_id),fields[3])||!copyField(c.target_id,sizeof(c.target_id),fields[4]))return HostCommand{};
        c.type=HostCommand::Type::Session;return c;
    }
    if(std::strcmp(cmd,"RANGE")==0 && count>=6){
        if(!copyField(c.from,sizeof(c.from),fields[3])||!copyField(c.to,sizeof(c.to),fields[4]))return HostCommand{};
        long n=std::strtol(fields[5],nullptr,10); if(n<1)n=1;if(n>100)n=100;c.count=static_cast<uint16_t>(n);
        c.type=HostCommand::Type::Range;return c;
    }
    if(std::strcmp(cmd,"CAL")==0 && count>=5){
        if(!copyField(c.device_id,sizeof(c.device_id),fields[3])||!copyField(c.calibration_id,sizeof(c.calibration_id),fields[4]))return HostCommand{};
        c.type=HostCommand::Type::Cal;return c;
    }
    return c;
}

} // namespace rf_fusion3
