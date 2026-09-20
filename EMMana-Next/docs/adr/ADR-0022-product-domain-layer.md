# ADR-0022 — Separate Product Domain from EM solver model

Status: Accepted  
Date: 2026-09-20

## Context
EMMana-Next is expanding from a solver prototype into an engineering antenna product. Adding templates, measurements, reports, job management and workflow metadata directly into .emnx would couple product behavior to solver contracts and create layering risk.

## Decision
Keep .emnx as the physical solver model. Introduce a Product Domain layer above it.

Domain chain:
Product Project → Design Model → Analysis Plan → Execution → Evidence Bundle → Measurement Set → Report/Release.

The new Analysis Plan carries requested analyses, optimisation goals and verification policy. Product registry exposes capabilities and trust levels. Future measurement and reporting features must reference solver results rather than overwrite them.

## Consequences
- solver can evolve or be replaced independently;
- multiple backends can share one product workflow;
- evidence status is explicit;
- UI can be redesigned without changing solver schemas;
- product metadata does not affect stable model hash unless it changes the physical EM model.

## Alternatives rejected
- add all workflow fields to project.schema.json;
- store UI state inside .emnx;
- build measurement/report logic directly into the solver CLI.
