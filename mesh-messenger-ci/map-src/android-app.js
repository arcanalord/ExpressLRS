import { TransportManager, MessageQueue, SmallFileTransferManager, SmallFileReceiver, SmallFileTransferPersistence, PositionTrackHistory } from './core.js';
import { MockMeshtasticTransport } from './transports/mock-meshtastic.js';
import { WebSerialMeshtasticTransport } from './transports/web-serial-meshtastic.js';
import { AndroidBridgeMeshtasticTransport } from './transports/android-bridge-meshtastic.js';
import { PhoneApiSession } from './transports/phoneapi-session.js';
import { BROADCAST, PORTNUM, encodeTextToRadio, encodePositionToRadio, encodeWaypointToRadio, encodePortPayloadToRadio, encodeSmallFileManifest, encodeSmallFileChunk, encodeSmallFileStatus, encodeSmallFileStatusRequest, decodeSmallFileFrame, sharedContactUrl, channelSetUrl, parseMeshtasticShareUrl } from './transports/phoneapi-lite.js';
import { HELP_FALLBACK_ID, ERROR_TOPIC_MAP, helpRegistry, parseHelpTopic, buildSafeDiagnostics } from './help-registry.js';

const transportManager = new TransportManager();
const queue = new MessageQueue();
let fileTransfers = new SmallFileTransferManager({maxBytes:32768,chunkBytes:180});
let filePersistence = null;
const fileSendLocks = new Set();
const fileReceiver = new SmallFileReceiver({maxBytes:32768});
const mockRadio = new MockMeshtasticTransport({ connectDelayMs: 0, loopback: false, autoPhoneApi: true });
const webSerialRadio = new WebSerialMeshtasticTransport();
const androidBleRadio = new AndroidBridgeMeshtasticTransport();
let activeRadio = AndroidBridgeMeshtasticTransport.isSupported() ? androidBleRadio : mockRadio;
let phoneApiSession = null;
let currentConversationId = 'channel:0';
let selectedMapNodeNum = 0;
const packetPositions = new Map();
const trackHistory = new PositionTrackHistory({maxPointsPerNode:120});
const sharedWaypoints = new Map();
let pendingWaypointPosition = null;
let mapTileState = 'loading';
let mapTileGeneration = 0;
let qrMode = 'contact';
const importedContacts = new Map();
let pendingQrImport = null;
let currentViewName = 'chats';
let currentHelpTopicId = HELP_FALLBACK_ID;
let helpHistoryPushed = false;
let activeHelpErrorCode = '';
const SCREEN_HELP_TOPICS = Object.freeze({
  chats:'mesh-messenger.chats.messaging',
  map:'mesh-messenger.map.overview',
  network:'mesh-messenger.network.overview',
  settings:'mesh-messenger.settings.overview',
});
try{for(const item of JSON.parse(storageGet('mesh-imported-contacts')||'[]'))if(item?.nodeNum)importedContacts.set(item.nodeNum>>>0,item);}catch{}
const QR_ASSETS={contact:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAjoAAAI6AQAAAAAGM99tAAAFj0lEQVR4nO2dW47jRgxFDyMB/pSALGCWIu9gltSYJWUH1lJ6AQ1Inw3IYD5YL3kCJJhuJzWZWx+C9fBBCaAJ+pKsMudTxvrb53BAIIEEEkgggQQSSCCB/i8gS2PEbL4b63w3Vhux615uxOkI60y5YWbXZ8xIIIE+ONzdncXd3bfB3f2Ia+4bxOltco9DnAIs8XD+7q2/VxNIIGBPztfMLkkuWefB7crgcePldQT2EbtORzxhZuPTZiSQQJ8J8ht3i5Bk8Xfz2z7GNf82A0zJZ4fj/jdmJJBAPzLG765MG7CPwD5jgAEjFnf3GZaN71Xw/l5NoF8alC17cmAHW7b76EwepuzrdThg//2AfTYHMBgiHGntu79XE0ggWM3MbAbYLx4SyLINbi8b2BWwFHEPzhLX7iGNPGlGAgn0oRE+uzpfhwPgbs4O+XC3CLHXeYhT5yEi6e/VBBKIcNLsFiq238heOVzzPIQZ24sfmH1xB+6WpJJnzEgggT44QpNmOoDJHSb3pH5MRzmkR+ppfKrit/RsgfoC5ayMe8TPNWfD4gfuGwCD5/wM+I0h8jMs26BMjUBdgrLLBU7uunjvKScni+MO7x0mPx3IsgXqEdT47Gys2ReHFTN4e43szG85ESnLFqhHUFM3kg8HyUmXR25NFF58th808YssW6C+QEn1W204fLXIymThY3obff36NtoSJSMGyx8jIXkzvUHJ6PT4agL90qCsjdSgw09BdLnhN9riviyV5EBGPlugHkERb4RrBuw6ubO85qq/KCOZjvxpN/PbfnG7clcOUqAuQaUWO6sfETXnv4e5SLu69eM7oVtxtkAdgrLqNyVtJFS/0oPQKtYMXuXtB2Vbli1QZ6DHODvnFr05jefCiksnTc1ayrIF6hDUWvay5fCjpM5p/1rWpGNpGXNlagTqGZQV66NcTz1i7ts9NdZ8m4H1yxEdvqeHnzAjgQT64EhC3pbPw3FnX1xvuPu5QArkswXqF9TW+jU6NdCUjHgTXfujqC3LFqhH0Mmyiw4SWl8tFNlysF1PUxkJqmIVqEtQo4NkN1yED5Iicqr1Ozv4nJeUZQvUGajU+pXKva3Nz7RlUaQbEV3HkOon0E8ASm4YYHKP5c5ecoQCgNmXA1a7lOyNsusC9Qk6r36WZRHyn8fknx/07A0IoRvF2QL1CWoyNaksquTUUxCdr5Hv5moR1Y0I1DHotEbUPuLhi3fw9euGMb3h7DMUJ23Lq5HquPcxh9z9vZpAvzTolKmZPBf8ZQHbS+uMN33qtQ4qy9vy2QJ1Bmotu+Ybm77eXLuaHylN7Q823t+rCfRLgx7j7FbAzmWrzUraZTnt+G4pDJRlC9QZ6OyzT4svNLmYuJu/Ukqz5bMF6hZUOg9qT3oOtuv6OaVjvVFO6s9Ali1Qh6DQRiw+7BcH7iNM99HXr2/msaLwPgIMbjC4rTPm6zxg1Y93+GoCCVTyM+/GOudczPI6nqTsDYC75YDlPe+D8IwZCSTQB0cNP5IOAjT5xpSNhMdesiWXtyoaEahHUFP4lCy2UbHPzepAPaVkKKWNCNQjqFX9Su96rsWuGy2dmyFrYaB6agTqFHRasdKr7ZbIowQdpTQ715eccpWybIF6BNU9fGP73hj7xc3mtPuB++tIWjdqv3hdN8quz5iRQAJ9cLTRdU2nA3mZ7PJHsVZqn5sm5bMF6hD0FznI0ijWaH1Q9/qAavzKQQr0s4CW10tx0lDXZ63Db9O7eS0CvD15RgIJ9Amg2Jg65WzAv1lKTiblZB+xa2wZecnrbD93RgIJ9EPjMc6uC+Y0Xb+e8jjtfjbloDhboH5BZQ/f3NcLsQtkpGvq+tlTu4i2vbxqP0iB+gSZ//0z/2Ss/b2aQAIJJJBAAgkkkEAC/WegPwFFi9jj/BPloAAAAABJRU5ErkJggg==',channel:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAeoAAAHqAQAAAADjFjCXAAAELklEQVR4nO2dS26rShBATz2QPGykLCBLae/gLekqS7o7gKV4AZaaoSVQvUF/ycvIcJX4UjVwsOGoQSrVn44oO2T6Zw8NhhtuuOGGG2644YYfi0uSHqYB5Dr38YNpWCUeMYvAnC+9Hre64WfD+/jHjwDzG/iw9goLOr0viA8r4B6iOAXoFgDkkNUNPyeetI55AP8bgC6mtYIDnaRTmN9UADSeyKr33Tdv+N+CTyLCJD3AKsAqIu8P0ZFO5fqHVzf8FHj/+QcfBgR3F/y4Au4eLxHcXZT50NUNPyeOqqriVVU1dApOFR86VQ2gGjrVEcAHSCcKMb70sxv+zfgkIiID4G/J/Mk1u1T5FTolBXxrTGEPXd3wk+FRxWpbTOEhOg0dOg2kI2bS1/bSA1Y3/Jx48bALOtJlX6sL0cOOTpOZiy7VLZGIYh7W8Kck6U8AcAtZrxZihIfbBnyqMcwzrTN8h0RbF61ZVK6lnEj2L37Er81Z0zrDd+GqYRX9eH9IzCZ8TR/cIxXtrvNF8bc+ul65Hre64WfDSzFu6cXfLirTuyK4BaZ/7z24TsEFJOlfulgPWd3wc+JtNqElaBuBFNdBivVKXhHdrNXrDH9eUlwX47XUgt0kDUtWwhr61Ute+tkN/148WTj3kKhmH8MqQKexclwKxDqySk0pfsbNG/5yeLF12Ztq6LRtfIWu+N+FxhNbDmv485KjuVyRowZtuXyHz+W7VDkG87CG75FquPCBXKAr6YMPndYji+sMPwLPtu5TW4KSSLjSpQCSYjrzsIbvkhq+xbZYTV/H7FJz06LktaGzSSfD90g2WwuxD5sa/6kFFqfqYl0lWz2r1xl+oIctTf7qXFMLtiSyKcKzPqzhuySZugDNuBPkWeKS3KaxlHLCtM7w5yXV6yDPqG9Urxl3aibtgmmd4bska10pkGxNX3OWtq5icZ3hO6StEtdSXWPrljIgUHJdNa0zfJf8L4cNxa65r2dO8pC7aZ3hu3C50in+dlGRYRVwqvIrrNJOcAJ10vjI1Q0/G76ZqstlkfoGRe6DQc5caw/DbJ3hz8omaMs/btv9qRlbXp5oehgv/eyGfxde6nWd1kAunhibvLbMfNaxANM6w5+V9N6E/72KMvcLuHt+KcIFJNq/+U0FF4C5T5s9HbK64efE2xlNLbWRETajdVFS+tpgZusMfx6ve3XmF3WWuOOJfsglVfN8WAXm/gt85+qGnw3/ek8noDTIynxxnm+qR2brDN+Fz2mrYdVbz6dXxlRvl6R6k4i0RbufcfOGvxj+eddEAUSZLwozMAlx61idhnsPdIs0l7/0sxv+U/A82vQQuW77EHGzCV3ivux/ZnXDz4F/jus2U3V1eFjzhp3WmzB8P97O1zUDdbkPESVmDq6+t2haZ/geEfvvdYYbbrjhhhtuuOF/Bf4fr0I6dp6SxVIAAAAASUVORK5CYII='};
const conversationUi = new Map([
  ['channel:0',{unread:0,muted:false}],
  ['channel:1',{unread:4,muted:true}],
  ['direct:2952855554',{unread:0,muted:false}],
]);

const messageBuckets = new Map([
  ['channel:0', [
    { side:'in', author:'Иван', text:'Узел B на связи. Подхожу к точке.', time:'07:19' },
    { side:'out', text:'Принял. Координаты вижу.', time:'07:20', status:'Доставлено' },
    { side:'in', author:'Иван', text:'Остаюсь на основном канале.', time:'07:22' },
  ]],
  ['direct:2952855554', [
    { side:'in', author:'Узел B', text:'Личный канал связи готов.', time:'07:18' },
  ]],
]);

const $ = (sel, root=document) => root.querySelector(sel);
const $$ = (sel, root=document) => [...root.querySelectorAll(sel)];
const storageGet = key => { try { return localStorage.getItem(key); } catch { return null; } };
const storageSet = (key, value) => { try { localStorage.setItem(key, value); } catch {} };

const storageRemove = key => { try { localStorage.removeItem(key); } catch {} };
function persistTrackHistory(){try{storageSet('mesh-position-tracks-v1',JSON.stringify(trackHistory.serialize()));}catch{}}
function restoreTrackHistory(){try{trackHistory.restore(JSON.parse(storageGet('mesh-position-tracks-v1')||'[]'));}catch{}}
function persistWaypoints(){try{storageSet('mesh-waypoints-v1',JSON.stringify([...sharedWaypoints.values()]));}catch{}}
function restoreWaypoints(){try{for(const w of JSON.parse(storageGet('mesh-waypoints-v1')||'[]'))if(w?.id)sharedWaypoints.set(w.id>>>0,w);}catch{}}
restoreTrackHistory();restoreWaypoints();
const transferStorage = globalThis.__meshTransferStorage || {getItem:storageGet,setItem:storageSet,removeItem:storageRemove};
filePersistence = new SmallFileTransferPersistence(transferStorage,{maxItems:8,maxBytes:262144});
currentConversationId = storageGet('mesh-current-conversation') || currentConversationId;
function persistFileTransfers(){try{filePersistence.save(fileTransfers);}catch{}}
function restoreFileTransfers(){try{return fileTransfers.restoreMany(filePersistence.load());}catch{return[];}}
const restoredTransfers = restoreFileTransfers();
function formatEta(seconds){if(seconds==null)return 'ETA —';if(seconds<=1)return 'ETA <1 с';const m=Math.floor(seconds/60),s=seconds%60;return m?`ETA ~${m}:${String(s).padStart(2,'0')}`:`ETA ~${s} с`;}
function findFileMessage(id){for(const bucket of messageBuckets.values()){const m=bucket.find(x=>x.file?.id===Number(id));if(m)return m;}return null;}
function fileStatusText(t){
  const confirmed=fileTransfers.confirmedCount(t.id), eta=fileTransfers.etaSeconds(t.id,transportManager.get('meshtastic')?.bitrate||1.1);
  if(t.status==='complete')return `Получено · SHA-256 OK`;
  if(t.status==='paused')return `Пауза · подтверждено ${confirmed}/${t.total}`;
  if(t.status==='checking-remote')return `Проверяем полученные чанки…`;
  if(t.status==='resuming')return `Возобновление · ${confirmed}/${t.total} · ${formatEta(eta)}`;
  if(t.status==='awaiting-confirmation')return `Ждём подтверждение · ${confirmed}/${t.total}`;
  if(t.status==='failed')return `Ошибка файла: ${t.error||'UNKNOWN'}`;
  return `Передача · ${confirmed}/${t.total} · ${formatEta(eta)}`;
}
function refreshFileMessage(t){const m=findFileMessage(t.id);if(m){m.file=t;m.status=fileStatusText(t);}if(m&&m===getBucket().find(x=>x.file?.id===t.id))renderMessages();persistFileTransfers();return m;}
for(const t of restoredTransfers){
  if(!t.conversationId)continue;
  const bucket=getBucket(t.conversationId);
  if(!bucket.some(m=>m.file?.id===t.id))bucket.push({side:'out',text:`Файл ${t.name}`,time:new Date(t.createdAt).toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}),status:`Восстановлено · ${fileStatusText(t)}`,file:t});
}

