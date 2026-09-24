#!/usr/bin/env python3
from pathlib import Path
import hashlib
import urllib.request
import sys

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'assets' / 'map_runtime' / 'vendor'
VENDOR.mkdir(parents=True, exist_ok=True)

FILES = {
    'maplibre-gl.mjs': (
        'https://cdn.jsdelivr.net/npm/maplibre-gl@6.10.0/dist/maplibre-gl.mjs',
        '454e0bbb16c721cfbf952a92ff3e4362130346ed59a5bff56ae5d6fbebb651f7',
    ),
    'maplibre-gl-shared.mjs': (
        'https://cdn.jsdelivr.net/npm/maplibre-gl@6.10.0/dist/maplibre-gl-shared.mjs',
        '0996a0ff2ecb2807afc3f053992539ff7fe45c1678a02304b2b33120136f81f3',
    ),
    'maplibre-gl-worker.mjs': (
        'https://cdn.jsdelivr.net/npm/maplibre-gl@6.10.0/dist/maplibre-gl-worker.mjs',
        '7d5ebf88ec25a72cc48cc320d374f41d921e5105d2f1fc774d463a4b68164227',
    ),
    'maplibre-gl.css': (
        'https://cdn.jsdelivr.net/npm/maplibre-gl@6.10.0/dist/maplibre-gl.css',
        '8e2dbbab312dc57656fbb76e9fa5308c75c9d7c7ba5808a7d55bcdb64cc813fa',
    ),
    'pmtiles.js': (
        'https://cdn.jsdelivr.net/npm/pmtiles@4.5.0/dist/pmtiles.js',
        'caf981bc46f6327ee7e65d5dc964d89d38a69f60edca2bd4c5c890c21b554c6c',
    ),
}

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

for name, (url, expected) in FILES.items():
    path = VENDOR / name
    if path.exists() and sha256(path.read_bytes()) == expected:
        print(f'OK cached {name}')
        continue
    print(f'GET {name}')
    req = urllib.request.Request(url, headers={'User-Agent':'MeshMessenger-build/0.1.10-dev.4'})
    with urllib.request.urlopen(req, timeout=90) as response:
        data = response.read()
    actual = sha256(data)
    if actual != expected:
        print(f'HASH FAIL {name}: {actual} != {expected}', file=sys.stderr)
        raise SystemExit(2)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_bytes(data)
    tmp.replace(path)
    print(f'OK {name} {len(data)} bytes')
print('MESH_MESSENGER_MAP_VENDOR_FETCH_PASS')
