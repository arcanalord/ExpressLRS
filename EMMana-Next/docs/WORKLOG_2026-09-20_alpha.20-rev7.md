# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev7
Date: 2026-09-20

## Scope
Add the first usable Template / Materials / Measurement product layer without changing solver physics.

## Implemented
- Template Registry v0.1.
- Frequency-scaled seed synthesis for half-wave dipole, PEC monopole and 3-element Yagi.
- Explicit unsupported status for patch antennas under the current wire-only solver.
- Conductors registry: PEC, copper, aluminum, stainless steel engineering defaults.
- Ground profiles: PEC, dry, average and wet; finite-ground profiles remain characterized-not-accepted.
- Measurement Set v0.1 for Touchstone s1p/s2p and VNA CSV sidecar assets.
- Read-only APIs: /api/templates, /api/materials, /api/measurement-contract, /api/template/<id>?frequency_hz=...
- Product asset regression test and Linux UI API smoke checks.
- Source snapshot manifest with exact Git SHA and archive SHA256.

## No-layering controls
- No solver source files changed.
- EMNX schema unchanged.
- Template metadata is not written into EMNX.
- Library values are copied into model revisions rather than resolved as hidden mutable dependencies.
- Measurements remain separate from simulation outputs.

## Next
1. Touchstone s1p parser and normalized MeasurementSet data.
2. Simulation-vs-measurement comparison engine.
3. Named immutable DesignVariant object.
4. Engineering report generator.
5. More template generators after validation.
