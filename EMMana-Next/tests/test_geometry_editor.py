#!/usr/bin/env python3
from __future__ import annotations
import re, sys
from pathlib import Path
root=Path(sys.argv[1])
html=(root/'apps/linux_web/static/index.html').read_text(encoding='utf-8')
js=(root/'apps/linux_web/static/app.js').read_text(encoding='utf-8')
ids=re.findall(r'\bid="([^"]+)"',html)
dups=sorted({x for x in ids if ids.count(x)>1})
assert not dups, f'duplicate DOM ids: {dups}'
for marker in ('geometry-canvas','geometry-3d-canvas','geometry-3d-reset','geometry-add','geometry-feed','geometry-delete','geometry-sx','geometry-ex','geometry-diameter','geometry-segments'): assert marker in html, marker
for marker in ("geometryAxes={xy:[0,1,'X','Y'],xz:[0,2,'X','Z'],yz:[1,2,'Y','Z']}",'function renderGeometry','function geometryPointerDown','function geometryPointerMove','function addGeometryWire','function deleteGeometryWire','function assignGeometryFeed',"hidden=[0,1,2].find"): assert marker in js, marker
assert "new Set(['model','geometry','solve','optimize','measurement'])" in js
g3=(root/'apps/linux_web/static/geometry3d.js').read_text(encoding='utf-8')
assert '/geometry3d.js' in html
for marker in ('window.renderGeometry3D=render','pointerdown','wheel','drawGround','drawAxes','feedPoint'): assert marker in g3, marker
assert 'three.js' not in html.lower() and 'webgl' not in js.lower() and 'three.js' not in g3.lower() and 'webgl' not in g3.lower()
print('GEOMETRY EDITOR STRUCTURE PASS: 2D editor + lightweight canvas 3D preview, unique DOM ids, no WebGL stack')