function initTheme() {
  const requested = new URLSearchParams(location.search).get('theme');
  const stored = storageGet('mesh-theme');
  const theme = requested || stored || 'light';
  document.documentElement.dataset.theme = theme === 'dark' ? 'dark' : 'light';
}
function toggleTheme() {
  const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  storageSet('mesh-theme', next);
}

function setView(name) {
  currentViewName = name;
  $$('.view').forEach(v => v.classList.toggle('is-active', v.dataset.screen === name));
  $$('[data-nav] [data-view]').forEach(b => b.classList.toggle('is-active', b.dataset.view === name));
  window.scrollTo({top:0, behavior:'instant'});
  if (name === 'network') renderRoute();
  if (name === 'map') renderMap();
}

function helpCategoryLabel(category){
  return ({start:'\u0411\u044b\u0441\u0442\u0440\u044b\u0439 \u0441\u0442\u0430\u0440\u0442',chats:'\u0427\u0430\u0442\u044b',map:'\u041a\u0430\u0440\u0442\u0430',network:'\u0421\u0432\u044f\u0437\u044c',share:'QR',settings:'\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438',errors:'\u041e\u0448\u0438\u0431\u043a\u0438'})[category] || category || '';
}
function currentScreenHelpTopic(){ return SCREEN_HELP_TOPICS[currentViewName] || HELP_FALLBACK_ID; }
function setNetworkDetails(open){
  const screen=document.querySelector('[data-screen="network"]'); if(!screen)return;
  screen.classList.toggle('show-network-details',Boolean(open));
  const button=$('#networkDetailsToggle'); if(button){button.setAttribute('aria-expanded',String(Boolean(open)));button.textContent=open?'Скрыть детали':'Детали';}
}
function toggleNetworkDetails(){
  const screen=document.querySelector('[data-screen="network"]');
  setNetworkDetails(!screen?.classList.contains('show-network-details'));
}
function renderHelpSteps(target,steps=[]){
  if(!target)return; target.innerHTML='';
  for(const step of steps||[]){const li=document.createElement('li');li.textContent=step;target.appendChild(li);}
  target.hidden=!steps?.length;
}
function renderQuickHelp(topicId=currentScreenHelpTopic()){
  const topic=helpRegistry.get(topicId); currentHelpTopicId=topic.id;
  $('#quickHelpEyebrow').textContent='QUICK HELP';
  $('#quickHelpTitle').textContent=topic.title;
  $('#quickHelpSummary').textContent=topic.summary;
  renderHelpSteps($('#quickHelpSteps'),topic.quickSteps||[]);
  $('#openFullHelp').textContent='\u041f\u043e\u0434\u0440\u043e\u0431\u043d\u0430\u044f \u0441\u043f\u0440\u0430\u0432\u043a\u0430';
  openModal($('#quickHelpModal'));
}
function helpSearchResults(query=''){ return helpRegistry.search(query); }
function renderHelpTopicList(query=''){
  const list=$('#helpTopicList'); if(!list)return; list.innerHTML='';
  const topics=helpSearchResults(query);
  if(!topics.length){const empty=document.createElement('div');empty.className='help-empty';empty.textContent='\u041d\u0438\u0447\u0435\u0433\u043e \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u043e';list.appendChild(empty);return;}
  for(const topic of topics){
    const b=document.createElement('button');b.type='button';b.className=`help-topic-button ${topic.id===currentHelpTopicId?'is-active':''}`;
    const strong=document.createElement('strong');strong.textContent=topic.title;
    const small=document.createElement('small');small.textContent=helpCategoryLabel(topic.category);
    b.append(strong,small);b.addEventListener('click',()=>{renderHelpArticle(topic.id);renderHelpTopicList($('#helpSearchInput')?.value||'');setHelpUrl(topic.id,'replace');});list.appendChild(b);
  }
}
function renderHelpArticle(topicId){
  const topic=helpRegistry.get(topicId); currentHelpTopicId=topic.id;
  $('#helpArticleCategory').textContent=helpCategoryLabel(topic.category);
  $('#helpArticleTitle').textContent=topic.title;
  $('#helpArticleSummary').textContent=topic.summary;
  $('#helpArticleBody').textContent=topic.body;
  $('#helpArticleId').textContent=topic.id;
  renderHelpSteps($('#helpArticleSteps'),topic.quickSteps||[]);
  $('#fullHelpContext').textContent=topic.id;
  $('#copySafeDiagnostics').textContent='\u0421\u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u0442\u044c \u0431\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u0443\u044e \u0434\u0438\u0430\u0433\u043d\u043e\u0441\u0442\u0438\u043a\u0443';
}
function setHelpUrl(topicId,mode='push'){
  try{const url=new URL(location.href);url.searchParams.set('topic',topicId);history[mode==='replace'?'replaceState':'pushState']({meshHelp:true,topicId},'',url);}
  catch{}
}
function clearHelpUrl(){
  try{const url=new URL(location.href);url.searchParams.delete('topic');history.replaceState(history.state||{},'',url);}
  catch{}
}
function openFullHelp(topicId=currentHelpTopicId,{pushHistory=true}={}){
  const topic=helpRegistry.get(topicId); currentHelpTopicId=topic.id;
  closeModal($('#quickHelpModal'));
  $('#fullHelpEyebrow').textContent='FULL HELP';
  $('#fullHelpTitle').textContent='\u0421\u043f\u0440\u0430\u0432\u043a\u0430';
  $('#helpSearchInput').placeholder='\u041f\u043e\u0438\u0441\u043a \u043f\u043e \u0442\u0435\u043c\u0430\u043c, \u043e\u0448\u0438\u0431\u043a\u0430\u043c \u0438 \u043f\u0430\u0440\u0430\u043c\u0435\u0442\u0440\u0430\u043c';
  $('#helpSearchInput').value='';
  renderHelpArticle(topic.id); renderHelpTopicList(''); openModal($('#fullHelpModal'));
  if(pushHistory){setHelpUrl(topic.id,'push');helpHistoryPushed=true;}else helpHistoryPushed=false;
}
function closeFullHelpFromUi(){
  closeModal($('#fullHelpModal'));
  if(helpHistoryPushed && parseHelpTopic(location.search)){helpHistoryPushed=false;history.back();}
  else {helpHistoryPushed=false;clearHelpUrl();}
}
function setBleErrorHelp(errorCode=''){
  activeHelpErrorCode=errorCode; const box=$('#bleErrorHelp'); if(!box)return;
  if(!errorCode){box.hidden=true;return;}
  const topic=helpRegistry.resolve(errorCode);box.hidden=false;$('#bleErrorHelpText').textContent=topic.summary;$('#bleErrorHelpButton').textContent='\u041f\u043e\u0434\u0440\u043e\u0431\u043d\u0435\u0435';
}
function safeDiagnostics(){
  return buildSafeDiagnostics({
    appVersion:'1.5.5',
    platform:navigator.platform||'web',
    runtime:navigator.userAgent||'browser',
    transport:activeRadio?.id||'none',
    phoneApiState:phoneApiSession?.state||'none',
    errorCode:activeHelpErrorCode,
    capabilities:{webSerial:Boolean(navigator.serial),androidBridge:AndroidBridgeMeshtasticTransport.isSupported(),serviceWorker:'serviceWorker' in navigator}
  });
}
async function copySafeDiagnostics(){
  const text=JSON.stringify(safeDiagnostics(),null,2); const button=$('#copySafeDiagnostics');
  try{await navigator.clipboard.writeText(text);}catch{const ta=document.createElement('textarea');ta.value=text;ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();document.execCommand('copy');ta.remove();}
  if(button){const previous=button.textContent;button.textContent='\u0421\u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u043d\u043e';setTimeout(()=>button.textContent=previous,900);}
  return text;
}

function formatNodeNum(num) { return `!${(num >>> 0).toString(16).padStart(8,'0')}`; }
function currentSnapshot() { return phoneApiSession?.snapshot() || null; }
function getBucket(id=currentConversationId) { if(!messageBuckets.has(id)) messageBuckets.set(id,[]); return messageBuckets.get(id); }
function getLastMessage(id){ const b=messageBuckets.get(id)||[]; return b.at(-1) || null; }
function channelTitle(channel){ return channel?.settings?.name || (channel?.role===1 ? 'Основной канал' : `Канал ${(channel?.index ?? 0)+1}`); }
function uiState(id, defaults={}) { if(!conversationUi.has(id))conversationUi.set(id,{unread:0,muted:false,...defaults}); return conversationUi.get(id); }
function latestDeliveryStatus(id){ const b=messageBuckets.get(id)||[]; const out=[...b].reverse().find(x=>x.side==='out'&&x.status); return out?.status||''; }
function kindLabel(kind){ return kind==='direct'?'Лично':'Канал'; }

