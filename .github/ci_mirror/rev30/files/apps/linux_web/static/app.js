const $=s=>document.querySelector(s);let kernel='reduced',lastResult=null,lastOptimizer=null,lastSweep=null,lastMeasurement=null,lastComparison=null,lastMeasurementRawText='',lastVariant=null,lastMeasurementSet=null,lastReport=null;let variantHistory=[],variantSnapshots={},variantOverlayVisible={};let geometryUndoStack=[],geometryRedoStack=[];const GEOMETRY_HISTORY_LIMIT=30;
const els={status:$('#status'),run:$('#run'),runSweep:$('#run-sweep'),runOpt:$('#run-opt'),applyOpt:$('#apply-opt'),example:$('#example'),editor:$('#project-json'),name:$('#project-name'),meta:$('#project-meta'),zin:$('#zin'),vswr:$('#vswr'),dmax:$('#dmax'),eff:$('#eff'),accepted:$('#accepted'),radiated:$('#radiated'),dissipated:$('#dissipated'),balance:$('#balance'),diag:$('#diagnostics'),raw:$('#raw-result'),polar:$('#polar'),currents:$('#currents'),chip:$('#kernel-chip'),sweepChart:$('#sweep-chart'),sweepSummary:$('#sweep-summary'),sweepCursor:$('#sweep-cursor'),sweepOverlays:$('#sweep-overlays'),sweepStart:$('#sweep-start'),sweepStop:$('#sweep-stop'),sweepPoints:$('#sweep-points'),parallelWorkers:$('#parallel-workers'),optGoal:$('#opt-goal'),optGoalNote:$('#opt-goal-note'),optGoalTitle:$('#opt-goal-title'),optGoalDescription:$('#opt-goal-description'),optAlg:$('#opt-alg'),optPop:$('#opt-pop'),optGen:$('#opt-gen'),optLocal:$('#opt-local'),optSeed:$('#opt-seed'),optWMatch:$('#opt-w-match'),optWGain:$('#opt-w-gain'),optWFb:$('#opt-w-fb'),optWSize:$('#opt-w-size'),optGainGuard:$('#opt-gain-guard'),optMaxVswr:$('#opt-max-vswr'),optBandStart:$('#opt-band-start'),optBandStop:$('#opt-band-stop'),optBandPoints:$('#opt-band-points'),optQuantMm:$('#opt-quant-mm'),optTolMm:$('#opt-tol-mm'),optRobustSamples:$('#opt-robust-samples'),optMcSamples:$('#opt-mc-samples'),optSummary:$('#opt-summary'),optVariables:$('#opt-variables'),optConstraints:$('#opt-constraints'),optMetrics:$('#opt-metrics'),optPareto:$('#opt-pareto'),optChart:$('#opt-chart'),measurementFile:$('#measurement-file'),measurementCalibration:$('#measurement-calibration'),measurementReferencePlane:$('#measurement-reference-plane'),measurementImport:$('#measurement-import'),measurementCompare:$('#measurement-compare'),measurementSummary:$('#measurement-summary'),measurementDr:$('#measurement-dr'),measurementDx:$('#measurement-dx'),measurementDvswr:$('#measurement-dvswr'),measurementDs11:$('#measurement-ds11'),measurementChart:$('#measurement-chart'),measurementTableBody:$('#measurement-table-body'),measurementProvenance:$('#measurement-provenance'),variantName:$('#variant-name'),variantSave:$('#variant-save'),measurementBind:$('#measurement-bind'),reportGenerate:$('#report-generate'),reportDownload:$('#report-download'),workflowSummary:$('#workflow-summary'),variantHistory:$('#variant-history'),variantCompare:$('#variant-compare'),reportPreview:$('#report-preview'),geometryCanvas:$('#geometry-canvas'),geometrySummary:$('#geometry-summary'),geometryWireId:$('#geometry-wire-id'),geometrySx:$('#geometry-sx'),geometrySy:$('#geometry-sy'),geometrySz:$('#geometry-sz'),geometryEx:$('#geometry-ex'),geometryEy:$('#geometry-ey'),geometryEz:$('#geometry-ez'),geometryDiameter:$('#geometry-diameter'),geometrySegments:$('#geometry-segments'),geometryFeedStatus:$('#geometry-feed-status'),geometryAdd:$('#geometry-add'),geometryFeed:$('#geometry-feed'),geometryDelete:$('#geometry-delete'),geometryCheck:$('#geometry-check'),geometryTemplate:$('#geometry-template'),geometryTemplateFrequency:$('#geometry-template-frequency'),geometryTemplateCreate:$('#geometry-template-create'),geometryTemplateStatus:$('#geometry-template-status'),templateParamPanel:$('#template-parameter-panel'),templateParamTitle:$('#template-parameter-title'),templateParamTrust:$('#template-parameter-trust'),templateParamFields:$('#template-parameter-fields'),templateParamApply:$('#template-parameter-apply'),templateParamRecalc:$('#template-parameter-recalc'),templateParamOptimize:$('#template-parameter-optimize'),templateParamNote:$('#template-parameter-note'),geometryUndo:$('#geometry-undo'),geometryRedo:$('#geometry-redo'),geometryHistoryState:$('#geometry-history-state'),yagiQuickPanel:$('#yagi-quick-panel'),yagiQuickState:$('#yagi-quick-state'),yagiRefLength:$('#yagi-ref-length'),yagiDrvLength:$('#yagi-drv-length'),yagiDirLength:$('#yagi-dir-length'),yagiGap1:$('#yagi-gap-1'),yagiGap2:$('#yagi-gap-2'),yagiDiameter:$('#yagi-diameter'),yagiSegments:$('#yagi-segments'),yagiApply:$('#yagi-apply'),yagiRecalc:$('#yagi-recalc'),yagiOptimize:$('#yagi-optimize'),measurementDemo:$('#measurement-demo')};
function status(t,type=''){els.status.textContent=t;els.status.className='status '+type}
function fmt(x,n=3){return Number.isFinite(Number(x))?Number(x).toFixed(n):'—'}
const OPT_GOAL_PRESETS={
  balanced:{title:'Баланс',description:'Ищет компромисс между КСВ, усилением, отношением вперёд/назад и размером.',note:'Баланс согласования, усиления, F/B и размера.',weights:{match:40,gain:30,front_to_back:20,size:10},maxVswr:2.0,gainGuard:0.5,algorithm:'staged'},
  match:{title:'Лучшее согласование',description:'Сильнее снижает КСВ в выбранном диапазоне, сохраняя разумное усиление и направленность.',note:'Приоритет КСВ и согласования в выбранном диапазоне.',weights:{match:70,gain:12,front_to_back:13,size:5},maxVswr:1.5,gainGuard:1.0,algorithm:'staged'},
  gain:{title:'Максимум усиления',description:'Сильнее повышает усиление, но всё равно удерживает КСВ и F/B в допустимых пределах.',note:'Приоритет усиления; согласование остаётся ограничением.',weights:{match:18,gain:57,front_to_back:20,size:5},maxVswr:2.5,gainGuard:0.0,algorithm:'staged'}
};
function renderOptimizerGoal(custom=false){
  const g=OPT_GOAL_PRESETS[els.optGoal?.value]||OPT_GOAL_PRESETS.balanced;
  if(els.optGoalTitle)els.optGoalTitle.textContent=g.title;
  if(els.optGoalDescription)els.optGoalDescription.textContent=g.description;
  if(els.optGoalNote){els.optGoalNote.textContent=custom?'Технические параметры изменены вручную. Цель остаётся ориентиром, но используются ваши значения.':g.note;els.optGoalNote.classList.toggle('custom',!!custom)}
}
function applyOptimizerGoalPreset(){
  const g=OPT_GOAL_PRESETS[els.optGoal?.value]||OPT_GOAL_PRESETS.balanced;
  els.optWMatch.value=String(g.weights.match);els.optWGain.value=String(g.weights.gain);els.optWFb.value=String(g.weights.front_to_back);els.optWSize.value=String(g.weights.size);
  els.optMaxVswr.value=String(g.maxVswr);els.optGainGuard.value=String(g.gainGuard);els.optAlg.value=g.algorithm;
  renderOptimizerGoal(false)
}
function markOptimizerGoalCustom(){renderOptimizerGoal(true)}

