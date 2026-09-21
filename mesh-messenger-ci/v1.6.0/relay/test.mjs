import assert from 'node:assert/strict';
import { WebSocketServer, WebSocket } from 'ws';

const wss = new WebSocketServer({ port: 0 });
await new Promise(r=>wss.once('listening',r));
const port=wss.address().port;
const rooms=new Map();
const send=(ws,v)=>ws.readyState===1&&ws.send(JSON.stringify(v));
const key=m=>m.roomId+':'+m.roomKey;
wss.on('connection',ws=>{
 ws.meta={room:'',peerId:''};
 ws.on('message',raw=>{
  const m=JSON.parse(String(raw));
  if(m.type==='hello'){
   const room=key(m);ws.meta={room,peerId:m.peerId};if(!rooms.has(room))rooms.set(room,new Set());rooms.get(room).add(ws);
   for(const o of rooms.get(room))if(o!==ws){send(o,{type:'peer',peerId:m.peerId});send(ws,{type:'peer',peerId:o.meta.peerId});}
   return;
  }
  for(const o of rooms.get(ws.meta.room)||[])if(o!==ws)send(o,{...m,from:ws.meta.peerId});
 });
});
const url='ws://127.0.0.1:'+port;
const a=new WebSocket(url),b=new WebSocket(url);
await Promise.all([new Promise(r=>a.once('open',r)),new Promise(r=>b.once('open',r))]);
a.send(JSON.stringify({type:'hello',roomId:'r',roomKey:'k',peerId:'a'}));
b.send(JSON.stringify({type:'hello',roomId:'r',roomKey:'k',peerId:'b'}));
await new Promise(r=>setTimeout(r,30));
const got=new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(new Error('timeout')),500);b.on('message',raw=>{const m=JSON.parse(String(raw));if(m.type==='envelope') {clearTimeout(t);resolve(m);}});});
a.send(JSON.stringify({type:'envelope',roomId:'r',roomKey:'k',to:'b',messageId:'m1',payload:{type:'text',text:'hello'}}));
const m=await got;
assert.equal(m.from,'a');
assert.equal(m.payload.text,'hello');
a.close();b.close();wss.close();
console.log('RELAY_TEST_PASS');
