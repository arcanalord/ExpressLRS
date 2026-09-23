from pathlib import Path
import re

root = Path("src/emmana_rev25")
static = root / "apps/linux_web/static"
version = "0.1.0-alpha.20-rev26"

def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f"rev26 patch anchor missing: {label}")
    return text.replace(old, new, 1)

(root / "VERSION").write_text(version + "\n", encoding="utf-8")

html_path = static / "index.html"
html = html_path.read_text(encoding="utf-8")

yagi_html = r'''
        <div id="yagi-quick-panel" class="yagi-quick-panel" hidden>
          <div class="yagi-quick-head">
            <div><small>ЯГИ · БЫСТРАЯ НАСТРОЙКА</small><h3>Размеры и расстояния</h3></div>
            <span id="yagi-quick-state">3 элемента</span>
          </div>
          <div class="yagi-quick-fields">
            <label>Рефлектор, см<input id="yagi-ref-length" type="number" min="1" step="0.1"></label>
            <label>Активный, см<input id="yagi-drv-length" type="number" min="1" step="0.1"></label>
            <label>Директор, см<input id="yagi-dir-length" type="number" min="1" step="0.1"></label>
            <label>REF → DRV, см<input id="yagi-gap-1" type="number" min="0.1" step="0.1"></label>
            <label>DRV → DIR, см<input id="yagi-gap-2" type="number" min="0.1" step="0.1"></label>
            <label>Диаметр, мм<input id="yagi-diameter" type="number" min="0.1" step="0.1"></label>
            <label>Сегментов<input id="yagi-segments" type="number" min="3" step="2"></label>
          </div>
          <div class="yagi-quick-actions">
            <button id="yagi-apply" class="secondary" type="button">Применить геометрию</button>
            <button id="yagi-recalc" class="primary" type="button">Рассчитать изменения</button>
            <button id="yagi-optimize" class="secondary" type="button">Быстрая оптимизация</button>
          </div>
          <p class="yagi-quick-note">Элементы можно также двигать мышью в 2D. Поля синхронизируются с геометрией; после любого изменения старый расчёт помечается устаревшим.</p>
        </div>
'''
html = replace_once(html, '        <div class="geometry-toolbar">', yagi_html + '        <div class="geometry-toolbar">', "geometry toolbar")

measurement_guide = r'''
      <div class="flow-guide measurement-guide">
        <div><b>Как проверить измерения</b><span>1 · Выполните частотный расчёт</span><span>2 · Импортируйте S1P/CSV</span><span>3 · Нажмите «Сравнить»</span></div>
        <button id="measurement-demo" class="secondary" type="button">Тестовые данные</button>
        <small>Тестовые данные строятся из текущего Sweep и помечаются как демо — это не реальное измерение VNA.</small>
      </div>
'''
html = replace_once(html, '      <div class="measurement-toolbar">', measurement_guide + '      <div class="measurement-toolbar">', "measurement toolbar")

optimizer_guide = r'''
      <div class="flow-guide optimizer-guide">
        <b>Простой режим</b>
        <span>1 · В «Геометрии» выберите «Яги, 3 элемента»</span>
        <span>2 · Измените размеры вручную или мышью</span>
        <span>3 · Запустите оптимизацию и примените лучший вариант</span>
      </div>
'''
html = replace_once(html, '      <div class="optimizer-grid">', optimizer_guide + '      <div class="optimizer-grid">', "optimizer grid")
html_path.write_text(html, encoding="utf-8")