function buildConversations(snapshot=currentSnapshot()) {
  const result=[];
  if(snapshot?.channels?.length){
    for(const ch of snapshot.channels.filter(x=>x.role!==0)){
      const id=`channel:${ch.index}`; const last=getLastMessage(id);
      const ui=uiState(id,{muted:Boolean(ch.settings?.isMuted)}); if(ch.settings?.isMuted)ui.muted=true;
      result.push({id,kind:'channel',channel:ch.index,title:channelTitle(ch),subtitle:`${ch.roleLabel} · канал ${ch.index}`,preview:last?.text || 'Групповой Meshtastic-канал',time:last?.time || '',route:'Mesh',unread:ui.unread||0,muted:Boolean(ui.muted),delivery:''});
    }
  } else {
    const ui=uiState('channel:0');
    result.push({id:'channel:0',kind:'channel',channel:0,title:'Основной канал',subtitle:'PRIMARY · канал 0',preview:getLastMessage('channel:0')?.text||'Meshtastic канал',time:'07:24',route:'Mesh',unread:ui.unread||0,muted:Boolean(ui.muted),delivery:''});
  }
  const local=snapshot?.myInfo?.myNodeNum;
  const nodes=(snapshot?.nodes||[]).filter(n=>n.num!==local && !n.isIgnored && n.user?.isUnmessagable!==true);
  for(const n of nodes){
    const id=`direct:${n.num>>>0}`; const last=getLastMessage(id);
    const ui=uiState(id);
    result.push({id,kind:'direct',nodeNum:n.num>>>0,channel:n.channel||0,title:n.user?.longName||n.user?.shortName||formatNodeNum(n.num),subtitle:`${formatNodeNum(n.num)} · ${n.hopsAway ?? '—'} hops · ${n.snr==null?'SNR —':`SNR ${n.snr.toFixed(1)} dB`}`,preview:last?.text||'Личное сообщение',time:last?.time||'',route:'Mesh',unread:ui.unread||0,muted:Boolean(ui.muted),delivery:latestDeliveryStatus(id)});
  }
  for(const c of importedContacts.values()){
    const id=`direct:${c.nodeNum>>>0}`;if(result.some(x=>x.id===id))continue;
    const last=getLastMessage(id),ui=uiState(id);
    result.push({id,kind:'direct',nodeNum:c.nodeNum>>>0,channel:0,title:c.longName||c.shortName||formatNodeNum(c.nodeNum),subtitle:`${formatNodeNum(c.nodeNum)} · QR contact`,preview:last?.text||'Импортированный контакт',time:last?.time||'',route:'Mesh',unread:ui.unread||0,muted:Boolean(ui.muted),delivery:latestDeliveryStatus(id)});
  }
  if(!result.some(x=>x.id===currentConversationId)){
    const keepDuringSync=/^(syncing|rebooted)$/.test(phoneApiSession?.state||'') && currentConversationId.startsWith('direct:');
    if(keepDuringSync){
      const nodeNum=Number(currentConversationId.split(':')[1])>>>0,last=getLastMessage(currentConversationId),ui=uiState(currentConversationId);
      result.push({id:currentConversationId,kind:'direct',nodeNum,channel:0,title:last?.author||formatNodeNum(nodeNum),subtitle:`${formatNodeNum(nodeNum)} · синхронизация…`,preview:last?.text||'Личное сообщение',time:last?.time||'',route:'Mesh',unread:ui.unread||0,muted:Boolean(ui.muted),delivery:latestDeliveryStatus(currentConversationId)});
    } else currentConversationId=result[0]?.id || 'channel:0';
  }
  return result;
}
function currentConversation(){ const list=buildConversations();return list.find(x=>x.id===currentConversationId) || list[0]; }

function renderConversations(filter='') {
  const list = $('#conversationList');
  list.innerHTML = '';
  const conversations=buildConversations();
  conversations.filter(c => `${c.title} ${c.preview}`.toLowerCase().includes(filter.toLowerCase())).forEach(c => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `conversation-row ${c.id===currentConversationId?'is-active':''}`;
    const deliveryClass=statusClass(c.delivery);
    button.innerHTML = `
      <span class="avatar">${c.kind==='channel'?'#':c.title.slice(0,1)}</span>
      <span class="conversation-copy"><span class="conversation-title-line"><strong>${c.title}</strong><span class="kind-chip ${c.kind}">${kindLabel(c.kind)}</span>${c.muted?'<span class="mute-chip" title="Без уведомлений">mute</span>':''}</span><small class="conversation-subtitle">${c.subtitle}</small><small>${c.preview}</small></span>
      <span class="conversation-meta"><time>${c.time}</time>${c.unread?`<span class="unread-badge">${c.unread}</span>`:''}${c.delivery?`<small class="delivery-chip ${deliveryClass}">${c.delivery}</small>`:''}</span>`;
    button.addEventListener('click', () => selectConversation(c.id));
    list.append(button);
  });
}

function selectConversation(id){
  currentConversationId=id; storageSet('mesh-current-conversation',id); const ui=uiState(id); ui.unread=0; renderConversationHeader(); renderConversations($('#chatSearch')?.value||''); renderMessages();
  const mobile=globalThis.matchMedia?.('(max-width: 760px)')?.matches;
  if(mobile){
    const screen=document.querySelector('[data-screen="chats"]');
    screen?.classList.add('mobile-conversation-open');
    requestAnimationFrame(()=>screen?.scrollIntoView({behavior:'smooth',block:'start'}));
  } else $('#messageInput')?.focus();
}

function renderConversationHeader(){
  const c=currentConversation(); if(!c)return;
  $('#conversationTitle').textContent=c.title;
  const span=$('#conversationTitle')?.parentElement?.querySelector('span');
  if(span) span.innerHTML=`<span class="status-dot ok"></span> ${c.kind==='direct' ? `Лично · ${c.subtitle}` : `Канал ${c.channel} · ${c.subtitle}`}`;
}

function statusClass(status=''){
  if(/Ошибка|NAK|нет маршрута/i.test(status))return 'status-error';
  if(/очеред|ждём|отправка/i.test(status))return 'status-warn';
  return '';
}
function renderMessages() {
  const stream = $('#messageStream');
  stream.innerHTML = '<div class="day-label">Сегодня</div>';
  getBucket().forEach(m => {
    const row = document.createElement('div');
    row.className = `message-row ${m.side === 'out' ? 'out' : 'in'}`;
    row.innerHTML = `
      <div class="message-bubble">
        ${m.author ? `<strong class="message-author">${m.author}</strong>` : ''}
        ${m.file ? `<div class="file-message"><strong>📎 ${m.file.name}</strong><small>${formatBytes(m.file.size)} · ${m.file.total} чанков · SHA-256</small><div class="file-progress"><span style="width:${Math.round((((Array.isArray(m.file.confirmed)?m.file.confirmed.filter(Boolean).length:(m.file.received||m.file.sent||0)))/Math.max(1,m.file.total))*100)}%"></span></div>${m.file.url?`<a class="file-download" href="${m.file.url}" download="${m.file.name}">Сохранить</a>`:''}</div>` : m.position ? `<div class="position-message"><strong>⌖ Позиция</strong><small>${formatCoords(m.position)}${m.position.altitude!=null?` · ${Math.round(m.position.altitude)} м`:''}</small><button class="text-button" type="button" data-show-position="${m.positionNodeNum||0}" data-lat="${m.position.latitude}" data-lon="${m.position.longitude}">Показать на карте →</button></div>` : `<p>${m.text}</p>`}
        <div class="message-meta"><time>${m.time}</time><span class="message-status-actions">${m.status ? `<span class="${statusClass(m.status)}">${m.status}</span>` : ''}${m.queueId && /Ошибка|NO_ROUTE|TIMEOUT|MAX_RETRANSMIT|NO_CHANNEL/i.test(m.status||'') ? `<button type="button" class="retry-message" data-retry-queue="${m.queueId}">Повторить</button>` : ''}</span></div>
      </div>`;
    stream.append(row);
  });
  stream.querySelectorAll('[data-retry-queue]').forEach(button=>button.addEventListener('click',()=>retryQueueItem(button.dataset.retryQueue)));
  stream.querySelectorAll('[data-show-position]').forEach(button=>button.addEventListener('click',()=>{const num=Number(button.dataset.showPosition)||0;if(num)selectedMapNodeNum=num;setView('map');renderMap({fallback:{latitude:Number(button.dataset.lat),longitude:Number(button.dataset.lon)}});}));
  stream.scrollTop = stream.scrollHeight;
}
function updateMessageByQueueId(queueId, patch){
  for(const bucket of messageBuckets.values()){
    const m=bucket.find(x=>x.queueId===queueId); if(m){Object.assign(m,patch); if(bucket===getBucket())renderMessages(); return m;}
  }
  return null;
}

function formatLatency(ms) { return ms < 100 ? `~${ms} ms` : `~${Math.round(ms/100)*100} ms`; }
function radioStateCopy(snapshot) {
  if (snapshot.state === 'connected') return snapshot.id === 'meshtastic-mock' ? 'Симулятор подключён' : snapshot.id === 'meshtastic-android-ble' ? 'BLE-узел подключён' : 'USB-радио подключено';
  if (snapshot.state === 'connecting') return 'Подключаем…';
  if (snapshot.state === 'error') return `Ошибка: ${snapshot.error || 'соединение не установлено'}`;
  return 'Радио отключено';
}

function renderRadioState(snapshot = activeRadio.snapshot()) {
  const card = $('#radioLinkCard'); if (!card) return;
  card.dataset.state = snapshot.state;
  $('#radioConnectionState').textContent = radioStateCopy(snapshot);
  $('#radioAdapterName').textContent = snapshot.id === 'meshtastic-mock' ? 'MOCK' : snapshot.id === 'meshtastic-android-ble' ? 'ANDROID BLE' : 'WEB SERIAL';
  $('#radioRuntimeHint').textContent = snapshot.id === 'meshtastic-mock'
    ? 'Linux QA использует тот же transport contract без физического радио.'
    : snapshot.id === 'meshtastic-android-ble' ? (snapshot.state === 'connected' ? 'PhoneAPI идёт через Android BluetoothGatt; service держит BLE при сворачивании.' : 'Android BLE использует системные разрешения и последний известный узел.')
    : snapshot.state === 'connected' ? 'Поток PhoneAPI идёт через Web Serial; NodeDB/config decode включён.' : 'USB требует Chromium/Web Serial и разрешение пользователя.';
  $('#serialCapability').textContent = AndroidBridgeMeshtasticTransport.isSupported() ? 'Android BLE: доступен' : (WebSerialMeshtasticTransport.isSupported() ? 'Web Serial: доступен' : 'Web Serial: недоступен в этом runtime');
  transportManager.setAvailable('meshtastic', snapshot.state === 'connected');
  if(snapshot.state==='disconnected'||snapshot.state==='error')pauseActiveFileTransfers(snapshot.error||'link-down');
  if(snapshot.state==='connecting')renderSystemBanner('connecting');
  else if(snapshot.state==='disconnected')renderSystemBanner('disconnected');
  else if(snapshot.state==='error')renderSystemBanner('error',snapshot.error||'');
  renderTransportCards(); renderGlobalStatus(); renderRoute(); renderDeliveryQueue();
}

function closePhoneApiSession() {
  phoneApiSession?.close(); phoneApiSession = null; renderPhoneApiSnapshot(null);
  if ($('#phoneApiCapability')) $('#phoneApiCapability').textContent = 'PhoneAPI: не синхронизирован';
}
function renderSystemBanner(state='disconnected', detail='') {
  const banner=$('#systemBanner'); if(!banner)return;
  banner.className='system-banner';
  const copy={
    disconnected:['Meshtastic не подключён','Подключите узел по Bluetooth или USB. Интернет для mesh не нужен.'],
    connecting:['CONNECTING · подключаем устройство','Открываем device link и ждём PhoneAPI.'],
    syncing:['SYNCING · получаем данные узла','Чаты доступны, новые сообщения пока остаются в очереди.'],
    rebooted:['RESYNC · узел перезагрузился','Восстанавливаем каналы и NodeDB · очередь сохранена.'],
    ready:['READY · Meshtastic работает','Каналы и NodeDB синхронизированы.'],
    error:['ERROR · синхронизация не завершена','Можно повторить подключение; локальные сообщения не потеряны.']
  };
  const [title,base]=copy[state]||copy.disconnected; banner.classList.add(`is-${state}`); $('#systemBannerTitle').textContent=title; $('#systemBannerDetail').textContent=detail||base;
}

