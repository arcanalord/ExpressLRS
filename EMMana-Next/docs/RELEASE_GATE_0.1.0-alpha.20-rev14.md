# Release gate — EMMana-Next 0.1.0-alpha.20-rev14

## Candidate scope
Rev13 verified Measurement workspace plus simple VNA CSV profile auto-detection.

## Required PASS
- Linux/internal regression suite
- Measurement pipeline including R/X, S11 RI and S11 dB/phase CSV
- Linux UI smoke
- real NEC2 strict B01 gate
- Windows x64 build/regression/package
- exact source snapshot

## Still blocked
- authoritative finite-ground validation
- independent conductor-loss/load validation
- real Windows clean-run on a user machine
- production-kernel convergence policy
- final geometry editor
