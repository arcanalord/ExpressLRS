#!/usr/bin/env python3
from pathlib import Path
import importlib.util,json,subprocess,tempfile,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
emnext=Path(sys.argv[2] if len(sys.argv)>2 else root/'build-linux/emnext').resolve()
spec=importlib.util.spec_from_file_location('emnext_server',root/'apps/linux_web/server.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
ids=['halfwave-dipole','quarterwave-monopole-pec','yagi-3el','yagi-5el','yagi-7el','square-loop','moxon']
with tempfile.TemporaryDirectory(prefix='rev30-templates-') as td:
    td=Path(td)
    projects={}
    for tid in ids:
        r=mod.synthesize_template(tid,299792458.0,{})
        p=r['project'];projects[tid]=p
        f=td/(tid+'.emnx');f.write_text(json.dumps(p),encoding='utf-8')
        cp=subprocess.run([str(emnext),'model-check',str(f)],capture_output=True,text=True,timeout=60)
        if cp.returncode!=0:
            raise RuntimeError(f'{tid} model-check failed\n{cp.stdout}\n{cp.stderr}')
        print('MODEL_CHECK_PASS',tid,'wires',len(p.get('wires',[])))
    assert len(projects['yagi-5el']['wires'])==5
    assert len(projects['yagi-7el']['wires'])==7
    assert len(projects['moxon']['wires'])==6
    for tid in ['halfwave-dipole','quarterwave-monopole-pec','yagi-3el','square-loop']:
        f=td/(tid+'.emnx');o=td/(tid+'.json')
        cp=subprocess.run([str(emnext),'solve-exp-json',str(f),str(o)],capture_output=True,text=True,timeout=120)
        if cp.returncode!=0: raise RuntimeError(f'{tid} solve failed\n{cp.stdout}\n{cp.stderr}')
        data=json.loads(o.read_text())
        assert data.get('feeds'),tid
        print('SOLVE_PASS',tid,'vswr',data['feeds'][0].get('vswr'))
print('REV30_TEMPLATE_RUNTIME_PASS')