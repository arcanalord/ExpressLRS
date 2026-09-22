#!/usr/bin/env python3
from pathlib import Path
import re, sys, shutil
from playwright.sync_api import sync_playwright

ROOT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
index=(ROOT/'index.html').read_text(encoding='utf-8')
css=(ROOT/'src/styles.css').read_text(encoding='utf-8')
modules=[
 ROOT/'src/core.js', ROOT/'src/help-registry.js',
 ROOT/'src/transports/radio-transport.js', ROOT/'src/transports/meshtastic-stream.js',
 ROOT/'src/transports/mock-meshtastic.js', ROOT/'src/transports/web-serial-meshtastic.js',
 ROOT/'src/transports/android-bridge-meshtastic.js', ROOT/'src/transports/protobuf-lite.js',
 ROOT/'src/transports/phoneapi-lite.js', ROOT/'src/transports/phoneapi-session.js',
 ROOT/'src/transports/lan-peer-transport.js', ROOT/'src/transports/auto-route-selector.js',
]
core='\n'.join(p.read_text(encoding='utf-8').replace('export ','') for p in modules)
core=re.sub(r'^import .*?;\s*$','',core,flags=re.MULTILINE)
app=(ROOT/'src/app.js').read_text(encoding='utf-8')
app=re.sub(r'^import .*?;\s*$','',app,flags=re.MULTILINE)
html=index.replace('<link rel="manifest" href="./manifest.webmanifest" />','')
html=html.replace('<link rel="stylesheet" href="./src/styles.css" />',f'<style>{css}</style>')
html=html.replace('<script type="module" src="./src/app.js"></script>','')
script="window.__meshDisableAutoConnect=true; const __testStore=new Map(); Object.defineProperty(window,'localStorage',{value:{getItem:k=>__testStore.has(k)?__testStore.get(k):null,setItem:(k,v)=>__testStore.set(k,String(v)),removeItem:k=>__testStore.delete(k),clear:()=>__testStore.clear()},configurable:true});\n"+core+'\n'+app

errors=[]
with sync_playwright() as p:
    executable=(shutil.which("google-chrome") or shutil.which("google-chrome-stable") or shutil.which("chromium") or shutil.which("chromium-browser"))
    args={"headless":True}
    if executable: args["executable_path"]=executable
    browser=p.chromium.launch(**args)
    page=browser.new_page(viewport={'width':412,'height':915})
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('console',lambda m: errors.append(m.text) if m.type=='error' and 'Failed to load resource' not in m.text else None)
    page.set_content(html,wait_until='load')
    page.add_script_tag(content=script,type='module')
    page.wait_for_timeout(500)
    assert page.evaluate("typeof window.__meshDebug")=='object', errors

    page.evaluate("""() => {
      const d=window.__meshDebug;
      d.peerContacts.set('peer-b',{peerId:'peer-b',displayName:'Алексей',trust:'unverified'});
      d.selectConversation('peer:peer-b');
    }""")
    page.wait_for_timeout(80)
    page.locator('.mobile-bottom-nav [data-view="map"]').click(); page.wait_for_timeout(100)
    assert page.locator('#mapCreateWaypointButton').is_enabled()

    box=page.locator('#mapCanvas').bounding_box(); assert box
    page.mouse.click(box['x']+box['width']*0.72,box['y']+box['height']*0.38)
    page.wait_for_timeout(80)
    assert page.locator('#waypointModal').get_attribute('aria-hidden')=='false'
    assert 'Получатель: Алексей' in page.locator('#waypointTarget').inner_text()
    coords=page.locator('#waypointCoords').inner_text(); assert ',' in coords and coords!='—'
    page.locator('#waypointName').fill('Точка A')
    page.locator('#waypointDescription').fill('Проверка отправки')
    page.locator('#confirmWaypoint').click(); page.wait_for_timeout(100)
    assert page.locator('#waypointModal').get_attribute('aria-hidden')=='true'
    points=page.evaluate('window.__meshDebug.getWaypoints()')
    assert len(points)==1 and points[0]['name']=='Точка A'
    queued=page.evaluate("window.__meshDebug.queue.list().filter(x=>x.payload?.type==='waypoint')")
    assert len(queued)==1 and queued[0]['payload']['conversationId']=='peer:peer-b'
    assert queued[0]['status']=='queued'

    page.locator('.mobile-bottom-nav [data-view="chats"]').click(); page.wait_for_timeout(80)
    body=page.locator('body').inner_text()
    assert 'Точка A' in body and 'В очереди' in body

    accepted=page.evaluate("""() => window.__meshDebug.lanTransport.onEnvelope({
      type:'waypoint',waypoint:{id:9001,latitude:52.1,longitude:5.1,expire:0,name:'Точка B',description:'Входящая'}
    },{from:'peer-b',messageId:'msg-map-1'})""")
    assert accepted is True
    page.wait_for_timeout(80)
    points=page.evaluate('window.__meshDebug.getWaypoints()')
    assert any(x.get('name')=='Точка B' for x in points)
    assert 'Точка B' in page.locator('body').inner_text()

    saved=page.evaluate("localStorage.getItem('mesh-waypoints-v1')")
    assert 'Точка A' in saved and 'Точка B' in saved

    assert not errors, errors
    print('MAP_POINT_V164_PASS')
    browser.close()
