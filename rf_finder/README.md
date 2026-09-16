# FPV Club RF Finder 2.4 — v0.3.0

Custom RX-only RF/RSSI finder for an ELRS Nano RX class board (ESP8285 + SX1280/SX1281, Generic 2400 PA layout) and Android.

This branch is intentionally standalone from the normal ExpressLRS firmware build. It uses the ExpressLRS fork only as the convenient GitHub build host and hardware-reference home.

## Hardware profile

Generic 2400 PA pin map:

- BUSY 5
- DIO1 4
- MISO 12
- MOSI 13
- NSS 15
- RESET 2
- SCK 14
- RXEN 9
- TXEN 10
- UART RX 3
- UART TX 1

## Safety invariant

The firmware is RX-only: it has no SX128x TX command and never drives TXEN high. ESP8285 Wi-Fi is disabled while measuring.

## Build

GitHub Actions workflow `.github/workflows/rf-finder-build.yml` builds:

- `RF_Finder_Nano_RX_v0.3.0.bin`
- `RF_Finder_Android_v0.3.0-debug.apk`

The complete source bundle is stored as `rf_finder/RF_Finder_v0.3.0_source.zip.b64`; the workflow decodes it before building.
