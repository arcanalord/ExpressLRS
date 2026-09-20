#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, os, subprocess, tempfile
from pathlib import Path

def solve(emnext:Path,project:Path,backend:str,out:Path)->dict:
    env=dict(os.environ); env['EMNEXT_LINEAR_BACKEND']=backend
    proc=subprocess.run([str(emnext),'solve-exp-json',str(project),str(out)],env=env,text=True,capture_output=True)
    if proc.returncode!=0: raise RuntimeError(f'{backend} solve failed for {project.name}:\n{proc.stdout}\n{proc.stderr}')
    return json.loads(out.read_text())

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument('--emnext',type=Path,required=True); ap.add_argument('--root',type=Path,required=True); ap.add_argument('--r-tol',type=float,default=1e-8); ap.add_argument('--x-tol',type=float,default=1e-8); ap.add_argument('--residual-max',type=float,default=1e-10); ap.add_argument('--json-report',type=Path); ns=ap.parse_args()
    cases=['B01_halfwave_dipole_51seg.emnx','B04_three_element_yagi.emnx']; rows=[]
    with tempfile.TemporaryDirectory(prefix='emnext-backend-parity-') as td:
        td=Path(td)
        for case in cases:
            p=ns.root/'benchmarks'/case; a=solve(ns.emnext,p,'lapack',td/(case+'.lapack.json')); b=solve(ns.emnext,p,'bootstrap',td/(case+'.bootstrap.json'))
            za=a['feeds'][0]['impedance_ohm']; zb=b['feeds'][0]['impedance_ohm']; dr=float(za['re'])-float(zb['re']); dx=float(za['im'])-float(zb['im'])
            row={'case':case,'lapack_backend':a['linear_solver_backend'],'bootstrap_backend':b['linear_solver_backend'],'lapack_residual':a['linear_residual_relative'],'bootstrap_residual':b['linear_residual_relative'],'lapack_z_ohm':za,'bootstrap_z_ohm':zb,'delta_r_ohm':dr,'delta_x_ohm':dx,'pass':abs(dr)<=ns.r_tol and abs(dx)<=ns.x_tol and a['linear_residual_relative']<=ns.residual_max and b['linear_residual_relative']<=ns.residual_max}
            rows.append(row); print(f"{case}: dR={dr:+.3e} ohm dX={dx:+.3e} ohm residuals={a['linear_residual_relative']:.3e}/{b['linear_residual_relative']:.3e} {'PASS' if row['pass'] else 'FAIL'}")
    report={'schema_version':'0.1','r_tolerance_ohm':ns.r_tol,'x_tolerance_ohm':ns.x_tol,'residual_max':ns.residual_max,'cases':rows,'pass':all(r['pass'] for r in rows)}
    if ns.json_report: ns.json_report.parent.mkdir(parents=True,exist_ok=True); ns.json_report.write_text(json.dumps(report,indent=2)+'\n')
    return 0 if report['pass'] else 5
if __name__=='__main__': raise SystemExit(main())
