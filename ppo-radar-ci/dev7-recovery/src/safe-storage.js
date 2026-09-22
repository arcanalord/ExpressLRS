const STATUS = Object.freeze({
  OK:'OK',
  MEMORY_FALLBACK:'MEMORY_FALLBACK',
  UNAVAILABLE:'UNAVAILABLE',
  READ_ERROR:'READ_ERROR',
  WRITE_ERROR:'WRITE_ERROR',
  REMOVE_ERROR:'REMOVE_ERROR',
  CORRUPT:'CORRUPT'
});

export const STORAGE_STATUS = STATUS;

function normalizeError(error) {
  if (!error) return 'unknown error';
  return String(error?.message ?? error);
}

export function createSafeStorage({
  getStorage = () => globalThis.localStorage,
  onIssue = () => {},
  memory = new Map()
} = {}) {
  let storage = null;
  let state = { status:STATUS.OK, persistent:true, lastError:null, issues:0 };

  try {
    storage = getStorage?.() ?? null;
    if (!storage) {
      state = { ...state, status:STATUS.UNAVAILABLE, persistent:false, lastError:'storage unavailable' };
      onIssue({ code:STATUS.UNAVAILABLE, error:'storage unavailable' });
    }
  } catch (error) {
    state = { ...state, status:STATUS.UNAVAILABLE, persistent:false, lastError:normalizeError(error), issues:state.issues+1 };
    onIssue({ code:STATUS.UNAVAILABLE, error:normalizeError(error) });
  }

  const note = (code, error) => {
    state = { ...state, status:code, persistent:Boolean(storage), lastError:normalizeError(error), issues:state.issues+1 };
    onIssue({ code, error:normalizeError(error) });
  };

  const getItem = (key) => {
    const k = String(key);
    if (!state.persistent && memory.has(k)) return memory.get(k);
    if (storage) {
      try {
        const value = storage.getItem(k);
        if (value != null) memory.set(k, String(value));
        return value;
      } catch (error) {
        note(STATUS.READ_ERROR, error);
      }
    }
    return memory.has(k) ? memory.get(k) : null;
  };

  const setItem = (key, value) => {
    const k = String(key), v = String(value);
    memory.set(k, v);
    if (storage) {
      try {
        storage.setItem(k, v);
        state = { ...state, status:STATUS.OK, persistent:true, lastError:null };
        return true;
      } catch (error) {
        note(STATUS.WRITE_ERROR, error);
      }
    }
    state = { ...state, status:STATUS.MEMORY_FALLBACK, persistent:false };
    return false;
  };

  const removeItem = (key) => {
    const k = String(key);
    memory.delete(k);
    if (storage) {
      try {
        storage.removeItem(k);
        return true;
      } catch (error) {
        note(STATUS.REMOVE_ERROR, error);
      }
    }
    return false;
  };

  const readJson = (key, fallback = null, validate = null) => {
    const raw = getItem(key);
    if (raw == null || raw === '') return { value:fallback, found:false, status:state.status, error:null };
    try {
      const value = JSON.parse(raw);
      if (typeof validate === 'function' && !validate(value)) throw new Error('stored value failed schema validation');
      return { value, found:true, status:state.status, error:null };
    } catch (error) {
      note(STATUS.CORRUPT, error);
      return { value:fallback, found:true, status:STATUS.CORRUPT, error };
    }
  };

  const writeJson = (key, value) => setItem(key, JSON.stringify(value));

  return Object.freeze({
    getItem,
    setItem,
    removeItem,
    readJson,
    writeJson,
    snapshot: () => Object.freeze({ ...state, memoryEntries:memory.size })
  });
}
