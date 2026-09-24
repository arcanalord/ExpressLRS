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
function vectorStyle(sourceUrl){
  return {version:8,sources:{basemap:{type:'vector',url:sourceUrl}},layers:[
    {id:'background',type:'background',paint:{'background-color':'#eef2f4'}},
    {id:'landcover',type:'fill',source:'basemap','source-layer':'landcover',paint:{'fill-color':'#dfe8dd','fill-opacity':0.72}},
    {id:'landuse',type:'fill',source:'basemap','source-layer':'landuse',paint:{'fill-color':'#e7e1d5','fill-opacity':0.56}},
    {id:'water',type:'fill',source:'basemap','source-layer':'water',paint:{'fill-color':'#a9cee5'}},
    {id:'waterway',type:'line',source:'basemap','source-layer':'waterway',paint:{'line-color':'#91c3e2','line-width':1.2}},
    {id:'buildings-v4',type:'fill',source:'basemap','source-layer':'buildings',minzoom:12,paint:{'fill-color':'#d7d2ca','fill-outline-color':'#c0bbb4'}},
    {id:'buildings-legacy',type:'fill',source:'basemap','source-layer':'building',minzoom:12,paint:{'fill-color':'#d7d2ca','fill-outline-color':'#c0bbb4'}},
    {id:'roads-v4-casing',type:'line',source:'basemap','source-layer':'roads',minzoom:6,paint:{'line-color':'#fff','line-width':['interpolate',['linear'],['zoom'],6,1.1,16,5.4]}},
    {id:'roads-v4',type:'line',source:'basemap','source-layer':'roads',minzoom:6,paint:{'line-color':'#c3b9aa','line-width':['interpolate',['linear'],['zoom'],6,0.6,16,3.1]}},
    {id:'roads-legacy-casing',type:'line',source:'basemap','source-layer':'transportation',minzoom:6,paint:{'line-color':'#fff','line-width':['interpolate',['linear'],['zoom'],6,1.1,16,5.4]}},
    {id:'roads-legacy',type:'line',source:'basemap','source-layer':'transportation',minzoom:6,paint:{'line-color':'#c3b9aa','line-width':['interpolate',['linear'],['zoom'],6,0.6,16,3.1]}},
    {id:'boundaries-v4',type:'line',source:'basemap','source-layer':'boundaries',paint:{'line-color':'#9aa5ad','line-width':0.8,'line-dasharray':[3,2]}},
    {id:'boundaries-legacy',type:'line',source:'basemap','source-layer':'boundary',paint:{'line-color':'#9aa5ad','line-width':0.8,'line-dasharray':[3,2]}},
    {id:'pois-v4',type:'circle',source:'basemap','source-layer':'pois',minzoom:12,paint:{'circle-radius':2.4,'circle-color':'#8b6f47','circle-opacity':0.75}}
  ]};
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
    let style=emptyStyle(), center=[0,0], zoom=1, packageReady=false;
    try {
      const url='https://app.local/offline/active.pmtiles';
      const archive=new window.pmtiles.PMTiles(url);
      protocol.add(archive);
      const header=await archive.getHeader();
      center=[header.centerLon||0,header.centerLat||0]; zoom=header.centerZoom||Math.max(1,header.minZoom||1);
      if(header.tileType===window.pmtiles.TileType.Mvt){
        style=vectorStyle(`pmtiles://${url}`);
      } else {
        style=rasterStyle(`pmtiles://${url}/{z}/{x}/{y}`);
      }
      packageReady=true;
    } catch (_) {}
    map = new maplibregl.Map({container:'map',style,center,zoom,attributionControl:false,fadeDuration:0});
    map.addControl(new maplibregl.NavigationControl({showCompass:false}),'bottom-right');
    map.on('load',()=>{
      fallbackEl.style.display=packageReady?'none':'flex';
      installPointLayer();
      status(packageReady?'Офлайн PMTiles':'Сетка · карта не выбрана');
      bridgeReady();
    });
    map.on('styledata',()=>{pointSourceReady=false;installPointLayer();});
    map.on('click',e=>bridgeTap(e.lngLat.lat,e.lngLat.lng));
  } catch (e) {
    mapEl.style.display='none';
    fallbackEl.style.display='flex';
    status('Сетка · MapLibre runtime не подготовлен');
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