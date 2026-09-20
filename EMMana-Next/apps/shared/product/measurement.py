from __future__ import annotations

import cmath
import csv
import io
import math
import re
from typing import Iterable

_FREQ_SCALE={"HZ":1.0,"KHZ":1e3,"MHZ":1e6,"GHZ":1e9}


def _finite_or_none(value: float):
    return value if math.isfinite(value) else None


def _derive_sample(frequency_hz: float, gamma: complex, z0: float) -> dict:
    mag=abs(gamma)
    s11_db=20.0*math.log10(mag) if mag>0 else -300.0
    vswr=(1.0+mag)/(1.0-mag) if mag<1.0 else None
    den=1.0-gamma
    if abs(den)<1e-15:
        zr=zi=None
    else:
        z=z0*(1.0+gamma)/den
        zr=_finite_or_none(float(z.real)); zi=_finite_or_none(float(z.imag))
    return {
        "frequency_hz":float(frequency_hz),
        "s11":{"re":float(gamma.real),"im":float(gamma.imag)},
        "s11_db":float(s11_db),
        "vswr":_finite_or_none(vswr) if vswr is not None else None,
        "impedance_ohm":{"re":zr,"im":zi}
    }


def _validate_samples(samples: list[dict]) -> None:
    if not samples:
        raise ValueError("measurement has no samples")
    prev=None
    for sample in samples:
        f=float(sample["frequency_hz"])
        if not math.isfinite(f) or f<=0:
            raise ValueError("measurement frequency must be positive and finite")
        if prev is not None and f<=prev:
            raise ValueError("measurement frequencies must be strictly increasing")
        prev=f


def _touchstone_option(line: str) -> tuple[str,str,str,float]:
    tokens=line[1:].strip().upper().split()
    unit="GHZ"; parameter="S"; data_format="MA"; z0=50.0
    i=0
    while i<len(tokens):
        token=tokens[i]
        if token in _FREQ_SCALE: unit=token
        elif token in {"S","Y","Z","H","G"}: parameter=token
        elif token in {"RI","MA","DB"}: data_format=token
        elif token=="R":
            if i+1>=len(tokens): raise ValueError("Touchstone R requires a reference resistance")
            z0=float(tokens[i+1]); i+=1
        i+=1
    if z0<=0 or not math.isfinite(z0): raise ValueError("Touchstone reference resistance must be positive")
    return unit,parameter,data_format,z0


def parse_touchstone_s1p(text: str, source_name: str="measurement.s1p") -> dict:
    unit="GHZ"; parameter="S"; data_format="MA"; z0=50.0
    number_of_ports=1
    in_network_data=True
    samples=[]
    for raw in text.splitlines():
        line=raw.split("!",1)[0].strip()
        if not line: continue
        if line.startswith("#"):
            unit,parameter,data_format,z0=_touchstone_option(line); continue
        if line.startswith("["):
            m=re.match(r"^\[([^\]]+)\]\s*(.*)$",line)
            if not m: continue
            key=m.group(1).strip().lower(); value=m.group(2).strip()
            if key=="number of ports" and value:
                number_of_ports=int(value)
            elif key=="reference" and value:
                z0=float(value.split()[0])
            elif key=="network data":
                in_network_data=True
            elif key=="end":
                in_network_data=False
            continue
        if not in_network_data: continue
        if number_of_ports!=1: raise ValueError("first parser scope supports 1-port Touchstone only")
        if parameter!="S": raise ValueError("first parser scope supports S-parameter Touchstone only")
        parts=line.replace(","," ").split()
        if len(parts)<3: continue
        f=float(parts[0])*_FREQ_SCALE[unit]
        a=float(parts[1]); b=float(parts[2])
        if data_format=="RI":
            gamma=complex(a,b)
        else:
            mag=10.0**(a/20.0) if data_format=="DB" else a
            gamma=cmath.rect(mag,math.radians(b))
        samples.append(_derive_sample(f,gamma,z0))
    _validate_samples(samples)
    return {
        "schema_version":"0.1",
        "source":{"format":"touchstone-s1p","name":source_name},
        "parameter":"S11",
        "reference_impedance_ohm":z0,
        "samples":samples
    }


def _header_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+","",value.lower())


