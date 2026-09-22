#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply_wifi_v16.py <source-root>")

root=Path(sys.argv[1]).resolve()
web=root
android=root/"android-app"/"app"/"src"/"main"/"assets"/"www"

def patch_tree(base: Path):
    app=base/"src"/"app.js"
    index=base/"index.html"
    if not app.exists() or not index.exists():
        raise SystemExit(f"missing app/index under {base}")

    s=app.read_text(encoding="utf-8")
    imports="""import { LanPeerTransport } from './transports/lan-peer-transport.js';
import { AutoRouteSelector } from './transports/auto-route-selector.js';
"""
    anchor="import { HELP_FALLBACK_ID, ERROR_TOPIC_MAP, helpRegistry, parseHelpTopic, buildSafeDiagnostics } from './help-registry.js';\n"
    if imports not in s:
        if anchor not in s: raise SystemExit("import anchor missing")
        s=s.replace(anchor,anchor+imports,1)

    helpers="""const peerContacts = new Map();
let lanTransport = null;
let autoRoute = null;
let appPeerId = '';
let appDisplayName = '';

function persistPeerContacts(){
  storageSet('mesh-wifi-contacts',JSON.stringify([...peerContacts.values()]));
}
function fastConversation(peerId){
  return peerContacts.get(String(peerId)) || null;
}
function fastConversationId(peerId){ return 'peer:'+String(peerId); }
function selectDeliveryRoute(payload={}){
  const c=buildConversations().find(x=>x.id===payload.conversationId);
  if(c?.peerId){
    const route=autoRoute?.select?.()||{transport:null,id:null,label:'Нет маршрута',reason:'offline'};
    return {transport:route.transport,reason:route.reason||route.label,codec:'text',mode:'data',routeId:route.id};
  }
  return transportManager.select(payload.type||'text');
}
function fastRouteLabel(){
  const r=autoRoute?.select?.();
  return r?.id==='wifi'?'Напрямую':'Офлайн';
}
function handleFastEnvelope(payload,meta={}){
  if(meta.system && payload?.type==='transport_ack'){
    const m=String(payload.messageId||'').match(/^q-(\d+)$/);
    if(m){const item=queue.get(Number(m[1]));if(item){queue.markDelivered(item.id);updateMessageByQueueId(item.id,{status:'Доставлено'});renderConversations($('#chatSearch')?.value||'');renderGlobalStatus();renderDeliveryQueue();}}
    return;
  }
  const from=String(meta.from||'').trim(); if(!from)return;
  const transport=lanTransport;
  if(!peerContacts.has(from)){
    peerContacts.set(from,{peerId:from,displayName:transport?.remoteName||'Контакт'});
    persistPeerContacts();
  }
  const id=fastConversationId(from), bucket=getBucket(id);
  if(payload?.type==='position' && payload.position?.latitude!=null && payload.position?.longitude!=null){
    bucket.push({side:'in',author:peerContacts.get(from)?.displayName||'Контакт',text:'Позиция',position:payload.position,positionNodeNum:0,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})});
  } else if(payload?.type==='text' && payload.text){
    bucket.push({side:'in',author:peerContacts.get(from)?.displayName||'Контакт',text:payload.text,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})});
  } else return;
  if(id!==currentConversationId)uiState(id).unread=(uiState(id).unread||0)+1;
  renderConversations($('#chatSearch')?.value||'');if(id===currentConversationId)renderMessages();
}
function initFastTransports(){
  appPeerId=storageGet('mesh-wifi-peer-id')||((globalThis.crypto?.randomUUID?.())||('peer-'+Date.now().toString(36)));
  appDisplayName=storageGet('mesh-wifi-name')||'Mesh Wi-Fi';
  storageSet('mesh-wifi-peer-id',appPeerId);storageSet('mesh-wifi-name',appDisplayName);
  try{for(const c of JSON.parse(storageGet('mesh-wifi-contacts')||'[]'))if(c?.peerId)peerContacts.set(String(c.peerId),c);}catch{}
  const state=()=>{renderGlobalStatus();renderRoute();renderConversations($('#chatSearch')?.value||'');renderFastPairingState();};
  lanTransport=new LanPeerTransport({peerId:appPeerId,displayName:appDisplayName,onEnvelope:handleFastEnvelope,onState:state});
  autoRoute=new AutoRouteSelector({lan:lanTransport});
}
function rememberFastPeer(transport){
  const peerId=transport?.remotePeerId;if(!peerId)return;
  peerContacts.set(String(peerId),{peerId:String(peerId),displayName:transport.remoteName||'Контакт'});
  persistPeerContacts();
  currentConversationId=fastConversationId(peerId);storageSet('mesh-current-conversation',currentConversationId);
  renderConversations();renderConversationHeader();renderMessages();
}
function renderFastPairingState(){
  const el=$('#fastPairState');if(!el)return;
  const l=lanTransport?.snapshot?.()||{};
  el.textContent='LAN: '+(l.ready?'готов':'не подключён');
}
async function createLanInvite(){
  const code=await lanTransport.createInvite();$('#pairingCode').value=code;renderFastPairingState();
}
async function applyLanCode(){
  const code=$('#pairingCode').value.trim();if(!code)return;
  const r=await lanTransport.applySignal(code);if(r.response)$('#pairingCode').value=r.response;
  rememberFastPeer(lanTransport);renderFastPairingState();
}
"""
    anchor2="const storageRemove = key => { try { localStorage.removeItem(key); } catch {} };\n"
    if helpers not in s:
        if anchor2 not in s: raise SystemExit("storage anchor missing")
        s=s.replace(anchor2,anchor2+helpers,1)

    peer_block="""  for(const c of peerContacts.values()){
    const id=fastConversationId(c.peerId);const last=getLastMessage(id),ui=uiState(id);
    result.push({id,kind:'direct',peerId:String(c.peerId),channel:0,title:c.displayName||'Контакт',subtitle:fastRouteLabel(),preview:last?.text||'Личный чат',time:last?.time||'',route:fastRouteLabel(),unread:ui.unread||0,muted:Boolean(ui.muted),delivery:latestDeliveryStatus(id)});
  }
"""
    anchor3="  if(!result.some(x=>x.id===currentConversationId)){\n"
    if peer_block not in s:
        if anchor3 not in s: raise SystemExit("conversation anchor missing")
        s=s.replace(anchor3,peer_block+anchor3,1)

    old_route="  const kind=$('#messageTypeSelect')?.value||'text', decision=transportManager.select(kind);"
    new_route="  const kind=$('#messageTypeSelect')?.value||'text', fast=autoRoute?.select?.(), decision=fast?.transport?{transport:{...fast.transport,name:fast.label,latency:fast.id==='wifi'?20:120},reason:fast.reason,codec:'data',mode:'data'}:transportManager.select(kind);"
    if old_route in s: s=s.replace(old_route,new_route,1)

    old_global="  const decision=transportManager.select('text'), pending=queue.pendingCount(), active=Boolean(decision.transport);"
    new_global="  const fast=autoRoute?.select?.(), decision=fast?.transport?{transport:{...fast.transport,name:fast.label},reason:fast.reason}:transportManager.select('text'), pending=queue.pendingCount(), active=Boolean(decision.transport);"
    if old_global in s: s=s.replace(old_global,new_global,1)

    old_tx="""async function transmitQueueItem(queueId){
  const item=queue.get(queueId); if(!item)return;
  const c=buildConversations().find(x=>x.id===item.payload.conversationId);
  if(!c || activeRadio.state!=='connected' || phoneApiSession?.state!=='ready'){queue.defer(queueId);updateMessageByQueueId(queueId,{status:'В очереди'});renderGlobalStatus();renderRoute();return;}
"""
    new_tx="""async function transmitQueueItem(queueId){
  const item=queue.get(queueId); if(!item)return;
  const c=buildConversations().find(x=>x.id===item.payload.conversationId);
  if(c?.peerId){
    const route=autoRoute?.select?.();
    if(!route?.transport){queue.defer(queueId);updateMessageByQueueId(queueId,{status:'В очереди'});renderGlobalStatus();renderRoute();return;}
    const packetId=nextPacketId();queue.markSending(queueId,{packetId,transportId:route.id});updateMessageByQueueId(queueId,{status:'Отправка…',packetId});
    try{
      await route.transport.send({type:item.payload.type||'text',text:item.payload.text||'',position:item.payload.position||null,conversationId:c.id},{messageId:'q-'+queueId,to:c.peerId});
      queue.markSent(queueId,{broadcast:false});updateMessageByQueueId(queueId,{status:'Отправлено · ждём ACK'});
    }catch(error){queue.markFailed(queueId,error?.message||error);updateMessageByQueueId(queueId,{status:'Ошибка отправки'});}
    renderGlobalStatus();renderRoute();renderDeliveryQueue();return;
  }
  if(!c || activeRadio.state!=='connected' || phoneApiSession?.state!=='ready'){queue.defer(queueId);updateMessageByQueueId(queueId,{status:'В очереди'});renderGlobalStatus();renderRoute();return;}
"""
    if old_tx in s: s=s.replace(old_tx,new_tx,1)
    elif "if(c?.peerId){" not in s: raise SystemExit("transmitQueueItem anchor missing")

    s=s.replace("queue.flush(payload=>transportManager.select(payload.type||'text'))","queue.flush(payload=>selectDeliveryRoute(payload))")
    s=s.replace("const decision=transportManager.select('text');\n  const item=queue.enqueue({type:'text',text:clean,conversationId:c.id},decision);","const decision=selectDeliveryRoute({type:'text',conversationId:c.id});\n  const item=queue.enqueue({type:'text',text:clean,conversationId:c.id},decision);",1)

    wire="""  $('#openFastPairing')?.addEventListener('click',()=>{closeModal($('#addMenuModal'));openModal($('#fastPairModal'));renderFastPairingState();});
  $('#closeFastPairing')?.addEventListener('click',()=>closeModal($('#fastPairModal')));
  $('#fastPairModal')?.addEventListener('click',e=>{if(e.target===$('#fastPairModal'))closeModal($('#fastPairModal'));});
  $('#createLanInvite')?.addEventListener('click',()=>createLanInvite().catch(e=>renderSystemBanner('error',e.message)));
  $('#applyLanCode')?.addEventListener('click',()=>applyLanCode().catch(e=>renderSystemBanner('error',e.message)));
  $('#copyPairingCode')?.addEventListener('click',async()=>{const v=$('#pairingCode').value;if(!v)return;try{await navigator.clipboard.writeText(v);}catch{}});
"""
    anchor4="  $('#newContactButton').onclick=()=>openModal($('#addMenuModal'));\n"
    if wire not in s:
        if anchor4 not in s: raise SystemExit("wire anchor missing")
        s=s.replace(anchor4,anchor4+wire,1)

    init_anchor="initTheme();\n"
    if "initFastTransports();" not in s:
        s=s.replace(init_anchor,init_anchor+"initFastTransports();\n",1)

    debug_old="window.__meshDebug={transportManager,queue,"
    if debug_old in s:
        s=s.replace(debug_old,"window.__meshDebug={transportManager,queue,lanTransport,autoRoute,peerContacts,",1)

    app.write_text(s,encoding="utf-8")

    h=index.read_text(encoding="utf-8")
    h=h.replace('<title>Mesh Messenger Prototype</title>','<title>Mesh Wi-Fi 1.6</title>')
    h=h.replace('<strong>Mesh Messenger</strong>\n          <span>local QA runtime</span>','<strong>Mesh Wi‑Fi</strong>\n          <span>LAN only</span>')
    h=h.replace('<strong>Mesh Messenger</strong>\n          <span id="mobileSubstatus">Сеть активна</span>','<strong>Mesh Wi‑Fi</strong>\n          <span id="mobileSubstatus">Проверяем маршрут</span>')
    if 'id="openFastPairing"' not in h:
        h=h.replace('<div class="add-menu-grid">','<div class="add-menu-grid">\n            <button type="button" id="openFastPairing"><strong>Добавить контакт</strong><small>LAN · один контакт</small></button>',1)
    modal="""
      <section class="modal-layer" id="fastPairModal" aria-hidden="true">
        <div class="modal-card" role="dialog" aria-modal="true" aria-labelledby="fastPairTitle">
          <div class="modal-header"><div><p class="eyebrow">Mesh Wi‑Fi 1.6</p><h2 id="fastPairTitle">Добавить контакт</h2></div><button class="icon-button" id="closeFastPairing" aria-label="Закрыть" type="button">×</button></div>
          <p class="modal-copy">Добавьте контакт для прямой связи по локальной Wi‑Fi сети или hotspot. Интернет и relay на этом этапе отключены.</p>
          <div class="pending-card"><strong id="fastPairState">LAN: не подключён</strong><span>Оба устройства должны быть в одной локальной Wi‑Fi сети или hotspot.</span></div>
          <label class="field-stack"><span>Код подключения</span><textarea id="pairingCode" rows="6" placeholder="Создайте код на одном устройстве и вставьте его на другом"></textarea></label>
          <div class="modal-actions"><button class="secondary-button" id="createLanInvite" type="button">Создать LAN-код</button><button class="secondary-button" id="applyLanCode" type="button">Применить LAN-код</button></div>
          <div class="modal-actions"><button class="primary-button" id="copyPairingCode" type="button">Копировать код</button></div>
        </div>
      </section>
"""
    if 'id="fastPairModal"' not in h:
        anchor='      <section class="modal-layer" id="importQrModal" aria-hidden="true">'
        if anchor not in h: raise SystemExit("modal anchor missing")
        h=h.replace(anchor,modal+"\n"+anchor,1)
    index.write_text(h,encoding="utf-8")

patch_tree(web)
if android.exists():
    patch_tree(android)

# Wi-Fi focused Android permission policy: retain INTERNET/location, make BLE optional rather than required.
manifest=root/"android-app"/"app"/"src"/"main"/"AndroidManifest.xml"
if manifest.exists():
    m=manifest.read_text(encoding="utf-8")
    m=m.replace('android.hardware.bluetooth_le" android:required="true"','android.hardware.bluetooth_le" android:required="false"')
    manifest.write_text(m,encoding="utf-8")

print("MESH_WIFI_V16_OVERLAY_PASS")
