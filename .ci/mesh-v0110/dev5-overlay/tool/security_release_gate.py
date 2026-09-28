#!/usr/bin/env python3
"""Mesh Messenger production security release gate.

This gate is intentionally stricter than the development build. It is not a
cryptographic implementation. It prevents a public/release artifact from being
declared ready while known security boundaries are still missing.
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path


def fail(results: list[tuple[str, bool, str]], gate: str, detail: str) -> None:
    results.append((gate, False, detail))


def passed(results: list[tuple[str, bool, str]], gate: str, detail: str) -> None:
    results.append((gate, True, detail))


def read(path: Path) -> str:
    if not path.is_file():
        raise FileNotFoundError(path)
    return path.read_text(encoding="utf-8")


def source_checks(root: Path) -> list[tuple[str, bool, str]]:
    results: list[tuple[str, bool, str]] = []
    messenger = read(root / "lib/core/messenger_core.dart")
    delivery = read(root / "lib/core/delivery.dart")
    storage = read(root / "lib/core/app_storage.dart")
    m07 = read(root / "lib/core/m07_security.dart")
    manifest = read(root / "android/app/src/main/AndroidManifest.xml")

    contract_ok = (
        "abstract interface class M07CryptoProvider" in m07
        and "encryptDirect" in m07
        and "decryptDirect" in m07
    )
    (passed if contract_ok else fail)(
        results,
        "M07_CONTRACT_PRESENT",
        "M07CryptoProvider encrypt/decrypt contract present"
        if contract_ok
        else "M07CryptoProvider contract missing or incomplete",
    )

    # Known unsafe prototype paths. A production direct/private path must pass
    # through M07 before DeliveryManager/transport. General/open channel policy
    # is intentionally not tested here.
    direct_plaintext = (
        "delivery.sendText(" in messenger
        and "text: clean" in messenger
        and "payload: text" in delivery
    )
    group_plaintext = (
        "sendGroupText" in messenger
        and "payload: clean" in messenger
    )
    map_plaintext = (
        "sendMapPoint" in messenger
        and "payload: jsonEncode(point.toJson())" in messenger
    )
    m07_wired = (
        "m07_security.dart" in messenger
        and "M07CryptoProvider" in messenger
        and "encryptDirect" in messenger
        and "decryptDirect" in messenger
    )
    e2ee_ok = m07_wired and not direct_plaintext and not group_plaintext and not map_plaintext
    (passed if e2ee_ok else fail)(
        results,
        "PRIVATE_E2EE_WIRED",
        "Direct/private message path uses M07 before delivery"
        if e2ee_ok
        else "Known plaintext direct/group/map payload path still reaches DeliveryEnvelope",
    )

    plaintext_json_storage = (
        "messages.json" in storage
        and "outbox.json" in storage
        and "writeAsString" in storage
        and "JsonEncoder" in storage
    )
    (fail if plaintext_json_storage else passed)(
        results,
        "LOCAL_AT_REST_ENCRYPTION",
        "Prototype JSON messages/outbox are still written as plaintext"
        if plaintext_json_storage
        else "Known plaintext JSON storage pattern not present",
    )

    backup_hardened = (
        'android:allowBackup="false"' in manifest
        or "android:dataExtractionRules" in manifest
        or "android:fullBackupContent" in manifest
    )
    (passed if backup_hardened else fail)(
        results,
        "ANDROID_BACKUP_POLICY",
        "Explicit Android backup/data extraction policy present"
        if backup_hardened
        else "No explicit backup/data-extraction policy in main manifest",
    )

    return results


SECRET_PATTERNS: tuple[tuple[str, bytes], ...] = (
    ("PEM_PRIVATE_KEY", b"-----BEGIN PRIVATE KEY-----"),
    ("PEM_RSA_PRIVATE_KEY", b"-----BEGIN RSA PRIVATE KEY-----"),
    ("AWS_ACCESS_KEY", b"AKIA"),
    ("GITHUB_CLASSIC_TOKEN", b"ghp_"),
    ("SLACK_TOKEN", b"xoxb-"),
)


def apk_checks(apk: Path) -> list[tuple[str, bool, str]]:
    results: list[tuple[str, bool, str]] = []
    with zipfile.ZipFile(apk) as zf:
        names = set(zf.namelist())
        debug_payloads = [
            name
            for name in names
            if name.endswith("kernel_blob.bin")
            or name.endswith("libVkLayer_khronos_validation.so")
        ]
        (passed if not debug_payloads else fail)(
            results,
            "DEBUG_ARTIFACTS_REMOVED",
            "No Flutter kernel blob or Vulkan validation layer"
            if not debug_payloads
            else "Debug artifacts present: " + ", ".join(sorted(debug_payloads)),
        )

        findings: list[str] = []
        # High-confidence token scan only. This is a release tripwire, not a
        # replacement for a full secret scanner/SAST job.
        for info in zf.infolist():
            if info.file_size > 80 * 1024 * 1024:
                continue
            try:
                data = zf.read(info)
            except Exception:
                continue
            for label, pattern in SECRET_PATTERNS:
                if pattern in data:
                    findings.append(f"{label}:{info.filename}")
        (passed if not findings else fail)(
            results,
            "APK_NO_HIGH_CONFIDENCE_SECRET",
            "No high-confidence embedded secret markers found"
            if not findings
            else "Potential embedded secret markers: " + ", ".join(sorted(set(findings))),
        )
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="Flutter app root")
    parser.add_argument("--apk", help="Optional built APK to inspect")
    args = parser.parse_args()

    results = source_checks(Path(args.root).resolve())
    if args.apk:
        results.extend(apk_checks(Path(args.apk).resolve()))

    print("Mesh Messenger security release gate")
    print("=" * 40)
    for name, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name}: {detail}")

    failed = [name for name, ok, _ in results if not ok]
    if failed:
        print("\nSECURITY_RELEASE_BLOCKED=" + ",".join(failed))
        return 1
    print("\nSECURITY_RELEASE_SOURCE_GATES_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
