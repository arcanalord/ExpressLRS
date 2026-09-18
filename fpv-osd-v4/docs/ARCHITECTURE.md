# Architecture — FPV OSD v4

## Direction

Windows remains the primary product target. Raspberry Pi/Linux ARM64 and Android are portability targets, not reasons to compromise the Windows operator experience.

## Layering

### 1. Core
Pure .NET. No Avalonia, Media Foundation, Android, FFmpeg, sockets, registry, Win32, or filesystem UI assumptions.

Owns:
- application/operator state
- stream selection and PiP policy
- alarm policy and event semantics
- settings models and validation contracts
- recording policy
- diagnostics models
- Center Motion state/result models

### 2. Protocol
Pure .NET protocol code.

Owns:
- RTP parsing
- Opus RTP clock mapping
- CRSF telemetry parsing
- RC7-compatible network framing

This layer must be executable in tests on any OS.

### 3. Platform.Abstractions
Stable interfaces between application logic and hardware/media/platform services.

Owns contracts for:
- video sources
- incoming audio
- recorder
- camera control
- alarm output
- joystick/input
- settings persistence/secret store

### 4. Platform implementations
Separate assemblies by platform.

Planned:
- `FpvOsd.Platform.Windows`: Media Foundation, WASAPI/waveOut replacement, camera HTTP/SSH, Windows joystick, DPAPI/Credential Manager
- `FpvOsd.Platform.Linux`: Raspberry Pi/Linux video/audio/input backend
- `FpvOsd.Platform.Android`: MediaCodec/AudioTrack/Android input backend

No platform implementation may leak native handles/types into Core/UI-facing contracts.

### 5. Desktop UI
Avalonia desktop shell. Owns rendering and interaction only.

The UI binds to application state/services; it does not open sockets, decode H.264/Opus, write MP4, or call camera protocols directly.

## Media pipeline

Visible RTP UDP -> demux -> H.264 video decoder -> video frame surface
                       -> Opus PT97 decoder -> PCM fan-out -> playback
                                                    -> recorder AAC audio input

Thermal -> decoder -> video frame surface -> optional PiP -> recorder video

Mute only controls local playback. It must not disable receive/decode or recording PCM delivery.

## Recording

Recording is an application service using `IRecorder`.

Windows first contract:
- H.264 MP4 video
- Visible recording may include AAC 48 kHz mono audio
- Thermal is video-only unless a real source contract is added
- audio failure must not terminate video recording
- timestamps remain monotonic

## Center Motion

Center Motion is monitoring/alarm only:
- center-zone motion detection
- score/state/event
- audible/visual alarm

Explicitly out of scope:
- target tracking
- target lock
- aiming/guidance
- payload/weapon actuation

## Settings

Cross-platform settings model uses JSON with validation and atomic replace.

Platform secret providers:
- Windows: DPAPI/Credential Manager
- Linux: protected local provider/keyring where available
- Android: Android Keystore-backed storage

## Build strategy

Primary development and packaging targets:
1. `win-x64`
2. `linux-arm64`
3. `android-arm64`

Core and Protocol must build/test without any native SDK. Platform assemblies are the only place where native SDK/toolchain constraints are allowed.

## Migration rule

M12 is the behavioral reference. Port tests and protocol contracts before replacing implementation details. Do not blindly transliterate Win32 classes line-for-line.
