#include "elrs_compat.h"
namespace mm::elrs_compat {
const char TARGET_NAME[]="Unified_ESP8285_2400_RX";
const char PRIOR_TARGET_NAME[]="HappyModel_EP_2400_RX";
const unsigned char TARGET_MARKER[]="\xBE\xEF\xCA\xFE""Unified_ESP8285_2400_RX";
const unsigned char PRIOR_TARGET_MARKER[]="\xBE\xEF\xCA\xFE""HappyModel_EP_2400_RX";
uint16_t markerChecksum(){uint16_t acc=0x4D4D;for(size_t i=0;i<sizeof(TARGET_MARKER);++i)acc=static_cast<uint16_t>((acc*33u)^TARGET_MARKER[i]);for(size_t i=0;i<sizeof(PRIOR_TARGET_MARKER);++i)acc=static_cast<uint16_t>((acc*33u)^PRIOR_TARGET_MARKER[i]);return acc;}
}
