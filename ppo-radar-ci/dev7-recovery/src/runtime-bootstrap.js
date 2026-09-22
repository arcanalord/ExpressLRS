export const BOOT_STAGE = Object.freeze({
  IDLE: 'IDLE',
  HELP: 'HELP',
  SCENARIO: 'SCENARIO',
  CORE: 'CORE',
  MAP: 'MAP',
  READY: 'READY',
  DEGRADED: 'DEGRADED',
  ERROR: 'ERROR'
});

export function createBootState() {
  return Object.freeze({
    stage: BOOT_STAGE.IDLE,
    ready: false,
    degraded: false,
    fatal: false,
    detail: null,
    failures: []
  });
}

function snapshot(state, patch = {}) {
  return Object.freeze({ ...state, ...patch, failures: [...(patch.failures ?? state.failures ?? [])] });
}

export function createEmbeddedFallbackScenario() {
  return Object.freeze({
    name: 'embedded-runtime-fallback',
    durationMs: 12000,
    initialSources: [
      { id:'fallback-radar', label:'Тестовый источник', type:'RADAR', connectionState:'CONNECTED', lastUpdate:0, latencyMs:0 }
    ],
    initialPosts: [
      { id:'fallback-post', name:'Тестовый пост', lat:54.3300, lon:48.3850, altitude:0, coverageKm:5, sourceId:'fallback-radar', sourceType:'REPLAY', color:'#5aa8ff', lastUpdate:0 }
    ],
    initialObjects: [
      { id:'fallback-object', label:'Тестовый объект', sourceId:'fallback-radar', lat:54.3450, lon:48.4000, altitude:300, confidence:0.75, color:'#ff7a66', lastUpdate:0, history:[{at:0,lat:54.3450,lon:48.4000,altitude:300}] }
    ],
    events: [
      { at:2000, type:'OBJECT_UPDATE', object:{ id:'fallback-object', sourceId:'fallback-radar', lat:54.3430, lon:48.4040, altitude:295, confidence:0.78 } },
      { at:5000, type:'OBJECT_UPDATE', object:{ id:'fallback-object', sourceId:'fallback-radar', lat:54.3400, lon:48.4090, altitude:285, confidence:0.80 } },
      { at:8000, type:'SELECT_OBJECT', objectId:'fallback-object' }
    ]
  });
}

export async function loadJsonWithFallback(url, {
  fetchImpl = globalThis.fetch,
  fallback = createEmbeddedFallbackScenario,
  validate = (value) => value && typeof value === 'object'
} = {}) {
  if (typeof fetchImpl !== 'function') {
    return { value: typeof fallback === 'function' ? fallback() : fallback, recovered:true, error:new Error('fetch unavailable') };
  }
  try {
    const response = await fetchImpl(url, { cache:'no-store' });
    if (!response?.ok) throw new Error(`HTTP ${response?.status ?? 'ERR'}`);
    const value = await response.json();
    if (!validate(value)) throw new Error('invalid JSON payload');
    return { value, recovered:false, error:null };
  } catch (error) {
    const value = typeof fallback === 'function' ? await fallback(error) : fallback;
    return { value, recovered:true, error };
  }
}

export function withTimeout(task, timeoutMs, label = 'operation', {
  setTimer = globalThis.setTimeout,
  clearTimer = globalThis.clearTimeout
} = {}) {
  const ms = Math.max(1, Number(timeoutMs) || 1);
  const work = typeof task === 'function' ? Promise.resolve().then(task) : Promise.resolve(task);
  return new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimer(() => {
      if (settled) return;
      settled = true;
      reject(new Error(`${label} timeout after ${ms} ms`));
    }, ms);
    work.then((value) => {
      if (settled) return;
      settled = true;
      clearTimer?.(timer);
      resolve(value);
    }, (error) => {
      if (settled) return;
      settled = true;
      clearTimer?.(timer);
      reject(error);
    });
  });
}

export function installRuntimeGuards({
  target = globalThis,
  onError = () => {}
} = {}) {
  if (!target?.addEventListener) return () => {};
  const errorHandler = (event) => onError({ type:'error', error:event?.error ?? event?.message ?? 'runtime error' });
  const rejectionHandler = (event) => onError({ type:'unhandledrejection', error:event?.reason ?? 'unhandled rejection' });
  target.addEventListener('error', errorHandler);
  target.addEventListener('unhandledrejection', rejectionHandler);
  return () => {
    target.removeEventListener?.('error', errorHandler);
    target.removeEventListener?.('unhandledrejection', rejectionHandler);
  };
}

export async function runBootSequence({
  initHelp,
  loadScenario,
  fallbackScenario,
  createCore,
  initMap,
  mapTimeoutMs = 8000,
  onState = () => {}
} = {}) {
  let state = createBootState();
  const publish = (patch) => { state = snapshot(state, patch); onState(state); return state; };

  try {
    publish({ stage: BOOT_STAGE.HELP, detail: 'Инициализация справки' });
    await initHelp?.();
  } catch (error) {
    publish({ degraded: true, failures: [...state.failures, { stage: BOOT_STAGE.HELP, error: String(error?.message ?? error) }] });
  }

  let scenario = null;
  publish({ stage: BOOT_STAGE.SCENARIO, detail: 'Загрузка тестового сценария' });
  try {
    scenario = await loadScenario?.();
  } catch (error) {
    if (fallbackScenario) {
      scenario = typeof fallbackScenario === 'function' ? await fallbackScenario(error) : fallbackScenario;
      publish({ degraded: true, failures: [...state.failures, { stage: BOOT_STAGE.SCENARIO, error: String(error?.message ?? error), recovered: true }] });
    } else {
      publish({ stage: BOOT_STAGE.ERROR, fatal: true, detail: 'Сценарий не загружен', failures: [...state.failures, { stage: BOOT_STAGE.SCENARIO, error: String(error?.message ?? error) }] });
      return { state, scenario: null, core: null, map: null };
    }
  }

  let core = null;
  publish({ stage: BOOT_STAGE.CORE, detail: 'Запуск core' });
  try {
    core = await createCore?.(scenario);
  } catch (error) {
    publish({ stage: BOOT_STAGE.ERROR, fatal: true, detail: 'Core не запущен', failures: [...state.failures, { stage: BOOT_STAGE.CORE, error: String(error?.message ?? error) }] });
    return { state, scenario, core: null, map: null };
  }

  let map = null;
  publish({ stage: BOOT_STAGE.MAP, detail: 'Запуск карты' });
  try {
    if (initMap) map = await withTimeout(() => initMap(), mapTimeoutMs, 'Map runtime');
  } catch (error) {
    publish({ degraded: true, failures: [...state.failures, { stage: BOOT_STAGE.MAP, error: String(error?.message ?? error), recovered: true }] });
  }

  publish({
    stage: state.degraded ? BOOT_STAGE.DEGRADED : BOOT_STAGE.READY,
    ready: true,
    fatal: false,
    detail: state.degraded ? 'Приложение запущено с ограничениями' : 'Готово'
  });
  return { state, scenario, core, map };
}
