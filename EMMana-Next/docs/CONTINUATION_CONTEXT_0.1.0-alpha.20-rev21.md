# EMMana-Next — CONTINUATION CONTEXT
Date: 2026-09-20
Project cloud owner: Dropbox `/FPV Club Research/07_Simulation_Testing/EMMana-Next`
Git/CI mirror: GitHub `arcanalord/ExpressLRS`, branch `emmana-next-alpha20`

## Exact checkpoint
- Current development target: `0.1.0-alpha.20-rev21`
- Base validated release: `0.1.0-alpha.20-rev20`
- Base validated SHA: `c858627d4f60903afb9c9623730e4055f05e7ecb`

## rev21 scope
- Lightweight 3D geometry preview only.
- Native Canvas; no Three.js/WebGL/Tauri/Electron.
- Same EMNX model remains source of truth.
- Existing 2D XY/XZ/YZ editor remains the editing surface.
- 3D view is read-only: drag to rotate, wheel to zoom, reset view.
- Shows wires, XYZ axes, feed point and ground plane when enabled.

## Guardrails
- Do not add a second UI stack.
- Do not change solver trust status as part of visualization work.
- Do not add 3D editing in rev21.
- Do not add 3D radiation-pattern rendering until geometry preview is validated.

## Next validation
1. Run source/UI tests.
2. Run Windows portable gate.
3. Test Yagi, Dipole, Loop and GP in Geometry view.
4. If stable, save exact-SHA rev21 artifacts back to Dropbox.
