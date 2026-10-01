# Map Markup — MapAdapter v1 + MapPoint v1 browser runtime evidence

Date: 2026-10-02
Candidate lineage: SOURCE_CANDIDATE_0.2.6-shared-contracts-r2.zip
New candidate: SOURCE_CANDIDATE_0.2.6-shared-contracts-r3.zip
Scope: runtime-test harness only. Application/runtime production source is unchanged from r2.

Finding MAP-001:
r2 browser harness omitted map-point-v1.js from its in-memory module bundle although app.js uses publishFeatureAsMapPointV1. This caused the browser gate to fail immediately after point creation and obscured the shared-contract runtime gate.

r3:
- adds map-point-v1.js to the real browser harness bundle;
- checks MapAdapter v1 project/unproject round-trip on desktop and mobile;
- checks coverageRadiusPx > 0;
- checks local-grid readiness/provider identity;
- switches to unavailable vector/PMTiles path and proves fallback without ProjectSnapshot mutation;
- checks return to grid without ProjectSnapshot mutation;
- listens for the real map-markup:map-point-v1 event emitted by the UI addPoint path and validates id/lat/lon/createdAt/label.

Local verification before packaging:
- JavaScript syntax: PASS.
- MAP_ADAPTER_CONTRACT_V1_PASS.
- MAP_POINT_V1_CONTRACT_PASS.
- MAP_POINT_V1_RUNTIME_BRIDGE_PASS.
- Playwright/Chromium full UI gate: UI_VISUAL_GATE_OK on desktop 1440x900 and mobile 412x915.
- Console errors: 0.
- Provider fallback project state unchanged: PASS.
- MapPoint UI event: PASS.

Promotion interpretation:
Map Markup provides the missing second browser/runtime consumer evidence for MapAdapter v1 when combined with PPO Radar. This supports a browser-contract scoped VERIFIED status for MapAdapter v1. It does not by itself make every provider/platform adapter VERIFIED.

MapPoint v1 remains CANDIDATE globally until its second independent consumer is reconciled against the canonical M04/Mesh runtime evidence. This r3 evidence proves Map Markup's runtime consumer only.
