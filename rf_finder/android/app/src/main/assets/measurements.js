(function(global){
'use strict';

const HEALTH=Object.freeze({GOOD:'GOOD',SUSPECT:'SUSPECT',NLOS:'NLOS',STALE:'STALE',REJECTED:'REJECTED'});
let seq=0;

function finite(v){return Number.isFinite(Number(v));}
function num(v,fallback=null){const n=Number(v);return Number.isFinite(n)?n:fallback;}
function normalizeBearing(v){v=num(v);return v===null?null:((v%360)+360)%360;}
function id(kind,deviceId,timestamp){seq=(seq+1)%1000000;return kind+'-'+String(deviceId||'unknown')+'-'+String(timestamp||Date.now())+'-'+seq;}
function health(input){
  if(input&&input.rejected)return HEALTH.REJECTED;
  if(input&&input.nlos)return HEALTH.NLOS;
  const age=num(input&&input.ageMs,0),stale=num(input&&input.staleMs,5000);
  if(age>stale)return HEALTH.STALE;
  const q=num(input&&input.quality,1);
  if(q!==null&&q<0.45)return HEALTH.SUSPECT;
  return HEALTH.GOOD;
}
function common(kind,input){
  input=input||{};const ts=num(input.timestamp,Date.now());
  return{
    measurementId:input.measurementId||id(kind,input.deviceId,ts),
    kind,
    sessionId:String(input.sessionId||'fusion3'),
    deviceId:String(input.deviceId||'unknown'),
    targetId:input.targetId==null?null:String(input.targetId),
    sequence:num(input.sequence,seq),
    timestamp:ts,
    sourceTimestamp:num(input.sourceTimestamp,null),
    ageMs:num(input.ageMs,0),
    quality:Math.max(0,Math.min(1,num(input.quality,1))),
    health:input.health||health(input),
    valid:input.valid!==false,
    rejectReason:input.rejectReason||null,
    calibrationId:input.calibrationId||null,
    meta:Object.assign({},input.meta||{})
  };
}
function pose(input){
  const m=common('POSE',input),lat=num(input&&input.lat),lon=num(input&&input.lon),x=num(input&&input.x),y=num(input&&input.y);
  m.lat=lat;m.lon=lon;m.x=x;m.y=y;m.accuracyM=Math.max(0,num(input&&input.accuracyM,0));m.provider=(input&&input.provider)||'UNKNOWN';
  if(!((lat!==null&&lon!==null)||(x!==null&&y!==null))){m.valid=false;m.health=HEALTH.REJECTED;m.rejectReason='POSE_MISSING';}
  return m;
}
function bearing(input){
  const m=common('BEARING',input);m.bearingDeg=normalizeBearing(input&&input.bearingDeg);m.sigmaDeg=Math.max(.1,num(input&&input.sigmaDeg,8));m.rssiDbm=num(input&&input.rssiDbm);m.rotationRateDps=num(input&&input.rotationRateDps);m.antennaOffsetDeg=num(input&&input.antennaOffsetDeg,0);
  if(m.bearingDeg===null){m.valid=false;m.health=HEALTH.REJECTED;m.rejectReason='BEARING_MISSING';}
  return m;
}
function range(input){
  const m=common('RANGE',input);m.peerId=String((input&&input.peerId)||'unknown');m.rangeRawM=num(input&&input.rangeRawM);m.rangeM=num(input&&input.rangeM,m.rangeRawM);m.sigmaM=Math.max(.05,num(input&&input.sigmaM,1.5));m.rssiDbm=num(input&&input.rssiDbm);m.txPowerDbm=num(input&&input.txPowerDbm);m.losState=(input&&input.losState)||'UNKNOWN';
  if(!(m.rangeM>0)){m.valid=false;m.health=HEALTH.REJECTED;m.rejectReason='RANGE_INVALID';}
  if(m.losState==='NLOS'&&m.health===HEALTH.GOOD)m.health=HEALTH.NLOS;
  return m;
}
class Store{
  constructor(limit=1000){this.limit=limit;this.items=[];}
  add(m){if(!m||!m.kind)return null;this.items.push(m);if(this.items.length>this.limit)this.items.splice(0,this.items.length-this.limit);return m;}
  latest(kind,predicate){for(let i=this.items.length-1;i>=0;i--){const m=this.items[i];if(m.kind===kind&&(!predicate||predicate(m)))return m;}return null;}
  recent(kind,limit=50){return this.items.filter(x=>!kind||x.kind===kind).slice(-limit);}
  clear(predicate){this.items=predicate?this.items.filter(x=>!predicate(x)):[];}
  snapshot(){return this.items.slice();}
}
function weightFromSigma(sigma,min=.05){sigma=Math.max(min,num(sigma,1));return 1/(sigma*sigma);}
function isUsable(m,now=Date.now(),staleMs=5000){
  if(!m||!m.valid||m.health===HEALTH.REJECTED||m.health===HEALTH.NLOS)return false;
  return now-m.timestamp<=staleMs;
}

global.RFFusionMeasurements=Object.freeze({HEALTH,Store,pose,bearing,range,health,weightFromSigma,isUsable,normalizeBearing});
})(window);
