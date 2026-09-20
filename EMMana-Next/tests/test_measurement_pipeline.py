#!/usr/bin/env python3
from __future__ import annotations
import importlib.util, math, sys
from pathlib import Path
root=Path(sys.argv[1])
path=root/"apps/shared/product/measurement.py"
spec=importlib.util.spec_from_file_location("emnext_measurement",path); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
ri="# MHz S RI R 50\n100 0 0\n150 0.3333333333 0\n200 0 0\n"
p=m.parse_touchstone_s1p(ri)
assert len(p["points"])==3 and p["reference_ohm"]==50
assert abs(p["points"][1]["z_ohm"]["re"]-100)<1e-6 and abs(p["points"][1]["z_ohm"]["im"])<1e-9
ma="# GHZ S MA R 50\n0.1 0.5 90\n"
q=m.parse_touchstone_s1p(ma)
assert abs(q["points"][0]["s11"]["re"])<1e-9 and abs(q["points"][0]["s11"]["im"]-0.5)<1e-9
db="# MHz S DB R 50\n100 -6.020599913 0\n"
d=m.parse_touchstone_s1p(db);assert abs(d["points"][0]["s11"]["mag"]-0.5)<1e-6
csv="frequency_hz,R_ohm,X_ohm\n100000000,50,0\n150000000,100,0\n200000000,50,0\n"
v=m.parse_vna_csv(csv);assert len(v["points"])==3
sim={"samples":[{"frequency_hz":100e6,"impedance_ohm":{"re":50,"im":0}},{"frequency_hz":150e6,"impedance_ohm":{"re":90,"im":10}},{"frequency_hz":200e6,"impedance_ohm":{"re":50,"im":0}}]}
cmp=m.compare_measurement_to_simulation(v,sim)
assert cmp["summary"]["overlap_points"]==3
assert abs(cmp["points"][1]["delta"]["r_ohm"]+10)<1e-9
assert abs(cmp["points"][1]["delta"]["x_ohm"]-10)<1e-9
print("MEASUREMENT PIPELINE PASS",cmp["summary"])
