#!/usr/bin/env python3
from __future__ import annotations
import json, math, sys
from pathlib import Path
root=Path(sys.argv[1])
sys.path.insert(0,str(root/"apps/shared/product"))
from measurement import parse_touchstone_s1p, parse_vna_csv, compare_measurement_to_sweep

fixtures=root/"measurements/fixtures"
ri=parse_touchstone_s1p((fixtures/"touchstone_ri.s1p").read_text(),"ri.s1p")
ma=parse_touchstone_s1p((fixtures/"touchstone_ma.s1p").read_text(),"ma.s1p")
db=parse_touchstone_s1p((fixtures/"touchstone_db.s1p").read_text(),"db.s1p")
csvm=parse_vna_csv((fixtures/"vna_s11.csv").read_text(),"vna.csv")

for other in (ma,db,csvm):
    assert len(other["samples"])==len(ri["samples"])==3
    for a,b in zip(ri["samples"],other["samples"]):
        assert abs(a["frequency_hz"]-b["frequency_hz"])<1e-6
        assert abs(a["s11"]["re"]-b["s11"]["re"])<1e-8
        assert abs(a["s11"]["im"]-b["s11"]["im"])<1e-8

sweep={
 "resonance_frequency_hz":120000000.0,
 "samples":[
   {"frequency_hz":100000000.0,"impedance_ohm":ri["samples"][0]["impedance_ohm"],"s11":ri["samples"][0]["s11"],"vswr":ri["samples"][0]["vswr"]},
   {"frequency_hz":105000000.0,"impedance_ohm":{"re":65.0,"im":10.0},"s11":{"re":0.15,"im":0.075},"vswr":1.4},
   {"frequency_hz":110000000.0,"impedance_ohm":ri["samples"][1]["impedance_ohm"],"s11":ri["samples"][1]["s11"],"vswr":ri["samples"][1]["vswr"]},
   {"frequency_hz":120000000.0,"impedance_ohm":ri["samples"][2]["impedance_ohm"],"s11":ri["samples"][2]["s11"],"vswr":ri["samples"][2]["vswr"]}
 ]
}
cmp=compare_measurement_to_sweep(ri,sweep)
assert cmp["overlap"]["points"]==4
assert cmp["summary"]["delta_r_ohm"]["count"]==4
assert abs(cmp["summary"]["resonance_shift_hz"])<1e-6
assert abs(cmp["samples"][0]["delta"]["r_ohm"])<1e-9
print("MEASUREMENT PIPELINE PASS",json.dumps(cmp["summary"],sort_keys=True))
