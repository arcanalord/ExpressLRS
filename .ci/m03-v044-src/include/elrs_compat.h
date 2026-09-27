#pragma once
#include <Arduino.h>
namespace mm::elrs_compat {
extern const char TARGET_NAME[];
extern const char PRIOR_TARGET_NAME[];
extern const unsigned char TARGET_MARKER[];
extern const unsigned char PRIOR_TARGET_MARKER[];
uint16_t markerChecksum();
}