function renderPhoneApiSnapshot(snapshot = currentSnapshot()) {
  if (!snapshot) {
    $('#localNodeValue').textContent='—'; $('#firmwareValue').textContent='—'; $('#loraConfigValue').textContent='—'; $('#nodeDbValue').textContent='0'; $('#channelCountValue').textContent='0';
    $('#nodeSnapshotList').innerHTML='<div class="node-empty">Нет синхронизированных узлов</div>'; $('#channelSnapshotList').innerHTML='<div class="node-empty">Нет синхронизированных каналов</div>'; return;
  }
  const local=snapshot.myInfo, meta=snapshot.metadata, lora=snapshot.configs?.lora;
  $('#localNodeValue').textContent=local?.myNodeNum?formatNodeNum(local.myNodeNum):'—';
  $('#firmwareValue').textContent=meta?.firmwareVersion||local?.pioEnv||'—';
  $('#loraConfigValue').textContent=lora?`${lora.regionLabel} · ${lora.modemPresetLabel} · hop ${lora.hopLimit}`:'—';
  $('#nodeDbValue').textContent=String(snapshot.nodes?.length||local?.nodeDbCount||0);
  $('#channelCountValue').textContent=String(snapshot.channels?.filter(x=>x.role!==0).length||0);
  $('#nodeCount').textContent=`${snapshot.nodes?.length||0} узлов`;
  const meshTransport=transportManager.get('meshtastic'); if(meshTransport) meshTransport.detail=`LoRa · ${snapshot.nodes?.length||0} узлов · ${snapshot.channels?.filter(x=>x.role!==0).length||0} каналов`;
  const chatCount=document.querySelector('.desktop-rail [data-view="chats"] small'); if(chatCount) chatCount.textContent=String(buildConversations(snapshot).length);
  for(const n of snapshot.nodes||[])if(n.position?.latitude!=null&&n.position?.longitude!=null)trackHistory.append(n.num>>>0,n.position);
  persistTrackHistory();
  renderTransportCards();
  renderMap();

  const channels=$('#channelSnapshotList'); channels.innerHTML='';
  const enabled=(snapshot.channels||[]).filter(x=>x.role!==0);
  if(!enabled.length) channels.innerHTML='<div class="node-empty">Каналы ещё синхронизируются…</div>';
  for(const ch of enabled){
    const row=document.createElement('div');row.className='channel-snapshot-row';
    row.innerHTML=`<div><strong>#${ch.index} · ${channelTitle(ch)}</strong><small>${ch.settings?.useAead?'AEAD · ':''}${ch.settings?.hasPsk?'ключ настроен':'без ключа'}${ch.settings?.isMuted?' · muted':''}</small></div><span class="channel-role">${ch.roleLabel}</span>`;channels.append(row);
  }

  const list=$('#nodeSnapshotList'); list.innerHTML='';
  const nodes=[...(snapshot.nodes||[])].sort((a,b)=>(a.hopsAway??99)-(b.hopsAway??99));
  if(!nodes.length){list.innerHTML='<div class="node-empty">NodeDB ещё синхронизируется…</div>';return;}
  for(const node of nodes){
    const row=document.createElement('div');row.className='node-snapshot-row';
    const name=node.user?.longName||node.user?.shortName||formatNodeNum(node.num), battery=node.deviceMetrics?.batteryLevel;
    row.innerHTML=`<div><strong>${name}</strong><small>${node.user?.id||formatNodeNum(node.num)}</small></div><div class="node-metrics"><span>${node.snr==null?'SNR —':`SNR ${node.snr.toFixed(1)} dB`}</span><span>${node.hopsAway==null?'hops —':`${node.hopsAway} hops`}</span><span>${battery==null?'bat —':battery>100?'питание':`${battery}%`}</span></div>`;list.append(row);
  }
}

async function syncPhoneApi() {
  closePhoneApiSession();
  phoneApiSession = new PhoneApiSession(activeRadio,{autoResync:true,resyncDelayMs:80,syncTimeoutMs:4000});
  phoneApiSession.onEvent(event => {
    if (event.type === 'state' && $('#phoneApiCapability')) {
      const labels={syncing:'PhoneAPI: синхронизация…',ready:'PhoneAPI: READY',rebooted:'PhoneAPI: reboot → resync…',error:'PhoneAPI: ошибка синхронизации'};
      $('#phoneApiCapability').textContent=labels[event.state]||`PhoneAPI: ${event.state}`;
      renderSystemBanner(event.state);
      if(event.state==='ready'){renderConversations();renderConversationHeader();renderMap();flushQueuedMessages();resumeIncompleteFileTransfers().catch(()=>{});}
    }
    if (event.snapshot) renderPhoneApiSnapshot(event.snapshot);
    if (event.type === 'delivery') handleDeliveryEvent(event);
    if (event.type === 'from_radio' && event.message?.type === 'packet') handleInboundPacket(event.message.packet,event.snapshot);
  });
  try { await phoneApiSession.requestConfig(); }
  catch (error) { if ($('#phoneApiCapability')) $('#phoneApiCapability').textContent=`PhoneAPI: ошибка ${error?.message||error}`; }
}

function handleDeliveryEvent(event){
  const item=queue.byPacketId(event.packetId); if(!item)return;
  if(event.ok){queue.markDelivered(item.id);updateMessageByQueueId(item.id,{status:'Доставлено'});}
  else {queue.markFailed(item.id,event.errorLabel);updateMessageByQueueId(item.id,{status:`Ошибка: ${event.errorLabel}`});}
  renderConversations($('#chatSearch')?.value||''); renderGlobalStatus();renderRoute();renderDeliveryQueue();
}

async function handleInboundPacket(packet,snapshot){
  if(packet?.decoded?.portnum===PORTNUM.PRIVATE_APP){ await handleInboundFilePacket(packet,snapshot); return; }
  const local=snapshot?.myInfo?.myNodeNum;
  if(!packet.from || packet.from===local)return;
  const node=snapshot?.nodes?.find(n=>n.num===packet.from);
  if(packet?.decoded?.portnum===PORTNUM.WAYPOINT_APP && packet.decoded.waypoint?.latitude!=null && packet.decoded.waypoint?.longitude!=null){
    const w={...packet.decoded.waypoint,sourceNode:packet.from>>>0,receivedAt:Date.now()};sharedWaypoints.set(w.id>>>0,w);persistWaypoints();renderMap();
    if(AndroidBridgeMeshtasticTransport.isSupported()&&document.hidden)androidBleRadio.notify(node?.user?.longName||'Mesh Messenger',`Новая точка: ${w.name||formatCoords(w)}`,'waypoint','');
    return;
  }
  const id=packet.to===local ? `direct:${packet.from>>>0}` : `channel:${packet.channel||0}`;
  const bucket=getBucket(id);
  if(packet?.decoded?.portnum===PORTNUM.POSITION_APP && packet.decoded.position?.latitude!=null && packet.decoded.position?.longitude!=null){
    const position=packet.decoded.position;packetPositions.set(packet.from>>>0,position);trackHistory.append(packet.from>>>0,position);persistTrackHistory();
    bucket.push({side:'in',author:node?.user?.longName||node?.user?.shortName||formatNodeNum(packet.from),text:'Позиция',position,positionNodeNum:packet.from>>>0,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})});
    renderMap();
  } else {
    const text=packet?.decoded?.text; if(!text)return;
    bucket.push({side:'in',author:node?.user?.longName||node?.user?.shortName||formatNodeNum(packet.from),text,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})});
  }
  if(id!==currentConversationId)uiState(id).unread=(uiState(id).unread||0)+1;
  if(AndroidBridgeMeshtasticTransport.isSupported() && (document.hidden || id!==currentConversationId)){const latest=bucket.at(-1);androidBleRadio.notify(latest?.author||'Mesh Messenger',latest?.position?'Получена позиция':latest?.text||'Новое сообщение','message',id);}
  renderConversations($('#chatSearch')?.value||''); if(id===currentConversationId)renderMessages();
}

async function activateRadio(radio,options={}) {
  if (activeRadio !== radio && activeRadio.state !== 'disconnected') { try { await activeRadio.disconnect(); } catch {} }
  activeRadio=radio; renderRadioState(activeRadio.snapshot());
  try {
    if(options.deviceId && typeof activeRadio.connectDevice==='function') await activeRadio.connectDevice(options.deviceId); else await activeRadio.connect();
    await syncPhoneApi();
  } catch(error) { renderRadioState(activeRadio.snapshot()); throw error; }
}

function renderTransportCards() {
  const holder=$('#transportCards'); holder.innerHTML='';
  transportManager.list().forEach(t=>{
    const card=document.createElement('div'); card.className=`transport-card ${t.available?'available':''}`;
    card.innerHTML=`<div class="transport-title"><div><strong>${t.name}</strong><small>${t.detail}</small></div>${t.id==='meshtastic'?'<span class="runtime-badge">RADIO</span>':`<label class="switch"><input type="checkbox" data-transport-toggle="${t.id}" ${t.available?'checked':''}><span></span></label>`}</div><div class="transport-metrics"><span>${t.available?'доступен':'отключён'}</span><span>${t.latency} ms</span><span>${t.bitrate>=1000?Math.round(t.bitrate/1000)+' Mb/s':t.bitrate+' kb/s'}</span></div>`;
    holder.append(card);
  });
  $$('[data-transport-toggle]').forEach(input=>input.addEventListener('change',e=>{transportManager.setAvailable(e.target.dataset.transportToggle,e.target.checked);renderTransportCards();renderRoute();renderGlobalStatus();}));
}

function renderRoute() {
  const kind=$('#messageTypeSelect')?.value||'text', decision=transportManager.select(kind);
  $('#activeRouteName').textContent=decision.transport?.name||'Нет маршрута'; $('#activeRouteReason').textContent=decision.reason; $('#routeCodec').textContent=decision.codec;
  $('#routeLatency').textContent=decision.transport?formatLatency(decision.transport.latency):'—'; $('#routeQueue').textContent=String(queue.pendingCount());
  if($('#pttRouteLabel'))$('#pttRouteLabel').textContent=decision.transport?`${decision.transport.name} · ${decision.codec}`:'Нет доступного голосового маршрута';
  if($('#pttFallbackLabel'))$('#pttFallbackLabel').textContent=decision.mode==='voice-message'?'Будет отправлено как голосовое сообщение':'Резерв: Meshtastic → голосовое сообщение';
}
function renderGlobalStatus() {
  const decision=transportManager.select('text'), pending=queue.pendingCount(), active=Boolean(decision.transport);
  $('#networkStateLabel').textContent=active?'Сеть активна':'Нет маршрута';
  $('#routeSummary').textContent=active?`${decision.transport.name} · PhoneAPI ${phoneApiSession?.state==='ready'?'READY':'…'} · очередь ${pending}`:`Локальная очередь · ${pending} ожидает маршрут`;
  $('#mobileSubstatus').textContent=active?`${decision.transport.name} · очередь ${pending}`:`Офлайн · очередь ${pending}`;
  const healthLabel=$('#networkHealthLabel'),healthMeta=$('#networkHealthMeta'),healthDot=$('#networkHealthDot');
  if(healthLabel)healthLabel.textContent=active?(pending>2?'Сеть: очередь растёт':'Сеть: работает'):'Сеть: нет маршрута';
  if(healthMeta)healthMeta.textContent=active?`${decision.transport.name} · ${pending} в очереди`:`${pending} ожидает доступный канал`;
  if(healthDot)healthDot.classList.toggle('warn',!active||pending>2);
  $('#conversationRoute').textContent=active?`Связь через ${decision.transport.name}`:'Нет маршрута · сохраняем локально'; $('#queueBadge').textContent=`очередь ${pending}`;
  $$('.status-dot').forEach(d=>d.classList.toggle('warn',!active));
  renderDeliveryQueue();
}

function nextPacketId(){
  if(globalThis.crypto?.getRandomValues){const a=new Uint32Array(1);crypto.getRandomValues(a);return a[0]||1;}
  return ((Date.now() ^ Math.floor(Math.random()*0xffffffff))>>>0)||1;
}

