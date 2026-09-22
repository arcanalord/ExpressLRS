import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const root = path.resolve(process.argv[2] ?? '.');
const appPath = path.join(root, 'src', 'app.js');
const versionPath = path.join(root, 'src', 'version.js');
if (!fs.existsSync(appPath)) throw new Error(`Missing ${appPath}`);

for (const name of [
  'runtime-bootstrap.js',
  'map-runtime-state.js',
  'runtime-health.js',
  'safe-storage.js',
  'ui-binder.js',
  'native-runtime.js',
  'help-ui-controller.js'
]) {
  const source = path.resolve(new URL(`../src/${name}`, import.meta.url).pathname);
  const dest = path.join(root,'src',name);
  fs.copyFileSync(source,dest);
}

let app = fs.readFileSync(appPath, 'utf8');
const replaceRequired = (oldText,newText,label) => {
  if (app.includes(newText)) return;
  if (!app.includes(oldText)) throw new Error(`${label} anchor not found`);
  app = app.replace(oldText,newText);
};

const importAnchor = "import { buildAzimuthRay, buildRangeZone, parseKmlOverlay } from './markup-overlay.js';";
const imports = [
  "import { BOOT_STAGE, createEmbeddedFallbackScenario, installRuntimeGuards, runBootSequence } from './runtime-bootstrap.js';",
  "import { MAP_RUNTIME, createMapRuntimeState, reduceMapRuntime, mapRuntimeLabel } from './map-runtime-state.js';",
  "import { combineRuntimeHealth, runtimeHealthLabel } from './runtime-health.js';",
  "import { createSafeStorage } from './safe-storage.js';",
  "import { createUiBinder, wireCriticalUi } from './ui-binder.js';",
  "import { createNativeRuntime } from './native-runtime.js';",
  "import { createHelpUiController } from './help-ui-controller.js';"
];
for (const importLine of imports) {
  if (!app.includes(importLine)) {
    if (!app.includes(importAnchor)) throw new Error('Import anchor not found');
    app = app.replace(importAnchor, `${importAnchor}\n${importLine}`);
  }
}

const stateAnchor = "let activeLayerPreset = 'main';";
const stateBlock = `let activeLayerPreset = 'main';
let lastBootState = { stage:BOOT_STAGE.IDLE, ready:false, degraded:false, fatal:false, detail:null, failures:[] };
let mapRuntimeState = createMapRuntimeState();
let lastRuntimeHealth = null;
let runtimeGuardFailure = null;
const runtimeStorageIssues = [];
const runtimeUiIssues = [];`;
if (!app.includes('const runtimeStorageIssues = [];')) {
  if (!app.includes(stateAnchor)) throw new Error('Runtime state anchor not found');
  app = app.replace(stateAnchor,stateBlock);
}

const helpAnchor = 'let activeHelpTopicId = HELP_FALLBACK_ID;';
const helpBlock = `const helpUi = createHelpUiController({
  documentRef:document,
  locationRef:location,
  historyRef:history,
  session:helpSession,
  fallbackTopicId:HELP_FALLBACK_ID,
  resolveTopic:resolveHelp,
  listTopics:listHelpTopics,
  searchTopics:searchHelpTopics,
  buildDeepLink:buildHelpDeepLink,
  clearDeepLink:clearHelpDeepLink,
  elements:{ sheet:helpSheet, quickTitle:helpQuickTitle, quickSummary:helpQuickSummary, quickSteps:helpQuickSteps, why:helpWhy, registry:helpRegistry, topicList:helpTopicList, topicContent:helpTopicContent, search:helpSearch, diagnosticsStatus:helpDiagnosticsStatus },
  buildDiagnostics:()=>buildSafeDiagnostics({
    appVersion:APP_VERSION,
    runtime:'webview',
    platform:new URLSearchParams(location.search).get('platform') ?? 'web',
    runtimeProfile:runtimeConfig?.profile ?? 'unknown',
    mapProvider:mapAdapter?.describe?.().provider ?? 'unknown',
    capabilityFlags:{ help:true, replay:Boolean(controller), androidBridge:Boolean(globalThis.AndroidBridge) },
    mode:state?.mode ?? null,
    sourceSummary:state ? getSourceSummary(state) : null,
    lastOperationStatus:lastRuntimeHealth?.level ?? null
  }),
  onIssue:(issue)=>runtimeUiIssues.push(issue)
});
const initHelpRegistry = () => helpUi.init();
const openHelp = (ref, options={}) => helpUi.open(ref, options);
const openErrorHelp = (code, options={}) => helpUi.openError(code, options);
const closeHelp = (options={}) => helpUi.close(options);
const safeDiagnosticsText = () => helpUi.diagnosticsText();
const nativeRuntime = createNativeRuntime({ onState:()=>{ try { renderRuntimeHealth?.(); } catch {} } });
globalThis.__ppoNativeReady = (payload) => { nativeRuntime.markNativeReady(payload); try { renderRuntimeHealth?.(); } catch {} };`;
if (!app.includes('const helpUi = createHelpUiController({')) {
  if (!app.includes(helpAnchor)) throw new Error('Help controller anchor not found');
  app = app.replace(helpAnchor,helpBlock);
}

