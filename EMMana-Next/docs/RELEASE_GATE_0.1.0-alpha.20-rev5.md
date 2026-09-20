# Release gate — EMMana-Next 0.1.0-alpha.20-rev5

## PASS
- Clean Linux Release build
- 10/10 CTest
- B01/B02/B04/B05/B06/B07/B08/B09 internal regression coverage
- PEC/finite-ground internal consistency gates
- LAPACK/bootstrap parity
- serial/parallel parity
- Linux UI/API smoke
- Help Registry content/JS/runtime hooks
- UI single-surface ownership gate
- real NEC2 B01 strict reference gate
- B02/B04 NEC2 characterization
- Windows MSVC x64 build/regression/package on prior rev4 baseline

## MEASURED / NOT ACCEPTED
- Finite-ground independent NEC2 matrix G01–G06
- Worst impedance delta: G01 dR=-30.163280 ohm, dX=+12.262247 ohm
- Current homogeneous-halfspace-image-v1 is experimental and not release-authoritative

## PENDING
- validated Sommerfeld/Norton-grade finite-ground implementation
- rerun G01–G06 and adopt evidence-backed tolerances
- independent conductor-loss / RLC-load validation
- production-kernel convergence/policy closure
- real Windows clean-run verification
- final graphical desktop/editor workflow
