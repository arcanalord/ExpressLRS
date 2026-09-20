# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev17
Date: 2026-09-20

## Goal
Reduce cognitive load before starting the graphical antenna editor.

## User-facing simplification
- Four real workspace tabs: Model, Calculation, Optimization, Measurements.
- Default view: Calculation.
- Technical solver controls collapsed behind Technical details.
- Top bar no longer exposes the independent-reference status continuously.
- Model view keeps EMNX + diagnostics and explicitly says the graphical editor is the next stage.
- Measurement/Report workflow keeps the rev16 backend but uses simpler visible language.

## No layering
- No new product entity.
- No new API.
- No solver change.
- No EMNX change.
- No second navigation state owner; one setWorkspaceView owns view visibility.

## Next
Build the real graphical geometry editor, then add a Geometry tab only when it is usable.
