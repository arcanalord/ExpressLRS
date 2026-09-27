#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>
#ifdef LINK_STATS
#undef LINK_STATS
#endif
namespace mm::uart {
constexpr uint8_t VERSION = 1;
enum FrameType : uint8_t {
  HELLO=0x01, GET_INFO=0x02, GET_CAPS=0x03, GET_STATE=0x04, GET_STATS=0x05, COMPAT_SELFTEST=0x06,
  RADIO_INIT=0x10, SET_PROFILE=0x11, SEND=0x12, CANCEL=0x13, RESET_STATS=0x14, REBOOT=0x15,
  ENTER_OTA=0x16, EXIT_OTA=0x17, READY=0x80, STATE_CHANGED=0x81, RX_PACKET=0x82,
  TX_ACCEPTED=0x83, TX_RESULT=0x84, LINK_STATS=0x85, RADIO_ERROR=0x86, DEVICE_RESET=0x87, RESPONSE=0x90
};
struct Frame { uint8_t version=VERSION; uint8_t type=0; uint16_t sequence=0; std::vector<uint8_t> payload; };
uint16_t crc16Ccitt(const uint8_t* data,size_t len,uint16_t initial=0xFFFF);
std::vector<uint8_t> cobsEncode(const uint8_t* data,size_t len);
bool cobsDecode(const uint8_t* data,size_t len,std::vector<uint8_t>& out,std::string& error);
std::vector<uint8_t> encodeFrame(uint8_t type,uint16_t sequence,const uint8_t* payload,size_t payloadLen);
inline std::vector<uint8_t> encodeFrame(uint8_t type,uint16_t sequence,const std::string& payload){
 return encodeFrame(type,sequence,reinterpret_cast<const uint8_t*>(payload.data()),payload.size());
}
bool decodeFrame(const uint8_t* encoded,size_t encodedLen,Frame& out,std::string& error);
}
