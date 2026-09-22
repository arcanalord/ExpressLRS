#!/usr/bin/env python3
import pathlib, sys

root = pathlib.Path(sys.argv[1]).resolve()
app = (root / "src" / "app.js").read_text(encoding="utf-8")
manager = (root / "src" / "offline-map-manager.js").read_text(encoding="utf-8")
html = (root / "index.html").read_text(encoding="utf-8")

required_html = [
    'id="offlineMapsButton"',
    'id="offlineMapsModal"',
    'id="offlineMapArea"',
    'id="offlineMapDetail"',
    'id="offlineMapDownload"',
    'id="offlinePackagesList"',
]
for token in required_html:
    assert token in html, f"missing offline map UI token: {token}"

required_app = [
    "createOfflineMapManager",
    "selectedOfflineBounds",
    "renderOfflineEstimate",
    "downloadOfflineSelection",
    "tileObjectUrl",
    "offlineMapManager.cachedTile",
]
for token in required_app:
    assert token in app, f"missing offline map app integration: {token}"

required_manager = [
    "IndexedDbTileStore",
    "OFFLINE_PROVIDER_NOT_CONFIGURED",
    "OFFLINE_REGION_TOO_LARGE",
    "provider?.offlineAllowed",
    "maxTiles",
]
for token in required_manager:
    assert token in manager, f"missing offline map safety/storage token: {token}"

assert "tile.openstreetmap.org" not in manager, "offline downloader must not hardcode public OSM tile server"
assert "12000" in manager, "offline download safety cap missing"

print("OFFLINE_MAP_REGRESSION_PASS")
