from __future__ import annotations

import hashlib
import json
import math
from typing import Any


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _with_fingerprint(payload: dict) -> dict:
    out = dict(payload)
    out["immutability"] = {
        "fingerprint_algorithm": "sha256-canonical-json-v1",
        "fingerprint": sha256_json(payload),
    }
    return out


def verify_fingerprint(value: dict) -> bool:
    imm = value.get("immutability") or {}
    expected = imm.get("fingerprint")
    if not isinstance(expected, str):
        return False
    payload = {k: v for k, v in value.items() if k != "immutability"}
    return expected == sha256_json(payload)


def create_design_variant(
    variant_id: str,
    name: str,
    model_hash: str,
    model_hash_algorithm: str = "fnv1a64-emnext-model-v3",
    parent_variant_id: str | None = None,
    tags: list[str] | None = None,
    notes: str = "",
) -> dict:
    variant_id = str(variant_id).strip()
    name = str(name).strip()
    model_hash = str(model_hash).strip()
    if not variant_id or not name or not model_hash:
        raise ValueError("variant_id, name and model_hash are required")
    payload = {
        "schema_version": "0.1",
        "variant_id": variant_id,
        "name": name,
        "model_ref": {
            "model_hash_algorithm": str(model_hash_algorithm),
            "model_hash": model_hash,
        },
        "lineage": {
            "parent_variant_id": str(parent_variant_id).strip() if parent_variant_id else None,
        },
        "annotations": {
            "tags": sorted({str(x).strip() for x in (tags or []) if str(x).strip()}),
            "notes": str(notes),
        },
    }
    return _with_fingerprint(payload)


def create_measurement_set(
    measurement_id: str,
    variant: dict,
    measurement: dict,
    raw_text: str,
    calibration: dict | None = None,
    provenance: dict | None = None,
) -> dict:
    if not verify_fingerprint(variant):
        raise ValueError("design variant fingerprint is invalid")
    measurement_id = str(measurement_id).strip()
    if not measurement_id:
        raise ValueError("measurement_id is required")
    samples = measurement.get("samples")
    if not isinstance(samples, list) or not samples:
        raise ValueError("measurement samples are required")
    source = measurement.get("source") or {}
    variant_ref = {
        "variant_id": variant["variant_id"],
        "variant_fingerprint": variant["immutability"]["fingerprint"],
        "model_hash_algorithm": variant["model_ref"]["model_hash_algorithm"],
        "expected_model_hash": variant["model_ref"]["model_hash"],
    }
    normalized_payload = {
        "parameter": measurement.get("parameter", "S11"),
        "reference_impedance_ohm": float(measurement.get("reference_impedance_ohm", 50.0)),
        "samples": samples,
    }
    payload = {
        "schema_version": "0.2",
        "measurement_id": measurement_id,
        "variant_ref": variant_ref,
        "source": {
            "format": str(source.get("format", "unknown")),
            "name": str(source.get("name", "measurement")),
            "profile": source.get("profile"),
            "raw_sha256": sha256_text(raw_text),
        },
        "normalized": {
            "parameter": normalized_payload["parameter"],
            "reference_impedance_ohm": normalized_payload["reference_impedance_ohm"],
            "sample_count": len(samples),
            "data_sha256": sha256_json(normalized_payload),
        },
        "calibration": {
            "type": str((calibration or {}).get("type", "unknown")),
            "reference_plane_note": str((calibration or {}).get("reference_plane_note", "")),
            "fixture_deembedded": bool((calibration or {}).get("fixture_deembedded", False)),
        },
        "provenance": {
            "instrument_or_source": str((provenance or {}).get("instrument_or_source", source.get("name", "unknown"))),
            "operator": str((provenance or {}).get("operator", "")),
            "measured_at": str((provenance or {}).get("measured_at", "")),
            "notes": str((provenance or {}).get("notes", "")),
        },
    }
    return _with_fingerprint(payload)


def _finite(value):
    try:
        x = float(value)
        return x if math.isfinite(x) else None
    except (TypeError, ValueError):
        return None


