#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
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

def synthesize_template(template_id: str, target_frequency_hz: float) -> dict:
    if not math.isfinite(target_frequency_hz) or target_frequency_hz <= 0:
        raise ValueError("frequency_hz must be positive")
    registry=load_json(TEMPLATE_REGISTRY)
    item=next((x for x in registry.get("templates",[]) if x.get("id")==template_id),None)
    if item is None: raise ValueError("unknown template")
    if item.get("status")!="implemented": raise ValueError("template is not implemented")
    project=load_json(ROOT/item["seed_model"])
    seed_frequency=float(project["frequency_hz"])
    scale=seed_frequency/target_frequency_hz
    for wire in project.get("wires",[]):
        wire["start_m"]=scale_xyz(wire["start_m"],scale)
        wire["end_m"]=scale_xyz(wire["end_m"],scale)
        wire["radius_m"]=float(wire["radius_m"])*scale
    ground=project.get("ground")
    if isinstance(ground,dict) and "plane_z_m" in ground:
        ground["plane_z_m"]=float(ground["plane_z_m"])*scale
    for feed in project.get("feeds",[]):
        if "source_span_m" in feed: feed["source_span_m"]=float(feed["source_span_m"])*scale
    for var in project.get("design_variables",[]):
        if var.get("kind") in {"wire_length_m","wire_center_x_m"}:
            var["min"]=float(var["min"])*scale; var["max"]=float(var["max"])*scale
    for con in project.get("design_constraints",[]):
        if con.get("kind") in {"min_center_x_gap_m","wire_length_order_min_delta_m","max_boom_length_m"}:
            con["value"]=float(con["value"])*scale
    project["schema_version"]="0.5"
    project["frequency_hz"]=target_frequency_hz
    project["name"]=f'{item["label"]} synthesized at {target_frequency_hz/1e6:.6f} MHz'
    return {"template_id":template_id,"method":registry["synthesis_method"],"seed_model":item["seed_model"],"scale":scale,"project":project}


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
        if parsed.path.startswith("/api/template/"):
            try:
                template_id=urllib.parse.unquote(parsed.path.split("/api/template/",1)[1])
                qs=urllib.parse.parse_qs(parsed.query)
                frequency_hz=float(qs.get("frequency_hz",["0"])[0])
                self.send_json(synthesize_template(template_id,frequency_hz))
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
        if parsed.path not in {"/api/model-check","/api/solve","/api/sweep","/api/optimize"}:
            self.send_json({"error":"Not found"},HTTPStatus.NOT_FOUND); return
        try:
            body=self.read_json(); project=body.get("project")
            if not isinstance(project,dict): raise ValueError("project must be a JSON object")
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
