# EP2 LINK v0.2.0 — verified build report

Date: 2026-09-22
Gate: EP2_BUILD_PASS = PASS

## Toolchain
- PlatformIO / Espressif 8266 platform 4.2.1
- Generic ESP8285 Module, 1 MB flash
- Arduino ESP8266 core 3.1.2
- xtensa-lx106 GCC 10.3.0
- RadioLib 7.7.1

## Tests
- protocol self-test: PASS
- source invariant self-test: PASS
- real ESP8285 compile: PASS
- embedded target marker verification: PASS

## Resources
- RAM: 30,520 / 81,920 bytes (37.3%)
- flash: 329,695 / 958,448 bytes (34.4%)

## Raw firmware
- EP2_LINK_v0.2.0_ESP8285.bin
- size: 333,840 bytes
- SHA256: 37d4ebb2934853b7682a14a5454182e54f52cd2d3dfb9bd55e5f281bbcb0795b

## Gzip
- EP2_LINK_v0.2.0_ESP8285.bin.gz
- size: 241,345 bytes
- SHA256: f87ba2caf7da9a60963e2b9966543a0b2f2b895b7a373a1379a3aaa8165aa91c

## Target marker
Raw binary contains:
BE EF CA FE + UNIFIED_ESP8285_2400_RX + NUL

Observed marker offset: 333207.

Prefer raw .bin for the first transition from stock ExpressLRS so the stock updater actually scans and validates the embedded target name. Current ESP8266 ELRS updater treats gzip input beginning with 0x1F as target-approved before normal marker scanning, so .bin.gz is not the preferred first-flash safety path.

## Corrections found by review/CI
1. Fixed SX1280::begin() argument order: syncWord, outputPower and preamble are now passed to the correct slots.
2. RadioLib 7.7.1 transmit(String&) requires mutable String; CI caught and fixed the const mismatch.
3. Updated deprecated ICACHE_RAM_ATTR to IRAM_ATTR.
4. Added bounded retries (2), duplicate suppression, one-pending-packet protection, and separate radio diagnostics.
5. Own Wi-Fi OTA validates the EP2 target marker before finalizing an image.

## Meaning of PASS
Build PASS does not mean hardware PASS. Still required:
EP2_RECOVERY_READY -> EP2_FW_BOOT_PASS -> EP2_OWN_OTA_PASS -> EP2_NODE_ID_PASS -> EP2_PING_PONG_PASS.
