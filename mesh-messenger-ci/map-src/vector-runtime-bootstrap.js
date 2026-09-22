let maplibreReady = false;
try {
  const maplibregl = await import('../vendor/maplibre-gl.mjs');
  if (typeof maplibregl.setWorkerUrl === 'function') {
    maplibregl.setWorkerUrl(new URL('../vendor/maplibre-gl-worker.mjs', import.meta.url).href);
  }
  globalThis.maplibregl = maplibregl;
  maplibreReady = true;
} catch (error) {
  console.warn('MapLibre local runtime unavailable; raster/grid fallback remains active.', error);
}
globalThis.__meshVectorRuntimeLocal = Object.freeze({
  maplibreReady,
  pmtilesReady: Boolean(globalThis.pmtiles),
  offlineVendor: true,
});
await import('./app.js');
