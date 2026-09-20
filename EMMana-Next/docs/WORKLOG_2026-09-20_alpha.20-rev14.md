# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev14
Date: 2026-09-20

## Scope
Small VNA CSV compatibility improvement. No new UI controls and no solver changes.

## Implemented
- Header normalization (case, spaces and underscores are tolerated).
- Auto-detect impedance-rx.
- Auto-detect s11-ri.
- Auto-detect s11-db-phase.
- source_profile in parsed measurement provenance.
- Reject non-positive frequencies and duplicate frequencies.
- Help text updated.

## Design choice
Keep CSV handling generic rather than adding vendor-specific adapters. Touchstone remains the preferred interchange format when available.

## Not changed
- solver physics
- EMNX schema
- comparison engine
- Measurement UI layout
- API endpoint shapes beyond optional source_profile in the returned parsed measurement