async function transmitQueueItem(queueId){
  const item=queue.get(queueId); if(!item)return;
  const c=buildConversations().find(x=>x.id===item.payload.conversationId);
  if(!c || activeRadio.state!=='connected' || phoneApiSession?.state!=='ready'){queue.defer(queueId);updateMessageByQueueId(queueId,{status:'В очереди'});renderGlobalStatus();renderRoute();return;}
  const packetId=nextPacketId(); const isDirect=c.kind==='direct';
  queue.markSending(queueId,{packetId,transportId:'meshtastic'});updateMessageByQueueId(queueId,{status:'Отправка…',packetId});
  try{
    const options={to:isDirect?c.nodeNum:BROADCAST,channel:c.channel||0,packetId,wantAck:isDirect};
    const envelope=item.payload.type==='position'?encodePositionToRadio(item.payload.position,options):item.payload.type==='waypoint'?encodeWaypointToRadio(item.payload.waypoint,{...options,wantAck:false}):encodeTextToRadio(item.payload.text,options);
    await activeRadio.sendEnvelope(envelope);
    queue.markSent(queueId,{broadcast:!isDirect});
    updateMessageByQueueId(queueId,{status:isDirect?'Отправлено · ждём ACK':'Отправлено в сеть'});
  }catch(error){queue.markFailed(queueId,error?.message||error);updateMessageByQueueId(queueId,{status:'Ошибка отправки'});}
  renderGlobalStatus();renderRoute();
}
async function flushQueuedMessages(){
  if(activeRadio.state!=='connected'||phoneApiSession?.state!=='ready')return;
  const ready=queue.flush(payload=>transportManager.select(payload.type||'text'));
  for(const item of ready) await transmitQueueItem(item.id);
}
async function retryQueueItem(queueId){
  const item=queue.retry(queueId); if(!item)return; updateMessageByQueueId(queueId,{status:'В очереди'}); renderConversations($('#chatSearch')?.value||''); renderGlobalStatus(); renderDeliveryQueue();
  if(activeRadio.state==='connected'&&phoneApiSession?.state==='ready'){const ready=queue.flush(payload=>transportManager.select(payload.type||'text'));if(ready.some(x=>x.id===queueId))await transmitQueueItem(queueId);}
}
function deliveryStatusLabel(item){
  const map={queued:'В очереди',ready:'Готово',sending:'Отправка…',sent:'Ждём ACK','sent-broadcast':'Отправлено в сеть',delivered:'Доставлено',failed:`Ошибка: ${item.error||'UNKNOWN'}`}; return map[item.status]||item.status;
}
function renderDeliveryQueue(){
  const holder=$('#deliveryList'), summary=$('#deliverySummary'); if(!holder||!summary)return; const items=queue.list().slice().reverse();
  summary.textContent=items.length?`Всего ${items.length} · активных ${queue.unsettledCount()}`:'Очередь пуста'; holder.innerHTML='';
  if(!items.length){holder.innerHTML='<div class="delivery-empty">Сообщений в очереди пока нет.</div>';return;}
  for(const item of items){const c=buildConversations().find(x=>x.id===item.payload.conversationId);const row=document.createElement('div');row.className=`delivery-item status-${item.status}`;row.innerHTML=`<div><strong>${item.payload.text||item.payload.type}</strong><small>${c?.title||item.payload.conversationId}</small></div><div class="delivery-item-side"><span>${deliveryStatusLabel(item)}</span>${item.status==='failed'?`<button type="button" data-delivery-retry="${item.id}">Повторить</button>`:''}</div>`;holder.append(row);}
  holder.querySelectorAll('[data-delivery-retry]').forEach(b=>b.addEventListener('click',()=>retryQueueItem(b.dataset.deliveryRetry)));
}

function formatBytes(n){ if(n<1024)return `${n} B`; return `${(n/1024).toFixed(n<10240?1:0)} KB`; }

function renderChatSearch(query=''){
  const q=query.trim().toLowerCase(); const rows=$$('#messageStream .message-row'); let hits=0;
  rows.forEach(row=>{const hit=!q || row.textContent.toLowerCase().includes(q); row.classList.toggle('is-search-hit',Boolean(q&&hit)); row.classList.toggle('is-search-dim',Boolean(q&&!hit)); if(q&&hit)hits++;});
  const out=$('#messageSearchCount'); if(out)out.textContent=q?`${hits} найдено`:'Введите текст';
}

function transferTarget(t){
  let target=t.targetNode>>>0;
  if(!target&&String(t.conversationId||'').startsWith('direct:'))target=Number(String(t.conversationId).split(':')[1])>>>0;
  return {target,channel:t.channel>>>0};
}
function pauseActiveFileTransfers(reason='link-down'){
  for(const t of fileTransfers.list()){
    if(['complete','failed','paused','queued'].includes(t.status))continue;
    fileTransfers.pause(t.id,reason);refreshFileMessage(t);
  }
  persistFileTransfers();
}
async function sendFilePrivatePayload(t,payload,{wantAck=false}={}){
  const {target,channel}=transferTarget(t);
  if(!target)throw new Error('File transfer target is unknown');
  await activeRadio.sendEnvelope(encodePortPayloadToRadio(PORTNUM.PRIVATE_APP,payload,{to:target,channel,packetId:nextPacketId(),wantAck}));
}
async function beginFileNegotiation(t){
  if(!t||['complete','failed'].includes(t.status))return;
  if(activeRadio.state!=='connected'||phoneApiSession?.state!=='ready'){
    fileTransfers.pause(t.id,'waiting-radio');refreshFileMessage(t);return;
  }
  t.status='checking-remote';t.error=null;refreshFileMessage(t);
  try{
    const manifest=encodeSmallFileManifest({transferId:t.id,name:t.name,size:t.size,sha256:t.sha256,totalChunks:t.total});
    await sendFilePrivatePayload(t,manifest,{wantAck:false});
    await sendFilePrivatePayload(t,encodeSmallFileStatusRequest({transferId:t.id}),{wantAck:false});
  }catch(error){
    if(activeRadio.state!=='connected')fileTransfers.pause(t.id,'link-down');else fileTransfers.fail(t.id,error?.message||error);
    refreshFileMessage(t);
  }
}
async function sendMissingFileChunks(transferId){
  const t=fileTransfers.get(transferId);if(!t||fileSendLocks.has(t.id)||['complete','failed'].includes(t.status))return;
  if(activeRadio.state!=='connected'||phoneApiSession?.state!=='ready'){fileTransfers.pause(t.id,'waiting-radio');refreshFileMessage(t);return;}
  fileSendLocks.add(t.id);
  try{
    const missing=fileTransfers.missingIndices(t.id);
    if(!missing.length){t.status='awaiting-confirmation';refreshFileMessage(t);await sendFilePrivatePayload(t,encodeSmallFileStatusRequest({transferId:t.id}),{wantAck:false});return;}
    t.status=fileTransfers.confirmedCount(t.id)>0?'resuming':'sending';t.error=null;refreshFileMessage(t);
    for(const index of missing){
      if(activeRadio.state!=='connected'||phoneApiSession?.state!=='ready')throw new Error('link-down');
      const frame=encodeSmallFileChunk({transferId:t.id,index,totalChunks:t.total,data:t.chunks[index]});
      await sendFilePrivatePayload(t,frame,{wantAck:false});
      t.sent=Math.min(t.total,(t.sent||0)+1);t.updatedAt=new Date().toISOString();refreshFileMessage(t);
    }
    if(t.status!=='complete'){t.status='awaiting-confirmation';refreshFileMessage(t);await sendFilePrivatePayload(t,encodeSmallFileStatusRequest({transferId:t.id}),{wantAck:false});}
  }catch(error){
    if(activeRadio.state!=='connected'||String(error?.message||error).includes('link-down'))fileTransfers.pause(t.id,'link-down');else fileTransfers.fail(t.id,error?.message||error);
    refreshFileMessage(t);
  }finally{fileSendLocks.delete(t.id);}
}
async function resumeIncompleteFileTransfers(){
  if(activeRadio.state!=='connected'||phoneApiSession?.state!=='ready')return;
  for(const t of fileTransfers.list()){
    if(['complete','failed'].includes(t.status)||fileSendLocks.has(t.id))continue;
    await beginFileNegotiation(t);
  }
}
async function sendReceiverStatus(packet,transferId){
  const status=fileReceiver.status(transferId);if(!status||activeRadio.state!=='connected')return;
  const payload=encodeSmallFileStatus(status);
  await activeRadio.sendEnvelope(encodePortPayloadToRadio(PORTNUM.PRIVATE_APP,payload,{to:packet.from>>>0,channel:packet.channel||0,packetId:nextPacketId(),wantAck:false}));
}
async function handleInboundFilePacket(packet,snapshot){
  let frame;try{frame=decodeSmallFileFrame(packet.decoded.payload);}catch{return;}
  if(frame.kind==='status'){
    const t=fileTransfers.get(frame.transferId);if(!t)return;
    fileTransfers.applyStatus(t.id,frame);
    if(activeRadio.state!=='connected'&&t.status!=='complete'&&t.status!=='failed')fileTransfers.pause(t.id,'link-down');
    refreshFileMessage(t);
    if(t.status==='complete'||t.status==='failed')return;
    if(activeRadio.state==='connected'&&phoneApiSession?.state==='ready'&&!fileSendLocks.has(t.id))sendMissingFileChunks(t.id).catch(()=>{});
    return;
  }
  if(frame.kind==='status_request'){
    await sendReceiverStatus(packet,frame.transferId);return;
  }
  if(frame.kind!=='manifest'&&frame.kind!=='chunk')return;
  const result=await fileReceiver.accept(frame);
  const id=`direct:${packet.from>>>0}`;const bucket=getBucket(id);let msg=bucket.find(m=>m.incomingTransferId===frame.transferId);
  if(frame.kind==='manifest'&&!msg){
    msg={side:'in',author:snapshot?.nodes?.find(n=>n.num===packet.from)?.user?.longName||formatNodeNum(packet.from),text:`Файл ${frame.name}`,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}),status:'Получаем файл…',incomingTransferId:frame.transferId,file:{id:frame.transferId,name:frame.name,size:frame.size,total:frame.totalChunks,received:0}};bucket.push(msg);
  }
  const receiverState=fileReceiver.incoming.get(frame.transferId);
  if(msg&&receiverState){msg.file.received=receiverState.received;msg.status=receiverState.status==='complete'?'Получено · SHA-256 OK':receiverState.status==='hash-error'?'Ошибка SHA-256':`Получено ${receiverState.received}/${receiverState.total}`;if(receiverState.status==='complete'&&receiverState.bytes&&!msg.file.url)msg.file.url=URL.createObjectURL(new Blob([receiverState.bytes]));}
  await sendReceiverStatus(packet,frame.transferId);
  if(id!==currentConversationId)uiState(id).unread=(uiState(id).unread||0)+1;
  if(AndroidBridgeMeshtasticTransport.isSupported() && (document.hidden || id!==currentConversationId)){const latest=bucket.at(-1);androidBleRadio.notify(latest?.author||'Mesh Messenger',latest?.position?'Получена позиция':latest?.text||'Новое сообщение','message',id);}
  renderConversations($('#chatSearch')?.value||'');if(id===currentConversationId)renderMessages();
}
async function sendSmallFile(file){
  const c=currentConversation(); if(!c)return;
  if(c.kind!=='direct'){ alert('В этой версии файлы отправляются только лично узлу.'); return; }
  let transfer; try{transfer=await fileTransfers.create(file,{conversationId:c.id,targetNode:c.nodeNum,channel:c.channel||0});}catch(error){alert(error.message||String(error));return;}
  const msg={side:'out',text:`Файл ${transfer.name}`,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}),status:fileStatusText(transfer),file:transfer}; getBucket(c.id).push(msg);persistFileTransfers();renderMessages();
  if(!transportManager.get('meshtastic')?.available||activeRadio.state!=='connected'||phoneApiSession?.state!=='ready'){transfer.status='queued';refreshFileMessage(transfer);return;}
  await beginFileNegotiation(transfer);
}
function simulateFileSubsystemRestart(){
  persistFileTransfers();
  const next=new SmallFileTransferManager({maxBytes:32768,chunkBytes:180});
  const restored=next.restoreMany(filePersistence.load());fileTransfers=next;
  for(const bucket of messageBuckets.values())for(const m of bucket){if(!m.file?.id)continue;const t=fileTransfers.get(m.file.id);if(t){m.file=t;m.status=`Восстановлено · ${fileStatusText(t)}`;}}
  for(const t of restored){if(!findFileMessage(t.id)&&t.conversationId)getBucket(t.conversationId).push({side:'out',text:`Файл ${t.name}`,time:new Date(t.createdAt).toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}),status:`Восстановлено · ${fileStatusText(t)}`,file:t});}
  renderMessages();renderConversations($('#chatSearch')?.value||'');persistFileTransfers();return restored.map(t=>({id:t.id,status:t.status,confirmed:fileTransfers.confirmedCount(t.id),total:t.total}));
}


