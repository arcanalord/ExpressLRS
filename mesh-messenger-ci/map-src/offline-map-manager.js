const CACHE_NAME = 'mesh-offline-maps-v1';
const META_KEY = 'mesh-offline-map-packages-v1';

function safeRead(storage, key, fallback) {
  try { return JSON.parse(storage?.getItem(key) || '') || fallback; } catch { return fallback; }
}
function safeWrite(storage, key, value) {
  try { storage?.setItem(key, JSON.stringify(value)); } catch {}
}
function canonicalTileUrl(z, x, y) {
  return `https://offline.mesh.local/${z}/${x}/${y}`;
}
function lngToX(lng, z) { return Math.floor(((lng + 180) / 360) * 2 ** z); }
function latToY(lat, z) {
  const clamped = Math.max(-85.05112878, Math.min(85.05112878, lat));
  const rad = clamped * Math.PI / 180;
  return Math.floor((1 - Math.asinh(Math.tan(rad)) / Math.PI) / 2 * 2 ** z);
}
function tileRange(bounds, z) {
  const n = 2 ** z;
  const minX = Math.max(0, Math.min(n - 1, lngToX(bounds.west, z)));
  const maxX = Math.max(0, Math.min(n - 1, lngToX(bounds.east, z)));
  const minY = Math.max(0, Math.min(n - 1, latToY(bounds.north, z)));
  const maxY = Math.max(0, Math.min(n - 1, latToY(bounds.south, z)));
  return { minX: Math.min(minX, maxX), maxX: Math.max(minX, maxX), minY: Math.min(minY, maxY), maxY: Math.max(minY, maxY) };
}
function enumerateTiles(bounds, minZoom, maxZoom) {
  const out = [];
  for (let z = minZoom; z <= maxZoom; z += 1) {
    const r = tileRange(bounds, z);
    for (let y = r.minY; y <= r.maxY; y += 1) {
      for (let x = r.minX; x <= r.maxX; x += 1) out.push({ z, x, y });
    }
  }
  return out;
}
function providerUrl(provider, tile) {
  return provider.urlTemplate
    .replace('{z}', tile.z)
    .replace('{x}', tile.x)
    .replace('{y}', tile.y);
}
function makeId() {
  return globalThis.crypto?.randomUUID?.() || `pkg-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

export class OfflineMapManager {
  constructor({ storage = globalThis.localStorage, cachesImpl = globalThis.caches, provider = null } = {}) {
    this.storage = storage;
    this.caches = cachesImpl;
    this.provider = provider?.offlineAllowed ? provider : null;
    this.packages = safeRead(storage, META_KEY, []);
  }

  setProvider(provider) {
    this.provider = provider?.offlineAllowed ? provider : null;
  }

  list() {
    return this.packages.slice().sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)));
  }

  estimate(bounds, minZoom, maxZoom, averageTileBytes = 24000) {
    const tiles = enumerateTiles(bounds, minZoom, maxZoom);
    return { tileCount: tiles.length, estimatedBytes: tiles.length * averageTileBytes };
  }

  async cachedTile(z, x, y) {
    if (!this.caches) return null;
    const cache = await this.caches.open(CACHE_NAME);
    return cache.match(canonicalTileUrl(z, x, y));
  }

  async download({ name, bounds, minZoom, maxZoom, onProgress = () => {}, signal } = {}) {
    if (!this.provider) throw new Error('OFFLINE_PROVIDER_NOT_CONFIGURED');
    const tiles = enumerateTiles(bounds, minZoom, maxZoom);
    if (!tiles.length) throw new Error('OFFLINE_EMPTY_REGION');
    const maxTiles = Number(this.provider.maxTiles || 12000);
    if (tiles.length > maxTiles) throw new Error('OFFLINE_REGION_TOO_LARGE');
    const cache = await this.caches.open(CACHE_NAME);
    const id = makeId();
    const startedAt = new Date().toISOString();
    let done = 0;
    let bytes = 0;

    for (const tile of tiles) {
      if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
      const url = providerUrl(this.provider, tile);
      const response = await fetch(url, { signal, cache: 'default' });
      if (!response.ok) throw new Error(`OFFLINE_TILE_HTTP_${response.status}`);
      const body = await response.arrayBuffer();
      bytes += body.byteLength;
      const headers = new Headers(response.headers);
      headers.set('x-mesh-offline-provider', this.provider.id || 'custom');
      await cache.put(canonicalTileUrl(tile.z, tile.x, tile.y), new Response(body, { status: 200, headers }));
      done += 1;
      onProgress({ done, total: tiles.length, bytes });
    }

    const record = {
      id,
      name: String(name || 'Офлайн-карта').trim() || 'Офлайн-карта',
      bounds,
      minZoom,
      maxZoom,
      tileCount: tiles.length,
      bytes,
      providerId: this.provider.id || 'custom',
      providerName: this.provider.name || 'Offline provider',
      attribution: this.provider.attribution || '',
      createdAt: startedAt,
      updatedAt: new Date().toISOString(),
    };
    this.packages.push(record);
    safeWrite(this.storage, META_KEY, this.packages);
    return record;
  }

  async remove(id) {
    const pkg = this.packages.find(item => item.id === id);
    if (!pkg) return false;
    const cache = await this.caches.open(CACHE_NAME);
    const tiles = enumerateTiles(pkg.bounds, pkg.minZoom, pkg.maxZoom);
    await Promise.all(tiles.map(tile => cache.delete(canonicalTileUrl(tile.z, tile.x, tile.y))));
    this.packages = this.packages.filter(item => item.id !== id);
    safeWrite(this.storage, META_KEY, this.packages);
    return true;
  }

  rename(id, name) {
    const pkg = this.packages.find(item => item.id === id);
    if (!pkg) return false;
    pkg.name = String(name || '').trim() || pkg.name;
    pkg.updatedAt = new Date().toISOString();
    safeWrite(this.storage, META_KEY, this.packages);
    return true;
  }
}

export function createOfflineMapManager(options) {
  return new OfflineMapManager(options);
}
