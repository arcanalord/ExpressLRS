#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, shutil, subprocess, sys, tempfile
from pathlib import Path

def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument('project',type=Path); ap.add_argument('--emnext',type=Path,default=Path('build/emnext')); ap.add_argument('--engine',default='nec2c'); ap.add_argument('--keep',action='store_true'); ap.add_argument('--compare-own',action='store_true'); ap.add_argument('--report-only',action='store_true'); ap.add_argument('--r-tol',type=float,default=3.0); ap.add_argument('--x-tol',type=float,default=3.0); args=ap.parse_args()
    engine=shutil.which(args.engine)
    if not engine:
        print(f'reference engine not found in PATH: {args.engine}',file=sys.stderr); return 3
    if not args.emnext.exists():
        print(f'emnext CLI not found: {args.emnext}',file=sys.stderr); return 3
    if args.keep:
        deck=args.project.with_suffix('.reference.nec'); out=args.project.with_suffix('.reference.out'); work=None
    else:
        work=tempfile.TemporaryDirectory(prefix='emnext-nec2-'); root=Path(work.name); deck=root/'reference.nec'; out=root/'reference.out'
    subprocess.run([str(args.emnext),'export-nec',str(args.project),str(deck)],check=True)
    proc=subprocess.run([engine,f'-i{deck}',f'-o{out}'],text=True)
    if proc.returncode!=0:
        print(f'reference engine failed with exit code {proc.returncode}',file=sys.stderr); return proc.returncode
    parsed=subprocess.run([str(args.emnext),'parse-nec',str(out)],text=True,capture_output=True)
    if parsed.stdout: print(parsed.stdout,end='')
    if parsed.stderr: print(parsed.stderr,end='',file=sys.stderr)
    if parsed.returncode!=0:
        if work is not None: work.cleanup()
        return parsed.returncode
    if args.compare_own:
        m=re.search(r'Z=([+-]?[0-9.eE]+)([+-])j([0-9.eE]+) ohm',parsed.stdout)
        if not m:
            print('could not extract NEC impedance from normalized parser output',file=sys.stderr)
            if work is not None: work.cleanup()
            return 4
        nec_r=float(m.group(1)); nec_x=float(m.group(3))*(1.0 if m.group(2)=='+' else -1.0)
        own_json=out.parent/'own-result.json'
        own=subprocess.run([str(args.emnext),'solve-exp-json',str(args.project),str(own_json)],text=True,capture_output=True)
        if own.returncode!=0:
            print(own.stdout,end=''); print(own.stderr,end='',file=sys.stderr)
            if work is not None: work.cleanup()
            return own.returncode
        data=json.loads(own_json.read_text(encoding='utf-8')); feed=data['feeds'][0]; own_r=float(feed['impedance_ohm']['re']); own_x=float(feed['impedance_ohm']['im']); dr=own_r-nec_r; dx=own_x-nec_x
        print(f'Cross-solver gate: own={own_r:.6f}{own_x:+.6f}j ohm, NEC={nec_r:.6f}{nec_x:+.6f}j ohm, dR={dr:+.6f}, dX={dx:+.6f}')
        if abs(dr)>args.r_tol or abs(dx)>args.x_tol:
            if args.report_only: print(f'cross-solver report-only: outside provisional tolerances R={args.r_tol} ohm X={args.x_tol} ohm')
            else:
                print(f'cross-solver gate FAILED: tolerances R={args.r_tol} ohm X={args.x_tol} ohm',file=sys.stderr)
                if work is not None: work.cleanup()
                return 5
        else: print('cross-solver gate PASS' if not args.report_only else 'cross-solver report-only: inside provisional tolerances')
    if work is not None: work.cleanup()
    return 0
if __name__=='__main__': raise SystemExit(main())
