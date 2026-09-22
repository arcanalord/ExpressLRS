from pathlib import Path
import sys
root=Path(sys.argv[1])
web=root/'app/src/main/assets/web'

def rep(path, old, new, n=1):
    p=Path(path); s=p.read_text(encoding='utf-8')
    if old not in s:
        raise SystemExit(f'patch target not found: {p}: {old[:80]!r}')
    p.write_text(s.replace(old,new,n),encoding='utf-8')

def append_once(path, marker, text):
    p=Path(path); s=p.read_text(encoding='utf-8')
    if marker not in s:
        p.write_text(s.rstrip()+"\n\n"+text.strip()+"\n",encoding='utf-8')

# Android shell
rep(root/'app/build.gradle', "versionCode 25", "versionCode 26")
rep(root/'app/build.gradle', "versionName '0.2.5'", "versionName '0.2.6'")
main=root/'app/src/main/java/ru/fpvclub/pporadar/MainActivity.java'
rep(main, 'import android.content.Intent;\n', 'import android.content.Intent;\nimport android.graphics.Color;\n')
rep(main, 'import android.os.Bundle;\n', 'import android.os.Bundle;\nimport android.os.Build;\nimport android.view.WindowInsets;\n')
rep(main, '        webView = new WebView(this);\n        setContentView(webView);', '        webView = new WebView(this);\n        webView.setBackgroundColor(Color.rgb(11, 15, 19));\n        setContentView(webView);\n        applySystemBarInsets();')
rep(main, '        webView.loadUrl("https://appassets.androidplatform.net/assets/web/index.html");\n    }', '''        webView.loadUrl("https://appassets.androidplatform.net/assets/web/index.html?profile=safe&map=maplibre&platform=android");\n    }\n\n    private void applySystemBarInsets() {\n        if (Build.VERSION.SDK_INT < 35) return;\n        getWindow().setStatusBarColor(Color.TRANSPARENT);\n        getWindow().setNavigationBarColor(Color.TRANSPARENT);\n        if (Build.VERSION.SDK_INT >= 29) getWindow().setNavigationBarContrastEnforced(false);\n        webView.setOnApplyWindowInsetsListener((view, insets) -> {\n            android.graphics.Insets bars = insets.getInsets(\n                WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout()\n            );\n            view.setPadding(bars.left, bars.top, bars.right, bars.bottom);\n            return insets;\n        });\n        webView.requestApplyInsets();\n    }''')
rep(main, 'PPO-Radar-Android/0.2.5', 'PPO-Radar-Android/0.2.6')

# Runtime version + shell
rep(web/'package.json', '"version": "0.2.5"', '"version": "0.2.6"')
rep(web/'src/version.js', "export const APP_VERSION = '0.2.5';", "export const APP_VERSION = '0.2.6';")
rep(web/'index.html', 'runtime v0.2.5', 'runtime v0.2.6', n=2)
rep(web/'index.html', '<g opacity=".18" stroke="#557080">', '<g class="schematic-grid" opacity=".18" stroke="#557080">')

# Map adapter runtime health/resize hooks
p=web/'src/map-adapter.js'; s=p.read_text(encoding='utf-8')
old="mount({onMove=null}={}){if(this.map)return this.map;if(!this.maplibregl?.Map)throw new Error('MapLibre GL JS is unavailable');if(!this.container)throw new Error('MapLibre container is required');this.map=new this.maplibregl.Map({container:this.container,style:this.style,center:this.center,zoom:this.zoom,attributionControl:true});if(onMove&&typeof this.map.on==='function')this.map.on('move',onMove);return this.map;}project"
new="mount({onMove=null,onIdle=null,onError=null}={}){if(this.map)return this.map;if(!this.maplibregl?.Map)throw new Error('MapLibre GL JS is unavailable');if(!this.container)throw new Error('MapLibre container is required');this.map=new this.maplibregl.Map({container:this.container,style:this.style,center:this.center,zoom:this.zoom,attributionControl:true});if(typeof this.map.on==='function'){if(onMove)this.map.on('move',onMove);if(onIdle)this.map.on('idle',onIdle);if(onError)this.map.on('error',onError);}return this.map;}resize(){this.map?.resize?.();return this;}project"
if old not in s: raise SystemExit('map-adapter mount target not found')
p.write_text(s.replace(old,new,1),encoding='utf-8')

