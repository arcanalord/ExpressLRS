import test from 'node:test';
import assert from 'node:assert/strict';
import { createSafeStorage, STORAGE_STATUS } from '../src/safe-storage.js';

test('safe storage uses persistent storage when healthy', () => {
  const data=new Map();
  const storage={getItem:k=>data.get(k)??null,setItem:(k,v)=>data.set(k,v),removeItem:k=>data.delete(k)};
  const safe=createSafeStorage({getStorage:()=>storage});
  assert.equal(safe.setItem('a','1'),true);
  assert.equal(safe.getItem('a'),'1');
  assert.equal(safe.snapshot().persistent,true);
});

test('localStorage SecurityError falls back to memory', () => {
  const seen=[];
  const safe=createSafeStorage({getStorage:()=>{throw new Error('SecurityError');},onIssue:i=>seen.push(i)});
  assert.equal(safe.setItem('a','1'),false);
  assert.equal(safe.getItem('a'),'1');
  assert.equal(safe.snapshot().status,STORAGE_STATUS.MEMORY_FALLBACK);
  assert.equal(safe.snapshot().persistent,false);
  assert.ok(seen.length>=1);
});

test('quota failure preserves the value in memory fallback', () => {
  const storage={getItem:()=>null,setItem:()=>{throw new Error('QuotaExceededError');},removeItem:()=>{}};
  const safe=createSafeStorage({getStorage:()=>storage});
  assert.equal(safe.setItem('session','value'),false);
  assert.equal(safe.getItem('session'),'value');
  assert.equal(safe.snapshot().status,STORAGE_STATUS.MEMORY_FALLBACK);
});

test('corrupt JSON returns fallback instead of throwing', () => {
  const storage={getItem:()=>'{bad',setItem:()=>{},removeItem:()=>{}};
  const safe=createSafeStorage({getStorage:()=>storage});
  const out=safe.readJson('x',{ok:false});
  assert.deepEqual(out.value,{ok:false});
  assert.equal(out.status,STORAGE_STATUS.CORRUPT);
});

test('schema validation failure is reported as corrupt', () => {
  const storage={getItem:()=>'{"version":99}',setItem:()=>{},removeItem:()=>{}};
  const safe=createSafeStorage({getStorage:()=>storage});
  const out=safe.readJson('x',null,v=>v.version===1);
  assert.equal(out.value,null);
  assert.equal(out.status,STORAGE_STATUS.CORRUPT);
});
