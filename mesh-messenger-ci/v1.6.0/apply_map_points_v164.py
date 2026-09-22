#!/usr/bin/env python3
from pathlib import Path
import re, sys
if len(sys.argv)!=2: raise SystemExit("usage: apply_map_points_v164.py <source-root>")
root=Path(sys.argv[1]).resolve()

def one(s,a,b,name):
    if a not in s: raise SystemExit("missing anchor: "+name)
    return s.replace(a,b,1)

def patch_app(p):
    s=p.read_text(encoding="utf-8")
    s=one(s,
      "const mapViewport={centerX:.5,centerY:.5,zoom:1,initialized:false,userMoved:false,pointers:new Map(),pinch:null};",
      "const mapViewport={centerX:.5,centerY:.5,zoom:1,initialized:false,userMoved:false,pointers:new Map(),pinch:null,suppressPointTapUntil:0};",
      "mapViewport")
    s=one(s,
      "function persistWaypoints(){try{storageSet('mesh-waypoints-v1',JSON.stringify([...sharedWaypoints.values()]));}catch{}}\nfunction restoreWaypoints(){try{for(const w of JSON.parse(storageGet('mesh-waypoints-v1')||'[]'))if(w?.id)sharedWaypoints.set(w.id>>>0,w);}catch{}}",
      "function waypointStorageKey(w){return \`${w?.sourcePeerId||w?.sourceNode||'local'}:${Number(w?.id)>>>0}\`;}\nfunction persistWaypoints(){try{storageSet('mesh-waypoints-v1',JSON.stringify([...sharedWaypoints.values()]));}catch{}}\nfunction restoreWaypoints(){try{for(const w of JSON.parse(storageGet('mesh-waypoints-v1')||'[]'))if(w?.id)sharedWaypoints.set(waypointStorageKey(w),w);}catch{}}",
      "waypoint persistence")
    s=one(s,
      "  } else if(payload?.type==='text' && payload.text){\n    bucket.push({side:'in',author:peerContacts.get(from)?.displayName||'Контакт',text:payload.text,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})});\n  } else return;",
      "  } else if(payload?.type==='waypoint' && payload.waypoint?.latitude!=null && payload.waypoint?.longitude!=null){\n    const w={...payload.waypoint,sourcePeerId:from,receivedAt:Date.now()};sharedWaypoints.set(waypointStorageKey(w),w);persistWaypoints();renderMap();\n    bucket.push({side:'in',author:peerContacts.get(from)?.displayName||'Контакт',text:w.name||'Точка',waypoint:w,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})});\n  } else if(payload?.type==='text' && payload.text){\n    bucket.push({side:'in',author:peerContacts.get(from)?.displayName||'Контакт',text:payload.text,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})});\n  } else return false;",
      "incoming waypoint")
    s=one(s,
      "await route.transport.send({type:item.payload.type||'text',text:item.payload.text||'',position:item.payload.position||null,conversationId:c.id},{messageId:item.messageId,to:c.peerId});",
      "await route.transport.send({type:item.payload.type||'text',text:item.payload.text||'',position:item.payload.position||null,waypoint:item.payload.waypoint||null,conversationId:c.id},{messageId:item.messageId,to:c.peerId});",
      "LAN waypoint payload")
    s=one(s,
      "const w={...packet.decoded.waypoint,sourceNode:packet.from>>>0,receivedAt:Date.now()};sharedWaypoints.set(w.id>>>0,w);persistWaypoints();renderMap();",
      "const w={...packet.decoded.waypoint,sourceNode:packet.from>>>0,receivedAt:Date.now()};sharedWaypoints.set(waypointStorageKey(w),w);persistWaypoints();renderMap();",
      "meshtastic waypoint key")
    merc="""function mercatorPoint(position){
  const lat=Math.max(-85.05112878,Math.min(85.05112878,Number(position.latitude))),lon=Number(position.longitude);
  const x=(lon+180)/360;
  const sin=Math.sin(lat*Math.PI/180);
  const y=0.5-Math.log((1+sin)/(1-sin))/(4*Math.PI);
  return {x,y};
}"""
    s=one(s,merc,merc+"""
function unmercatorPoint(point){
  const x=((Number(point.x)%1)+1)%1,y=Math.max(0,Math.min(1,Number(point.y)));
  const longitude=x*360-180,n=Math.PI-2*Math.PI*y,latitude=180/Math.PI*Math.atan(Math.sinh(n));
  return {latitude,longitude};
}
function unprojectMapScreen(clientX,clientY){
  const {canvas,w,h}=mapCanvasSize();if(!canvas)return null;
  const rect=canvas.getBoundingClientRect(),world=mapWorldSize();
  return unmercatorPoint({x:mapViewport.centerX+(clientX-rect.left-w/2)/world,y:mapViewport.centerY+(clientY-rect.top-h/2)/world});
}
function mapCenterPosition(){return unmercatorPoint({x:mapViewport.centerX,y:mapViewport.centerY});}""","unproject")
    old=re.search(r"function openWaypointModal\(\)\{.*?\n\}\nasync function sendWaypointFromModal\(\)\{.*?\n\}",s,re.S)
    if not old: raise SystemExit("missing waypoint functions")
    new="""function openWaypointModal(position=null){
  const target=position||mapCenterPosition();
  if(!Number.isFinite(Number(target?.latitude))||!Number.isFinite(Number(target?.longitude))){alert('Не удалось определить координаты точки.');return;}
  pendingWaypointPosition={latitude:Number(target.latitude),longitude:Number(target.longitude)};
  $('#waypointName').value=`Точка ${new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})}`;$('#waypointDescription').value='';$('#waypointExpire').value='21600';
  const coords=$('#waypointCoords');if(coords)coords.textContent=formatCoords(pendingWaypointPosition);
  const c=currentConversation(),targetLabel=$('#waypointTarget');if(targetLabel)targetLabel.textContent=c?`Получатель: ${c.title}`:'Получатель не выбран · можно сохранить локально';
  const send=$('#confirmWaypoint');if(send)send.disabled=!c;openModal($('#waypointModal'));
}
function waypointFromModal(){
  if(!pendingWaypointPosition)return null;
  const name=($('#waypointName').value||'Точка').trim().slice(0,30),description=($('#waypointDescription').value||'').trim().slice(0,100),ttl=Math.max(0,Number($('#waypointExpire').value)||0);
  const id=nextPacketId(),expire=ttl?Math.floor(Date.now()/1000)+ttl:0;
  return {id,latitude:pendingWaypointPosition.latitude,longitude:pendingWaypointPosition.longitude,expire,lockedTo:currentSnapshot()?.myInfo?.myNodeNum>>>0,name,description,icon:0x1f4cd,sourcePeerId:appPeerId||'local',createdAt:Date.now()};
}
function saveWaypointLocal(){
  const waypoint=waypointFromModal();if(!waypoint)return null;
  sharedWaypoints.set(waypointStorageKey(waypoint),waypoint);persistWaypoints();renderMap();closeModal($('#waypointModal'));pendingWaypointPosition=null;return waypoint;
}
async function sendWaypointFromModal(){
  const c=currentConversation();if(!c){alert('Сначала выберите личный чат или сохраните точку локально.');return null;}
  const waypoint=waypointFromModal();if(!waypoint)return null;
  sharedWaypoints.set(waypointStorageKey(waypoint),waypoint);persistWaypoints();renderMap();closeModal($('#waypointModal'));pendingWaypointPosition=null;
  const decision=selectDeliveryRoute({type:'waypoint',conversationId:c.id});
  const item=queue.enqueue({type:'waypoint',text:`Точка: ${waypoint.name}`,waypoint,conversationId:c.id},decision);
  getBucket(c.id).push({side:'out',text:waypoint.name,waypoint,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}),status:item.status==='queued'?'В очереди':'Готово к отправке',queueId:item.id});
  renderMessages();renderConversations($('#chatSearch')?.value||'');renderGlobalStatus();renderDeliveryQueue();if(item.status==='ready')await transmitQueueItem(item.id);return item;
}"""
    s=s[:old.start()]+new+s[old.end():]
    s=one(s,
      "      panMapPixels(current.x-previous.x,current.y-previous.y);renderMap({preserveViewport:true});return;",
      "      if(Math.hypot(current.x-previous.x,current.y-previous.y)>2)mapViewport.suppressPointTapUntil=Date.now()+250;panMapPixels(current.x-previous.x,current.y-previous.y);renderMap({preserveViewport:true});return;",
      "pan suppress")
    s=one(s,
      "  const end=e=>{mapViewport.pointers.delete(e.pointerId);if(mapViewport.pointers.size<2)mapViewport.pinch=null;};",
      "  const end=e=>{mapViewport.pointers.delete(e.pointerId);if(mapViewport.pointers.size<2)mapViewport.pinch=null;};\n  canvas.addEventListener('click',e=>{if(e.target.closest('button')||e.detail>1||Date.now()<mapViewport.suppressPointTapUntil)return;const p=unprojectMapScreen(e.clientX,e.clientY);if(p)openWaypointModal(p);});",
      "map click")
    s=s.replace("$('#mapCreateWaypointButton').disabled=!fallback;","$('#mapCreateWaypointButton').disabled=false;",1)
    s=one(s,
      "$('#mapCreateWaypointButton')?.addEventListener('click',openWaypointModal);$('#cancelWaypoint')?.addEventListener('click',()=>{pendingWaypointPosition=null;closeModal($('#waypointModal'));});$('#confirmWaypoint')?.addEventListener('click',()=>sendWaypointFromModal());",
      "$('#mapCreateWaypointButton')?.addEventListener('click',()=>openWaypointModal());$('#cancelWaypoint')?.addEventListener('click',()=>{pendingWaypointPosition=null;closeModal($('#waypointModal'));});$('#saveWaypointLocal')?.addEventListener('click',()=>saveWaypointLocal());$('#confirmWaypoint')?.addEventListener('click',()=>sendWaypointFromModal());",
      "waypoint events")
    # Chat card for waypoint
    needle=" : m.position ? \`<div class=\"position-message\"><strong>⌖ Позиция</strong>"
    if needle not in s: raise SystemExit("missing chat waypoint insertion")
    s=s.replace(needle," : m.waypoint ? \`<div class=\"position-message map-point-message\"><strong>⌖ ${m.waypoint.name||'Точка'}</strong><small>${formatCoords(m.waypoint)}${m.waypoint.description?\` · ${m.waypoint.description}\`:''}</small><button class=\"text-button\" type=\"button\" data-show-map-point=\"1\" data-lat=\"${m.waypoint.latitude}\" data-lon=\"${m.waypoint.longitude}\">Показать на карте →</button></div>\` : m.position ? \`<div class=\"position-message\"><strong>⌖ Позиция</strong>",1)
    s=one(s,
      "  stream.scrollTop = stream.scrollHeight;",
      "  stream.querySelectorAll('[data-show-map-point]').forEach(button=>button.addEventListener('click',()=>{selectedMapNodeNum=0;const p={latitude:Number(button.dataset.lat),longitude:Number(button.dataset.lon)};setMapView(p,Math.max(16,mapViewport.zoom));setView('map');renderMap({preserveViewport:true});}));\n  stream.scrollTop = stream.scrollHeight;",
      "show point handler")
    s=s.replace("getWaypoints:()=>[...sharedWaypoints.values()],sendWaypointFromModal,","getWaypoints:()=>[...sharedWaypoints.values()],openWaypointModal,saveWaypointLocal,sendWaypointFromModal,unprojectMapScreen,",1)
    p.write_text(s,encoding="utf-8")

