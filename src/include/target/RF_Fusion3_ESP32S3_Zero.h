#pragma once

// RF Finder Fusion 3 bench target
// ESP32-S3-Zero + external SX1280 module.
// Wiring source of truth: Google Drive "КД — SX1280 2.4 GHz связь".
#define DEVICE_NAME "RF Finder Fusion3 SX1280 Bench"

#define GPIO_PIN_SCK   13
#define GPIO_PIN_MOSI  11
#define GPIO_PIN_MISO  12
#define GPIO_PIN_NSS   10
#define GPIO_PIN_BUSY   9
#define GPIO_PIN_DIO1   8
#define GPIO_PIN_RST    7

// No external RF switch/PA in the first low-power LoRa1280 bench.
#define GPIO_PIN_PA_ENABLE -1
#define GPIO_PIN_TX_ENABLE -1
#define GPIO_PIN_RX_ENABLE -1

// USB CDC is used for the F3 host protocol on node A and diagnostics on T.
#define GPIO_PIN_RCSIGNAL_RX -1
#define GPIO_PIN_RCSIGNAL_TX -1

// Keep the first ranging bench on the SX1280 internal PA only.
#define POWER_OUTPUT_FIXED 0
#define POWER_OUTPUT_DACWRITE 0
#define POWER_OUTPUT_VALUES2 nullptr
#define GPIO_PIN_RFamp_APC1 -1
#define GPIO_PIN_RFamp_APC2 -1
