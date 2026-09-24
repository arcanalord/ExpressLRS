# Map runtime vendor lock

Map runtime is deliberately pinned and bundled into the APK for offline use.

Required files in `assets/map_runtime/vendor/`:

- MapLibre GL JS 6.10.0: `maplibre-gl.mjs`, `maplibre-gl-shared.mjs`, `maplibre-gl-worker.mjs`, `maplibre-gl.css`
- PMTiles JS 4.5.0: `pmtiles.js`

Before `flutter build`, run:

```bash
python3 tool/fetch_map_vendor.py
python3 tool/map_vendor_gate.py
```

`fetch_map_vendor.py` downloads only the exact pinned URLs and verifies SHA-256 before installing the files. Runtime does not use the CDN; all files are Flutter assets in the APK.
