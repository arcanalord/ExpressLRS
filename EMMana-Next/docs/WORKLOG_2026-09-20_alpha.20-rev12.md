# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev12
Date: 2026-09-20

## Scope
Small UI hardening pass on the rev11 Measurement workspace before promotion.

## Change
- Escape user-controlled provenance values (uploaded file name and reference-plane text) before inserting them into the measurement provenance HTML.
- Add smoke assertion that the escape helper is present.

## Not changed
- solver physics
- EMNX schema
- measurement parser
- comparison math
- API contracts
- Figma layout

## Promotion
Promote rev12 only after internal/Linux, real NEC2, Windows x64 and source snapshot gates pass.
