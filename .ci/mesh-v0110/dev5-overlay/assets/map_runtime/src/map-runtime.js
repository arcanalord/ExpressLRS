const statusEl = document.getElementById('status');
const fallbackEl = document.getElementById('fallback');
const mapEl = document.getElementById('map');
let map = null;
let pointSourceReady = false;
let pendingPoints = [];
let readySent = false;

function status(text){ statusEl.textContent = text; }
function bridgeTap(lat, lon){
  try { window.MeshBridge?.onMapTap(Number(lat), Number(lon)); } catch (_) {}
}
function bridgeReady(){
  if (readySent) return;
  readySent = true;
  try { window.MeshBridge?.onMapReady(); } catch (_) {}
}
function emptyStyle(){
  return {version:8,sources:{},layers:[{id:'background',type:'background',paint:{'background-color':'#151a20'}}]};
}
function vectorStyle(sourceUrl, layerNames=[]){
  const names=new Set(layerNames||[]);
  const pick=(...candidates)=>candidates.find(name=>names.has(name))||null;
  const layers=[
    {id:'background',type:'background',paint:{'background-color':'#eef2f4'}}
  ];
  const add=(layer)=>{ if(layer?.['source-layer']) layers.push(layer); };
  const landcover=pick('landcover','land_cover');
  const landuse=pick('landuse','land_use');
  const water=pick('water','water_polygons');
  const waterway=pick('waterway','waterways');
  const buildings=pick('buildings','building');
  const roads=pick('roads','transportation','road');
  const boundaries=pick('boundaries','boundary');
  const pois=pick('pois','poi');

  add(landcover&&{id:'landcover',type:'fill',source:'basemap','source-layer':landcover,paint:{'fill-color':'#dfe8dd','fill-opacity':0.72}});
  add(landuse&&{id:'landuse',type:'fill',source:'basemap','source-layer':landuse,paint:{'fill-color':'#e7e1d5','fill-opacity':0.56}});
  add(water&&{id:'water',type:'fill',source:'basemap','source-layer':water,paint:{'fill-color':'#a9cee5'}});
  add(waterway&&{id:'waterway',type:'line',source:'basemap','source-layer':waterway,paint:{'line-color':'#91c3e2','line-width':1.2}});
  add(buildings&&{id:'buildings',type:'fill',source:'basemap','source-layer':buildings,minzoom:12,paint:{'fill-color':'#d7d2ca','fill-outline-color':'#c0bbb4'}});
  if(roads){
    layers.push({id:'roads-casing',type:'line',source:'basemap','source-layer':roads,minzoom:6,paint:{'line-color':'#fff','line-width':['interpolate',['linear'],['zoom'],6,1.1,16,5.4]}});
    layers.push({id:'roads',type:'line',source:'basemap','source-layer':roads,minzoom:6,paint:{'line-color':'#c3b9aa','line-width':['interpolate',['linear'],['zoom'],6,0.6,16,3.1]}});
  }
  add(boundaries&&{id:'boundaries',type:'line',source:'basemap','source-layer':boundaries,paint:{'line-color':'#9aa5ad','line-width':0.8,'line-dasharray':[3,2]}});
  add(pois&&{id:'pois',type:'circle',source:'basemap','source-layer':pois,minzoom:12,paint:{'circle-radius':2.4,'circle-color':'#8b6f47','circle-opacity':0.75}});

  return {version:8,sources:{basemap:{type:'vector',url:sourceUrl}},layers};
}
function rasterStyle(tileUrl){
  return {version:8,sources:{basemap:{type:'raster',tiles:[tileUrl],tileSize:256}},layers:[
    {id:'basemap',type:'raster',source:'basemap'}
  ]};
}
function pointsGeoJson(points){
  return {type:'FeatureCollection',features:(points||[]).map(p=>({type:'Feature',geometry:{type:'Point',coordinates:[Number(p.lon),Number(p.lat)]},properties:{id:String(p.id||''),label:String(p.label||''),outgoing:Boolean(p.outgoing)}}))};
}
function installPointLayer(){
  if (!map || !map.isStyleLoaded()) return;
  const data=pointsGeoJson(pendingPoints);
  const existing=map.getSource('mesh-points');
  if(existing){existing.setData(data);pointSourceReady=true;return;}
  map.addSource('mesh-points',{type:'geojson',data});
  map.addLayer({id:'mesh-points-halo',type:'circle',source:'mesh-points',paint:{'circle-radius':9,'circle-color':'#ffffff','circle-opacity':0.9}});
  map.addLayer({id:'mesh-points',type:'circle',source:'mesh-points',paint:{'circle-radius':6,'circle-color':['case',['get','outgoing'],'#5f8cff','#ff7f66'],'circle-stroke-width':1,'circle-stroke-color':'#1b2230'}});
  pointSourceReady=true;
}
async function createMap(){
  try {
    const maplibregl = await import('../vendor/maplibre-gl.mjs');
    window.maplibregl = maplibregl;
    const protocol = new window.pmtiles.Protocol({metadata:true});
    maplibregl.addProtocol('pmtiles', protocol.tile);
    let style=emptyStyle(), center=[0,0], zoom=1, packageReady=false, mapMode='grid', mapError='';
    try {
      const url='https://app.local/offline/active.pmtiles';
      const archive=new window.pmtiles.PMTiles(url);
      protocol.add(archive);
      const header=await archive.getHeader();
      center=[header.centerLon||0,header.centerLat||0];
      zoom=header.centerZoom||Math.max(1,header.minZoom||1);
      if(header.tileType===window.pmtiles.TileType.Mvt){
        let layerNames=[];
        try {
          const metadata=await archive.getMetadata();
          layerNames=(metadata?.vector_layers||[]).map(layer=>String(layer?.id||'')).filter(Boolean);
        } catch (_) {}
        style=vectorStyle(`pmtiles://${url}`,layerNames);
      } else {
        style=rasterStyle(`pmtiles://${url}/{z}/{x}/{y}`);
      }
      packageReady=true;
      mapMode='pmtiles';
    } catch (e) {
      mapError=String(e||'PMTiles error');
      if(navigator.onLine!==false){
        style=rasterStyle('https://tile.openstreetmap.org/{z}/{x}/{y}.png');
        center=[0,0];
        zoom=2;
        mapMode='osm';
      }
    }
    map = new maplibregl.Map({container:'map',style,center,zoom,attributionControl:false,fadeDuration:0});
    map.addControl(new maplibregl.NavigationControl({showCompass:false}),'bottom-right');
    map.on('load',()=>{
      fallbackEl.style.display=mapMode==='grid'?'flex':'none';
      installPointLayer();
      if(mapMode==='pmtiles') status('Офлайн PMTiles');
      else if(mapMode==='osm') status('OSM · лёгкая карта');
      else status('Локальная сетка');
      bridgeReady();
    });
    map.on('error',event=>{
      if(mapMode==='pmtiles'){
        mapError=String(event?.error?.message||event?.error||mapError||'Ошибка PMTiles');
        status('Ошибка офлайн-карты');
      }
    });
    map.on('styledata',()=>{pointSourceReady=false;installPointLayer();});
    map.on('click',e=>bridgeTap(e.lngLat.lat,e.lngLat.lng));
  } catch (e) {
    mapEl.style.display='none';
    fallbackEl.style.display='flex';
    fallbackEl.textContent='Карта недоступна. Точки и координаты продолжают работать.';
    status('Локальная сетка');
    bridgeReady();
    fallbackEl.addEventListener('click', ev=>{
      const r=fallbackEl.getBoundingClientRect();
      const nx=(ev.clientX-r.left)/Math.max(1,r.width); const ny=(ev.clientY-r.top)/Math.max(1,r.height);
      bridgeTap((0.5-ny)*180,(nx-0.5)*360);
    });
  }
}
window.MeshMap={
  setPoints(points){pendingPoints=Array.isArray(points)?points:[];installPointLayer();},
  focus(lat,lon,zoom=15){if(map){map.easeTo({center:[Number(lon),Number(lat)],zoom:Number(zoom)||15,duration:250});}},
  reload(){location.reload();}
};
createMap();