css_path = static / "app.css"
css = css_path.read_text(encoding="utf-8")
css += r'''

/* rev26: clear antenna workflow */
.yagi-quick-panel{margin:0 0 12px;padding:13px;border:1px solid #2b3d57;border-radius:12px;background:linear-gradient(180deg,#101a28,#0c1119)}
.yagi-quick-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:10px}
.yagi-quick-head small{font-size:9px;letter-spacing:.1em;color:#82b5ff;font-weight:800}
.yagi-quick-head h3{margin:4px 0 0;font-size:15px}
.yagi-quick-head>span{color:#8fa8c9;font-size:10px}
.yagi-quick-fields{display:grid;grid-template-columns:repeat(4,minmax(110px,1fr));gap:8px}
.yagi-quick-fields label{font-size:9px;color:var(--muted)}
.yagi-quick-fields input{display:block;width:100%;margin-top:5px;background:#151b24;color:var(--text);border:1px solid #2a3546;border-radius:8px;padding:8px}
.yagi-quick-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:11px}
.yagi-quick-note{margin:10px 0 0;color:#8490a3;font-size:10px;line-height:1.45}
.flow-guide{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:0 0 12px;padding:11px 12px;border:1px solid #263449;border-radius:11px;background:#0d131c;color:#9aa7ba;font-size:10px}
.flow-guide>div{display:flex;align-items:center;gap:11px;flex-wrap:wrap}
.flow-guide b{color:#e3ebf7;font-size:11px}
.flow-guide small{color:#6f7b8d;flex:1 1 240px}
.optimizer-guide span{padding-left:10px;border-left:1px solid #293448}
@media(max-width:900px){.yagi-quick-fields{grid-template-columns:repeat(2,minmax(120px,1fr))}}
@media(max-width:650px){.yagi-quick-fields{grid-template-columns:1fr 1fr}.yagi-quick-actions>*{flex:1 1 100%}.flow-guide{align-items:stretch;flex-direction:column}.flow-guide>div{align-items:flex-start;flex-direction:column}.optimizer-guide span{padding-left:0;border-left:0}}
'''
css_path.write_text(css, encoding="utf-8")

js_path = static / "app.js"
js = js_path.read_text(encoding="utf-8")

old_end = "geometryTemplateStatus:$('#geometry-template-status')};"
new_end = """geometryTemplateStatus:$('#geometry-template-status'),yagiQuickPanel:$('#yagi-quick-panel'),yagiQuickState:$('#yagi-quick-state'),yagiRefLength:$('#yagi-ref-length'),yagiDrvLength:$('#yagi-drv-length'),yagiDirLength:$('#yagi-dir-length'),yagiGap1:$('#yagi-gap-1'),yagiGap2:$('#yagi-gap-2'),yagiDiameter:$('#yagi-diameter'),yagiSegments:$('#yagi-segments'),yagiApply:$('#yagi-apply'),yagiRecalc:$('#yagi-recalc'),yagiOptimize:$('#yagi-optimize'),measurementDemo:$('#measurement-demo')};"""
js = replace_once(js, old_end, new_end, "els map")

