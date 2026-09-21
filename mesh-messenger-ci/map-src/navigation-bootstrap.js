// Mesh Messenger app-shell navigation bootstrap.
// Owns only the active view and navigation DOM wiring.
// Domain rendering remains in app.js through onActivate().
export function createNavigationBootstrap({
  initialView = 'chats',
  documentRef = globalThis.document,
  windowRef = globalThis.window,
  onActivate = () => {},
} = {}) {
  let currentView = initialView;
  let wired = false;

  function setView(name) {
    currentView = String(name || initialView);
    documentRef.querySelectorAll('.view').forEach(view => {
      view.classList.toggle('is-active', view.dataset.screen === currentView);
    });
    documentRef.querySelectorAll('[data-nav] [data-view]').forEach(button => {
      button.classList.toggle('is-active', button.dataset.view === currentView);
    });
    windowRef?.scrollTo?.({ top: 0, behavior: 'instant' });
    onActivate(currentView);
    return currentView;
  }

  function wire() {
    if (wired) return;
    wired = true;
    documentRef.querySelectorAll('[data-nav] [data-view]').forEach(button => {
      button.addEventListener('click', () => setView(button.dataset.view));
    });
    documentRef.querySelectorAll('[data-open-network]').forEach(button => {
      button.addEventListener('click', () => setView('network'));
    });
  }

  return Object.freeze({
    setView,
    wire,
    current: () => currentView,
  });
}
