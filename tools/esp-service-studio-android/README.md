# ESP Service Studio Android build

Isolated Android APK build branch for ESP flashing over USB OTG.

Build base: https://github.com/drakosha/esp-flash-android
Pinned upstream commit: `c4036ace9d2f5526e3535d1ac8bfb8ac3bafc23d`

GitHub Actions builds a debug-signed APK labelled `ESP Service Studio`, verifies the APK signature and ZIP structure, calculates SHA-256, and publishes `ESP_Service_Studio_Pixel7a.apk` as an artifact.

This branch does not modify ExpressLRS master.