yagi_js = r'''
function yagiWire(p,id){return(p.wires||[]).find(w=>w.id===id)}
function yagiWireLength(w){if(!w)return NaN;return Math.hypot(w.end_m[0]-w.start_m[0],w.end_m[1]-w.start_m[1],w.end_m[2]-w.start_m[2])}
function yagiCenterX(w){return w?(Number(w.start_m[0])+Number(w.end_m[0]))/2:NaN}
function isYagiQuickProject(p){return !!(yagiWire(p,'REF')&&yagiWire(p,'DRV')&&yagiWire(p,'DIR1')&&(p.design_variables||[]).length)}
function setYagiWireLength(w,length){const a=w.start_m,b=w.end_m,dx=b[0]-a[0],dy=b[1]-a[1],dz=b[2]-a[2],old=Math.hypot(dx,dy,dz);if(!(old>0))throw new Error('Нулевая длина элемента');const ux=dx/old,uy=dy/old,uz=dz/old,mx=(a[0]+b[0])/2,my=(a[1]+b[1])/2,mz=(a[2]+b[2])/2,h=length/2;w.start_m=[mx-ux*h,my-uy*h,mz-uz*h];w.end_m=[mx+ux*h,my+uy*h,mz+uz*h]}
function setYagiCenterX(w,x){const old=yagiCenterX(w),dx=x-old;w.start_m[0]+=dx;w.end_m[0]+=dx}
function setYagiField(el,value,digits=2){if(el&&document.activeElement!==el&&Number.isFinite(value))el.value=Number(value).toFixed(digits)}
function syncYagiQuickPanel(p){
  if(!els.yagiQuickPanel)return;
  const ok=isYagiQuickProject(p);els.yagiQuickPanel.hidden=!ok;if(!ok)return;
  const ref=yagiWire(p,'REF'),drv=yagiWire(p,'DRV'),dir=yagiWire(p,'DIR1');
  setYagiField(els.yagiRefLength,100*yagiWireLength(ref));
  setYagiField(els.yagiDrvLength,100*yagiWireLength(drv));
  setYagiField(els.yagiDirLength,100*yagiWireLength(dir));
  setYagiField(els.yagiGap1,100*(yagiCenterX(drv)-yagiCenterX(ref)));
  setYagiField(els.yagiGap2,100*(yagiCenterX(dir)-yagiCenterX(drv)));
  setYagiField(els.yagiDiameter,2000*Number(drv.radius_m||0),2);
  if(els.yagiSegments&&document.activeElement!==els.yagiSegments)els.yagiSegments.value=String(Number(drv.segments||21));
  if(els.yagiQuickState)els.yagiQuickState.textContent='REF · DRV · DIR · редактирование в сантиметрах';
}
function applyYagiQuickPanel(){
  try{
    const p=project();if(!isYagiQuickProject(p))throw new Error('Откройте шаблон «Яги, 3 элемента»');
    const ref=yagiWire(p,'REF'),drv=yagiWire(p,'DRV'),dir=yagiWire(p,'DIR1');
    const lr=Number(els.yagiRefLength.value)/100,ld=Number(els.yagiDrvLength.value)/100,li=Number(els.yagiDirLength.value)/100;
    const g1=Number(els.yagiGap1.value)/100,g2=Number(els.yagiGap2.value)/100,diam=Number(els.yagiDiameter.value),segments=Math.round(Number(els.yagiSegments.value));
    if(![lr,ld,li,g1,g2,diam,segments].every(Number.isFinite)||Math.min(lr,ld,li,g1,g2,diam)<=0||segments<3)throw new Error('Проверьте длины, расстояния, диаметр и сегменты');
    setYagiWireLength(ref,lr);setYagiWireLength(drv,ld);setYagiWireLength(dir,li);
    const xr=yagiCenterX(ref);setYagiCenterX(drv,xr+g1);setYagiCenterX(dir,xr+g1+g2);
    for(const w of[ref,drv,dir]){w.radius_m=diam/2000;w.segments=segments}
    const feed=(p.feeds||[]).find(f=>f.wire_id==='DRV');if(feed)feed.segment=Math.floor((segments-1)/2);
    selectedWireId='DRV';geometryCommit(p,'параметры Яги изменены');syncYagiQuickPanel(p);return p
  }catch(e){status('ошибка параметров Яги','err');els.diag.textContent=String(e.message||e);return null}
}
async function recalcYagiQuick(){if(!applyYagiQuickPanel())return;await check();await run();if(lastResult)await runSweep()}
async function optimizeYagiQuick(){
  if(!applyYagiQuickPanel())return;
  els.optAlg.value='pso';els.optPop.value='6';els.optGen.value='2';els.optLocal.value='0';els.optRobustSamples.value='0';els.optMcSamples.value='0';els.optTolMm.value='0';els.optBandPoints.value='1';
  await runOptimize()
}
'''
js = replace_once(js, "let geometryTemplates=[];", yagi_js + "\nlet geometryTemplates=[];", "yagi helper insertion")

old_sync = "function syncGeometryFromProject(p){if(!els.geometryCanvas)return;ensureGeometrySelection(p);renderGeometry(p);if(els.geometryTemplateFrequency&&document.activeElement!==els.geometryTemplateFrequency&&p.frequency_hz)els.geometryTemplateFrequency.value=(Number(p.frequency_hz)/1e6).toFixed(3)}"
new_sync = "function syncGeometryFromProject(p){if(!els.geometryCanvas)return;ensureGeometrySelection(p);renderGeometry(p);syncYagiQuickPanel(p);if(els.geometryTemplateFrequency&&document.activeElement!==els.geometryTemplateFrequency&&p.frequency_hz)els.geometryTemplateFrequency.value=(Number(p.frequency_hz)/1e6).toFixed(3)}"
js = replace_once(js, old_sync, new_sync, "geometry sync")

start = js.find("async function createGeometryTemplate()")
end = js.find("function initGeometryEditor", start)
if start < 0 or end < 0:
    raise SystemExit("rev26 patch anchor missing: createGeometryTemplate")