function markResultsStale(message='модель изменена · нужно пересчитать'){
  lastResult=null;lastSweep=null;lastOptimizer=null;lastComparison=null;lastVariant=null;lastMeasurementSet=null;lastReport=null;
  [els.zin,els.vswr,els.dmax,els.eff,els.accepted,els.radiated,els.dissipated,els.balance].filter(Boolean).forEach(x=>x.textContent='—');
  if(els.sweepSummary)els.sweepSummary.textContent='нужно пересчитать';
  if(els.measurementCompare)els.measurementCompare.disabled=true;
  if(els.run)els.run.textContent='Пересчитать';
  syncWorkflowButtons();status(message,'warn');
}
async function api(url,opt){const r=await fetch(url,opt);let j={};try{j=await r.json()}catch{}if(!r.ok)throw new Error(j.error||j.stderr||`HTTP ${r.status}`);return j}
async function loadReferenceStatus(){try{const r=await api('/api/reference-status');const ref=r.independent_reference||{},internal=r.internal_numerical_gates||{};const internalOk=Object.values(internal).every(x=>String(x).toLowerCase()==='pass');const necPass=String(ref.ci_status||'').toLowerCase()==='pass'||String(ref.local_status||'').toLowerCase()==='pass';const el=$('#reference-status');el.textContent=necPass?'NEC2 ПРОЙДЕН':(internalOk?'ВНУТРЕННИЕ ТЕСТЫ ПРОЙДЕНЫ · NEC2 НЕ ЗАПУЩЕН':'ТРЕБУЕТ ПРОВЕРКИ');el.className='status '+(necPass?'ok':(internalOk?'':'err'));el.title=`NEC2 local: ${ref.local_status||'unknown'} · CI: ${ref.ci_status||'unknown'}${ref.local_reason?' · '+ref.local_reason:''}`}catch(e){const el=$('#reference-status');el.textContent='СТАТУС НЕИЗВЕСТЕН';el.className='status err'}}
function project(){return JSON.parse(els.editor.value)}
function updateMeta(p){els.name.textContent=p.name||'Без имени';const lossy=(p.wires||[]).filter(w=>Number(w.conductivity_s_per_m||0)>0).length;els.meta.textContent=`${fmt((p.frequency_hz||0)/1e6,3)} MHz · проводов ${p.wires?.length||0} · питание ${p.feeds?.length||0} · нагрузок ${p.loads?.length||0} · потерь в проводах ${lossy} · переменных ${p.design_variables?.length||0}`;renderVariables(p);}
async function loadExample(){const name=els.example.value;if(!name)return;const p=await api('/api/example/'+encodeURIComponent(name));els.editor.value=JSON.stringify(p,null,2);resetGeometryHistory();updateMeta(p);const mhz=(p.frequency_hz||0)/1e6;if(mhz>0){els.sweepStart.value=(mhz*.9).toFixed(3);els.sweepStop.value=(mhz*1.1).toFixed(3);els.optBandStart.value=(mhz*.99).toFixed(3);els.optBandStop.value=(mhz*1.01).toFixed(3)}markResultsStale('модель загружена · нажмите «Рассчитать»')}
function cpx(z){if(!z)return '—';return `${fmt(z.re,3)} ${Number(z.im)>=0?'+':'−'} j${fmt(Math.abs(z.im),3)}`}
function drawPolar(result){const c=els.polar,ctx=c.getContext('2d'),W=c.width,H=c.height;ctx.clearRect(0,0,W,H);ctx.fillStyle='#0b0d11';ctx.fillRect(0,0,W,H);const cx=W/2,cy=H/2,r=Math.min(W,H)*.41;ctx.strokeStyle='#202735';ctx.lineWidth=1;for(let k=1;k<=4;k++){ctx.beginPath();ctx.arc(cx,cy,r*k/4,0,Math.PI*2);ctx.stroke()}ctx.beginPath();ctx.moveTo(cx-r,cy);ctx.lineTo(cx+r,cy);ctx.moveTo(cx,cy-r);ctx.lineTo(cx,cy+r);ctx.stroke();const pts=(result.pattern||[]).filter(p=>Math.abs(p.phi_rad)<1e-8).sort((a,b)=>a.theta_rad-b.theta_rad);const max=Math.max(...pts.map(p=>p.directivity_linear),1e-12);if(!pts.length)return;ctx.strokeStyle='#5ba0ff';ctx.lineWidth=3;ctx.beginPath();pts.forEach((p,i)=>{const ang=p.theta_rad-Math.PI/2,rr=r*Math.sqrt(Math.max(0,p.directivity_linear/max)),x=cx+rr*Math.cos(ang),y=cy+rr*Math.sin(ang);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});for(let i=pts.length-1;i>=0;i--){const p=pts[i],ang=-(p.theta_rad-Math.PI/2)+Math.PI,rr=r*Math.sqrt(Math.max(0,p.directivity_linear/max)),x=cx+rr*Math.cos(ang),y=cy+rr*Math.sin(ang);ctx.lineTo(x,y)}ctx.closePath();ctx.globalAlpha=.18;ctx.fillStyle='#3b82f6';ctx.fill();ctx.globalAlpha=1;ctx.stroke();ctx.fillStyle='#798499';ctx.font='12px system-ui';ctx.fillText('0°',cx-8,cy-r-8);ctx.fillText('90°',cx+r+8,cy+4);ctx.fillText('180°',cx-14,cy+r+18)}
function drawCurrents(result){const c=els.currents,ctx=c.getContext('2d'),W=c.width,H=c.height;ctx.clearRect(0,0,W,H);ctx.fillStyle='#0b0d11';ctx.fillRect(0,0,W,H);const vals=(result.segment_currents_a||[]).map(z=>Math.hypot(z.re,z.im));if(!vals.length)return;const m=Math.max(...vals,1e-12),pad=35,bw=(W-2*pad)/vals.length;ctx.strokeStyle='#202735';for(let k=0;k<=4;k++){const y=pad+(H-2*pad)*k/4;ctx.beginPath();ctx.moveTo(pad,y);ctx.lineTo(W-pad,y);ctx.stroke()}ctx.fillStyle='#5ba0ff';vals.forEach((v,i)=>{const h=(H-2*pad)*v/m;ctx.fillRect(pad+i*bw,H-pad-h,Math.max(1,bw*.72),h)});ctx.fillStyle='#798499';ctx.font='12px system-ui';ctx.fillText(`max |I| = ${m.toExponential(3)} A`,pad,20);ctx.fillText(`${vals.length} сегм.`,W-130,H-12)}
function s11db(s){const m=Math.hypot(Number(s?.re||0),Number(s?.im||0));return m>0?20*Math.log10(m):-300}
function sweepPointText(p){
  if(!p)return 'Наведите на график: частота · S11 · КСВ · R/X';
  const z=p.impedance_ohm||{};
  return `${fmt(Number(p.frequency_hz)/1e6,3)} МГц · S11 ${fmt(s11db(p.s11),2)} dB · КСВ ${fmt(p.vswr,3)} · R ${fmt(z.re,2)} Ω · X ${fmt(z.im,2)} Ω · D ${fmt(p.dmax_dbi,2)} dBi`;
}
function comparisonVariantRows(){
  const recent=variantHistory.slice(0,3).map((v,index)=>({v,index})).reverse();
  return recent.map((row,i)=>({...row,label:String.fromCharCode(65+i),snapshot:variantSnapshots[row.v.immutability?.fingerprint]||null}));
}
function sweepOverlayRows(){
  return comparisonVariantRows().filter(r=>r.snapshot?.sweep?.samples?.length).map(r=>{const fp=r.v.immutability?.fingerprint;if(!(fp in variantOverlayVisible))variantOverlayVisible[fp]=true;return {...r,visible:variantOverlayVisible[fp]!==false}})
}
function renderSweepOverlayControls(){
  if(!els.sweepOverlays)return;const rows=sweepOverlayRows();
  if(!rows.length){els.sweepOverlays.innerHTML='<span>Наложение A/B/C появится после сохранения рассчитанных вариантов.</span>';return}
  const colors=['#ffbd59','#d68cff','#ff7d7d'];
  els.sweepOverlays.innerHTML='<span>Наложение S11:</span>'+rows.map((r,i)=>`<button type="button" class="sweep-overlay-chip${r.visible?' active':''}" data-sweep-overlay="${escapeHtml(r.v.immutability.fingerprint)}" style="--overlay-color:${colors[i%colors.length]}"><span class="sweep-overlay-dot"></span>${r.label} · ${escapeHtml(r.v.name||r.v.variant_id)}</button>`).join('');
  els.sweepOverlays.querySelectorAll('[data-sweep-overlay]').forEach(b=>b.onclick=()=>{const fp=b.dataset.sweepOverlay;variantOverlayVisible[fp]=variantOverlayVisible[fp]===false;renderSweepOverlayControls();if(lastSweep)drawSweep(lastSweep)});
}
function drawSweep(sw,hoverIndex=null){
  const c=els.sweepChart,ctx=c.getContext('2d'),W=c.width,H=c.height;ctx.clearRect(0,0,W,H);ctx.fillStyle='#0b0d11';ctx.fillRect(0,0,W,H);
  const pts=sw?.samples||[];if(pts.length<2)return;
  const overlays=sweepOverlayRows().filter(r=>r.visible),overlayColors=['#ffbd59','#d68cff','#ff7d7d'];
  const padL=64,padR=64,padT=34,padB=42,x0=pts[0].frequency_hz,x1=pts[pts.length-1].frequency_hz;
  const dbs=pts.map(p=>s11db(p.s11)),vs=pts.map(p=>Math.min(Number(p.vswr||1),10)),overlayDbs=overlays.flatMap(r=>(r.snapshot.sweep.samples||[]).map(p=>s11db(p.s11)).filter(Number.isFinite));let yDbMin=Math.min(-10,...dbs,...overlayDbs),yDbMax=0;if(yDbMin<-60)yDbMin=-60;
  const X=f=>padL+(W-padL-padR)*(f-x0)/(x1-x0||1),Ydb=d=>padT+(H-padT-padB)*(yDbMax-d)/(yDbMax-yDbMin||1),Yv=v=>padT+(H-padT-padB)*(v-1)/9;
  ctx.strokeStyle='#202735';ctx.lineWidth=1;for(let k=0;k<=5;k++){const y=padT+(H-padT-padB)*k/5;ctx.beginPath();ctx.moveTo(padL,y);ctx.lineTo(W-padR,y);ctx.stroke()}for(let k=0;k<=6;k++){const x=padL+(W-padL-padR)*k/6;ctx.beginPath();ctx.moveTo(x,padT);ctx.lineTo(x,H-padB);ctx.stroke()}
  if(yDbMin<=-10){ctx.strokeStyle='#344154';ctx.setLineDash([3,4]);ctx.beginPath();ctx.moveTo(padL,Ydb(-10));ctx.lineTo(W-padR,Ydb(-10));ctx.stroke();ctx.setLineDash([]);ctx.fillStyle='#6f7b8d';ctx.font='10px system-ui';ctx.fillText('−10 dB',8,Ydb(-10)+3)}
  overlays.forEach((r,i)=>{const samples=(r.snapshot.sweep.samples||[]).filter(p=>Number(p.frequency_hz)>=x0&&Number(p.frequency_hz)<=x1);if(samples.length<2)return;ctx.strokeStyle=overlayColors[i%overlayColors.length];ctx.lineWidth=1.8;ctx.setLineDash([7,5]);ctx.beginPath();samples.forEach((p,k)=>{const x=X(Number(p.frequency_hz)),y=Ydb(s11db(p.s11));k?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.stroke();ctx.setLineDash([]);ctx.fillStyle=overlayColors[i%overlayColors.length];ctx.font='10px system-ui';ctx.fillText(r.label,padL+250+i*32,padT-14)});
  ctx.strokeStyle='#5ba0ff';ctx.lineWidth=3;ctx.beginPath();pts.forEach((p,i)=>{const x=X(p.frequency_hz),y=Ydb(dbs[i]);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.stroke();
  ctx.strokeStyle='#43d17c';ctx.lineWidth=2;ctx.beginPath();pts.forEach((p,i)=>{const x=X(p.frequency_hz),y=Yv(vs[i]);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.stroke();
  const marker=(f,color,dash,label,slot)=>{if(!(Number(f)>=x0&&Number(f)<=x1))return;const x=X(Number(f));ctx.strokeStyle=color;ctx.lineWidth=1.5;ctx.setLineDash(dash);ctx.beginPath();ctx.moveTo(x,padT);ctx.lineTo(x,H-padB);ctx.stroke();ctx.setLineDash([]);ctx.fillStyle=color;ctx.font='10px system-ui';ctx.fillText(label,padL+slot,padT-14)};
  let workingHz=NaN;try{workingHz=Number(project().frequency_hz)}catch{}
  marker(workingHz,'#d6deea',[2,3],'рабочая',0);marker(sw.resonance_frequency_hz,'#ffbd59',[6,5],'резонанс',78);marker(sw.min_s11_frequency_hz,'#d68cff',[3,3],'мин. S11',162);
  ctx.fillStyle='#798499';ctx.font='12px system-ui';ctx.fillText(`${(x0/1e6).toFixed(1)} МГц`,padL,H-15);ctx.fillText(`${(x1/1e6).toFixed(1)} МГц`,W-padR-70,H-15);ctx.fillStyle='#5ba0ff';ctx.fillText('S11 текущий',padL,H-2);ctx.fillStyle='#43d17c';ctx.fillText('КСВ 1…10',padL+105,H-2);
  if(Number.isInteger(hoverIndex)&&hoverIndex>=0&&hoverIndex<pts.length){const p=pts[hoverIndex],x=X(p.frequency_hz),yd=Ydb(dbs[hoverIndex]),yv=Yv(vs[hoverIndex]);ctx.strokeStyle='#e6edf7';ctx.lineWidth=1;ctx.setLineDash([2,3]);ctx.beginPath();ctx.moveTo(x,padT);ctx.lineTo(x,H-padB);ctx.stroke();ctx.setLineDash([]);ctx.fillStyle='#5ba0ff';ctx.beginPath();ctx.arc(x,yd,4,0,Math.PI*2);ctx.fill();ctx.fillStyle='#43d17c';ctx.beginPath();ctx.arc(x,yv,3.5,0,Math.PI*2);ctx.fill()}
}
function initSweepInteractions(){
  const c=els.sweepChart;if(!c)return;
  c.addEventListener('pointermove',e=>{if(!lastSweep?.samples?.length)return;const rect=c.getBoundingClientRect(),W=c.width,padL=64,padR=64,x=(e.clientX-rect.left)*W/(rect.width||1),ratio=Math.max(0,Math.min(1,(x-padL)/(W-padL-padR))),idx=Math.round(ratio*(lastSweep.samples.length-1));drawSweep(lastSweep,idx);if(els.sweepCursor)els.sweepCursor.textContent=sweepPointText(lastSweep.samples[idx])});
  c.addEventListener('pointerleave',()=>{if(lastSweep)drawSweep(lastSweep);if(els.sweepCursor)els.sweepCursor.textContent='Наведите на график: частота · S11 · КСВ · R/X'});
}
function renderVariables(p){const vars=p.design_variables||[],cons=p.design_constraints||[];if(!vars.length){els.optVariables.classList.add('muted');els.optVariables.textContent='Для этой модели параметры оптимизации не заданы. Откройте «Геометрия» → «Яги, 3 элемента», чтобы проверить оптимизацию.'}else{els.optVariables.classList.remove('muted');const valueOf=v=>{const w=(p.wires||[]).find(x=>x.id===v.wire_id);if(!w)return NaN;const a=w.start_m,b=w.end_m;if(v.kind==='wire_center_x_m')return(a[0]+b[0])/2;if(v.kind==='wire_length_m')return Math.hypot(b[0]-a[0],b[1]-a[1],b[2]-a[2]);return NaN};els.optVariables.innerHTML=vars.map(v=>`<div class="opt-row"><span>${v.id}<small> ${v.kind}</small></span><b>${fmt(valueOf(v),4)} · ${fmt(v.min,4)}…${fmt(v.max,4)}</b></div>`).join('')}if(cons.length){els.optConstraints.classList.remove('muted');els.optConstraints.innerHTML='<div class="constraint-head">Ограничения</div>'+cons.map(c=>`<div class="opt-row"><span>${c.id}<small> ${c.kind}</small></span><b>${fmt(c.value,4)}</b></div>`).join('')}else{els.optConstraints.classList.add('muted');els.optConstraints.textContent='Ограничения не заданы.'}}
function drawOpt(opt){const c=els.optChart,ctx=c.getContext('2d'),W=c.width,H=c.height;ctx.clearRect(0,0,W,H);ctx.fillStyle='#0b0d11';ctx.fillRect(0,0,W,H);const global=opt.generation_best||[],local=opt.local_refinement_best||[],pts=[opt.initial,...global,...local].map((x,i)=>({i,score:Number(x.metrics?.score),local:i>global.length})).filter(x=>Number.isFinite(x.score));if(pts.length<2)return;const pad=28,min=Math.min(...pts.map(x=>x.score)),max=Math.max(...pts.map(x=>x.score));const span=Math.max(max-min,1e-9),X=i=>pad+(W-2*pad)*i/(pts.length-1),Y=v=>pad+(H-2*pad)*(max-v)/span;ctx.strokeStyle='#202735';for(let k=0;k<=4;k++){const y=pad+(H-2*pad)*k/4;ctx.beginPath();ctx.moveTo(pad,y);ctx.lineTo(W-pad,y);ctx.stroke()}ctx.strokeStyle='#43d17c';ctx.lineWidth=3;ctx.beginPath();pts.forEach((p,i)=>{const x=X(i),y=Y(p.score);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.stroke();if(local.length){const split=X(global.length);ctx.strokeStyle='#ffbd59';ctx.setLineDash([5,4]);ctx.beginPath();ctx.moveTo(split,pad);ctx.lineTo(split,H-pad);ctx.stroke();ctx.setLineDash([])}ctx.fillStyle='#8992a3';ctx.font='12px system-ui';ctx.fillText(`score ${min.toFixed(4)} … ${max.toFixed(4)}`,pad,18);ctx.fillText(`${global.length} global + ${local.length} local`,W-175,H-8)}
function candidateRows(c){const m=c.metrics||{};return `КСВ ${fmt(m.vswr,3)} · усиление ${fmt(m.forward_gain_dbi,2)} dBi · F/B ${fmt(m.front_to_back_db,2)} dB · траверса ${fmt(m.boom_length_m,3)} м`}
function renderPareto(opt){const featured=opt.featured_candidates||[];els.optPareto.classList.toggle('muted',!featured.length);if(!featured.length){els.optPareto.textContent='Pareto-кандидатов нет.';return}els.optPareto.innerHTML=featured.map((x,i)=>`<button class="pareto-card" data-pareto="${i}"><b>${x.label}</b><small>${candidateRows(x.candidate)}</small></button>`).join('')+`<div class="objective-note">Pareto front: ${(opt.pareto_front||[]).length} вариантов</div>`;els.optPareto.querySelectorAll('[data-pareto]').forEach(b=>b.onclick=()=>{const x=featured[Number(b.dataset.pareto)];if(x)applyCandidate(x.candidate,x.label)})}
function showOptimizer(opt,cacheHit=false){lastOptimizer=opt;const a=opt.initial.metrics,b=opt.best.metrics,w=opt.weights||{};const band=Number(opt.band_points)>1?`${fmt(opt.band_start_hz/1e6,2)}…${fmt(opt.band_stop_hz/1e6,2)} MHz / ${opt.band_points}`:`single ${fmt(opt.band_start_hz/1e6,3)} MHz`;els.optSummary.textContent=`${opt.algorithm} · score ${fmt(a.score,4)} → ${fmt(b.score,4)} · ${band} · Pareto ${(opt.pareto_front||[]).length} · eval ${opt.evaluations}${cacheHit?' · cache':''}`;const feasibility=b.feasible?'OK':`VIOLATIONS ${b.violated_constraints}`;const violations=(opt.best.constraint_violations||[]).map(v=>[`⚠ ${v.id}`,fmt(v.amount,5)]);const audit=opt.tolerance_audit,ra=opt.robust_tolerance_audit,rb=opt.robust_best,mc=opt.monte_carlo_audit,bn=opt.best_nominal?.metrics;const auditRows=[...(audit?[['Axis tolerance',`${audit.passes_guardrails?'PASS':'FAIL'} · ±${fmt(1000*audit.tolerance_m,2)} mm · ${audit.stress_cases} cases`],['Tol worst VSWR',`${fmt(audit.worst_case.vswr,3)} @ ${fmt(audit.worst_case.worst_vswr_frequency_hz/1e6,2)} MHz`],['Tol min Gain',`${fmt(audit.worst_case.forward_gain_dbi,2)} dBi @ ${fmt(audit.worst_case.min_gain_frequency_hz/1e6,2)} MHz`]]:[]),...(mc?[['Monte Carlo',`${fmt(100*mc.pass_fraction,1)}% PASS · ${mc.passing_samples}/${mc.samples}`],['MC p95 VSWR',fmt(mc.p95_vswr,3)],['MC p05 Gain',`${fmt(mc.p05_gain_dbi,2)} dBi`],['MC p05 F/B',`${fmt(mc.p05_front_to_back_db,2)} dB`]]:[]),...(bn?[['Nominal best',`VSWR ${fmt(bn.vswr,3)} · Gain ${fmt(bn.forward_gain_dbi,2)} dBi · F/B ${fmt(bn.front_to_back_db,2)} dB`]]:[]),...(rb&&ra?[['Robust balanced',`score ${fmt(rb.metrics.score,4)} · ${ra.passes_guardrails?'PASS':'FAIL'}`],['Robust values',rb.values.map(v=>`${v.id}=${fmt(v.value,3)}`).join(' · ')]]:[])];els.optMetrics.classList.remove('muted');els.optMetrics.innerHTML=[['Feasible',feasibility],['Band',band],['Manufacturing',`grid ${fmt(1000*opt.quantization_step_m,2)} mm · tol ±${fmt(1000*opt.manufacturing_tolerance_m,2)} mm · robust ${opt.robust_objective_samples||0} · MC ${opt.monte_carlo_samples||0}`],['Weights',`${fmt(100*w.match,0)}/${fmt(100*w.gain,0)}/${fmt(100*w.front_to_back,0)}/${fmt(100*w.size,0)}`],['Guardrail',`gain −${fmt(opt.gain_guardrail_db,2)} dB · VSWR ≤ ${fmt(opt.max_vswr,2)}`],['Worst VSWR',`${fmt(a.vswr,3)} → ${fmt(b.vswr,3)} @ ${fmt(b.worst_vswr_frequency_hz/1e6,2)} MHz`],['Min Gain +X',`${fmt(a.forward_gain_dbi,2)} → ${fmt(b.forward_gain_dbi,2)} dBi @ ${fmt(b.min_gain_frequency_hz/1e6,2)} MHz`],['Min F/B',`${fmt(a.front_to_back_db,2)} → ${fmt(b.front_to_back_db,2)} dB @ ${fmt(b.min_front_to_back_frequency_hz/1e6,2)} MHz`],['Boom',`${fmt(a.boom_length_m,3)} → ${fmt(b.boom_length_m,3)} m`],...auditRows,...violations,...opt.best.values.map(v=>[v.id,fmt(v.value,6)])].map(([k,v])=>`<div class="opt-row"><span>${k}</span><b>${v}</b></div>`).join('');els.applyOpt.hidden=!(rb?.metrics?.feasible||b.feasible);els.applyOpt.textContent=rb?'Применить robust-balanced':'Применить balanced';renderPareto(opt);drawOpt(opt)}
async function runOptimize(){setWorkspaceView('optimize');try{const p=project();updateMeta(p);if(!(p.design_variables||[]).length)throw new Error('У этой модели нет параметров для оптимизации. Откройте параметрический шаблон, например «Яги, 3 элемента».');const parallel_workers=Number(els.parallelWorkers.value);if(!(parallel_workers>=1&&parallel_workers<=16))throw new Error('Потоки: 1…16');const population=Number(els.optPop.value),generations=Number(els.optGen.value),local_iterations=Number(els.optLocal.value),seed=Number(els.optSeed.value),algorithm=els.optAlg.value;const weights={match:Number(els.optWMatch.value),gain:Number(els.optWGain.value),front_to_back:Number(els.optWFb.value),size:Number(els.optWSize.value)};const gain_guardrail_db=Number(els.optGainGuard.value),max_vswr=Number(els.optMaxVswr.value),band_points=Number(els.optBandPoints.value),band_start_hz=Number(els.optBandStart.value)*1e6,band_stop_hz=Number(els.optBandStop.value)*1e6,quantization_step_m=Number(els.optQuantMm.value)/1000,manufacturing_tolerance_m=Number(els.optTolMm.value)/1000,robust_objective_samples=Number(els.optRobustSamples.value),monte_carlo_samples=Number(els.optMcSamples.value);if(Object.values(weights).some(x=>x<0)||Object.values(weights).reduce((a,b)=>a+b,0)<=0)throw new Error('Вес хотя бы одной цели должен быть > 0');if(!(band_points>=1&&band_points<=11))throw new Error('Band points: 1…11');if(band_points>1&&!(band_start_hz>0&&band_stop_hz>band_start_hz))throw new Error('Проверь диапазон optimizer band');if(!(robust_objective_samples>=0&&robust_objective_samples<=16))throw new Error('Robust samples: 0…16');if(!(monte_carlo_samples>=0&&monte_carlo_samples<=128))throw new Error('Monte Carlo: 0…128');if((robust_objective_samples>0||monte_carlo_samples>0)&&!(manufacturing_tolerance_m>0))throw new Error('Для robust/Monte Carlo нужен допуск > 0');els.runOpt.disabled=true;status('оптимизация…');const j=await api('/api/optimize',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,kernel,population,generations,local_iterations,seed,algorithm,weights,gain_guardrail_db,max_vswr,band_start_hz,band_stop_hz,band_points,quantization_step_m,manufacturing_tolerance_m,robust_objective_samples,monte_carlo_samples,parallel_workers})});showOptimizer(j.optimizer,j.cache_hit);status(j.cache_hit?'оптимизация из кэша':'оптимизация завершена','ok')}catch(e){status('ошибка оптимизации','err');els.diag.textContent=String(e.message||e)}finally{els.runOpt.disabled=false}}
async function applyCandidate(candidate,label='вариант'){if(!candidate)return;try{els.applyOpt.disabled=true;const beforeText=els.editor.value,p=project(),map=new Map((candidate.values||[]).map(v=>[v.id,Number(v.value)]));for(const dv of p.design_variables||[]){if(!map.has(dv.id))continue;const w=(p.wires||[]).find(x=>x.id===dv.wire_id);if(!w)continue;const value=map.get(dv.id),a=w.start_m,b=w.end_m;if(dv.kind==='wire_center_x_m'){const mid=(a[0]+b[0])/2,dx=value-mid;a[0]+=dx;b[0]+=dx}else if(dv.kind==='wire_length_m'){const dx=b[0]-a[0],dy=b[1]-a[1],dz=b[2]-a[2],old=Math.hypot(dx,dy,dz),ux=dx/old,uy=dy/old,uz=dz/old,mx=(a[0]+b[0])/2,my=(a[1]+b[1])/2,mz=(a[2]+b[2])/2,h=value/2;w.start_m=[mx-ux*h,my-uy*h,mz-uz*h];w.end_m=[mx+ux*h,my+uy*h,mz+uz*h]}}geometryCommit(p,`${label} применён`,beforeText);status(`${label} применён · контрольный solve…`);await run();status('контрольный sweep…');await runSweep();status(`${label} применён и перепроверен`,'ok')}catch(e){status('ошибка применения','err');els.diag.textContent=String(e.message||e)}finally{els.applyOpt.disabled=false}}
async function applyBest(){if(lastOptimizer){const c=lastOptimizer.robust_best||lastOptimizer.best;await applyCandidate(c,lastOptimizer.robust_best?'robust-balanced':'balanced')}}
async function runSweep(){setWorkspaceView('solve');try{const p=project();updateMeta(p);const startHz=Number(els.sweepStart.value)*1e6,stopHz=Number(els.sweepStop.value)*1e6,points=Number(els.sweepPoints.value),parallel_workers=Number(els.parallelWorkers.value);if(!(parallel_workers>=1&&parallel_workers<=16))throw new Error('Потоки: 1…16');if(!(startHz>0&&stopHz>=startHz&&points>=2))throw new Error('Проверь диапазон частотного расчёта');els.runSweep.disabled=true;status('частотный расчёт…');const j=await api('/api/sweep',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,kernel,start_hz:startHz,stop_hz:stopHz,points,parallel_workers})});const sw=j.sweep;lastSweep=sw;drawSweep(sw);if(els.sweepCursor)els.sweepCursor.textContent='Наведите на график: частота · S11 · КСВ · R/X';if(lastMeasurement)els.measurementCompare.disabled=false;els.sweepSummary.textContent=`резонанс ${fmt(sw.resonance_frequency_hz/1e6,3)} MHz · мин. S11 ${fmt(sw.min_s11_db,2)} dB @ ${fmt(sw.min_s11_frequency_hz/1e6,3)} MHz · полоса −10 dB ${fmt(sw.bandwidth_10db_hz/1e6,3)} MHz · потоков ${sw.execution_workers}${j.cache_hit?' · кэш':''}`;status(j.cache_hit?'частотный расчёт из кэша':'частотный расчёт завершён','ok')}catch(e){status('ошибка частотного расчёта','err');els.diag.textContent=String(e.message||e)}finally{els.runSweep.disabled=false}}


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

function measurementFormat(file){const n=String(file?.name||'').toLowerCase();if(n.endsWith('.csv'))return 'vna-csv';if(n.endsWith('.s1p'))return 'touchstone-s1p';throw new Error('Поддерживаются только .s1p и .csv')}
function measurementValue(v,n=3){return Number.isFinite(Number(v))?Number(v).toFixed(n):'—'}
function escapeHtml(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function setMeasurementKpis(summary){els.measurementDr.textContent=measurementValue(summary?.delta_r_ohm?.max_abs);els.measurementDx.textContent=measurementValue(summary?.delta_x_ohm?.max_abs);els.measurementDvswr.textContent=measurementValue(summary?.delta_vswr?.max_abs);els.measurementDs11.textContent=measurementValue(summary?.delta_s11_db?.max_abs)}
function renderMeasurementProvenance(){
  if(!lastMeasurement){els.measurementProvenance.textContent='Загрузите измерение. Raw asset останется отдельным от simulation.';return}
  const m=lastMeasurement,cal=els.measurementCalibration.value||'unknown',plane=els.measurementReferencePlane.value.trim()||'не указан';
  els.measurementProvenance.innerHTML=[['Source',m.source?.name||'—'],['Format',m.source?.format||'—'],['Reference',measurementValue(m.reference_impedance_ohm,1)+' Ω'],['Calibration',cal],['Reference plane',plane],['Points',String(m.samples?.length||0)]].map(([k,v])=>`<div class="measurement-prov-row"><span>${escapeHtml(k)}</span><b>${escapeHtml(v)}</b></div>`).join('');
}
function drawMeasurementComparison(cmp){
  const c=els.measurementChart,ctx=c.getContext('2d'),W=c.width,H=c.height;ctx.clearRect(0,0,W,H);ctx.fillStyle='#0b0d11';ctx.fillRect(0,0,W,H);
  const pts=cmp?.samples||[];if(pts.length<2){ctx.fillStyle='#8992a3';ctx.font='12px system-ui';ctx.fillText('Недостаточно общих точек для графика.',24,30);return}
  const padL=58,padR=28,padT=32,padB=38,x0=pts[0].frequency_hz,x1=pts[pts.length-1].frequency_hz;
  const values=pts.flatMap(p=>[Number(p.simulation.s11_db),Number(p.measurement.s11_db)]).filter(Number.isFinite);let ymin=Math.min(-10,...values),ymax=Math.max(0,...values);if(ymin<-80)ymin=-80;if(ymax>5)ymax=5;
  const X=f=>padL+(W-padL-padR)*(f-x0)/(x1-x0||1),Y=v=>padT+(H-padT-padB)*(ymax-v)/(ymax-ymin||1);
  ctx.strokeStyle='#202735';ctx.lineWidth=1;for(let k=0;k<=5;k++){const y=padT+(H-padT-padB)*k/5;ctx.beginPath();ctx.moveTo(padL,y);ctx.lineTo(W-padR,y);ctx.stroke()}
  const trace=(key,color,dash=[])=>{ctx.strokeStyle=color;ctx.lineWidth=2.5;ctx.setLineDash(dash);ctx.beginPath();pts.forEach((p,i)=>{const x=X(p.frequency_hz),y=Y(p[key].s11_db);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.stroke();ctx.setLineDash([])};
  trace('simulation','#5ba0ff');trace('measurement','#43d17c',[7,5]);
  ctx.fillStyle='#798499';ctx.font='12px system-ui';ctx.fillText(`${(x0/1e6).toFixed(2)} MHz`,padL,H-14);ctx.fillText(`${(x1/1e6).toFixed(2)} MHz`,W-padR-82,H-14);
  ctx.fillStyle='#5ba0ff';ctx.fillText('Simulation S11',padL,18);ctx.fillStyle='#43d17c';ctx.fillText('Measurement S11',padL+118,18);
}
function renderMeasurementTable(cmp){
  const pts=cmp?.samples||[];if(!pts.length){els.measurementTableBody.innerHTML='<tr><td colspan="7" class="muted">Нет сравнения.</td></tr>';return}
  const maxRows=8,step=Math.max(1,Math.floor(pts.length/maxRows)),rows=[];for(let i=0;i<pts.length&&rows.length<maxRows;i+=step)rows.push(pts[i]);if(rows[rows.length-1]!==pts[pts.length-1]&&rows.length<maxRows)rows.push(pts[pts.length-1]);
  els.measurementTableBody.innerHTML=rows.map(p=>`<tr><td>${measurementValue(p.frequency_hz/1e6,3)}</td><td>${measurementValue(p.simulation.r_ohm)}</td><td>${measurementValue(p.measurement.r_ohm)}</td><td>${measurementValue(p.delta.r_ohm)}</td><td>${measurementValue(p.simulation.x_ohm)}</td><td>${measurementValue(p.measurement.x_ohm)}</td><td>${measurementValue(p.delta.x_ohm)}</td></tr>`).join('');
}
async function importMeasurement(){setWorkspaceView('measurement');
  try{
    const file=els.measurementFile.files?.[0];if(!file)throw new Error('Выберите файл .s1p или .csv');
    const format=measurementFormat(file),text=await file.text();lastMeasurementRawText=text;els.measurementImport.disabled=true;status('импорт измерения…');
    const j=await api('/api/measurement/parse',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({format,source_name:file.name,text})});
    lastMeasurement=j.measurement;lastComparison=null;lastMeasurementSet=null;lastReport=null;setMeasurementKpis(null);renderMeasurementTable(null);drawMeasurementComparison(null);renderMeasurementProvenance();syncWorkflowButtons();
    els.measurementSummary.textContent=`${file.name} · ${lastMeasurement.samples?.length||0} points · ${measurementValue(lastMeasurement.reference_impedance_ohm,1)} Ω`;
    els.measurementCompare.disabled=!lastSweep;status(lastSweep?'измерение загружено · можно сравнить':'измерение загружено · сначала выполните частотный расчёт','ok');
  }catch(e){status('ошибка измерения','err');els.diag.textContent=String(e.message||e)}finally{els.measurementImport.disabled=false}
}
async function compareMeasurement(){
  try{
    if(!lastMeasurement)throw new Error('Сначала импортируйте измерение');if(!lastSweep)throw new Error('Сначала выполните Sweep');
    els.measurementCompare.disabled=true;status('сравнение измерения…');
    const j=await api('/api/measurement/compare',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({measurement:lastMeasurement,sweep:lastSweep})});
    lastComparison=j.comparison;lastReport=null;setMeasurementKpis(lastComparison.summary);drawMeasurementComparison(lastComparison);renderMeasurementTable(lastComparison);renderMeasurementProvenance();syncWorkflowButtons();
    els.measurementSummary.textContent=`${lastComparison.overlap.points} совмещённых точек · ${lastMeasurement.source?.name||'измерение'}`;status('сравнение готово','ok');
  }catch(e){const msg=String(e.message||e);if(msg.includes('frequency ranges do not overlap')){const mf=(lastMeasurement?.samples||[]).map(x=>Number(x.frequency_hz)).filter(Number.isFinite),sf=(lastSweep?.samples||[]).map(x=>Number(x.frequency_hz)).filter(Number.isFinite),mr=mf.length?[Math.min(...mf),Math.max(...mf)]:null,sr=sf.length?[Math.min(...sf),Math.max(...sf)]:null,fr=r=>r?`${(r[0]/1e6).toFixed(3)}…${(r[1]/1e6).toFixed(3)} МГц`:'неизвестно';status('диапазоны частот не совпадают','err');els.measurementSummary.textContent='нужно пересчитать диапазон';els.diag.textContent=`Диапазоны не пересекаются. Измерение: ${fr(mr)}. Расчёт: ${fr(sr)}. Выполните частотный расчёт в диапазоне измерения и повторите сравнение.`}else{status('ошибка сравнения','err');els.diag.textContent=msg}}finally{els.measurementCompare.disabled=!lastMeasurement||!lastSweep}
}
const VARIANT_STORAGE_KEY='emnext.variantHistory.v1';
const VARIANT_SNAPSHOT_STORAGE_KEY='emnext.variantSnapshots.v1';
function workflowShort(v,n=10){const s=String(v||'');return s.length>n?s.slice(0,n)+'…':s}
function loadVariantHistory(){
  try{const rows=JSON.parse(localStorage.getItem(VARIANT_STORAGE_KEY)||'[]');variantHistory=Array.isArray(rows)?rows.filter(x=>x&&x.variant_id&&x.immutability?.fingerprint).slice(0,8):[]}catch{variantHistory=[]}
  try{const rows=JSON.parse(localStorage.getItem(VARIANT_SNAPSHOT_STORAGE_KEY)||'{}');variantSnapshots=rows&&typeof rows==='object'&&!Array.isArray(rows)?rows:{}}catch{variantSnapshots={}}
  renderVariantHistory();renderVariantComparison();renderSweepOverlayControls()
}
function persistVariantHistory(){try{localStorage.setItem(VARIANT_STORAGE_KEY,JSON.stringify(variantHistory.slice(0,8)));localStorage.setItem(VARIANT_SNAPSHOT_STORAGE_KEY,JSON.stringify(variantSnapshots))}catch{}}
function compactSweep(sw){return sw?{resonance_frequency_hz:Number(sw.resonance_frequency_hz),min_s11_frequency_hz:Number(sw.min_s11_frequency_hz),min_s11_db:Number(sw.min_s11_db),bandwidth_10db_hz:Number(sw.bandwidth_10db_hz),samples:(sw.samples||[]).map(p=>({frequency_hz:Number(p.frequency_hz),s11:{re:Number(p.s11?.re||0),im:Number(p.s11?.im||0)},vswr:Number(p.vswr),dmax_dbi:Number(p.dmax_dbi)}))}:null}
function captureVariantSnapshot(p,v){
  const hash=v?.model_ref?.model_hash||'',resultOk=!!(lastResult&&lastResult.model_hash===hash),sweepOk=!!(lastSweep&&lastSweep.source_model_hash===hash),f=resultOk?lastResult.feeds?.[0]:null;
  const ref=yagiWire(p,'REF'),drv=yagiWire(p,'DRV'),dir=yagiWire(p,'DIR1'),yagi=ref&&drv&&dir?{ref_cm:100*yagiWireLength(ref),drv_cm:100*yagiWireLength(drv),dir_cm:100*yagiWireLength(dir),gap1_cm:100*(yagiCenterX(drv)-yagiCenterX(ref)),gap2_cm:100*(yagiCenterX(dir)-yagiCenterX(drv))}:null;
  return {captured_at:new Date().toISOString(),model_hash:hash,frequency_hz:Number(p.frequency_hz||0),project:JSON.parse(JSON.stringify(p)),result:resultOk?{r_ohm:Number(f?.impedance_ohm?.re),x_ohm:Number(f?.impedance_ohm?.im),vswr:Number(f?.vswr),dmax_dbi:Number(lastResult.summary?.dmax_dbi),efficiency:Number(lastResult.efficiency)}:null,sweep:sweepOk?compactSweep(lastSweep):null,yagi};
}
function snapshotValue(s,path,n=2){let v=s;for(const k of path.split('.'))v=v?.[k];return Number.isFinite(Number(v))?Number(v).toFixed(n):'—'}
function signed(v,n=2,suffix=''){const x=Number(v);if(!Number.isFinite(x))return '—';return `${x>0?'+':''}${x.toFixed(n)}${suffix}`}
function variantDeltaSummary(base,row){
  const a=base?.snapshot,b=row?.snapshot;if(!a||!b)return 'нет полного снимка для сравнения';const parts=[];
  if(a.yagi&&b.yagi){parts.push(`DIR ${signed((b.yagi.dir_cm-a.yagi.dir_cm)*10,1,' мм')}`);parts.push(`DRV→DIR ${signed((b.yagi.gap2_cm-a.yagi.gap2_cm)*10,1,' мм')}`)}
  if(Number.isFinite(a.result?.vswr)&&Number.isFinite(b.result?.vswr))parts.push(`КСВ ${a.result.vswr.toFixed(2)}→${b.result.vswr.toFixed(2)} (${signed(b.result.vswr-a.result.vswr,2)})`);
  if(Number.isFinite(a.result?.dmax_dbi)&&Number.isFinite(b.result?.dmax_dbi))parts.push(`Dmax ${signed(b.result.dmax_dbi-a.result.dmax_dbi,2,' dB')}`);
  if(Number.isFinite(a.sweep?.resonance_frequency_hz)&&Number.isFinite(b.sweep?.resonance_frequency_hz))parts.push(`резонанс ${signed((b.sweep.resonance_frequency_hz-a.sweep.resonance_frequency_hz)/1e6,3,' МГц')}`);
  if(Number.isFinite(a.sweep?.min_s11_db)&&Number.isFinite(b.sweep?.min_s11_db))parts.push(`мин. S11 ${signed(b.sweep.min_s11_db-a.sweep.min_s11_db,2,' dB')}`);
  return parts.length?parts.join(' · '):'показатели ещё не рассчитаны';
}
function restoreVariantSnapshot(fp,label='вариант'){
  try{const snap=variantSnapshots[fp];if(!snap?.project)throw new Error('В этом старом снимке нет геометрии для восстановления');geometryRecordUndo(els.editor.value);const text=JSON.stringify(snap.project,null,2);els.editor.value=text;selectedWireId=snap.project.wires?.[0]?.id||null;updateMeta(snap.project);markResultsStale(`${label} восстановлен · нужно пересчитать`);setWorkspaceView('geometry');status(`${label} восстановлен · нажмите «Рассчитать изменения»`,'ok')}catch(e){status('не удалось восстановить вариант','err');els.diag.textContent=String(e.message||e)}
}
function renderVariantComparison(){
  if(!els.variantCompare)return;const rows=comparisonVariantRows();if(!rows.length){els.variantCompare.className='variant-compare muted';els.variantCompare.textContent='Сохраните рассчитанные варианты — здесь появится сравнение.';renderSweepOverlayControls();return}
  els.variantCompare.className='variant-compare';const cols=rows;
  const cell=(c,fn,missing='—')=>c.snapshot?fn(c.snapshot):`<span class="variant-missing">${missing}</span>`;
  const tr=(label,fn)=>`<tr><td>${label}</td>${cols.map(c=>`<td>${cell(c,fn)}</td>`).join('')}</tr>`;
  const deltas=cols.length>1?`<div class="variant-delta-list">${cols.slice(1).map(c=>`<div class="variant-delta-row"><b>${c.label} относительно A</b><span>${escapeHtml(variantDeltaSummary(cols[0],c))}</span></div>`).join('')}</div>`:'';
  els.variantCompare.innerHTML=`<table class="variant-compare-table"><thead><tr><th>Параметр</th>${cols.map(c=>`<th class="variant-col">${c.label} · ${escapeHtml(c.v.name||c.v.variant_id)}${c.snapshot?.project?`<button type="button" class="variant-restore" data-variant-restore="${escapeHtml(c.v.immutability.fingerprint)}">Открыть ${c.label}</button>`:''}</th>`).join('')}</tr></thead><tbody>${tr('Zin, Ω',s=>s.result?`${snapshotValue(s,'result.r_ohm')} ${Number(s.result.x_ohm)>=0?'+':'−'} j${snapshotValue({v:Math.abs(Number(s.result.x_ohm))},'v')}`:'—')}${tr('КСВ',s=>snapshotValue(s,'result.vswr',3))}${tr('Dmax, dBi',s=>snapshotValue(s,'result.dmax_dbi',2))}${tr('Резонанс, МГц',s=>Number.isFinite(Number(s.sweep?.resonance_frequency_hz))?(Number(s.sweep.resonance_frequency_hz)/1e6).toFixed(3):'—')}${tr('Мин. S11, dB',s=>snapshotValue(s,'sweep.min_s11_db',2))}${tr('Полоса −10 dB, МГц',s=>Number.isFinite(Number(s.sweep?.bandwidth_10db_hz))?(Number(s.sweep.bandwidth_10db_hz)/1e6).toFixed(3):'—')}${tr('REF / DRV / DIR, см',s=>s.yagi?`${s.yagi.ref_cm.toFixed(1)} / ${s.yagi.drv_cm.toFixed(1)} / ${s.yagi.dir_cm.toFixed(1)}`:'—')}${tr('Зазоры, см',s=>s.yagi?`${s.yagi.gap1_cm.toFixed(1)} / ${s.yagi.gap2_cm.toFixed(1)}`:'—')}</tbody></table>${deltas}<div class="variant-compare-note">A/B/C — три последних сохранённых варианта в порядке создания. «Открыть» восстанавливает геометрию, но требует нового расчёта.</div>`;
  els.variantCompare.querySelectorAll('[data-variant-restore]').forEach(b=>b.onclick=()=>{const row=cols.find(c=>c.v.immutability?.fingerprint===b.dataset.variantRestore);restoreVariantSnapshot(b.dataset.variantRestore,row?`${row.label} · ${row.v.name||row.v.variant_id}`:'вариант')});renderSweepOverlayControls();if(lastSweep)drawSweep(lastSweep)
}
function renderVariantHistory(){
  if(!els.variantHistory)return;
  if(!variantHistory.length){els.variantHistory.className='variant-history muted';els.variantHistory.textContent='Сохранённых вариантов пока нет.';return}
  els.variantHistory.className='variant-history';const compare=new Map(comparisonVariantRows().map(r=>[r.v.immutability?.fingerprint,r.label]));
  els.variantHistory.innerHTML=variantHistory.map((v,i)=>{const active=lastVariant?.immutability?.fingerprint===v.immutability?.fingerprint,letter=compare.get(v.immutability?.fingerprint)||'·',archived=letter==='·';return `<button type="button" class="variant-row${active?' active':''}" data-variant-index="${i}"><span class="variant-letter">${letter}</span><span><b>${escapeHtml(v.name||v.variant_id)}</b><small>${archived?'<span class="variant-archive-label">архив · </span>':''}${escapeHtml(v.variant_id)} · model ${escapeHtml(workflowShort(v.model_ref?.model_hash,12))}</small></span><span class="variant-fp">${escapeHtml(workflowShort(v.immutability?.fingerprint,10))}</span></button>`}).join('');
  els.variantHistory.querySelectorAll('[data-variant-index]').forEach(b=>b.onclick=()=>{const v=variantHistory[Number(b.dataset.variantIndex)];if(v){lastVariant=v;lastMeasurementSet=null;lastReport=null;els.variantName.value=v.name||v.variant_id;renderVariantHistory();renderVariantComparison();renderReportPreview();syncWorkflowButtons();status('вариант выбран','ok')}});renderVariantComparison()
}
function syncWorkflowButtons(){
  if(!els.variantSave)return;
  els.measurementBind.disabled=!(lastVariant&&lastMeasurement&&lastMeasurementRawText);
  els.reportGenerate.disabled=!(lastVariant&&lastMeasurementSet&&lastSweep&&lastMeasurement&&lastComparison);
  els.reportDownload.disabled=!lastReport?.markdown;
  const bits=[];
  if(lastVariant)bits.push('вариант сохранён');
  if(lastMeasurementSet)bits.push('измерение привязано');
  if(lastReport)bits.push('отчёт готов');
  els.workflowSummary.textContent=bits.length?bits.join(' · '):'вариант ещё не сохранён';
  els.workflowSummary.classList.toggle('workflow-ok',!!lastReport);
}
function renderReportPreview(){
  if(!els.reportPreview)return;
  if(lastReport?.markdown){els.reportPreview.className='report-preview';els.reportPreview.textContent=lastReport.markdown;return}
  els.reportPreview.className='report-preview muted';
  if(lastMeasurementSet)els.reportPreview.textContent='Измерение связано с '+lastMeasurementSet.variant_ref.variant_id+'. Проверьте сравнение и сформируйте отчёт.';
  else if(lastVariant)els.reportPreview.textContent='Вариант '+lastVariant.variant_id+' сохранён. Импортируйте измерение и привяжите его к этому варианту.';
  else els.reportPreview.textContent='Сохраните вариант, привяжите измерение и выполните сравнение.';
}
async function saveVariant(){
  try{
    const p=project(),name=(els.variantName.value||p.name||'Design Variant').trim(),variant_id='variant-'+Date.now().toString(36);
    els.variantSave.disabled=true;status('сохраняю вариант…');
    const j=await api('/api/variant/create',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,variant_id,name,tags:['ui-rev28','ui-rev29'] /* compatibility marker: tags:['ui-rev28'] */})});
    lastVariant=j.variant;lastMeasurementSet=null;lastReport=null;
    variantHistory=[lastVariant,...variantHistory.filter(v=>v.immutability?.fingerprint!==lastVariant.immutability?.fingerprint)].slice(0,8);
    variantSnapshots[lastVariant.immutability.fingerprint]=captureVariantSnapshot(p,lastVariant);
    const keep=new Set(variantHistory.map(v=>v.immutability?.fingerprint).filter(Boolean));Object.keys(variantSnapshots).forEach(k=>{if(!keep.has(k))delete variantSnapshots[k]});
    persistVariantHistory();renderVariantHistory();renderVariantComparison();renderReportPreview();syncWorkflowButtons();
    status('вариант сохранён · модель зафиксирована','ok')
  }catch(e){status('ошибка сохранения варианта','err');els.diag.textContent=String(e.message||e)}finally{els.variantSave.disabled=false}
}
async function bindMeasurement(){
  try{
    if(!lastVariant)throw new Error('Сначала сохраните или выберите вариант');
    if(!lastMeasurement||!lastMeasurementRawText)throw new Error('Сначала импортируйте измерение в этой вкладке');
    els.measurementBind.disabled=true;status('привязка измерения…');
    const measurement_id=(lastMeasurement.source?.name||'measurement').replace(/[^a-zA-Z0-9_.-]+/g,'-')+'-'+Date.now().toString(36);
    const j=await api('/api/measurement/bind',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({variant:lastVariant,measurement:lastMeasurement,raw_text:lastMeasurementRawText,measurement_id,calibration:{type:els.measurementCalibration.value||'unknown',reference_plane_note:els.measurementReferencePlane.value.trim(),fixture_deembedded:false},provenance:{instrument_or_source:lastMeasurement.source?.name||'browser import',notes:'Bound in EMMana-Next rev28 UI'}})});
    lastMeasurementSet=j.measurement_set;lastReport=null;renderReportPreview();syncWorkflowButtons();status('измерение привязано к варианту','ok')
  }catch(e){status('ошибка привязки','err');els.diag.textContent=String(e.message||e)}finally{syncWorkflowButtons()}
}
async function generateReport(){
  try{
    if(!lastVariant||!lastMeasurementSet||!lastSweep||!lastMeasurement||!lastComparison)throw new Error('Нужны сохранённый вариант, привязанное измерение, частотный расчёт и сравнение');
    els.reportGenerate.disabled=true;status('формирую инженерный отчёт…');
    const j=await api('/api/report/generate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({variant:lastVariant,measurement_set:lastMeasurementSet,sweep:lastSweep,measurement:lastMeasurement,comparison:lastComparison})});
    lastReport=j.report;renderReportPreview();syncWorkflowButtons();status('инженерный отчёт готов','ok')
  }catch(e){status('ошибка отчёта','err');els.diag.textContent=String(e.message||e)}finally{syncWorkflowButtons()}
}
function downloadReport(){
  if(!lastReport?.markdown)return;
  const blob=new Blob([lastReport.markdown],{type:'text/markdown;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');
  a.href=url;a.download=(lastVariant?.variant_id||'emnext-report')+'.md';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),500)
}
let geometryProjection='xz',selectedWireId=null,geometryDrag=null,geometryView=null;
const geometryAxes={xy:[0,1,'X','Y'],xz:[0,2,'X','Z'],yz:[1,2,'Y','Z']};
function geometryWire(p){return (p.wires||[]).find(w=>w.id===selectedWireId)||null}
function ensureGeometrySelection(p){const wires=p.wires||[];if(!wires.length){selectedWireId=null;return null}if(!wires.some(w=>w.id===selectedWireId))selectedWireId=wires[0].id;return geometryWire(p)}
function geometryBounds(p){const [a,b]=geometryAxes[geometryProjection],vals=(p.wires||[]).flatMap(w=>[w.start_m,w.end_m]);if(!vals.length)return{minA:-.5,maxA:.5,minB:-.5,maxB:.5};let minA=Math.min(...vals.map(v=>Number(v[a]))),maxA=Math.max(...vals.map(v=>Number(v[a]))),minB=Math.min(...vals.map(v=>Number(v[b]))),maxB=Math.max(...vals.map(v=>Number(v[b])));let da=Math.max(maxA-minA,.05),db=Math.max(maxB-minB,.05),m=.14*Math.max(da,db);return{minA:minA-m,maxA:maxA+m,minB:minB-m,maxB:maxB+m}}
function geometryTransform(p,locked=null){const c=els.geometryCanvas,W=c.width,H=c.height,pad=56,bounds=locked?.bounds||geometryBounds(p),da=Math.max(bounds.maxA-bounds.minA,1e-9),db=Math.max(bounds.maxB-bounds.minB,1e-9),scale=Math.min((W-2*pad)/da,(H-2*pad)/db);return{bounds,scale,pad,W,H,toScreen(v){const[a,b]=geometryAxes[geometryProjection];return{x:pad+(Number(v[a])-bounds.minA)*scale,y:H-pad-(Number(v[b])-bounds.minB)*scale}},fromScreen(x,y,base){const[a,b]=geometryAxes[geometryProjection],v=[...base];v[a]=bounds.minA+(x-pad)/scale;v[b]=bounds.minB+(H-pad-y)/scale;return v}}}
function geometryCanvasPoint(ev){const r=els.geometryCanvas.getBoundingClientRect();return{x:(ev.clientX-r.left)*els.geometryCanvas.width/r.width,y:(ev.clientY-r.top)*els.geometryCanvas.height/r.height}}
function geometryDistanceToSegment(px,py,a,b){const dx=b.x-a.x,dy=b.y-a.y,l2=dx*dx+dy*dy;if(!l2)return Math.hypot(px-a.x,py-a.y);const t=Math.max(0,Math.min(1,((px-a.x)*dx+(py-a.y)*dy)/l2));return Math.hypot(px-(a.x+t*dx),py-(a.y+t*dy))}
function syncGeometryInspector(p){const w=ensureGeometrySelection(p),inputs=[els.geometrySx,els.geometrySy,els.geometrySz,els.geometryEx,els.geometryEy,els.geometryEz,els.geometryDiameter,els.geometrySegments];inputs.forEach(x=>{if(x)x.disabled=!w});els.geometryDelete.disabled=!w;els.geometryFeed.disabled=!w;if(!w){els.geometryWireId.textContent='—';els.geometryFeedStatus.textContent='Нет проводов.';els.geometryFeedStatus.classList.remove('active');return}els.geometryWireId.textContent=w.id;[els.geometrySx,els.geometrySy,els.geometrySz].forEach((x,i)=>x.value=Number(w.start_m[i]).toFixed(4));[els.geometryEx,els.geometryEy,els.geometryEz].forEach((x,i)=>x.value=Number(w.end_m[i]).toFixed(4));els.geometryDiameter.value=(2000*Number(w.radius_m)).toFixed(3);els.geometrySegments.value=Number(w.segments);const feed=(p.feeds||[]).find(f=>f.wire_id===w.id);els.geometryFeedStatus.textContent=feed?'● Feed · segment '+feed.segment:'Feed не назначен этому проводу.';els.geometryFeedStatus.classList.toggle('active',!!feed)}
function renderGeometry(p){if(!els.geometryCanvas)return;const c=els.geometryCanvas,ctx=c.getContext('2d'),W=c.width,H=c.height;ctx.clearRect(0,0,W,H);ctx.fillStyle='#0b0d11';ctx.fillRect(0,0,W,H);const wires=p.wires||[],view=geometryTransform(p,geometryDrag?.view||null);geometryView=view;ctx.strokeStyle='#202632';ctx.lineWidth=1;for(let i=0;i<=10;i++){const x=40+(W-80)*i/10;ctx.beginPath();ctx.moveTo(x,28);ctx.lineTo(x,H-36);ctx.stroke()}for(let i=0;i<=7;i++){const y=28+(H-64)*i/7;ctx.beginPath();ctx.moveTo(40,y);ctx.lineTo(W-40,y);ctx.stroke()}const axes=geometryAxes[geometryProjection];ctx.fillStyle='#697384';ctx.font='12px Inter,system-ui';ctx.fillText(axes[2]+' →',W-55,H-12);ctx.fillText(axes[3]+' ↑',12,20);for(const w of wires){const a=view.toScreen(w.start_m),b=view.toScreen(w.end_m),sel=w.id===selectedWireId;ctx.strokeStyle=sel?'#3b82f6':'#8992a3';ctx.lineWidth=sel?6:4;ctx.lineCap='round';ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke();ctx.fillStyle=sel?'#82b5ff':'#8992a3';ctx.font='11px Inter,system-ui';ctx.fillText(w.id,(a.x+b.x)/2+7,(a.y+b.y)/2-7);if(sel){for(const pt of[a,b]){ctx.beginPath();ctx.fillStyle='#f4f6fb';ctx.strokeStyle='#3b82f6';ctx.lineWidth=3;ctx.arc(pt.x,pt.y,7,0,Math.PI*2);ctx.fill();ctx.stroke()}}const feed=(p.feeds||[]).find(f=>f.wire_id===w.id);if(feed){const t=Math.max(0,Math.min(1,(Number(feed.segment)+.5)/Math.max(1,Number(w.segments)))),x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t;ctx.beginPath();ctx.fillStyle='#43d17c';ctx.strokeStyle='#0b0d11';ctx.lineWidth=3;ctx.arc(x,y,8,0,Math.PI*2);ctx.fill();ctx.stroke()}}syncGeometryInspector(p);els.geometrySummary.textContent=geometryProjection.toUpperCase()+' · '+wires.length+' wires · drag endpoints · '+(selectedWireId||'no selection')}
const GEOMETRY_STALE_MESSAGE='геометрия обновлена · нужно пересчитать';
function syncGeometryHistoryButtons(){if(els.geometryUndo)els.geometryUndo.disabled=!geometryUndoStack.length;if(els.geometryRedo)els.geometryRedo.disabled=!geometryRedoStack.length;if(els.geometryHistoryState)els.geometryHistoryState.textContent=geometryUndoStack.length||geometryRedoStack.length?`назад ${geometryUndoStack.length} · вперёд ${geometryRedoStack.length}`:'история пуста'}
function resetGeometryHistory(){geometryUndoStack=[];geometryRedoStack=[];syncGeometryHistoryButtons()}
function geometryRecordUndo(text){if(!text)return;const last=geometryUndoStack[geometryUndoStack.length-1];if(last!==text)geometryUndoStack.push(text);if(geometryUndoStack.length>GEOMETRY_HISTORY_LIMIT)geometryUndoStack.shift();geometryRedoStack=[];syncGeometryHistoryButtons()}
function geometryRestoreText(text,message){els.editor.value=text;const p=project();selectedWireId=(p.wires||[]).some(w=>w.id===selectedWireId)?selectedWireId:p.wires?.[0]?.id||null;updateMeta(p);markResultsStale(`${message} · нужно пересчитать`);syncGeometryHistoryButtons()}
function undoGeometry(){if(!geometryUndoStack.length)return;try{const current=els.editor.value,prev=geometryUndoStack.pop();geometryRedoStack.push(current);geometryRestoreText(prev,'изменение отменено');status('изменение геометрии отменено','ok')}catch(e){status('ошибка Undo','err');els.diag.textContent=String(e.message||e)}}
function redoGeometry(){if(!geometryRedoStack.length)return;try{const current=els.editor.value,next=geometryRedoStack.pop();geometryUndoStack.push(current);geometryRestoreText(next,'изменение возвращено');status('изменение геометрии возвращено','ok')}catch(e){status('ошибка Redo','err');els.diag.textContent=String(e.message||e)}}
function geometryCommit(p,msg='геометрия обновлена',beforeText=null){const before=beforeText??els.editor.value,after=JSON.stringify(p,null,2);if(before!==after)geometryRecordUndo(before);els.editor.value=after;updateMeta(p);markResultsStale(`${msg} · нужно пересчитать`);syncGeometryHistoryButtons()}