patch_app(root/"src/app.js")
(root/"android-app/app/src/main/assets/www/src/app.js").write_text((root/"src/app.js").read_text(encoding="utf-8"),encoding="utf-8")

for p in [root/"index.html",root/"android-app/app/src/main/assets/www/index.html"]:
    h=p.read_text(encoding="utf-8").replace(">Создать точку</button>",">Поставить точку</button>",1)
    old="""          <div class="modal-header"><div><p class="eyebrow">Meshtastic waypoint</p><h2 id="waypointTitle">Новая точка</h2></div></div>
          <label class="field-stack"><span>Название</span><input id="waypointName" maxlength="30" placeholder="Точка" /></label>
          <label class="field-stack"><span>Описание</span><input id="waypointDescription" maxlength="100" placeholder="Необязательно" /></label>
          <label class="field-stack"><span>Срок</span><select id="waypointExpire"><option value="3600">1 час</option><option value="21600" selected>6 часов</option><option value="86400">24 часа</option><option value="0">Без срока</option></select></label>
          <p class="modal-copy">Точка будет отправлена в основной mesh-канал через WAYPOINT_APP.</p>
          <div class="modal-actions"><button class="secondary-button" id="cancelWaypoint" type="button">Отмена</button><button class="primary-button" id="confirmWaypoint" type="button">Отправить точку</button></div>"""
    new="""          <div class="modal-header"><div><p class="eyebrow">Карта</p><h2 id="waypointTitle">Новая точка</h2></div></div>
          <div class="pending-card"><strong id="waypointCoords">—</strong><span id="waypointTarget">Получатель не выбран</span></div>
          <label class="field-stack"><span>Название</span><input id="waypointName" maxlength="30" placeholder="Точка" /></label>
          <label class="field-stack"><span>Описание</span><input id="waypointDescription" maxlength="100" placeholder="Необязательно" /></label>
          <label class="field-stack"><span>Срок</span><select id="waypointExpire"><option value="3600">1 час</option><option value="21600" selected>6 часов</option><option value="86400">24 часа</option><option value="0">Без срока</option></select></label>
          <p class="modal-copy">Точка хранится как объект карты и отправляется через Delivery Manager. Транспорт выбирается отдельно.</p>
          <div class="modal-actions"><button class="quiet-button" id="cancelWaypoint" type="button">Отмена</button><button class="secondary-button" id="saveWaypointLocal" type="button">Сохранить</button><button class="primary-button" id="confirmWaypoint" type="button">Отправить</button></div>"""
    h=one(h,old,new,"waypoint modal")
    p.write_text(h,encoding="utf-8")
print("PATCH_MAP_POINTS_V164_PASS")
