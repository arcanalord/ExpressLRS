#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.')
reg=json.loads((root/'apps/shared/product/template-registry.json').read_text(encoding='utf-8'))
impl={x['id']:x for x in reg['templates'] if x.get('status')=='implemented'}
required={'halfwave-dipole','quarterwave-monopole-pec','yagi-3el','yagi-5el','yagi-7el','square-loop','moxon'}
assert required <= set(impl)
for k in required:
    assert impl[k].get('parameters'), k
assert impl['moxon']['trust']=='experimental'
assert impl['yagi-5el']['trust']=='experimental' and impl['yagi-7el']['trust']=='experimental'
html=(root/'apps/linux_web/static/index.html').read_text(encoding='utf-8'); js=(root/'apps/linux_web/static/app.js').read_text(encoding='utf-8'); css=(root/'apps/linux_web/static/app.css').read_text(encoding='utf-8'); server=(root/'apps/linux_web/server.py').read_text(encoding='utf-8')
for m in ['template-parameter-panel','template-parameter-fields','template-parameter-apply','template-parameter-recalc','template-parameter-optimize']: assert m in html
for m in ['renderTemplateParameterPanel','collectTemplateParameterQuery','fetchParameterizedTemplate','applyTemplateParameters','syncTemplateParameterPanelFromProject']: assert m in js
for m in ['template-parameter-panel','template-parameter-fields']: assert m in css
for m in ['resolve_template_parameters','apply_template_binding','refresh_yagi_design_contract']: assert m in server
for p in ['apps/shared/product/seeds/yagi_5el_seed.emnx','apps/shared/product/seeds/yagi_7el_seed.emnx','apps/shared/product/seeds/moxon_seed.emnx']: assert (root/p).exists()
print('REV30_TEMPLATE_SYSTEM_PASS')