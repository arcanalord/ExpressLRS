#include <Arduino.h>
#include <ArduinoJson.h>
#include <RadioLib.h>
#include <vector>
#include <string>
#include "target_config.h"
#include "radio_adapter.h"
#include "ota_portal.h"
#include "mm_uart.h"
#include "mmrp_packet.h"
using namespace mm;

static volatile bool radioRxFlag=false;
static bool radioReady=false;
static String bootId,nodeId;
static uint16_t rfSequence=1;
static uint32_t statTx=0,statRx=0,statRetries=0,statErrors=0,statDropped=0;
static float lastRssi=0,lastSnr=0;
static std::vector<uint8_t> serialFrame;
static void IRAM_ATTR onRadioRx(){radioRxFlag=true;}

static String toHex(uint32_t v){char b[12];snprintf(b,sizeof(b),"%08lx",static_cast<unsigned long>(v));return String(b);}
static String jsonString(const JsonDocument& d){String out;serializeJson(d,out);return out;}
static void writeFrame(uint8_t type,uint16_t seq,const String& json){auto bytes=uart::encodeFrame(type,seq,reinterpret_cast<const uint8_t*>(json.c_str()),json.length());if(!bytes.empty())Serial.write(bytes.data(),bytes.size());}
static void respond(uint16_t seq,bool ok,JsonVariantConst data,const char* error=nullptr){JsonDocument d;d["ok"]=ok;if(ok)d["data"].set(data);else d["data"]=nullptr;d["error"]=error?error:nullptr;writeFrame(uart::RESPONSE,seq,jsonString(d));}
static void respondObject(uint16_t seq,JsonDocument& d){respond(seq,true,d.as<JsonVariantConst>());}
static void respondError(uint16_t seq,const char* e){JsonDocument n;respond(seq,false,n.as<JsonVariantConst>(),e);}
static void emitSimple(uint8_t t,JsonDocument& d){writeFrame(t,0,jsonString(d));}

static int16_t initRadio(){int16_t st=radio::begin(onRadioRx);radioReady=(st==RADIOLIB_ERR_NONE);if(!radioReady)statErrors++;return st;}
static void emitRadioError(const String& code,int16_t st){JsonDocument d;d["error"]=code;d["radioStatus"]=st;emitSimple(uart::RADIO_ERROR,d);}
static uint16_t nextRfSequence(){uint16_t value=rfSequence++;if(rfSequence==0)rfSequence=1;return value;}
static uint8_t defaultQos(const String& payloadType,mmrp::PacketType type){if(type==mmrp::PING||type==mmrp::PONG||type==mmrp::ACK)return mmrp::QOS_CONTROL;if(payloadType=="map_point"||payloadType=="position")return mmrp::QOS_POSITION;return mmrp::QOS_TEXT;}