function applyGeometryFields(){try{const p=project(),w=geometryWire(p);if(!w)return;const s=[els.geometrySx,els.geometrySy,els.geometrySz].map(x=>Number(x.value)),e=[els.geometryEx,els.geometryEy,els.geometryEz].map(x=>Number(x.value)),diam=Number(els.geometryDiameter.value),segments=Math.round(Number(els.geometrySegments.value));if([...s,...e,diam,segments].some(x=>!Number.isFinite(x))||diam<=0||segments<3)throw new Error('Проверь координаты, диаметр и число сегментов');w.start_m=s;w.end_m=e;w.radius_m=diam/2000;w.segments=segments;const feed=(p.feeds||[]).find(f=>f.wire_id===w.id);if(feed)feed.segment=Math.min(Math.max(0,Number(feed.segment)||0),segments-1);geometryCommit(p)}catch(e){status('ошибка геометрии','err');els.diag.textContent=String(e.message||e)}}
function addGeometryWire(){try{const p=project(),wires=p.wires||(p.wires=[]),used=new Set(wires.map(w=>w.id));let n=1;while(used.has('W'+n))n++;const id='W'+n,[a,b]=geometryAxes[geometryProjection],freq=Number(p.frequency_hz)||299792458,lambda=299792458/freq,len=.5*lambda,gap=.18*lambda,bounds=geometryBounds(p),centerA=wires.length?bounds.maxA+gap:0,centerB=(bounds.minB+bounds.maxB)/2,hidden=[0,1,2].find(x=>x!==a&&x!==b),start=[0,0,0],end=[0,0,0];start[a]=end[a]=centerA;start[b]=centerB-len/2;end[b]=centerB+len/2;start[hidden]=end[hidden]=0;wires.push({id,start_m:start,end_m:end,radius_m:.001,segments:21});selectedWireId=id;geometryCommit(p,'провод добавлен')}catch(e){status('ошибка добавления','err');els.diag.textContent=String(e.message||e)}}
function deleteGeometryWire(){try{const p=project(),w=geometryWire(p);if(!w)return;if((p.wires||[]).length<=1)throw new Error('Нельзя удалить последний провод');const referenced=(p.design_variables||[]).some(v=>v.wire_id===w.id)||(p.design_constraints||[]).some(c=>c.wire_a===w.id||c.wire_b===w.id);if(referenced)throw new Error('Провод используется в переменных или ограничениях оптимизации. Сначала измените их в EMNX.');p.wires=p.wires.filter(x=>x.id!==w.id);p.loads=(p.loads||[]).filter(x=>x.wire_id!==w.id);p.feeds=(p.feeds||[]).filter(x=>x.wire_id!==w.id);if(!p.feeds.length&&p.wires.length){const q=p.wires[0];p.feeds=[{wire_id:q.id,segment:Math.floor((Number(q.segments)-1)/2),voltage_re_v:1,voltage_im_v:0}]}selectedWireId=p.wires[0]?.id||null;geometryCommit(p,'провод удалён')}catch(e){status('удаление отменено','err');els.diag.textContent=String(e.message||e)}}
function assignGeometryFeed(){try{const p=project(),w=geometryWire(p);if(!w)throw new Error('Выберите провод');p.feeds=[{wire_id:w.id,segment:Math.floor((Number(w.segments)-1)/2),voltage_re_v:1,voltage_im_v:0}];geometryCommit(p,'питание назначено')}catch(e){status('ошибка назначения питания','err');els.diag.textContent=String(e.message||e)}}
function geometryPointerDown(ev){try{const p=project(),wires=p.wires||[],pt=geometryCanvasPoint(ev),view=geometryView||geometryTransform(p);let endpoint=null,best=14;for(const w of wires){for(const key of['start_m','end_m']){const q=view.toScreen(w[key]),d=Math.hypot(pt.x-q.x,pt.y-q.y);if(d<best){best=d;endpoint={wireId:w.id,key}}}}if(endpoint){selectedWireId=endpoint.wireId;geometryDrag={wireId:endpoint.wireId,key:endpoint.key,view:{bounds:{...view.bounds}},beforeText:els.editor.value};els.geometryCanvas.setPointerCapture?.(ev.pointerId);renderGeometry(p);ev.preventDefault();return}let hit=null,hd=12;for(const w of wires){const a=view.toScreen(w.start_m),b=view.toScreen(w.end_m),d=geometryDistanceToSegment(pt.x,pt.y,a,b);if(d<hd){hd=d;hit=w.id}}if(hit){selectedWireId=hit;renderGeometry(p);ev.preventDefault()}}catch(e){status('ошибка выбора','err')}}
function geometryPointerMove(ev){if(!geometryDrag)return;try{const p=project(),w=(p.wires||[]).find(x=>x.id===geometryDrag.wireId);if(!w)return;const pt=geometryCanvasPoint(ev),view=geometryTransform(p,geometryDrag.view),base=w[geometryDrag.key];w[geometryDrag.key]=view.fromScreen(pt.x,pt.y,base);els.editor.value=JSON.stringify(p,null,2);updateMeta(p);status('геометрия изменена · отпустите мышь и пересчитайте','warn');ev.preventDefault()}catch(e){status('ошибка drag','err')}}
function geometryPointerUp(ev){if(!geometryDrag)return;const beforeText=geometryDrag.beforeText;geometryDrag=null;try{const p=project();geometryCommit(p,'геометрия обновлена',beforeText)}catch{}els.geometryCanvas.releasePointerCapture?.(ev.pointerId)}
function syncGeometryFromProject(p){if(!els.geometryCanvas)return;ensureGeometrySelection(p);renderGeometry(p);syncTemplateParameterPanelFromProject(p);if(els.geometryTemplateFrequency&&document.activeElement!==els.geometryTemplateFrequency&&p.frequency_hz)els.geometryTemplateFrequency.value=(Number(p.frequency_hz)/1e6).toFixed(3)}

