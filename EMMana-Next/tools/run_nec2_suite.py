#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, shutil, subprocess, tempfile
from pathlib import Path

CASES = [
    ("B01", "B01_halfwave_dipole_51seg.emnx", 3.0, 3.0, True),
    ("B02", "B02_quarterwave_monopole_over_pec.emnx", 5.0, 5.0, False),
    ("B04", "B04_three_element_yagi.emnx", 8.0, 8.0, False),
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
        for label, filename, rtol, xtol, strict in CASES:
            project=ns.root/'benchmarks'/filename
            deck=td/f'{label}.nec'; out=td/f'{label}.out'; own_json=td/f'{label}.own.json'
            exp=run([str(ns.emnext),'export-nec',str(project),str(deck)])
            if exp.returncode != 0:
                rows.append({'case':label,'project':filename,'strict':strict,'status':'export_failed','stderr':exp.stderr})
                strict_ok = strict_ok and not strict
                continue
            nec=run([engine,str(deck),str(out)])
            if nec.returncode != 0:
                rows.append({
                    'case':label,'project':filename,'strict':strict,'status':'nec2_failed',
                    'returncode':nec.returncode,'stdout':nec.stdout,'stderr':nec.stderr
                })
                strict_ok = strict_ok and not strict
                continue
            parsed=run([str(ns.emnext),'parse-nec',str(out)])
            nec_z=extract_impedance(parsed.stdout)
            own=run([str(ns.emnext),'solve-exp-json',str(project),str(own_json)])
            if parsed.returncode or own.returncode or nec_z is None or not own_json.exists():
                rows.append({'case':label,'project':filename,'strict':strict,'status':'parse_or_own_failed','parse_stdout':parsed.stdout,'parse_stderr':parsed.stderr,'own_stderr':own.stderr})
                strict_ok = strict_ok and not strict
                continue
            own_data=json.loads(own_json.read_text())
            own_z=own_data['feeds'][0]['impedance_ohm']
            dr=float(own_z['re'])-nec_z['re']; dx=float(own_z['im'])-nec_z['im']
            passed=abs(dr)<=rtol and abs(dx)<=xtol
            if strict and not passed: strict_ok=False
            rows.append({
                'case':label,'project':filename,'strict':strict,'status':'pass' if passed else ('fail' if strict else 'characterization'),
                'own_z_ohm':{'re':float(own_z['re']),'im':float(own_z['im'])},'nec2_z_ohm':nec_z,
                'delta_r_ohm':dr,'delta_x_ohm':dx,'r_tolerance_ohm':rtol,'x_tolerance_ohm':xtol,
                'within_provisional_tolerance':passed,
                'solver_version':own_data.get('solver_version'),'model_hash':own_data.get('model_hash')
            })
            print(f"{label}: own={own_z['re']:.6f}{own_z['im']:+.6f}j NEC2={nec_z['re']:.6f}{nec_z['im']:+.6f}j dR={dr:+.6f} dX={dx:+.6f} {'PASS' if passed else 'OUTSIDE'}{' STRICT' if strict else ' CHARACTERIZATION'}")
    report={
        'schema_version':'0.2','reference_engine':'nec2c','strict_gate_cases':['B01'],
        'characterization_cases':['B02','B04'],'cases':rows,'strict_pass':strict_ok
    }
    ns.json_report.parent.mkdir(parents=True,exist_ok=True)
    ns.json_report.write_text(json.dumps(report,indent=2)+'\n')
    return 0 if strict_ok else 5

if __name__=='__main__': raise SystemExit(main())
