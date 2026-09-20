from __future__ import annotations
import cmath, csv, io, math
from typing import Iterable

_UNIT_SCALE={"HZ":1.0,"KHZ":1e3,"MHZ":1e6,"GHZ":1e9}

def _finite(x: float) -> bool:
    return math.isfinite(x)

def _s11_to_derived(gamma: complex, z0: float) -> dict:
    mag=abs(gamma)
    if mag >= 1.0:
        vswr=math.inf
    else:
        vswr=(1.0+mag)/max(1e-15,1.0-mag)
    if abs(1.0-gamma) < 1e-15:
        z=complex(math.inf, math.inf)
    else:
        z=z0*(1.0+gamma)/(1.0-gamma)
    db=-math.inf if mag == 0 else 20.0*math.log10(mag)
    return {
        "s11":{"re":gamma.real,"im":gamma.imag,"mag":mag,"db":db,"phase_deg":math.degrees(cmath.phase(gamma))},
        "z_ohm":{"re":z.real,"im":z.imag},
        "vswr":vswr
    }

def parse_touchstone_s1p(text: str, source_name: str="inline.s1p") -> dict:
    unit="GHZ"; parameter="S"; data_format="MA"; z0=50.0
    version="1.0"; points=[]; option_seen=False
    for raw in text.replace("\r\n","\n").replace("\r","\n").split("\n"):
        line=raw.split("!",1)[0].strip()
        if not line: continue
        if line.startswith("["):
            low=line.lower()
            if low.startswith("[version]"):
                parts=line.split()
                if len(parts)>=2: version=parts[-1]
            elif low.startswith("[reference]"):
                parts=line.replace("[Reference]","").replace("[reference]","").split()
                if parts: z0=float(parts[0])
            elif low.startswith("[number of ports]"):
                parts=line.split("]",1)[-1].split()
                if parts and int(parts[0]) != 1: raise ValueError("Only 1-port Touchstone is supported in rev9")
            elif low.startswith("[network data]") or low.startswith("[end]") or low.startswith("[number of frequencies]"):
                continue
            else:
                raise ValueError(f"Unsupported Touchstone keyword: {line}")
            continue
        if line.startswith("#"):
            toks=line[1:].upper().split()
            if len(toks) < 3: raise ValueError("Invalid Touchstone option line")
            unit,parameter,data_format=toks[0],toks[1],toks[2]
            if unit not in _UNIT_SCALE: raise ValueError(f"Unsupported frequency unit: {unit}")
            if parameter != "S": raise ValueError("Only S-parameters are supported in rev9")
            if data_format not in {"RI","MA","DB"}: raise ValueError(f"Unsupported Touchstone data format: {data_format}")
            if "R" in toks:
                i=toks.index("R")
                if i+1>=len(toks): raise ValueError("Missing reference resistance after R")
                z0=float(toks[i+1])
            if not (_finite(z0) and z0>0): raise ValueError("Reference resistance must be positive")
            option_seen=True
            continue
        vals=line.replace(","," ").split()
        if len(vals) != 3:
            raise ValueError("S1P data row must contain frequency and one complex pair")
        f,a,b=map(float,vals)
        if not all(_finite(x) for x in (f,a,b)): raise ValueError("Non-finite Touchstone value")
        hz=f*_UNIT_SCALE[unit]
        if data_format=="RI": gamma=complex(a,b)
        elif data_format=="MA": gamma=cmath.rect(a,math.radians(b))
        else: gamma=cmath.rect(10.0**(a/20.0),math.radians(b))
        row={"frequency_hz":hz}
        row.update(_s11_to_derived(gamma,z0))
        points.append(row)
    if not points: raise ValueError("Touchstone file contains no S1P data")
    if any(points[i]["frequency_hz"]<=points[i-1]["frequency_hz"] for i in range(1,len(points))):
        raise ValueError("Touchstone frequencies must be strictly increasing")
    return {
        "schema_version":"0.1","source_format":"touchstone-s1p","touchstone_version":version,
        "source_name":source_name,"option_line_seen":option_seen,"reference_ohm":z0,
        "points":points
    }