function yagiWire(p,id){return(p.wires||[]).find(w=>w.id===id)}
function yagiWireLength(w){if(!w)return NaN;return Math.hypot(w.end_m[0]-w.start_m[0],w.end_m[1]-w.start_m[1],w.end_m[2]-w.start_m[2])}
function yagiCenterX(w){return w?(Number(w.start_m[0])+Number(w.end_m[0]))/2:NaN}
function isYagiQuickProject(p){return !!(yagiWire(p,'REF')&&yagiWire(p,'DRV')&&yagiWire(p,'DIR1')&&(p.design_variables||[]).length)}
function setYagiWireLength(w,length){const a=w.start_m,b=w.end_m,dx=b[0]-a[0],dy=b[1]-a[1],dz=b[2]-a[2],old=Math.hypot(dx,dy,dz);if(!(old>0))throw new Error('Нулевая длина элемента');const ux=dx/old,uy=dy/old,uz=dz/old,mx=(a[0]+b[0])/2,my=(a[1]+b[1])/2,mz=(a[2]+b[2])/2,h=length/2;w.start_m=[mx-ux*h,my-uy*h,mz-uz*h];w.end_m=[mx+ux*h,my+uy*h,mz+uz*h]}
function setYagiCenterX(w,x){const old=yagiCenterX(w),dx=x-old;w.start_m[0]+=dx;w.end_m[0]+=dx}
function setYagiField(el,value,digits=2){if(el&&document.activeElement!==el&&Number.isFinite(value))el.value=Number(value).toFixed(digits)}
function syncYagiQuickPanel(p){
  if(els.templateParamPanel){if(els.yagiQuickPanel)els.yagiQuickPanel.hidden=true;return}
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

let geometryTemplates=[],activeTemplateId=null;
const TEMPLATE_C0=299792458;
function currentTemplateItem(){return geometryTemplates.find(x=>x.id===els.geometryTemplate?.value)||null}
function templateLambda(){const mhz=Number(els.geometryTemplateFrequency?.value);return mhz>0?TEMPLATE_C0/(mhz*1e6):1}
function templateParamDefaultSI(spec){const lam=templateLambda();return spec.default_lambda!=null?Number(spec.default_lambda)*lam:Number(spec.default??0)}
function templateParamBoundUI(spec,key){const lam=templateLambda(),lk=key+'_lambda',v=spec[lk]!=null?Number(spec[lk])*lam:spec[key];return v==null?null:templateSiToUi(spec,Number(v))}
function templateSiToUi(spec,v){return spec.ui_unit==='cm'?v*100:spec.ui_unit==='mm'?v*1000:v}
function templateUiToSi(spec,v){return spec.ui_unit==='cm'?v/100:spec.ui_unit==='mm'?v/1000:v}
function templateUnitLabel(spec){return spec.ui_unit==='cm'?'см':spec.ui_unit==='mm'?'мм':spec.ui_unit==='count'?'шт.':spec.ui_unit||''}
function renderTemplateParameterPanel(reset=true){
  const item=currentTemplateItem();if(!item||!els.templateParamPanel)return;activeTemplateId=item.id;els.templateParamTitle.textContent=item.label;const trustLabels={'reference-validated':'проверено по эталону','characterized':'охарактеризовано','experimental':'экспериментально'};els.templateParamTrust.textContent=trustLabels[item.trust]||item.trust||'экспериментально';els.templateParamPanel.classList.toggle('experimental',item.trust==='experimental');els.templateParamPanel.classList.toggle('reference',item.trust==='reference-validated');els.templateParamFields.innerHTML='';
  for(const spec of item.parameters||[]){const label=document.createElement('label');label.textContent=spec.label+(templateUnitLabel(spec)?`, ${templateUnitLabel(spec)}`:'');const input=document.createElement('input');input.type='number';input.dataset.templateParam=spec.id;input.step=String(spec.step??(spec.ui_unit==='count'?2:.1));const lo=templateParamBoundUI(spec,'min'),hi=templateParamBoundUI(spec,'max');if(lo!=null)input.min=String(lo);if(hi!=null)input.max=String(hi);input.value=String(templateSiToUi(spec,templateParamDefaultSI(spec)).toFixed(spec.ui_unit==='count'?0:3));label.appendChild(input);if(spec.help){const small=document.createElement('span');small.className='template-param-help';small.textContent=spec.help;label.appendChild(small)}els.templateParamFields.appendChild(label)}
  els.templateParamOptimize.disabled=!item.supports_optimizer;els.templateParamOptimize.textContent=item.supports_optimizer?'Перейти к оптимизации':'Оптимизация недоступна';els.templateParamNote.textContent=(item.use_cases||[]).join(' · ')+' · EMNX остаётся источником физической модели';
}
function collectTemplateParameterQuery(){const item=currentTemplateItem();if(!item)throw new Error('Выберите шаблон');const qs=new URLSearchParams();const f=Number(els.geometryTemplateFrequency.value)*1e6;if(!(f>0))throw new Error('Частота должна быть > 0');qs.set('frequency_hz',String(f));for(const spec of item.parameters||[]){const input=els.templateParamFields.querySelector(`[data-template-param="${spec.id}"]`);const ui=Number(input?.value);if(!Number.isFinite(ui))throw new Error('Проверьте параметр: '+spec.label);qs.set(spec.id,String(templateUiToSi(spec,ui)))}return qs}
async function fetchParameterizedTemplate(){const item=currentTemplateItem();if(!item)throw new Error('Выберите шаблон');const qs=collectTemplateParameterQuery();return api('/api/template/'+encodeURIComponent(item.id)+'?'+qs.toString())}
function acceptTemplateProject(r,msg='параметры шаблона применены'){const before=els.editor.value,p=r.project;geometryRecordUndo(before);els.editor.value=JSON.stringify(p,null,2);selectedWireId=p.wires?.[0]?.id||null;updateMeta(p);syncGeometryHistoryButtons();activeTemplateId=r.template_id;markResultsStale(msg+' · нужно пересчитать');return p}
async function applyTemplateParameters(calculate=false){try{status('применяю параметры…');const r=await fetchParameterizedTemplate(),p=acceptTemplateProject(r);if(calculate){await check();await run();if(lastResult)await runSweep();setWorkspaceView('geometry');status('параметры рассчитаны','ok')}else status('геометрия шаблона обновлена','ok');return p}catch(e){status('ошибка параметров шаблона','err');els.diag.textContent=String(e.message||e);return null}}
async function optimizeTemplateParameters(){const item=currentTemplateItem();if(!item?.supports_optimizer)return;const p=await applyTemplateParameters(false);if(!p)return;setWorkspaceView('optimize');status('шаблон готов к оптимизации','ok')}
function syncTemplateParameterPanelFromProject(p){if(!activeTemplateId||activeTemplateId!==els.geometryTemplate?.value)return;const item=currentTemplateItem();if(!item)return;const wires=Object.fromEntries((p.wires||[]).map(w=>[w.id,w]));const length=w=>w?Math.hypot(w.end_m[0]-w.start_m[0],w.end_m[1]-w.start_m[1],w.end_m[2]-w.start_m[2]):NaN,cx=w=>w?(Number(w.start_m[0])+Number(w.end_m[0]))/2:NaN;for(const spec of item.parameters||[]){const b=spec.binding||{},input=els.templateParamFields.querySelector(`[data-template-param="${spec.id}"]`);if(!input||document.activeElement===input)continue;let v=NaN;if(b.kind==='wire_length')v=length(wires[b.wire_id]);else if(b.kind==='wire_length_from_start')v=length(wires[b.wire_id]);else if(b.kind==='wire_diameter_all')v=2*Number((p.wires||[])[0]?.radius_m);else if(b.kind==='wire_segments_all')v=Number((p.wires||[])[0]?.segments);else if(b.kind==='center_gap_x')v=cx(wires[b.wire_b])-cx(wires[b.wire_a]);else if(b.kind==='square_side')v=length(wires.W1);else if(b.kind==='yagi_director_spacing'&&wires.DIR2)v=cx(wires.DIR2)-cx(wires.DIR1);else if(b.kind==='yagi_director_step'&&wires.DIR2)v=length(wires.DIR1)-length(wires.DIR2);else if(b.kind==='moxon_span')v=length(wires.DRV);else if(b.kind==='moxon_spacing')v=cx(wires.REF)-cx(wires.DRV);else if(b.kind==='moxon_end_gap')v=Number(wires.RTOP?.end_m?.[0])-Number(wires.DTOP?.end_m?.[0]);if(Number.isFinite(v))input.value=String(templateSiToUi(spec,v).toFixed(spec.ui_unit==='count'?0:3))}}
async function loadGeometryTemplates(){if(!els.geometryTemplate)return;try{const r=await api('/api/templates');geometryTemplates=(r.templates||[]).filter(x=>x.status==='implemented');els.geometryTemplate.innerHTML='';for(const item of geometryTemplates){const o=document.createElement('option');o.value=item.id;o.textContent=item.label;els.geometryTemplate.appendChild(o)}const preferred=geometryTemplates.find(x=>x.id==='yagi-3el')||geometryTemplates[0];if(preferred)els.geometryTemplate.value=preferred.id;syncGeometryTemplateStatus();renderTemplateParameterPanel();const p=project();if(p.frequency_hz)els.geometryTemplateFrequency.value=(Number(p.frequency_hz)/1e6).toFixed(3)}catch(e){els.geometryTemplate.innerHTML='<option value="">Шаблоны недоступны</option>';els.geometryTemplateStatus.textContent=String(e.message||e);els.geometryTemplateStatus.classList.remove('ready')}}
function syncGeometryTemplateStatus(){const item=geometryTemplates.find(x=>x.id===els.geometryTemplate?.value);if(!item){els.geometryTemplateStatus.textContent='—';return}const trustLabels={'reference-validated':'проверено по эталону','characterized':'охарактеризовано','experimental':'экспериментально'};els.geometryTemplateStatus.textContent=(trustLabels[item.trust]||item.trust||'экспериментально')+' · '+(item.use_cases||[]).join(' · ');els.geometryTemplateStatus.classList.toggle('ready',item.trust==='reference-validated'||item.trust==='characterized')}
async function createGeometryTemplate(){
  let templateLoaded=false,stage='создание шаблона';
  try{
    const id=els.geometryTemplate.value,fmhz=Number(els.geometryTemplateFrequency.value);
    if(!id)throw new Error('Выберите шаблон');if(!(fmhz>0))throw new Error('Частота должна быть > 0');
    if(!confirm('Заменить текущую модель шаблоном и выполнить расчёт?'))return;
    const beforeText=els.editor.value;els.geometryTemplateCreate.disabled=true;status('создаю шаблон…');
    const r=await fetchParameterizedTemplate(),p=r.project;templateLoaded=true;activeTemplateId=id;
    geometryRecordUndo(beforeText);els.editor.value=JSON.stringify(p,null,2);selectedWireId=p.wires?.[0]?.id||null;updateMeta(p);syncGeometryHistoryButtons();
    const mhz=Number(p.frequency_hz)/1e6;els.sweepStart.value=(mhz*.9).toFixed(3);els.sweepStop.value=(mhz*1.1).toFixed(3);els.optBandStart.value=(mhz*.99).toFixed(3);els.optBandStop.value=(mhz*1.01).toFixed(3);
    markResultsStale('шаблон создан · выполняю проверку');stage='проверка модели';
    const cj=await api('/api/model-check',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,kernel})});
    els.diag.textContent=cj.stdout+(cj.stderr?'\n'+cj.stderr:'');if(!cj.ok)throw new Error(cj.stderr||cj.stdout||'модель не прошла проверку');
    stage='расчёт';
    const sj=await api('/api/solve',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,kernel})});
    if(!sj.result)throw new Error('Расчёт не вернул результат');showResult(sj.result);els.run.textContent='Рассчитать';syncTemplateParameterPanelFromProject(p);setWorkspaceView('geometry');status('шаблон создан и рассчитан','ok')
  }catch(e){
    if(templateLoaded)markResultsStale('шаблон создан, но '+stage+' не завершён');
    status('ошибка: '+stage,'err');els.diag.textContent=String(e.message||e)
  }finally{els.geometryTemplateCreate.disabled=false}
}