const storageOld = `const eventLogStore = new EventLogStore({ storage: window.localStorage, key: 'ppo-radar.timeline.v1' });\nconst offlineMapRegistry = new OfflineMapRegistry({ storage: window.localStorage });`;
const storageNew = `const safeStorage = createSafeStorage({ getStorage:()=>globalThis.localStorage, onIssue:(issue)=>runtimeStorageIssues.push(issue) });\nconst eventLogStore = new EventLogStore({ storage: safeStorage, key: 'ppo-radar.timeline.v1' });\nconst offlineMapRegistry = new OfflineMapRegistry({ storage: safeStorage });`;
if (!app.includes('const safeStorage = createSafeStorage(')) replaceRequired(storageOld,storageNew,'Storage');

const mapFnStart = "async function initMapProvider() {\n  if (runtimeConfig.map.provider !== 'maplibre') return;";
const mapFnStartNew = "async function initMapProvider() {\n  if (runtimeConfig.map.provider !== 'maplibre') { mapRuntimeState=reduceMapRuntime(mapRuntimeState,{type:'MAP_DEGRADED',reason:'SCHEMATIC_MODE'}); return mapAdapter.describe(); }\n  mapRuntimeState=reduceMapRuntime(mapRuntimeState,{type:'MAP_LOADING',provider:'maplibre'});\n  renderRuntimeHealth?.();";
if (!app.includes("reason:'SCHEMATIC_MODE'")) replaceRequired(mapFnStart,mapFnStartNew,'Map function start');

const idleOld = "onIdle:()=>{ mapWrap.classList.add('maplibre-loaded'); mapProviderStatus.classList.remove('warn','issue'); },";
const idleNew = "onIdle:()=>{ mapWrap.classList.add('maplibre-loaded'); mapProviderStatus.classList.remove('warn','issue'); mapRuntimeState=reduceMapRuntime(mapRuntimeState,{type:'MAP_ONLINE',provider:'maplibre'}); renderRuntimeHealth(); },";
if (!app.includes("type:'MAP_ONLINE'")) replaceRequired(idleOld,idleNew,'Map idle');

const mapErrorOld = "onError:()=>{ mapWrap.classList.remove('maplibre-loaded'); mapProviderStatus.textContent='Карта: фон недоступен · локальные слои работают'; mapProviderStatus.classList.add('warn'); }";
const mapErrorNew = "onError:(error)=>{ mapWrap.classList.remove('maplibre-loaded'); mapProviderStatus.textContent='Карта: фон недоступен · локальные слои работают'; mapProviderStatus.classList.add('warn'); mapRuntimeState=reduceMapRuntime(mapRuntimeState,{type:'MAP_NETWORK_ERROR',reason:String(error?.message??'MAP_PROVIDER_ERROR')}); renderRuntimeHealth(); }";
if (!app.includes("type:'MAP_NETWORK_ERROR'")) replaceRequired(mapErrorOld,mapErrorNew,'Map error');

const mapSuccessOld = "if (activeOffline) applyMapPackage(activeOffline); else mapProviderStatus.textContent=`Карта: ${mapAdapter.describe().provider} · ${runtimeConfig.profile}`;";
const mapSuccessNew = "if (activeOffline) { applyMapPackage(activeOffline); mapRuntimeState=reduceMapRuntime(mapRuntimeState,{type:'MAP_OFFLINE_LOCAL',provider:'LOCAL_PMTILES'}); } else mapProviderStatus.textContent=`Карта: ${mapAdapter.describe().provider} · ${runtimeConfig.profile}`;\n    renderRuntimeHealth();\n    return mapAdapter.describe();";
if (!app.includes("provider:'LOCAL_PMTILES'")) replaceRequired(mapSuccessOld,mapSuccessNew,'Map success');

const mapCatchOld = "mapProviderStatus.onclick = () => openErrorHelp('PPO_RADAR_MAP_PROVIDER_FAILED');\n  }\n}";
const mapCatchNew = "mapProviderStatus.onclick = () => openErrorHelp('PPO_RADAR_MAP_PROVIDER_FAILED');\n    mapRuntimeState=reduceMapRuntime(mapRuntimeState,{type:'MAP_PROVIDER_ERROR',reason:String(error?.message??'PPO_RADAR_MAP_PROVIDER_FAILED')});\n    renderRuntimeHealth();\n    return { provider:'SCHEMATIC_SVG', degraded:true, reason:String(error?.message??'PPO_RADAR_MAP_PROVIDER_FAILED') };\n  }\n}";
if (!app.includes("degraded:true, reason:String(error?.message??'PPO_RADAR_MAP_PROVIDER_FAILED')")) replaceRequired(mapCatchOld,mapCatchNew,'Map catch');

