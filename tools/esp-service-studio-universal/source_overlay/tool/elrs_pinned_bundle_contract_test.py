from __future__ import annotations

import os
import io
import json
import urllib.request
import zipfile
from pathlib import Path

SERVICE = Path("android_overlay/OfficialElrsService.kt").read_text(encoding="utf-8")
PINNED_TAG = "4.1.0"
PINNED_SHA = "a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6"

offline_checks = {
    "latest release endpoint": "releases/latest" in SERVICE,
    "commit resolution": "COMMITS_API" in SERVICE,
    "artifactory bundle": "artifactory.expresslrs.org/ExpressLRS" in SERVICE,
    "targets entry": 'firmware/hardware/targets.json' in SERVICE,
    "same-bundle hardware source": 'same firmware.zip commit' in SERVICE,
    "hardware pinned result": '"hardwarePinned" to true' in SERVICE,
    "firmware sha256": '"sha256"' in SERVICE and "sha256(configured)" in SERVICE,
    "esp8285 gate": 'platform == "esp8285"' in SERVICE,
    "uart gate": 'methods.contains("uart")' in SERVICE,
}

failed = [name for name, ok in offline_checks.items() if not ok]
if failed:
    raise SystemExit("ExpressLRS offline contract failed: " + ", ".join(failed))

print(
    "ExpressLRS pinned bundle offline contract PASS "
    f"(reference tag={PINNED_TAG}, commit={PINNED_SHA[:12]})"
)

if os.getenv("ELRS_ONLINE_CONTRACT") != "1":
    raise SystemExit(0)

UA = {"User-Agent": "ESP-Service-Studio-contract-test"}
CACHE = "https://artifactory.expresslrs.org/ExpressLRS"


def get_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as response:
        return response.read()


def target(root: dict, path: str) -> dict:
    node = root
    for part in path.split("."):
        node = node[part]
    return node


def check_target(root: dict, names: set[str], path: str) -> None:
    cfg = target(root, path)
    product = cfg["product_name"]
    platform = cfg["platform"]
    firmware = cfg["firmware"]
    methods = cfg.get("upload_methods", [])
    layout = cfg["layout_file"]
    category = path.split(".")[1]
    hw_dir = "TX" if category.startswith("tx_") else "RX"

    assert product
    assert platform == "esp8285", (path, platform)
    assert firmware.startswith("Unified_ESP8285_"), (path, firmware)
    assert "uart" in methods, (path, methods)
    assert f"firmware/hardware/{hw_dir}/{layout}" in names, (path, layout)

    if "2400" in category:
        assert f"firmware/FCC/{firmware}/firmware.bin" in names, path
        assert f"firmware/LBT/{firmware}/firmware.bin" in names, path
    elif "900" in category:
        assert f"firmware/FCC/{firmware}/firmware.bin" in names, path


bundle = get_bytes(f"{CACHE}/{PINNED_SHA}/firmware.zip")
assert len(bundle) > 1_000_000, len(bundle)

with zipfile.ZipFile(io.BytesIO(bundle)) as zf:
    names = set(zf.namelist())
    targets_name = "firmware/hardware/targets.json"
    assert targets_name in names
    root = json.loads(zf.read(targets_name).decode("utf-8"))

    check_target(root, names, "happymodel.rx_2400.ep")
    check_target(root, names, "betafpv.rx_2400.nano")
    check_target(root, names, "betafpv.rx_900.nano")

print(
    "ExpressLRS pinned bundle ONLINE contract PASS "
    f"(tag={PINNED_TAG}, commit={PINNED_SHA[:12]}, size={len(bundle)})"
)