def _find_header(headers: list[str], candidates: Iterable[str]):
    mapping={_header_key(h):h for h in headers}
    for c in candidates:
        if c in mapping: return mapping[c]
    return None


def _frequency_scale_from_header(header: str) -> float:
    key=_header_key(header)
    if "ghz" in key: return 1e9
    if "mhz" in key: return 1e6
    if "khz" in key: return 1e3
    return 1.0


def parse_vna_csv(text: str, source_name: str="measurement.csv", reference_impedance_ohm: float=50.0) -> dict:
    if reference_impedance_ohm<=0: raise ValueError("reference_impedance_ohm must be positive")
    reader=csv.DictReader(io.StringIO(text))
    headers=reader.fieldnames or []
    freq_h=_find_header(headers,["frequencyhz","frequency","freqhz","freq","frequencykhz","frequencymhz","frequencyghz"])
    if not freq_h: raise ValueError("VNA CSV frequency column not recognized")
    real_h=_find_header(headers,["s11real","s11re","real","reals11"])
    imag_h=_find_header(headers,["s11imaginary","s11imag","s11im","imaginary","imag","ims11"])
    db_h=_find_header(headers,["s11db","s11logmagdb","logmagdb","s11magnitude db".replace(" ",""),"s11logmag"])
    phase_h=_find_header(headers,["s11phasedeg","s11phase","phasedeg","phase"])
    r_h=_find_header(headers,["resistanceohm","resistance","rohms","rohm","r"])
    x_h=_find_header(headers,["reactanceohm","reactance","xohms","xohm","x"])
    if real_h and imag_h:
        profile="s11-ri"
    elif db_h and phase_h:
        profile="s11-db-phase"
    elif r_h and x_h:
        profile="impedance-rx"
    else:
        raise ValueError("VNA CSV needs S11 real/imag, S11 dB/phase, or R/X columns")
    fscale=_frequency_scale_from_header(freq_h)
    samples=[]
    for row in reader:
        if not row or not str(row.get(freq_h,"")).strip(): continue
        f=float(row[freq_h])*fscale
        if real_h and imag_h:
            gamma=complex(float(row[real_h]),float(row[imag_h]))
        elif db_h and phase_h:
            gamma=cmath.rect(10.0**(float(row[db_h])/20.0),math.radians(float(row[phase_h])))
        else:
            z=complex(float(row[r_h]),float(row[x_h]))
            den=z+reference_impedance_ohm
            if abs(den)<1e-15: raise ValueError("cannot convert VNA R/X sample to S11")
            gamma=(z-reference_impedance_ohm)/den
        samples.append(_derive_sample(f,gamma,reference_impedance_ohm))
    _validate_samples(samples)
    return {
        "schema_version":"0.1",
        "source":{"format":"vna-csv","name":source_name,"profile":profile},
        "parameter":"S11",
        "reference_impedance_ohm":float(reference_impedance_ohm),
        "samples":samples
    }


def parse_measurement(fmt: str, text: str, source_name: str="", reference_impedance_ohm: float=50.0) -> dict:
    fmt=fmt.lower()
    if fmt=="touchstone-s1p": return parse_touchstone_s1p(text,source_name or "measurement.s1p")
    if fmt=="vna-csv": return parse_vna_csv(text,source_name or "measurement.csv",reference_impedance_ohm)
    raise ValueError("unsupported measurement format")


def _interp(samples: list[dict], frequency_hz: float, reference_impedance_ohm: float=50.0) -> dict | None:
    if frequency_hz<samples[0]["frequency_hz"] or frequency_hz>samples[-1]["frequency_hz"]: return None
    lo=0; hi=len(samples)-1
    while lo<=hi:
        mid=(lo+hi)//2
        fm=samples[mid]["frequency_hz"]
        if fm<frequency_hz: lo=mid+1
        elif fm>frequency_hz: hi=mid-1
        else: return samples[mid]
    a=samples[hi]; b=samples[lo]
    t=(frequency_hz-a["frequency_hz"])/(b["frequency_hz"]-a["frequency_hz"])
    def lerp(x,y): return float(x)+(float(y)-float(x))*t
    zre=lerp(a["impedance_ohm"]["re"],b["impedance_ohm"]["re"])
    zim=lerp(a["impedance_ohm"]["im"],b["impedance_ohm"]["im"])
    sre=lerp(a["s11"]["re"],b["s11"]["re"]); sim=lerp(a["s11"]["im"],b["s11"]["im"])
    gamma=complex(sre,sim)
    out=_derive_sample(frequency_hz,gamma,reference_impedance_ohm)
    out["impedance_ohm"]={"re":zre,"im":zim}
    return out


