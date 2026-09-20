# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev9
Date: 2026-09-20

## Goal
Make measurement correlation a real, single-contract product feature.

## Reconciliation
A partially connected measurement UI already existed and used an older parallel data contract (points/source_name/reference_ohm). Rev9 removes that parallel contract. Server, UI and tests now use the normalized contract from apps/shared/product/measurement.py.

## Implemented
- Touchstone S1P parser with RI/MA/DB, Hz/kHz/MHz/GHz and reference R.
- VNA CSV parsing from S11 real/imag, S11 dB/phase, or R/X.
- Normalized S11, S11 dB, VSWR and complex impedance.
- Interpolation of measurement onto simulation sweep grid within overlap.
- Delta R/X/S11/VSWR statistics and resonance shift.
- Existing Simulation vs Measurement UI migrated to the canonical contract.
- Deterministic fixtures and CI tests.

## No layering
- One measurement contract only.
- No solver physics changes.
- Raw measurement remains sidecar data.
- Simulation is never overwritten by measurement.
