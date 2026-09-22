#!/usr/bin/env python3
import pathlib, sys

root = pathlib.Path(sys.argv[1]).resolve()
app = (root / "src" / "app.js").read_text(encoding="utf-8")
manager = (root / "src" / "offline-map-manager.js").read_text(encoding="utf-8")
vector_manager = (root / "src" / "vector-package-manager.js").read_text(encoding="utf-8")
vector_adapter = (root / "src" / "vector-map-adapter.js").read_text(encoding="utf-8")
vector_style = (root / "src" / "openmaptiles-basic-style.js").read_text(encoding="utf-8")
html = (root / "index.html").read_text(encoding="utf-8")

required_html = [
    'id="offlineMapsButton"',
    'id="offlineMapsModal"',
    'id="offlineMapArea"',
    'id="offlineMapDetail"',
    'id="offlineMapDownload"',
    'id="offlinePackagesList"',
    'id="offlineMapImportButton"',
    'id="offlineMapImportInput"',
    'id="mapVectorLayer"',
    './vendor/maplibre-gl.css',
    './vendor/pmtiles.js',
    './src/vector-runtime-bootstrap.js',
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
    "createVectorPackageManager",
    "createVectorMapAdapter",
    "activateVectorPackage",
    "importPmtilesFile",
    "syncVectorMap",
    "PMTiles · vector",
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

for token in ["PMTILES_FILE_REQUIRED", "application/vnd.pmtiles", "ACTIVE_KEY", "importFile", "download"]:
    assert token in vector_manager, f"missing PMTiles package manager token: {token}"

for token in ["maplibregl", "pmtiles.Protocol", "pmtiles.FileSource", "pmtiles.PMTiles", "map.resize"]:
    assert token in vector_adapter, f"missing MapLibre/PMTiles adapter token: {token}"

bootstrap = (root / "src" / "vector-runtime-bootstrap.js").read_text(encoding="utf-8")
for token in ["../vendor/maplibre-gl.mjs", "globalThis.maplibregl", "offlineVendor: true"]:
    assert token in bootstrap, f"missing local vector runtime bootstrap token: {token}"

for token in ["type: 'vector'", "'source-layer':'water'", "'source-layer':'transportation'"]:
    assert token in vector_style, f"missing vector style token: {token}"

assert app.index("syncVectorMap()") < app.index("tileObjectUrl"), "vector path must be evaluated before raster fallback"
assert "tile.openstreetmap.org" in app, "online raster fallback unexpectedly removed"

print("OFFLINE_MAP_REGRESSION_PASS")
