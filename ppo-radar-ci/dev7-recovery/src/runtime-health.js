export const HEALTH_LEVEL = Object.freeze({
  READY:'READY',
  DEGRADED:'DEGRADED',
  ERROR:'ERROR',
  STARTING:'STARTING'
});

export function createRuntimeHealth() {
  return Object.freeze({
    level: HEALTH_LEVEL.STARTING,
    bootStage: 'IDLE',
    mapState: 'INIT',
    sourceState: 'UNKNOWN',
    nativeState: 'UNKNOWN',
    updatedAt: 0,
    messages: []
  });
}

export function combineRuntimeHealth({ boot, map, sourceSummary, native, storage, ui, at = Date.now() } = {}) {
  const messages = [];
  let level = HEALTH_LEVEL.READY;

  if (!boot?.ready) level = boot?.fatal ? HEALTH_LEVEL.ERROR : HEALTH_LEVEL.STARTING;
  if (boot?.degraded && level !== HEALTH_LEVEL.ERROR) level = HEALTH_LEVEL.DEGRADED;
  if (boot?.detail) messages.push(String(boot.detail));

  if (map?.state === 'ERROR' && level !== HEALTH_LEVEL.ERROR) level = HEALTH_LEVEL.DEGRADED;
  else if (['DEGRADED','LOADING'].includes(map?.state) && level === HEALTH_LEVEL.READY) level = map?.state === 'LOADING' ? HEALTH_LEVEL.STARTING : HEALTH_LEVEL.DEGRADED;
  if (map?.reason) messages.push(String(map.reason));

  const issues = Number(sourceSummary?.transportIssues ?? 0);
  if (issues > 0 && level === HEALTH_LEVEL.READY) level = HEALTH_LEVEL.DEGRADED;
  if (issues > 0) messages.push(`Источники: проблем ${issues}`);

  const nativeState = native?.state ?? 'UNKNOWN';
  if (['ERROR','DEGRADED'].includes(nativeState) && level !== HEALTH_LEVEL.ERROR) level = HEALTH_LEVEL.DEGRADED;
  if (native?.message) messages.push(String(native.message));

  const storageState = storage?.status ?? 'UNKNOWN';
  if (storage && storage.persistent === false && level === HEALTH_LEVEL.READY) level = HEALTH_LEVEL.DEGRADED;
  if (storage && storage.persistent === false) messages.push(`Storage: ${storageState}`);

  const uiIssueCount = Number(ui?.issues ?? 0);
  const uiCriticalMissing = Number(ui?.criticalMissing ?? 0);
  if (uiCriticalMissing > 0 && level !== HEALTH_LEVEL.ERROR) level = HEALTH_LEVEL.DEGRADED;
  if (uiIssueCount > 0) messages.push(`UI: проблем ${uiIssueCount}`);

  return Object.freeze({
    level,
    bootStage: boot?.stage ?? 'IDLE',
    mapState: map?.state ?? 'INIT',
    sourceState: issues > 0 ? 'ISSUE' : 'OK',
    nativeState,
    storageState,
    uiState: uiCriticalMissing > 0 ? 'DEGRADED' : 'OK',
    updatedAt: Number(at),
    messages: [...new Set(messages)]
  });
}

export function runtimeHealthLabel(health) {
  switch (health?.level) {
    case HEALTH_LEVEL.READY: return 'Система · готова';
    case HEALTH_LEVEL.DEGRADED: return 'Система · ограниченный режим';
    case HEALTH_LEVEL.ERROR: return 'Система · ошибка';
    default: return 'Система · запуск';
  }
}