def _s11_db(s11: dict) -> float:
    mag=math.hypot(float(s11["re"]),float(s11["im"]))
    return 20.0*math.log10(mag) if mag>0 else -300.0


def _resonance(samples: list[dict]) -> float | None:
    usable=[s for s in samples if s.get("impedance_ohm",{}).get("im") is not None]
    if not usable: return None
    for a,b in zip(usable,usable[1:]):
        xa=float(a["impedance_ohm"]["im"]); xb=float(b["impedance_ohm"]["im"])
        if xa==0: return float(a["frequency_hz"])
        if xa*xb<=0 and xa!=xb:
            t=-xa/(xb-xa)
            return float(a["frequency_hz"])+t*(float(b["frequency_hz"])-float(a["frequency_hz"]))
    return float(min(usable,key=lambda s:abs(float(s["impedance_ohm"]["im"])))["frequency_hz"])


def _summary(values: list[float]) -> dict:
    if not values: return {"count":0,"mean":None,"mae":None,"rms":None,"max_abs":None}
    return {
        "count":len(values),
        "mean":sum(values)/len(values),
        "mae":sum(abs(v) for v in values)/len(values),
        "rms":math.sqrt(sum(v*v for v in values)/len(values)),
        "max_abs":max(abs(v) for v in values)
    }


def compare_measurement_to_sweep(measurement: dict, sweep: dict) -> dict:
    ms=measurement.get("samples") or []
    ss=sweep.get("samples") or []
    _validate_samples(ms)
    if not ss: raise ValueError("simulation sweep has no samples")
    rows=[]; drs=[]; dxs=[]; ddbs=[]; dvswrs=[]
    for sim in ss:
        f=float(sim["frequency_hz"])
        meas=_interp(ms,f,float(measurement.get("reference_impedance_ohm",50.0)))
        if meas is None: continue
        sr=float(sim["impedance_ohm"]["re"]); sx=float(sim["impedance_ohm"]["im"])
        mr=float(meas["impedance_ohm"]["re"]); mx=float(meas["impedance_ohm"]["im"])
        dr=sr-mr; dx=sx-mx
        sdb=_s11_db(sim["s11"]); mdb=float(meas["s11_db"]); ddb=sdb-mdb
        sim_vswr=sim.get("vswr"); meas_vswr=meas.get("vswr")
        dvswr=(float(sim_vswr)-float(meas_vswr)) if sim_vswr is not None and meas_vswr is not None else None
        rows.append({
            "frequency_hz":f,
            "simulation":{"r_ohm":sr,"x_ohm":sx,"s11_db":sdb,"vswr":sim_vswr},
            "measurement":{"r_ohm":mr,"x_ohm":mx,"s11_db":mdb,"vswr":meas_vswr},
            "delta":{"r_ohm":dr,"x_ohm":dx,"s11_db":ddb,"vswr":dvswr}
        })
        drs.append(dr); dxs.append(dx); ddbs.append(ddb)
        if dvswr is not None and math.isfinite(dvswr): dvswrs.append(dvswr)
    if not rows: raise ValueError("simulation and measurement frequency ranges do not overlap")
    mres=_resonance(ms)
    sres=float(sweep.get("resonance_frequency_hz")) if sweep.get("resonance_frequency_hz") is not None else _resonance(ss)
    return {
        "schema_version":"0.1",
        "alignment":"interpolate-measured-to-simulation",
        "overlap":{"start_hz":rows[0]["frequency_hz"],"stop_hz":rows[-1]["frequency_hz"],"points":len(rows)},
        "summary":{
            "delta_r_ohm":_summary(drs),
            "delta_x_ohm":_summary(dxs),
            "delta_s11_db":_summary(ddbs),
            "delta_vswr":_summary(dvswrs),
            "measurement_resonance_hz":mres,
            "simulation_resonance_hz":sres,
            "resonance_shift_hz":(sres-mres) if sres is not None and mres is not None else None
        },
        "samples":rows
    }
