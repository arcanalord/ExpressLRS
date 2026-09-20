# ADR-0023 — Templates, libraries and measurements remain sidecar product assets

Status: Accepted
Date: 2026-09-20

## Decision
Antenna templates, material/ground libraries and measurement sets live in the Product Domain layer.

- Template synthesis returns a new pure EMNX project.
- Material/ground library values are copied into a design revision; models never depend on a hidden mutable library at solve time.
- Measurement sets reference the simulated model and raw measurement assets but never overwrite simulation results.
- Patch/surface antennas remain explicitly unsupported by the current wire-only solver rather than being approximated deceptively.

## Current implementation
- frequency-scaled seed synthesis: half-wave dipole, PEC monopole and 3-element Yagi;
- conductor and ground-profile registry;
- measurement-set v0.1 contract for Touchstone s1p/s2p and VNA CSV.

## Future
Add explicit template parameter generators, Touchstone parsers, VNA CSV import profiles, comparison engine and measurement report cards.
