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
for marker in ('geometry-canvas','geometry-add','geometry-feed','geometry-delete','geometry-sx','geometry-ex','geometry-diameter','geometry-segments'): assert marker in html, marker
for marker in ("geometryAxes={xy:[0,1,'X','Y'],xz:[0,2,'X','Z'],yz:[1,2,'Y','Z']}",'function renderGeometry','function geometryPointerDown','function geometryPointerMove','function addGeometryWire','function deleteGeometryWire','function assignGeometryFeed',"const hidden=[0,1,2].find"): assert marker in js, marker
assert "new Set(['model','geometry','solve','optimize','measurement'])" in js
assert 'three.js' not in html.lower() and 'webgl' not in js.lower()
print('GEOMETRY EDITOR STRUCTURE PASS: 2D projections, unique DOM ids, no hidden 3D stack')