static bool buildRfPacket(JsonVariantConst in,mmrp::Packet& p,std::string& error){
 String packetType=(const char*)(in["packetType"]|"DATA");mmrp::PacketType type;
 if(!mmrp::packetTypeFromName(packetType.c_str(),type)){error="UNSUPPORTED_PACKET_TYPE";return false;}
 String correlationId=(const char*)(in["messageId"]|in["correlationId"]|"");
 String recipient=(const char*)(in["recipientBinding"]|"");
 String payloadType=(const char*)(in["payloadType"]|"json");
 if(!correlationId.length()||!recipient.length()){error="BAD_SEND";return false;}
 if(type==mmrp::DATA&&in["payload"].isNull()){error="BAD_SEND";return false;}
 String payloadJson;if(!in["payload"].isNull())serializeJson(in["payload"],payloadJson);
 p.type=type;p.flags=in["flags"].is<uint8_t>()?in["flags"].as<uint8_t>():(type==mmrp::DATA?mmrp::ACK_REQUESTED:0);
 p.qos=in["qos"].is<uint8_t>()?in["qos"].as<uint8_t>():defaultQos(payloadType,type);
 p.ttl=in["ttl"].is<uint8_t>()?in["ttl"].as<uint8_t>():1;p.sequence=nextRfSequence();p.fragmentIndex=0;p.fragmentCount=1;
 p.correlationId=correlationId.c_str();p.sourceBinding=nodeId.c_str();p.recipientBinding=recipient.c_str();p.payloadType=payloadType.c_str();p.payload.assign(payloadJson.begin(),payloadJson.end());return true;
}
static int16_t transmitBytes(const uint8_t* data,size_t len){radio::clearRxAction();int16_t st=radio::transmit(data,len);if(st==RADIOLIB_ERR_NONE)statTx++;else statErrors++;radio::setRxAction(onRadioRx);int16_t rs=radio::startReceive();if(rs!=RADIOLIB_ERR_NONE){radioReady=false;statErrors++;emitRadioError("RX_RESTART_FAILED",rs);}return st;}
static bool sendPongFor(const mmrp::Packet& ping){mmrp::Packet pong;pong.type=mmrp::PONG;pong.qos=mmrp::QOS_CONTROL;pong.ttl=1;pong.sequence=nextRfSequence();pong.correlationId=ping.correlationId;pong.sourceBinding=nodeId.c_str();pong.recipientBinding=ping.sourceBinding;pong.payloadType="diag.pong";std::vector<uint8_t> bytes;std::string error;if(!mmrp::encode(pong,bytes,error)){statErrors++;return false;}return transmitBytes(bytes.data(),bytes.size())==RADIOLIB_ERR_NONE;}
static bool isForThisNode(const mmrp::Packet& p){return p.recipientBinding==nodeId.c_str()||p.recipientBinding=="*";}

static void emitRxPacket(const mmrp::Packet& p){
 JsonDocument e;e["networkProtocol"]="MMRP/1";e["packetType"]=mmrp::packetTypeName(p.type);e["messageId"]=p.correlationId;e["correlationId"]=p.correlationId;e["sourceBinding"]=p.sourceBinding;e["recipientBinding"]=p.recipientBinding;e["payloadType"]=p.payloadType;e["flags"]=p.flags;e["qos"]=p.qos;e["ttl"]=p.ttl;e["fragmentIndex"]=p.fragmentIndex;e["fragmentCount"]=p.fragmentCount;
 if(!p.payload.empty()){JsonDocument pd;auto err=deserializeJson(pd,p.payload.data(),p.payload.size());if(!err)e["payload"].set(pd.as<JsonVariantConst>());else{String text;text.reserve(p.payload.size());for(uint8_t b:p.payload)text+=static_cast<char>(b);e["payloadText"]=text;}}else e["payload"]=nullptr;
 e["rssi"]=lastRssi;e["snr"]=lastSnr;e["profileId"]=target::PROFILE_ID;emitSimple(uart::RX_PACKET,e);
}
static void handleRadioRx(){
 if(!radioRxFlag)return;radioRxFlag=false;size_t len=radio::packetLength();if(len==0||len>mmrp::MAX_RF_PACKET){statErrors++;radio::startReceive();return;}
 std::vector<uint8_t> bytes(len);int16_t st=radio::readData(bytes.data(),bytes.size());if(st!=RADIOLIB_ERR_NONE){statErrors++;radio::startReceive();return;}
 lastRssi=radio::rssi();lastSnr=radio::snr();mmrp::Packet p;std::string error;if(!mmrp::decode(bytes.data(),bytes.size(),p,error)){statErrors++;radio::startReceive();return;}
 if(!isForThisNode(p)){statDropped++;radio::startReceive();return;}statRx++;emitRxPacket(p);if(p.type==mmrp::PING){sendPongFor(p);return;}radio::startReceive();
}

