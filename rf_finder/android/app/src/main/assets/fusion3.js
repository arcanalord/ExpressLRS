(()=>{'use strict';
if(window.__rfFusion3Loaded)return;window.__rfFusion3Loaded=true;

const $=id=>document.getElementById(id);
const STORE='rfFinder.fusion3.v1', EARTH=6371000, TILE=256;
let nodes={
  A:newAnchor('A','#0A84FF'),
  B:newAnchor('B','#FFD60A'),
  T:{id:'T',deviceId:'T-001',online:false,lastSeen:null,color:'#30D158'}
};
let ranges={AB:null,AT:null,BT:null};
let rangeAt={AB:null,AT:null,BT:null};
let target=null,pendingGps=null,placeId=null,mapView=null,zoomDelta=0,mapEpoch=0;

function newAnchor(id,color){return{id,color,deviceId:id+'-001',lat:null,lon:null,accuracyM:null,provider:null,bearing:null,bearingAt:null,rssi:null};}
function n(v){v=Number(v);return Number.isFinite(v)?v:null;}
function coord(v){return Number.isFinite(v)?v.toFixed(6):'—';}
function age(ms){if(!Number.isFinite(ms))return'—';const d=Math.max(0,Date.now()-ms);return d<60000?Math.round(d/1000)+' с':d<3600000?Math.round(d/60000)+' мин':Math.round(d/3600000)+' ч';}
function dist(a,b){const p=(a.lat+b.lat)/2*Math.PI/180,dx=(b.lon-a.lon)*Math.PI/180*EARTH*Math.cos(p),dy=(b.lat-a.lat)*Math.PI/180*EARTH;return Math.hypot(dx,dy);}
function xy(lat,lon,lat0,lon0){const r=Math.PI/180;return{x:(lon-lon0)*r*EARTH*Math.cos(lat0*r),y:(lat-lat0)*r*EARTH};}
function ll(x,y,lat0,lon0){const r=Math.PI/180;return{lat:lat0+y/EARTH/r,lon:lon0+x/(EARTH*Math.cos(lat0*r))/r};}
function cross(ax,ay,bx,by){return ax*by-ay*bx;}
function angleDiff(a,b){return Math.abs(((a-b+540)%360)-180);}

function css(){
 const s=document.createElement('style');s.id='rf-fusion3-style';s.textContent=
 '#rfFusion3{margin-top:14px}.f3Head{display:flex;justify-content:space-between;align-items:flex-start;gap:10px}.f3Mode{font-size:12px;color:var(--green);font-weight:700}.f3TargetId{display:grid;grid-template-columns:1fr 150px;gap:8px;align-items:end;margin-top:10px}.f3TargetId input,.f3Range input,.f3Manual input{min-height:44px;border:1px solid var(--hair2);border-radius:10px;background:#0B0D10;color:var(--text);padding:0 9px}.f3Map{position:relative;height:310px;overflow:hidden;border:1px solid var(--hair);border-radius:16px;background:#0A0D10;background-image:linear-gradient(rgba(255,255,255,.025) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.025) 1px,transparent 1px);background-size:32px 32px;margin-top:10px;touch-action:manipulation}.f3Tiles,.f3Overlay{position:absolute;inset:0;width:100%;height:100%}.f3Tiles img{position:absolute;width:256px;height:256px;filter:grayscale(.22) brightness(.58) contrast(1.08);user-select:none;-webkit-user-drag:none}.f3Overlay{pointer-events:none}.f3MapBar{position:absolute;left:8px;right:8px;top:8px;display:flex;justify-content:space-between;pointer-events:none}.f3MapCtl{display:flex;gap:6px;pointer-events:auto}.f3MapCtl button{width:44px;height:44px;border-radius:11px;border:1px solid rgba(255,255,255,.18);background:rgba(17,19,22,.92);color:var(--text);font-weight:800}.f3MapState,.f3Hint{padding:5px 8px;border-radius:9px;background:rgba(11,11,12,.84);font-size:12px;color:#D3D6DC}.f3Hint{position:absolute;left:8px;bottom:8px}.f3Attr{position:absolute;right:7px;bottom:5px;font-size:10px;color:#D7D7DC;background:rgba(0,0,0,.58);padding:2px 5px;border-radius:6px}'+
 '.f3Nodes{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:10px}.f3Node{border:1px solid var(--hair);border-radius:14px;padding:10px;background:#0E1013}.f3NodeHead{display:flex;justify-content:space-between;align-items:center}.f3Badge{width:32px;height:32px;border-radius:9px;display:grid;place-items:center;font-weight:800}.f3A{background:rgba(10,132,255,.18);color:#74B9FF}.f3B{background:rgba(255,214,10,.12);color:#FFD60A}.f3T{background:rgba(48,209,88,.14);color:#30D158}.f3Node b{display:block;margin-top:7px;font:700 14px ui-monospace,monospace}.f3Node small{display:block;color:var(--muted);margin-top:3px}.f3Actions{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:8px}.f3Actions button{min-height:44px;padding:0 7px}.f3Manual{display:none;grid-template-columns:1fr 1fr;gap:6px;margin-top:7px}.f3Manual.open{display:grid}.f3Manual input{width:100%;min-width:0}.f3Manual button{grid-column:1/-1;min-height:44px}'+
 '.f3Ranges{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:10px}.f3Range{border:1px solid var(--hair);border-radius:12px;padding:9px;background:#0B0D10}.f3Range input{width:100%;margin-top:5px;text-align:center;font:700 16px ui-monospace,monospace}.f3Range small{display:block;color:var(--muted);margin-top:4px}.f3Metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin-top:10px}.f3Metric{padding:8px;border:1px solid var(--hair);border-radius:11px;background:#0B0D10;text-align:center}.f3Metric span{display:block;color:var(--muted);font-size:12px}.f3Metric b{display:block;font:700 14px ui-monospace,monospace;margin-top:2px}.f3Result{margin-top:10px;padding-top:10px;border-top:1px solid var(--hair)}.f3Result strong{display:block;font:750 19px ui-monospace,monospace;margin-top:3px}.f3Good{color:var(--green)!important}.f3Warn{color:var(--yellow)!important}.f3Bad{color:var(--red)!important}.f3Hidden{display:none!important}@media(max-width:620px){.f3Nodes,.f3Ranges{grid-template-columns:1fr}.f3Metrics{grid-template-columns:1fr 1fr}.f3TargetId{grid-template-columns:1fr}.f3Map{height:280px}}';
 document.head.appendChild(s);
}

function anchorHtml(id){
 return '<div class="f3Node"><div class="f3NodeHead"><span class="f3Badge f3'+id+'">'+id+'</span><span id="f3'+id+'State" class="muted">не готова</span></div>'+
 '<b id="f3'+id+'Pos">позиция —</b><small id="f3'+id+'Meta">пеленг —</small>'+
 '<div class="f3Actions"><button class="btn primary" data-f3-bearing="'+id+'">ПЕЛЕНГ</button><button class="btn" data-f3-gps="'+id+'">GPS</button><button class="btn" data-f3-place="'+id+'">НА КАРТЕ</button><button class="btn" data-f3-manual="'+id+'">КООРДИНАТЫ</button></div>'+
 '<div id="f3Manual'+id+'" class="f3Manual"><input id="f3Lat'+id+'" inputmode="decimal" placeholder="lat"><input id="f3Lon'+id+'" inputmode="decimal" placeholder="lon"><button class="btn" data-f3-apply="'+id+'">ПРИМЕНИТЬ</button></div></div>';
}

function targetHtml(){
 return '<div class="f3Node"><div class="f3NodeHead"><span class="f3Badge f3T">T</span><span id="f3TState" class="muted">ожидание</span></div>'+
 '<b id="f3TId">T-001</b><small id="f3TMeta">собственный SX1280 target</small>'+
 '<div class="f3Actions"><button id="f3UseTarget" class="btn primary">LOCK T</button><button id="f3Clear" class="btn">СБРОС</button></div></div>';
}

function mount(){
 const old=$('rfFusion')||$('rfLoc')||$('rfFusion3');if(old)old.remove();const host=$('bearing');if(!host)return;
 const card=document.createElement('article');card.id='rfFusion3';card.className='card section';
 card.innerHTML='<div class="f3Head"><div><div class="label">FUSION 3 · A + B + T</div><div class="muted">Три своих устройства. A/B — опорные станции, T — свой SX1280-маяк.</div></div><span class="f3Mode">OWN TARGET</span></div>'+
 '<div class="f3TargetId"><div><div class="label">TARGET ID</div><small class="muted">Одинаковый ID обязателен для пеленга и ranging.</small></div><input id="f3TargetId" value="T-001" placeholder="T-001"></div>'+
 '<div id="f3Map" class="f3Map"><div id="f3Tiles" class="f3Tiles"></div><svg id="f3Overlay" class="f3Overlay"></svg><div class="f3MapBar"><span id="f3MapState" class="f3MapState">СХЕМА</span><div class="f3MapCtl"><button id="f3Minus">−</button><button id="f3Auto">◎</button><button id="f3Plus">+</button></div></div><div id="f3Hint" class="f3Hint">Задай позиции A и B</div><div class="f3Attr">© OpenStreetMap contributors</div></div>'+
 '<div class="f3Nodes">'+anchorHtml('A')+anchorHtml('B')+targetHtml()+'</div>'+
 '<div class="f3Ranges">'+
 '<div class="f3Range"><div class="label">A↔B RANGE</div><input id="f3RangeAB" type="number" inputmode="decimal" min="0" step="0.1" placeholder="м"><small id="f3RangeABMeta">контроль базы</small></div>'+
 '<div class="f3Range"><div class="label">A↔T RANGE</div><input id="f3RangeAT" type="number" inputmode="decimal" min="0" step="0.1" placeholder="м"><small id="f3RangeATMeta">SX1280 / тест вручную</small></div>'+
 '<div class="f3Range"><div class="label">B↔T RANGE</div><input id="f3RangeBT" type="number" inputmode="decimal" min="0" step="0.1" placeholder="м"><small id="f3RangeBTMeta">SX1280 / тест вручную</small></div></div>'+
 '<div class="f3Metrics"><div class="f3Metric"><span>BASE A–B</span><b id="f3Base">—</b></div><div class="f3Metric"><span>SYNC Δt</span><b id="f3Sync">—</b></div><div class="f3Metric"><span>УГОЛ</span><b id="f3Angle">—</b></div><div class="f3Metric"><span>RANGE ERR</span><b id="f3RangeErr">—</b></div></div>'+
 '<div class="f3Result"><div class="head"><span class="label">ПОЗИЦИЯ T</span><button id="f3OpenTarget" class="btn f3Hidden">В КАРТЫ</button></div><strong id="f3Target">—</strong><small id="f3Quality">Нужны позиции A/B и измерения T</small></div>';
 const controls=host.querySelector('.controls.section');host.insertBefore(card,controls||null);bind();restore();render();
}

function bind(){
 $('f3TargetId').onchange=e=>{nodes.T.deviceId=(e.target.value||'').trim()||'T-001';clearMeasurements();persist();render();};
 document.querySelectorAll('[data-f3-bearing]').forEach(b=>b.onclick=()=>captureBearing(b.dataset.f3Bearing));
 document.querySelectorAll('[data-f3-gps]').forEach(b=>b.onclick=()=>gps(b.dataset.f3Gps));
 document.querySelectorAll('[data-f3-place]').forEach(b=>b.onclick=()=>beginPlace(b.dataset.f3Place));
 document.querySelectorAll('[data-f3-manual]').forEach(b=>b.onclick=()=>$('f3Manual'+b.dataset.f3Manual).classList.toggle('open'));
 document.querySelectorAll('[data-f3-apply]').forEach(b=>b.onclick=()=>manual(b.dataset.f3Apply));
 for(const k of ['AB','AT','BT'])$('f3Range'+k).onchange=e=>setRange(k,e.target.value,'MANUAL');
 $('f3UseTarget').onclick=()=>{nodes.T.online=true;nodes.T.lastSeen=Date.now();persist();render();};
 $('f3Clear').onclick=()=>{clearMeasurements();persist();render();};
 $('f3Minus').onclick=()=>{zoomDelta=Math.max(-5,zoomDelta-1);renderMap();};
 $('f3Plus').onclick=()=>{zoomDelta=Math.min(5,zoomDelta+1);renderMap();};
 $('f3Auto').onclick=()=>{zoomDelta=0;renderMap();};
 $('f3Map').onclick=mapClick;
 $('f3OpenTarget').onclick=()=>{if(target&&target.ok&&typeof AndroidLocation!=='undefined')AndroidLocation.openMap(target.lat,target.lon);};
}

function setRange(key,value,source){
 const v=n(value);ranges[key]=v&&v>0?v:null;rangeAt[key]=ranges[key]?Date.now():null;
 const m=$('f3Range'+key+'Meta');if(m)m.textContent=ranges[key]?(source+' · '+ranges[key].toFixed(1)+' м · сейчас'):(key==='AB'?'контроль базы':'SX1280 / тест вручную');
 persist();render();
}
window.onFusionRange=(o)=>{
 if(!o)return;const a=String(o.a||''),b=String(o.b||''),v=n(o.rangeM),targetId=String(o.targetId||'');
 if(targetId&&targetId!==nodes.T.deviceId)return;
 const key=(a+b==='AB'||a+b==='BA')?'AB':(a+b==='AT'||a+b==='TA')?'AT':(a+b==='BT'||a+b==='TB')?'BT':null;
 if(!key||!Number.isFinite(v)||v<=0)return;
 ranges[key]=v;rangeAt[key]=n(o.timeMs)||Date.now();nodes.T.online=true;nodes.T.lastSeen=rangeAt[key];persist();render();
};

function clearMeasurements(){
 for(const id of ['A','B']){nodes[id].bearing=null;nodes[id].bearingAt=null;nodes[id].rssi=null;}
 ranges.AT=ranges.BT=null;rangeAt.AT=rangeAt.BT=null;target=null;
}
function numFrom(id){const e=$(id),m=e?(e.textContent||'').match(/-?\d+(?:\.\d+)?/):null,v=m?Number(m[0]):NaN;return Number.isFinite(v)?v:null;}
function captureBearing(id){
 const b=numFrom('bestHeading');if(!Number.isFinite(b)){quality('Сначала получи устойчивый лучший пеленг','warn');return;}
 const s=nodes[id];s.bearing=((b%360)+360)%360;s.bearingAt=Date.now();s.rssi=numFrom('bestPass');nodes.T.online=true;nodes.T.lastSeen=Date.now();persist();render();
}

function gps(id){if(typeof AndroidLocation==='undefined'){quality('GPS доступен только в Android APK','warn');return;}pendingGps=id;quality('Получаю GPS для '+id+'…');try{AndroidLocation.requestFix();}catch(e){pendingGps=null;quality('GPS ошибка','warn');}}
window.onLocationFix=o=>{if(!pendingGps)return;const id=pendingGps;pendingGps=null;const lat=n(o.lat),lon=n(o.lon);if(!Number.isFinite(lat)||!Number.isFinite(lon)){quality('Некорректный GPS fix','warn');return;}Object.assign(nodes[id],{lat,lon,accuracyM:n(o.accuracyM),provider:o.cached?'GNSS cached':'GNSS'});zoomDelta=0;persist();render();};
window.onLocationError=m=>{pendingGps=null;quality(String(m||'GPS ошибка'),'warn');};
function manual(id){const lat=n($('f3Lat'+id).value),lon=n($('f3Lon'+id).value);if(!Number.isFinite(lat)||!Number.isFinite(lon)||Math.abs(lat)>90||Math.abs(lon)>180){quality('Проверь координаты '+id,'warn');return;}Object.assign(nodes[id],{lat,lon,accuracyM:null,provider:'MANUAL'});$('f3Manual'+id).classList.remove('open');zoomDelta=0;persist();render();}
function beginPlace(id){if(!mapView){quality('Сначала задай одну позицию GPS или координатами','warn');return;}placeId=id;quality('Тапни по карте: поставить '+id);renderMap();}
function mapClick(e){if(!placeId||!mapView)return;const r=$('f3Map').getBoundingClientRect(),wx=mapView.cx+(e.clientX-r.left-r.width/2),wy=mapView.cy+(e.clientY-r.top-r.height/2),p=invMerc(wx,wy,mapView.z);Object.assign(nodes[placeId],{lat:p.lat,lon:p.lon,accuracyM:null,provider:'MAP'});placeId=null;persist();render();}

function bearingSolve(a,b){
 if(!Number.isFinite(a.lat)||!Number.isFinite(a.lon)||!Number.isFinite(b.lat)||!Number.isFinite(b.lon)||!Number.isFinite(a.bearing)||!Number.isFinite(b.bearing))return null;
 const lat0=(a.lat+b.lat)/2,lon0=(a.lon+b.lon)/2,A=xy(a.lat,a.lon,lat0,lon0),B=xy(b.lat,b.lon,lat0,lon0);
 const ar=a.bearing*Math.PI/180,br=b.bearing*Math.PI/180,dA={x:Math.sin(ar),y:Math.cos(ar)},dB={x:Math.sin(br),y:Math.cos(br)},den=cross(dA.x,dA.y,dB.x,dB.y);
 if(Math.abs(den)<1e-4)return null;
 const qx=B.x-A.x,qy=B.y-A.y,tA=cross(qx,qy,dB.x,dB.y)/den,tB=cross(qx,qy,dA.x,dA.y)/den,p=ll(A.x+tA*dA.x,A.y+tA*dA.y,lat0,lon0);
 let ang=angleDiff(a.bearing,b.bearing);ang=Math.min(ang,180-ang);
 return{lat:p.lat,lon:p.lon,angle:ang,forward:tA>=0&&tB>=0,dAT:Math.abs(tA),dBT:Math.abs(tB),method:'BEARING'};
}

function rangeIntersections(a,b,rA,rB){
 if(!Number.isFinite(a.lat)||!Number.isFinite(b.lat)||!Number.isFinite(rA)||!Number.isFinite(rB))return[];
 const lat0=(a.lat+b.lat)/2,lon0=(a.lon+b.lon)/2,A=xy(a.lat,a.lon,lat0,lon0),B=xy(b.lat,b.lon,lat0,lon0),dx=B.x-A.x,dy=B.y-A.y,d=Math.hypot(dx,dy);
 if(d<=0||d>rA+rB||d<Math.abs(rA-rB))return[];
 const x=(rA*rA-rB*rB+d*d)/(2*d),h2=rA*rA-x*x;if(h2<0)return[];const h=Math.sqrt(Math.max(0,h2)),ux=dx/d,uy=dy/d,px=A.x+x*ux,py=A.y+x*uy,rx=-uy*h,ry=ux*h;
 return[ll(px+rx,py+ry,lat0,lon0),ll(px-rx,py-ry,lat0,lon0)].map(p=>({lat:p.lat,lon:p.lon,method:'RANGE'}));
}
function geoDistancePoint(p,s){const lat0=(p.lat+s.lat)/2*Math.PI/180,dx=(p.lon-s.lon)*Math.PI/180*EARTH*Math.cos(lat0),dy=(p.lat-s.lat)*Math.PI/180*EARTH;return Math.hypot(dx,dy);}
function solve(){
 const a=nodes.A,b=nodes.B,bs=bearingSolve(a,b),ri=rangeIntersections(a,b,ranges.AT,ranges.BT);
 let p=null,method='';
 if(bs&&bs.forward){p=bs;method='BEARING';}
 if(ri.length){
   if(p){ri.sort((x,y)=>geoDistancePoint(x,p)-geoDistancePoint(y,p));const rp=ri[0],sep=geoDistancePoint(rp,p);p={...p,lat:(p.lat+rp.lat)/2,lon:(p.lon+rp.lon)/2,rangeSeparation:sep};method='BEARING+RANGE';}
   else if(ri.length===1){p=ri[0];method='RANGE';}
   else return{ok:false,reason:'Две точки по дальностям — нужен хотя бы один пеленг',candidates:ri};
 }
 if(!p)return{ok:false,reason:'Нужны A/B: два пеленга или две дальности A↔T и B↔T'};
 const baseM=(Number.isFinite(a.lat)&&Number.isFinite(b.lat))?dist(a,b):null;
 const dt=Number.isFinite(a.bearingAt)&&Number.isFinite(b.bearingAt)?Math.abs(a.bearingAt-b.bearingAt):null;
 const predAT=geoDistancePoint(p,a),predBT=geoDistancePoint(p,b),errs=[];
 if(Number.isFinite(ranges.AT))errs.push(Math.abs(predAT-ranges.AT));
 if(Number.isFinite(ranges.BT))errs.push(Math.abs(predBT-ranges.BT));
 const rangeErr=errs.length?errs.reduce((x,y)=>x+y,0)/errs.length:null;
 const angle=bs?bs.angle:null;
 const good=(angle===null||angle>=30)&&(dt===null||dt<=5000)&&(rangeErr===null||rangeErr<=Math.max(3,.12*Math.max(ranges.AT||0,ranges.BT||0)));
 return{ok:true,lat:p.lat,lon:p.lon,method,baseM,dt,angle,rangeErr,predAT,predBT,good};
}

function renderAnchor(id){
 const s=nodes[id],pos=Number.isFinite(s.lat),br=Number.isFinite(s.bearing);
 $('f3'+id+'Pos').textContent=pos?coord(s.lat)+', '+coord(s.lon)+' · '+(s.provider||'position'):'позиция —';
 $('f3'+id+'Meta').textContent=br?'пеленг '+s.bearing.toFixed(1)+'° · RSSI '+(Number.isFinite(s.rssi)?s.rssi.toFixed(1):'—')+' · '+age(s.bearingAt):'пеленг —';
 $('f3'+id+'State').textContent=pos&&br?'готова':(pos||br?'частично':'не готова');
}
function quality(t,k){const e=$('f3Quality');if(!e)return;e.textContent=t;e.className=k==='good'?'f3Good':k==='bad'?'f3Bad':'f3Warn';}
function render(){
 $('f3TargetId').value=nodes.T.deviceId;$('f3TId').textContent=nodes.T.deviceId;
 $('f3TState').textContent=nodes.T.online?'online':'ожидание';$('f3TMeta').textContent='свой SX1280 · '+(nodes.T.lastSeen?'последний пакет '+age(nodes.T.lastSeen):'нет данных');
 renderAnchor('A');renderAnchor('B');
 for(const k of ['AB','AT','BT'])$('f3Range'+k).value=Number.isFinite(ranges[k])?ranges[k]:'';
 const baseM=Number.isFinite(nodes.A.lat)&&Number.isFinite(nodes.B.lat)?dist(nodes.A,nodes.B):null;
 $('f3Base').textContent=Number.isFinite(baseM)?baseM.toFixed(1)+' м':'—';
 $('f3RangeABMeta').textContent=Number.isFinite(ranges.AB)?'radio '+ranges.AB.toFixed(1)+' м · Δ '+(Number.isFinite(baseM)?(ranges.AB-baseM).toFixed(1)+' м':'—'):'контроль базы';
 const dt=Number.isFinite(nodes.A.bearingAt)&&Number.isFinite(nodes.B.bearingAt)?Math.abs(nodes.A.bearingAt-nodes.B.bearingAt):null;
 $('f3Sync').textContent=Number.isFinite(dt)?(dt<1000?dt+' ms':(dt/1000).toFixed(1)+' s'):'—';
 target=solve();$('f3Angle').textContent=target.ok&&Number.isFinite(target.angle)?target.angle.toFixed(1)+'°':'—';$('f3RangeErr').textContent=target.ok&&Number.isFinite(target.rangeErr)?target.rangeErr.toFixed(1)+' м':'—';
 $('f3OpenTarget').classList.toggle('f3Hidden',!target.ok);$('f3Target').textContent=target.ok?coord(target.lat)+', '+coord(target.lon):'—';
 if(!target.ok)quality(target.reason,'warn');else quality(target.method+' · '+(target.good?'геометрия нормальная':'проверь геометрию')+(Number.isFinite(target.rangeErr)?' · ошибка range '+target.rangeErr.toFixed(1)+' м':''),target.good?'good':'warn');
 persist();renderMap();
}
function persist(){try{localStorage.setItem(STORE,JSON.stringify({savedAt:Date.now(),nodes,ranges,rangeAt}));}catch(e){}}
function restore(){try{const x=JSON.parse(localStorage.getItem(STORE)||'{}');if(!x.savedAt||Date.now()-x.savedAt>24*3600*1000)return;if(x.nodes){nodes.A=Object.assign(newAnchor('A','#0A84FF'),x.nodes.A||{});nodes.B=Object.assign(newAnchor('B','#FFD60A'),x.nodes.B||{});nodes.T=Object.assign(nodes.T,x.nodes.T||{});}if(x.ranges)for(const k of ['AB','AT','BT'])ranges[k]=n(x.ranges[k]);if(x.rangeAt)rangeAt=Object.assign(rangeAt,x.rangeAt);}catch(e){}}

function merc(lat,lon,z){lat=Math.max(-85.0511,Math.min(85.0511,lat));const q=TILE*Math.pow(2,z),r=lat*Math.PI/180;return{x:(lon+180)/360*q,y:(1-Math.log(Math.tan(r)+1/Math.cos(r))/Math.PI)/2*q};}
function invMerc(x,y,z){const q=TILE*Math.pow(2,z),lon=x/q*360-180,t=Math.PI*(1-2*y/q);return{lat:180/Math.PI*Math.atan(Math.sinh(t)),lon};}
function mapItems(){const a=[];for(const id of ['A','B']){const s=nodes[id];if(Number.isFinite(s.lat)&&Number.isFinite(s.lon))a.push(s);}if(target&&target.ok)a.push({lat:target.lat,lon:target.lon});return a;}
function choose(items,w,h){if(!items.length)return null;let auto=17;if(items.length>1)for(let z=19;z>=2;z--){const p=items.map(x=>merc(x.lat,x.lon,z)),xs=p.map(x=>x.x),ys=p.map(x=>x.y);if(Math.max(...xs)-Math.min(...xs)<w-70&&Math.max(...ys)-Math.min(...ys)<h-70){auto=z;break;}}const z=Math.max(2,Math.min(19,auto+zoomDelta)),p=items.map(x=>merc(x.lat,x.lon,z)),xs=p.map(x=>x.x),ys=p.map(x=>x.y);return{z,cx:(Math.min(...xs)+Math.max(...xs))/2,cy:(Math.min(...ys)+Math.max(...ys))/2};}
function renderMap(){
 const map=$('f3Map'),tiles=$('f3Tiles'),svg=$('f3Overlay'),state=$('f3MapState'),hint=$('f3Hint'),r=map.getBoundingClientRect(),w=Math.max(10,Math.round(r.width)),h=Math.max(10,Math.round(r.height)),items=mapItems();mapEpoch++;const ep=mapEpoch;tiles.innerHTML='';svg.innerHTML='';svg.setAttribute('viewBox','0 0 '+w+' '+h);
 if(!items.length){mapView=null;state.textContent='СХЕМА · нет позиций';hint.textContent='Задай A через GPS/координаты';return;}
 mapView=choose(items,w,h);const z=mapView.z,cx=mapView.cx,cy=mapView.cy,N=Math.pow(2,z);let loaded=0,failed=0;state.textContent='OSM · z'+z;hint.textContent=placeId?'ТАП → поставить '+placeId:'A/B — якоря · T — расчёт';
 for(let tx=Math.floor((cx-w/2)/TILE);tx<=Math.floor((cx+w/2)/TILE);tx++)for(let ty=Math.floor((cy-h/2)/TILE);ty<=Math.floor((cy+h/2)/TILE);ty++){if(ty<0||ty>=N)continue;const img=document.createElement('img'),xx=((tx%N)+N)%N;img.src='https://tile.openstreetmap.org/'+z+'/'+xx+'/'+ty+'.png';img.alt='';img.style.left=(tx*TILE-cx+w/2)+'px';img.style.top=(ty*TILE-cy+h/2)+'px';img.onload=()=>{if(ep===mapEpoch){loaded++;state.textContent='OSM · z'+z;}};img.onerror=()=>{if(ep===mapEpoch){failed++;if(!loaded&&failed>2)state.textContent='СХЕМА · offline';}};tiles.appendChild(img);}
 const project=p=>{const q=merc(p.lat,p.lon,z);return{x:q.x-cx+w/2,y:q.y-cy+h/2}};let sh='',a=nodes.A,b=nodes.B;
 if(Number.isFinite(a.lat)&&Number.isFinite(b.lat)){const A=project(a),B=project(b),m={x:(A.x+B.x)/2,y:(A.y+B.y)/2};sh+='<line x1="'+A.x+'" y1="'+A.y+'" x2="'+B.x+'" y2="'+B.y+'" stroke="rgba(255,255,255,.5)" stroke-width="2" stroke-dasharray="7 6"/><text x="'+(m.x+7)+'" y="'+(m.y-7)+'" fill="#fff" font-size="13" font-weight="700" style="paint-order:stroke;stroke:#000;stroke-width:4px">'+Math.round(dist(a,b))+' м</text>';}
 for(const id of ['A','B']){const s=nodes[id];if(!Number.isFinite(s.lat))continue;const q=project(s),col=s.color;if(Number.isFinite(s.bearing)){const rr=s.bearing*Math.PI/180,L=Math.hypot(w,h)*2.2;sh+='<line x1="'+q.x+'" y1="'+q.y+'" x2="'+(q.x+Math.sin(rr)*L)+'" y2="'+(q.y-Math.cos(rr)*L)+'" stroke="'+col+'" stroke-width="3"/>';}sh+='<circle cx="'+q.x+'" cy="'+q.y+'" r="8" fill="'+col+'" stroke="#0B0B0C" stroke-width="3"/><text x="'+(q.x+12)+'" y="'+(q.y-11)+'" fill="#fff" font-size="13" font-weight="800" style="paint-order:stroke;stroke:#000;stroke-width:4px">'+id+(Number.isFinite(s.bearing)?' · '+Math.round(s.bearing)+'°':'')+'</text>';}
 if(target&&target.ok){const t=project(target);sh+='<circle cx="'+t.x+'" cy="'+t.y+'" r="10" fill="#30D158" stroke="#0B0B0C" stroke-width="3"/><text x="'+(t.x+14)+'" y="'+(t.y-12)+'" fill="#fff" font-size="13" font-weight="800" style="paint-order:stroke;stroke:#000;stroke-width:4px">T · '+nodes.T.deviceId+'</text>';}svg.innerHTML=sh;
}

css();mount();window.addEventListener('resize',()=>requestAnimationFrame(renderMap));
})();