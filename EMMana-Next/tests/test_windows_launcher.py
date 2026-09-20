#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import sys
from pathlib import Path

root=Path(sys.argv[1])
path=root/"apps/windows_launcher.py"
spec=importlib.util.spec_from_file_location("emnext_windows_launcher",path)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert mod.runtime_root()==root.resolve()
assert mod.default_cache_dir().name=="cache"
src=path.read_text(encoding="utf-8")
for marker in ("--no-browser","webbrowser.open","runpy.run_path","127.0.0.1","EMMana-Next"):
    assert marker in src, marker
print("WINDOWS LAUNCHER SOURCE PASS")
