# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev19
Date: 2026-09-20

## Goal
Make the new geometry editor immediately useful without adding another configuration layer.

## Implemented
- Template bar inside Geometry.
- Dynamic list from /api/templates; UI does not own a duplicate template catalog.
- Half-wave Dipole.
- Quarter-wave monopole / GP over PEC.
- 3-element Yagi.
- Square full-wave Loop.
- Frequency-driven scaling.
- One action: Create and Calculate.
- New template is model-checked before/with the normal solver workflow.

## Trust
- Dipole: reference-validated.
- GP/Yagi: characterized under the existing policy.
- Square Loop: experimental starter only; no independent reference claim yet.

## No layering
- Output is the same pure EMNX edited by Geometry/JSON.
- No second geometry representation.
- No new backend endpoint.
- No solver physics or schema change.
