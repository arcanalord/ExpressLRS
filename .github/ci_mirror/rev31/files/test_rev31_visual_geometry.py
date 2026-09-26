#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.')
js=(root/'apps/linux_web/static/app.js').read_text(encoding='utf-8')
html=(root/'apps/linux_web/static/index.html').read_text(encoding='utf-8')
server=(root/'apps/linux_web/server.py').read_text(encoding='utf-8')
static_registry=root/'apps/linux_web/static/template-registry.json'
for marker in ['drawYagiGuide','projectTemplateId','antennaElementLabel','бум · визуальная ось','Питание','Директор ']: assert marker in js, marker
for old in ['2D редактор проводов','+ Провод','ВЫБРАННЫЙ ПРОВОД']: assert old not in html, old
for marker in ['Геометрия антенны','+ Элемент','ВЫБРАННЫЙ ЭЛЕМЕНТ']: assert marker in html, marker
assert 'load_template_registry' in server
assert static_registry.exists()
print('REV31 VISUAL GEOMETRY PASS')