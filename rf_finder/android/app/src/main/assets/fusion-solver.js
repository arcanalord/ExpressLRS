(function(global){
'use strict';

const EARTH=6371000;
const DEG=Math.PI/180;
const HEALTH_WEIGHT=Object.freeze({GOOD:1,SUSPECT:.22,NLOS:.05,STALE:0,REJECTED:0,UNKNOWN:.65});

function num(v,f=null){v=Number(v);return Number.isFinite(v)?v:f;}
function clamp(v,a,b){return Math.max(a,Math.min(b,v));}
function wrapRad(a){while(a>Math.PI)a-=2*Math.PI;while(a<-Math.PI)a+=2*Math.PI;return a;}
function midpoint(a,b){return{lat:(a.lat+b.lat)/2,lon:(a.lon+b.lon)/2};}
function toEnu(lat,lon,o){return{x:(lon-o.lon)*DEG*EARTH*Math.cos(o.lat*DEG),y:(lat-o.lat)*DEG*EARTH};}
function fromEnu(x,y,o){return{lat:o.lat+y/EARTH/DEG,lon:o.lon+x/(EARTH*Math.cos(o.lat*DEG))/DEG};}
function bearingRad(a,p){return Math.atan2(p.x-a.x,p.y-a.y);}
function distance(a,p){return Math.hypot(p.x-a.x,p.y-a.y);}
function angleBetweenBearings(a,b){let d=Math.abs((((a-b)+540)%360)-180);return Math.min(d,180-d);}
function healthWeight(h){return HEALTH_WEIGHT[String(h||'UNKNOWN')]??HEALTH_WEIGHT.UNKNOWN;}
function huber(z,k=2.5){z=Math.abs(z);return z<=k?1:k/z;}

function lineIntersection(a,b){
  if(!a||!b)return null;
  const ra=a.bearingDeg*DEG,rb=b.bearingDeg*DEG;
  const da={x:Math.sin(ra),y:Math.cos(ra)},db={x:Math.sin(rb),y:Math.cos(rb)};
  const den=da.x*db.y-da.y*db.x;if(Math.abs(den)<1e-6)return null;
  const qx=b.anchor.x-a.anchor.x,qy=b.anchor.y-a.anchor.y;
  const ta=(qx*db.y-qy*db.x)/den,tb=(qx*da.y-qy*da.x)/den;
  if(ta<0||tb<0)return null;
  return{x:a.anchor.x+ta*da.x,y:a.anchor.y+ta*da.y};
}
function rangeIntersections(a,b,ra,rb){
  const dx=b.x-a.x,dy=b.y-a.y,d=Math.hypot(dx,dy);
  if(!(d>0)||d>ra+rb||d<Math.abs(ra-rb))return[];
  const x=(ra*ra-rb*rb+d*d)/(2*d),h2=ra*ra-x*x;
  if(h2<0)return[];
  const h=Math.sqrt(Math.max(0,h2)),ux=dx/d,uy=dy/d,px=a.x+x*ux,py=a.y+x*uy;
  return[{x:px-uy*h,y:py+ux*h},{x:px+uy*h,y:py-ux*h}];
}
function initialGuess(anchors,bearings,ranges){
  const bb=bearings.length>=2?lineIntersection(bearings[0],bearings[1]):null;
  if(bb)return bb;
  const ar=ranges.find(r=>r.anchorId==='A'),br=ranges.find(r=>r.anchorId==='B');
  if(ar&&br){
    const xs=rangeIntersections(anchors.A,anchors.B,ar.rangeM,br.rangeM);
    if(xs.length===1)return xs[0];
    if(xs.length===2&&bearings.length){
      const b=bearings[0],v={x:Math.sin(b.bearingDeg*DEG),y:Math.cos(b.bearingDeg*DEG)};
      xs.sort((p,q)=>((q.x-b.anchor.x)*v.x+(q.y-b.anchor.y)*v.y)-((p.x-b.anchor.x)*v.x+(p.y-b.anchor.y)*v.y));
      return xs[0];
    }
    if(xs.length===2)return null;
  }
  if(bearings.length&&ranges.length){
    const b=bearings[0],r=ranges.find(x=>x.anchorId===b.anchorId)||ranges[0],d=r.rangeM;
    return{x:b.anchor.x+Math.sin(b.bearingDeg*DEG)*d,y:b.anchor.y+Math.cos(b.bearingDeg*DEG)*d};
  }
  if(bearings.length){
    const base=Math.max(20,Math.hypot(anchors.B.x-anchors.A.x,anchors.B.y-anchors.A.y)*1.5);
    const b=bearings[0];return{x:b.anchor.x+Math.sin(b.bearingDeg*DEG)*base,y:b.anchor.y+Math.cos(b.bearingDeg*DEG)*base};
  }
  return{x:(anchors.A.x+anchors.B.x)/2,y:(anchors.A.y+anchors.B.y)/2+Math.max(10,Math.hypot(anchors.B.x-anchors.A.x,anchors.B.y-anchors.A.y))};
}
function inv2(a,b,c){const d=a*c-b*b;if(Math.abs(d)<1e-12)return null;return{a:c/d,b:-b/d,c:a/d,det:d};}
function eigenCov(cxx,cxy,cyy){
  const tr=cxx+cyy,disc=Math.sqrt(Math.max(0,(cxx-cyy)*(cxx-cyy)+4*cxy*cxy));
  const l1=Math.max(0,(tr+disc)/2),l2=Math.max(0,(tr-disc)/2);
  const angle=.5*Math.atan2(2*cxy,cxx-cyy)/DEG;
  return{sigmaMajorM:Math.sqrt(l1),sigmaMinorM:Math.sqrt(l2),ellipseAngleDeg:angle,condition:l2>1e-12?l1/l2:Infinity};
}
function prep(input){
  const A=input&&input.anchors&&input.anchors.A,B=input&&input.anchors&&input.anchors.B;
  if(!A||!B||!Number.isFinite(A.lat)||!Number.isFinite(A.lon)||!Number.isFinite(B.lat)||!Number.isFinite(B.lon))return{error:'ANCHORS_MISSING'};
  const origin=midpoint(A,B),anchors={A:Object.assign(toEnu(A.lat,A.lon,origin),{accuracyM:Math.max(0,num(A.accuracyM,3))}),B:Object.assign(toEnu(B.lat,B.lon,origin),{accuracyM:Math.max(0,num(B.accuracyM,3))})};
  const now=num(input.now,Date.now()),maxAge=num(input.maxAgeMs,5000),targetId=input.targetId==null?null:String(input.targetId);
  const bearings=(input.bearings||[]).filter(m=>m&&m.valid!==false&&num(m.timestamp,now)>=now-maxAge&&(!targetId||!m.targetId||String(m.targetId)===targetId)).map(m=>{
    const id=String(m.anchorId||m.deviceId||'');if(!anchors[id])return null;
    return{m,anchorId:id,anchor:anchors[id],bearingDeg:((num(m.bearingDeg)%360)+360)%360,sigmaDeg:Math.max(.25,num(m.sigmaDeg,8)),quality:clamp(num(m.quality,1),.02,1),health:String(m.health||'GOOD')};
  }).filter(Boolean);
  const ranges=(input.ranges||[]).filter(m=>m&&m.valid!==false&&num(m.timestamp,now)>=now-maxAge&&(!targetId||!m.targetId||String(m.targetId)===targetId)).map(m=>{
    const d=String(m.deviceId||''),p=String(m.peerId||''),id=anchors[d]?d:anchors[p]?p:null;if(!id)return null;
    return{m,anchorId:id,anchor:anchors[id],rangeM:num(m.rangeM),sigmaM:Math.max(.05,num(m.sigmaM,1.5)),quality:clamp(num(m.quality,1),.02,1),health:String(m.health||m.losState||'GOOD')};
  }).filter(r=>r&&r.rangeM>0);
  return{origin,anchors,bearings,ranges,now,maxAge};
}
function solve(input){
  const p=prep(input);if(p.error)return{ok:false,reason:p.error};
  const {origin,anchors,bearings,ranges}=p;
  const rangeByAnchor=new Set(ranges.filter(r=>healthWeight(r.health)>0).map(r=>r.anchorId));
  if(!bearings.length&&rangeByAnchor.size===2){
    const ar=ranges.find(r=>r.anchorId==='A'),br=ranges.find(r=>r.anchorId==='B'),xs=rangeIntersections(anchors.A,anchors.B,ar.rangeM,br.rangeM);
    if(xs.length===2)return{ok:false,reason:'AMBIGUOUS_RANGE_ONLY',candidates:xs.map(q=>fromEnu(q.x,q.y,origin))};
  }
  if(bearings.length+ranges.length<2)return{ok:false,reason:'INSUFFICIENT_MEASUREMENTS'};
  let x=initialGuess(anchors,bearings,ranges);if(!x)return{ok:false,reason:'AMBIGUOUS_RANGE_ONLY'};
  let lastCost=Infinity,H={a:0,b:0,c:0},used=0,residuals=[];
  for(let iter=0;iter<20;iter++){
    let hxx=0,hxy=0,hyy=0,gx=0,gy=0,cost=0,count=0;residuals=[];
    for(const b of bearings){
      const dx=x.x-b.anchor.x,dy=x.y-b.anchor.y,d2=Math.max(1,dx*dx+dy*dy),d=Math.sqrt(d2);
      const pred=Math.atan2(dx,dy),obs=b.bearingDeg*DEG,res=wrapRad(pred-obs);
      const poseAng=Math.atan2(b.anchor.accuracyM,Math.max(1,d)),sigma=Math.sqrt(Math.pow(b.sigmaDeg*DEG,2)+poseAng*poseAng);
      const baseW=healthWeight(b.health)*b.quality/(sigma*sigma);if(!(baseW>0))continue;
      const z=res/sigma,rw=huber(z),w=baseW*rw,jx=dy/d2,jy=-dx/d2;
      hxx+=w*jx*jx;hxy+=w*jx*jy;hyy+=w*jy*jy;gx+=w*jx*res;gy+=w*jy*res;cost+=w*res*res;count++;
      residuals.push({kind:'BEARING',anchorId:b.anchorId,residualDeg:res/DEG,normalized:z,weight:w,health:b.health});
    }
    for(const r of ranges){
      const dx=x.x-r.anchor.x,dy=x.y-r.anchor.y,d=Math.max(.1,Math.hypot(dx,dy)),res=d-r.rangeM;
      const sigma=Math.sqrt(r.sigmaM*r.sigmaM+r.anchor.accuracyM*r.anchor.accuracyM),baseW=healthWeight(r.health)*r.quality/(sigma*sigma);if(!(baseW>0))continue;
      const z=res/sigma,rw=huber(z),w=baseW*rw,jx=dx/d,jy=dy/d;
      hxx+=w*jx*jx;hxy+=w*jx*jy;hyy+=w*jy*jy;gx+=w*jx*res;gy+=w*jy*res;cost+=w*res*res;count++;
      residuals.push({kind:'RANGE',anchorId:r.anchorId,residualM:res,normalized:z,weight:w,health:r.health});
    }
    used=count;if(count<2)return{ok:false,reason:'INSUFFICIENT_USABLE_MEASUREMENTS'};
    const damp=1e-6+.001*(hxx+hyy),I=inv2(hxx+damp,hxy,hyy+damp);if(!I)return{ok:false,reason:'POOR_GEOMETRY'};
    const dxStep=-(I.a*gx+I.b*gy),dyStep=-(I.b*gx+I.c*gy);
    if(!Number.isFinite(dxStep)||!Number.isFinite(dyStep))return{ok:false,reason:'SOLVER_DIVERGED'};
    x.x+=clamp(dxStep,-1000,1000);x.y+=clamp(dyStep,-1000,1000);
    H={a:hxx,b:hxy,c:hyy};
    if(Math.hypot(dxStep,dyStep)<.005||Math.abs(lastCost-cost)<1e-7){lastCost=cost;break;}
    lastCost=cost;
  }
  const I=inv2(H.a,H.b,H.c);if(!I)return{ok:false,reason:'POOR_GEOMETRY'};
  const eig=eigenCov(I.a,I.b,I.c),ll=fromEnu(x.x,x.y,origin),baseM=distance(anchors.A,anchors.B);
  const angle=bearings.length>=2?angleBetweenBearings(bearings[0].bearingDeg,bearings[1].bearingDeg):null;
  const rms=residuals.length?Math.sqrt(residuals.reduce((s,r)=>s+r.normalized*r.normalized,0)/residuals.length):null;
  let geometry='POOR';
  if(eig.condition<25&&eig.sigmaMajorM<10&&(angle===null||angle>=30))geometry='GOOD';
  else if(eig.condition<100&&eig.sigmaMajorM<30&&(angle===null||angle>=12))geometry='FAIR';
  const good=geometry!=='POOR'&&rms!==null&&rms<3;
  return{ok:true,lat:ll.lat,lon:ll.lon,x:x.x,y:x.y,origin,method:'WLS_ENU',usedMeasurements:used,residualRms:rms,baseM,angle,good,geometry,covariance:{xx:I.a,xy:I.b,yy:I.c},...eig,residuals};
}

global.RFFusionSolver=Object.freeze({solve,toEnu,fromEnu,rangeIntersections,HEALTH_WEIGHT});
})(typeof window!=='undefined'?window:globalThis);
