# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev20
Date: 2026-09-20

## Goal
Turn the existing Windows verification package into a simple portable user application without adding a second desktop UI framework.

## Implemented
- Self-contained EMMana-Next.exe using PyInstaller one-file packaging.
- Bundled Python runtime.
- Bundled current UI/assets and solver.
- Automatic default-browser launch.
- Localhost-only default binding.
- Separate emnext-cli.exe retained for diagnostics.
- README-WINDOWS.txt in the package.

## Windows runtime gate
CI starts packaged EMMana-Next.exe with --no-browser, polls /api/health, checks exact VERSION and verifies the served HTML contains Geometry and Template controls.

## Architecture choice
No Tauri, Electron or WebView was added. The browser UI remains the one interface implementation.

## Promotion
Promote rev20 only if source snapshot, Linux/internal/NEC2, Windows C++ gates and packaged Windows runtime gate all pass.