function initGeometryEditor(){if(!els.geometryCanvas)return;els.geometryTemplateCreate.onclick=createGeometryTemplate;if(els.geometryUndo)els.geometryUndo.onclick=undoGeometry;if(els.geometryRedo)els.geometryRedo.onclick=redoGeometry;syncGeometryHistoryButtons();if(els.yagiApply)els.yagiApply.onclick=applyYagiQuickPanel;if(els.yagiRecalc)els.yagiRecalc.onclick=recalcYagiQuick;if(els.yagiOptimize)els.yagiOptimize.onclick=optimizeYagiQuick;if(els.templateParamApply)els.templateParamApply.onclick=()=>applyTemplateParameters(false);if(els.templateParamRecalc)els.templateParamRecalc.onclick=()=>applyTemplateParameters(true);if(els.templateParamOptimize)els.templateParamOptimize.onclick=optimizeTemplateParameters;els.geometryTemplate.addEventListener('change',()=>{syncGeometryTemplateStatus();renderTemplateParameterPanel(true)});els.geometryTemplateFrequency.addEventListener('change',()=>renderTemplateParameterPanel(true));loadGeometryTemplates();document.querySelectorAll('[data-geometry-projection]').forEach(b=>b.addEventListener('click',()=>{geometryProjection=b.dataset.geometryProjection;document.querySelectorAll('[data-geometry-projection]').forEach(x=>x.classList.toggle('active',x===b));try{renderGeometry(project())}catch{}}));els.geometryAdd.onclick=addGeometryWire;els.geometryFeed.onclick=assignGeometryFeed;els.geometryDelete.onclick=deleteGeometryWire;els.geometryCheck.onclick=check;[els.geometrySx,els.geometrySy,els.geometrySz,els.geometryEx,els.geometryEy,els.geometryEz,els.geometryDiameter,els.geometrySegments].forEach(x=>x.addEventListener('change',applyGeometryFields));els.geometryCanvas.addEventListener('pointerdown',geometryPointerDown);els.geometryCanvas.addEventListener('pointermove',geometryPointerMove);els.geometryCanvas.addEventListener('pointerup',geometryPointerUp);els.geometryCanvas.addEventListener('pointercancel',geometryPointerUp);els.editor.addEventListener('input',()=>{try{updateMeta(project());markResultsStale('модель изменена в EMNX · нужно пересчитать')}catch{}})}
function showResult(r){lastResult=r;const f=r.feeds?.[0],p=project(),lossy=(p.wires||[]).filter(w=>Number(w.conductivity_s_per_m||0)>0),loads=p.loads||[];const lossLines=[`Loss model: ${lossy.length?lossy.length+' finite-conductivity wire(s)':'PEC conductors'} · ${loads.length} lumped load(s)`];if(lossy.length)lossLines.push('Conductivity: '+lossy.map(w=>`${w.id||'?'}=${Number(w.conductivity_s_per_m).toExponential(3)} S/m`).join(', '));if(loads.length)lossLines.push('Loads: '+loads.map(x=>`${x.id||'?'}[${x.wire_id||'?'}:${x.segment_index??'?'}] R=${Number(x.resistance_ohm||0)}Ω L=${Number(x.inductance_h||0).toExponential(3)}H C=${Number(x.capacitance_f||0).toExponential(3)}F`).join('; '));els.zin.textContent=cpx(f?.impedance_ohm);els.vswr.textContent=fmt(f?.vswr,3);els.dmax.textContent=fmt(r.summary?.dmax_dbi,3);els.eff.textContent=fmt(100*(r.efficiency??0),3);els.accepted.textContent=Number(r.accepted_power_w||0).toExponential(3);els.radiated.textContent=Number(r.radiated_power_w||0).toExponential(3);els.dissipated.textContent=Number(r.dissipated_power_w||0).toExponential(3);els.balance.textContent=(r.power_balance_relative_error??0).toExponential(2);els.raw.textContent=JSON.stringify(r,null,2);els.diag.textContent=[`Solver: ${r.solver_id} v${r.solver_version}`,`Settings: ${r.solver_settings_id}`,`Model hash: ${r.model_hash}`,...lossLines,`Accepted power: ${r.accepted_power_w} W`,`Radiated power: ${r.radiated_power_w} W`,`Dissipated power: ${r.dissipated_power_w} W`,`Efficiency: ${fmt(100*(r.efficiency??0),4)}%`,'',...(r.warnings||[]).map(x=>'⚠ '+x)].join('\n');drawPolar(r);drawCurrents(r)}
async function run(){setWorkspaceView('solve');try{const p=project();updateMeta(p);document.body.classList.add('busy');els.run.disabled=true;status('расчёт…');const j=await api('/api/solve',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,kernel})});showResult(j.result);els.run.textContent='Рассчитать';status('расчёт завершён','ok')}catch(e){status('ошибка','err');els.diag.textContent=String(e.message||e)}finally{document.body.classList.remove('busy');els.run.disabled=false}}
async function check(){try{const p=project();status('проверка…');const j=await api('/api/model-check',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({project:p,kernel})});els.diag.textContent=j.stdout+(j.stderr?'\n'+j.stderr:'');status(j.ok?'модель корректна':'модель с ошибками',j.ok?'ok':'err')}catch(e){status('ошибка','err');els.diag.textContent=String(e.message||e)}}
let initialView='geometry';try{initialView=localStorage.getItem('emnext.workspaceView')||'solve'}catch{}setWorkspaceView(initialView);
initGeometryEditor();
document.addEventListener('keydown',e=>{const tag=String(document.activeElement?.tagName||'').toLowerCase();if(tag==='input'||tag==='textarea'||tag==='select')return;if(!(e.ctrlKey||e.metaKey))return;if(String(e.key).toLowerCase()==='z'){e.preventDefault();e.shiftKey?redoGeometry():undoGeometry()}else if(String(e.key).toLowerCase()==='y'){e.preventDefault();redoGeometry()}});
initSweepInteractions();
document.querySelectorAll('[data-kernel]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-kernel]').forEach(x=>x.classList.remove('active'));b.classList.add('active');kernel=b.dataset.kernel;els.chip.textContent=kernel==='reduced'?'БЫСТРЫЙ':'ТОЧНЫЙ КОНТРОЛЬ'});if(els.optGoal){els.optGoal.onchange=applyOptimizerGoalPreset;applyOptimizerGoalPreset()}[els.optAlg,els.optPop,els.optGen,els.optLocal,els.optSeed,els.optWMatch,els.optWGain,els.optWFb,els.optWSize,els.optGainGuard,els.optMaxVswr,els.optBandPoints,els.optQuantMm,els.optTolMm,els.optRobustSamples,els.optMcSamples].filter(Boolean).forEach(x=>x.addEventListener('change',markOptimizerGoalCustom));els.run.onclick=run;els.runSweep.onclick=runSweep;els.runOpt.onclick=runOptimize;els.applyOpt.onclick=applyBest;$('#check').onclick=check;els.example.onchange=loadExample;els.measurementImport.onclick=importMeasurement;if(els.measurementDemo)els.measurementDemo.onclick=loadMeasurementDemo;els.measurementCompare.onclick=compareMeasurement;els.measurementCalibration.onchange=renderMeasurementProvenance;els.measurementReferencePlane.oninput=renderMeasurementProvenance;els.variantSave.onclick=saveVariant;els.measurementBind.onclick=bindMeasurement;els.reportGenerate.onclick=generateReport;els.reportDownload.onclick=downloadReport;loadVariantHistory();syncWorkflowButtons();
(async()=>{try{const h=await api('/api/health');$('#version').textContent=`Локальная версия · ${h.version}`;await loadReferenceStatus();const e=await api('/api/examples');e.examples.forEach(x=>{const o=document.createElement('option');o.value=x.file;o.textContent=x.name;els.example.appendChild(o)});const preferred=e.examples.find(x=>x.file.includes('51seg'))||e.examples[0];if(preferred)els.example.value=preferred.file;await loadExample();status('готово · выберите шаблон или измените геометрию','ok')}catch(e){status('не готово','err');els.diag.textContent=String(e.message||e)}})();

