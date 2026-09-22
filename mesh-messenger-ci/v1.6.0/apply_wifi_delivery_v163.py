#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv)!=2:
    raise SystemExit("usage: apply_wifi_delivery_v163.py <source-root>")

root=Path(sys.argv[1]).resolve()
trees=[root]
android=root/"android-app"/"app"/"src"/"main"/"assets"/"www"
if android.exists():
    trees.append(android)

def patch_core(base):
    p=base/"src"/"core.js"
    s=p.read_text(encoding="utf-8")
    start=s.find("export class MessageQueue {")
    end=s.find("export class PositionTrackHistory",start)
    if start<0 or end<0:
        raise SystemExit("MessageQueue anchors missing under "+str(base))
    new=r"""export class MessageQueue {
  constructor({initialItems=[],onChange=()=>{}}={}) {
    this.items = Array.isArray(initialItems) ? initialItems.map(x=>({...x})) : [];
    this.onChange = typeof onChange === 'function' ? onChange : ()=>{};
  }
  _messageId(){
    if(globalThis.crypto?.randomUUID)return 'msg-'+crypto.randomUUID();
    return 'msg-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
  }
  _changed(){ try{this.onChange(this.list());}catch{} }
  setOnChange(fn){ this.onChange=typeof fn==='function'?fn:()=>{}; return this; }
  restore(items=[]){
    this.items=Array.isArray(items)?items.filter(x=>x&&x.id&&x.payload).map(x=>({
      ...x,
      messageId:x.messageId||this._messageId(),
      status:['ready','sending'].includes(x.status)?'queued':x.status
    })):[];
    this._changed();
    return this.list();
  }
  enqueue(payload, decision) {
    const item = {
      id: 'm-'+Date.now()+'-'+Math.random().toString(16).slice(2),
      messageId: this._messageId(),
      payload,
      transportId: decision.transport?.id || null,
      status: decision.transport ? 'ready' : 'queued',
      packetId: null,
      error: null,
      createdAt: new Date().toISOString()
    };
    this.items.push(item); this._changed();
    return {...item};
  }
  pendingCount() { return this.items.filter(x => x.status === 'queued').length; }
  inFlightCount() { return this.items.filter(x => ['ready','sending','sent'].includes(x.status)).length; }
  unsettledCount() { return this.items.filter(x => !['delivered','failed','sent-broadcast'].includes(x.status)).length; }
  get(id) { return this.items.find(x => x.id === id) || null; }
  byMessageId(messageId) { return this.items.find(x => x.messageId === messageId) || null; }
  byPacketId(packetId) { return this.items.find(x => x.packetId === (packetId >>> 0)) || null; }
  defer(id) { const item=this.get(id); if(item){item.status='queued';item.transportId=null;item.packetId=null;this._changed();} return item ? {...item} : null; }
  markSending(id,{packetId=null,transportId=null}={}) { const item=this.get(id); if(!item)return null; item.status='sending'; if(packetId!=null)item.packetId=packetId>>>0; if(transportId)item.transportId=transportId; this._changed(); return {...item}; }
  markSent(id,{broadcast=false}={}) { const item=this.get(id); if(!item)return null; item.status=broadcast?'sent-broadcast':'sent'; item.sentAt=new Date().toISOString(); this._changed(); return {...item}; }
  markDelivered(id) { const item=this.get(id); if(!item)return null; item.status='delivered'; item.deliveredAt=new Date().toISOString(); item.error=null; this._changed(); return {...item}; }
  markFailed(id,error) { const item=this.get(id); if(!item)return null; item.status='failed'; item.error=String(error||'unknown'); item.failedAt=new Date().toISOString(); this._changed(); return {...item}; }
  retry(id) { const item=this.get(id); if(!item)return null; item.status='queued'; item.transportId=null; item.packetId=null; item.error=null; delete item.failedAt; this._changed(); return {...item}; }
  flush(selectDecision) {
    const ready = [];
    for (const item of this.items) {
      if (item.status !== 'queued') continue;
      const decision = selectDecision(item.payload);
      if (!decision?.transport) continue;
      item.transportId = decision.transport.id;
      item.status = 'ready';
      ready.push({...item});
    }
    if(ready.length)this._changed();
    return ready;
  }
  list() { return this.items.map(x => ({...x})); }
}

"""
    p.write_text(s[:start]+new+s[end:],encoding="utf-8")

