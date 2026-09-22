export const MAP_RUNTIME = Object.freeze({
  INIT: 'INIT',
  LOADING: 'LOADING',
  ONLINE: 'ONLINE',
  OFFLINE_LOCAL: 'OFFLINE_LOCAL',
  DEGRADED: 'DEGRADED',
  ERROR: 'ERROR'
});

export function createMapRuntimeState() {
  return Object.freeze({ state: MAP_RUNTIME.INIT, provider: null, localLayersAvailable: true, reason: null, updatedAt: 0 });
}

export function reduceMapRuntime(current, event) {
  const now = Number(event?.at ?? Date.now());
  switch (event?.type) {
    case 'MAP_LOADING':
      return Object.freeze({ ...current, state: MAP_RUNTIME.LOADING, provider: event.provider ?? current.provider, reason: null, updatedAt: now });
    case 'MAP_ONLINE':
      return Object.freeze({ ...current, state: MAP_RUNTIME.ONLINE, provider: event.provider ?? current.provider, reason: null, updatedAt: now });
    case 'MAP_OFFLINE_LOCAL':
      return Object.freeze({ ...current, state: MAP_RUNTIME.OFFLINE_LOCAL, provider: event.provider ?? 'LOCAL_PMTILES', reason: null, updatedAt: now });
    case 'MAP_DEGRADED':
      return Object.freeze({ ...current, state: MAP_RUNTIME.DEGRADED, provider: event.provider ?? current.provider, reason: event.reason ?? 'MAP_DEGRADED', updatedAt: now });
    case 'MAP_PROVIDER_ERROR':
    case 'MAP_NETWORK_ERROR':
    case 'MAP_RENDER_ERROR':
      return Object.freeze({ ...current, state: current.localLayersAvailable ? MAP_RUNTIME.DEGRADED : MAP_RUNTIME.ERROR, reason: event.reason ?? event.type, updatedAt: now });
    case 'MAP_FATAL':
      return Object.freeze({ ...current, state: MAP_RUNTIME.ERROR, localLayersAvailable: false, reason: event.reason ?? 'MAP_FATAL', updatedAt: now });
    default:
      return current;
  }
}

export function mapRuntimeLabel(runtime) {
  switch (runtime?.state) {
    case MAP_RUNTIME.ONLINE: return 'Карта · Online';
    case MAP_RUNTIME.OFFLINE_LOCAL: return 'Карта · Offline PMTiles';
    case MAP_RUNTIME.DEGRADED: return 'Карта · фон недоступен · локальные слои работают';
    case MAP_RUNTIME.ERROR: return 'Карта · ошибка';
    case MAP_RUNTIME.LOADING: return 'Карта · загрузка';
    default: return 'Карта · инициализация';
  }
}
