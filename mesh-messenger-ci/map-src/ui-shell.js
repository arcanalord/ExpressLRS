export function createUiShell({
  documentRef = globalThis.document,
  windowRef = globalThis,
  storageGet = () => null,
  storageSet = () => {},
  onNetwork = () => {},
  onMap = () => {},
} = {}) {
  let currentView = 'chats';
  const $$ = (selector) => [...documentRef.querySelectorAll(selector)];

  function initTheme() {
    const requested = new URLSearchParams(windowRef.location?.search || '').get('theme');
    const stored = storageGet('mesh-theme');
    const theme = requested || stored || 'light';
    documentRef.documentElement.dataset.theme = theme === 'dark' ? 'dark' : 'light';
  }

  function toggleTheme() {
    const next = documentRef.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    documentRef.documentElement.dataset.theme = next;
    storageSet('mesh-theme', next);
    return next;
  }

  function setView(name) {
    currentView = name;
    $$('.view').forEach(v => v.classList.toggle('is-active', v.dataset.screen === name));
    $$('[data-nav] [data-view]').forEach(b => b.classList.toggle('is-active', b.dataset.view === name));
    windowRef.scrollTo?.({top:0, behavior:'instant'});
    if(name === 'network') onNetwork();
    if(name === 'map') onMap();
    return currentView;
  }

  return {
    initTheme,
    toggleTheme,
    setView,
    get currentView(){ return currentView; },
  };
}