template_fn = r'''async function createGeometryTemplate(){
  let templateLoaded=false,stage='создание шаблона';
  try{
    const id=els.geometryTemplate.value,fmhz=Number(els.geometryTemplateFrequency.value);
    if(!id)throw new Error('Выберите шаблон');if(!(fmhz>0))throw new Error('Частота должна быть > 0');
    if(!confirm('Заменить текущую модель шаблоном и выполнить расчёт?'))return;
    els.geometryTemplateCreate.disabled=true;status('создаю шаблон…');
    const r=await api('/api/template/'+encodeURIComponent(id)+'?frequency_hz='+encodeURIComponent(fmhz*1e6)),p=r.project;templateLoaded=true;
    els.editor.value=JSON.stringify(p,null,2);selectedWireId=p.wires?.[0]?.id||null;updateMeta(p);
    const mhz=Number(p.frequency_hz)/1e6;els.sweepStart.value=(mhz*.9).toFixed(3);els.sweepStop.value=(mhz*1.1).toFixed(3);els.optBandStart.value=(mhz*.99).toFixed(3);els.optBandStop.value=(mhz*1.01).toFixed(3);
    markResultsStale('шаблон создан · выполняю проверку');stage='проверка модели';
    const cj=await api('/api/model-check',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,kernel})});
    els.diag.textContent=cj.stdout+(cj.stderr?'\n'+cj.stderr:'');if(!cj.ok)throw new Error(cj.stderr||cj.stdout||'модель не прошла проверку');
    stage='расчёт';
    const sj=await api('/api/solve',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,kernel})});
    if(!sj.result)throw new Error('Расчёт не вернул результат');showResult(sj.result);els.run.textContent='Рассчитать';syncYagiQuickPanel(p);setWorkspaceView('geometry');status('шаблон создан и рассчитан','ok')
  }catch(e){
    if(templateLoaded)markResultsStale('шаблон создан, но '+stage+' не завершён');
    status('ошибка: '+stage,'err');els.diag.textContent=String(e.message||e)
  }finally{els.geometryTemplateCreate.disabled=false}
}
'''
js = js[:start] + template_fn + "\n" + js[end:]

old_init = "function initGeometryEditor(){if(!els.geometryCanvas)return;els.geometryTemplateCreate.onclick=createGeometryTemplate;"
new_init = "function initGeometryEditor(){if(!els.geometryCanvas)return;els.geometryTemplateCreate.onclick=createGeometryTemplate;if(els.yagiApply)els.yagiApply.onclick=applyYagiQuickPanel;if(els.yagiRecalc)els.yagiRecalc.onclick=recalcYagiQuick;if(els.yagiOptimize)els.yagiOptimize.onclick=optimizeYagiQuick;"
js = replace_once(js, old_init, new_init, "geometry bindings")

js = replace_once(js, "els.optVariables.textContent='В проекте нет переменных оптимизации.'", "els.optVariables.textContent='Для этой модели параметры оптимизации не заданы. Откройте «Геометрия» → «Яги, 3 элемента», чтобы проверить оптимизацию.'", "optimizer empty state")

demo_js = r'''
async function loadMeasurementDemo(){
  try{
    if(!lastSweep){status('для демо сначала выполняю частотный расчёт…');await runSweep()}
    if(!lastSweep||!(lastSweep.samples||[]).length)throw new Error('Сначала выполните частотный расчёт');
    setWorkspaceView('measurement');
    const samples=lastSweep.samples||[],mid=Math.floor(samples.length/2),pick=[samples[0],samples[mid],samples[samples.length-1]].filter((x,i,a)=>x&&a.indexOf(x)===i);
    const lines=['# Hz S RI R 50',...pick.map(s=>String(s.frequency_hz)+' '+String(s.s11?.re??0)+' '+String(s.s11?.im??0))];
    const text=lines.join('\n')+'\n',j=await api('/api/measurement/parse',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({format:'touchstone-s1p',source_name:'DEMO_FROM_CURRENT_SWEEP.s1p',text})});
    lastMeasurement=j.measurement;lastMeasurementRawText=text;lastComparison=null;lastMeasurementSet=null;lastReport=null;
    els.measurementReferencePlane.value='ДЕМО из текущего расчёта — не измерение VNA';setMeasurementKpis(null);renderMeasurementTable(null);renderMeasurementProvenance();els.measurementCompare.disabled=false;syncWorkflowButtons();
    await compareMeasurement();status('тестовые данные загружены и сравнены · это не реальное измерение','ok')
  }catch(e){status('ошибка тестовых измерений','err');els.diag.textContent=String(e.message||e)}
}
'''
js = replace_once(js, "function measurementFormat(file)", demo_js + "\nfunction measurementFormat(file)", "measurement demo helper")
js = replace_once(js, "els.measurementImport.onclick=importMeasurement;", "els.measurementImport.onclick=importMeasurement;if(els.measurementDemo)els.measurementDemo.onclick=loadMeasurementDemo;", "measurement demo binding")
js = replace_once(js, "let initialView='solve';", "let initialView='geometry';", "initial view")
js = replace_once(js, "await loadExample();await run();await runSweep()", "await loadExample();status('готово · выберите шаблон или измените геометрию','ok')", "startup autorun")
js_path.write_text(js, encoding="utf-8")

