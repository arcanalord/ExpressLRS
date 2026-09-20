# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev15
Date: 2026-09-20

## Baseline reconciliation
The branch contained valid rev10–rev14 commits followed by two later commits that converged measurement data on a cleaner canonical contract but reset VERSION to rev9. Rev15 preserves the Git history and declares one current baseline instead of force-resetting or duplicating fields.

## Canonical measurement rule
- Runtime normalized data: samples, nested source, reference_impedance_ohm.
- VNA CSV profile is source.profile.
- Legacy parallel points/source_name/reference_ohm fields are not restored.

## New product artifacts
- DesignVariant v0.1: immutable named identity for one exact EMNX model hash.
- MeasurementSet v0.2: immutable binding of raw measurement SHA-256 and normalized data SHA-256 to one DesignVariant/model hash.
- Engineering Report v0.1: derived correlation/evidence report with Markdown rendering.

## API
- POST /api/variant/create
- POST /api/measurement/bind
- POST /api/report/generate
- GET contract endpoints for all three new schemas.

## Invariants
- No solver physics change.
- No EMNX schema change.
- Measurement never overwrites simulation.
- Invalid fingerprints or cross-variant binding fail closed.
- Generated reports cannot promote solver trust beyond recorded evidence gates.

## Promotion gate
Promote rev15 only after internal/Linux UI, product workflow, real NEC2, Windows x64 and exact source snapshot all pass.