# App overlay viewport + map health
app=web/'src/app.js'; s=app.read_text(encoding='utf-8')
s=s.replace("const mapProviderStatus = qs('#map-provider-status');", "const mapProviderStatus = qs('#map-provider-status');\nconst mapSvg = qs('#map');\nconst mapWrap = qs('.map-wrap');",1)
old="""function renderMap() {\n  postsLayer.replaceChildren();"""
new="""function syncMapOverlayViewport() {\n  if (!mapSvg || !mapWrap) return;\n  if (mapAdapter.id === 'maplibre') {\n    const width = Math.max(1, Math.round(mapWrap.clientWidth));\n    const height = Math.max(1, Math.round(mapWrap.clientHeight));\n    mapSvg.setAttribute('viewBox', `0 0 ${width} ${height}`);\n    mapSvg.setAttribute('preserveAspectRatio', 'none');\n  } else {\n    mapSvg.setAttribute('viewBox', '0 0 1000 650');\n    mapSvg.setAttribute('preserveAspectRatio', 'xMidYMid meet');\n  }\n}\n\nfunction renderMap() {\n  syncMapOverlayViewport();\n  postsLayer.replaceChildren();"""
if old not in s: raise SystemExit('renderMap target not found')
s=s.replace(old,new,1)
old="mapAdapter.mount({onMove:()=>renderMap()});"
new="""mapAdapter.mount({\n      onMove:()=>renderMap(),\n      onIdle:()=>{ mapWrap.classList.add('maplibre-loaded'); mapProviderStatus.classList.remove('warn','issue'); },\n      onError:()=>{ mapWrap.classList.remove('maplibre-loaded'); mapProviderStatus.textContent='Карта: фон недоступен · локальные слои работают'; mapProviderStatus.classList.add('warn'); }\n    });"""
if old not in s: raise SystemExit('map mount target not found')
s=s.replace(old,new,1)
s=s.replace("qs('.map-wrap').classList.add('maplibre-active');", "mapWrap.classList.add('maplibre-active');\n    mapAdapter.resize?.();\n    syncMapOverlayViewport();",1)
old="""await initMapProvider();\nrender(); ensureLoop();"""
new="""await initMapProvider();\nlet mapResizeFrame = null;\nwindow.addEventListener('resize',()=>{\n  if (mapResizeFrame) cancelAnimationFrame(mapResizeFrame);\n  mapResizeFrame=requestAnimationFrame(()=>{ mapResizeFrame=null; mapAdapter.resize?.(); renderMap(); });\n});\nrender(); ensureLoop();"""
if old not in s: raise SystemExit('resize target not found')
s=s.replace(old,new,1)
app.write_text(s,encoding='utf-8')

# CSS no-overlap release gate
css='''/* v0.2.6 mobile shell + no-overlap release gate */\nhtml,body{width:100%;height:100%;overflow:hidden}\nbody{min-height:100dvh}\nheader{position:relative;z-index:12;min-width:0}\n.brand,.mode,.right-top{min-width:0}\n.brand b{display:block;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}\n.map-wrap{isolation:isolate}\n.maplibre-map{width:100%;height:100%}\n.maplibre-map canvas{display:block}\n.map-wrap.maplibre-active .schematic-grid{opacity:.10}\n.map-wrap.maplibre-loaded .schematic-grid{display:none}\n\n@media(max-width:800px){\n  header{height:60px;min-height:60px;display:grid;grid-template-columns:minmax(84px,1fr) auto 44px;align-items:center;gap:8px;padding:7px 10px}\n  .brand{display:block;overflow:hidden}\n  .brand b{font-size:13px;line-height:1.1}\n  .mode{justify-self:center;border-radius:16px;padding:2px;white-space:nowrap}\n  .mode button{min-height:36px;padding:5px 10px;border-radius:14px;font-size:12px}\n  .right-top{display:block;justify-self:end}\n  .right-top>#help{display:grid!important;place-items:center;width:44px;min-width:44px;height:44px;min-height:44px;padding:0;border-radius:14px;font-size:0}\n  .right-top>#help::before{content:'?';font-size:18px;font-weight:700;line-height:1}\n  main{position:relative;display:flex;flex-direction:column;gap:0;padding:0;height:calc(100dvh - 60px);min-height:0;overflow:hidden}\n  .map-wrap{flex:1 1 auto;height:auto;min-height:0;border-radius:0}\n  aside{position:relative;left:auto;right:auto;bottom:auto;z-index:8;flex:0 0 min(31dvh,260px);height:auto;min-height:180px;max-height:31dvh;border-radius:20px 20px 0 0;padding:12px 14px;overflow:auto}\n  .operator-status-strip{top:8px;left:8px;right:74px;max-width:calc(100% - 82px)}\n  .operator-status-item{min-width:86px;max-width:118px;padding:6px 7px}\n  .operator-status-item:nth-child(n+4){display:none}\n  .map-tools{top:8px;right:8px}\n  .latest-event{left:8px;right:8px;bottom:62px}\n  .timeline{left:8px;right:8px;bottom:8px;height:46px;z-index:9;padding:7px 9px}\n  .timeline button{width:32px;height:32px;flex:0 0 32px}\n  .timeline #replay-time{min-width:70px;font-size:11px}\n  .session-actions{margin-top:10px;display:grid;grid-template-columns:1fr 1fr;gap:8px}\n  .session-actions button{min-width:0;padding:9px 10px;font-size:14px}\n  .detail-head h2{margin:8px 0;font-size:19px}\n}\n\n@media(max-width:390px){\n  header{grid-template-columns:minmax(70px,1fr) auto 40px;gap:6px;padding-left:8px;padding-right:8px}\n  .brand b{font-size:11.5px}\n  .mode button{padding:5px 8px;font-size:11px}\n  .right-top>#help{width:40px;min-width:40px;height:40px;min-height:40px}\n  .operator-status-item{min-width:80px}\n}'''
append_once(web/'styles.css','v0.2.6 mobile shell + no-overlap release gate',css)

