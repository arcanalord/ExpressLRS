import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] || '.');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const fail = (message) => { console.error(`FAIL: ${message}`); process.exitCode = 1; };
const pass = (message) => console.log(`PASS: ${message}`);

let app, version, pkg;
try { app = read('src/app.js'); } catch { fail('src/app.js missing'); process.exit(1); }
try { version = read('src/version.js'); } catch { fail('src/version.js missing'); process.exit(1); }
try { pkg = JSON.parse(read('package.json')); } catch { fail('package.json missing/invalid'); process.exit(1); }

const versionMatch = version.match(/APP_VERSION\s*=\s*['"]([^'"]+)['"]/);
if (!versionMatch) fail('APP_VERSION not found');
else if (String(pkg.version) !== versionMatch[1]) fail(`package/version mismatch: package=${pkg.version} APP_VERSION=${versionMatch[1]}`);
else pass(`version contract ${versionMatch[1]}`);

for (const symbol of ['initHelpRegistry','openHelp','openErrorHelp','closeHelp','safeDiagnosticsText']) {
  const declared = new RegExp(`(?:function\\s+${symbol}\\s*\\(|(?:const|let|var)\\s+${symbol}\\s*=|import[^;]*\\b${symbol}\\b)`).test(app);
  if (!declared) fail(`critical symbol not declared/imported: ${symbol}`); else pass(`critical symbol ${symbol}`);
}

for (const marker of ['nativeRuntime.markAppReady','initMapProvider','ReplayController']) {
  if (!app.includes(marker)) fail(`runtime marker missing: ${marker}`); else pass(`runtime marker ${marker}`);
}

const stale = [...app.matchAll(/runtime v(0\.\d+\.\d+)/g)].map(m=>m[1]);
if (stale.length && versionMatch && stale.some(v=>v!==versionMatch[1])) fail(`stale runtime export markers: ${[...new Set(stale)].join(', ')}`);

if (!process.exitCode) console.log('PACKAGED_WEB_GATE=PASS');
