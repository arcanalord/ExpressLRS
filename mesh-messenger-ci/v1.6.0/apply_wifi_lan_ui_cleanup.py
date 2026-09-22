#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply_wifi_lan_ui_cleanup.py <source-root>")

root=Path(sys.argv[1]).resolve()
trees=[root]
android=root/"android-app"/"app"/"src"/"main"/"assets"/"www"
if android.exists():
    trees.append(android)

def once(s, old, new, label):
    if old not in s:
        raise SystemExit("missing anchor: "+label)
    return s.replace(old,new,1)

def patch_app(base):
    p=base/"src"/"app.js"
    s=p.read_text(encoding="utf-8")

    s=once(s,
      "import { AutoRouteSelector } from './transports/auto-route-selector.js';\n",
      "import { AutoRouteSelector } from './transports/auto-route-selector.js';\n\nconst WIFI_ONLY_MODE = true;\n",
      "wifi-only constant")

    old="""function rememberFastPeer(transport){
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
    new="""function updateLocalPairingName(){
  const input=$('#pairingMyName');
  const name=(input?.value||storageGet('mesh-wifi-name')||'').trim()||'Устройство';
  appDisplayName=name;
  storageSet('mesh-wifi-name',name);
  lanTransport?.setIdentity?.({peerId:appPeerId,displayName:name});
}
function showFastPairError(message=''){
  const el=$('#fastPairError');if(!el)return;
  el.hidden=!message;el.textContent=message||'';
}
function rememberFastPeer(transport){
  const peerId=transport?.remotePeerId;
  if(!peerId || !transport?.isReady?.()){showFastPairError('Сначала дождитесь статуса «LAN подключён».');return false;}
  const displayName=(transport.remoteName||'Контакт').trim()||'Контакт';
  peerContacts.set(String(peerId),{peerId:String(peerId),displayName});
  persistPeerContacts();
  currentConversationId=fastConversationId(peerId);storageSet('mesh-current-conversation',currentConversationId);
  renderConversations();renderConversationHeader();renderMessages();
  closeModal($('#fastPairModal'));selectConversation(currentConversationId);
  return true;
}
function renderFastPairingState(){
  const el=$('#fastPairState');if(!el)return;
  const l=lanTransport?.snapshot?.()||{};
  const save=$('#saveFastPeer');
  const hint=$('#fastPairHint');
  if(l.ready){
    el.textContent='LAN подключён'+(l.remoteName?' · '+l.remoteName:'');
    if(hint)hint.textContent='Соединение установлено. Теперь сохраните контакт и откройте личный чат.';
    if(save)save.disabled=false;
    showFastPairError('');
  }else if(l.state==='connecting'){
    el.textContent='LAN: соединяем устройства…';
    if(hint)hint.textContent='Подождите несколько секунд.';
    if(save)save.disabled=true;
  }else if(l.state==='pairing'){
    el.textContent='LAN: обмен кодами';
    if(hint)hint.textContent='Передайте текущий код на второе устройство. Если оно создаст ответ — верните ответный код сюда.';
    if(save)save.disabled=true;
  }else{
    el.textContent='LAN: не подключён';
    if(hint)hint.textContent='Оба устройства должны быть в одной Wi‑Fi сети или hotspot.';
    if(save)save.disabled=true;
  }
}
async function createLanInvite(){
  showFastPairError('');updateLocalPairingName();
  const code=await lanTransport.createInvite();
  $('#pairingCode').value=code;
  const hint=$('#fastPairHint');if(hint)hint.textContent='Шаг 1: передайте этот код на второе устройство.';
  renderFastPairingState();
}
async function applyLanCode(){
  showFastPairError('');updateLocalPairingName();
  const code=$('#pairingCode').value.trim();if(!code){showFastPairError('Вставьте код второго устройства.');return;}
  const r=await lanTransport.applySignal(code);
  if(r.response){
    $('#pairingCode').value=r.response;
    const hint=$('#fastPairHint');if(hint)hint.textContent='Шаг 2: создан ответ. Передайте этот новый код обратно на первое устройство.';
  }else{
    const hint=$('#fastPairHint');if(hint)hint.textContent='Шаг 3: ответ принят. Устанавливаем прямое соединение…';
  }
  renderFastPairingState();
}
"""
    s=once(s,old,new,"pairing functions")

    old="function buildConversations(snapshot=currentSnapshot()) {\n  const result=[];\n"
    new="""function buildConversations(snapshot=currentSnapshot()) {
  const result=[];
  if(WIFI_ONLY_MODE){
    for(const c of peerContacts.values()){
      const id=fastConversationId(c.peerId),last=getLastMessage(id),ui=uiState(id);
      result.push({id,kind:'direct',peerId:String(c.peerId),channel:0,title:c.displayName||'Контакт',subtitle:fastRouteLabel(),preview:last?.text||'Личный чат',time:last?.time||'',route:fastRouteLabel(),unread:ui.unread||0,muted:Boolean(ui.muted),delivery:latestDeliveryStatus(id)});
    }
    if(!result.some(x=>x.id===currentConversationId))currentConversationId=result[0]?.id||'';
    return result;
  }
"""
    s=once(s,old,new,"conversation wifi branch")

    old="  const conversations=buildConversations();\n  conversations.filter(c =>"
    new="""  const conversations=buildConversations();
  if(!conversations.length){
    list.innerHTML='<div class="node-empty"><strong>Пока нет контактов</strong><br>Нажмите +, соедините два устройства и сохраните личный контакт.</div>';
    return;
  }
  conversations.filter(c =>"""
    s=once(s,old,new,"empty conversations")

    old="function renderConversationHeader(){\n  const c=currentConversation(); if(!c)return;\n"
    new="""function renderConversationHeader(){
  const c=currentConversation();
  if(!c){
    $('#conversationTitle').textContent='Выберите контакт';
    const span=$('#conversationTitle')?.parentElement?.querySelector('span');
    if(span)span.textContent='Добавьте контакт кнопкой +';
    return;
  }
"""
    s=once(s,old,new,"empty conversation header")

    old="""function renderMessages() {
  const stream = $('#messageStream');
  stream.innerHTML = '<div class="day-label">Сегодня</div>';
"""
    new="""function renderMessages() {
  const stream = $('#messageStream');
  if(WIFI_ONLY_MODE && !currentConversation()){
    stream.innerHTML='<div class="node-empty">Здесь появится личная переписка после добавления контакта.</div>';
    return;
  }
  stream.innerHTML = '<div class="day-label">Сегодня</div>';
"""
    s=once(s,old,new,"empty messages")

    old="function renderSystemBanner(state='disconnected', detail='') {\n  const banner=$('#systemBanner'); if(!banner)return;\n"
    new="""function renderSystemBanner(state='disconnected', detail='') {
  const banner=$('#systemBanner'); if(!banner)return;
  if(WIFI_ONLY_MODE){banner.hidden=true;return;}
"""
    s=once(s,old,new,"hide legacy banner")

    old="function renderTransportCards() {\n  const holder=$('#transportCards'); holder.innerHTML='';\n"
    new="""function renderTransportCards() {
  const holder=$('#transportCards'); holder.innerHTML='';
  if(WIFI_ONLY_MODE){
    const l=lanTransport?.snapshot?.()||{};
    holder.innerHTML='<div class="transport-card '+(l.ready?'available':'')+'"><div class="transport-title"><div><strong>Локальный Wi‑Fi</strong><small>Прямое соединение без Internet/relay</small></div><span class="runtime-badge">LAN</span></div><div class="transport-metrics"><span>'+(l.ready?'подключён':'не подключён')+'</span><span>direct</span><span>WebRTC</span></div></div>';
    return;
  }
"""
    s=once(s,old,new,"wifi transport card")

    old="""function renderRoute() {
  const kind=$('#messageTypeSelect')?.value||'text', fast=autoRoute?.select?.(), decision=fast?.transport?{transport:{...fast.transport,name:fast.label,latency:fast.id==='wifi'?20:120},reason:fast.reason,codec:'data',mode:'data'}:transportManager.select(kind);
"""
    new="""function renderRoute() {
  const kind=$('#messageTypeSelect')?.value||'text', fast=autoRoute?.select?.();
  const decision=WIFI_ONLY_MODE
    ? (fast?.transport?{transport:{...fast.transport,name:'Прямой Wi‑Fi',latency:20},reason:'Прямое соединение в локальной сети',codec:'data',mode:'data'}:{transport:null,reason:'Добавьте контакт и установите LAN-соединение',codec:'data',mode:'data'})
    : (fast?.transport?{transport:{...fast.transport,name:fast.label,latency:fast.id==='wifi'?20:120},reason:fast.reason,codec:'data',mode:'data'}:transportManager.select(kind));
"""
    s=once(s,old,new,"wifi route only")

    old="""function renderGlobalStatus() {
  const fast=autoRoute?.select?.(), decision=fast?.transport?{transport:{...fast.transport,name:fast.label},reason:fast.reason}:transportManager.select('text'), pending=queue.pendingCount(), active=Boolean(decision.transport);
"""
    new="""function renderGlobalStatus() {
  const fast=autoRoute?.select?.();
  const decision=WIFI_ONLY_MODE?(fast?.transport?{transport:{...fast.transport,name:'Прямой Wi‑Fi'},reason:fast.reason}:{transport:null,reason:'offline'}):(fast?.transport?{transport:{...fast.transport,name:fast.label},reason:fast.reason}:transportManager.select('text'));
  const pending=queue.pendingCount(),active=Boolean(decision.transport);
  if(WIFI_ONLY_MODE){
    $('#networkStateLabel').textContent=active?'LAN подключён':'LAN не подключён';
    $('#routeSummary').textContent=active?('Прямой Wi‑Fi · очередь '+pending):('Добавьте контакт или восстановите LAN · очередь '+pending);
    $('#mobileSubstatus').textContent=active?('LAN · очередь '+pending):('LAN офлайн · очередь '+pending);
    const count=$('#nodeCount');if(count){count.hidden=true;count.textContent='';}
    const healthLabel=$('#networkHealthLabel'),healthMeta=$('#networkHealthMeta'),healthDot=$('#networkHealthDot');
    if(healthLabel)healthLabel.textContent=active?'Связь: напрямую':'Связь: LAN не подключён';
    if(healthMeta)healthMeta.textContent=active?(pending+' в очереди'):(pending+' ожидает соединение');
    if(healthDot)healthDot.classList.toggle('warn',!active);
    $('#conversationRoute').textContent=active?'Связь напрямую по Wi‑Fi':'LAN не подключён · сообщение останется в очереди';
    $('#queueBadge').textContent='очередь '+pending;
    $$('.status-dot').forEach(d=>d.classList.toggle('warn',!active));
    renderDeliveryQueue();
    return;
  }
"""
    s=once(s,old,new,"wifi global status")

    s=s.replace("$('#newContactButton').onclick=()=>openModal($('#addMenuModal'));",
                "$('#newContactButton').onclick=()=>{showFastPairError('');openModal($('#fastPairModal'));renderFastPairingState();};",1)
    s=s.replace("$('#openFastPairing')?.addEventListener('click',()=>{closeModal($('#addMenuModal'));openModal($('#fastPairModal'));renderFastPairingState();});",
                "$('#openFastPairing')?.addEventListener('click',()=>{closeModal($('#addMenuModal'));showFastPairError('');openModal($('#fastPairModal'));renderFastPairingState();});",1)

    anchor="  $('#applyLanCode')?.addEventListener('click',()=>applyLanCode().catch(e=>renderSystemBanner('error',e.message)));\n"
    repl="""  $('#applyLanCode')?.addEventListener('click',()=>applyLanCode().catch(e=>showFastPairError(e.message||String(e))));
  $('#saveFastPeer')?.addEventListener('click',()=>rememberFastPeer(lanTransport));
  $('#pairingMyName')?.addEventListener('change',updateLocalPairingName);
"""
    s=once(s,anchor,repl,"pair event handlers")
    s=s.replace("$('#createLanInvite')?.addEventListener('click',()=>createLanInvite().catch(e=>renderSystemBanner('error',e.message)));",
                "$('#createLanInvite')?.addEventListener('click',()=>createLanInvite().catch(e=>showFastPairError(e.message||String(e))));",1)

    old="renderConversations();renderConversationHeader();renderMessages();renderTransportCards();renderGlobalStatus();renderRoute();renderDeliveryQueue();renderSystemBanner('syncing');renderMap();\n"
    new="renderConversations();renderConversationHeader();renderMessages();renderTransportCards();renderGlobalStatus();renderRoute();renderDeliveryQueue();if(!WIFI_ONLY_MODE)renderSystemBanner('syncing');renderMap();\n"
    s=once(s,old,new,"startup banner")

    old="if(!globalThis.__meshDisableAutoConnect)activateRadio(AndroidBridgeMeshtasticTransport.isSupported()?androidBleRadio:mockRadio).catch(()=>{});"
    new="if(!WIFI_ONLY_MODE&&!globalThis.__meshDisableAutoConnect)activateRadio(AndroidBridgeMeshtasticTransport.isSupported()?androidBleRadio:mockRadio).catch(()=>{});"
    s=once(s,old,new,"disable radio autoconnect")

    p.write_text(s,encoding="utf-8")

def patch_html(base):
    p=base/"index.html"
    h=p.read_text(encoding="utf-8")
    h=h.replace('<p class="eyebrow">Offline-first</p>','<p class="eyebrow">Локальная связь</p>',1)
    h=h.replace('<p>Сообщения не пропадают без интернета: они ждут доступный маршрут.</p>','<p>Личные чаты по одной Wi‑Fi сети или hotspot. Internet/relay добавим позже.</p>',1)
    h=h.replace('<span id="nodeCount">7 узлов</span>','<span id="nodeCount" hidden></span>',1)
    h=h.replace('<p id="routeSummary">Meshtastic · хороший сигнал · очередь 0</p>','<p id="routeSummary">LAN не подключён · очередь 0</p>',1)
    h=h.replace('<div class="system-banner is-ready" id="systemBanner"','<div class="system-banner is-ready" id="systemBanner" hidden',1)
    h=h.replace('placeholder="Поиск по чатам и узлам" aria-label="Поиск по чатам и узлам"','placeholder="Поиск по чатам" aria-label="Поиск по чатам"',1)
    h=h.replace('<strong id="conversationTitle">Группа Альфа</strong>','<strong id="conversationTitle">Выберите контакт</strong>',1)
    h=h.replace('<span><span class="status-dot ok"></span> Mesh · 5 участников · 2 hops</span>','<span>Добавьте контакт кнопкой +</span>',1)
    h=h.replace('<button class="secondary-button" id="pttShortcut" type="button">PTT</button>','<button class="secondary-button" id="pttShortcut" type="button" hidden>PTT</button>',1)
    h=h.replace('<button id="attachFile" class="icon-button"','<button id="attachFile" class="icon-button" hidden',1)
    h=h.replace('<button id="composerVoice" class="quiet-button composer-voice"','<button id="composerVoice" class="quiet-button composer-voice" hidden',1)
    h=h.replace('<div class="radio-link-card" id="radioLinkCard">','<div class="radio-link-card" id="radioLinkCard" hidden>',1)
    h=h.replace('<div class="phoneapi-snapshot" id="phoneApiSnapshot">','<div class="phoneapi-snapshot" id="phoneApiSnapshot" hidden>',1)
    h=h.replace('<div class="relay-card">','<div class="relay-card" hidden>',1)
    h=h.replace('<small>Meshtastic BLE / USB · состояние связи</small>','<small>Прямой LAN / Wi‑Fi · без relay</small>',1)
    h=h.replace('<span>Mesh активен</span>','<span>LAN режим</span>',1)
    h=h.replace('<button class="nav-item is-active" data-view="chats" type="button"><span>Чаты</span><small>3</small></button>','<button class="nav-item is-active" data-view="chats" type="button"><span>Чаты</span><small></small></button>',1)
    h=h.replace('<button class="nav-item" data-view="map" type="button"><span>Карта</span><small>7</small></button>','<button class="nav-item" data-view="map" type="button"><span>Карта</span><small></small></button>',1)

    modal_start=h.find('<section class="modal-layer" id="fastPairModal"')
    modal_end=h.find('</section>',modal_start)
    if modal_start<0 or modal_end<0:
        raise SystemExit("fastPairModal not found under "+str(base))
    modal_end+=len('</section>')
    new_modal="""<section class="modal-layer" id="fastPairModal" aria-hidden="true">
        <div class="modal-card" role="dialog" aria-modal="true" aria-labelledby="fastPairTitle">
          <div class="modal-header"><div><p class="eyebrow">Mesh Wi-Fi</p><h2 id="fastPairTitle">Добавить личный контакт</h2></div><button class="icon-button" id="closeFastPairing" aria-label="Закрыть" type="button">×</button></div>
          <p class="modal-copy">Это личный контакт 1↔1, не группа. Оба устройства должны быть в одной Wi‑Fi сети или hotspot.</p>
          <label class="field-stack"><span>Моё имя</span><input id="pairingMyName" maxlength="40" placeholder="Например: Кирилл" /></label>
          <div class="pending-card"><strong id="fastPairState">LAN: не подключён</strong><span id="fastPairHint">Оба устройства должны быть в одной локальной Wi‑Fi сети или hotspot.</span></div>
          <div class="pending-card is-error" id="fastPairError" hidden></div>
          <label class="field-stack"><span>Код подключения</span><textarea id="pairingCode" rows="6" placeholder="1. Создай код на A → 2. Вставь на B → 3. Ответ B вставь обратно на A"></textarea></label>
          <div class="modal-actions"><button class="secondary-button" id="createLanInvite" type="button">Создать код</button><button class="secondary-button" id="applyLanCode" type="button">Применить код</button></div>
          <div class="modal-actions"><button class="quiet-button" id="copyPairingCode" type="button">Копировать код</button><button class="primary-button" id="saveFastPeer" type="button" disabled>Сохранить и открыть чат</button></div>
        </div>
      </section>"""
    h=h[:modal_start]+new_modal+h[modal_end:]

    start=h.find('<div class="add-menu-grid">')
    end=h.find('</div>',start)
    if start>=0 and end>=0:
        h=h[:start]+'''<div class="add-menu-grid">
            <button type="button" id="openFastPairing"><strong>Добавить контакт</strong><small>Личный чат · LAN</small></button>
          </div>'''+h[end+6:]

    p.write_text(h,encoding="utf-8")

for tree in trees:
    patch_app(tree)
    patch_html(tree)

print("MESH_WIFI_LAN_UI_CLEANUP_PASS")
