#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from pathlib import Path

root=Path(sys.argv[1])
reg=json.loads((root/"apps/shared/product/product-registry.json").read_text(encoding="utf-8"))
assert reg["schema_version"]=="0.1"
assert reg["layer"]=="product-domain"
ids={x["id"] for x in reg["workflow"]}
assert {"project","design-model","analysis-plan","solve","evidence","measurement","report"} <= ids
trust={x["id"] for x in reg["trust_levels"]}
assert trust=={"experimental","characterized","reference-validated","release-authoritative"}
assert any("Measured data never overwrites simulated data."==x for x in reg["invariants"])
plan=json.loads((root/"workflows/B04_yagi.analysis.json").read_text(encoding="utf-8"))
assert plan["schema_version"]=="0.1"
assert plan["verification_policy"]["trust_target"]=="reference-validated"
assert "reference-compare" in plan["requests"]
print("PRODUCT DOMAIN REGISTRY PASS")
