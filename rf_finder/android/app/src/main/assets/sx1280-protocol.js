(function(global){
'use strict';

const VERSION=1;
const PREFIX='F3';
const ROLE=Object.freeze({COORDINATOR:'COORDINATOR',ANCHOR:'ANCHOR',TARGET:'TARGET',UNKNOWN:'UNKNOWN'});
const NODE_STATE=Object.freeze({OFFLINE:'OFFLINE',IDLE:'IDLE',READY:'READY',RANGING:'RANGING',ERROR:'ERROR'});

function num(v,f=null){const n=Number(v);return Number.isFinite(n)?n:f;}
function int(v,f=null){const n=parseInt(v,10);return Number.isFinite(n)?n:f;}
function text(v){return String(v==null?'':v).trim();}
function splitCaps(s){return text(s).split('|').map(x=>x.trim()).filter(Boolean);}
function validNode(id){return /^[A-Za-z0-9_.:-]{1,32}$/.test(text(id));}

function parseLine(line){
  const raw=text(line); if(!raw.startsWith(PREFIX+',')) return null;
  const p=raw.split(','); if(p[0]!==PREFIX||p.length<2)return null;
  const type=text(p[1]).toUpperCase();

  if(type==='HELLO'){
    if(p.length<8)return{ok:false,type,error:'HELLO_FIELDS',raw};
    const version=int(p[2]),deviceId=text(p[3]),role=text(p[4]).toUpperCase(),fw=text(p[5]),sessionId=text(p[6]),caps=splitCaps(p[7]);
    if(version!==VERSION)return{ok:false,type,error:'PROTOCOL_VERSION',version,raw};
    if(!validNode(deviceId))return{ok:false,type,error:'DEVICE_ID',raw};
    return{ok:true,type,version,deviceId,role:ROLE[role]||ROLE.UNKNOWN,fw,sessionId,caps,raw};
  }

  if(type==='STATE'){
    if(p.length<9)return{ok:false,type,error:'STATE_FIELDS',raw};
    const deviceId=text(p[2]),sessionId=text(p[3]),sequence=int(p[4]),timestamp=int(p[5]),state=text(p[6]).toUpperCase(),targetId=text(p[7]),batteryMv=int(p[8]),rssiDbm=num(p[9]);
    if(!validNode(deviceId))return{ok:false,type,error:'DEVICE_ID',raw};
    return{ok:true,type,deviceId,sessionId,sequence,timestamp,state:NODE_STATE[state]||state,targetId,batteryMv,rssiDbm,raw};
  }

  if(type==='RANGE'){
    if(p.length<17)return{ok:false,type,error:'RANGE_FIELDS',raw};
    const sessionId=text(p[2]),sequence=int(p[3]),from=text(p[4]),to=text(p[5]),targetId=text(p[6]),timestamp=int(p[7]),
      rawMm=int(p[8]),rangeMm=int(p[9]),sigmaMm=int(p[10]),qualityMilli=int(p[11]),rssiDbm=num(p[12]),txPowerDbm=num(p[13]),
      losState=text(p[14]).toUpperCase(),calibrationId=text(p[15]),flags=text(p[16]);
    if(!validNode(from)||!validNode(to))return{ok:false,type,error:'NODE_ID',raw};
    if(!(rangeMm>0))return{ok:false,type,error:'RANGE_VALUE',raw};
    return{ok:true,type,sessionId,sequence,from,to,targetId,timestamp,
      rangeRawM:rawMm>0?rawMm/1000:null,rangeM:rangeMm/1000,sigmaM:Math.max(.001,(sigmaMm>0?sigmaMm:1500)/1000),
      quality:Math.max(0,Math.min(1,(qualityMilli==null?1000:qualityMilli)/1000)),rssiDbm,txPowerDbm,
      losState:losState||'UNKNOWN',calibrationId:calibrationId||null,flags:splitCaps(flags),raw};
  }

  if(type==='BEARING'){
    if(p.length<13)return{ok:false,type,error:'BEARING_FIELDS',raw};
    const sessionId=text(p[2]),sequence=int(p[3]),from=text(p[4]),targetId=text(p[5]),timestamp=int(p[6]),
      bearingMilli=int(p[7]),sigmaMilli=int(p[8]),qualityMilli=int(p[9]),rssiDbm=num(p[10]),calibrationId=text(p[11]),flags=text(p[12]);
    if(!validNode(from))return{ok:false,type,error:'NODE_ID',raw};
    if(bearingMilli==null)return{ok:false,type,error:'BEARING_VALUE',raw};
    return{ok:true,type,sessionId,sequence,from,targetId,timestamp,bearingDeg:((bearingMilli/1000)%360+360)%360,
      sigmaDeg:Math.max(.001,(sigmaMilli>0?sigmaMilli:8000)/1000),quality:Math.max(0,Math.min(1,(qualityMilli==null?1000:qualityMilli)/1000)),
      rssiDbm,calibrationId:calibrationId||null,flags:splitCaps(flags),raw};
  }

  if(type==='ACK'){
    return{ok:true,type,command:text(p[2]),sequence:int(p[3]),status:text(p[4]),detail:p.slice(5).join(','),raw};
  }

  if(type==='ERR'){
    return{ok:false,type,code:text(p[2]),sequence:int(p[3]),detail:p.slice(4).join(','),raw};
  }

  return{ok:false,type,error:'UNKNOWN_TYPE',raw};
}

function lineHello(o){
  return[PREFIX,'HELLO',VERSION,text(o.deviceId),text(o.role||ROLE.UNKNOWN),text(o.fw||'0'),text(o.sessionId||'-'),(o.caps||[]).join('|')].join(',');
}
function lineState(o){
  return[PREFIX,'STATE',text(o.deviceId),text(o.sessionId||'-'),int(o.sequence,0),int(o.timestamp,Date.now()),text(o.state||NODE_STATE.IDLE),text(o.targetId||'-'),int(o.batteryMv,0),num(o.rssiDbm,'')].join(',');
}
function lineRange(o){
  return[PREFIX,'RANGE',text(o.sessionId||'-'),int(o.sequence,0),text(o.from),text(o.to),text(o.targetId||'-'),int(o.timestamp,Date.now()),
    Math.round(num(o.rangeRawM,o.rangeM)*1000),Math.round(num(o.rangeM,0)*1000),Math.round(num(o.sigmaM,1.5)*1000),Math.round(num(o.quality,1)*1000),
    num(o.rssiDbm,''),num(o.txPowerDbm,''),text(o.losState||'UNKNOWN'),text(o.calibrationId||'-'),(o.flags||[]).join('|')].join(',');
}
function lineBearing(o){
  return[PREFIX,'BEARING',text(o.sessionId||'-'),int(o.sequence,0),text(o.from),text(o.targetId||'-'),int(o.timestamp,Date.now()),
    Math.round(num(o.bearingDeg,0)*1000),Math.round(num(o.sigmaDeg,8)*1000),Math.round(num(o.quality,1)*1000),num(o.rssiDbm,''),text(o.calibrationId||'-'),(o.flags||[]).join('|')].join(',');
}
function commandHello(){return[PREFIX,'C','HELLO',VERSION].join(',');}
function commandSession(sessionId,targetId){return[PREFIX,'C','SESSION',text(sessionId),text(targetId)].join(',');}
function commandRange(from,to,count=1){return[PREFIX,'C','RANGE',text(from),text(to),Math.max(1,int(count,1))].join(',');}
function commandStop(){return[PREFIX,'C','STOP'].join(',');}
function commandCal(deviceId,calibrationId){return[PREFIX,'C','CAL',text(deviceId),text(calibrationId)].join(',');}

class Registry{
  constructor(){this.nodes=new Map();this.lastSequence=new Map();this.sessionId=null;this.targetId=null;}
  accept(msg){
    if(!msg||!msg.ok)return{accepted:false,reason:msg&&msg.error||'INVALID'};
    if(msg.sessionId&&msg.sessionId!=='-')this.sessionId=msg.sessionId;
    if(msg.targetId&&msg.targetId!=='-')this.targetId=msg.targetId;
    const deviceId=msg.deviceId||msg.from;
    if(deviceId){
      const n=this.nodes.get(deviceId)||{deviceId,role:ROLE.UNKNOWN,state:NODE_STATE.OFFLINE,lastSeen:0,caps:[]};
      if(msg.type==='HELLO'){n.role=msg.role;n.fw=msg.fw;n.caps=msg.caps;}
      if(msg.type==='STATE'){n.state=msg.state;n.batteryMv=msg.batteryMv;n.rssiDbm=msg.rssiDbm;}
      n.lastSeen=Date.now();this.nodes.set(deviceId,n);
    }
    if(Number.isFinite(msg.sequence)&&deviceId){
      const key=(msg.sessionId||'-')+'|'+deviceId+'|'+msg.type,prev=this.lastSequence.get(key);
      if(prev!=null&&msg.sequence<=prev)return{accepted:false,reason:'DUPLICATE_OR_OLD',message:msg};
      this.lastSequence.set(key,msg.sequence);
    }
    return{accepted:true,message:msg};
  }
  snapshot(){return{sessionId:this.sessionId,targetId:this.targetId,nodes:Array.from(this.nodes.values())};}
}

global.RFFusionProtocol=Object.freeze({VERSION,PREFIX,ROLE,NODE_STATE,parseLine,lineHello,lineState,lineRange,lineBearing,commandHello,commandSession,commandRange,commandStop,commandCal,Registry});
})(typeof window!=='undefined'?window:globalThis);