const renderAnchor = "function render() {\n  clock.textContent = `${state.mode} · t=${(state.now/1000).toFixed(1)} с`;";
const renderAnchorNew = "function renderRuntimeHealth() {\n" +
  "  const summary = state ? getSourceSummary(state) : { transportIssues:0 };\n" +
  "  const criticalMissing = runtimeUiIssues.filter((item)=>item?.level==='CRITICAL' || item?.code==='CRITICAL_UI_INCOMPLETE').length;\n" +
  "  lastRuntimeHealth = combineRuntimeHealth({\n" +
  "    boot:lastBootState,\n" +
  "    map:mapRuntimeState,\n" +
  "    sourceSummary:summary,\n" +
  "    native:nativeRuntime.snapshot(),\n" +
  "    storage:safeStorage.snapshot(),\n" +
  "    ui:{issues:runtimeUiIssues.length,criticalMissing}\n" +
  "  });\n" +
  "  if (runtimeProfileStatus) {\n" +
  "    runtimeProfileStatus.textContent = runtimeHealthLabel(lastRuntimeHealth);\n" +
  "    runtimeProfileStatus.dataset.healthLevel = lastRuntimeHealth.level;\n" +
  "    runtimeProfileStatus.dataset.bootStage = lastRuntimeHealth.bootStage;\n" +
  "    runtimeProfileStatus.className = lastRuntimeHealth.level === 'ERROR' ? 'runtime-status issue' : lastRuntimeHealth.level === 'DEGRADED' ? 'runtime-status warn' : 'runtime-status';\n" +
  "  }\n" +
  "  if (mapProviderStatus && mapRuntimeState) mapProviderStatus.title = mapRuntimeLabel(mapRuntimeState);\n" +
  "}\n\n" +
  "function render() {\n" +
  "  clock.textContent = `${state.mode} · t=${(state.now/1000).toFixed(1)} с`;";
if (!app.includes('function renderRuntimeHealth()')) replaceRequired(renderAnchor,renderAnchorNew,'Render');

const renderTailOld = "renderMap(); applyLayerPreset(activeLayerPreset); renderMarkupPanel(); renderDetail(); renderSourceSummary(); renderOperatorStatus(); renderOperationalState(); renderLatestEvent(); persistLiveTimeline(); renderEventLog(); renderOfflineMaps(); syncReplayUi(); renderTelemetry();";
const renderTailNew = "renderMap(); applyLayerPreset(activeLayerPreset); renderMarkupPanel(); renderDetail(); renderSourceSummary(); renderOperatorStatus(); renderOperationalState(); renderLatestEvent(); persistLiveTimeline(); renderEventLog(); renderOfflineMaps(); syncReplayUi(); renderTelemetry(); renderRuntimeHealth();";
if (!app.includes('renderTelemetry(); renderRuntimeHealth();')) replaceRequired(renderTailOld,renderTailNew,'Render tail');

const criticalAnchor = "modeButtons.forEach((button)=>button.addEventListener('click',async()=>{";
const criticalBlock = `const uiBinder = createUiBinder({ root:document, onIssue:(issue)=>runtimeUiIssues.push(issue) });
const criticalUiContract = wireCriticalUi({
  binder:uiBinder,
  openHelp,
  closeHelp,
  restartReplay,
  toggleReplay:()=>{ if (!controller || state?.mode!=='REPLAY') return; controller.toggle(); render(); ensureLoop(); },
  fallbackTopicId:HELP_FALLBACK_ID,
  onIssue:(issue)=>runtimeUiIssues.push(issue)
});
void criticalUiContract;

modeButtons.forEach((button)=>button.addEventListener('click',async()=>{`;
if (!app.includes('const criticalUiContract = wireCriticalUi({')) replaceRequired(criticalAnchor,criticalBlock,'Critical UI');

for (const line of [
  "replayToggle.addEventListener('click',()=>{ if(state.mode!=='REPLAY') return; controller.toggle(); render(); ensureLoop(); });\n",
  "qs('#replay-restart').addEventListener('click',()=>restartReplay());\n",
  "qs('#help').addEventListener('click',()=>openHelp(HELP_FALLBACK_ID));\n",
  "qs('#help-close').addEventListener('click',()=>closeHelp());\n",
  "qs('#help-back').addEventListener('click',()=>closeHelp());\n"
]) app = app.replace(line,'');

