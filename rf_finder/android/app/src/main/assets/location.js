(()=>{'use strict';
if(window.__rfLocationLoaded)return;window.__rfLocationLoaded=true;
const $=id=>document.getElementById(id);
const STORE='rfFinder.location.v2',MAX_SESSION_MS=6*60*60*1000,TILE=256,EARTH=6371000;
let points={A:null,B:null},pendingPoint=null,targetResult=null,manualZoom=0,mapEpoch=0;

function style(){
 const old=$('rf-location-style');if(old)old.remove();
 const s=document.createElement('style');s.id='rf-location-style';s.textContent=`
 #rfLoc{margin-top:14px}.rfLocSub{font-size:13px}.rfMap{position:relative;height:292px;overflow:hidden;border:1px solid var(--hair);border-radius:16px;background:#0A0D10;background-image:linear-gradient(rgba(255,255,255,.025) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.025) 1px,transparent 1px);background-size:32px 32px}.rfMapTiles,.rfMapOverlay{position:absolute;inset:0;width:100%;height:100%}.rfMapTiles img{position:absolute;width:256px;height:256px;filter:grayscale(.25) brightness(.58) contrast(1.08);user-select:none;-webkit-user-drag:none}.rfMapOverlay{pointer-events:none}.rfMapBar{position:absolute;left:8px;right:8px;top:8px;display:flex;justify-content:space-between;align-items:flex-start;gap:8px;pointer-events:none}.rfMapMode{padding:5px 8px;border:1px solid rgba(255,255,255,.14);border-radius:9px;background:rgba(11,11,12,.82);font-size:12px;color:#D3D6DC;backdrop-filter:blur(8px)}.rfMapControls{display:flex;gap:6px;pointer-events:auto}.rfMapControls button{width:42px;height:42px;border-radius:11px;border:1px solid rgba(255,255,255,.18);background:rgba(17,19,22,.90);font-weight:800}.rfMapAttr{position:absolute;right:7px;bottom:5px;padding:2px 5px;border-radius:6px;background:rgba(0,0,0,.58);font-size:10px;color:#D7D7DC}.rfLocRows{margin-top:10px;border-top:1px solid var(--hair)}.rfLocRow{display:grid;grid-template-columns:34px 1fr;gap:10px;align-items:center;padding:10px 0;border-bottom:1px solid var(--hair)}.rfLocBadge{width:30px;height:30px;border-radius:9px;display:grid;place-items:center;background:#1A1D22;border:1px solid var(--hair2);font-weight:800}.rfLocRow b{display:block;font:700 14px ui-monospace,monospace}.rfLocRow small{display:block;color:var(--muted);margin-top:2px;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.rfLocActions{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px;margin-top:10px}.rfLocActions button{min-height:48px}.rfLocTarget{margin-top:10px;padding-top:10px;border-top:1px solid var(--hair)}.rfLocTargetHead{display:flex;justify-content:space-between;align-items:center;gap:8px}.rfLocTarget strong{display:block;font:750 19px ui-monospace,monospace;margin-top:3px;word-break:break-word}.rfLocTarget small{display:block;color:var(--muted);margin-top:4px}.rfLocWarn{color:var(--yellow)!important}.rfLocGood{color:var(--green)!important}.rfLocHidden{display:none!important}@media(max-width:620px){.rfMap{height:255px}.rfLocActions{grid-template-columns:1fr auto}}
 `;document.head.appendChild(s);
}
function mount(){
 const old=$('rfLoc');if(old)old.remove();
 const bearing=$('bearing');if(!bearing)return;
 const host=document.createElement('article');host.id='rfLoc';host.className='card section';host.innerHTML=`
 <div class="head"><div><div class="label">ЛОКАЦИЯ</div><div class="muted rfLocSub">A/B · пассивная триангуляция · карта north-up</div></div></div>
 <div id="rfMap" class="rfMap" aria-label="Карта пеленгов">
  <div id="rfMapTiles" class="rfMapTiles"></div><svg id="rfMapOverlay" class="rfMapOverlay"></svg>
  <div class="rfMapBar"><span id="rfMapMode" class="rfMapMode">СХЕМА · жду A</span><div class="rfMapControls"><button id="rfMapMinus" aria-label="Уменьшить">−</button><button id="rfMapAuto" aria-label="Автомасштаб">◎</button><button id="rfMapPlus" aria-label="Увеличить">+</button></div></div>
  <div class="rfMapAttr">© OpenStreetMap contributors</div>
 </div>
 <div class="rfLocRows">
  <div class="rfLocRow"><span class="rfLocBadge">A</span><div><b id="rfLocA">—</b><small id="rfLocAMeta">не записана</small></div></div>
  <div class="rfLocRow"><span class="rfLocBadge">B</span><div><b id="rfLocB">—</b><small id="rfLocBMeta">не записана</small></div></div>
 </div>
 <div class="rfLocActions"><button id="rfLocCapture" class="btn primary">ЗАПИСАТЬ A</button><button id="rfLocClear" class="btn">Сброс</button></div>
 <div class="rfLocTarget"><div class="rfLocTargetHead"><span class="label">ОЦЕНКА ЦЕЛИ</span><button id="rfLocOpen" class="btn rfLocHidden">В КАРТЫ</button></div><strong id="rfLocTarget">—</strong><small id="rfLocQuality">Сначала запиши A, затем B</small></div>`;
 const controls=bearing.querySelector('.controls.section');bearing.insertBefore(host,controls||null);
 $('rfLocCapture').onclick=()=>capture(!points.A?'A':'B');
 const clear=()=>{points={A:null,B:null};pendingPoint=null;targetResult=null;manualZoom=0;persist();render();};
 $('rfLocClear').onclick=clear;
 $('rfMapMinus').onclick=()=>{manualZoom=Math.max(-5,manualZoom-1);renderMap();};
 $('rfMapPlus').onclick=()=>{manualZoom=Math.min(5,manualZoom+1);renderMap();};
 $('rfMapAuto').onclick=()=>{manualZoom=0;renderMap();};
 $('rfLocOpen').onclick=()=>{if(!targetResult||!targetResult.ok)return;try{AndroidLocation.openMap(targetResult.lat,targetResult.lon);}catch(e){status('Не удалось открыть внешнюю карту','warn');}};
 restore();render();
}
function parseDeg(id){const e=$(id);if(!e)return null;const m=(e.textContent||'').match(/(-?\d+(?:\.\d+)?)/);if(!m)return null;const v=Number(m[1]);return Number.isFinite(v)?((v%360)+360)%360:null;}
function currentBearing(){const best=parseDeg('bestHeading');return Number.isFinite(best)?best:null;}
function currentRssi(){const e=$('bestPass');if(!e)return null;const m=(e.textContent||'').match(/-?\d+(?:\.\d+)?/);const v=m?Number(m[0]):NaN;return Number.isFinite(v)?v:null;}
function currentSource(){
 const log=$('log');if(log){const lines=(log.textContent||'').split(/\n/).reverse();for(const line of lines){if(line.includes('E,ELRS,CONFIRMED')){const p=line.replace(/^<\s*/,'').trim().split(',');const uid=p.length>=9?p[8].trim():'';return uid?'ELRS '+uid:'ELRS CONFIRMED';}}}
 const er=$('elrsResult');if(er&&/ПОДТВЕРЖД|CONFIRMED/i.test(er.textContent||''))return (er.textContent||'').trim();
 const f=$('fixedText');return f?'RF '+(f.textContent||'').trim():'RF source';
}
function capture(name){
 const bearing=currentBearing();if(!Number.isFinite(bearing)){status('Сначала получи устойчивый лучший пеленг','warn');return;}
 if(typeof AndroidLocation==='undefined'){status('Геолокация доступна только в Android APK','warn');return;}
 pendingPoint={name,bearing,rssi:currentRssi(),source:currentSource(),takenAt:Date.now()};
 status('Получаю свежий GPS fix для точки '+name+'…');
 try{AndroidLocation.requestFix();}catch(e){pendingPoint=null;status('Ошибка GPS: '+e,'warn');}
}
window.onLocationFix=o=>{
 if(!pendingPoint)return;
 const lat=Number(o.lat),lon=Number(o.lon),timeMs=Number(o.timeMs),age=Number.isFinite(timeMs)?Date.now()-timeMs:0;
 if(!Number.isFinite(lat)||!Number.isFinite(lon)){pendingPoint=null;status('Некорректный GPS fix','warn');return;}
 if(o.cached&&Number.isFinite(age)&&age>120000){pendingPoint=null;status('GPS fix устарел ('+Math.round(age/1000)+' с). Нужна свежая позиция','warn');return;}
 const p={...pendingPoint,lat,lon,accuracyM:Number(o.accuracyM),altitudeM:Number(o.altitudeM),provider:o.provider||'',cached:!!o.cached,locationTimeMs:timeMs};
 points[pendingPoint.name]=p;if(pendingPoint.name==='A')points.B=null;pendingPoint=null;manualZoom=0;persist();render();
};
window.onLocationError=msg=>{pendingPoint=null;status(String(msg||'GPS ошибка'),'warn');};
function status(text,kind=''){const q=$('rfLocQuality');if(!q)return;q.textContent=text;q.className=kind==='warn'?'rfLocWarn':kind==='good'?'rfLocGood':'';}
function fmtCoord(v){return Number.isFinite(v)?v.toFixed(6):'—';}
function fmtAge(ms){const d=Math.max(0,Date.now()-ms);if(d<60000)return Math.round(d/1000)+' с назад';if(d<3600000)return Math.round(d/60000)+' мин назад';return Math.round(d/3600000)+' ч назад';}
function renderPoint(name,p){const main=$('rfLoc'+name),meta=$('rfLoc'+name+'Meta');if(!main||!meta)return;if(!p){main.textContent='—';meta.textContent='не записана';return;}main.textContent=`${fmtCoord(p.lat)}, ${fmtCoord(p.lon)} · ${p.bearing.toFixed(1)}°`;const acc=Number.isFinite(p.accuracyM)?`GPS ±${Math.round(p.accuracyM)} м`:'GPS ?';const r=Number.isFinite(p.rssi)?` · ${p.rssi.toFixed(1)} dBm`:'';meta.textContent=`${acc}${r} · ${p.source} · ${fmtAge(p.takenAt)}${p.cached?' · cached':''}`;}
function toXY(lat,lon,lat0,lon0){const rad=Math.PI/180;return{x:(lon-lon0)*rad*EARTH*Math.cos(lat0*rad),y:(lat-lat0)*rad*EARTH};}
function toLL(x,y,lat0,lon0){const rad=Math.PI/180;return{lat:lat0+y/EARTH/rad,lon:lon0+x/(EARTH*Math.cos(lat0*rad))/rad};}
function cross(ax,ay,bx,by){return ax*by-ay*bx;}
function elrsUid(src){const m=String(src||'').match(/^ELRS\s+([0-9A-Fa-f]{6})\b/);return m?m[1].toUpperCase():null;}
function triangulate(a,b){
 const ua=elrsUid(a.source),ub=elrsUid(b.source),ae=String(a.source||'').startsWith('ELRS'),be=String(b.source||'').startsWith('ELRS');if(ae||be){if(!ua||!ub)return{ok:false,reason:'Для A и B нужен один подтвержденный ELRS UID'};if(ua!==ub)return{ok:false,reason:'A и B относятся к разным ELRS UID'};}else if(String(a.source||'')!==String(b.source||''))return{ok:false,reason:'A и B измерены на разных RF-источниках'};
 const lat0=(a.lat+b.lat)/2,lon0=(a.lon+b.lon)/2,A=toXY(a.lat,a.lon,lat0,lon0),B=toXY(b.lat,b.lon,lat0,lon0);
 const ar=a.bearing*Math.PI/180,br=b.bearing*Math.PI/180,dA={x:Math.sin(ar),y:Math.cos(ar)},dB={x:Math.sin(br),y:Math.cos(br)};
 const den=cross(dA.x,dA.y,dB.x,dB.y);if(Math.abs(den)<1e-4)return{ok:false,reason:'Пеленги почти параллельны'};
 const qx=B.x-A.x,qy=B.y-A.y,tA=cross(qx,qy,dB.x,dB.y)/den,tB=cross(qx,qy,dA.x,dA.y)/den;
 const X={x:A.x+tA*dA.x,y:A.y+tA*dA.y},ll=toLL(X.x,X.y,lat0,lon0);
 let angle=Math.abs(((a.bearing-b.bearing+540)%360)-180);angle=Math.min(angle,180-angle);
 const baseline=Math.hypot(B.x-A.x,B.y-A.y),gps=Math.hypot(Number.isFinite(a.accuracyM)?a.accuracyM:0,Number.isFinite(b.accuracyM)?b.accuracyM:0);
 const forward=tA>=0&&tB>=0,range=Math.max(Math.abs(tA),Math.abs(tB)),geom=Math.max(.20,Math.sin(Math.max(1,angle)*Math.PI/180));
 const bearingSigmaDeg=8,dirErr=range*Math.tan(bearingSigmaDeg*Math.PI/180)/geom,rough=Math.max(gps,Math.hypot(gps,dirErr));
 const minBase=Math.max(20,2*((Number.isFinite(a.accuracyM)?a.accuracyM:5)+(Number.isFinite(b.accuracyM)?b.accuracyM:5)));
 return{ok:true,lat:ll.lat,lon:ll.lon,tA,tB,angle,baseline,rough,forward,minBase,range,bearingSigmaDeg};
}
function persist(){try{if(!points.A&&!points.B)localStorage.removeItem(STORE);else localStorage.setItem(STORE,JSON.stringify({savedAt:Date.now(),points}));}catch(e){}}
function restore(){try{const raw=localStorage.getItem(STORE);if(!raw)return;const s=JSON.parse(raw);if(!s||Date.now()-Number(s.savedAt)>MAX_SESSION_MS){localStorage.removeItem(STORE);return;}if(s.points)points={A:s.points.A||null,B:s.points.B||null};}catch(e){}}
function render(){
 renderPoint('A',points.A);renderPoint('B',points.B);const target=$('rfLocTarget'),open=$('rfLocOpen'),capture=$('rfLocCapture');if(capture)capture.textContent=!points.A?'ЗАПИСАТЬ A':!points.B?'ЗАПИСАТЬ B':'ОБНОВИТЬ B';
 targetResult=null;if(open)open.classList.add('rfLocHidden');
 if(!points.A||!points.B){target.textContent='—';status(!points.A?'Сначала запиши A':'A записана · отойди минимум на 30–100 м и запиши B');renderMap();return;}
 const r=triangulate(points.A,points.B);targetResult=r;if(!r.ok){target.textContent='—';status(r.reason,'warn');renderMap();return;}
 target.textContent=`${fmtCoord(r.lat)}, ${fmtCoord(r.lon)}`;if(open)open.classList.remove('rfLocHidden');
 const geom=r.angle<20?'плохая геометрия':r.angle<35?'слабая геометрия':'геометрия OK',base=r.baseline<r.minBase?'база мала':'база OK',dir=r.forward?'вперёд':'пересечение позади луча';
 const good=r.forward&&r.angle>=35&&r.baseline>=r.minBase;
 status(`база ${Math.round(r.baseline)} м · угол ${r.angle.toFixed(1)}° · ${base} · ${geom} · ${dir} · оценка ±${Math.round(r.rough)} м`,good?'good':'warn');renderMap();
}
function mercWorld(lat,lon,z){lat=Math.max(-85.05112878,Math.min(85.05112878,lat));const n=TILE*Math.pow(2,z),x=(lon+180)/360*n,rad=lat*Math.PI/180,y=(1-Math.log(Math.tan(rad)+1/Math.cos(rad))/Math.PI)/2*n;return{x,y};}
function mapItems(){const out=[];if(points.A)out.push({kind:'A',...points.A});if(points.B)out.push({kind:'B',...points.B});if(targetResult&&targetResult.ok&&targetResult.forward&&targetResult.range<50000)out.push({kind:'T',lat:targetResult.lat,lon:targetResult.lon,rough:targetResult.rough});return out;}
function chooseView(items,w,h){if(!items.length)return null;let auto=17;if(items.length>1){for(let z=19;z>=2;z--){const ps=items.map(p=>mercWorld(p.lat,p.lon,z)),xs=ps.map(p=>p.x),ys=ps.map(p=>p.y);if(Math.max(...xs)-Math.min(...xs)<=Math.max(80,w-72)&&Math.max(...ys)-Math.min(...ys)<=Math.max(80,h-72)){auto=z;break;}}}const z=Math.max(2,Math.min(19,auto+manualZoom)),ps=items.map(p=>mercWorld(p.lat,p.lon,z)),xs=ps.map(p=>p.x),ys=ps.map(p=>p.y);return{z,cx:(Math.min(...xs)+Math.max(...xs))/2,cy:(Math.min(...ys)+Math.max(...ys))/2};}
function renderMap(){
 const map=$('rfMap'),tiles=$('rfMapTiles'),svg=$('rfMapOverlay'),mode=$('rfMapMode');if(!map||!tiles||!svg)return;const rect=map.getBoundingClientRect(),w=Math.max(10,Math.round(rect.width)),h=Math.max(10,Math.round(rect.height)),items=mapItems();mapEpoch++;const epoch=mapEpoch;tiles.innerHTML='';svg.innerHTML='';svg.setAttribute('viewBox',`0 0 ${w} ${h}`);
 if(!items.length){mode.textContent='СХЕМА · жду A';return;}const view=chooseView(items,w,h);if(!view)return;const {z,cx,cy}=view,n=Math.pow(2,z);let loaded=0,failed=0;mode.textContent='OSM · z'+z;
 const minTx=Math.floor((cx-w/2)/TILE),maxTx=Math.floor((cx+w/2)/TILE),minTy=Math.floor((cy-h/2)/TILE),maxTy=Math.floor((cy+h/2)/TILE);
 for(let tx=minTx;tx<=maxTx;tx++)for(let ty=minTy;ty<=maxTy;ty++){if(ty<0||ty>=n)continue;const img=document.createElement('img'),wrapX=((tx%n)+n)%n;img.alt='';img.src=`https://tile.openstreetmap.org/${z}/${wrapX}/${ty}.png`;img.style.left=(tx*TILE-cx+w/2)+'px';img.style.top=(ty*TILE-cy+h/2)+'px';img.onload=()=>{if(epoch===mapEpoch){loaded++;mode.textContent='OSM · z'+z;}};img.onerror=()=>{if(epoch===mapEpoch){failed++;if(!loaded&&failed>2)mode.textContent='СХЕМА · offline';}};tiles.appendChild(img);}
 const project=p=>{const q=mercWorld(p.lat,p.lon,z);return{x:q.x-cx+w/2,y:q.y-cy+h/2}};const centerLat=items.reduce((s,p)=>s+p.lat,0)/items.length,mpp=156543.03392*Math.cos(centerLat*Math.PI/180)/Math.pow(2,z);let shapes='';
 if(points.A&&points.B){const a=project(points.A),b=project(points.B);shapes+=`<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="rgba(255,255,255,.42)" stroke-width="2" stroke-dasharray="7 6"/>`;}
 for(const p of [points.A,points.B].filter(Boolean)){const q=project(p),isA=p===points.A,stroke=isA?'#0A84FF':'#FFD60A',acc=Number.isFinite(p.accuracyM)?Math.max(4,Math.min(80,p.accuracyM/mpp)):0,rad=p.bearing*Math.PI/180,dx=Math.sin(rad),dy=-Math.cos(rad),L=Math.hypot(w,h)*2.2;shapes+=acc?`<circle cx="${q.x}" cy="${q.y}" r="${acc}" fill="none" stroke="${stroke}" stroke-opacity=".35" stroke-width="1.5"/>`:'';shapes+=`<line x1="${q.x}" y1="${q.y}" x2="${q.x+dx*L}" y2="${q.y+dy*L}" stroke="${stroke}" stroke-width="3" stroke-opacity=".92"/><circle cx="${q.x}" cy="${q.y}" r="7" fill="${stroke}" stroke="#0B0B0C" stroke-width="3"/><text x="${q.x+11}" y="${q.y-10}" fill="#fff" font-size="13" font-weight="800" style="paint-order:stroke;stroke:#000;stroke-width:4px">${isA?'A':'B'} · ${Math.round(p.bearing)}°</text>`;}
 if(targetResult&&targetResult.ok&&targetResult.forward&&targetResult.range<50000){const t=project({lat:targetResult.lat,lon:targetResult.lon}),rr=Math.max(7,Math.min(120,targetResult.rough/mpp));shapes+=`<circle cx="${t.x}" cy="${t.y}" r="${rr}" fill="#30D158" fill-opacity=".10" stroke="#30D158" stroke-opacity=".75" stroke-width="2"/><circle cx="${t.x}" cy="${t.y}" r="8" fill="#30D158" stroke="#0B0B0C" stroke-width="3"/><path d="M ${t.x-13} ${t.y} H ${t.x+13} M ${t.x} ${t.y-13} V ${t.y+13}" stroke="#fff" stroke-width="2"/><text x="${t.x+12}" y="${t.y-12}" fill="#fff" font-size="13" font-weight="800" style="paint-order:stroke;stroke:#000;stroke-width:4px">ЦЕЛЬ</text>`;}
 svg.innerHTML=shapes;
}
style();mount();setTimeout(()=>{if(!$('rfLoc'))mount();},600);window.addEventListener('resize',()=>requestAnimationFrame(renderMap));
})();