# Tests
rep(web/'tests/version.test.js', 'v0.2.5 checkpoint', 'v0.2.6 checkpoint')
rep(web/'tests/version.test.js', "'0.2.5'", "'0.2.6'")
wt=web/'tests/web-shell.test.js'; s=wt.read_text(encoding='utf-8').replace('v0.2.5','v0.2.6').replace(r'v0\.2\.5',r'v0\.2\.6')
extra='''\n\ntest('v0.2.6 mobile shell prevents header/detail/timeline overlap', async () => {\n  const css=await readFile(new URL('../styles.css', import.meta.url),'utf8');\n  assert.match(css,/v0\\.2\\.6 mobile shell \\+ no-overlap release gate/);\n  assert.match(css,/@media\\(max-width:800px\\)[\\s\\S]*header\\{height:60px;min-height:60px;display:grid/);\n  assert.match(css,/@media\\(max-width:800px\\)[\\s\\S]*main\\{position:relative;display:flex;flex-direction:column/);\n  assert.match(css,/@media\\(max-width:800px\\)[\\s\\S]*aside\\{position:relative;/);\n  assert.doesNotMatch(css,/v0\\.2\\.6 mobile shell[\\s\\S]*aside\\{position:absolute/);\n});\n\ntest('v0.2.6 syncs SVG overlay to MapLibre viewport', () => {\n  assert.match(app,/function syncMapOverlayViewport\\(\\)/);\n  assert.match(app,/mapSvg\\.setAttribute\\('viewBox', `0 0 \\${width} \\${height}`\\)/);\n  assert.match(app,/mapAdapter\\.resize\\?\\.\\(\\)/);\n  assert.match(html,/class="schematic-grid"/);\n});\n'''
if 'mobile shell prevents header/detail/timeline overlap' not in s: s=s.rstrip()+extra
wt.write_text(s,encoding='utf-8')
mat=web/'tests/map-adapter.test.js'; s=mat.read_text(encoding='utf-8')
extra2="""\n\ntest('maplibre adapter exposes resize and runtime health hooks',()=>{\n  const hooks={}; let resized=0;\n  class FakeMap { constructor(){} on(name,fn){hooks[name]=fn;} resize(){resized++;} project(){return{x:0,y:0};} }\n  const adapter=new MapLibreMapAdapter({maplibregl:{Map:FakeMap},container:'map'});\n  let idle=0,error=0; adapter.mount({onIdle:()=>idle++,onError:()=>error++}); adapter.resize();\n  hooks.idle(); hooks.error(new Error('tile'));\n  assert.equal(resized,1); assert.equal(idle,1); assert.equal(error,1);\n});\n"""
if 'runtime health hooks' not in s: mat.write_text(s.rstrip()+extra2,encoding='utf-8')
print('patched', root)
