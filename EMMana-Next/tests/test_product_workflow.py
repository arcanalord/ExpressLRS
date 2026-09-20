#!/usr/bin/env python3
from __future__ import annotations
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "apps/shared/product"))
from measurement import parse_touchstone_s1p, compare_measurement_to_sweep
from workflow_artifacts import create_design_variant, create_measurement_set, generate_engineering_report, verify_fingerprint

raw = "# MHz S RI R 50\n285 0.10 0\n300 0.20 0\n315 0.10 0\n"
measurement = parse_touchstone_s1p(raw, "lab.s1p")
variant = create_design_variant("b01-lab-v1", "B01 lab correlation", "fnv1a64-test-model")
assert verify_fingerprint(variant)

mset = create_measurement_set(
    "b01-vna-001",
    variant,
    measurement,
    raw,
    {"type": "SOL", "reference_plane_note": "feed connector", "fixture_deembedded": False},
    {"instrument_or_source": "VNA fixture", "operator": "test"},
)
assert verify_fingerprint(mset)
assert mset["variant_ref"]["variant_id"] == variant["variant_id"]
assert mset["normalized"]["sample_count"] == 3

sweep = {
    "solver_id": "wire-mom-experimental",
    "solver_version": "test",
    "linear_solver_backend": "test",
    "resonance_frequency_hz": 300e6,
    "min_s11_db": -13.0,
    "min_s11_frequency_hz": 300e6,
    "samples": [
        {"frequency_hz": 285e6, "impedance_ohm": measurement["samples"][0]["impedance_ohm"], "s11": measurement["samples"][0]["s11"], "vswr": measurement["samples"][0]["vswr"]},
        {"frequency_hz": 300e6, "impedance_ohm": measurement["samples"][1]["impedance_ohm"], "s11": measurement["samples"][1]["s11"], "vswr": measurement["samples"][1]["vswr"]},
        {"frequency_hz": 315e6, "impedance_ohm": measurement["samples"][2]["impedance_ohm"], "s11": measurement["samples"][2]["s11"], "vswr": measurement["samples"][2]["vswr"]},
    ],
}
comparison = compare_measurement_to_sweep(measurement, sweep)
reference = {
    "independent_reference": {
        "engine": "nec2c",
        "ci_status": "pass",
        "strict_gate": "B01 PASS",
        "ground_reference_status": "characterization_measured_not_accepted",
        "loss_load_reference_status": "not_executed",
    },
    "release_status": {
        "authoritative_engineering_release": "blocked",
        "windows_verification": "build_pass_runtime_pending",
    },
}
report = generate_engineering_report(variant, mset, sweep, measurement, comparison, reference)
assert report["variant_ref"]["variant_id"] == "b01-lab-v1"
assert report["measurement_ref"]["measurement_id"] == "b01-vna-001"
assert report["correlation"]["delta_r_ohm"]["max_abs"] < 1e-9
assert "Finite ground" in report["markdown"]
assert "does not modify or replace simulated data" in report["markdown"]
assert verify_fingerprint({k: v for k, v in report.items() if k != "markdown"})

for name in ("design-variant-0.1.schema.json", "measurement-set-0.2.schema.json", "engineering-report-0.1.schema.json"):
    assert (root / "schemas" / name).exists()

print("PRODUCT WORKFLOW PASS", json.dumps({
    "variant": variant["immutability"]["fingerprint"],
    "measurement": mset["immutability"]["fingerprint"],
    "report": report["immutability"]["fingerprint"],
}, sort_keys=True))
