# EMMana-Next — WORKLOG 2026-09-20 alpha.20-rev21

## Scope
Lightweight 3D geometry preview only. No solver changes and no new UI framework.

## Changes
- Added native Canvas 3D wire preview inside the existing Geometry tab.
- Added mouse/touch drag rotation, wheel zoom and one Reset view action.
- Added XYZ axes, feed marker and ground-plane indication when ground is enabled.
- Selected wire is highlighted when selection state is available from the 2D editor.
- 3D view reads the same EMNX project model; it does not own or mutate geometry.
- Kept the existing XY/XZ/YZ editor unchanged.
- No Three.js, WebGL, Electron or Tauri dependency.

## Validation target
- geometry structure test includes the 3D surface and remains dependency-free.
- existing Linux/UI/C++ gates must remain green.
- Windows portable runtime must still expose the same single local-browser workflow.

## Version
0.1.0-alpha.20-rev21
