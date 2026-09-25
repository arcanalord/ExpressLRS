from __future__ import annotations

import io
import json
import sys
import urllib.request
import zipfile

UA = {"User-Agent": "ESP-Service-Studio-alpha10-contract-test"}
LATEST = "https://api.github.com/repos/ExpressLRS/ExpressLRS/releases/latest"
COMMITS = "https://api.github.com/repos/ExpressLRS/ExpressLRS/commits/"
CACHE = "https://artifactory.expresslrs.org/ExpressLRS"


def get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def get_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


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

    assert platform == "esp8285", (path, platform)
    assert firmware.startswith("Unified_ESP8285_"), (path, firmware)
    assert "uart" in methods, (path, methods)
    assert f"firmware/hardware/{hw_dir}/{layout}" in names, (path, layout)

    if "2400" in category:
        assert f"firmware/FCC/{firmware}/firmware.bin" in names, path
        assert f"firmware/LBT/{firmware}/firmware.bin" in names, path
    elif "900" in category:
        assert f"firmware/FCC/{firmware}/firmware.bin" in names, path


release = get_json(LATEST)
tag = release["tag_name"]
commit = get_json(COMMITS + tag)
sha = commit["sha"]

bundle = get_bytes(f"{CACHE}/{sha}/firmware.zip")
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
    "ExpressLRS pinned bundle contract PASS "
    f"(tag={tag}, commit={sha[:12]}, size={len(bundle)})"
)
