export const NATIVE_STATE = Object.freeze({
  WEB:'WEB',
  CONNECTING:'CONNECTING',
  READY:'READY',
  DEGRADED:'DEGRADED',
  ERROR:'ERROR'
});

function normalizePayload(value) {
  if (value == null) return null;
  if (typeof value === 'string') {
    try { return JSON.parse(value); } catch { return { raw:value }; }
  }
  return value;
}

export function createNativeRuntime({
  bridgeProvider = () => globalThis.AndroidBridge,
  protocolVersion = 1,
  onState = () => {}
} = {}) {
  let state = { state:NATIVE_STATE.WEB, protocolVersion, appReady:false, nativeReady:false, capabilities:[], message:null, updatedAt:0 };
  let readySent = false;

  const publish = (patch) => {
    state = Object.freeze({ ...state, ...patch, updatedAt:Date.now(), capabilities:[...(patch.capabilities ?? state.capabilities ?? [])] });
    onState(state);
    return state;
  };

  const bridge = () => {
    try { return bridgeProvider?.() ?? null; }
    catch (error) { publish({ state:NATIVE_STATE.DEGRADED, message:String(error?.message ?? error) }); return null; }
  };

  const safeCall = (method, ...args) => {
    const b = bridge();
    if (!b) { publish({ state:NATIVE_STATE.WEB, message:null }); return { ok:false, reason:'BRIDGE_UNAVAILABLE' }; }
    const fn = b?.[method];
    if (typeof fn !== 'function') { publish({ state:NATIVE_STATE.DEGRADED, message:`Native capability missing: ${method}` }); return { ok:false, reason:'CAPABILITY_MISSING' }; }
    try { return { ok:true, value:fn.apply(b,args) }; }
    catch (error) { publish({ state:NATIVE_STATE.DEGRADED, message:String(error?.message ?? error) }); return { ok:false, reason:'BRIDGE_ERROR', error }; }
  };

  const markAppReady = ({ appVersion = 'unknown', capabilities = [] } = {}) => {
    if (readySent) return state;
    readySent = true;
    const b = bridge();
    if (!b) return publish({ state:NATIVE_STATE.WEB, appReady:true, nativeReady:false, capabilities:[] });
    publish({ state:NATIVE_STATE.CONNECTING, appReady:true, nativeReady:false, capabilities:[] });
    const payload = JSON.stringify({ protocolVersion, appVersion, capabilities:[...capabilities] });
    const result = safeCall('appReady', payload);
    if (!result.ok) return publish({ state:NATIVE_STATE.DEGRADED, appReady:true, message:result.reason });
    return state;
  };

  const markNativeReady = (payload) => {
    const value = normalizePayload(payload) ?? {};
    const caps = Array.isArray(value.capabilities) ? value.capabilities.map(String) : [];
    return publish({ state:NATIVE_STATE.READY, nativeReady:true, appReady:true, capabilities:caps, message:null });
  };

  return Object.freeze({
    snapshot:()=>state,
    safeCall,
    markAppReady,
    markNativeReady
  });
}
