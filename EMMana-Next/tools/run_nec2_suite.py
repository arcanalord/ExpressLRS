#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, shutil, subprocess, tempfile
from pathlib import Path

CASES = [
    {"label":"B01","file":"B01_halfwave_dipole_51seg.emnx","r_tol":3.0,"x_tol":3.0,"strict":True,"group":"free-space"},
    {"label":"B02","file":"B02_quarterwave_monopole_over_pec.emnx","r_tol":5.0,"x_tol":5.0,"strict":False,"group":"pec-ground"},
    {"label":"B04","file":"B04_three_element_yagi.emnx","r_tol":8.0,"x_tol":8.0,"strict":False,"group":"free-space"},
    # Finite-ground cases are measurement-only on their first real NEC2 run.
    # Do not invent acceptance tolerances before observing independent deltas.
    {"label":"G01","file":"G01_ground_avg_h010.emnx","r_tol":None,"x_tol":None,"strict":False,"group":"finite-ground"},
    {"label":"G02","file":"G02_ground_avg_h025.emnx","r_tol":None,"x_tol":None,"strict":False,"group":"finite-ground"},
    {"label":"G03","file":"G03_ground_avg_h050.emnx","r_tol":None,"x_tol":None,"strict":False,"group":"finite-ground"},
    {"label":"G04","file":"G04_ground_avg_h100.emnx","r_tol":None,"x_tol":None,"strict":False,"group":"finite-ground"},
    {"label":"G05","file":"G05_ground_dry_h025.emnx","r_tol":None,"x_tol":None,"strict":False,"group":"finite-ground"},
    {"label":"G06","file":"G06_ground_wet_h025.emnx","r_tol":None,"x_tol":None,"strict":False,"group":"finite-ground"},
]

def run(cmd, **kw):
    return subprocess.run(cmd, text=True, capture_output=True, **kw)

def extract_impedance(text: str):
    m=re.search(r"Z=([+-]?[0-9.eE]+)([+-])j([0-9.eE]+) ohm", text)
    if not m: return None
    return {"re": float(m.group(1)), "im": float(m.group(3))*(1 if m.group(2)=="+" else -1)}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, required=True)
    ap.add_argument('--emnext', type=Path, required=True)
    ap.add_argument('--engine', default='nec2c')
    ap.add_argument('--json-report', type=Path, required=True)
    ns=ap.parse_args()
    engine=shutil.which(ns.engine)
    if not engine:
        raise SystemExit(f"reference engine not found: {ns.engine}")
    rows=[]
    strict_ok=True
    with tempfile.TemporaryDirectory(prefix='emnext-nec2-suite-') as td:
        td=Path(td)
        for case in CASES:
            label=case["label"]; filename=case["file"]; rtol=case["r_tol"]; xtol=case["x_tol"]; strict=case["strict"]; group=case["group"]
            project=ns.root/'benchmarks'/filename
            deck=td/f'{label}.nec'; out=td/f'{label}.out'; own_json=td/f'{label}.own.json'
            exp=run([str(ns.emnext),'export-nec',str(project),str(deck)])
            if exp.returncode != 0:
                rows.append({'case':label,'project':filename,'group':group,'strict':strict,'status':'export_failed','stderr':exp.stderr})
                strict_ok = strict_ok and not strict
                continue
            nec=run([engine,'-i',str(deck),'-o',str(out)])
            if nec.returncode != 0:
                rows.append({
                    'case':label,'project':filename,'group':group,'strict':strict,'status':'nec2_failed',
                    'returncode':nec.returncode,'stdout':nec.stdout,'stderr':nec.stderr,
                    'deck': deck.read_text(encoding='utf-8', errors='replace') if deck.exists() else '',
                    'nec2_output_tail': out.read_text(encoding='utf-8', errors='replace')[-6000:] if out.exists() else ''
                })
                strict_ok = strict_ok and not strict
                continue
            parsed=run([str(ns.emnext),'parse-nec',str(out)])
            nec_z=extract_impedance(parsed.stdout)
            own=run([str(ns.emnext),'solve-exp-json',str(project),str(own_json)])
            if parsed.returncode or own.returncode or nec_z is None or not own_json.exists():
                rows.append({'case':label,'project':filename,'group':group,'strict':strict,'status':'parse_or_own_failed','parse_stdout':parsed.stdout,'parse_stderr':parsed.stderr,'own_stderr':own.stderr})
                strict_ok = strict_ok and not strict
                continue
            own_data=json.loads(own_json.read_text())
            own_z=own_data['feeds'][0]['impedance_ohm']
            dr=float(own_z['re'])-nec_z['re']; dx=float(own_z['im'])-nec_z['im']
            measured_only = rtol is None or xtol is None
            passed = None if measured_only else (abs(dr)<=rtol and abs(dx)<=xtol)
            if strict and passed is not True: strict_ok=False
            status = 'characterization' if measured_only else ('pass' if passed else ('fail' if strict else 'characterization'))
            rows.append({
                'case':label,'project':filename,'group':group,'strict':strict,'status':status,
                'own_z_ohm':{'re':float(own_z['re']),'im':float(own_z['im'])},'nec2_z_ohm':nec_z,
                'delta_r_ohm':dr,'delta_x_ohm':dx,'r_tolerance_ohm':rtol,'x_tolerance_ohm':xtol,
                'within_provisional_tolerance':passed,
                'solver_version':own_data.get('solver_version'),'model_hash':own_data.get('model_hash')
            })
            verdict = 'MEASURED' if measured_only else ('PASS' if passed else 'OUTSIDE')
            mode = 'STRICT' if strict else 'CHARACTERIZATION'
            print(f"{label}: own={own_z['re']:.6f}{own_z['im']:+.6f}j NEC2={nec_z['re']:.6f}{nec_z['im']:+.6f}j dR={dr:+.6f} dX={dx:+.6f} {verdict} {mode}")
    report={
        'schema_version':'0.2','reference_engine':'nec2c','strict_gate_cases':['B01'],
        'characterization_cases':['B02','B04','G01','G02','G03','G04','G05','G06'],
        'finite_ground_cases':['G01','G02','G03','G04','G05','G06'],
        'finite_ground_policy':'measurement-only until evidence-backed tolerances are adopted',
        'cases':rows,'strict_pass':strict_ok
    }
    ns.json_report.parent.mkdir(parents=True,exist_ok=True)
    ns.json_report.write_text(json.dumps(report,indent=2)+'\n')
    return 0 if strict_ok else 5

if __name__=='__main__': raise SystemExit(main())
