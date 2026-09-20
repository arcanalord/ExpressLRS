# RELEASE GATE — EMMana-Next 0.1.0-alpha.20-rev20
Date: 2026-09-20

## Candidate scope
Portable Windows application packaging only. Solver physics, EMNX schemas, Geometry, Templates, Measurement and optimizer behavior are unchanged from the validated rev19 baseline.

## Required exact-SHA gates
- Source snapshot artifact: PASS
- Linux/internal CTest: PASS
- Geometry editor gate: PASS
- Linux UI smoke: PASS
- Real NEC2 cross-solver suite: PASS
- B01 strict independent reference: PASS
- Windows MSVC x64 build: PASS
- Windows C++ regression gates: PASS
- PyInstaller portable launcher build: PASS
- Packaged EMMana-Next.exe runtime /api/health gate: PASS
- Packaged UI contains Geometry and Template workflow: PASS
- Windows ZIP artifact: PASS

## Portable package contract
- EMMana-Next.exe is the user-facing launcher.
- No system Python installation is required.
- emnext-cli.exe is included for engineering diagnostics.
- Default bind address is 127.0.0.1.
- Default browser opens automatically; --no-browser is reserved for automation/diagnostics.
- No Tauri, Electron or second WebView UI layer is introduced.

## Promotion rule
Promote this rev20 candidate to Dropbox only from one commit for which source snapshot, real NEC2 and Windows portable workflow all complete successfully. Do not reuse a package from an earlier commit.
