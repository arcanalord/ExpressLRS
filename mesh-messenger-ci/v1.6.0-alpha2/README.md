# APK Mesh Wi-Fi — v1.6.0-alpha2

## Scope

This branch is the Wi-Fi-first APK line for `WiFi_First / APK Mesh Wi-Fi`.

Current transport policy:
- active communication transport: **Wi-Fi LAN only**;
- uses the phone/laptop Wi-Fi interface;
- no ESP/radio module is required for the current communication path;
- no Internet relay is exposed in this build;
- Meshtastic/BLE/radio transports are not exposed in this build;
- transport boundaries remain modular so other transports can be added later without rewriting the messenger UI/data model.

## Baseline and provenance

The build is reconstructed from the clean `mesh-messenger-v1.5.5` source payload.
The incomplete/corrupt `v1.6.0-alpha1` Android archive is intentionally not used as a binary baseline.

The already-developed alpha1 source changes are replayed as patches:
- build
- core
- help
- UI
- LAN WebRTC transport
- Internet relay source (then disabled by alpha2 product policy)
- service worker
- application integration

Then `wifi_only_overlay.py` applies the Wi-Fi-only product policy.

## Wi-Fi implementation

Direct local connection uses `RTCPeerConnection` + `RTCDataChannel` with no configured ICE servers.
Pairing uses an offline invitation/answer code.
Both devices are expected to be reachable on the same local Wi-Fi network for the current build.

## Build

Workflow:
`.github/workflows/mesh-wifi-v1.6.0-alpha2-apk.yml`

Expected APK identity:
- applicationId: `org.fpvclub.mesh`
- versionName: `1.6.0-alpha2`
- versionCode: `23`

Artifact:
`mesh-wifi-v1.6.0-alpha2-debug-apk`

## Guardrails

The workflow must fail if:
- the clean v1.5.5 source archive is invalid;
- alpha1 source patches cannot be replayed;
- Wi-Fi LAN transport source is absent;
- BLE permissions remain in the Android manifest;
- Internet relay UI is exposed;
- the transport selector exposes anything other than Wi-Fi;
- JS syntax checks fail;
- APK alignment/signature/package/version checks fail.

## Next functional checks after CI passes

1. Install on two Android devices.
2. Put both devices on the same Wi-Fi network/hotspot.
3. Create invitation on device A.
4. Paste invitation on device B and return the answer code.
5. Verify status becomes `Связано`.
6. Send text A -> B and B -> A.
7. Disconnect/reconnect and check queued message delivery.
8. Repeat with one phone providing the hotspot.
9. Verify the UI contains no Meshtastic/Bluetooth/Internet transport controls.
