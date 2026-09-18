(function(global){
'use strict';

function mulberry32(seed){return function(){let t=seed+=0x6D2B79F5;t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);return((t^t>>>14)>>>0)/4294967296;};}
function normal(rng){let u=0,v=0;while(!u)u=rng();while(!v)v=rng();return Math.sqrt(-2*Math.log(u))*Math.cos(2*Math.PI*v);}
function bearing(a,b){return((Math.atan2(b.x-a.x,b.y-a.y)*180/Math.PI)%360+360)%360;}
function distance(a,b){return Math.hypot(b.x-a.x,b.y-a.y);}
function localToLatLon(p,origin){const R=6371000,r=180/Math.PI;return{lat:origin.lat+p.y/R*r,lon:origin.lon+p.x/(R*Math.cos(origin.lat*Math.PI/180))*r};}
const PRESETS=Object.freeze({
  GOOD:{name:'GOOD',A:{x:0,y:0},B:{x:60,y:0},T:{x:30,y:85}},
  WIDE:{name:'WIDE',A:{x:-60,y:0},B:{x:60,y:0},T:{x:15,y:150}},
  BAD_GEOMETRY:{name:'BAD_GEOMETRY',A:{x:0,y:0},B:{x:20,y:0},T:{x:280,y:20}},
  CLOSE:{name:'CLOSE',A:{x:0,y:0},B:{x:25,y:0},T:{x:12,y:30}}
});
function generate(name,opts){
  opts=Object.assign({seed:1,bearingSigmaDeg:2.5,rangeSigmaM:.8,nlos:false,outlier:false,origin:{lat:0.01,lon:0.01},targetId:'T-001'},opts||{});
  const p=PRESETS[name]||PRESETS.GOOD,rng=mulberry32(Number(opts.seed)||1),M=global.RFFusionMeasurements;
  const ts=Date.now(),latA=localToLatLon(p.A,opts.origin),latB=localToLatLon(p.B,opts.origin),latT=localToLatLon(p.T,opts.origin);
  const ba=bearing(p.A,p.T)+normal(rng)*opts.bearingSigmaDeg,bb=bearing(p.B,p.T)+normal(rng)*opts.bearingSigmaDeg;
  let ra=distance(p.A,p.T)+normal(rng)*opts.rangeSigmaM,rb=distance(p.B,p.T)+normal(rng)*opts.rangeSigmaM,ab=distance(p.A,p.B)+normal(rng)*opts.rangeSigmaM*.5;
  let losA='LOS',losB='LOS',healthA='GOOD',healthB='GOOD';
  if(opts.nlos){rb+=8+Math.abs(normal(rng))*3;losB='NLOS';healthB='NLOS';}
  if(opts.outlier){ra+=20;healthA='SUSPECT';}
  return{
    preset:p.name,truth:{A:p.A,B:p.B,T:p.T,latLonT:latT},
    poses:{
      A:M?M.pose({deviceId:'A',targetId:opts.targetId,timestamp:ts,lat:latA.lat,lon:latA.lon,accuracyM:.5,provider:'SIM'}):latA,
      B:M?M.pose({deviceId:'B',targetId:opts.targetId,timestamp:ts,lat:latB.lat,lon:latB.lon,accuracyM:.5,provider:'SIM'}):latB
    },
    bearings:{
      A:M?M.bearing({deviceId:'A',targetId:opts.targetId,timestamp:ts,bearingDeg:ba,sigmaDeg:opts.bearingSigmaDeg,quality:healthA==='GOOD'?.95:.55}):ba,
      B:M?M.bearing({deviceId:'B',targetId:opts.targetId,timestamp:ts+35,bearingDeg:bb,sigmaDeg:opts.bearingSigmaDeg,quality:healthB==='GOOD'?.95:.25,health:healthB}):bb
    },
    ranges:{
      AB:M?M.range({deviceId:'A',peerId:'B',targetId:opts.targetId,timestamp:ts,rangeM:ab,sigmaM:opts.rangeSigmaM*.5,losState:'LOS'}):ab,
      AT:M?M.range({deviceId:'A',peerId:'T',targetId:opts.targetId,timestamp:ts+20,rangeM:ra,sigmaM:opts.rangeSigmaM,losState:losA,health:healthA}):ra,
      BT:M?M.range({deviceId:'B',peerId:'T',targetId:opts.targetId,timestamp:ts+40,rangeM:rb,sigmaM:opts.rangeSigmaM,losState:losB,health:healthB}):rb
    }
  };
}
global.RFFusionSim=Object.freeze({PRESETS,generate,bearing,distance,localToLatLon});
})(window);
