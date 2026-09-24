from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
vendor=root/'assets/map_runtime/vendor'
expected={
 'maplibre-gl.mjs':'454e0bbb16c721cfbf952a92ff3e4362130346ed59a5bff56ae5d6fbebb651f7',
 'maplibre-gl-shared.mjs':'0996a0ff2ecb2807afc3f053992539ff7fe45c1678a02304b2b33120136f81f3',
 'maplibre-gl-worker.mjs':'7d5ebf88ec25a72cc48cc320d374f41d921e5105d2f1fc774d463a4b68164227',
 'maplibre-gl.css':'8e2dbbab312dc57656fbb76e9fa5308c75c9d7c7ba5808a7d55bcdb64cc813fa',
 'pmtiles.js':'caf981bc46f6327ee7e65d5dc964d89d38a69f60edca2bd4c5c890c21b554c6c',
}
missing=[]; bad=[]
for name,digest in expected.items():
    path=vendor/name
    if not path.is_file(): missing.append(name); continue
    actual=hashlib.sha256(path.read_bytes()).hexdigest()
    if actual!=digest: bad.append((name,actual,digest))
if missing:
    raise SystemExit('MAP_VENDOR_GATE_FAIL missing: '+', '.join(missing))
if bad:
    raise SystemExit('MAP_VENDOR_GATE_FAIL hash mismatch: '+repr(bad))
print('MESH_MESSENGER_MAP_VENDOR_GATE_PASS')
