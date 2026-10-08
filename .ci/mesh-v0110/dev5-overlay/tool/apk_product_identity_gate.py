#!/usr/bin/env python3
"""Fail-closed Flutter RC8 product identity gate for SOURCE and built APK.

The pinned dev3 source ZIP is overlaid with dev5-overlay before the build.
Checking launcher resource *files* is insufficient: an APK can package the
files but omit android:icon in the merged manifest.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
APP_ID = "org.fpvclub.mesh.flutter"
APP_LABEL = "Mesh Messenger"
EXPECTED_VERSION = "0.6.0-secure-core-rc8"
EXPECTED_BUILD = "26102109"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def field(line: str, name: str) -> str:
    match = re.search(r"\b" + re.escape(name) + r"='([^']*)'", line)
    require(match is not None, f"Badging missing {name}: {line}")
    return match.group(1)


def check_badging(badging: str, version: str, build: str) -> None:
    lines = badging.splitlines()
    required = ("package:", "application:", "launchable-activity:")
    found = {}
    for prefix in required:
        row = next((line for line in lines if line.startswith(prefix)), None)
        require(row is not None, f"aapt dump badging missing {prefix}")
        found[prefix] = row

    package = found["package:"]
    require(field(package, "name") == APP_ID, "Unexpected applicationId")
    require(field(package, "versionName") == version, "APK versionName drift")
    require(field(package, "versionCode") == build, "APK versionCode drift")

    application = found["application:"]
    require(field(application, "label") == APP_LABEL, "Wrong application label")
    require(field(application, "icon") not in ("", "0x0"), "Launcher icon is empty")

    launchable = found["launchable-activity:"]
    require(field(launchable, "name").endswith(".MainActivity"),
            "Unexpected launcher activity")
    require(field(launchable, "icon") not in ("", "0x0"),
            "Launcher activity has no inherited icon")


def check_sources(manifest_path: Path, pubspec_path: Path,
                  build_info_path: Path) -> tuple[str, str]:
    app = ET.parse(manifest_path).getroot().find("application")
    require(app is not None, "No Android <application>")
    require(app.get(ANDROID + "label") == APP_LABEL, "Source label mismatch")
    require(app.get(ANDROID + "icon") == "@mipmap/ic_launcher",
            "Source launcher icon missing")
    require(app.get(ANDROID + "roundIcon") == "@mipmap/ic_launcher_round",
            "Source round icon missing")
    activity = app.find("activity")
    require(activity is not None and activity.get(ANDROID + "name") == ".MainActivity",
            "Source launcher MainActivity not found")

    pubspec = pubspec_path.read_text(encoding="utf-8")
    match = re.search(r"(?m)^version:\s*([^\s+]+)\+([0-9]+)\s*$", pubspec)
    require(match is not None, "pubspec version+build not found")
    version, build = match.groups()
    require(version == EXPECTED_VERSION, "Unexpected source version")
    require(build == EXPECTED_BUILD, "Unexpected source build number")

    build_info = build_info_path.read_text(encoding="utf-8")
    require(f"defaultValue: '{version}'" in build_info,
            "Settings/About fallback version differs from pubspec")
    require(f"defaultValue: '{build}'" in build_info,
            "Settings/About fallback build differs from pubspec")
    return version, build


def self_test() -> None:
    good = (
        "package: name='org.fpvclub.mesh.flutter' "
        "versionCode='26102109' versionName='0.6.0-secure-core-rc8'\n"
        "application: label='Mesh Messenger' "
        "icon='res/mipmap-anydpi-v26/ic_launcher.xml'\n"
        "launchable-activity: name='org.fpvclub.mesh.MainActivity' "
        "label='Mesh Messenger' icon='res/mipmap-anydpi-v26/ic_launcher.xml'\n"
    )
    check_badging(good, EXPECTED_VERSION, EXPECTED_BUILD)
    bad_cases = (
        good.replace("application: label='Mesh Messenger'", "application: label='Flutter'", 1),
        good.replace("versionCode='26102109'", "versionCode='26100108'", 1),
        good.replace("name='org.fpvclub.mesh.flutter'", "name='wrong.app'", 1),
        good.replace("application: label='Mesh Messenger' "
                     "icon='res/mipmap-anydpi-v26/ic_launcher.xml'",
                     "application: label='Mesh Messenger' icon=''", 1),
        good.replace("launchable-activity: name='org.fpvclub.mesh.MainActivity' "
                     "label='Mesh Messenger' icon='res/mipmap-anydpi-v26/ic_launcher.xml'",
                     "launchable-activity: name='org.fpvclub.mesh.MainActivity' "
                     "label='Mesh Messenger' icon=''", 1),
        good.replace("launchable-activity:", "non-launchable-activity:", 1),
    )
    for i, invalid in enumerate(bad_cases, 1):
        try:
            check_badging(invalid, EXPECTED_VERSION, EXPECTED_BUILD)
        except AssertionError:
            continue
        raise AssertionError(f"Negative badging sample {i} escaped the gate")
    print("APK_PRODUCT_IDENTITY_NEGATIVE_TESTS_PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--pubspec", type=Path)
    parser.add_argument("--build-info", type=Path)
    parser.add_argument("--badging", type=Path)
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    require(args.manifest is not None and args.pubspec is not None
            and args.build_info is not None, "Missing source paths")
    version, build = check_sources(args.manifest, args.pubspec, args.build_info)
    if args.source_only:
        print("APK_PRODUCT_IDENTITY_SOURCE_PASS")
        return
    require(args.badging is not None, "Missing --badging from real APK")
    check_badging(args.badging.read_text(encoding="utf-8"), version, build)
    print("APK_PRODUCT_IDENTITY_PASS")


if __name__ == "__main__":
    main()
