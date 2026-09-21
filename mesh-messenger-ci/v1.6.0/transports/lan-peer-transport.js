const enc = new TextEncoder();
const dec = new TextDecoder();

function id(prefix='peer') {
  if (globalThis.crypto?.randomUUID) return prefix + '-' + crypto.randomUUID();
  return prefix + '-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
}
function b64url(text) {
  let bin=''; for (const b of enc.encode(text)) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
}
function unb64url(value) {
  const normalized=String(value).replace(/-/g,'+').replace(/_/g,'/');
  const padded=normalized+'='.repeat((4-normalized.length%4)%4);
  const bin=atob(padded); const bytes=new Uint8Array(bin.length);
  for(let i=0;i<bin.length;i++) bytes[i]=bin.charCodeAt(i);
  return dec.decode(bytes);
}
function encodeSignal(v){ return 'MM-LAN1.' + b64url(JSON.stringify(v)); }
function decodeSignal(code){
  const raw=String(code||'').trim();
  if(!raw.startsWith('MM-LAN1.')) throw new Error('Неверный код LAN');
  const v=JSON.parse(unb64url(raw.slice(8)));
  if(!v?.description||!v?.peerId) throw new Error('Повреждённый код LAN');
  return v;
}

export class LanPeerTransport {
  constructor({peerId=id(),displayName='Устройство',onEnvelope=()=>{},onState=()=>{},RTCPeerConnectionImpl=globalThis.RTCPeerConnection}={}){
    this.peerId=peerId; this.displayName=displayName; this.onEnvelope=onEnvelope; this.onState=onState;
    this.RTCPeerConnectionImpl=RTCPeerConnectionImpl; this.pc=null; this.channel=null; this.remotePeerId=''; this.remoteName='';
    this.state='idle'; this.outbox=[]; this.pendingRole='';
  }
  setIdentity({peerId,displayName}={}){ if(peerId)this.peerId=peerId; if(displayName)this.displayName=displayName; }
  _state(state,detail=''){ this.state=state; this.onState({state,detail,remotePeerId:this.remotePeerId,remoteName:this.remoteName}); }
  _attach(ch){
    this.channel=ch; ch.binaryType='arraybuffer';
    ch.onopen=()=>{this._state('ready','Прямой Wi-Fi канал готов');this._send({type:'hello',peerId:this.peerId,displayName:this.displayName});this._flush();};
    ch.onclose=()=>this._state('degraded','Прямой канал закрыт');
    ch.onerror=()=>this._state('degraded','Ошибка прямого канала');
    ch.onmessage=e=>this._receive(e.data);
  }
  _pc(){
    if(!this.RTCPeerConnectionImpl) throw new Error('WebRTC недоступен');
    this.close({preserveQueue:true,silent:true});
    const pc=new this.RTCPeerConnectionImpl({iceServers:[]}); this.pc=pc;
    pc.ondatachannel=e=>this._attach(e.channel);
    pc.onconnectionstatechange=()=>{const s=pc.connectionState;if(s==='connected')this._state('ready','Прямой Wi-Fi канал готов');else if(['failed','disconnected'].includes(s))this._state('degraded','Прямой канал потерян');};
    return pc;
  }
  _send(v){ if(this.channel?.readyState!=='open')return false; this.channel.send(JSON.stringify(v)); return true; }
  _receive(raw){
    if(typeof raw!=='string') return;
    let m; try{m=JSON.parse(raw);}catch{return;}
    if(m.type==='hello'){this.remotePeerId=m.peerId||'';this.remoteName=m.displayName||this.remotePeerId;if(!m.reply)this._send({type:'hello',peerId:this.peerId,displayName:this.displayName,reply:true});return;}
    if(m.type==='envelope'){this.onEnvelope(m.payload,{transportId:'wifi',from:m.from||this.remotePeerId,messageId:m.messageId||''});if(m.messageId)this._send({type:'ack',messageId:m.messageId});return;}
    if(m.type==='ack'){this.onEnvelope({type:'transport_ack',messageId:m.messageId},{transportId:'wifi',system:true});}
  }
  async _iceComplete(timeout=5000){
    if(this.pc?.iceGatheringState==='complete')return;
    await new Promise((resolve,reject)=>{const t=setTimeout(()=>{cleanup();reject(new Error('LAN маршрут не найден'));},timeout);const f=()=>{if(this.pc?.iceGatheringState==='complete'){cleanup();resolve();}};const cleanup=()=>{clearTimeout(t);this.pc?.removeEventListener?.('icegatheringstatechange',f);};this.pc.addEventListener('icegatheringstatechange',f);});
  }
  async createInvite(){
    const pc=this._pc(); this._attach(pc.createDataChannel('mesh-messenger',{ordered:true}));
    await pc.setLocalDescription(await pc.createOffer()); this._state('pairing','Создаём приглашение'); await this._iceComplete();
    this.pendingRole='offer'; return encodeSignal({v:1,role:'offer',peerId:this.peerId,displayName:this.displayName,description:pc.localDescription});
  }
  async applySignal(code){
    const s=decodeSignal(code);
    if(s.role==='offer'){const pc=this._pc();this.remotePeerId=s.peerId;this.remoteName=s.displayName||s.peerId;await pc.setRemoteDescription(s.description);await pc.setLocalDescription(await pc.createAnswer());this._state('pairing','Готовим ответ');await this._iceComplete();this.pendingRole='answer';return {role:'answer',response:encodeSignal({v:1,role:'answer',peerId:this.peerId,displayName:this.displayName,description:pc.localDescription})};}
    if(s.role==='answer'){if(!this.pc||this.pendingRole!=='offer')throw new Error('Сначала создайте приглашение');this.remotePeerId=s.peerId;this.remoteName=s.displayName||s.peerId;await this.pc.setRemoteDescription(s.description);this._state('connecting','Соединяем устройства');return {role:'connected'};}
    throw new Error('Неизвестный LAN-код');
  }
  isReady(){return this.channel?.readyState==='open'&&(this.state==='ready'||this.pc?.connectionState==='connected');}
  async send(payload,{messageId=id('msg')}={}){const packet={type:'envelope',messageId,from:this.peerId,payload};if(!this._send(packet)){this.outbox.push(packet);this._state('queued','Нет LAN маршрута — сообщение ждёт');return {queued:true,messageId};}return {queued:false,messageId};}
  _flush(){const q=this.outbox.splice(0);for(const m of q)if(!this._send(m))this.outbox.push(m);}
  close({preserveQueue=true,silent=false}={}){try{this.channel?.close();}catch{}try{this.pc?.close();}catch{}this.channel=null;this.pc=null;this.pendingRole='';if(!preserveQueue)this.outbox=[];if(!silent)this._state('idle','LAN отключён');}
  snapshot(){return {id:'wifi',state:this.state,ready:this.isReady(),remotePeerId:this.remotePeerId,remoteName:this.remoteName,queued:this.outbox.length};}
}
export const LanPairing={encode:encodeSignal,decode:decodeSignal};
