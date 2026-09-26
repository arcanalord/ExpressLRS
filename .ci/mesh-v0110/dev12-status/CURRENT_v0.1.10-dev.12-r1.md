# CURRENT — Mesh Messenger Flutter v0.1.10-dev.12-r1

Date: 2026-09-26
Status: SOFTWARE PASS / TWO-NODE SOFTWARE HIL PASS / PHYSICAL RF HIL PENDING

## Active baseline
v0.1.10-dev.12-r1 is the active Flutter development baseline.

Android:
- package: org.fpvclub.mesh.flutter
- versionName: 0.1.10-dev.12-r1
- versionCode: 26092602
- ABI: arm64-v8a

Stable internal signing certificate:
1805de6223824deb07d9ae94f1e38ed16960016375483f200516e1fb6b0b0d2d

## Radio path
Android USB Serial -> MM-UART/1 -> M03 firmware -> MMRP/1 -> PHY profile.
Legacy EP2 LINK / CRSF remains fallback/diagnostics.

## Added after dev.11
- built-in two-radio HIL responder on every running MM-UART session;
- one-tap Test 100 and Test 1000 on Connection screen;
- RTT min/avg/max, packet loss and retry counters;
- recipient ACK verification;
- duplicate messageId verification;
- MapPoint round-trip verification;
- automatic response from second phone;
- selected contact ep2NodeId used as target binding;
- nodeId/nodeBinding can be learned from COMPAT_SELFTEST;
- v0.4.0 compatibility: HIL no longer requires COMPAT_SELFTEST when the session already established MM-UART/1 + explicit MMRP/1.

## Software verification
Two-node radio simulator validates:
- Text + recipient ACK;
- MapPoint + ACK;
- duplicate suppression;
- reconnect resend;
- DEVICE_RESET recovery;
- built-in HIL 100.

Physical two-board RF HIL is still required before release-candidate status.

## Real hardware procedure
1. Install this build on two Android devices.
2. Connect one M03-compatible radio to each device.
3. Use radio node bindings 1 and 2 (or bind the selected contact to the actual node ID).
4. Wait until both devices show MM-UART/1 + MMRP/1 ready.
5. Leave the second phone open; HIL responder is automatic.
6. On the first phone run Test 100.
7. If PASS, run Test 1000.
8. Unplug/replug USB on one side and repeat Test 100.
9. Save result/log as RADIO_HIL_PASS only after the physical test passes.

## Final CI
Run: 36215746688
Result: SUCCESS
Tested head: 2d934520decc41246ddb368340b860e170ccda11

Final signed APK SHA-256:
f23831d7ae119e0761ce67c126d7affd1fdaad1e653d9a67d0c994430685c2bd
