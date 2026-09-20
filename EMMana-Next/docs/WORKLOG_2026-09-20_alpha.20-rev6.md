# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev6
Date: 2026-09-20

## Goal
Continue product/business-layer development using patterns observed in Japanese, Chinese, US and European antenna/EM products, without changing solver physics.

## Added
- Product Domain registry with workflow stages, capability groups, trust levels and invariants.
- Analysis Plan v0.1 schema.
- B04 example analysis plan.
- /api/product-registry.
- Product-domain regression test.
- World product-pattern research note.
- ADR-0022 separating product workflow from EMNX.

## Key rule
EMNX remains the physical solver input. Product metadata, measurement sets, reports and workflow state live above it.

## World patterns adopted
- MMANA: fast wire workflow, result comparison, optimisation.
- Murata Femtet: project/model/material/result integration and circuit interoperability.
- Xpeedic: separation of solver, RF system, post-processing, measurement, libraries and job management.
- HFSS: template/synthesis front door.
- XFdtd: explicit analysis workflow and requested outputs.
- CST: system decomposition and solver selection above components.
- WIPL-D: explicit optimisation goals, hybrid methods and Pareto.

## Next
1. Template/synthesis registry.
2. Materials and ground-profile library with evidence status.
3. Touchstone/VNA measurement-set contract and comparison metrics.
4. Report generator.
5. Matching-network product layer.
