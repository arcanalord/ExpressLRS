#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import subprocess
import tempfile
import urllib.parse
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATIC = Path(__file__).resolve().parent / "static"
BENCHMARKS = ROOT / "benchmarks"
PRODUCT_REGISTRY = ROOT / "apps" / "shared" / "product" / "product-registry.json"
TEMPLATE_REGISTRY = ROOT / "apps" / "shared" / "product" / "template-registry.json"
MATERIALS_REGISTRY = ROOT / "apps" / "shared" / "product" / "materials-registry.json"
MEASUREMENT_SCHEMA = ROOT / "schemas" / "measurement-set-0.1.schema.json"
MEASUREMENT_MODULE = ROOT / "apps" / "shared" / "product" / "measurement.py"
WORKFLOW_MODULE = ROOT / "apps" / "shared" / "product" / "workflow_artifacts.py"
DESIGN_VARIANT_SCHEMA = ROOT / "schemas" / "design-variant-0.1.schema.json"
MEASUREMENT_SET_V2_SCHEMA = ROOT / "schemas" / "measurement-set-0.2.schema.json"
ENGINEERING_REPORT_SCHEMA = ROOT / "schemas" / "engineering-report-0.1.schema.json"
_ms=importlib.util.spec_from_file_location("emnext_measurement",MEASUREMENT_MODULE)
measurement=importlib.util.module_from_spec(_ms); _ms.loader.exec_module(measurement)
_ws=importlib.util.spec_from_file_location("emnext_workflow",WORKFLOW_MODULE)
workflow=importlib.util.module_from_spec(_ws); _ws.loader.exec_module(workflow)
DEFAULT_BINARY = ROOT / "build-linux" / "emnext"


