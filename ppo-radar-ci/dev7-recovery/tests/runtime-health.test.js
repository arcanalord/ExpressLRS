import test from 'node:test';
import assert from 'node:assert/strict';
import { HEALTH_LEVEL, combineRuntimeHealth, runtimeHealthLabel } from '../src/runtime-health.js';

test('healthy boot + online map + sources produces READY', () => {
  const health = combineRuntimeHealth({boot:{ready:true,degraded:false,stage:'READY'},map:{state:'ONLINE'},sourceSummary:{transportIssues:0},native:{state:'READY'},at:1});
  assert.equal(health.level, HEALTH_LEVEL.READY);
  assert.equal(runtimeHealthLabel(health), 'Система · готова');
});

test('map degraded keeps app usable but reports DEGRADED', () => {
  const health = combineRuntimeHealth({boot:{ready:true,degraded:false,stage:'READY'},map:{state:'DEGRADED',reason:'MAP_NETWORK_ERROR'},sourceSummary:{transportIssues:0}});
  assert.equal(health.level, HEALTH_LEVEL.DEGRADED);
  assert.ok(health.messages.includes('MAP_NETWORK_ERROR'));
});

test('map loading keeps explicit STARTING instead of fake ready', () => {
  const health = combineRuntimeHealth({boot:{ready:true,degraded:false,stage:'MAP'},map:{state:'LOADING'},sourceSummary:{transportIssues:0}});
  assert.equal(health.level,HEALTH_LEVEL.STARTING);
});

test('native error degrades but does not kill web shell', () => {
  const health=combineRuntimeHealth({boot:{ready:true,degraded:false,stage:'READY'},map:{state:'ONLINE'},sourceSummary:{transportIssues:0},native:{state:'ERROR',message:'bridge unavailable'}});
  assert.equal(health.level,HEALTH_LEVEL.DEGRADED);
  assert.ok(health.messages.includes('bridge unavailable'));
});

test('fatal boot dominates health', () => {
  const health = combineRuntimeHealth({boot:{ready:false,fatal:true,stage:'ERROR',detail:'Core не запущен'},map:{state:'INIT'},sourceSummary:{transportIssues:0}});
  assert.equal(health.level, HEALTH_LEVEL.ERROR);
});


test('map ERROR is nonfatal when core is alive', () => {
  const health = combineRuntimeHealth({boot:{ready:true,degraded:false,fatal:false,stage:'READY'},map:{state:'ERROR',reason:'WEBGL_UNAVAILABLE'},sourceSummary:{transportIssues:0},native:{state:'READY'}});
  assert.equal(health.level, HEALTH_LEVEL.DEGRADED);
  assert.equal(runtimeHealthLabel(health), 'Система · ограниченный режим');
  assert.ok(health.messages.includes('WEBGL_UNAVAILABLE'));
});

test('storage fallback degrades health without fatal error', () => {
  const health=combineRuntimeHealth({boot:{ready:true,stage:'READY'},map:{state:'ONLINE'},sourceSummary:{transportIssues:0},native:{state:'WEB'},storage:{status:'MEMORY_FALLBACK',persistent:false},ui:{issues:0,criticalMissing:0}});
  assert.equal(health.level,HEALTH_LEVEL.DEGRADED);
  assert.equal(health.storageState,'MEMORY_FALLBACK');
});

test('critical UI contract issue degrades health', () => {
  const health=combineRuntimeHealth({boot:{ready:true,stage:'READY'},map:{state:'ONLINE'},sourceSummary:{transportIssues:0},native:{state:'WEB'},storage:{status:'OK',persistent:true},ui:{issues:1,criticalMissing:1}});
  assert.equal(health.level,HEALTH_LEVEL.DEGRADED);
  assert.equal(health.uiState,'DEGRADED');
});
