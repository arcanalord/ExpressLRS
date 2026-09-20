# EMMana-Next worklog — 0.1.0-alpha.20-rev3
Date: 2026-09-20

## Goal
Prepare the project for repeatable external NEC2 validation and Windows x64 verification without introducing Replit as an unnecessary build layer.

## CI infrastructure added
- Added `.github/workflows/ci-nec2.yml` targeting Ubuntu 24.04.
- Workflow installs real `nec2c`, Eigen and LAPACK, performs a Release build, runs the full internal CTest suite, then runs `tools/run_nec2_suite.py`.
- Added `.github/workflows/ci-windows.yml` targeting `windows-2025` / MSVC x64.
- Windows workflow uses vcpkg for Boost.JSON and Eigen, runs C++ regression gates, and uploads a versioned Windows verification ZIP containing `emnext.exe`, benchmarks, schemas and docs.
- Windows artifact is explicitly a CLI/verification package, not the final M8/Tauri desktop application.

## Cross-solver policy
- Added `tools/run_nec2_suite.py`.
- B01 is the current strict real-NEC2 release gate with provisional absolute tolerances |dR| <= 3 ohm and |dX| <= 3 ohm.
- B02 and B04 are characterization-only until first real measured deltas are stored and evidence-based tolerances are adopted.
- Machine-readable real-run output path: `benchmarks/NEC2_REAL_CROSS_SOLVER.json`.
- Fake adapter is used only to verify orchestration/plumbing and cannot close the independent-reference gate.

## Portability work
- Replaced CMake's legacy Boost module discovery with a direct required search for `boost/json.hpp`.
- This avoids the CMake 3.31 CMP0167/FindBoost deprecation path and is compatible with system headers on Linux and vcpkg toolchains on Windows.

## Local validation
- Both GitHub Actions YAML files parse successfully with PyYAML.
- Clean Release configure/build after the portability change: PASS.
- Full CTest: **9/9 PASS**.
- Serial vs 4-worker numerical parity: PASS; sweep maximum absolute delta = 0; optimizer best model hash identical.
- Linux UI runtime smoke: PASS.
- Help Registry content + JS gates: PASS.
- NEC2 suite orchestration tested with deterministic fake adapter: PASS for plumbing. B01 fake delta is approximately +0.0043 + j0.0281 ohm; B02/B04 intentionally show unrelated fake deltas and remain characterization-only.

## External blockers / truth
- A dedicated EMMana-Next GitHub repository is not currently present in the connected GitHub account.
- The GitHub connector available in this session does not expose repository creation.
- The connected Opera browser is currently unavailable (`Browser not connected`), so repository creation could not be completed through the browser.
- Therefore the real `nec2c` Action and Windows MSVC Action are **prepared but not executed**.
- Replit is not required for the current C++/CMake/NEC2/Windows CI path.

## Next action
Create/connect a dedicated EMMana-Next GitHub repository, push this rev3 source tree, then run both workflows. Ingest `NEC2_REAL_CROSS_SOLVER.json` and the Windows artifact into the release records/Dropbox. Do not mark `INDEPENDENT_NEC2_PASS` or `WINDOWS_VERIFICATION_PASS` before those actual runs complete.