// ---- alpha.20 runtime UX: ground controls, mobile drawer, unified Help Registry ----
const groundEls={mode:$('#ground-mode'),plane:$('#ground-plane'),epsr:$('#ground-epsr'),sigma:$('#ground-sigma')};
function syncGroundFromProject(p){
  if(!groundEls.mode)return;
  const g=p.ground||{model:'free-space',plane_z_m:0,relative_permittivity:13,conductivity_s_per_m:.005};
  groundEls.mode.value=g.model||'free-space';groundEls.plane.value=Number(g.plane_z_m??0);groundEls.epsr.value=Number(g.relative_permittivity??13);groundEls.sigma.value=Number(g.conductivity_s_per_m??.005);
  const real=groundEls.mode.value==='homogeneous-halfspace-image-v1'; groundEls.epsr.disabled=!real;groundEls.sigma.disabled=!real;
}
function applyGroundControls(){
  try{
    const p=project(); const model=groundEls.mode.value;
    p.ground={model,plane_z_m:Number(groundEls.plane.value||0),relative_permittivity:Number(groundEls.epsr.value||13),conductivity_s_per_m:Number(groundEls.sigma.value||0)};
    els.editor.value=JSON.stringify(p,null,2);updateMeta(p);markResultsStale('модель земли изменена · нужно пересчитать');
  }catch(e){status('ошибка ground','err');els.diag.textContent=String(e.message||e)}
}
const _updateMeta=updateMeta;updateMeta=function(p){_updateMeta(p);syncGroundFromProject(p);syncGeometryFromProject(p);window.renderGeometry3D?.(p);};
Object.values(groundEls).filter(Boolean).forEach(x=>x.addEventListener('change',applyGroundControls));