function formatCoords(position){
  if(position?.latitude==null||position?.longitude==null)return '—';
  return `${Number(position.latitude).toFixed(5)}, ${Number(position.longitude).toFixed(5)}`;
}
function mapNodes(snapshot=currentSnapshot()){
  const local=snapshot?.myInfo?.myNodeNum>>>0;
  return (snapshot?.nodes||[]).map(n=>{
    const override=packetPositions.get(n.num>>>0);const position=override||n.position;
    if(position?.latitude==null||position?.longitude==null)return null;
    return {...n,position,isLocal:(n.num>>>0)===local,name:n.user?.longName||n.user?.shortName||formatNodeNum(n.num)};
  }).filter(Boolean);
}
function formatDistanceMeters(meters){if(!Number.isFinite(meters)||meters<=0)return '0 м';return meters>=1000?`${(meters/1000).toFixed(meters>=10000?0:1)} км`:`${Math.round(meters)} м`;}
function activeWaypoints(){const now=Math.floor(Date.now()/1000);return [...sharedWaypoints.values()].filter(w=>w?.latitude!=null&&w?.longitude!=null&&(!w.expire||w.expire>now));}
function mercatorPoint(position){
  const lat=Math.max(-85.05112878,Math.min(85.05112878,Number(position.latitude))),lon=Number(position.longitude);
  const x=(lon+180)/360;
  const sin=Math.sin(lat*Math.PI/180);
  const y=0.5-Math.log((1+sin)/(1-sin))/(4*Math.PI);
  return {x,y};
}
function chooseMapZoom(minX,maxX,minY,maxY){
  const canvas=$('#mapCanvas'),w=Math.max(320,canvas?.clientWidth||800),h=Math.max(320,canvas?.clientHeight||680);
  const spanX=Math.max(1e-7,maxX-minX),spanY=Math.max(1e-7,maxY-minY);
  const target=Math.min((w*.8)/(spanX*256),(h*.8)/(spanY*256));
  return Math.max(2,Math.min(18,Math.floor(Math.log2(Math.max(1,target)))));
}
function renderOnlineTiles({minX,maxX,minY,maxY,pad=10,span=80}){
  const layer=$('#mapTileLayer'),grid=$('#mapGrid'),attribution=$('#mapAttribution');
  if(!layer)return;
  const generation=++mapTileGeneration;
  layer.innerHTML='';
  if(navigator.onLine===false){
    mapTileState='offline'; layer.hidden=true; if(grid)grid.hidden=false;if(attribution)attribution.hidden=true;return;
  }
  const z=chooseMapZoom(minX,maxX,minY,maxY),n=2**z;
  const tx0=Math.max(0,Math.floor(minX*n)-1),tx1=Math.min(n-1,Math.floor(maxX*n)+1);
  const ty0=Math.max(0,Math.floor(minY*n)-1),ty1=Math.min(n-1,Math.floor(maxY*n)+1);
  let pending=0,loaded=0,failed=0;
  mapTileState='loading';layer.hidden=false;if(grid)grid.hidden=false;if(attribution)attribution.hidden=false;
  const settle=()=>{
    if(generation!==mapTileGeneration)return;
    if(loaded>0){mapTileState='online';if(grid)grid.hidden=true;$('#mapOverlayTitle').textContent='OSM · Позиции NodeDB';}
    else if(pending===failed){mapTileState='fallback';layer.hidden=true;if(grid)grid.hidden=false;if(attribution)attribution.hidden=true;$('#mapOverlayTitle').textContent='Карта недоступна · локальная сетка';}
  };
  for(let ty=ty0;ty<=ty1;ty++)for(let tx=tx0;tx<=tx1;tx++){
    pending++;
    const img=document.createElement('img');img.className='map-tile';img.alt='';img.decoding='async';img.loading='eager';img.referrerPolicy='origin';
    const left=pad+(((tx/n)-minX)/(maxX-minX))*span,top=pad+(((ty/n)-minY)/(maxY-minY))*span;
    const right=pad+((((tx+1)/n)-minX)/(maxX-minX))*span,bottom=pad+((((ty+1)/n)-minY)/(maxY-minY))*span;
    img.style.left=`${left}%`;img.style.top=`${top}%`;img.style.width=`${right-left}%`;img.style.height=`${bottom-top}%`;
    img.addEventListener('load',()=>{loaded++;settle();},{once:true});
    img.addEventListener('error',()=>{failed++;img.remove();settle();},{once:true});
    img.src=`https://tile.openstreetmap.org/${z}/${tx}/${ty}.png`;
    layer.appendChild(img);
  }
  setTimeout(()=>{if(generation===mapTileGeneration&&loaded===0){mapTileState='fallback';layer.hidden=true;if(grid)grid.hidden=false;if(attribution)attribution.hidden=true;$('#mapOverlayTitle').textContent='Карта недоступна · локальная сетка';}},4500);
}
function renderMap({fallback=null}={}){
  const holder=$('#mapMarkers'),trackLayer=$('#mapTrackLayer');if(!holder)return;
  const nodes=mapNodes();holder.innerHTML='';if(trackLayer)trackLayer.innerHTML='';
  const waypoints=activeWaypoints();
  const hasGeoData=Boolean(nodes.length||waypoints.length||(fallback?.latitude!=null&&fallback?.longitude!=null));
  let selected=selectedMapNodeNum?nodes.find(n=>(n.num>>>0)===selectedMapNodeNum):null;
  if(!selected&&nodes.length){selected=nodes.find(n=>!n.isLocal)||nodes[0];if(selected&&!selected.isLocal)selectedMapNodeNum=selected.num>>>0;}
  const track=selected?trackHistory.list(selected.num>>>0):[];
  const boundPoints=[...nodes.map(n=>n.position),...track,...waypoints.map(w=>({latitude:w.latitude,longitude:w.longitude}))];
  if(!hasGeoData)boundPoints.push({latitude:-60,longitude:-170},{latitude:75,longitude:170});
  if(fallback?.latitude!=null&&fallback?.longitude!=null)boundPoints.push(fallback);
  const projected=boundPoints.map(mercatorPoint).filter(p=>Number.isFinite(p.x)&&Number.isFinite(p.y));
  let minX=Math.min(...projected.map(p=>p.x)),maxX=Math.max(...projected.map(p=>p.x)),minY=Math.min(...projected.map(p=>p.y)),maxY=Math.max(...projected.map(p=>p.y));
  if(!Number.isFinite(minX)||!Number.isFinite(minY)){return;}
  if(maxX-minX<0.00001){minX-=0.000005;maxX+=0.000005;} if(maxY-minY<0.00001){minY-=0.000005;maxY+=0.000005;}
  const extraX=(maxX-minX)*0.16,extraY=(maxY-minY)*0.16;minX-=extraX;maxX+=extraX;minY-=extraY;maxY+=extraY;
  const pad=10,span=80,project=p=>{const m=mercatorPoint(p);return{x:pad+((m.x-minX)/(maxX-minX))*span,y:pad+((m.y-minY)/(maxY-minY))*span};};
  renderOnlineTiles({minX,maxX,minY,maxY,pad,span});
  if(trackLayer&&track.length>=2){const points=track.map(p=>{const q=project(p);return `${q.x.toFixed(2)},${q.y.toFixed(2)}`}).join(' ');const poly=document.createElementNS('http://www.w3.org/2000/svg','polyline');poly.setAttribute('points',points);poly.setAttribute('class','map-track-line');trackLayer.appendChild(poly);}
  for(const w of waypoints){const q=project(w);const b=document.createElement('button');b.type='button';b.className='map-waypoint';b.style.left=`${q.x}%`;b.style.top=`${q.y}%`;b.title=w.description||w.name||'Waypoint';b.innerHTML=`<span>⌖</span><span class="marker-label">${w.name||'Waypoint'}</span>`;holder.append(b);}
  for(const n of nodes){
    const q=project(n.position);
    const b=document.createElement('button');b.type='button';b.className=`map-marker ${n.isLocal?'self':n.user?.role===2?'relay':'peer'} ${(n.num>>>0)===selectedMapNodeNum?'is-selected':''}`;
    b.style.left=`${q.x}%`;b.style.top=`${q.y}%`;b.dataset.nodeNum=String(n.num>>>0);b.innerHTML=`${n.isLocal?'Вы':(n.user?.shortName||n.name.slice(0,2))}<span class="marker-label">${n.name}</span>`;
    b.addEventListener('click',()=>{selectedMapNodeNum=n.num>>>0;renderMap();});holder.append(b);
  }
  $('#mapOverlayTitle').textContent=mapTileState==='online'?'OSM · Позиции NodeDB':mapTileState==='loading'?'Карта загружается · Позиции NodeDB':'Карта недоступна · локальная сетка';$('#mapOverlayMeta').textContent=hasGeoData?`${nodes.length} узлов · ${waypoints.length} точек · ${new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})}`:'координат пока нет · общий вид';
  if(!selected){$('#mapSelectedName').textContent='Нет узла';$('#mapSelectedCoords').textContent=fallback?formatCoords(fallback):'—';$('#mapSelectedAltitude').textContent='—';$('#mapSelectedRoute').textContent='—';$('#mapTrackMeta').textContent='—';$('#mapOpenChatButton').disabled=true;$('#mapCreateWaypointButton').disabled=!fallback;$('#mapClearTrackButton').disabled=true;return;}
  $('#mapSelectedName').textContent=selected.name;$('#mapSelectedCoords').textContent=formatCoords(selected.position);$('#mapSelectedAltitude').textContent=selected.position.altitude==null?'—':`${Math.round(selected.position.altitude)} м`;
  $('#mapSelectedRoute').textContent=selected.isLocal?'локальный узел':`${selected.hopsAway??'—'} hops · ${selected.snr==null?'SNR —':`SNR ${selected.snr.toFixed(1)} dB`}`;
  $('#mapTrackMeta').textContent=`${track.length} точек · ${formatDistanceMeters(trackHistory.distanceMeters(selected.num>>>0))}`;
  const open=$('#mapOpenChatButton');open.disabled=Boolean(selected.isLocal);open.dataset.nodeNum=String(selected.num>>>0);$('#mapCreateWaypointButton').disabled=false;$('#mapClearTrackButton').disabled=track.length===0;
}

function bestLocalPosition(){
  const snapshot=currentSnapshot(),local=snapshot?.myInfo?.myNodeNum>>>0;
  const node=snapshot?.nodes?.find(n=>(n.num>>>0)===local);return packetPositions.get(local)||node?.position||null;
}
function browserPosition(){
  return new Promise((resolve,reject)=>{
    if(!navigator.geolocation)return reject(new Error('Geolocation API недоступен'));
    navigator.geolocation.getCurrentPosition(p=>resolve({latitude:p.coords.latitude,longitude:p.coords.longitude,altitude:p.coords.altitude==null?null:Math.round(p.coords.altitude),timestamp:Math.floor(Date.now()/1000)}),reject,{enableHighAccuracy:true,timeout:5000,maximumAge:15000});
  });
}
async function shareCurrentPosition({preferBrowser=true}={}){
  let position=null;
  if(preferBrowser){try{position=await browserPosition();}catch{}}
  position=position||bestLocalPosition();
  if(!position){alert('У локального узла пока нет координат.');return null;}
  const c=currentConversation();if(!c)return null;
  const decision=transportManager.select('position');
  const label=`Позиция ${formatCoords(position)}`;
  const localNum=currentSnapshot()?.myInfo?.myNodeNum>>>0;if(localNum){trackHistory.append(localNum,position);persistTrackHistory();}
  const item=queue.enqueue({type:'position',text:label,position,conversationId:c.id},decision);
  getBucket(c.id).push({side:'out',text:'Позиция',position,positionNodeNum:currentSnapshot()?.myInfo?.myNodeNum>>>0,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}),status:item.status==='queued'?'В очереди':'Готово к отправке',queueId:item.id});
  renderMessages();renderConversations($('#chatSearch')?.value||'');renderGlobalStatus();renderDeliveryQueue();
  if(item.status==='ready')await transmitQueueItem(item.id);return item;
}
function mapSelectedNode(){const nodes=mapNodes();return selectedMapNodeNum?nodes.find(n=>(n.num>>>0)===selectedMapNodeNum):(nodes.find(n=>!n.isLocal)||nodes[0]||null);}
function openWaypointModal(){
  const selected=mapSelectedNode();if(!selected?.position){alert('Сначала выберите точку на карте.');return;}
  pendingWaypointPosition={...selected.position};$('#waypointName').value=`Точка ${new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})}`;$('#waypointDescription').value='';$('#waypointExpire').value='21600';openModal($('#waypointModal'));
}
async function sendWaypointFromModal(){
  if(!pendingWaypointPosition)return;const name=($('#waypointName').value||'Точка').trim().slice(0,30),description=($('#waypointDescription').value||'').trim().slice(0,100),ttl=Math.max(0,Number($('#waypointExpire').value)||0);
  const id=nextPacketId(),expire=ttl?Math.floor(Date.now()/1000)+ttl:0,waypoint={id,latitude:pendingWaypointPosition.latitude,longitude:pendingWaypointPosition.longitude,expire,lockedTo:currentSnapshot()?.myInfo?.myNodeNum>>>0,name,description,icon:0x1f4cd};
  sharedWaypoints.set(id,waypoint);persistWaypoints();renderMap();closeModal($('#waypointModal'));pendingWaypointPosition=null;
  const decision=transportManager.select('waypoint');const item=queue.enqueue({type:'waypoint',text:`Waypoint: ${name}`,waypoint,conversationId:'channel:0'},decision);renderGlobalStatus();renderDeliveryQueue();if(item.status==='ready')await transmitQueueItem(item.id);
  return item;
}

