#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
app = (root / "src/app.js").read_text(encoding="utf-8")
android_app = (root / "android-app/app/src/main/assets/www/src/app.js").read_text(encoding="utf-8")
html = (root / "index.html").read_text(encoding="utf-8")
android_html = (root / "android-app/app/src/main/assets/www/index.html").read_text(encoding="utf-8")
css = (root / "src/styles.css").read_text(encoding="utf-8")
android_css = (root / "android-app/app/src/main/assets/www/src/styles.css").read_text(encoding="utf-8")
manifest = (root / "android-app/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")

def check(cond, msg):
    if not cond:
        raise SystemExit("MAP_REGRESSION_FAIL: " + msg)

# Root and Android WebView assets must stay in sync.
check(app == android_app, "root and Android app.js diverged")
check(html == android_html, "root and Android index.html diverged")
check(css == android_css, "root and Android styles.css diverged")

# Online map contract.
check("https://tile.openstreetmap.org/" in app, "OSM HTTPS tile endpoint missing")
check("© OpenStreetMap contributors" in html, "OSM attribution missing")
check('android.permission.INTERNET' in manifest, "Android INTERNET permission missing")
check('android:usesCleartextTraffic="false"' in manifest, "HTTPS-only Android policy changed")

# Exact regression: map must render tiles even with zero NodeDB/POSITION/WAYPOINT coordinates.
old_early_return = "if(!nodes.length&&!fallback&&!activeWaypoints().length)"
check(old_early_return not in app, "zero-coordinate early return reintroduced")
check("const hasGeoData=Boolean(" in app, "zero-coordinate state guard missing")
check("if(!hasGeoData)boundPoints.push(" in app, "default map bounds for zero-coordinate state missing")
check("'координат пока нет · общий вид'" in app, "zero-coordinate UI state missing")

# Offline/recovery contract.
check("navigator.onLine===false" in app, "offline tile fallback missing")
check("globalThis.addEventListener('online'" in app, "online recovery listener missing")
check("globalThis.addEventListener('offline'" in app, "offline listener missing")
check("Карта недоступна · локальная сетка" in app, "local-grid fallback status missing")

# Overlay paths must remain present.
for token in [
    "mapNodes()",
    "trackHistory.list",
    "activeWaypoints()",
    "shareCurrentPosition",
    "sendWaypointFromModal",
    "mapTrackLayer",
    "mapMarkers",
]:
    check(token in app or token in html, f"overlay/position contract missing: {token}")

print("MAP_REGRESSION_PASS")


# Explicit phone location request contract.
check('android.permission.ACCESS_COARSE_LOCATION' in manifest, "Android coarse location permission missing")
check('android.permission.ACCESS_FINE_LOCATION' in manifest, "Android fine location permission missing")
check('android:maxSdkVersion="30"' not in manifest.split('ACCESS_FINE_LOCATION')[1].split('/>')[0], "fine location incorrectly capped at SDK 30")
check("locateMapButton" in html, "explicit map location button missing")
check("async function locateOnMap()" in app, "explicit map location flow missing")
check("browserMapPosition" in app, "browser map position state missing")


# Interactive viewport regression.
check("const mapViewport=" in app, "interactive map viewport missing")
check("function wireMapGestures()" in app, "map gesture wiring missing")
check("pointerdown" in app and "pointermove" in app, "map pointer pan/pinch missing")
check("zoomMapAt" in app, "map zoom-at-anchor missing")
check("mapZoomInButton" in html and "mapZoomOutButton" in html, "map zoom controls missing")
check("touch-action:none" in css, "touch gesture CSS missing")
check("tileSize" in app and "px" in app, "pixel-sized OSM tiles missing")
