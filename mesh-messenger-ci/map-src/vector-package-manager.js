const DB_NAME='mesh-vector-map-packages-v1';
const DB_STORE='packages';
const META_KEY='mesh-vector-map-packages-meta-v1';
const ACTIVE_KEY='mesh-vector-map-active-v1';

function safeRead(storage,key,fallback){try{return JSON.parse(storage?.getItem(key)||'')||fallback}catch{return fallback}}
function safeWrite(storage,key,value){try{storage?.setItem(key,JSON.stringify(value))}catch{}}
function makeId(){return globalThis.crypto?.randomUUID?.()||`pmtiles-${Date.now().toString(36)}-${Math.random().toString(36).slice(2,8)}`}

class PackageStore{
  constructor(indexedDBImpl=globalThis.indexedDB){this.indexedDB=indexedDBImpl;this.dbPromise=null}
  _db(){
    if(!this.indexedDB)return Promise.reject(new Error('VECTOR_STORAGE_UNAVAILABLE'));
    if(this.dbPromise)return this.dbPromise;
    this.dbPromise=new Promise((resolve,reject)=>{
      const req=this.indexedDB.open(DB_NAME,1);
      req.onupgradeneeded=()=>{const db=req.result;if(!db.objectStoreNames.contains(DB_STORE))db.createObjectStore(DB_STORE)};
      req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error||new Error('VECTOR_STORAGE_OPEN_FAILED'));
    });
    return this.dbPromise;
  }
  async put(id,blob){const db=await this._db();return new Promise((resolve,reject)=>{const tx=db.transaction(DB_STORE,'readwrite');tx.objectStore(DB_STORE).put(blob,id);tx.oncomplete=()=>resolve(true);tx.onerror=()=>reject(tx.error)})}
  async get(id){const db=await this._db();return new Promise((resolve,reject)=>{const req=db.transaction(DB_STORE,'readonly').objectStore(DB_STORE).get(id);req.onsuccess=()=>resolve(req.result||null);req.onerror=()=>reject(req.error)})}
  async delete(id){const db=await this._db();return new Promise((resolve,reject)=>{const tx=db.transaction(DB_STORE,'readwrite');tx.objectStore(DB_STORE).delete(id);tx.oncomplete=()=>resolve(true);tx.onerror=()=>reject(tx.error)})}
}

export class VectorPackageManager{
  constructor({storage=globalThis.localStorage,indexedDBImpl=globalThis.indexedDB}={}){
    this.storage=storage;this.store=new PackageStore(indexedDBImpl);this.meta=safeRead(storage,META_KEY,[]);
  }
  list(){return this.meta.slice().sort((a,b)=>String(b.updatedAt).localeCompare(String(a.updatedAt)))}
  activeId(){try{return this.storage?.getItem(ACTIVE_KEY)||''}catch{return ''}}
  setActive(id){try{if(id)this.storage?.setItem(ACTIVE_KEY,id);else this.storage?.removeItem(ACTIVE_KEY)}catch{}}
  async importFile(file,{name,attribution=''}={}){
    if(!file||!String(file.name||'').toLowerCase().endsWith('.pmtiles'))throw new Error('PMTILES_FILE_REQUIRED');
    const id=makeId(),blob=file instanceof Blob?file:new Blob([file]);
    await this.store.put(id,blob);
    const now=new Date().toISOString();
    const record={id,name:String(name||file.name||'Offline PMTiles'),fileName:file.name||`${id}.pmtiles`,bytes:blob.size,attribution,createdAt:now,updatedAt:now,kind:'pmtiles'};
    this.meta.push(record);safeWrite(this.storage,META_KEY,this.meta);return record;
  }
  async download({url,name='Offline PMTiles',attribution='',onProgress=()=>{},signal}={}){
    if(!url)throw new Error('PMTILES_URL_REQUIRED');
    const response=await fetch(url,{signal});
    if(!response.ok)throw new Error(`PMTILES_HTTP_${response.status}`);
    const total=Number(response.headers.get('content-length')||0);
    let blob;
    if(response.body?.getReader){
      const reader=response.body.getReader(),parts=[];let doneBytes=0;
      for(;;){const {done,value}=await reader.read();if(done)break;parts.push(value);doneBytes+=value.byteLength;onProgress({bytes:doneBytes,total});}
      blob=new Blob(parts,{type:'application/vnd.pmtiles'});
    }else{blob=await response.blob();onProgress({bytes:blob.size,total:blob.size})}
    const file=new File([blob],`${makeId()}.pmtiles`,{type:'application/vnd.pmtiles'});
    return this.importFile(file,{name,attribution});
  }
  async file(id){
    const meta=this.meta.find(x=>x.id===id);if(!meta)return null;
    const blob=await this.store.get(id);if(!blob)return null;
    return new File([blob],`mesh-${id}.pmtiles`,{type:'application/vnd.pmtiles'});
  }
  async remove(id){await this.store.delete(id);this.meta=this.meta.filter(x=>x.id!==id);safeWrite(this.storage,META_KEY,this.meta);if(this.activeId()===id)this.setActive('');return true}
}

export function createVectorPackageManager(options){return new VectorPackageManager(options)}
