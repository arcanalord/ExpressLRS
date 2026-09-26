# BUILD MANIFEST — Mesh Messenger Flutter v0.1.10-dev.12-r1

Date: 2026-09-26

## Source
Repository: arcanalord/ExpressLRS
Branch: build/mesh-flutter-v0.1.10-dev.12
Workflow: .github/workflows/mesh-flutter-v0.1.10-dev.12.yml

## Package target
Package: org.fpvclub.mesh.flutter
Version name: 0.1.10-dev.12-r1
Version code: 26092602
ABI: arm64-v8a only

Stable dev certificate SHA-256:
1805de6223824deb07d9ae94f1e38ed16960016375483f200516e1fb6b0b0d2d

## Gates
- flutter analyze
- Core self test
- LAN transport self test
- MapPoint self test
- storage concurrency self test
- identity pairing self test
- PhoneAPI self test
- MM-UART codec/session/capability tests
- two-node MM-UART/MMRP simulation
- built-in HIL-100
- Android/source/UI gates
- widget tests
- Android arm64 APK build
- package/version/ABI/signature verification

## Release status
SOFTWARE PASS is required before publishing the APK.
PHYSICAL RF HIL remains a separate gate.

## Final verified build
CI run: 36215746688
CI tested head: 2d934520decc41246ddb368340b860e170ccda11
CI result: SUCCESS

Final stable-signed APK:
MeshMessenger-Flutter-v0.1.10-dev.12-r1-arm64-INSTALL.apk

Final signed APK SHA-256:
f23831d7ae119e0761ce67c126d7affd1fdaad1e653d9a67d0c994430685c2bd

Size: 78259479 bytes
APK Signature Scheme v2: PASS
APK Signature Scheme v3: PASS
zipalign 16 KiB: PASS