function currentShareUrls(){
  const snapshot=currentSnapshot();const localNum=snapshot?.myInfo?.myNodeNum>>>0;const localNode=snapshot?.nodes?.find(n=>(n.num>>>0)===localNum);
  const enabled=(snapshot?.channels||[]).filter(c=>c.role!==0);const lora=snapshot?.configs?.lora||null;
  return {
    contact: localNode?.user?sharedContactUrl({nodeNum:localNum,user:localNode.user,manuallyVerified:true}):'',
    channel: enabled.length?channelSetUrl(enabled,lora):''
  };
}
function renderShareQr(mode=qrMode){
  qrMode=mode;const urls=currentShareUrls(),url=urls[mode]||'';const isChannel=mode==='channel';
  $$('#qrModeTabs [data-qr-mode]').forEach(b=>b.classList.toggle('is-active',b.dataset.qrMode===mode));
  $('#shareQrUrl').textContent=url||'PhoneAPI ещё не готов';$('#shareQrImage').src=QR_ASSETS[mode];
  $('#shareQrImage').hidden=!url;$('#shareQrCaption').textContent=isChannel?'ChannelSet · https://meshtastic.org/e/#':'SharedContact · https://meshtastic.org/v/#';
  $('#shareQrTitle').textContent=isChannel?'Основной набор каналов':'Мой контакт';$('#shareQrDetail').textContent=isChannel?'QR содержит настройки канала, включая PSK. Показывайте его только тем, кому доверяете.':'QR содержит node number, User и публичный ключ контакта.';
  return url;
}
function openShareModal(mode='contact'){renderShareQr(mode);openModal($('#contactModal'));}

function sendMessage(text) {
  const clean=text.trim(); if(!clean)return;
  const c=currentConversation(); if(!c)return;
  const decision=transportManager.select('text');
  const item=queue.enqueue({type:'text',text:clean,conversationId:c.id},decision);
  getBucket(c.id).push({side:'out',text:clean,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}),status:item.status==='queued'?'В очереди':'Готово к отправке',queueId:item.id});
  renderMessages();renderConversations($('#chatSearch')?.value||'');renderGlobalStatus();renderRoute();renderDeliveryQueue();
  if(item.status==='ready')transmitQueueItem(item.id);
}

function exportPhoneApiCapture() {
  const events=phoneApiSession?.events?.filter(e=>e.type==='from_radio'&&e.message?.raw)||[];
  const payload={kind:activeRadio.id==='meshtastic-mock'?'synthetic-runtime-capture':'hardware-phoneapi-capture',capturedAt:new Date().toISOString(),adapter:activeRadio.id,phoneApiState:phoneApiSession?.state||'none',envelopes:events.map((event,index)=>({index:index+1,type:event.message.type,hex:[...event.message.raw].map(b=>b.toString(16).padStart(2,'0')).join('')}))};
  const blob=new Blob([JSON.stringify(payload,null,2)+'\n'],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`mesh-phoneapi-${activeRadio.id}-${Date.now()}.json`;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),0);return payload;
}

function openModal(el){el.classList.add('is-open');el.setAttribute('aria-hidden','false');}
function closeModal(el){el.classList.remove('is-open');el.setAttribute('aria-hidden','true');}
function persistImportedContacts(){storageSet('mesh-imported-contacts',JSON.stringify([...importedContacts.values()].map(x=>({nodeNum:x.nodeNum>>>0,longName:x.longName||'',shortName:x.shortName||'',id:x.id||'',manuallyVerified:Boolean(x.manuallyVerified)}))));}
function openQrImportModal(parsed){
  pendingQrImport=parsed;const modal=$('#importQrModal');if(!modal)return;
  const title=$('#importQrTitle'),detail=$('#importQrDetail'),confirm=$('#confirmQrImport');
  if(parsed.kind==='contact'){
    const c=parsed.contact,u=c.user||{};title.textContent='Добавить контакт';detail.textContent=`${u.longName||u.shortName||formatNodeNum(c.nodeNum)} · ${formatNodeNum(c.nodeNum)}${c.manuallyVerified?' · ключ подтверждён':''}`;confirm.textContent='Добавить контакт';
  }else{
    const set=parsed.channelSet,names=set.channels.map(c=>c.name||'Без имени').join(', ')||'канал';title.textContent='Импорт канала';detail.textContent=`${names} · ${set.channels.length} канал(а). Сохраним локально; запись в радио после hardware gate.`;confirm.textContent='Сохранить локально';
  }
  openModal(modal);
}
function handleScannedQr(text){
  try{openQrImportModal(parseMeshtasticShareUrl(text));}catch(error){renderSystemBanner('error',`QR: ${error?.message||error}`);}
}
function confirmQrImport(){
  const parsed=pendingQrImport;if(!parsed)return;
  if(parsed.kind==='contact'){
    const c=parsed.contact,u=c.user||{};importedContacts.set(c.nodeNum>>>0,{nodeNum:c.nodeNum>>>0,longName:u.longName||'',shortName:u.shortName||'',id:u.id||formatNodeNum(c.nodeNum),manuallyVerified:Boolean(c.manuallyVerified)});persistImportedContacts();renderConversations();selectConversation(`direct:${c.nodeNum>>>0}`);
  }else{
    storageSet('mesh-pending-channel-import',JSON.stringify({savedAt:Date.now(),names:parsed.channelSet.channels.map(c=>c.name||''),requiresRescan:true}));renderSystemBanner('ready','ChannelSet сохранён локально. Запись в радио ждёт hardware gate.');
  }
  pendingQrImport=null;closeModal($('#importQrModal'));
}

function renderBluetoothPower(detail={}){
  const button=$('#enableBluetoothButton'); if(button)button.hidden=detail?.enabled!==false;
  if(detail?.enabled===false)setBleErrorHelp('BLUETOOTH_DISABLED');
}
function renderBlePermission(detail={}){
  const el=$('#blePermissionText'),title=$('#blePermissionTitle');if(!el)return;
  const missing=Array.isArray(detail?.missing)?detail.missing:[];
  if(title)title.textContent=detail?.granted?'Bluetooth готов':'Нужно разрешение';
  el.textContent=detail?.granted?'Можно искать устройства рядом.':missing.length?'Разрешите доступ к устройствам поблизости.':'Разрешите Bluetooth для поиска устройства.';
  setBleErrorHelp(detail?.granted?'':'BLUETOOTH_PERMISSION_DENIED');
}
async function scanBleDevicePicker(){
  const list=$('#bleDeviceList');if(!list)return;
  const status=text=>{list.innerHTML='';const e=document.createElement('div');e.className='node-empty';e.textContent=String(text||'');list.appendChild(e);};
  status('Ищем Meshtastic BLE…');
  try{
    const devices=await androidBleRadio.scanDevices();list.innerHTML='';
    if(!devices.length){status('Meshtastic BLE не найден. Проверьте питание и Bluetooth.');setBleErrorHelp('BLE_DEVICE_NOT_FOUND');return;}
    setBleErrorHelp('');
    for(const d of devices){
      const b=document.createElement('button');b.type='button';b.dataset.deviceId=d.id;b.dataset.saved=String(Boolean(d.saved));
      const strong=document.createElement('strong');strong.textContent=d.name||'Meshtastic';
      const copy=document.createElement('span');copy.className='ble-device-copy';
      const small=document.createElement('small');small.textContent=`${d.id||''}${d.saved?' · последнее устройство':''}`;
      const action=document.createElement('span');action.className='ble-device-action';action.textContent='Подключить';
      copy.append(strong,small);b.append(copy,action);
      b.addEventListener('click',async()=>{status('Подключаем…');try{await activateRadio(androidBleRadio,{deviceId:d.id});closeModal($('#bleDeviceModal'));}catch(error){status(error?.message||String(error));}});
      list.appendChild(b);
    }
  }catch(error){
    const message=error?.message||String(error);
    if(message.includes('BLUETOOTH_DISABLED')){renderBluetoothPower({enabled:false});status('Bluetooth выключен. Нажмите «Включить Bluetooth».');setBleErrorHelp('BLUETOOTH_DISABLED');}
    else if(message.includes('BLE_SCANNER_UNAVAILABLE')){status('BLE-сканер Android ещё не готов. Подождите секунду и повторите.');setBleErrorHelp('BLE_SCANNER_UNAVAILABLE');}
    else if(message.includes('BLE_SCAN_PERMISSION_DENIED')){status('Android не дал доступ к BLE-сканированию. Проверьте разрешение «Устройства поблизости».');setBleErrorHelp('BLUETOOTH_PERMISSION_DENIED');}
    else if(message.includes('BLE_SCAN_FAILED_')){status(`Сканирование Bluetooth завершилось ошибкой (${message}). Повторите через несколько секунд.`);setBleErrorHelp('BLE_SCAN_FAILED');}
    else {status(message);setBleErrorHelp('BLE_DEVICE_NOT_FOUND');}
  }
}
function setBleDevicePickerStatus(text){
  const list=$('#bleDeviceList');if(!list)return;
  list.innerHTML='';const e=document.createElement('div');e.className='node-empty';e.textContent=String(text||'');list.appendChild(e);
}
function openBleDevicePicker(){
  if(!AndroidBridgeMeshtasticTransport.isSupported()){renderSystemBanner('error','BLE-выбор доступен в Android-приложении.');return;}
  const permission=androidBleRadio.permissionStatus();
  const bluetooth=androidBleRadio.bluetoothStatus();
  renderBlePermission(permission);renderBluetoothPower(bluetooth);openModal($('#bleDeviceModal'));
  if(permission?.granted&&bluetooth?.enabled===false){setBleDevicePickerStatus('Bluetooth выключен. Нажмите «Включить Bluetooth».');return;}
  if(permission?.granted){scanBleDevicePicker();return;}
  setBleDevicePickerStatus('Разрешите Bluetooth, затем приложение покажет доступные Meshtastic-узлы.');
  androidBleRadio.requestPermissions();
}
function handleAndroidDeepLink(id){if(!id)return;selectConversation(String(id));setView('chats');}

