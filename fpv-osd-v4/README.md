# FPV OSD v4 — .NET / Avalonia

Windows-first cross-platform rewrite of FPV OSD Native v3.

## Goal

Keep the operator contract of the M12 native branch while removing the build/toolchain bottleneck. The primary deliverable remains Windows x64. The same core is designed to run later on Raspberry Pi / Linux ARM64 and Android.

## Baseline

- .NET 10 LTS
- C# 14
- Avalonia 12.1.2
- Windows x64 first
- Linux ARM64 / Raspberry Pi second
- Android ARM64 after desktop media parity

## Non-negotiable behavior carried from Native v3

- Visible and Thermal streams
- stream switch and PiP
- OSD and telemetry
- recording
- incoming Visible Opus audio
- camera control
- joystick/input abstraction
- settings and diagnostics
- Center Motion Alarm

Center Motion remains monitoring/alarm only. No target tracking, lock, aiming, or payload actuation.

## Layout

- `src/FpvOsd.Core` — state, alarms, motion, settings models, orchestration contracts
- `src/FpvOsd.Protocol` — RTP/Opus packet parsing and telemetry protocol code
- `src/FpvOsd.Platform.Abstractions` — media, camera, recorder, input interfaces
- `src/FpvOsd.Desktop` — Avalonia desktop shell for Windows/Linux
- `tests/FpvOsd.Core.Smoke` — dependency-free executable smoke tests
- `docs/ARCHITECTURE.md` — architecture and platform policy
- `docs/MIGRATION-M12-TO-V4.md` — mapping from C++ M12
- `eng/build.ps1` / `eng/build.sh` — reproducible build entrypoints

## Build target

```text
dotnet restore fpv-osd-v4/src/FpvOsd.Desktop/FpvOsd.Desktop.csproj
dotnet build fpv-osd-v4/src/FpvOsd.Desktop/FpvOsd.Desktop.csproj -c Release
dotnet run --project fpv-osd-v4/tests/FpvOsd.Core.Smoke/FpvOsd.Core.Smoke.csproj -c Release
```

Windows publish:

```text
dotnet publish fpv-osd-v4/src/FpvOsd.Desktop/FpvOsd.Desktop.csproj -c Release -r win-x64 --self-contained false -o dist/win-x64
```

Self-contained single-file publish is optional for field deployment; the normal framework-dependent build stays smaller.

## Current milestone

V4-M0: architecture + compilable scaffold + protocol/motion smoke tests.

Next: Windows media backend, then operator UI parity page-by-page.
