#!/usr/bin/env python3
from __future__ import annotations
import sys
from pathlib import Path

root = Path(sys.argv[1])
app = (root / "apps/linux_web/static/app.js").read_text(encoding="utf-8")

required = [
    "const surfaceState={sidebar:false,quickHelp:false,fullHelp:false};",
    "function syncSurfaceState()",
    "function showSurface(name)",
    "showSurface('sidebar')",
    "showSurface('quickHelp')",
    "showSurface('fullHelp')",
    "closeSurface('quickHelp')",
    "closeSurface('fullHelp')",
]
for marker in required:
    if marker not in app:
        raise SystemExit(f"missing single-surface owner marker: {marker}")

if app.count("document.body.style.overflow=") != 1:
    raise SystemExit("body scroll lock must have exactly one owner")

for forbidden in (
    "qh.hidden=false",
    "fh.hidden=false",
    "hb.hidden=false",
    "sidebar.classList.toggle('open',open)",
):
    if forbidden in app:
        raise SystemExit(f"direct surface mutation bypasses owner: {forbidden}")

print("UI SURFACE STATE PASS: sidebar/quick/full are mutually exclusive with one scroll-lock owner")
