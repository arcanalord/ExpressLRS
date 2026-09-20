# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev8
Date: 2026-09-20

## Trigger
Rev7 candidate failed internal regression before independent NEC2 execution. Product asset tests passed; Linux UI smoke failed because B01 seed is historical EMNX schema 0.1.

## Fix
- Do not loosen the test.
- Template synthesis now normalizes generated projects to current EMNX schema 0.5.
- Linux UI smoke runs model-check on the synthesized project.
- Solver physics and EMNX parser are unchanged.

## Promotion rule
Rev7 is a failed candidate/history artifact. Rev8 becomes current only after Linux/internal, real NEC2, Windows build/regression/package and exact snapshot gates pass.
