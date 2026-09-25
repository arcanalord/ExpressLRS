# ESP Service Studio Universal — Architecture v1

Date: 2026-09-25
Status: CURRENT WORKING TARGET

## 1. Product shape
One operator-facing app. Internally four service targets:
- whole device;
- controller/MCU;
- radio;
- bare radio through Service Bridge.

## 2. Device profile
A profile describes:
- board/device family;
- controller family and boot/update transport;
- radio family;
- safe radio service kind;
- board pins/boot method (later);
- supported host protocols;
- update-package compatibility.

The profile is data, not UI code.

## 3. Capability-first radio service
For custom Mesh Messenger nodes, host capabilities are negotiated.
MM-UART/1 remains the canonical future app-to-radio host protocol.

Chip name is metadata. It must not be the sole authority for destructive operations.

## 4. Update package
Planned package format:
- manifest.json;
- controller image(s) + offsets;
- optional radio microcode;
- hardware profile id / compatible ids;
- hashes;
- package version;
- optional migration metadata.

Default UI does not expose raw offsets.

## 5. Radio families
- SX127x/SX126x/SX128x: probe/config/register/test path; no generic user firmware image assumption.
- LR1121: permit microcode update only through an explicit supported profile.
- LR2021: capability-driven service; do not assume update semantics until driver/profile confirms them.
- unknown/bare radio: probe-only until identified.

## 6. Service Bridge
ESP32-S3 Service Bridge is the universal adapter for a bare SPI radio:
phone USB <-> ESP32-S3 <-> SPI <-> radio.

Planned bridge protocol: SS-BRIDGE/1, binary/versioned/capability-driven.
It must support safe probe before write operations.

## 7. Recovery
Current Android/WebView v0.8 remains available as recovery for direct ESP ROM flashing.
Do not remove it until Flutter has physical HIL parity.

## 8. Safety gates
Before any write:
- identify target;
- check profile/package compatibility;
- verify hashes;
- check flash bounds;
- show exactly which component will be written;
- preserve recovery path;
- verify after write.

## 9. Storage
Dropbox = user-facing source of truth for releases, architecture, handoffs.
GitHub = build/CI workspace.

## 10. Current platform scope
Current test builds are Android arm64 only, targeted at the user's Pixel 7a.
Do not spend work on Windows/Linux/Web packaging yet. Cross-platform support stays an architectural goal for later.

USB device state must update live on attach/detach and refresh when the app returns to foreground.
