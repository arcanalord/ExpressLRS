#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from pathlib import Path
root=Path(sys.argv[1])
templates=json.loads((root/"apps/shared/product/template-registry.json").read_text(encoding="utf-8"))
materials=json.loads((root/"apps/shared/product/materials-registry.json").read_text(encoding="utf-8"))
example=json.loads((root/"measurements/examples/B01_vna.measurement.json").read_text(encoding="utf-8"))
assert templates["synthesis_method"]=="frequency-scale-seed-v1"
assert {"halfwave-dipole","quarterwave-monopole-pec","yagi-3el","square-loop"} <= {x["id"] for x in templates["templates"] if x["status"]=="implemented"}
assert next(x for x in templates["templates"] if x["id"]=="patch")["status"]=="unsupported-current-solver"
assert next(x for x in materials["ground_profiles"] if x["id"]=="average-ground")["trust"]=="characterized-not-accepted"
assert example["assets"][0]["format"]=="touchstone-s1p"
assert example["provenance"]["instrument_or_source"]=="example-placeholder"
print("PRODUCT ASSETS PASS")