const optionalStart = "layerPresetToggle.addEventListener('click',()=>{";
if (!app.includes('/* recovery optional UI begin */')) {
  if (!app.includes(optionalStart)) throw new Error('Optional UI start anchor not found');
  app = app.replace(optionalStart, `/* recovery optional UI begin */\ntry {\n${optionalStart}`);
  const optionalEnd = "\nasync function loadScriptAsset(src, id) {";
  if (!app.includes(optionalEnd)) throw new Error('Optional UI end anchor not found');
  app = app.replace(optionalEnd, `\n} catch (error) {\n  runtimeUiIssues.push({code:'OPTIONAL_UI_BIND_FAILED',level:'OPTIONAL',error:String(error?.message??error)});\n}\n/* recovery optional UI end */\n\nasync function loadScriptAsset(src, id) {`);
}

const oldBoot = `initHelpRegistry();
scenario=await fetch('./replay/demo.json').then((r)=>r.json());
controller=new ReplayController(scenario);
state=controller.restart({autoplay:true});
await initMapProvider();`;
const newBoot = `const removeRuntimeGuards = installRuntimeGuards({ onError:({type,error})=>{
  runtimeGuardFailure={type,error:String(error?.message??error)};
  lastBootState={...lastBootState,degraded:true,failures:[...(lastBootState.failures??[]),{stage:'RUNTIME',error:runtimeGuardFailure.error}]};
  renderRuntimeHealth();
} });
void removeRuntimeGuards;

await runBootSequence({
  initHelp: async () => initHelpRegistry(),
  loadScenario: async () => {
    const response = await fetch('./replay/demo.json', { cache:'no-store' });
    if (!response.ok) throw new Error('Replay asset HTTP ' + response.status);
    return response.json();
  },
  fallbackScenario: createEmbeddedFallbackScenario,
  createCore: async (loadedScenario) => {
    scenario = loadedScenario;
    controller = new ReplayController(scenario);
    state = controller.restart({ autoplay:true });
    render();
    ensureLoop();
    return { controller };
  },
  initMap: async () => initMapProvider(),
  mapTimeoutMs: 8000,
  onState: (next) => { lastBootState=next; renderRuntimeHealth(); }
});
nativeRuntime.markAppReady({ appVersion:APP_VERSION, capabilities:['help','replay','offline-maps','session-import-export'] });
renderRuntimeHealth();`;
if (!app.includes('nativeRuntime.markAppReady({ appVersion:APP_VERSION')) {
  if (app.includes(oldBoot)) app = app.replace(oldBoot,newBoot);
  else if (app.includes('await runBootSequence({')) {
    const end='\n});\nlet mapResizeFrame = null;';
    if (!app.includes(end)) throw new Error('Existing boot end anchor not found');
    app=app.replace(end,"\n});\nnativeRuntime.markAppReady({ appVersion:APP_VERSION, capabilities:['help','replay','offline-maps','session-import-export'] });\nrenderRuntimeHealth();\nlet mapResizeFrame = null;");
  } else throw new Error('Boot anchor not found');
}

fs.writeFileSync(appPath, app);

if (fs.existsSync(versionPath)) {
  let version = fs.readFileSync(versionPath, 'utf8');
  version = version.replace(/APP_VERSION\s*=\s*'[^']+'/m, "APP_VERSION = '0.3.0-dev.5'");
  fs.writeFileSync(versionPath, version);
}

const versionTest = path.join(root, 'tests', 'version.test.js');
if (fs.existsSync(versionTest)) {
  let text = fs.readFileSync(versionTest, 'utf8');
  text = text.replace(/v0\.[0-9.\-a-z]+ checkpoint/gi, 'v0.3.0-dev.5 checkpoint').replace(/'0\.[0-9.\-a-z]+'/gi, "'0.3.0-dev.5'");
  fs.writeFileSync(versionTest, text);
}

const webShellTest = path.join(root, 'tests', 'web-shell.test.js');
if (fs.existsSync(webShellTest)) {
  let text = fs.readFileSync(webShellTest, 'utf8');
  text = text.replace(/v0\.2\.6/g, 'v0.3.0-dev.5').replace(/0\\\.2\\\.6/g, '0\\.3\\.0-dev\\.5');
  fs.writeFileSync(webShellTest, text);
}

const indexPath = path.join(root, 'index.html');
if (fs.existsSync(indexPath)) {
  let text = fs.readFileSync(indexPath, 'utf8');
  text = text.replace(/runtime v0\.2\.6/g, 'runtime v0.3.0-dev.5').replace(/runtime v0\.3\.0-dev\.[0-9]+/g, 'runtime v0.3.0-dev.5');
  fs.writeFileSync(indexPath, text);
}

console.log('PPO Radar runtime recovery dev.5 patch applied');
