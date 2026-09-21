#!/usr/bin/env python3
from pathlib import Path
from collections import Counter
import re
import sys

root = Path(sys.argv[1]).resolve()

def fail(msg):
    raise SystemExit("SOURCE_AUDIT_FAIL: " + msg)

# Old/current ambiguity must not exist in release source root.
legacy_patterns = [
    "CURRENT_*.md", "STATUS_*.md", "RECHECK*.md", "WORKLOG*.md",
    "SOURCE_SHA256_*.txt", "PHONEAPI_SUBSET_*.md", "UX_CORE_*.md",
    "ANDROID_RUNTIME_*.md", "ANDROID_BLE_*.md", "PHONE_FEEDBACK_*.md",
]
for pat in legacy_patterns:
    hits = list(root.glob(pat))
    if hits:
        fail(f"legacy root files remain for {pat}: {[p.name for p in hits[:5]]}")

if (root / "android").exists():
    fail("legacy duplicate android/ source tree still exists")

pairs = [
    ("index.html", "android-app/app/src/main/assets/www/index.html"),
    ("src/app.js", "android-app/app/src/main/assets/www/src/app.js"),
    ("src/core.js", "android-app/app/src/main/assets/www/src/core.js"),
    ("src/help-registry.js", "android-app/app/src/main/assets/www/src/help-registry.js"),
    ("src/styles.css", "android-app/app/src/main/assets/www/src/styles.css"),
    ("src/navigation-controller.js", "android-app/app/src/main/assets/www/src/navigation-controller.js"),
    ("src/app-bootstrap.js", "android-app/app/src/main/assets/www/src/app-bootstrap.js"),
]
for a,b in pairs:
    pa,pb=root/a,root/b
    if not pa.exists() or not pb.exists() or pa.read_bytes()!=pb.read_bytes():
        fail(f"shared/Android parity failed: {a} != {b}")

html=(root/"index.html").read_text(encoding="utf-8")
ids=re.findall(r'\bid=["\']([^"\']+)["\']',html)
dup_ids=[k for k,v in Counter(ids).items() if v>1]
if dup_ids:
    fail(f"duplicate HTML ids: {dup_ids[:10]}")

app=(root/"src/app.js").read_text(encoding="utf-8")
funcs=re.findall(r'(?m)^\s*(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(',app)
dup_funcs=[k for k,v in Counter(funcs).items() if v>1]
if dup_funcs:
    fail(f"duplicate function declarations: {dup_funcs[:10]}")

if "appVersion:'1.5.5'" in app:
    fail("stale runtime appVersion 1.5.5 remains")

ble_test=(root/"tests/android_ble_contract.sh").read_text(encoding="utf-8")
if "/android/src/" in ble_test or "/android/tests/" in ble_test:
    fail("BLE contract test still depends on legacy android/ tree")

print(f"SOURCE_AUDIT_PASS app_lines={len(app.splitlines())} functions={len(funcs)} html_ids={len(ids)}")