function setWorkspaceView(view){
  const valid=new Set(['model','geometry','solve','optimize','measurement']);
  if(!valid.has(view))view='solve';
  document.querySelectorAll('[data-view]').forEach(node=>{node.hidden=node.dataset.view!==view});
  document.querySelectorAll('[data-view-tab]').forEach(btn=>btn.classList.toggle('active',btn.dataset.viewTab===view));
  try{localStorage.setItem('emnext.workspaceView',view)}catch{}
}
document.querySelectorAll('[data-view-tab]').forEach(btn=>btn.addEventListener('click',()=>setWorkspaceView(btn.dataset.viewTab)));
const sidebar=$('#sidebar'),sidebarBackdrop=$('#sidebar-backdrop');
let helpData=null,helpTopics=new Map(),activeHelpTopic='emmana-next.overview',quickReturnTopic='emmana-next.overview';
const qh=$('#quick-help'),hb=$('#help-backdrop'),fh=$('#full-help');

// One owner for transient surfaces: never stack sidebar, Quick Help and Full Help.
const surfaceState={sidebar:false,quickHelp:false,fullHelp:false};
function syncSurfaceState(){
  sidebar?.classList.toggle('open',surfaceState.sidebar);
  if(sidebarBackdrop)sidebarBackdrop.hidden=!surfaceState.sidebar;
  if(qh)qh.hidden=!surfaceState.quickHelp;
  if(fh)fh.hidden=!surfaceState.fullHelp;
  if(hb)hb.hidden=!(surfaceState.quickHelp||surfaceState.fullHelp);
  document.body.style.overflow=(surfaceState.sidebar||surfaceState.quickHelp||surfaceState.fullHelp)?'hidden':'';
}
function showSurface(name){
  surfaceState.sidebar=name==='sidebar';
  surfaceState.quickHelp=name==='quickHelp';
  surfaceState.fullHelp=name==='fullHelp';
  syncSurfaceState();
}
function closeSurface(name){if(name in surfaceState)surfaceState[name]=false;syncSurfaceState()}
function setSidebar(open){if(!sidebar)return;open?showSurface('sidebar'):closeSurface('sidebar')}
$('#mobile-menu')?.addEventListener('click',()=>setSidebar(true));$('#sidebar-close')?.addEventListener('click',()=>setSidebar(false));sidebarBackdrop?.addEventListener('click',()=>setSidebar(false));
function helpTopic(id){return helpTopics.get(id)||helpTopics.get(helpData?.fallbackTopic)||null}
function resolveHelp(value){
  if(!helpData)return null;if(helpTopics.has(value))return helpTopics.get(value);const mapped=helpData.errorMap?.[value];if(mapped&&helpTopics.has(mapped))return helpTopics.get(mapped);
  const q=String(value||'').toLowerCase();return [...helpTopics.values()].find(t=>(t.aliases||[]).some(a=>String(a).toLowerCase()===q))||helpTopic(helpData.fallbackTopic);
}
function relatedButtons(topic,target){
  target.innerHTML='';for(const id of topic?.relatedTopics||[]){const t=helpTopic(id);if(!t)continue;const b=document.createElement('button');b.type='button';b.className='help-topic';b.textContent=t.title;b.onclick=()=>openQuickHelp(t.id);target.appendChild(b)}
}
function openQuickHelp(id='emmana-next.overview'){
  const t=resolveHelp(id);if(!t)return;activeHelpTopic=t.id;quickReturnTopic=t.id;
  $('#quick-help-title').textContent=t.title;$('#quick-help-summary').textContent=t.summary||'';$('#quick-help-body').textContent=t.body||'';
  const steps=$('#quick-help-steps');steps.innerHTML='';for(const s of t.quickSteps||[]){const li=document.createElement('li');li.textContent=s;steps.appendChild(li)}steps.hidden=!(t.quickSteps||[]).length;
  relatedButtons(t,$('#quick-help-related'));showSurface('quickHelp');history.replaceState(null,'',`${location.pathname}?topic=${encodeURIComponent(t.id)}${location.hash||''}`);
}
function closeQuickHelp(){closeSurface('quickHelp')}
function helpSearch(q){
  const s=String(q||'').trim().toLowerCase();const rows=[...helpTopics.values()].filter(t=>!s||[t.id,t.title,t.summary,t.body,...(t.keywords||[]),...(t.aliases||[])].some(v=>String(v||'').toLowerCase().includes(s)));
  return rows.sort((a,b)=>a.category.localeCompare(b.category)||a.title.localeCompare(b.title));
}
function renderTopicList(q=''){
  const box=$('#help-topic-list');box.innerHTML='';for(const t of helpSearch(q)){const b=document.createElement('button');b.type='button';b.className='help-topic-row'+(t.id===activeHelpTopic?' active':'');b.innerHTML=`${t.title}<small>${t.category||''}</small>`;b.onclick=()=>showFullTopic(t.id);box.appendChild(b)}
}
function showFullTopic(id){
  const t=resolveHelp(id);if(!t)return;activeHelpTopic=t.id;$('#full-help-category').textContent=(t.category||'help').toUpperCase();$('#full-help-title').textContent=t.title;$('#full-help-summary').textContent=t.summary||'';$('#full-help-body').textContent=t.body||'';relatedButtons(t,$('#full-help-related'));renderTopicList($('#help-search').value);history.replaceState(null,'',`${location.pathname}?topic=${encodeURIComponent(t.id)}${location.hash||''}`);
}
function openFullHelp(){const t=helpTopic(activeHelpTopic)||helpTopic(helpData?.fallbackTopic);if(!t)return;showSurface('fullHelp');renderTopicList();showFullTopic(t.id);setTimeout(()=>$('#help-search')?.focus(),0)}
function closeFullHelp(){closeSurface('fullHelp')}
function topicForError(text){const s=String(text||'').toLowerCase();if(s.includes('ground-terminal')||s.includes('ground terminal'))return helpData?.errorMap?.INVALID_GROUND_TERMINAL;if(s.includes('nec2')&&s.includes('not'))return helpData?.errorMap?.NEC2_NOT_RUN;if(s.includes('model')&&(s.includes('invalid')||s.includes('error')||s.includes('failed')))return helpData?.errorMap?.MODEL_CHECK_FAILED;return 'emmana-next.overview'}

