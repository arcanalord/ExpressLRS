import test from 'node:test';
import assert from 'node:assert/strict';
import { SchematicMapAdapter, MapLibreMapAdapter } from '../src/map-adapter.js';

test('MapAdapter v1 schematic round-trips and exposes lifecycle',()=>{
  const adapter=new SchematicMapAdapter({width:1000,height:650,bounds:{minLat:54.28,maxLat:54.38,minLon:48.34,maxLon:48.48}});
  const geo={lat:54.33,lon:48.41};
  const px=adapter.project(geo);
  const back=adapter.unproject(px);
  assert.ok(Math.abs(back.lat-geo.lat)<1e-9);
  assert.ok(Math.abs(back.lon-geo.lon)<1e-9);
  assert.equal(adapter.isReady(),true);
  assert.equal(adapter.resize(),adapter);
  assert.equal(adapter.dispose(),adapter);
});

test('MapAdapter v1 MapLibre delegates project/unproject and disposes',()=>{
  let removed=false;
  const map={
    project:([lon,lat])=>({x:lon*10,y:lat*10}),
    unproject:([x,y])=>({lng:x/10,lat:y/10}),
    resize(){},
    remove(){removed=true;},
    getZoom:()=>10,
  };
  const adapter=new MapLibreMapAdapter({map});
  const geo={lat:54.33,lon:48.41};
  const back=adapter.unproject(adapter.project(geo));
  assert.deepEqual(back,geo);
  assert.equal(adapter.isReady(),true);
  adapter.dispose();
  assert.equal(removed,true);
  assert.equal(adapter.isReady(),false);
});
