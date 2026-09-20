# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev13
Date: 2026-09-20

## Trigger
The rev11/rev12 measurement UI candidate reached the integration compare path, where the smoke fixture used 100–200 MHz measurement data against a 285–315 MHz sweep. The comparison API correctly rejected non-overlapping ranges.

## Fix
- Change only the Linux UI smoke fixture to 285 / 300 / 315 MHz.
- Preserve rev12 provenance HTML escaping.
- Do not weaken comparison range validation.

## Unchanged
- solver physics
- EMNX schema
- parser/comparison math
- measurement UI
- API contracts

## Promotion
Rev13 becomes current only after internal/Linux UI, real NEC2, Windows x64 and exact source snapshot gates all pass.