async function initHelp(){
  try{helpData=await api('/api/help-registry');helpTopics=new Map((helpData.topics||[]).map(t=>[t.id,t]));const initial=new URL(location.href).searchParams.get('topic')||helpData.fallbackTopic;activeHelpTopic=resolveHelp(initial)?.id||helpData.fallbackTopic;
    document.querySelectorAll('[data-help-topic]').forEach(b=>b.addEventListener('click',()=>openQuickHelp(b.dataset.helpTopic)));
    $('#quick-help-close')?.addEventListener('click',closeQuickHelp);$('#help-full-open')?.addEventListener('click',openFullHelp);$('#full-help-close')?.addEventListener('click',closeFullHelp);$('#full-help-back')?.addEventListener('click',()=>openQuickHelp(quickReturnTopic));$('#help-search')?.addEventListener('input',e=>renderTopicList(e.target.value));hb?.addEventListener('click',()=>{if(surfaceState.fullHelp)closeFullHelp();else if(surfaceState.quickHelp)closeQuickHelp()});
    const observer=new MutationObserver(()=>{const b=$('#diag-help');if(b)b.dataset.helpTopic=topicForError(els.diag?.textContent||'')});if(els.diag)observer.observe(els.diag,{childList:true,subtree:true,characterData:true});
  }catch(e){console.warn('Help Registry unavailable',e)}
}
initHelp();