test = r'''#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,socket,subprocess,tempfile,time,urllib.request,urllib.error
from pathlib import Path

def free_port():
    s=socket.socket();s.bind(("127.0.0.1",0));p=s.getsockname()[1];s.close();return p
def get_json(url,timeout=5):
    with urllib.request.urlopen(url,timeout=timeout) as r:return json.load(r)
def post_json(url,obj,timeout=180):
    req=urllib.request.Request(url,data=json.dumps(obj).encode(),headers={"Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r:return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode("utf-8",errors="replace")) from e

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ap.add_argument("--emnext",required=True);ns=ap.parse_args()
    root=Path(ns.root);emnext=Path(ns.emnext).resolve()
    html=(root/"apps/linux_web/static/index.html").read_text(encoding="utf-8")
    js=(root/"apps/linux_web/static/app.js").read_text(encoding="utf-8")
    for marker in ("yagi-quick-panel","yagi-ref-length","yagi-gap-1","yagi-recalc","yagi-optimize","measurement-demo"):
        assert f'id="{marker}"' in html, marker
    for marker in ("syncYagiQuickPanel","applyYagiQuickPanel","recalcYagiQuick","optimizeYagiQuick","loadMeasurementDemo"):
        assert marker in js, marker
    assert "await loadExample();await run();await runSweep()" not in js

    with tempfile.TemporaryDirectory(prefix="emmana-rev26-") as td:
        port=free_port()
        proc=subprocess.Popen([str(Path(__import__("sys").executable)),str(root/"apps/linux_web/server.py"),"--host","127.0.0.1","--port",str(port),"--binary",str(emnext),"--cache-dir",td],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        base=f"http://127.0.0.1:{port}"
        try:
            for _ in range(80):
                try:
                    if get_json(base+"/api/health",1).get("ok"):break
                except Exception:time.sleep(.1)
            else: raise RuntimeError("server did not start")
            y=get_json(base+"/api/template/yagi-3el?frequency_hz=299792458")
            p=y["project"];assert len(p["wires"])==3 and len(p["design_variables"])>=5
            chk=post_json(base+"/api/model-check",{"project":p,"kernel":"reduced"},30);assert chk["ok"]
            sol=post_json(base+"/api/solve",{"project":p,"kernel":"reduced"},120);assert sol["ok"] and sol["result"]["feeds"]
            sw=post_json(base+"/api/sweep",{"project":p,"kernel":"reduced","start_hz":285e6,"stop_hz":315e6,"points":5,"parallel_workers":2},180);assert sw["ok"] and len(sw["sweep"]["samples"])==5
            opt=post_json(base+"/api/optimize",{"project":p,"kernel":"reduced","population":4,"generations":1,"local_iterations":0,"seed":42,"algorithm":"pso","weights":{"match":50,"gain":25,"front_to_back":15,"size":10},"gain_guardrail_db":0.5,"max_vswr":2.0,"band_start_hz":0,"band_stop_hz":0,"band_points":1,"quantization_step_m":0.001,"manufacturing_tolerance_m":0.0,"robust_objective_samples":0,"monte_carlo_samples":0,"parallel_workers":2},300)
            assert opt["ok"] and opt["optimizer"]["best"]["metrics"]["feasible"]
            print("REV26 YAGI WORKFLOW PASS")
        finally:
            proc.terminate()
            try:proc.wait(5)
            except subprocess.TimeoutExpired:proc.kill()
    return 0
if __name__=="__main__":raise SystemExit(main())
'''
(root / "tests/test_yagi_rev26.py").write_text(test, encoding="utf-8")

worklog = """# EMMana-Next rev26 — Yagi workflow UX

- Removed automatic solve/sweep on application startup; loaded model is now visibly stale until the user calculates it.
- Added a synchronized 3-element Yagi quick panel: reflector/driven/director lengths, two element gaps, diameter and segment count.
- Added one-click recalculate and quick PSO optimization for the Yagi panel.
- Mouse/coordinate geometry editing and quick-panel values share the same EMNX model; no parallel geometry model was introduced.
- Template creation now distinguishes synthesis/check/solve failures instead of reporting a generic template error.
- Optimization empty state now explains how to load a parametric Yagi model.
- Measurements now show a linear 1-2-3 guide and provide explicitly-labelled demo data generated from the current Sweep for UI testing only.
- Added end-to-end synthesized-Yagi gate: template -> model-check -> solve -> sweep -> optimize.

Solver physics and schemas are unchanged.
"""
(root / "docs/WORKLOG_2026-09-23_rev26.md").write_text(worklog, encoding="utf-8")
print("REV26_PATCH_PASS")
