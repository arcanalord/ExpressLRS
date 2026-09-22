import { createOpenMapTilesBasicStyle } from './openmaptiles-basic-style.js';

let sharedProtocol = null;

function runtime() {
  return { maplibregl: globalThis.maplibregl, pmtiles: globalThis.pmtiles };
}

function ensureProtocol() {
  const { maplibregl, pmtiles } = runtime();
  if (!maplibregl || !pmtiles) throw new Error('VECTOR_RUNTIME_UNAVAILABLE');
  if (!sharedProtocol) {
    sharedProtocol = new pmtiles.Protocol({ metadata: true });
    maplibregl.addProtocol('pmtiles', sharedProtocol.tile);
  }
  return { maplibregl, pmtiles, protocol: sharedProtocol };
}

export class VectorMapAdapter {
  constructor({ container } = {}) {
    this.container = container;
    this.map = null;
    this.archive = null;
    this.activePackageId = '';
    this.header = null;
  }

  isSupported() {
    const { maplibregl, pmtiles } = runtime();
    return Boolean(this.container && maplibregl && pmtiles);
  }

  ensureMap() {
    if (this.map) return this.map;
    const { maplibregl } = ensureProtocol();
    this.map = new maplibregl.Map({
      container: this.container,
      interactive: false,
      attributionControl: false,
      fadeDuration: 0,
      style: { version:8, sources:{}, layers:[{id:'background',type:'background',paint:{'background-color':'#eef2f4'}}] },
      center: [0,0],
      zoom: 1,
    });
    return this.map;
  }

  async activateFile(file, { id='', attribution='' } = {}) {
    const { pmtiles, protocol } = ensureProtocol();
    const map = this.ensureMap();
    const source = new pmtiles.FileSource(file);
    const archive = new pmtiles.PMTiles(source);
    protocol.add(archive);
    const header = await archive.getHeader();
    const key = source.getKey();
    map.setStyle(createOpenMapTilesBasicStyle({
      sourceUrl: `pmtiles://${key}`,
      attribution,
    }));
    this.archive = archive;
    this.activePackageId = id;
    this.header = header;
    this.container.hidden = false;
    return header;
  }

  syncView({ longitude, latitude, zoom }) {
    if (!this.map || this.container.hidden) return;
    this.map.jumpTo({ center:[longitude,latitude], zoom:Number(zoom)||1, bearing:0, pitch:0 });
  }

  deactivate() {
    this.activePackageId = '';
    this.archive = null;
    this.header = null;
    if (this.container) this.container.hidden = true;
  }

  destroy() {
    this.map?.remove();
    this.map = null;
    this.deactivate();
  }
}

export function createVectorMapAdapter(options) {
  return new VectorMapAdapter(options);
}
