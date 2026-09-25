# ESP Service Studio Universal — Architecture v2

Date: 2026-09-25
Status: CURRENT WORKING TARGET

## 1. Product rule
One operator-facing app, but two clearly separated workflows.

### Normal ELRS workflow
Connect -> detect MCU -> choose/confirm receiver model -> choose firmware options -> prepare -> flash controller -> boot check.

The operator does not choose SX1280/SX1276/SX1262 and does not choose a radio chip as a flash destination.
For normal ESP-based ELRS receivers, the firmware image is written to the ESP controller.
The selected official target describes the radio/layout/overlay internally.

### Advanced radio service
A separate section for:
- SPI probe;
- register diagnostics;
- RSSI/SNR;
- RX/TX tests;
- ranging where supported;
- radio reset/busy/dio checks;
- radio microcode only where the radio family explicitly supports it.

Advanced radio service must not complicate the normal ELRS workflow.

## 2. Official ELRS data
Do not hardcode common receiver models one by one.

The app loads the official ExpressLRS firmware bundle for one exact release commit.
From the same bundle it reads:
- hardware/targets.json;
- target layout files;
- target overlays;
- cached firmware binaries.

Firmware + target + layout must always come from the same pinned bundle/commit.
Never combine stable firmware with hardware data from Targets/master.

## 3. ELRS target filtering
After ROM detection:
- filter by detected MCU/platform;
- show RX targets only in the normal receiver workflow;
- respect min_version;
- respect upload_methods;
- use target firmware family/layout/overlay as data.

For an empty ESP8285 receiver, the exact physical model cannot be proven from ROM ID alone, so the user selects it from the filtered official list.

For an already-running receiver, later add CRSF Device Info / Unified metadata detection to reduce manual selection.

## 4. Regulatory profiles
Regulatory choices depend on target band.

2.4 GHz:
- normal ISM/FCC build;
- EU CE / LBT build.

900 MHz:
- FCC 915;
- AU 915;
- EU 868;
- IN 866.

433 MHz:
- US 433;
- US 433 wide;
- EU 433;
- AU 433.

Do not show FCC/LBT as a universal choice for every band.

## 5. Target-specific firmware options
Normal UI may expose only options supported by the selected target:
- binding phrase;
- Wi-Fi SSID/password when Wi-Fi is supported;
- auto Wi-Fi interval;
- receiver UART baud;
- lock on first connection;
- later: RX-as-TX, buzzer features, unlock higher power and other target features.

Sensitive values such as binding phrase and Wi-Fi password must not be written to ordinary logs.

## 6. Flash methods
Only advertise methods present in upload_methods:
- UART;
- Wi-Fi;
- Betaflight passthrough;
- EdgeTX passthrough;
- DFU;
- STLink;
- stock bootloader;
- ZIP/passthrough where applicable.

If ESP Service Studio has not implemented a method yet, show it as unavailable rather than pretending support.

## 7. Safe flashing
Before any destructive write:
- identify MCU;
- validate target;
- validate pinned release commit;
- validate firmware family;
- validate image sanity;
- validate SHA-256;
- validate write offset and flash bounds;
- validate flash capacity;
- require explicit confirmation.

ESP8285 ROM-only path may use per-block ROM ACK.
Do not label this as full readback verification.
Full readback/stub verification is a separate capability after physical HIL proves it reliable.

## 8. Custom hardware
Local profiles remain only for project-specific hardware:
- Mesh Messenger nodes;
- ESP32-S3 Service Bridge;
- experimental controller/radio combinations.

These profiles are separate from the dynamic official ELRS catalog.

## 9. Radio families
SX127x/SX126x/SX128x:
- service/diagnostics only;
- no generic user firmware image assumption.

LR1121:
- microcode update only through an explicit supported profile.

LR2021:
- capability-driven service;
- do not invent update semantics.

Unknown/bare radio:
- probe-only until identified.

## 10. Service Bridge
For a bare radio module:

Pixel / Android
  <-> USB
ESP32-S3 Service Bridge
  <-> SPI
SX / LR radio

Planned protocol: SS-BRIDGE/1.
It must be versioned, capability-driven and probe-before-write.

## 11. Recovery
Android/WebView v0.8 remains the recovery path until Flutter physical HIL parity is proven.

## 12. Storage and platform scope
Dropbox = user-facing source of truth for releases, architecture and handoffs.
GitHub = build/CI workspace.

Current build target: Android arm64 / Pixel 7a.
Windows/Linux/Web packaging is postponed.
