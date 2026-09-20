# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev11
Date: 2026-09-20

## Scope
Implement the real Simulation vs Measurement screen in the existing Linux web UI from the approved Figma design, without adding new solver behavior.

## Implemented
- S1P / VNA CSV file import in browser.
- Calibration and reference-plane metadata fields.
- Reuse of existing /api/measurement/parse and /api/measurement/compare.
- Comparison against the most recent frequency Sweep.
- KPI: max abs delta R, X, VSWR and S11.
- Dynamic S11 simulation/measurement overlay.
- Compact aligned-sample table.
- Measurement provenance card.
- Context Help Registry topic.
- Responsive desktop/tablet/mobile layout.
- Linux smoke verifies static UI contract plus real parse/sweep/compare API path.

## Simplicity rules
- No new navigation mode.
- No new backend endpoint.
- No solver or EMNX changes.
- No S2P, reporting or DesignVariant in this revision.

## Next after rev11 gates
1. S2P / fuller Touchstone 2.1 coverage.
2. Named VNA CSV profiles.
3. Resonance-shift and band-level correlation metrics.
4. DesignVariant and engineering report only after measurement workflow remains stable.