function wireEvents() {
  $$('[data-nav] [data-view]').forEach(b=>b.addEventListener('click',()=>setView(b.dataset.view)));
  $$('[data-open-network]').forEach(b=>b.addEventListener('click',()=>setView('network')));
  $('#chatSearch').addEventListener('input',e=>renderConversations(e.target.value));
  $('#composerForm').addEventListener('submit',e=>{e.preventDefault();const i=$('#messageInput');sendMessage(i.value);i.value='';});
  $$('.quick-phrases [data-phrase]').forEach(b=>b.addEventListener('click',()=>sendMessage(b.dataset.phrase)));
  $('#toggleStatusDetails')?.addEventListener('click',()=>{const card=$('#globalStatusCard');card.classList.toggle('is-collapsed');$('#toggleStatusDetails').setAttribute('aria-expanded',String(!card.classList.contains('is-collapsed')));});
  $('#openChatSearch')?.addEventListener('click',()=>{$('#messageSearchBar').hidden=false;$('#messageSearchInput').focus();});
  $('#closeChatSearch')?.addEventListener('click',()=>{$('#messageSearchBar').hidden=true;$('#messageSearchInput').value='';renderChatSearch('');});
  $('#messageSearchInput')?.addEventListener('input',e=>renderChatSearch(e.target.value));
  $('#newContactButton').textContent='＋';
  $('#newContactButton').setAttribute('aria-label','Добавить');
  $('#newContactButton').onclick=()=>openModal($('#addMenuModal'));
  $('#closeAddMenu')?.addEventListener('click',()=>closeModal($('#addMenuModal')));
  $('#addMenuModal')?.addEventListener('click',e=>{if(e.target===$('#addMenuModal'))closeModal($('#addMenuModal'));});
  $('[data-add-contact]')?.addEventListener('click',()=>{closeModal($('#addMenuModal'));openShareModal('contact');});
  $('[data-add-channel-qr]')?.addEventListener('click',()=>{closeModal($('#addMenuModal'));openShareModal('channel');});
  $('[data-scan-qr]')?.addEventListener('click',()=>{closeModal($('#addMenuModal'));if(AndroidBridgeMeshtasticTransport.isSupported())androidBleRadio.scanQr();else renderSystemBanner('error','Камера QR доступна в Android-приложении.');});
  globalThis.addEventListener('mesh-android-qr',e=>handleScannedQr(e.detail));
  globalThis.addEventListener('mesh-android-permissions',e=>{const detail=e.detail||{};renderBlePermission(detail);if(detail.granted&&$('#bleDeviceModal')?.getAttribute('aria-hidden')==='false')scanBleDevicePicker();else if(!detail.granted)setBleDevicePickerStatus('Bluetooth не разрешён. Нажмите «Сканировать», чтобы запросить разрешение ещё раз.');});
  globalThis.addEventListener('mesh-android-bluetooth',e=>{const detail=e.detail||{};renderBluetoothPower(detail);if(detail.enabled&&$('#bleDeviceModal')?.getAttribute('aria-hidden')==='false')setTimeout(()=>scanBleDevicePicker(),700);else if(detail.enabled===false)setBleDevicePickerStatus('Bluetooth выключен. Нажмите «Включить Bluetooth».');});
  globalThis.addEventListener('mesh-android-deeplink',e=>handleAndroidDeepLink(e.detail));
  globalThis.addEventListener('online',()=>{if(currentViewName==='map')renderMap();});
  globalThis.addEventListener('offline',()=>{mapTileState='offline';if(currentViewName==='map')renderMap();});
  $('#closeBleDeviceModal')?.addEventListener('click',()=>closeModal($('#bleDeviceModal')));$('#cancelBleDevices')?.addEventListener('click',()=>closeModal($('#bleDeviceModal')));$('#enableBluetoothButton')?.addEventListener('click',()=>androidBleRadio.requestBluetoothEnable());$('#rescanBleDevices')?.addEventListener('click',()=>{const permission=androidBleRadio.permissionStatus();const bluetooth=androidBleRadio.bluetoothStatus();renderBlePermission(permission);renderBluetoothPower(bluetooth);if(!permission?.granted)androidBleRadio.requestPermissions();else if(bluetooth?.enabled===false)androidBleRadio.requestBluetoothEnable();else scanBleDevicePicker();});$('#bleDeviceModal')?.addEventListener('click',e=>{if(e.target===$('#bleDeviceModal'))closeModal($('#bleDeviceModal'));});
  $('#confirmQrImport')?.addEventListener('click',confirmQrImport);$('#cancelQrImport')?.addEventListener('click',()=>{pendingQrImport=null;closeModal($('#importQrModal'));});
  $('[data-add-position]')?.addEventListener('click',async()=>{closeModal($('#addMenuModal'));await shareCurrentPosition();});
  $$('#qrModeTabs [data-qr-mode]').forEach(b=>b.addEventListener('click',()=>renderShareQr(b.dataset.qrMode)));
  $('#copyShareUrl')?.addEventListener('click',async()=>{const url=currentShareUrls()[qrMode];if(!url)return;try{await navigator.clipboard.writeText(url);$('#copyShareUrl').textContent='Скопировано';setTimeout(()=>$('#copyShareUrl').textContent='Копировать ссылку',900);}catch{$('#copyShareUrl').textContent='Скопируйте ссылку выше';}});
  $('[data-add-file]')?.addEventListener('click',()=>{closeModal($('#addMenuModal'));$('#fileInput').click();});
  $$('[data-help-topic]').forEach(button=>button.addEventListener('click',()=>openFullHelp(button.dataset.helpTopic||HELP_FALLBACK_ID)));
  $('#attachFile')?.addEventListener('click',()=>$('#fileInput').click());
  const fileInput=$('#fileInput'); if(fileInput){ const onFile=async e=>{const f=e.target.files?.[0];if(f)await sendSmallFile(f);e.target.value='';}; fileInput.addEventListener('change',onFile); }
  $('#messageTypeSelect').addEventListener('change',renderRoute);
  $('#engineeringToggle').addEventListener('change',e=>{$('#engineeringBlock').hidden=!e.target.checked;storageSet('engineering',e.target.checked?'1':'0');});
  $('#networkDetailsToggle')?.addEventListener('click',toggleNetworkDetails);
  $('#networkHealthDetails')?.addEventListener('click',()=>setNetworkDetails(true));
  const usbButton=$('#connectUsbRadio');if(usbButton&&!WebSerialMeshtasticTransport.isSupported()){usbButton.disabled=true;usbButton.title='USB/Web Serial недоступен в этом runtime';}
  $('#relaySwitch').addEventListener('change',e=>e.currentTarget.closest('.relay-card').classList.toggle('disabled-state',!e.target.checked));
  $('#helpTriggerDesktop')?.addEventListener('click',()=>renderQuickHelp()); $('#helpTriggerMobile')?.addEventListener('click',()=>renderQuickHelp());
  $('#closeQuickHelp')?.addEventListener('click',()=>closeModal($('#quickHelpModal'))); $('#quickHelpModal')?.addEventListener('click',e=>{if(e.target===$('#quickHelpModal'))closeModal($('#quickHelpModal'));});
  $('#openFullHelp')?.addEventListener('click',()=>openFullHelp(currentHelpTopicId)); $('#closeFullHelp')?.addEventListener('click',closeFullHelpFromUi);
  $('#fullHelpModal')?.addEventListener('click',e=>{if(e.target===$('#fullHelpModal'))closeFullHelpFromUi();}); $('#helpSearchInput')?.addEventListener('input',e=>renderHelpTopicList(e.target.value)); $('#copySafeDiagnostics')?.addEventListener('click',copySafeDiagnostics);
  $('#bleErrorHelpButton')?.addEventListener('click',()=>openFullHelp(helpRegistry.resolve(activeHelpErrorCode||'BLUETOOTH_PERMISSION_DENIED').id));
  globalThis.addEventListener('popstate',()=>{const topic=parseHelpTopic(location.search);if(topic)openFullHelp(topic,{pushHistory:false});else closeModal($('#fullHelpModal'));});
  $('#helpTriggerDesktop')?.setAttribute('aria-label','\u0421\u043f\u0440\u0430\u0432\u043a\u0430'); $('#helpTriggerMobile')?.setAttribute('aria-label','\u0421\u043f\u0440\u0430\u0432\u043a\u0430');
  $('#themeToggleDesktop').addEventListener('click',toggleTheme); $('#themeToggleMobile').addEventListener('click',toggleTheme);
  $('#connectDemoRadio').addEventListener('click',()=>activateRadio(mockRadio)); $('#connectUsbRadio').addEventListener('click',()=>activateRadio(webSerialRadio)); $('#connectBleRadio')?.addEventListener('click',()=>AndroidBridgeMeshtasticTransport.isSupported()?openBleDevicePicker():activateRadio(androidBleRadio)); $('#exportPhoneApiCapture').addEventListener('click',exportPhoneApiCapture);
  $('#disconnectRadio').addEventListener('click',async()=>{closePhoneApiSession();try{await activeRadio.disconnect();}catch{}renderRadioState(activeRadio.snapshot());});
  $('#closeContactModal').addEventListener('click',()=>closeModal($('#contactModal'))); $('#contactModal').addEventListener('click',e=>{if(e.target===$('#contactModal'))closeModal($('#contactModal'));});
  $('#openDeliveryQueue').addEventListener('click',()=>{renderDeliveryQueue();openModal($('#deliveryModal'));}); $('#closeDeliveryModal').addEventListener('click',()=>closeModal($('#deliveryModal'))); $('#deliveryModal').addEventListener('click',e=>{if(e.target===$('#deliveryModal'))closeModal($('#deliveryModal'));});
  $('#pttShortcut').addEventListener('click',()=>{$('#messageTypeSelect').value='voice';renderRoute();openModal($('#pttLayer'));}); $('#mapPttButton').addEventListener('click',()=>{$('#messageTypeSelect').value='voice';renderRoute();openModal($('#pttLayer'));});
  $('#composerVoice')?.addEventListener('click',()=>$('#pttShortcut')?.click());
  $('#conversationBackMobile')?.addEventListener('click',()=>{const screen=document.querySelector('[data-screen="chats"]');screen?.classList.remove('mobile-conversation-open');requestAnimationFrame(()=>screen?.scrollIntoView({behavior:'smooth',block:'start'}));});
  $('#sharePositionButton')?.addEventListener('click',()=>shareCurrentPosition());
  $('#centerMapButton')?.addEventListener('click',()=>{selectedMapNodeNum=0;renderMap();});
  $('#mapOpenChatButton')?.addEventListener('click',e=>{const num=Number(e.currentTarget.dataset.nodeNum)||0;if(num){selectConversation(`direct:${num}`);setView('chats');}});
  $('#mapCreateWaypointButton')?.addEventListener('click',openWaypointModal);$('#cancelWaypoint')?.addEventListener('click',()=>{pendingWaypointPosition=null;closeModal($('#waypointModal'));});$('#confirmWaypoint')?.addEventListener('click',()=>sendWaypointFromModal());$('#waypointModal')?.addEventListener('click',e=>{if(e.target===$('#waypointModal')){pendingWaypointPosition=null;closeModal($('#waypointModal'));}});$('#mapClearTrackButton')?.addEventListener('click',()=>{const n=mapSelectedNode();if(n){trackHistory.clear(n.num>>>0);persistTrackHistory();renderMap();}});
  $('#closePtt').addEventListener('click',()=>closeModal($('#pttLayer')));
  const ptt=$('#pttMain'),down=()=>{$('#pttState').textContent='Говорите · demo';ptt.classList.add('is-live');},up=()=>{$('#pttState').textContent='Готов к передаче';ptt.classList.remove('is-live');};ptt.addEventListener('pointerdown',down);ptt.addEventListener('pointerup',up);ptt.addEventListener('pointercancel',up);ptt.addEventListener('pointerleave',up);
}

initTheme();
mockRadio.onState(snapshot=>{if(activeRadio===mockRadio)renderRadioState(snapshot);}); webSerialRadio.onState(snapshot=>{if(activeRadio===webSerialRadio)renderRadioState(snapshot);}); androidBleRadio.onState(snapshot=>{if(activeRadio===androidBleRadio)renderRadioState(snapshot);});
renderConversations();renderConversationHeader();renderMessages();renderTransportCards();renderGlobalStatus();renderRoute();renderDeliveryQueue();renderSystemBanner('syncing');renderMap();
const eng=storageGet('engineering')==='1';$('#engineeringToggle').checked=eng;$('#engineeringBlock').hidden=!eng;wireEvents();
const initialHelpTopic=parseHelpTopic(location.search);if(initialHelpTopic)openFullHelp(initialHelpTopic,{pushHistory:false});
if(globalThis.__meshPendingDeepLink){handleAndroidDeepLink(globalThis.__meshPendingDeepLink);globalThis.__meshPendingDeepLink='';}
if(!globalThis.__meshDisableAutoConnect)activateRadio(AndroidBridgeMeshtasticTransport.isSupported()?androidBleRadio:mockRadio).catch(()=>{});

window.__meshDebug={transportManager,queue,mockRadio,androidBleRadio,getPhoneApiSnapshot:()=>currentSnapshot(),getCurrentConversation:()=>currentConversation(),selectConversation,sendMessage,retryQueueItem,renderDeliveryQueue,exportPhoneApiCapture,simulateReboot:()=>mockRadio.simulateReboot(),setNextRoutingResult:(code)=>mockRadio.setNextRoutingResult(code),setFileDisconnectAfter:(n)=>mockRadio.setFileDisconnectAfter(n),getConversationUi:(id)=>({...uiState(id)}),sendSmallFile,getFileTransfers:()=>fileTransfers.list().map(t=>({id:t.id,name:t.name,status:t.status,confirmed:fileTransfers.confirmedCount(t.id),total:t.total,targetNode:t.targetNode,conversationId:t.conversationId,error:t.error})),simulateFileSubsystemRestart,resumeIncompleteFileTransfers,renderMap,shareCurrentPosition,currentShareUrls,renderShareQr,trackHistory,getWaypoints:()=>[...sharedWaypoints.values()],sendWaypointFromModal,helpRegistry,renderQuickHelp,openFullHelp,copySafeDiagnostics,currentHelpTopic:()=>currentHelpTopicId};
if('serviceWorker' in navigator&&location.protocol.startsWith('http')&&!AndroidBridgeMeshtasticTransport.isSupported())serviceWorker.register('./sw.js').catch(()=>{});
