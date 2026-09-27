#pragma once
#include <Arduino.h>
#include <cstddef>
#include <cstdint>
namespace mm::radio {
using RxCallback = void (*)();
int16_t begin(RxCallback cb);
int16_t standby();
int16_t startReceive();
void clearRxAction();
void setRxAction(RxCallback cb);
int16_t transmit(const uint8_t* data, size_t len);
size_t packetLength();
int16_t readData(uint8_t* data, size_t len);
float rssi();
float snr();
}
