# Release gate — EMMana-Next 0.1.0-alpha.20-rev13

## Candidate scope
Measurement comparison workspace from rev11, rev12 provenance HTML escaping, and corrected overlapping integration fixture.

## Required PASS
- Linux/internal regression suite
- Linux UI smoke, including measurement UI/API hooks and overlapping parse/sweep/compare path
- Measurement pipeline
- Real NEC2 strict B01 gate
- Windows x64 build/regression/package
- Exact source snapshot

## Explicitly unchanged / still blocked
- finite-ground authoritative validation
- independent conductor-loss / load validation
- real Windows clean-run on a user machine
- production-kernel convergence policy
- final graphical geometry editor
