#pragma once
namespace mm::board {
constexpr int PIN_CE = -1;
constexpr int PIN_IRQ = 1;
constexpr int PIN_BUSY = 3;
constexpr int PIN_MOSI = 4;
constexpr int PIN_MISO = 5;
constexpr int PIN_SCK = 6;
constexpr int PIN_NSS = 7;
constexpr int PIN_RST = 2;
constexpr int PIN_AUX = 3;
constexpr int PIN_LED = 8;
constexpr int PIN_BUTTON = 9;
constexpr int HOST_UART_RX = 20;
constexpr int HOST_UART_TX = 21;
constexpr bool CUSTOM_SPI_PINS = true;
constexpr const char* MCU_FAMILY = "ESP32-C3";
constexpr const char* BOARD_BASE_ID = "dakerfpv_nano_c3";
constexpr const char* OTA_PREFIX = "MeshRadio-DAKER-LR1121";
}
