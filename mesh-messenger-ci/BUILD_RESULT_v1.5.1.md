# Mesh Messenger v1.5.1 — Android build result

Date: 2026-09-20

## Result

ANDROID_BUILD_PASS: PASS
PHONE_PASS: PENDING
HARDWARE_PASS: PENDING

## Build

- workflow run: 35504688891
- job: build-apk
- result: SUCCESS
- workflow commit: a916a397c64f4ab6a874e411313912abf43fbd5c
- artifact id: 10603103452
- artifact: mesh-messenger-v1.5.1-debug-apk
- applicationId: org.fpvclub.mesh
- versionName: 1.5.1
- versionCode: 17
- compileSdk: 36
- minSdk: 26
- targetSdk: 36

## Source lineage

- validated base: SOURCE_CURRENT_v1.5.zip
- base SHA-256: 1aeae2eec49b264a21004990e6827cd68d6ad00ae09d9065f95cab8d2809e054
- build patch: Kotlin jvmTarget migration from kotlinOptions string DSL to typed compilerOptions; versionName/versionCode bump only.
- shared domain/protocol/transport/UI logic was not changed by this build patch.

## Verification

PASS:
- assembleDebug
- zipalign -c
- apksigner verify
- aapt package/version assertions
- artifact upload

Final APK SHA-256:
a032e0f869ea6d66cf53bf958f6dfd6f2e1f77f4e1b5098e72426608ddd4999d

## Next

Install this exact APK on the target phone and execute the v1.5 hardware test protocol with a real Meshtastic node.