static void handleCommand(const uart::Frame& f){
 JsonDocument in;if(!f.payload.empty()){auto er=deserializeJson(in,f.payload.data(),f.payload.size());if(er){respondError(f.sequence,"BAD_JSON_PAYLOAD");return;}}
 switch(f.type){
 case uart::HELLO:{JsonDocument d;d["protocol"]=1;d["hostProtocol"]="MM-UART/1";d["networkProtocol"]="MMRP/1";d["bootId"]=bootId;respondObject(f.sequence,d);break;}
 case uart::GET_INFO:{JsonDocument d;d["protocolVersion"]=1;d["hostProtocol"]="MM-UART/1";d["networkProtocol"]="MMRP/1";d["firmwareFamily"]="mesh-radio-multi";d["firmwareVersion"]=MM_FW_VERSION;d["boardId"]=target::boardId();d["mcuFamily"]=board::MCU_FAMILY;d["radioFamily"]=target::RADIO_FAMILY;d["buildHash"]="framework-v0.4.4-dev";respondObject(f.sequence,d);break;}
 case uart::GET_CAPS:{JsonDocument d;d["radioFamily"]=target::RADIO_FAMILY;auto fr=d["frequencyRanges"].to<JsonArray>();auto one=fr.add<JsonArray>();one.add(target::FREQ_MIN_MHZ);one.add(target::FREQ_MAX_MHZ);auto pr=d["profileIds"].to<JsonArray>();pr.add(target::PROFILE_ID);d["maxPayload"]=mmrp::MAX_PAYLOAD;d["maxRfPacket"]=mmrp::MAX_RF_PACKET;d["rssiAvailable"]=true;d["snrAvailable"]=true;d["rangingAvailable"]=false;d["compatSelfTestAvailable"]=true;auto np=d["networkProtocols"].to<JsonArray>();np.add("MMRP/1");auto tx=d["txPowerRange"].to<JsonArray>();tx.add(target::TX_MIN_DBM);tx.add(target::TX_MAX_DBM);respondObject(f.sequence,d);break;}
 case uart::GET_STATE:{JsonDocument d;d["ready"]=radioReady;d["state"]=radioReady?"ready":"connected";d["profileId"]=target::PROFILE_ID;d["networkProtocol"]="MMRP/1";d["nodeBinding"]=nodeId;d["ota"]=ota::active();respondObject(f.sequence,d);break;}
 case uart::GET_STATS:{JsonDocument d;d["tx"]=statTx;d["rx"]=statRx;d["retries"]=statRetries;d["errors"]=statErrors;d["dropped"]=statDropped;d["rssi"]=lastRssi;d["snr"]=lastSnr;respondObject(f.sequence,d);break;}
 case uart::COMPAT_SELFTEST:{mmrp::Packet probe;probe.type=mmrp::DATA;probe.flags=mmrp::ACK_REQUESTED;probe.qos=mmrp::QOS_CONTROL;probe.ttl=1;probe.sequence=1;probe.correlationId="compat-selftest";probe.sourceBinding=nodeId.c_str();probe.recipientBinding=nodeId.c_str();probe.payloadType="diag.selftest";const char payload[]="{\"ok\":true}";probe.payload.assign(payload,payload+sizeof(payload)-1);std::vector<uint8_t> encoded;std::string err;bool eok=mmrp::encode(probe,encoded,err);mmrp::Packet decoded;bool rt=eok&&mmrp::decode(encoded.data(),encoded.size(),decoded,err)&&decoded.correlationId==probe.correlationId;bool crc=false;if(eok&&!encoded.empty()){auto bad=encoded;bad.back()^=1;mmrp::Packet x;std::string er;crc=!mmrp::decode(bad.data(),bad.size(),x,er);}JsonDocument d;d["hostProtocol"]="MM-UART/1";d["networkProtocol"]="MMRP/1";d["boardId"]=target::boardId();d["radioFamily"]=target::RADIO_FAMILY;d["profileId"]=target::PROFILE_ID;d["radioReady"]=radioReady;d["codecRoundTrip"]=rt;d["crcReject"]=crc;d["result"]=(rt&&crc)?"PASS":"FAIL";respondObject(f.sequence,d);break;}
 case uart::RADIO_INIT:{int16_t st=initRadio();if(st==RADIOLIB_ERR_NONE){JsonDocument d;d["ready"]=true;d["profileId"]=target::PROFILE_ID;respondObject(f.sequence,d);JsonDocument e;e["profileId"]=target::PROFILE_ID;emitSimple(uart::READY,e);}else{respondError(f.sequence,"RADIO_INIT_FAILED");emitRadioError("RADIO_INIT_FAILED",st);}break;}
 case uart::SET_PROFILE:{const char* id=in["profileId"]|"";if(String(id)!=target::PROFILE_ID){respondError(f.sequence,"UNSUPPORTED_PROFILE");break;}JsonDocument d;d["profileId"]=target::PROFILE_ID;respondObject(f.sequence,d);break;}
 case uart::SEND:{if(!radioReady){respondError(f.sequence,"RADIO_NOT_READY");break;}mmrp::Packet packet;std::string err;if(!buildRfPacket(in.as<JsonVariantConst>(),packet,err)){respondError(f.sequence,err.c_str());break;}std::vector<uint8_t> bytes;if(!mmrp::encode(packet,bytes,err)){respondError(f.sequence,err.c_str());break;}JsonDocument accepted;accepted["messageId"]=packet.correlationId;accepted["packetType"]=mmrp::packetTypeName(packet.type);emitSimple(uart::TX_ACCEPTED,accepted);int16_t st=transmitBytes(bytes.data(),bytes.size());JsonDocument rr;rr["messageId"]=packet.correlationId;rr["ok"]=st==RADIOLIB_ERR_NONE;rr["radioStatus"]=st;emitSimple(uart::TX_RESULT,rr);if(st==RADIOLIB_ERR_NONE){JsonDocument d;d["accepted"]=true;d["messageId"]=packet.correlationId;respondObject(f.sequence,d);}else respondError(f.sequence,"RADIO_TX_FAILED");break;}
 case uart::RESET_STATS:{statTx=statRx=statRetries=statErrors=statDropped=0;lastRssi=lastSnr=0;JsonDocument d;d["reset"]=true;respondObject(f.sequence,d);break;}
 case uart::ENTER_OTA:{radio::clearRxAction();radio::standby();radioReady=false;ota::start();JsonDocument d;d["ota"]=true;d["ssid"]=ota::ssid();d["url"]="http://192.168.4.1/";d["user"]="mesh";respondObject(f.sequence,d);break;}
 case uart::EXIT_OTA:{ota::stop();int16_t st=initRadio();JsonDocument d;d["ota"]=false;d["ready"]=st==RADIOLIB_ERR_NONE;respondObject(f.sequence,d);break;}
 case uart::REBOOT:{JsonDocument d;d["rebooting"]=true;respondObject(f.sequence,d);Serial.flush();delay(50);ESP.restart();break;}
 default:respondError(f.sequence,"UNSUPPORTED_COMMAND");break;
 }}
