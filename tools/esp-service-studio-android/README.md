# ESP Service Studio Android build

Isolated Android APK build branch for ESP flashing over USB OTG.

Build base: https://github.com/drakosha/esp-flash-android
Pinned upstream commit: `c4036ace9d2f5526e3535d1ac8bfb8ac3bafc23d`

GitHub Actions builds a debug-signed APK labelled `ESP Service Studio`, verifies the APK signature and ZIP structure, calculates SHA-256, and publishes `ESP_Service_Studio_Pixel7a.apk` as an artifact.

This branch does not modify ExpressLRS master.

## v0.3

Fixes direct ROM flashing used by one-button/manual BOOT mode: v0.2 disabled the flasher stub but accidentally kept the stub's 16 KiB flash block size. v0.3 switches ROM flashing to the chip's ROM block size (normally 1 KiB) and does not send stub-only FLASH_END after a normal ROM write.

## v0.4

Adds a non-destructive **Check device** flow (USB -> ROM sync -> chip -> flash ID/size), an explicit ESP8266/ESP8285 single-image preset, and overlap preflight for multi-part images before any write starts. The raw log remains available for engineering diagnostics, while the main flow gets a clearer health check before flashing.

The Google Drive build folder was reviewed for reusable inputs. The PlatformIO/ESP8266/toolchain archives are useful for separate firmware builds and recovery work, not for embedding into the Android flasher. Android SDK/Gradle archives are build-environment assets and remain outside the APK runtime.

## v0.5

- upgrades `esptool-js` from 0.6.1 to 0.7.0;
- upgrades `usb-serial-for-android` from 3.7.3 to 3.11.0;
- adds stage diagnostics such as `USB_OK`, `ROM_SYNC_OK`, `ROM_SYNC_TIMEOUT`, `FLASH_ID_FAIL`, `PREFLIGHT_FAIL`, `WRITE_TIMEOUT`, `WRITE_OK`;
- propagates native Android serial read/write failures into the JavaScript/esptool layer instead of silently waiting for a generic timeout;
- keeps the v0.3 ROM-mode 0x400 block fix and v0.4 non-destructive device probe.

The v0.5 dependency changes are isolated in one release so hardware behavior can be compared directly against v0.4.

## v0.6

- detects the ESP family after ROM sync and automatically selects the matching layout preset when doing so cannot overwrite picked files or a custom layout;
- preserves an existing layout/file selection and emits `PRESET_SUGGEST` instead of silently replacing it;
- normalizes the detected physical flash size and checks every image end address before the first write;
- aborts preflight with `IMAGE_OUT_OF_FLASH` / `PREFLIGHT_FAIL` if a selected binary would extend beyond the detected flash;
- emits `FLASH_BOUNDS_OK` when the full image set fits, and `FLASH_BOUNDS_UNKNOWN` when the chip does not report a usable size.
- keeps `usb-serial-for-android 3.11.0`, but excludes its `androidx.annotation 1.10.0` transitive dependency and pins `androidx.annotation 1.8.2` so the pinned Kotlin 1.9.22 / AGP 8.2.2 toolchain can compile the APK.
- forces `kotlin-stdlib`, `kotlin-stdlib-jdk7`, and `kotlin-stdlib-jdk8` to 1.9.22 across configurations; CI prints `dependencyInsight` for Kotlin and AndroidX annotation before assembling so future transitive version drift is visible.

- preset auto-selection uses the ROM target's `BOOTLOADER_FLASH_OFFSET`: `0x0` selects the S3/C2/C3/C6/H2/C61 layout, `0x1000` selects ESP32/ESP32-S2, ESP8266/8285 remains single-image; other offsets are reported but never auto-selected.

Hardware validation remains required on Pixel 7a with CH340/CH341 and native USB ESP32-C3/S3 before marking PHONE_PASS.