def canonical_cache_key(kind: str, version: str, binary: Path, payload: dict) -> str:
    stat = binary.stat()
    envelope = {
        "kind": kind,
        "version": version,
        "binary_size": stat.st_size,
        "binary_mtime_ns": stat.st_mtime_ns,
        "parallel_workers": os.environ.get("EMNEXT_PARALLEL_WORKERS", "auto"),
        "payload": payload,
    }
    canonical = json.dumps(envelope, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


class DiskCache:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.memory: dict[str, dict] = {}

    def path_for(self, key: str) -> Path:
        return self.root / f"{key}.json"

    def get(self, key: str):
        if key in self.memory:
            value = dict(self.memory[key]); value["cache_hit"] = True; value["cache_source"] = "memory"; return value
        p = self.path_for(key)
        if not p.exists(): return None
        try:
            value = json.loads(p.read_text(encoding="utf-8"))
            if not isinstance(value, dict): return None
            self.memory[key] = value
            out = dict(value); out["cache_hit"] = True; out["cache_source"] = "disk"; return out
        except Exception:
            return None

    def put(self, key: str, value: dict):
        clean = dict(value); clean["cache_hit"] = False; clean["cache_source"] = "computed"; self.memory[key] = clean
        dst = self.path_for(key); tmp = dst.with_suffix(".tmp")
        tmp.write_text(json.dumps(clean, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"); tmp.replace(dst)

    def stats(self):
        files = list(self.root.glob("*.json"))
        return {"entries": len(files), "bytes": sum(x.stat().st_size for x in files if x.is_file()), "path": str(self.root)}


def json_bytes(obj) -> bytes:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def safe_example_name(name: str) -> str:
    base = Path(name).name
    if base != name or not base.endswith(".emnx"): raise ValueError("Invalid example name")
    return base


def dmax_from_result(result: dict) -> float:
    values = [float(x.get("directivity_linear", 0.0)) for x in result.get("pattern", [])]
    return max(values, default=0.0)


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))

def scale_xyz(v, scale: float):
    return [float(x) * scale for x in v]

def wire_length(w):
    a,b=w["start_m"],w["end_m"]
    return math.sqrt(sum((float(b[i])-float(a[i]))**2 for i in range(3)))

def set_wire_length(w, length: float, anchor="center"):
    a=[float(x) for x in w["start_m"]]; b=[float(x) for x in w["end_m"]]
    dx=[b[i]-a[i] for i in range(3)]; old=math.sqrt(sum(x*x for x in dx))
    if old <= 0 or length <= 0: raise ValueError("wire length must be positive")
    u=[x/old for x in dx]
    if anchor=="start": w["end_m"]=[a[i]+u[i]*length for i in range(3)]; return
    c=[(a[i]+b[i])/2 for i in range(3)]; h=length/2
    w["start_m"]=[c[i]-u[i]*h for i in range(3)]; w["end_m"]=[c[i]+u[i]*h for i in range(3)]

def wire_center_x(w): return (float(w["start_m"][0])+float(w["end_m"][0]))/2

def set_wire_center_x(w, x):
    dx=float(x)-wire_center_x(w); w["start_m"][0]+=dx; w["end_m"][0]+=dx

def odd_segments(value):
    n=max(3,int(round(value))); return n if n%2 else n+1

def parameter_default(spec: dict, wavelength: float):
    if "default_lambda" in spec: return float(spec["default_lambda"])*wavelength
    return float(spec.get("default",0))

def parameter_bounds(spec: dict, wavelength: float):
    lo=float(spec["min_lambda"])*wavelength if "min_lambda" in spec else spec.get("min")
    hi=float(spec["max_lambda"])*wavelength if "max_lambda" in spec else spec.get("max")
    return (None if lo is None else float(lo),None if hi is None else float(hi))

def resolve_template_parameters(item: dict, target_frequency_hz: float, raw: dict) -> dict:
    wavelength=299792458.0/target_frequency_hz; out={}
    for spec in item.get("parameters",[]):
        name=spec["id"]; val=float(raw.get(name,parameter_default(spec,wavelength)))
        lo,hi=parameter_bounds(spec,wavelength)
        if lo is not None and val < lo-1e-12: raise ValueError(f"{name} below minimum")
        if hi is not None and val > hi+1e-12: raise ValueError(f"{name} above maximum")
        if spec.get("ui_unit")=="count": val=odd_segments(val)
        out[name]=val
    return out

def apply_template_binding(project: dict, binding: dict, value: float):
    wires={w["id"]:w for w in project.get("wires",[])}; kind=binding.get("kind")
    if kind=="wire_length": set_wire_length(wires[binding["wire_id"]],value); return
    if kind=="wire_length_from_start": set_wire_length(wires[binding["wire_id"]],value,"start"); return
    if kind=="wire_diameter_all":
        for w in wires.values(): w["radius_m"]=value/2
        return
    if kind=="wire_segments_all":
        n=odd_segments(value)
        for w in wires.values(): w["segments"]=n
        for feed in project.get("feeds",[]):
            if feed.get("mode","center") not in {"ground-terminal-start","ground-terminal-end"}: feed["segment"]=(n-1)//2
        return
    if kind=="center_gap_x": set_wire_center_x(wires[binding["wire_b"]],wire_center_x(wires[binding["wire_a"]])+value); return
    if kind=="yagi_director_spacing":
        dirs=sorted((w for k,w in wires.items() if k.startswith("DIR")),key=lambda w:int(w["id"][3:]))
        if dirs:
            x0=wire_center_x(dirs[0])
            for i,w in enumerate(dirs[1:],1): set_wire_center_x(w,x0+value*i)
        return
    if kind=="yagi_director_step":
        dirs=sorted((w for k,w in wires.items() if k.startswith("DIR")),key=lambda w:int(w["id"][3:]))
        if dirs:
            l0=wire_length(dirs[0])
            for i,w in enumerate(dirs[1:],1): set_wire_length(w,max(l0-value*i,l0*0.55))
        return
    if kind=="square_side":
        h=value/2; pts=[[-h,0,-h],[h,0,-h],[h,0,h],[-h,0,h]]
        order=["W1","W2","W3","W4"]
        for i,k in enumerate(order): wires[k]["start_m"]=pts[i]; wires[k]["end_m"]=pts[(i+1)%4]
        return
    if kind in {"moxon_span","moxon_spacing","moxon_end_gap"}:
        span=wire_length(wires["DRV"]); spacing=wire_center_x(wires["REF"])-wire_center_x(wires["DRV"])
        if kind=="moxon_span": span=value
        if kind=="moxon_spacing": spacing=value
        # current end gap from top fold endpoints
        current_gap=float(wires["RTOP"]["end_m"][0])-float(wires["DTOP"]["end_m"][0])
        gap=value if kind=="moxon_end_gap" else current_gap
        if gap<=0 or gap>=spacing: raise ValueError("Moxon end gap must be between 0 and spacing")
        z=span/2; fold=(spacing-gap)/2
        wires["DRV"]["start_m"]=[0,0,-z];wires["DRV"]["end_m"]=[0,0,z]
        wires["REF"]["start_m"]=[spacing,0,-z];wires["REF"]["end_m"]=[spacing,0,z]
        wires["DTOP"]["start_m"]=[0,0,z];wires["DTOP"]["end_m"]=[fold,0,z]
        wires["DBOT"]["start_m"]=[0,0,-z];wires["DBOT"]["end_m"]=[fold,0,-z]
        wires["RTOP"]["start_m"]=[spacing,0,z];wires["RTOP"]["end_m"]=[spacing-fold,0,z]
        wires["RBOT"]["start_m"]=[spacing,0,-z];wires["RBOT"]["end_m"]=[spacing-fold,0,-z]
        return
    raise ValueError(f"unsupported template binding: {kind}")

def refresh_yagi_design_contract(project: dict):
    wires={w["id"]:w for w in project.get("wires",[])}; ids=["REF","DRV"]+sorted([k for k in wires if k.startswith("DIR")],key=lambda x:int(x[3:]))
    variables=[]
    for wid in ids:
        l=wire_length(wires[wid]); variables.append({"id":wid.lower()+"_length","kind":"wire_length_m","wire_id":wid,"min":l*.88,"max":l*1.12})
    for wid in ids[1:]:
        x=wire_center_x(wires[wid]); variables.append({"id":wid.lower()+"_x","kind":"wire_center_x_m","wire_id":wid,"min":max(0,x*.78),"max":x*1.22+0.01})
    constraints=[]
    for a,b in zip(ids,ids[1:]):
        gap=wire_center_x(wires[b])-wire_center_x(wires[a]); constraints.append({"id":a.lower()+"_to_"+b.lower()+"_gap","kind":"min_center_x_gap_m","wire_a":a,"wire_b":b,"value":max(.005,gap*.55)})
    for a,b in zip(ids,ids[1:]):
        la,lb=wire_length(wires[a]),wire_length(wires[b]); constraints.append({"id":a.lower()+"_longer_"+b.lower(),"kind":"wire_length_order_min_delta_m","wire_a":a,"wire_b":b,"value":max(.001,(la-lb)*.25)})
    boom=max(wire_center_x(wires[k]) for k in ids)-min(wire_center_x(wires[k]) for k in ids)
    constraints.append({"id":"max_boom","kind":"max_boom_length_m","value":boom*1.25+.01})
    project["design_variables"]=variables; project["design_constraints"]=constraints

def synthesize_template(template_id: str, target_frequency_hz: float, raw_parameters: dict|None=None) -> dict:
    if not math.isfinite(target_frequency_hz) or target_frequency_hz <= 0: raise ValueError("frequency_hz must be positive")
    registry=load_json(TEMPLATE_REGISTRY); item=next((x for x in registry.get("templates",[]) if x.get("id")==template_id),None)
    if item is None: raise ValueError("unknown template")
    if item.get("status")!="implemented": raise ValueError("template is not implemented")
    project=load_json(ROOT/item["seed_model"]); seed_frequency=float(project["frequency_hz"]); scale=seed_frequency/target_frequency_hz
    for wire in project.get("wires",[]): wire["start_m"]=scale_xyz(wire["start_m"],scale);wire["end_m"]=scale_xyz(wire["end_m"],scale);wire["radius_m"]=float(wire["radius_m"])*scale
    ground=project.get("ground")
    if isinstance(ground,dict) and "plane_z_m" in ground: ground["plane_z_m"]=float(ground["plane_z_m"])*scale
    for feed in project.get("feeds",[]):
        if "source_span_m" in feed: feed["source_span_m"]=float(feed["source_span_m"])*scale
    params=resolve_template_parameters(item,target_frequency_hz,raw_parameters or {})
    for spec in item.get("parameters",[]): apply_template_binding(project,spec["binding"],params[spec["id"]])
    if item.get("family")=="yagi": refresh_yagi_design_contract(project)
    else: project.pop("design_variables",None); project.pop("design_constraints",None)
    project["schema_version"]="0.5"; project["frequency_hz"]=target_frequency_hz; project["name"]=f'{item["label"]} synthesized at {target_frequency_hz/1e6:.6f} MHz'
    return {"template_id":template_id,"method":registry["synthesis_method"],"seed_model":item["seed_model"],"scale":scale,"parameters":params,"supports_optimizer":bool(item.get("supports_optimizer")),"project":project}


class Handler(SimpleHTTPRequestHandler):
    server_version = "EMManaNextLinux/0.1"
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(STATIC), **kwargs)
    @property
    def emnext(self) -> Path: return Path(self.server.emnext_binary)  # type: ignore[attr-defined]
    @property
    def cache(self) -> DiskCache: return self.server.cache  # type: ignore[attr-defined]
    @property
    def version(self) -> str: return self.server.app_version  # type: ignore[attr-defined]
    def log_message(self, fmt: str, *args) -> None: print("[linux-ui] " + (fmt % args))
    def send_json(self, obj, status=HTTPStatus.OK):
        body = json_bytes(obj); self.send_response(status); self.send_header("Content-Type", "application/json; charset=utf-8"); self.send_header("Content-Length", str(len(body))); self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(body)
    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 2_000_000: raise ValueError("Invalid request size")
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/health":
            self.send_json({"ok": self.emnext.exists(), "version": (ROOT / "VERSION").read_text(encoding="utf-8").strip(), "binary": str(self.emnext)}); return
        if parsed.path == "/api/cache": self.send_json({"ok": True, **self.cache.stats()}); return
        if parsed.path == "/api/reference-status":
            candidates = sorted(BENCHMARKS.glob("REFERENCE_STATUS_ALPHA*.json")); status_path = candidates[-1] if candidates else BENCHMARKS / "REFERENCE_STATUS_ALPHA17.json"
            try: self.send_json(json.loads(status_path.read_text(encoding="utf-8")))
            except FileNotFoundError: self.send_json({"schema_version":"0.1","independent_reference":{"local_status":"unknown","ci_status":"unknown"}})
            return
        if parsed.path == "/api/product-registry":
            try: self.send_json(json.loads(PRODUCT_REGISTRY.read_text(encoding="utf-8")))
            except Exception as e: self.send_json({"error": str(e)}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        if parsed.path == "/api/templates":
            try: self.send_json(load_json(TEMPLATE_REGISTRY))
            except Exception as e: self.send_json({"error": str(e)}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        if parsed.path == "/api/materials":
            try: self.send_json(load_json(MATERIALS_REGISTRY))
            except Exception as e: self.send_json({"error": str(e)}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        if parsed.path == "/api/measurement-contract":
            try: self.send_json(load_json(MEASUREMENT_SCHEMA))
            except Exception as e: self.send_json({"error": str(e)}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        if parsed.path == "/api/design-variant-contract": self.send_json(load_json(DESIGN_VARIANT_SCHEMA)); return
        if parsed.path == "/api/measurement-set-contract": self.send_json(load_json(MEASUREMENT_SET_V2_SCHEMA)); return
        if parsed.path == "/api/engineering-report-contract": self.send_json(load_json(ENGINEERING_REPORT_SCHEMA)); return
        if parsed.path.startswith("/api/template/"):
            try:
                template_id=urllib.parse.unquote(parsed.path.split("/api/template/",1)[1])
                qs=urllib.parse.parse_qs(parsed.query)
                frequency_hz=float(qs.get("frequency_hz",["0"])[0])
                raw={k:v[0] for k,v in qs.items() if k!="frequency_hz" and v}
                self.send_json(synthesize_template(template_id,frequency_hz,raw))
            except Exception as e: self.send_json({"error":str(e)},HTTPStatus.BAD_REQUEST)
            return
        if parsed.path == "/api/help-registry":
            p = ROOT / "apps" / "shared" / "help" / "help-registry.json"
            try: self.send_json(json.loads(p.read_text(encoding="utf-8")))
            except Exception as e: self.send_json({"error": str(e)}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        if parsed.path == "/api/examples":
            items=[]
            for p in sorted(BENCHMARKS.glob("*.emnx")):
                try:
                    data=json.loads(p.read_text(encoding="utf-8")); items.append({"file":p.name,"name":data.get("name",p.stem),"frequency_hz":data.get("frequency_hz"),"wires":len(data.get("wires",[]))})
                except Exception: continue
            self.send_json({"examples":items}); return
        if parsed.path.startswith("/api/example/"):
            try:
                name=safe_example_name(urllib.parse.unquote(parsed.path.split("/api/example/",1)[1])); p=BENCHMARKS/name; self.send_json(json.loads(p.read_text(encoding="utf-8")))
            except FileNotFoundError: self.send_json({"error":"Example not found"},HTTPStatus.NOT_FOUND)
            except Exception as e: self.send_json({"error":str(e)},HTTPStatus.BAD_REQUEST)
            return
        super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path not in {"/api/model-check","/api/solve","/api/sweep","/api/optimize","/api/measurement/parse","/api/measurement/compare","/api/variant/create","/api/measurement/bind","/api/report/generate"}:
            self.send_json({"error":"Not found"},HTTPStatus.NOT_FOUND); return
        try:
            body=self.read_json()
            if parsed.path == "/api/measurement/parse":
                fmt=str(body.get("format","touchstone-s1p")); text=str(body.get("text","")); name=str(body.get("source_name","inline"))
                parsed_measurement=measurement.parse_measurement(fmt,text,name,float(body.get("reference_impedance_ohm",50.0)))
                self.send_json({"ok":True,"measurement":parsed_measurement}); return
            if parsed.path == "/api/measurement/compare":
                ms=body.get("measurement"); sw=body.get("sweep")
                if not isinstance(ms,dict) or not isinstance(sw,dict): raise ValueError("measurement and sweep must be objects")
                self.send_json({"ok":True,"comparison":measurement.compare_measurement_to_sweep(ms,sw)}); return
            if parsed.path == "/api/measurement/bind":
                variant=body.get("variant"); ms=body.get("measurement"); raw_text=body.get("raw_text")
                if not isinstance(variant,dict) or not isinstance(ms,dict) or not isinstance(raw_text,str): raise ValueError("variant, measurement and raw_text are required")
                calibration=body.get("calibration") if isinstance(body.get("calibration"),dict) else {}
                provenance=body.get("provenance") if isinstance(body.get("provenance"),dict) else {}
                bound=workflow.create_measurement_set(str(body.get("measurement_id","measurement-1")),variant,ms,raw_text,calibration,provenance)
                self.send_json({"ok":True,"measurement_set":bound}); return
            if parsed.path == "/api/report/generate":
                variant=body.get("variant"); mset=body.get("measurement_set"); sw=body.get("sweep"); ms=body.get("measurement"); cmp=body.get("comparison")
                if not all(isinstance(x,dict) for x in (variant,mset,sw,ms,cmp)): raise ValueError("variant, measurement_set, sweep, measurement and comparison are required")
                candidates=sorted(BENCHMARKS.glob("REFERENCE_STATUS_ALPHA*.json")); ref=load_json(candidates[-1]) if candidates else {}
                report=workflow.generate_engineering_report(variant,mset,sw,ms,cmp,ref)
                self.send_json({"ok":True,"report":report}); return
            project=body.get("project")
            if not isinstance(project,dict): raise ValueError("project must be a JSON object")
            if parsed.path == "/api/variant/create":
                with tempfile.TemporaryDirectory(prefix="emnext-variant-") as td:
                    project_path=Path(td)/"project.emnx"; project_path.write_text(json.dumps(project,ensure_ascii=False,indent=2),encoding="utf-8")
                    proc=subprocess.run([str(self.emnext),"model-check",str(project_path)],text=True,capture_output=True,timeout=30)
                    if proc.returncode!=0: self.send_json({"ok":False,"stdout":proc.stdout,"stderr":proc.stderr},HTTPStatus.UNPROCESSABLE_ENTITY); return
                    model_hash=next((line.split("Model hash:",1)[1].strip() for line in proc.stdout.splitlines() if line.startswith("Model hash:")),None)
                    if not model_hash: raise ValueError("model-check did not return model hash")
                    variant=workflow.create_design_variant(str(body.get("variant_id","variant-1")),str(body.get("name",project.get("name","Design Variant"))),model_hash,str(body.get("model_hash_algorithm","fnv1a64-emnext-model-v3")),body.get("parent_variant_id"),body.get("tags") if isinstance(body.get("tags"),list) else [],str(body.get("notes","")))
                    self.send_json({"ok":True,"variant":variant,"model_check_stdout":proc.stdout}); return
            kernel=body.get("kernel","reduced")
            if kernel not in {"reduced","exact"}: raise ValueError("kernel must be reduced or exact")
            parallel_workers=int(body.get("parallel_workers", os.environ.get("EMNEXT_PARALLEL_WORKERS","4") if os.environ.get("EMNEXT_PARALLEL_WORKERS","auto") != "auto" else 4))
            if parallel_workers < 1 or parallel_workers > 16: raise ValueError("parallel_workers must be in [1,16]")
            run_env=dict(os.environ); run_env["EMNEXT_PARALLEL_WORKERS"]=str(parallel_workers); run_env.setdefault("OPENBLAS_NUM_THREADS","1"); run_env.setdefault("OMP_NUM_THREADS","1"); run_env.setdefault("MKL_NUM_THREADS","1")
            with tempfile.TemporaryDirectory(prefix="emnext-ui-") as td:
                td_path=Path(td); project_path=td_path/"project.emnx"; project_path.write_text(json.dumps(project,ensure_ascii=False,indent=2),encoding="utf-8")
                if parsed.path == "/api/model-check":
                    proc=subprocess.run([str(self.emnext),"model-check",str(project_path)],text=True,capture_output=True,timeout=30)
                    self.send_json({"ok":proc.returncode==0,"returncode":proc.returncode,"stdout":proc.stdout,"stderr":proc.stderr},HTTPStatus.OK if proc.returncode==0 else HTTPStatus.UNPROCESSABLE_ENTITY); return
                if parsed.path == "/api/optimize":
                    population=int(body.get("population",10)); generations=int(body.get("generations",6)); seed=int(body.get("seed",42)); algorithm=str(body.get("algorithm","staged")); local_iterations=int(body.get("local_iterations",12)); weights=body.get("weights",{})
                    if not isinstance(weights,dict): raise ValueError("weights must be an object")
                    weight_match=float(weights.get("match",0.40)); weight_gain=float(weights.get("gain",0.30)); weight_fb=float(weights.get("front_to_back",0.20)); weight_size=float(weights.get("size",0.10)); gain_guardrail_db=float(body.get("gain_guardrail_db",0.50)); max_vswr=float(body.get("max_vswr",2.0)); band_start_hz=float(body.get("band_start_hz",0.0)); band_stop_hz=float(body.get("band_stop_hz",0.0)); band_points=int(body.get("band_points",1)); quantization_step_m=float(body.get("quantization_step_m",0.0)); manufacturing_tolerance_m=float(body.get("manufacturing_tolerance_m",0.0)); robust_objective_samples=int(body.get("robust_objective_samples",4)); monte_carlo_samples=int(body.get("monte_carlo_samples",32))
                    if any(x<0 for x in (weight_match,weight_gain,weight_fb,weight_size)) or (weight_match+weight_gain+weight_fb+weight_size)<=0: raise ValueError("objective weights must be non-negative and not all zero")
                    if not (0<=gain_guardrail_db<=20): raise ValueError("gain_guardrail_db must be in [0,20]")
                    if not (1<=max_vswr<=100): raise ValueError("max_vswr must be in [1,100]")
                    if band_points<1 or band_points>11: raise ValueError("band_points must be in [1,11]")
                    if band_points>1 and not (band_start_hz>0 and band_stop_hz>band_start_hz): raise ValueError("band mode requires 0 < start < stop")
                    if not (0<=quantization_step_m<=0.05): raise ValueError("quantization_step_m must be in [0,0.05]")
                    if not (0<=manufacturing_tolerance_m<=0.02): raise ValueError("manufacturing_tolerance_m must be in [0,0.02]")
                    if robust_objective_samples<0 or robust_objective_samples>16: raise ValueError("robust_objective_samples must be in [0,16]")
                    if monte_carlo_samples<0 or monte_carlo_samples>128: raise ValueError("monte_carlo_samples must be in [0,128]")
                    if (robust_objective_samples>0 or monte_carlo_samples>0) and manufacturing_tolerance_m<=0: raise ValueError("robust/Monte-Carlo sampling requires tolerance > 0")
                    if population<4 or population>32: raise ValueError("UI optimizer population must be in [4, 32]")
                    if generations<1 or generations>30: raise ValueError("UI optimizer generations must be in [1, 30]")
                    if local_iterations<0 or local_iterations>40: raise ValueError("UI optimizer local_iterations must be in [0, 40]")
                    if algorithm not in {"de","pso","staged"}: raise ValueError("optimizer algorithm must be de, pso, or staged")
                    if seed<0: raise ValueError("optimizer seed must be >= 0")
                    cache_payload={"project":project,"kernel":kernel,"population":population,"generations":generations,"seed":seed,"algorithm":algorithm,"local_iterations":local_iterations,"weights":{"match":weight_match,"gain":weight_gain,"front_to_back":weight_fb,"size":weight_size},"gain_guardrail_db":gain_guardrail_db,"max_vswr":max_vswr,"band_start_hz":band_start_hz,"band_stop_hz":band_stop_hz,"band_points":band_points,"quantization_step_m":quantization_step_m,"manufacturing_tolerance_m":manufacturing_tolerance_m,"robust_objective_samples":robust_objective_samples,"monte_carlo_samples":monte_carlo_samples,"parallel_workers":parallel_workers}
                    cache_key=canonical_cache_key("optimize",self.version,self.emnext,cache_payload); cached=self.cache.get(cache_key)
                    if cached is not None: self.send_json(cached); return
                    optimizer_path=td_path/"optimizer.json"
                    proc=subprocess.run([str(self.emnext),"optimize-exp-json",str(project_path),str(population),str(generations),str(seed),str(optimizer_path),kernel,algorithm,str(local_iterations),str(weight_match),str(weight_gain),str(weight_fb),str(weight_size),str(gain_guardrail_db),str(max_vswr),str(band_start_hz),str(band_stop_hz),str(band_points),str(quantization_step_m),str(manufacturing_tolerance_m),str(robust_objective_samples),str(monte_carlo_samples)],text=True,capture_output=True,timeout=900,env=run_env)
                    if proc.returncode!=0 or not optimizer_path.exists(): self.send_json({"ok":False,"returncode":proc.returncode,"stdout":proc.stdout,"stderr":proc.stderr},HTTPStatus.UNPROCESSABLE_ENTITY); return
                    payload={"ok":True,"optimizer":json.loads(optimizer_path.read_text(encoding="utf-8")),"stdout":proc.stdout,"cache_hit":False,"cache_source":"computed"}; self.cache.put(cache_key,payload); self.send_json(payload); return
                if parsed.path == "/api/sweep":
                    start_hz=float(body.get("start_hz",0.0)); stop_hz=float(body.get("stop_hz",0.0)); points=int(body.get("points",0))
                    if not (start_hz>0 and stop_hz>=start_hz): raise ValueError("invalid sweep frequency range")
                    if points<2 or points>81: raise ValueError("UI sweep points must be in [2, 81]")
                    cache_payload={"project":project,"kernel":kernel,"start_hz":start_hz,"stop_hz":stop_hz,"points":points,"parallel_workers":parallel_workers}; cache_key=canonical_cache_key("sweep",self.version,self.emnext,cache_payload); cached=self.cache.get(cache_key)
                    if cached is not None: self.send_json(cached); return
                    sweep_path=td_path/"sweep.json"; proc=subprocess.run([str(self.emnext),"sweep-exp-json",str(project_path),str(start_hz),str(stop_hz),str(points),str(sweep_path),kernel],text=True,capture_output=True,timeout=300,env=run_env)
                    if proc.returncode!=0 or not sweep_path.exists(): self.send_json({"ok":False,"returncode":proc.returncode,"stdout":proc.stdout,"stderr":proc.stderr},HTTPStatus.UNPROCESSABLE_ENTITY); return
                    payload={"ok":True,"sweep":json.loads(sweep_path.read_text(encoding="utf-8")),"stdout":proc.stdout,"cache_hit":False,"cache_source":"computed"}; self.cache.put(cache_key,payload); self.send_json(payload); return
                solve_payload={"project":project,"kernel":kernel}; solve_cache_key=canonical_cache_key("solve",self.version,self.emnext,solve_payload); cached_solve=self.cache.get(solve_cache_key)
                if cached_solve is not None: self.send_json(cached_solve); return
                result_path=td_path/"result.json"; cmd="solve-exp-json" if kernel=="reduced" else "solve-exp-exact-json"; proc=subprocess.run([str(self.emnext),cmd,str(project_path),str(result_path)],text=True,capture_output=True,timeout=120)
                if proc.returncode!=0 or not result_path.exists(): self.send_json({"ok":False,"returncode":proc.returncode,"stdout":proc.stdout,"stderr":proc.stderr},HTTPStatus.UNPROCESSABLE_ENTITY); return
                result=json.loads(result_path.read_text(encoding="utf-8")); dmax=dmax_from_result(result); result["summary"]={"dmax_linear":dmax,"dmax_dbi":10.0*math.log10(dmax) if dmax>0 else None}; payload={"ok":True,"result":result,"stdout":proc.stdout,"cache_hit":False,"cache_source":"computed"}; self.cache.put(solve_cache_key,payload); self.send_json(payload)
        except subprocess.TimeoutExpired: self.send_json({"error":"Solver timeout"},HTTPStatus.GATEWAY_TIMEOUT)
        except Exception as e: self.send_json({"error":str(e)},HTTPStatus.BAD_REQUEST)


def main() -> int:
    parser=argparse.ArgumentParser(description="EMMana-Next lightweight Linux UI"); parser.add_argument("--host",default="127.0.0.1"); parser.add_argument("--port",type=int,default=8787); parser.add_argument("--binary",default=os.environ.get("EMNEXT_BINARY",str(DEFAULT_BINARY))); parser.add_argument("--cache-dir",default=os.environ.get("EMNEXT_CACHE_DIR",str(Path.home()/".cache"/"emnext"))); args=parser.parse_args()
    binary=Path(args.binary).resolve()
    if not binary.exists(): raise SystemExit(f"EMMana-Next binary not found: {binary}")
    httpd=ThreadingHTTPServer((args.host,args.port),Handler); httpd.emnext_binary=str(binary); httpd.app_version=(ROOT/"VERSION").read_text(encoding="utf-8").strip(); httpd.cache=DiskCache(Path(args.cache_dir).expanduser().resolve())
    print(f"EMMana-Next Linux UI: http://{args.host}:{args.port}"); print(f"Solver: {binary}"); print(f"Cache: {httpd.cache.root}")
    try: httpd.serve_forever()
    except KeyboardInterrupt: pass
    finally: httpd.server_close()
    return 0

if __name__ == "__main__": raise SystemExit(main())