static void handleSerial(){while(Serial.available()){uint8_t b=static_cast<uint8_t>(Serial.read());if(b==0){if(serialFrame.empty())continue;uart::Frame f;std::string err;if(uart::decodeFrame(serialFrame.data(),serialFrame.size(),f,err))handleCommand(f);else{statErrors++;JsonDocument e;e["error"]=err;emitSimple(uart::RADIO_ERROR,e);}serialFrame.clear();}else{if(serialFrame.size()<2048)serialFrame.push_back(b);else{serialFrame.clear();statErrors++;}}}}
static String makeNodeId(){uint64_t mac=ESP.getEfuseMac();return String("node-")+toHex(static_cast<uint32_t>(mac));}
static String makeBootId(){return String("boot-")+toHex(static_cast<uint32_t>(esp_random()));}
void setup(){Serial.begin(115200);delay(30);nodeId=makeNodeId();bootId=makeBootId();ota::begin(nodeId);if(board::PIN_LED>=0){pinMode(board::PIN_LED,OUTPUT);digitalWrite(board::PIN_LED,HIGH);}if(board::PIN_BUTTON>=0)pinMode(board::PIN_BUTTON,INPUT_PULLUP);int16_t st=initRadio();if(st!=RADIOLIB_ERR_NONE)emitRadioError("RADIO_INIT_FAILED",st);if(board::PIN_LED>=0)digitalWrite(board::PIN_LED,radioReady?LOW:HIGH);}
void loop(){static uint32_t buttonSince=0;handleSerial();if(!ota::active())handleRadioRx();ota::loop();if(board::PIN_BUTTON>=0){if(digitalRead(board::PIN_BUTTON)==LOW){if(!buttonSince)buttonSince=millis();if(!ota::active()&&millis()-buttonSince>2000){radio::clearRxAction();radio::standby();radioReady=false;ota::start();}}else buttonSince=0;}delay(1);}
