(()=>{'use strict';
if(window.__rfLocationLoaded)return;window.__rfLocationLoaded=true;
const $=id=>document.getElementById(id);
let points={A:null,B:null},pendingPoint=null,lastFix=null;

function style(){
 const s=document.createElement('style');s.id='rf-location-style';s.textContent=`
 #rfLoc{margin-top:14px}.rfLocGrid{display:grid;grid-template-columns:1fr 1fr;gap:10px}.rfLocPoint{border:1px solid var(--hair);border-radius:14px;padding:10px;background:#0E1013}.rfLocPoint b{display:block;margin-top:4px;font:700 15px ui-monospace,monospace}.rfLocPoint small{display:block;color:var(--muted);margin-top:3px}.rfLocActions{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}.rfLocActions button{min-height:46px}.rfLocTarget{margin-top:10px;padding-top:10px;border-top:1px solid var(--hair)}.rfLocTarget strong{display:block;font:750 20px ui-monospace,monospace}.rfLocTarget small{display:block;color:var(--muted);margin-top:4px}.rfLocWarn{color:var(--yellow)!important}.rfLocGood{color:var(--green)!important}@media(max-width:620px){.rfLocGrid,.rfLocActions{grid-template-columns:1fr}}
 `;document.head.appendChild(s);
}
function mount(){
 if($('rfLoc'))return;
 const bearing=$('bearing'); if(!bearing)return;
 const host=document.createElement('article');host.id='rfLoc';host.className='card section';host.innerHTML=`
 <div class="head"><div><div class="label">ЛОКАЦИЯ</div><div class="muted">A/B · пассивная триангуляция по пеленгам</div></div><button id="rfLocReset" class="btn">Сбросить</button></div>
 <div class="rfLocGrid">
  <div class="rfLocPoint"><span class="label">ТОЧКА A</span><b id="rfLocA">—</b><small id="rfLocAMeta">не записана</small></div>
  <div class="rfLocPoint"><span class="label">ТОЧКА B</span><b id="rfLocB">—</b><small id="rfLocBMeta">не записана</small></div>
 </div>
 <div class="rfLocActions"><button id="rfLocTakeA" class="btn primary">ЗАПИСАТЬ A</button><button id="rfLocTakeB" class="btn primary">ЗАПИСАТЬ B</button></div>
 <div class="rfLocTarget"><span class="label">ОЦЕНКА ЦЕЛИ</span><strong id="rfLocTarget">—</strong><small id="rfLocQuality">Нужны две точки с валидным пеленгом</small></div>`;
 bearing.appendChild(host);
 $('rfLocTakeA').onclick=()=>capture('A');$('rfLocTakeB').onclick=()=>capture('B');$('rfLocReset').onclick=()=>{points={A:null,B:null};pendingPoint=null;render();};render();
}
function parseDeg(id){const e=$(id);if(!e)return null;const m=(e.textContent||'').match(/(-?\d+(?:\.\d+)?)/);if(!m)return null;const v=Number(m[1]);return Number.isFinite(v)?((v%360)+360)%360:null;}
function currentBearing(){const best=parseDeg('bestHeading');if(Number.isFinite(best))return best;return null;}
function currentRssi(){const e=$('bestPass');if(!e)return null;const m=(e.textContent||'').match(/-?\d+(?:\.\d+)?/);const v=m?Number(m[0]):NaN;return Number.isFinite(v)?v:null;}
function currentSource(){
 const log=$('log');if(log){const lines=(log.textContent||'').split(/\n/).reverse();for(const line of lines){if(line.includes('E,ELRS,CONFIRMED')){const p=line.replace(/^<\s*/,'').trim().split(',');const uid=p.length>=9?p[8].trim():'';return uid?'ELRS '+uid:'ELRS CONFIRMED';}}}
 const er=$('elrsResult');if(er&&/ПОДТВЕРЖД|CONFIRMED/i.test(er.textContent||''))return (er.textContent||'').trim();
 const f=$('fixedText');return f?'RF '+(f.textContent||'').trim():'RF source';
}
function capture(name){
 const bearing=currentBearing();if(!Number.isFinite(bearing)){status('Сначала получи устойчивый пеленг','warn');return;}
 if(typeof AndroidLocation==='undefined'){status('Геолокация доступна только в Android APK','warn');return;}
 pendingPoint={name,bearing,rssi:currentRssi(),source:currentSource(),takenAt:Date.now()};
 status('Получаю GPS для точки '+name+'…');
 try{AndroidLocation.requestFix();}catch(e){pendingPoint=null;status('Ошибка GPS: '+e,'warn');}
}
window.onLocationFix=o=>{
 if(!pendingPoint)return;
 const lat=Number(o.lat),lon=Number(o.lon);if(!Number.isFinite(lat)||!Number.isFinite(lon)){status('Некорректный GPS fix','warn');return;}
 lastFix=o;points[pendingPoint.name]={...pendingPoint,lat,lon,accuracyM:Number(o.accuracyM),altitudeM:Number(o.altitudeM),provider:o.provider||'',cached:!!o.cached};pendingPoint=null;render();
};
window.onLocationError=msg=>{pendingPoint=null;status(String(msg||'GPS ошибка'),'warn');};
function status(text,kind=''){const q=$('rfLocQuality');if(!q)return;q.textContent=text;q.className=kind==='warn'?'rfLocWarn':kind==='good'?'rfLocGood':'';}
function fmtCoord(v){return Number.isFinite(v)?v.toFixed(6):'—';}
function renderPoint(name,p){const main=$('rfLoc'+name),meta=$('rfLoc'+name+'Meta');if(!main||!meta)return;if(!p){main.textContent='—';meta.textContent='не записана';return;}main.textContent=`${fmtCoord(p.lat)}, ${fmtCoord(p.lon)} · ${p.bearing.toFixed(1)}°`;const acc=Number.isFinite(p.accuracyM)?`GPS ±${Math.round(p.accuracyM)} м`:'GPS ?';const r=Number.isFinite(p.rssi)?` · ${p.rssi.toFixed(1)} dBm`:'';meta.textContent=`${acc}${r} · ${p.source}${p.cached?' · cached':''}`;}
function toXY(lat,lon,lat0,lon0){const R=6371000,rad=Math.PI/180;return{x:(lon-lon0)*rad*R*Math.cos(lat0*rad),y:(lat-lat0)*rad*R};}
function toLL(x,y,lat0,lon0){const R=6371000,rad=Math.PI/180;return{lat:lat0+y/R/rad,lon:lon0+x/(R*Math.cos(lat0*rad))/rad};}
function cross(ax,ay,bx,by){return ax*by-ay*bx;}
function triangulate(a,b){
 const lat0=(a.lat+b.lat)/2,lon0=(a.lon+b.lon)/2,A=toXY(a.lat,a.lon,lat0,lon0),B=toXY(b.lat,b.lon,lat0,lon0);
 const ar=a.bearing*Math.PI/180,br=b.bearing*Math.PI/180,dA={x:Math.sin(ar),y:Math.cos(ar)},dB={x:Math.sin(br),y:Math.cos(br)};
 const den=cross(dA.x,dA.y,dB.x,dB.y);if(Math.abs(den)<1e-4)return{ok:false,reason:'Пеленги почти параллельны'};
 const qx=B.x-A.x,qy=B.y-A.y,tA=cross(qx,qy,dB.x,dB.y)/den,tB=cross(qx,qy,dA.x,dA.y)/den;
 const X={x:A.x+tA*dA.x,y:A.y+tA*dA.y};const ll=toLL(X.x,X.y,lat0,lon0);
 let angle=Math.abs(((a.bearing-b.bearing+540)%360)-180);angle=Math.min(angle,180-angle);
 const baseline=Math.hypot(B.x-A.x,B.y-A.y);const gps=Math.max(Number.isFinite(a.accuracyM)?a.accuracyM:0,Number.isFinite(b.accuracyM)?b.accuracyM:0);
 const geom=Math.max(0.08,Math.sin(Math.max(1,angle)*Math.PI/180));const rough=Math.max(gps,baseline*.035/geom);
 return{ok:true,lat:ll.lat,lon:ll.lon,tA,tB,angle,baseline,rough,forward:tA>=0&&tB>=0};
}
function render(){
 renderPoint('A',points.A);renderPoint('B',points.B);const target=$('rfLocTarget');if(!target)return;
 if(!points.A||!points.B){target.textContent='—';status('Нужны две точки с валидным пеленгом');return;}
 if(points.A.source!==points.B.source&&points.A.source.startsWith('ELRS')&&points.B.source.startsWith('ELRS')){target.textContent='—';status('A и B относятся к разным ELRS source-lock','warn');return;}
 const r=triangulate(points.A,points.B);if(!r.ok){target.textContent='—';status(r.reason,'warn');return;}
 target.textContent=`${fmtCoord(r.lat)}, ${fmtCoord(r.lon)}`;
 const geom=r.angle<20?'плохая геометрия':r.angle<35?'слабая геометрия':'геометрия OK';const dir=r.forward?'лучи пересекаются впереди':'пересечение позади одного пеленга';
 status(`база ${Math.round(r.baseline)} м · угол ${r.angle.toFixed(1)}° · ${geom} · ${dir} · грубо ±${Math.round(r.rough)} м`,r.forward&&r.angle>=35?'good':'warn');
}
style();mount();setTimeout(mount,500);
})();
