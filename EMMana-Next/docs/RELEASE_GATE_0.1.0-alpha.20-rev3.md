# Release gate — EMMana-Next 0.1.0-alpha.20-rev3

## PASS
- Clean Linux Release build
- 9/9 CTest
- B01/B02/B04/B05/B06/B07/B08/B09 internal regression coverage
- PEC/finite-ground internal gates
- LAPACK/bootstrap parity
- serial/parallel parity
- Linux UI/API smoke
- Help Registry content/JS/runtime hooks
- CI workflow YAML validation
- NEC2 suite orchestration plumbing

## READY, NOT EXECUTED
- Real `nec2c` GitHub Actions gate
- Windows MSVC x64 GitHub Actions build/package

## BLOCKING authoritative engineering release
- Real B01 NEC2 strict measurement and stored report
- Characterized B02/B04 independent deltas and adopted tolerances
- Independent finite-ground and loss/load validation
- Production kernel convergence/policy closure
- Actual Windows clean-run verification
- Final desktop/editor M8 workflow remains future work

Experimental Linux alpha remains usable for testing; it is not an authoritative RF solver release.
