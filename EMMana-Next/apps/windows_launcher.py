#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import runpy
import sys
import threading
import time
import webbrowser
from pathlib import Path


def runtime_root() -> Path:
    bundle = getattr(sys, "_MEIPASS", None)
    if bundle:
        return Path(bundle) / "EMMana-Next"
    return Path(__file__).resolve().parents[1]


def solver_binary(root: Path) -> Path:
    candidates = [
        root / "emnext.exe",
        root / "build-win" / "Release" / "emnext.exe",
        root / "build-linux" / "emnext",
        root / "build" / "emnext",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("EMMana-Next solver binary not found in portable bundle")


def default_cache_dir() -> Path:
    base = Path(os.environ.get("LOCALAPPDATA") or Path.home())
    return base / "EMMana-Next" / "cache"


def open_browser_later(url: str, delay: float = 1.0) -> None:
    def worker() -> None:
        time.sleep(delay)
        try:
            webbrowser.open(url, new=1)
        except Exception:
            pass
    threading.Thread(target=worker, daemon=True).start()


def main() -> int:
    parser = argparse.ArgumentParser(description="EMMana-Next portable Windows launcher")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--cache-dir", default=str(default_cache_dir()))
    args = parser.parse_args()

    root = runtime_root()
    server = root / "apps" / "linux_web" / "server.py"
    binary = solver_binary(root)
    if not server.exists():
        raise SystemExit(f"Bundled UI server not found: {server}")

    url = f"http://{args.host}:{args.port}"
    if not args.no_browser:
        open_browser_later(url)

    sys.argv = [
        str(server),
        "--host", args.host,
        "--port", str(args.port),
        "--binary", str(binary),
        "--cache-dir", str(Path(args.cache_dir).expanduser()),
    ]
    runpy.run_path(str(server), run_name="__main__")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
