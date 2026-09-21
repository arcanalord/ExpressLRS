import { WebSocketServer } from 'ws';

const port = Number(process.env.PORT || 8787);
const wss = new WebSocketServer({ port });
const rooms = new Map();

function roomKey(msg){ return String(msg.roomId||'') + ':' + String(msg.roomKey||''); }
function send(ws, value){ if(ws.readyState===ws.OPEN) ws.send(JSON.stringify(value)); }
function peers(room){ return rooms.get(room) || new Set(); }

wss.on('connection', ws => {
  ws.meta = { room:'', peerId:'', displayName:'' };

  ws.on('message', raw => {
    let msg; try { msg = JSON.parse(String(raw)); } catch { return send(ws,{type:'error',message:'BAD_JSON'}); }

    if(msg.type === 'hello'){
      if(!msg.roomId || !msg.roomKey || !msg.peerId) return send(ws,{type:'error',message:'BAD_HELLO'});
      const room = roomKey(msg);
      ws.meta = { room, peerId:String(msg.peerId), displayName:String(msg.displayName||msg.peerId) };
      if(!rooms.has(room)) rooms.set(room,new Set());
      rooms.get(room).add(ws);

      for(const other of peers(room)){
        if(other===ws) continue;
        send(other,{type:'peer',peerId:ws.meta.peerId,displayName:ws.meta.displayName});
        send(ws,{type:'peer',peerId:other.meta.peerId,displayName:other.meta.displayName});
      }
      return;
    }

    const room = ws.meta.room;
    if(!room || !peers(room).has(ws)) return send(ws,{type:'error',message:'NOT_JOINED'});
    if(msg.roomId && msg.roomKey && roomKey(msg)!==room) return send(ws,{type:'error',message:'ROOM_MISMATCH'});
    if(!['envelope','ack'].includes(msg.type)) return;

    for(const other of peers(room)){
      if(other===ws) continue;
      if(msg.to && other.meta.peerId!==msg.to) continue;
      send(other,{...msg,from:ws.meta.peerId});
    }
  });

  ws.on('close',()=>{
    const room=ws.meta.room;
    if(!room) return;
    const set=rooms.get(room); if(!set)return;
    set.delete(ws); if(!set.size) rooms.delete(room);
  });
});

console.log('mesh-wifi-relay listening on',port);
