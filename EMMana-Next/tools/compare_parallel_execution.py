#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, os, subprocess, tempfile
from pathlib import Path

def env_for(workers:int):
    e=dict(os.environ); e['EMNEXT_PARALLEL_WORKERS']=str(workers); e['OPENBLAS_NUM_THREADS']='1'; e['OMP_NUM_THREADS']='1'; e['MKL_NUM_THREADS']='1'; return e

def run_sweep(root:Path,emnext:Path,workers:int):
    with tempfile.TemporaryDirectory(prefix='emnext-par-sweep-') as td:
        out=Path(td)/'sweep.json'; subprocess.run([str(emnext),'sweep-exp-json',str(root/'benchmarks/B01_halfwave_dipole_51seg.emnx'),'270000000','330000000','9',str(out),'reduced'],env=env_for(workers),check=True,capture_output=True,text=True); return json.loads(out.read_text())

def run_optimizer(root:Path,emnext:Path,workers:int):
    with tempfile.TemporaryDirectory(prefix='emnext-par-opt-') as td:
        out=Path(td)/'opt.json'; cmd=[str(emnext),'optimize-exp-json',str(root/'benchmarks/B04_three_element_yagi_parametric.emnx'),'4','1','42',str(out),'reduced','pso','0','0.40','0.30','0.20','0.10','0.50','3.0','297000000','303000000','3','0.001','0.001','2','0']; subprocess.run(cmd,env=env_for(workers),check=True,capture_output=True,text=True); return json.loads(out.read_text())

def close(a:float,b:float,tol:float=1e-10): return abs(float(a)-float(b))<=tol*max(1.0,abs(float(a)),abs(float(b)))
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',type=Path,required=True); ap.add_argument('--emnext',type=Path,required=True); ap.add_argument('--json-report',type=Path); ns=ap.parse_args()
    s1=run_sweep(ns.root,ns.emnext,1); s4=run_sweep(ns.root,ns.emnext,4); sweep_ok=len(s1['samples'])==len(s4['samples']) and s1['execution_workers']==1 and s4['execution_workers']==4; max_delta=0.0
    for a,b in zip(s1['samples'],s4['samples']):
        vals=[(a['impedance_ohm']['re'],b['impedance_ohm']['re']),(a['impedance_ohm']['im'],b['impedance_ohm']['im']),(a['vswr'],b['vswr']),(a['dmax_dbi'],b['dmax_dbi']),(a['linear_residual_relative'],b['linear_residual_relative'])]
        for x,y in vals: max_delta=max(max_delta,abs(float(x)-float(y))); sweep_ok=sweep_ok and close(x,y)
    for k in ['resonance_frequency_hz','min_s11_frequency_hz','min_s11_db','bandwidth_10db_hz']: sweep_ok=sweep_ok and close(s1[k],s4[k])
    o1=run_optimizer(ns.root,ns.emnext,1); o4=run_optimizer(ns.root,ns.emnext,4); opt_ok=o1['execution_workers']==1 and o4['execution_workers']==4 and o1['best']['model_hash']==o4['best']['model_hash']
    if len(o1['best']['values'])!=len(o4['best']['values']): opt_ok=False
    else:
        for a,b in zip(o1['best']['values'],o4['best']['values']): opt_ok=opt_ok and a['id']==b['id'] and close(a['value'],b['value'])
    metric_keys=['score','vswr','forward_gain_dbi','front_to_back_db','boom_length_m','power_balance_relative_error','max_linear_residual_relative','worst_vswr_frequency_hz','min_gain_frequency_hz','min_front_to_back_frequency_hz','total_constraint_violation']
    for k in metric_keys: opt_ok=opt_ok and close(o1['best']['metrics'][k],o4['best']['metrics'][k])
    report={'schema_version':'0.1','serial_workers':1,'parallel_workers':4,'sweep_pass':sweep_ok,'sweep_max_absolute_delta':max_delta,'optimizer_pass':opt_ok,'optimizer_best_model_hash':o1['best']['model_hash'],'pass':sweep_ok and opt_ok}; print(json.dumps(report,indent=2))
    if ns.json_report: ns.json_report.parent.mkdir(parents=True,exist_ok=True); ns.json_report.write_text(json.dumps(report,indent=2)+'\n')
    return 0 if report['pass'] else 2
if __name__=='__main__': raise SystemExit(main())
