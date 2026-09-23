# Real-0 Android Tracker Lab v0.1.4

Native Android camera/video tracking bench with a shared pure-Kotlin production core.

## Current architecture

- Android shell: CameraX live camera + local video through Storage Access Framework / MediaMetadataRetriever.
- Manual target selection: QUICK LOCK / PRECISE LOCK.
- Shared tracking core: `core/NccTrackerCore`, independent from Android UI and CameraX.
- Android adapter: `BitmapGrayFrame` converts `Bitmap` to the shared `GrayFrame` contract.
- Synthetic replay: `core/src/test/.../ReplaySmoke.kt` runs the same production core on the JVM.
- Tracking output: TRACKING / UNCERTAIN / LOST, measured box, predicted box, quality and processing time.
- Local-only runtime; no network dependency.

Package: `club.fpv.real0.trackerlab`
Version: `0.1.4` / versionCode `5`

## Operator behavior

- QUICK/PRECISE LOCK is one-shot: after one lock gesture normal touches do not re-lock.
- RESET clears the current target and cancels pending lock.
- VIDEO pauses while the operator selects the target.
- VIDEO initializes the tracker on the frame actually displayed when ROI is selected.

## Build / tests

Core smoke:
```
gradle --no-daemon -p android/real0-tracker-lab-v0.1 :core:coreSmoke
```

Android debug APK:
```
gradle --no-daemon -p android/real0-tracker-lab-v0.1 :core:coreSmoke :app:assembleDebug
```

CI workflow: `.github/workflows/real0-android-apk.yml`.
The workflow must pass `:core:coreSmoke` before APK assembly and then verify ZIP integrity, zipalign, APK signature, package ID, SHA-256 and build provenance.

## Gates

- CORE_PASS: available through the shared JVM replay smoke.
- ANDROID_BUILD_PASS: pending while GitHub Actions runner fails before the first step.
- PHONE_PASS: pending for exact v0.1.4 APK.
- HELP_REGISTRY_PASS: pending; the current HELP dialog is temporary.

Do not add ReacquireManager until the exact v0.1.4 Android baseline has passed build and phone smoke.
