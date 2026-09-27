#pragma once
#include <Arduino.h>
#include "boards/dakerfpv_nano_c3_lr1121.h"

namespace mm::target {
constexpr const char* RADIO_FAMILY="LR1121";
constexpr const char* PROFILE_ID="SX1280_LORA_BALANCED_V1";
constexpr float FREQ_MHZ=2440.0f, BW_KHZ=812.5f, FREQ_MIN_MHZ=2400.0f, FREQ_MAX_MHZ=2480.0f;
constexpr int LORA_SF=8, LORA_CR=7, LORA_PREAMBLE=12;
constexpr int TX_POWER_DBM=10, TX_MIN_DBM=-18, TX_MAX_DBM=13;
constexpr bool RANGING_AVAILABLE=false, USES_BUSY=true, HIGH_POWER_FEM=false;
inline String boardId(){ return String(mm::board::BOARD_BASE_ID)+"_"+String(RADIO_FAMILY); }
}
