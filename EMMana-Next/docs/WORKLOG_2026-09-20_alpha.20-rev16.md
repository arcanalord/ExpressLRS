# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev16
Date: 2026-09-20

## Scope
Expose the already validated rev15 DesignVariant / MeasurementSet / EngineeringReport API as a real user workflow in the existing Linux web UI.

## Implemented
- Save Variant button with exact backend model-check/model hash.
- Selectable local variant history (A/B/C style, up to 8 records).
- Bind current S1P/VNA measurement to the selected immutable variant.
- Generate Engineering Report from current Sweep + correlation.
- Markdown report preview and download.
- Context help topic.
- Responsive desktop/tablet/mobile layout.
- Figma measurement screen updated in-place to rev16; no parallel screen.

## Privacy/data rule
Raw S1P/VNA content stays only in the current browser tab until binding. localStorage contains only immutable DesignVariant metadata, never raw measurement bytes.

## No layering
- Reuses rev15 API.
- No solver change.
- No EMNX change.
- No duplicate measurement contract.
- Measurement never overwrites simulation.

## Promotion
Promote rev16 only after Linux/internal tests, real NEC2, Windows x64, source snapshot, and visual screenshot verification pass.
