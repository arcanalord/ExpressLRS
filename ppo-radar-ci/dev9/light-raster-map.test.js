import test from 'node:test';
import assert from 'node:assert/strict';
import {tileRangeForBounds,chooseRasterZoom} from './light-raster-map.js';

test('tile range is finite for PPO Radar baseline bounds',()=>{
  const r=tileRangeForBounds({west:48.34,south:54.28,east:48.48,north:54.38},11);
  assert.ok(Number.isInteger(r.x0)&&Number.isInteger(r.x1));
  assert.ok(Number.isInteger(r.y0)&&Number.isInteger(r.y1));
  assert.ok(r.x1>=r.x0);
  assert.ok(r.y1>=r.y0);
});
test('light raster chooses bounded zoom',()=>{
  const z=chooseRasterZoom({west:48.34,south:54.28,east:48.48,north:54.38},700,450);
  assert.ok(z>=5&&z<=15);
});
