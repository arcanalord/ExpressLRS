#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${EMNEXT_BUILD_DIR:-$ROOT/build-linux}"
PORT="${EMNEXT_PORT:-8787}"
HOST="${EMNEXT_HOST:-127.0.0.1}"
echo "[1/3] Configure EMMana-Next"
cmake -S "$ROOT" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
echo "[2/3] Build"
cmake --build "$BUILD" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
echo "[3/3] Launch Linux UI"
echo "Open: http://$HOST:$PORT"
exec python3 "$ROOT/apps/linux_web/server.py" --host "$HOST" --port "$PORT" --binary "$BUILD/emnext"
