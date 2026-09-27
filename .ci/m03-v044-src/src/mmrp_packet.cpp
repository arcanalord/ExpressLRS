#include "mmrp_packet.h"
#include "mm_uart.h"
#include <algorithm>
namespace mm::mmrp {
namespace {
constexpr uint8_t MAGIC0='M',MAGIC1='R'; constexpr size_t FIXED_HEADER=17,CRC_BYTES=2;
bool isValidType(uint8_t raw){return raw>=static_cast<uint8_t>(DATA)&&raw<=static_cast<uint8_t>(PONG);}
bool fieldsWithinLimits(const Packet& p,std::string& error){
 if(p.correlationId.empty()||p.sourceBinding.empty()||p.recipientBinding.empty()){error="MMRP_REQUIRED_FIELD";return false;}
 if(p.correlationId.size()>MAX_CORRELATION_ID||p.sourceBinding.size()>MAX_SOURCE_BINDING||p.recipientBinding.size()>MAX_RECIPIENT_BINDING||p.payloadType.size()>MAX_PAYLOAD_TYPE||p.payload.size()>MAX_PAYLOAD){error="MMRP_FIELD_LIMIT";return false;}
 if(p.fragmentCount==0||p.fragmentIndex>=p.fragmentCount){error="MMRP_BAD_FRAGMENT";return false;}
 if(p.type==DATA&&p.payloadType.empty()){error="MMRP_PAYLOAD_TYPE_REQUIRED";return false;}
 return true;
}}
const char* packetTypeName(PacketType type){switch(type){case DATA:return"DATA";case ACK:return"ACK";case PING:return"PING";case PONG:return"PONG";default:return"UNKNOWN";}}
bool packetTypeFromName(const std::string& name,PacketType& out){if(name=="DATA"){out=DATA;return true;}if(name=="ACK"){out=ACK;return true;}if(name=="PING"){out=PING;return true;}if(name=="PONG"){out=PONG;return true;}return false;}
bool encode(const Packet& p,std::vector<uint8_t>& out,std::string& error){
 if(!fieldsWithinLimits(p,error))return false;
 size_t total=FIXED_HEADER+p.correlationId.size()+p.sourceBinding.size()+p.recipientBinding.size()+p.payloadType.size()+p.payload.size()+CRC_BYTES;
 if(total>MAX_RF_PACKET){error="MMRP_PACKET_TOO_LARGE";return false;}
 out.clear();out.reserve(total);out.push_back(MAGIC0);out.push_back(MAGIC1);out.push_back(VERSION);out.push_back(static_cast<uint8_t>(p.type));out.push_back(p.flags);out.push_back(p.qos);out.push_back(p.ttl);out.push_back(p.sequence&0xFF);out.push_back(p.sequence>>8);out.push_back(p.fragmentIndex);out.push_back(p.fragmentCount);out.push_back(p.correlationId.size());out.push_back(p.sourceBinding.size());out.push_back(p.recipientBinding.size());out.push_back(p.payloadType.size());out.push_back(p.payload.size()&0xFF);out.push_back(p.payload.size()>>8);
 auto add=[&](const std::string&s){out.insert(out.end(),s.begin(),s.end());};add(p.correlationId);add(p.sourceBinding);add(p.recipientBinding);add(p.payloadType);out.insert(out.end(),p.payload.begin(),p.payload.end());
 uint16_t crc=mm::uart::crc16Ccitt(out.data(),out.size());out.push_back(crc&0xFF);out.push_back(crc>>8);return true;
}
bool decode(const uint8_t* data,size_t len,Packet& out,std::string& error){
 if(len<FIXED_HEADER+CRC_BYTES||len>MAX_RF_PACKET){error="MMRP_BAD_LENGTH";return false;}
 if(data[0]!=MAGIC0||data[1]!=MAGIC1||data[2]!=VERSION||!isValidType(data[3])){error="MMRP_BAD_HEADER";return false;}
 uint16_t expected=data[len-2]|(static_cast<uint16_t>(data[len-1])<<8),actual=mm::uart::crc16Ccitt(data,len-2);if(expected!=actual){error="MMRP_BAD_CRC";return false;}
 size_t correlationLen=data[11],sourceLen=data[12],recipientLen=data[13],payloadTypeLen=data[14],payloadLen=data[15]|(static_cast<size_t>(data[16])<<8);
 size_t expectedLen=FIXED_HEADER+correlationLen+sourceLen+recipientLen+payloadTypeLen+payloadLen+CRC_BYTES;if(expectedLen!=len){error="MMRP_BAD_FIELDS";return false;}
 Packet p;p.type=static_cast<PacketType>(data[3]);p.flags=data[4];p.qos=data[5];p.ttl=data[6];p.sequence=data[7]|(static_cast<uint16_t>(data[8])<<8);p.fragmentIndex=data[9];p.fragmentCount=data[10];size_t pos=FIXED_HEADER;
 auto take=[&](size_t n){std::string s(reinterpret_cast<const char*>(data+pos),n);pos+=n;return s;};p.correlationId=take(correlationLen);p.sourceBinding=take(sourceLen);p.recipientBinding=take(recipientLen);p.payloadType=take(payloadTypeLen);p.payload.assign(data+pos,data+pos+payloadLen);
 if(!fieldsWithinLimits(p,error))return false;out=std::move(p);return true;
}}
