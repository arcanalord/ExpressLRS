# EMMana-Next CI bootstrap — alpha.20-rev3

## Purpose
Two workflows are now part of the source tree:

- `.github/workflows/ci-nec2.yml` — real independent NEC2 validation on Ubuntu 24.04.
- `.github/workflows/ci-windows.yml` — MSVC x64 verification build and ZIP artifact.

## NEC2 gate policy
B01 is the strict release gate with provisional absolute R/X tolerances of 3 ohm.
B02 and B04 are characterization-only until the first real measurements are recorded and evidence-based tolerances are adopted.
The generated report is `benchmarks/NEC2_REAL_CROSS_SOLVER.json`.

## Windows package policy
The Windows artifact is a verification/CLI package, not the final M8 desktop shell. It proves the C++ solver and project formats build under MSVC x64. Final desktop packaging still requires the planned desktop application layer.

## Repository prerequisite
A dedicated GitHub repository does not yet exist in the connected account. The workflows are ready but cannot execute until the source tree is pushed to a repository with GitHub Actions enabled.