def patch_app(base):
    p=base/"src"/"app.js"
    s=p.read_text(encoding="utf-8")

    old="""function handleFastEnvelope(payload,meta={}){
  if(meta.system && payload?.type==='transport_ack'){
    const m=String(payload.messageId||'').match(/^q-(\\d+)$/);
    if(m){const item=queue.get(Number(m[1]));if(item){queue.markDelivered(item.id);updateMessageByQueueId(item.id,{status:'Доставлено'});renderConversations($('#chatSearch')?.value||'');renderGlobalStatus();renderDeliveryQueue();}}
    return;
  }
  const from=String(meta.from||'').trim(); if(!from)return;
"""
    new="""function handleFastEnvelope(payload,meta={}){
  if(meta.system && payload?.type==='transport_ack'){
    const item=queue.byMessageId(String(payload.messageId||''));
    if(item){queue.markDelivered(item.id);updateMessageByQueueId(item.id,{status:'Доставлено'});renderConversations($('#chatSearch')?.value||'');renderGlobalStatus();renderDeliveryQueue();}
    return true;
  }
  const from=String(meta.from||'').trim(); if(!from)return false;
  if(meta.messageId){
    if(receivedFastMessageIds.has(meta.messageId))return true;
    receivedFastMessageIds.add(meta.messageId);
    while(receivedFastMessageIds.size>1000)receivedFastMessageIds.delete(receivedFastMessageIds.values().next().value);
    storageSet('mesh-wifi-received-message-ids',JSON.stringify([...receivedFastMessageIds]));
  }
"""
    if old not in s: raise SystemExit("fast envelope anchor missing under "+str(base))
    s=s.replace(old,new,1)

    old="""  if(!peerContacts.has(from)){
    peerContacts.set(from,{peerId:from,displayName:transport?.remoteName||'Контакт'});
    persistPeerContacts();
  }
"""
    new="""  if(!peerContacts.has(from)){
    return false;
  }
"""
    if old not in s: raise SystemExit("auto contact anchor missing under "+str(base))
    s=s.replace(old,new,1)

    old="""  renderConversations($('#chatSearch')?.value||'');if(id===currentConversationId)renderMessages();
}
"""
    new="""  renderConversations($('#chatSearch')?.value||'');if(id===currentConversationId)renderMessages();
  return true;
}
"""
    if old not in s: raise SystemExit("fast envelope return anchor missing under "+str(base))
    s=s.replace(old,new,1)

    old="""const storageGet = key => { try { return localStorage.getItem(key); } catch { return null; } };
const storageSet = (key, value) => { try { localStorage.setItem(key, value); } catch {} };
"""
    new="""const storageGet = key => { try { return localStorage.getItem(key); } catch { return null; } };
const storageSet = (key, value) => { try { localStorage.setItem(key, value); } catch {} };
const WIFI_QUEUE_KEY='mesh-wifi-delivery-queue-v1';
const receivedFastMessageIds=new Set();
if(WIFI_ONLY_MODE){
  try{queue.restore(JSON.parse(storageGet(WIFI_QUEUE_KEY)||'[]'));}catch{}
  queue.setOnChange(items=>storageSet(WIFI_QUEUE_KEY,JSON.stringify(items.filter(x=>!['delivered','sent-broadcast'].includes(x.status)))));
  try{for(const id of JSON.parse(storageGet('mesh-wifi-received-message-ids')||'[]'))if(id)receivedFastMessageIds.add(String(id));}catch{}
}
"""
    if old not in s: raise SystemExit("storage anchor missing under "+str(base))
    s=s.replace(old,new,1)

    old="""  const state=()=>{renderGlobalStatus();renderRoute();renderConversations($('#chatSearch')?.value||'');renderFastPairingState();};
"""
    new="""  const state=()=>{
    renderGlobalStatus();renderRoute();renderConversations($('#chatSearch')?.value||'');renderFastPairingState();
    if(lanTransport?.isReady?.())flushQueuedMessages().catch(()=>{});
  };
"""
    if old not in s: raise SystemExit("LAN state anchor missing under "+str(base))
    s=s.replace(old,new,1)

    old="""      await route.transport.send({type:item.payload.type||'text',text:item.payload.text||'',position:item.payload.position||null,conversationId:c.id},{messageId:'q-'+queueId,to:c.peerId});
"""
    new="""      await route.transport.send({type:item.payload.type||'text',text:item.payload.text||'',position:item.payload.position||null,conversationId:c.id},{messageId:item.messageId,to:c.peerId});
"""
    if old not in s: raise SystemExit("send messageId anchor missing under "+str(base))
    s=s.replace(old,new,1)

    old="""async function flushQueuedMessages(){
  if(activeRadio.state!=='connected'||phoneApiSession?.state!=='ready')return;
  const ready=queue.flush(payload=>selectDeliveryRoute(payload));
"""
    new="""async function flushQueuedMessages(){
  const ready=queue.flush(payload=>selectDeliveryRoute(payload));
"""
    if old not in s: raise SystemExit("flush gate anchor missing under "+str(base))
    s=s.replace(old,new,1)

    p.write_text(s,encoding="utf-8")

def patch_transport(base):
    p=base/"src"/"transports"/"lan-peer-transport.js"
    s=p.read_text(encoding="utf-8")
    old="""    if(m.type==='envelope'){this.onEnvelope(m.payload,{transportId:'wifi',from:m.from||this.remotePeerId,messageId:m.messageId||''});if(m.messageId)this._send({type:'ack',messageId:m.messageId});return;}
"""
    new="""    if(m.type==='envelope'){const accepted=this.onEnvelope(m.payload,{transportId:'wifi',from:m.from||this.remotePeerId,messageId:m.messageId||''});if(m.messageId&&accepted!==false)this._send({type:'ack',messageId:m.messageId});return;}
"""
    if old not in s: raise SystemExit("transport ACK anchor missing under "+str(base))
    p.write_text(s.replace(old,new,1),encoding="utf-8")

for tree in trees:
    patch_core(tree)
    patch_app(tree)
    patch_transport(tree)

print("MESH_WIFI_DELIVERY_V163_PASS")
