#include "radio_adapter.h"
#include "target_config.h"
#include <RadioLib.h>
#include <SPI.h>
namespace mm::radio {
static LR1121 dev = new Module(mm::board::PIN_NSS,mm::board::PIN_IRQ,mm::board::PIN_RST,mm::board::PIN_BUSY);
int16_t begin(RxCallback cb){
  if(mm::board::PIN_CE>=0){pinMode(mm::board::PIN_CE,OUTPUT);digitalWrite(mm::board::PIN_CE,HIGH);}
  if(mm::board::CUSTOM_SPI_PINS)SPI.begin(mm::board::PIN_SCK,mm::board::PIN_MISO,mm::board::PIN_MOSI,mm::board::PIN_NSS);else SPI.begin();
  int16_t st=dev.begin(mm::target::FREQ_MHZ,500.0f,mm::target::LORA_SF,mm::target::LORA_CR,RADIOLIB_LR11X0_LORA_SYNC_WORD_PRIVATE,mm::target::TX_POWER_DBM,mm::target::LORA_PREAMBLE,0.0f);
  if(st==RADIOLIB_ERR_NONE)st=dev.setRegulatorDCDC();
  if(st==RADIOLIB_ERR_NONE)st=dev.setBandwidth(mm::target::BW_KHZ,true);
  if(st==RADIOLIB_ERR_NONE){
    static const uint32_t rfPins[Module::RFSWITCH_MAX_PINS]={RADIOLIB_LR11X0_DIO5,RADIOLIB_LR11X0_DIO6,RADIOLIB_LR11X0_DIO7,RADIOLIB_LR11X0_DIO8,RADIOLIB_NC};
    static const Module::RfSwitchMode_t rfTable[]={
      {LR11x0::MODE_STBY,{LOW,LOW,LOW,LOW}},
      {LR11x0::MODE_RX,{LOW,LOW,HIGH,LOW}},
      {LR11x0::MODE_TX,{LOW,LOW,LOW,HIGH}},
      {LR11x0::MODE_TX_HP,{LOW,LOW,LOW,HIGH}},
      {LR11x0::MODE_TX_HF,{LOW,HIGH,LOW,LOW}},
      {LR11x0::MODE_GNSS,{LOW,LOW,LOW,LOW}},
      {LR11x0::MODE_WIFI,{HIGH,LOW,LOW,LOW}},
      END_OF_MODE_TABLE,
    };
    dev.setRfSwitchTable(rfPins,rfTable);
  }
  if(st!=RADIOLIB_ERR_NONE)return st;
  dev.setPacketReceivedAction(cb);
  return dev.startReceive();
}
int16_t standby(){return dev.standby();}
int16_t startReceive(){return dev.startReceive();}
void clearRxAction(){dev.clearPacketReceivedAction();}
void setRxAction(RxCallback cb){dev.setPacketReceivedAction(cb);}
int16_t transmit(const uint8_t* data,size_t len){return dev.transmit(data,len);}
size_t packetLength(){return dev.getPacketLength();}
int16_t readData(uint8_t* data,size_t len){return dev.readData(data,len);}
float rssi(){return dev.getRSSI();}
float snr(){return dev.getSNR();}
}
