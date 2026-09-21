#!/usr/bin/env python3
from pathlib import Path
import re
import shutil
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: prepare_current_source.py ROOT VERSION VERSION_CODE")

root = Path(sys.argv[1]).resolve()
version = sys.argv[2]
version_code = int(sys.argv[3])

def read(rel):
    return (root / rel).read_text(encoding="utf-8")

def write(rel, text):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")

# One release identity for Gradle + runtime diagnostics.
build_rel = "android-app/app/build.gradle.kts"
build = read(build_rel)
build = re.sub(r"versionCode\s*=\s*\d+", f"versionCode = {version_code}", build, count=1)
build = re.sub(r'versionName\s*=\s*"[^"]+"', f'versionName = "{version}"', build, count=1)
write(build_rel, build)

for rel in ("src/app.js", "android-app/app/src/main/assets/www/src/app.js"):
    s = read(rel)
    if not re.search(r"appVersion:'[^']+'", s):
        raise SystemExit(f"appVersion field not found in {rel}")
    s = re.sub(r"appVersion:'[^']+'", f"appVersion:'{version}'", s, count=1)
    write(rel, s)

# Version assertions must verify shape/contracts, not freeze a historical release.
rel = "tests/android_app_source_check.sh"
s = read(rel)
s = re.sub(r"grep -q 'versionCode = \d+' \"\$APP/build.gradle.kts\"",
           "grep -Eq 'versionCode = [0-9]+' \"$APP/build.gradle.kts\"", s)
s = re.sub(r"grep -q 'versionName = \"[^\"]+\"' \"\$APP/build.gradle.kts\"",
           "grep -Eq 'versionName = \"[0-9]+\\.[0-9]+\\.[0-9]+\"' \"$APP/build.gradle.kts\"", s)
write(rel, s)

rel = "tests/ui_compact_batch_a.test.py"
s = read(rel)
if "import re" not in s:
    s = s.replace("from pathlib import Path\n", "from pathlib import Path\nimport re\n", 1)
s = re.sub(r"'runtime version': .*?,\n",
           """'runtime version': bool(re.search(r"appVersion:'[0-9]+\\.[0-9]+\\.[0-9]+'", app)),\n""", s, count=1)
s = re.sub(r"'android versionName': .*?,\n",
           """'android versionName': bool(re.search(r'versionName = "[0-9]+\\.[0-9]+\\.[0-9]+"', build)),\n""", s, count=1)
s = re.sub(r"'android versionCode': .*?,\n",
           """'android versionCode': bool(re.search(r'versionCode = [0-9]+', build)),\n""", s, count=1)
write(rel, s)

rel = "tests/help_ui_v15.py"
s = read(rel)
s = re.sub(r"assert diag\['appVersion'\]=='[^']+'",
           lambda _m: "assert re.fullmatch(r'\\d+\\.\\d+\\.\\d+',diag['appVersion'])", s, count=1)
write(rel, s)

# Remove duplicate Android source owner. The contract test now targets production android-app sources.
legacy_test = root / "android/tests/BleTransportContractTest.kt"
new_test = root / "tests/android/BleTransportContractTest.kt"
new_test.parent.mkdir(parents=True, exist_ok=True)
if legacy_test.exists():
    shutil.copy2(legacy_test, new_test)
elif not new_test.exists():
    raise SystemExit("BLE contract test source not found")

rel = "tests/android_ble_contract.sh"
s = read(rel)
s = s.replace(
    '"$ROOT"/android/src/main/kotlin/org/fpvclub/mesh/ble/MeshtasticBleUuids.kt "$ROOT"/android/src/main/kotlin/org/fpvclub/mesh/ble/MeshtasticBleRadioTransport.kt "$ROOT"/android/tests/BleTransportContractTest.kt',
    '"$ROOT"/android-app/app/src/main/kotlin/org/fpvclub/mesh/ble/MeshtasticBleUuids.kt "$ROOT"/android-app/app/src/main/kotlin/org/fpvclub/mesh/ble/MeshtasticBleRadioTransport.kt "$ROOT"/tests/android/BleTransportContractTest.kt'
)
write(rel, s)

legacy_android = root / "android"
if legacy_android.exists():
    shutil.rmtree(legacy_android)

# Root documentation in historical source bundles had many mutually-conflicting CURRENT/STATUS files.
# Dropbox remains project-history storage; release source contains one current README only.
remove_patterns = [
    "CURRENT_*.md", "STATUS_*.md", "RECHECK*.md", "WORKLOG*.md",
    "SOURCE_SHA256_*.txt", "PHONEAPI_SUBSET_*.md", "UX_CORE_*.md",
    "ANDROID_RUNTIME_*.md", "ANDROID_BLE_*.md", "PHONE_FEEDBACK_*.md",
    "ARCHITECTURE_*.md", "PORTING_PLAN.md", "QA_*.log", "TEST_CASES.md",
]
for pattern in remove_patterns:
    for p in root.glob(pattern):
        if p.is_file():
            p.unlink()

readme = f"""# Mesh Messenger source {version}

This archive is the clean current source candidate.

## Source owners

- `src/app.js` — shared application/presentation coordinator.
- `src/core.js` — shared domain state and delivery/file/track primitives.
- `src/transports/` — Meshtastic/PhoneAPI transport adapters.
- `src/help-registry.js` — single Help Registry.
- `android-app/` — Android host and generated/shared WebView asset copy.
- `tests/` — regression and contract tests.
- `tools/sync_android_assets.sh` — root web source -> Android WebView sync.

## Ownership rule

Root web assets are the editable shared source.
Android WebView assets must remain byte-identical copies.
Do not edit both trees independently.

## Current candidate

- versionName: {version}
- versionCode: {version_code}
- Map: OSM online + local-grid fallback.
- Explicit phone-position request from Map.
- Meshtastic/PhoneAPI/BLE delivery path retained.

Project history, roadmap, architecture decisions and worklogs live in Dropbox:
`/FPV Club Research/Mesh Messenger`.

## QA

Run:
`./qa-linux.sh`

Release CI additionally verifies Android build, APK signature/alignment, source parity,
map zero-data/offline/recovery contracts, and clean-source rules.
"""
write("README.md", readme)

print(f"PREPARE_CURRENT_SOURCE_PASS version={version} code={version_code}")