def parse_vna_csv(text: str, source_name: str="inline.csv") -> dict:
    reader=csv.DictReader(io.StringIO(text))
    if not reader.fieldnames: raise ValueError("CSV header is required")
    names={n.strip().lower():n for n in reader.fieldnames}
    def key(*alts):
        for a in alts:
            if a in names:return names[a]
        return None
    fk=key("frequency_hz","frequency","freq_hz","freq")
    rk=key("r_ohm","resistance_ohm","resistance","r")
    xk=key("x_ohm","reactance_ohm","reactance","x")
    if not (fk and rk and xk): raise ValueError("VNA CSV requires frequency_hz/frequency, R and X columns")
    rows=[]
    for src in reader:
        f=float(src[fk]); r=float(src[rk]); x=float(src[xk])
        if not all(_finite(v) for v in (f,r,x)): raise ValueError("Non-finite VNA CSV value")
        z=complex(r,x); gamma=(z-50.0)/(z+50.0) if abs(z+50.0)>1e-15 else complex(1,0)
        row={"frequency_hz":f,"z_ohm":{"re":r,"im":x}}
        row.update({"s11":_s11_to_derived(gamma,50.0)["s11"],"vswr":_s11_to_derived(gamma,50.0)["vswr"]})
        rows.append(row)
    if not rows: raise ValueError("VNA CSV contains no data")
    rows.sort(key=lambda x:x["frequency_hz"])
    return {"schema_version":"0.1","source_format":"vna-csv","source_name":source_name,"reference_ohm":50.0,"points":rows}

def _interp(points: list[dict], f: float, field: str) -> float:
    if f < points[0]["frequency_hz"] or f > points[-1]["frequency_hz"]:
        raise ValueError("comparison frequency is outside measured range")
    for p in points:
        if p["frequency_hz"]==f: return float(p[field])
    for a,b in zip(points,points[1:]):
        fa,fb=a["frequency_hz"],b["frequency_hz"]
        if fa <= f <= fb:
            t=(f-fa)/(fb-fa)
            return float(a[field])+(float(b[field])-float(a[field]))*t
    raise ValueError("interpolation failed")

def _flatten_measurement(points: list[dict]) -> list[dict]:
    return [{
      "frequency_hz":p["frequency_hz"],
      "r_ohm":p["z_ohm"]["re"],"x_ohm":p["z_ohm"]["im"],
      "vswr":p["vswr"],"s11_db":p["s11"]["db"]
    } for p in points]

def normalize_simulation_sweep(sweep: dict, reference_ohm: float=50.0) -> list[dict]:
    rows=[]
    samples=sweep.get("samples",[])
    for s in samples:
        zsrc=s.get("impedance_ohm") or (s.get("feeds") or [{}])[0].get("impedance_ohm")
        if not zsrc: raise ValueError("Simulation sweep sample has no impedance")
        z=complex(float(zsrc["re"]),float(zsrc["im"]))
        gamma=(z-reference_ohm)/(z+reference_ohm) if abs(z+reference_ohm)>1e-15 else complex(1,0)
        d=_s11_to_derived(gamma,reference_ohm)
        rows.append({"frequency_hz":float(s["frequency_hz"]),"r_ohm":z.real,"x_ohm":z.imag,"vswr":d["vswr"],"s11_db":d["s11"]["db"]})
    if not rows: raise ValueError("Simulation sweep contains no samples")
    return rows

def compare_measurement_to_simulation(measurement: dict, simulation_sweep: dict) -> dict:
    mp=_flatten_measurement(measurement["points"])
    sp=normalize_simulation_sweep(simulation_sweep,float(measurement.get("reference_ohm",50.0)))
    rows=[]
    for s in sp:
        f=s["frequency_hz"]
        if f < mp[0]["frequency_hz"] or f > mp[-1]["frequency_hz"]: continue
        m={k:_interp(mp,f,k) for k in ("r_ohm","x_ohm","vswr","s11_db")}
        rows.append({
          "frequency_hz":f,
          "simulation":{k:s[k] for k in ("r_ohm","x_ohm","vswr","s11_db")},
          "measurement":m,
          "delta":{"r_ohm":s["r_ohm"]-m["r_ohm"],"x_ohm":s["x_ohm"]-m["x_ohm"],"vswr":s["vswr"]-m["vswr"],"s11_db":s["s11_db"]-m["s11_db"]}
        })
    if not rows: raise ValueError("Simulation and measurement ranges do not overlap")
    def maxabs(key): return max(abs(r["delta"][key]) for r in rows)
    return {
      "schema_version":"0.1","alignment":"measurement-linear-interpolation-to-simulation-grid",
      "points":rows,
      "summary":{"overlap_points":len(rows),"max_abs_delta_r_ohm":maxabs("r_ohm"),"max_abs_delta_x_ohm":maxabs("x_ohm"),"max_abs_delta_vswr":maxabs("vswr"),"max_abs_delta_s11_db":maxabs("s11_db")}
    }