def generate_engineering_report(
    variant: dict,
    measurement_set: dict,
    sweep: dict,
    measurement: dict,
    comparison: dict,
    reference_status: dict | None = None,
) -> dict:
    if not verify_fingerprint(variant):
        raise ValueError("design variant fingerprint is invalid")
    if not verify_fingerprint(measurement_set):
        raise ValueError("measurement set fingerprint is invalid")
    vref = measurement_set.get("variant_ref") or {}
    if vref.get("variant_id") != variant.get("variant_id"):
        raise ValueError("measurement set belongs to another design variant")
    if vref.get("expected_model_hash") != variant.get("model_ref", {}).get("model_hash"):
        raise ValueError("measurement set model hash does not match design variant")
    samples = sweep.get("samples") or []
    msamples = measurement.get("samples") or []
    if not samples or not msamples:
        raise ValueError("simulation and measurement samples are required")
    rs = reference_status or {}
    independent = rs.get("independent_reference") or {}
    release = rs.get("release_status") or {}
    corr = comparison.get("summary") or {}
    payload = {
        "schema_version": "0.1",
        "variant_ref": {
            "variant_id": variant["variant_id"],
            "variant_fingerprint": variant["immutability"]["fingerprint"],
            "model_hash_algorithm": variant["model_ref"]["model_hash_algorithm"],
            "model_hash": variant["model_ref"]["model_hash"],
        },
        "measurement_ref": {
            "measurement_id": measurement_set["measurement_id"],
            "measurement_fingerprint": measurement_set["immutability"]["fingerprint"],
            "raw_sha256": measurement_set["source"]["raw_sha256"],
            "normalized_data_sha256": measurement_set["normalized"]["data_sha256"],
        },
        "simulation": {
            "solver_id": sweep.get("solver_id"),
            "solver_version": sweep.get("solver_version"),
            "linear_solver_backend": sweep.get("linear_solver_backend"),
            "points": len(samples),
            "start_frequency_hz": _finite(samples[0].get("frequency_hz")),
            "stop_frequency_hz": _finite(samples[-1].get("frequency_hz")),
            "resonance_frequency_hz": _finite(sweep.get("resonance_frequency_hz")),
            "min_s11_db": _finite(sweep.get("min_s11_db")),
            "min_s11_frequency_hz": _finite(sweep.get("min_s11_frequency_hz")),
        },
        "measurement": {
            "source": measurement.get("source"),
            "reference_impedance_ohm": _finite(measurement.get("reference_impedance_ohm")),
            "points": len(msamples),
            "calibration": measurement_set.get("calibration"),
            "provenance": measurement_set.get("provenance"),
        },
        "correlation": {
            "overlap": comparison.get("overlap"),
            "delta_r_ohm": corr.get("delta_r_ohm"),
            "delta_x_ohm": corr.get("delta_x_ohm"),
            "delta_s11_db": corr.get("delta_s11_db"),
            "delta_vswr": corr.get("delta_vswr"),
            "measurement_resonance_hz": _finite(corr.get("measurement_resonance_hz")),
            "simulation_resonance_hz": _finite(corr.get("simulation_resonance_hz")),
            "resonance_shift_hz": _finite(corr.get("resonance_shift_hz")),
        },
        "evidence": {
            "reference_engine": independent.get("engine"),
            "reference_ci_status": independent.get("ci_status"),
            "strict_gate": independent.get("strict_gate"),
            "ground_reference_status": independent.get("ground_reference_status"),
            "loss_load_reference_status": independent.get("loss_load_reference_status"),
            "authoritative_release_status": release.get("authoritative_engineering_release"),
            "windows_verification": release.get("windows_verification"),
        },
        "limitations": [
            "Measurement correlation is evidence for this exact DesignVariant/model hash only.",
            "Measured data does not modify or replace simulated data.",
            "Finite-ground results are not authoritative while the independent ground reference status is not accepted.",
            "A generated report does not promote a solver scope beyond its recorded release gates.",
        ],
    }
    report = _with_fingerprint(payload)
    report["markdown"] = render_report_markdown(report)
    return report


def render_report_markdown(report: dict) -> str:
    vr = report["variant_ref"]
    mr = report["measurement_ref"]
    sim = report["simulation"]
    meas = report["measurement"]
    corr = report["correlation"]
    ev = report["evidence"]

    def fmt(v, scale=1.0, digits=3):
        x = _finite(v)
        return "—" if x is None else f"{x / scale:.{digits}f}"

    lines = [
        f"# EMMana-Next Engineering Report — {vr['variant_id']}",
        "",
        "## Identity",
        f"- Model hash: {vr['model_hash']} ({vr['model_hash_algorithm']})",
        f"- Variant fingerprint: {vr['variant_fingerprint']}",
        f"- Measurement: {mr['measurement_id']}",
        f"- Measurement fingerprint: {mr['measurement_fingerprint']}",
        "",
        "## Simulation",
        f"- Sweep: {fmt(sim['start_frequency_hz'], 1e6)}–{fmt(sim['stop_frequency_hz'], 1e6)} MHz / {sim['points']} points",
        f"- Resonance marker: {fmt(sim['resonance_frequency_hz'], 1e6, 6)} MHz",
        f"- Minimum S11: {fmt(sim['min_s11_db'], 1.0, 2)} dB @ {fmt(sim['min_s11_frequency_hz'], 1e6, 6)} MHz",
        f"- Solver: {sim.get('solver_id') or '—'} {sim.get('solver_version') or ''}".rstrip(),
        "",
        "## Measurement",
        f"- Source: {(meas.get('source') or {}).get('name', '—')}",
        f"- Format/profile: {(meas.get('source') or {}).get('format', '—')} / {(meas.get('source') or {}).get('profile') or '—'}",
        f"- Reference impedance: {fmt(meas.get('reference_impedance_ohm'), 1.0, 2)} ohm",
        f"- Samples: {meas.get('points', 0)}",
        "",
        "## Correlation",
        f"- Overlap points: {(corr.get('overlap') or {}).get('points', '—')}",
        f"- max |ΔR|: {fmt((corr.get('delta_r_ohm') or {}).get('max_abs'), 1.0, 3)} ohm",
        f"- max |ΔX|: {fmt((corr.get('delta_x_ohm') or {}).get('max_abs'), 1.0, 3)} ohm",
        f"- max |ΔS11|: {fmt((corr.get('delta_s11_db') or {}).get('max_abs'), 1.0, 3)} dB",
        f"- Resonance shift: {fmt(corr.get('resonance_shift_hz'), 1e3, 3)} kHz",
        "",
        "## Evidence status",
        f"- Independent reference: {ev.get('reference_engine') or '—'} / {ev.get('reference_ci_status') or '—'}",
        f"- Strict gate: {ev.get('strict_gate') or '—'}",
        f"- Finite ground: {ev.get('ground_reference_status') or '—'}",
        f"- Loss/load: {ev.get('loss_load_reference_status') or '—'}",
        f"- Authoritative release: {ev.get('authoritative_release_status') or '—'}",
        f"- Windows: {ev.get('windows_verification') or '—'}",
        "",
        "## Limitations",
    ]
    lines += [f"- {x}" for x in report.get("limitations", [])]
    return "\n".join(lines) + "\n"
