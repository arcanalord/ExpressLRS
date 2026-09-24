from pathlib import Path

root = Path(__file__).resolve().parents[1]
checks = {
    'map_page': root / 'lib/src/features/map/map_page.dart',
    'offline_sheet': root / 'lib/src/features/map/offline_maps_sheet.dart',
    'bridge': root / 'lib/platform/android_map_bridge.dart',
    'native_view': root / 'android/app/src/main/kotlin/org/fpvclub/mesh/MapPlatformView.kt',
    'package_store': root / 'android/app/src/main/kotlin/org/fpvclub/mesh/MapPackageStore.kt',
    'runtime': root / 'assets/map_runtime/src/map-runtime.js',
    'html': root / 'assets/map_runtime/index.html',
}
for name, path in checks.items():
    if not path.is_file() or path.stat().st_size < 100:
        raise SystemExit(f'MAP_GATE_FAIL missing {name}: {path}')

text = {k: p.read_text(errors='ignore') for k, p in checks.items()}
required = [
    ('map_point_ui', 'sendMapPoint', text['map_page']),
    ('android_view', 'AndroidMapSurface', text['map_page']),
    ('sheet_isolated', 'OfflineMapsSheet', text['map_page']),
    ('pmtiles_import', 'importPackage', text['offline_sheet']),
    ('pmtiles_delete_ui', 'deletePackage', text['offline_sheet']),
    ('pmtiles_disable_ui', 'setActive(null)', text['offline_sheet']),
    ('map_view_recreate', 'ValueKey(widget.reloadToken)', text['bridge']),
    ('map_bridge_dispose', 'setMethodCallHandler(null)', text['bridge']),
    ('range_requests', 'Content-Range', text['native_view']),
    ('local_origin', 'https://app.local', text['native_view']),
    ('native_ready_bridge', 'onMapReady', text['native_view']),
    ('flutter_ready_handshake', "call.method == 'mapReady'", text['bridge']),
    ('runtime_ready_handshake', 'bridgeReady()', text['runtime']),
    ('pmtiles_magic', 'PMTiles', text['package_store']),
    ('maplibre_runtime', 'maplibre-gl.mjs', text['runtime']),
    ('pmtiles_protocol', 'pmtiles.Protocol', text['runtime']),
    ('pmtiles_layer_autodetect', 'vector_layers', text['runtime']),
    ('osm_fallback', 'tile.openstreetmap.org', text['runtime']),
    ('grid_fallback', 'Локальная сетка', text['runtime']),
    ('point_layer', 'mesh-points', text['runtime']),
]
for name, needle, body in required:
    if needle not in body:
        raise SystemExit(f'MAP_GATE_FAIL {name}')

manifest = (root / 'pubspec.yaml').read_text()
if 'assets/map_runtime/' not in manifest:
    raise SystemExit('MAP_GATE_FAIL pubspec assets')

print('MESH_MESSENGER_MAP_SOURCE_GATE_PASS')
