from pathlib import Path
import sys

root = Path(sys.argv[1])
p = root / "tool" / "ui_visual_gate.py"
s = p.read_text(encoding="utf-8")

def once(old, new, label):
    global s
    if old not in s:
        raise SystemExit(f"patch anchor missing: {label}")
    s = s.replace(old, new, 1)

once(
'''        ui / 'src' / 'vector-runtime-bootstrap.js',
        ui / 'app.js',
''',
'''        ui / 'src' / 'vector-runtime-bootstrap.js',
        ui / 'src' / 'map-point-v1.js',
        ui / 'app.js',
''',
"bundle",
)

once(
'''        base_geometry = assert_no_overlap(page, label)
        shot(page, f'MAP_SHELL_{release_version}_{label}_base.png')

        page.click('#layersButton')
''',
'''        base_geometry = assert_no_overlap(page, label)

        adapter_runtime = page.evaluate("""() => {
          const grid = window.__MAP_MARKUP_SHELL__.gridAdapter;
          const geo = {longitude: 37.6184, latitude: 55.7512};
          const px = grid.project(geo);
          const back = grid.unproject(px);
          return {ready: grid.isReady(), provider: grid.describe(), px, back,
                  radiusPx: grid.coverageRadiusPx(1000, geo)};
        }""")
        assert adapter_runtime['ready'] is True, adapter_runtime
        assert adapter_runtime['provider'] == 'local-grid', adapter_runtime
        assert abs(adapter_runtime['back']['longitude'] - 37.6184) < 1e-9, adapter_runtime
        assert abs(adapter_runtime['back']['latitude'] - 55.7512) < 1e-9, adapter_runtime
        assert adapter_runtime['radiusPx'] > 0, adapter_runtime

        project_before_fallback = page.evaluate("window.__MAP_MARKUP_CORE__.snapshot()")
        page.evaluate("""() => {
          const grid = document.querySelector('input[name="basemap"][value="grid"]');
          grid.checked = true; grid.dispatchEvent(new Event('change', {bubbles: true}));
          const vector = document.querySelector('input[name="basemap"][value="vector"]');
          vector.checked = true; vector.dispatchEvent(new Event('change', {bubbles: true}));
        }""")
        assert page.locator('#fallbackCanvas').is_visible()
        assert page.locator('#mapHost').is_hidden()
        status_text = page.locator('#mapStatusText').inner_text().lower()
        assert 'runtime' in status_text or 'pmtiles' in status_text, status_text
        assert page.evaluate("window.__MAP_MARKUP_CORE__.snapshot()") == project_before_fallback
        page.evaluate("""() => {
          const grid = document.querySelector('input[name="basemap"][value="grid"]');
          grid.checked = true; grid.dispatchEvent(new Event('change', {bubbles: true}));
        }""")
        assert page.locator('#fallbackCanvas').is_visible()
        assert page.evaluate("window.__MAP_MARKUP_CORE__.snapshot()") == project_before_fallback

        shot(page, f'MAP_SHELL_{release_version}_{label}_base.png')

        page.click('#layersButton')
''',
"map-adapter-runtime",
)

once(
'''        page.fill('#pointCode', 'P-101')
        page.fill('#pointLabel', 'Контрольная')
        page.click('[data-add-point]')
        assert 'добавлена' in page.locator('[data-tool-feedback]').inner_text()
''',
'''        page.fill('#pointCode', 'P-101')
        page.fill('#pointLabel', 'Контрольная')
        page.evaluate("""() => {
          window.__MAP_POINT_V1_EVENTS__ = [];
          window.addEventListener('map-markup:map-point-v1',
            (event) => window.__MAP_POINT_V1_EVENTS__.push(event.detail), { once: true });
        }""")
        page.click('[data-add-point]')
        assert 'добавлена' in page.locator('[data-tool-feedback]').inner_text()
        assert 'MapPoint v1 готов' in page.locator('[data-tool-feedback]').inner_text()
        shared_events = page.evaluate("window.__MAP_POINT_V1_EVENTS__")
        assert len(shared_events) == 1, shared_events
        assert shared_events[0]['id'], shared_events
        assert shared_events[0]['label'] == 'Контрольная', shared_events
        assert isinstance(shared_events[0]['lat'], (int, float)), shared_events
        assert isinstance(shared_events[0]['lon'], (int, float)), shared_events
        assert shared_events[0]['createdAt'], shared_events
''',
"map-point-runtime",
)

once(
'''        results.append({'viewport': label, 'version': runtime_version, 'console_errors': console_errors, 'base_geometry': base_geometry})
''',
'''        results.append({
            'viewport': label,
            'version': runtime_version,
            'console_errors': console_errors,
            'base_geometry': base_geometry,
            'map_adapter_v1_runtime': adapter_runtime,
            'map_point_v1_event': shared_events[0],
            'provider_fallback_project_unchanged': True,
        })
''',
"result",
)

p.write_text(s, encoding="utf-8")
print("MAP_MARKUP_R3_PATCH_OK")
