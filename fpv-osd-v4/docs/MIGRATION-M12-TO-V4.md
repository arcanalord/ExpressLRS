# Migration map — Native v3 M12 to v4

## Keep as behavior/contracts

- `AppState` -> `FpvOsd.Core.AppState`
- `RtpPacket` -> `FpvOsd.Protocol.RtpParser`
- `RtpAudioClock` -> `FpvOsd.Protocol.RtpAudioClock`
- `CenterMotionDetector` -> planned `FpvOsd.Core.Motion`
- `MediaEngine` -> split into protocol demux + platform video/audio backends
- `Mp4RecorderWin` -> Windows implementation of `IRecorder`
- `OpusAudioWin` -> Windows implementation of `IIncomingAudio`
- camera HTTP/SSH -> Windows implementation of `ICameraControl`, later portable HTTP where appropriate
- joystick mapper -> portable mapping logic + platform device reader
- settings validation -> Core settings model + platform persistence/secret provider

## M12 audio invariants to preserve

- Visible RTP Opus payload type 97
- 48 kHz mono
- same Visible UDP transport as video
- RTP timestamp mapped to monotonic application time
- mute does not stop receive/decode
- PCM can feed playback and recording independently
- recording audio failure is fail-soft: video continues
- Visible clip may request AAC audio; Thermal remains video-only by default

## Port order

### V4-M0
- architecture
- Core state
- RTP parser
- audio clock
- desktop shell
- smoke tests

### V4-M1 — Windows receive path
- UDP receive/demux
- Visible/Thermal H.264 decode
- Opus PT97 decode
- local audio mute
- diagnostics state

### V4-M2 — operator parity
- real video surface
- stream switch
- PiP
- OSD rendering
- Center Motion overlay/alarm

### V4-M3 — recording
- MP4/H.264
- AAC 48 kHz mono for Visible
- disk guard
- fail-soft audio

### V4-M4 — controls/settings
- camera HTTP
- SSH/service actions
- joystick
- settings and credential storage
- diagnostics/events

### V4-M5 — Raspberry Pi
- `linux-arm64` publish
- Linux media backend
- hardware acceptance

### V4-M6 — Android
- Android host project
- MediaCodec/AudioTrack backend
- touch/operator UI adaptation

## Acceptance rule

A migrated feature is not considered complete because the UI exists. It is complete only when its M12/RC7 behavior contract has an executable test where practical and a platform acceptance result where native media/hardware is involved.
