# Main Mesh Messenger — Developer Guide

Source of truth for releases: Dropbox /FPV Club Research/Mesh Messenger
Validated baseline: v1.5.9

## Start
Read Dropbox files in order:
1. PROJECT_INDEX.md
2. CONTINUATION_HANDOFF.md
3. NEXT_TASK.md
4. BUILD_MANIFEST_CURRENT.md
5. CURRENT_v1.5.9.md
6. STATUS_v1.5.9.md
7. WORKLOG_v1.5.9.md
8. 00_Архитектура/MODULE_MAP_CURRENT.md
9. 00_Архитектура/MODULE_STRUCTURE_TARGET_CURRENT.md

Do not start from archived versions or 01_Исследования/WiFi_First.

## Change workflow
- one short-lived branch = one concern;
- small diff;
- refactor and behavior changes are separate;
- one mutable state = one owner;
- draft PR before promotion;
- CI evidence before promotion;
- Android runtime check for UI/runtime changes;
- real Meshtastic E2E for radio behavior changes;
- only after validation update Dropbox CURRENT/STATUS/WORKLOG/BUILD_MANIFEST.

## Refactor order
1. navigation/bootstrap
2. map
3. chat/delivery/files
4. radio/PhoneAPI/BLE
5. network health
6. help/diagnostics

## Ownership
UI never calls BLE/GATT directly.
Platform adapters do not own chat/delivery/map/file state.
Network Health is a domain owner.
There is one Help Registry and one Help Center.

## Required gates
- JS syntax
- source audit
- deterministic core/protocol tests
- startup/navigation smoke
- sector-specific regression
- Android BLE/source contracts
- Gradle build
- APK zipalign/signature/package/version verification
- Android runtime where applicable
- real hardware where radio behavior changed

A successful build alone is not a release.

## Current PR
PR #3: navigation/bootstrap extraction only.
Do not merge/promote until checks and Android runtime are verified.
