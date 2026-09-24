# ESP Service Studio Android build

Isolated Android APK build branch for ESP flashing over USB OTG.

Build base: https://github.com/drakosha/esp-flash-android
Pinned upstream commit: `c4036ace9d2f5526e3535d1ac8bfb8ac3bafc23d`

GitHub Actions builds a debug-signed APK labelled `ESP Service Studio`, verifies the APK signature and ZIP structure, calculates SHA-256, and publishes `ESP_Service_Studio_Pixel7a.apk` as an artifact.

This branch does not modify ExpressLRS master.

## v0.3

Fixes direct ROM flashing used by one-button/manual BOOT mode: v0.2 disabled the flasher stub but accidentally kept the stub's 16 KiB flash block size. v0.3 switches ROM flashing to the chip's ROM block size (normally 1 KiB) and does not send stub-only FLASH_END after a normal ROM write.
