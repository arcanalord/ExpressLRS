#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>
namespace mm::mmrp {
constexpr uint8_t VERSION=1;
constexpr size_t MAX_RF_PACKET=240, MAX_CORRELATION_ID=48, MAX_SOURCE_BINDING=32, MAX_RECIPIENT_BINDING=32, MAX_PAYLOAD_TYPE=24, MAX_PAYLOAD=160;
enum PacketType:uint8_t{DATA=1,ACK=2,PING=3,PONG=4};
enum Flags:uint8_t{ACK_REQUESTED=1<<0,ENCRYPTED=1<<1,RELAY_ELIGIBLE=1<<2};
enum QosClass:uint8_t{QOS_CONTROL=1,QOS_TEXT=2,QOS_POSITION=3,QOS_FILE=5,QOS_BACKGROUND=6};
struct Packet{
 PacketType type=DATA; uint8_t flags=0,qos=QOS_TEXT,ttl=1; uint16_t sequence=0; uint8_t fragmentIndex=0,fragmentCount=1;
 std::string correlationId,sourceBinding,recipientBinding,payloadType; std::vector<uint8_t> payload;
};
const char* packetTypeName(PacketType type);
bool packetTypeFromName(const std::string& name,PacketType& out);
bool encode(const Packet& in,std::vector<uint8_t>& out,std::string& error);
bool decode(const uint8_t* data,size_t len,Packet& out,std::string& error);
}
