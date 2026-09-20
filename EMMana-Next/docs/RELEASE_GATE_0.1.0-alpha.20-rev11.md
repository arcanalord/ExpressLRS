# Release gate — EMMana-Next 0.1.0-alpha.20-rev11

## Required PASS
- Linux/internal CTest
- Linux UI runtime smoke including measurement screen contract
- Touchstone/VNA measurement pipeline
- Real NEC2 B01 strict reference gate
- Finite-ground G01-G06 remains characterization-only
- Windows MSVC x64 build/regression/package
- Exact source snapshot manifest

## Scope guard
- Measurement UI only.
- Solver physics unchanged.
- EMNX schema unchanged.
- Existing measurement API contracts reused.

## Still not release-authoritative
- finite-ground homogeneous-halfspace-image-v1
- conductor-loss / RLC-load independent validation
- production-kernel convergence policy
- real Windows clean-run outside CI
