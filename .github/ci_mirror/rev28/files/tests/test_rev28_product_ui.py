#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.')
html=(root/'apps/linux_web/static/index.html').read_text(encoding='utf-8')
js=(root/'apps/linux_web/static/app.js').read_text(encoding='utf-8')
css=(root/'apps/linux_web/static/app.css').read_text(encoding='utf-8')
for marker in ['geometry-undo','geometry-redo','geometry-history-state','sweep-overlays','variant-compare']:
    assert f'id="{marker}"' in html, marker
for marker in ['geometryUndoStack','undoGeometry','redoGeometry','geometryRecordUndo','renderSweepOverlayControls','sweepOverlayRows','compactSweep','restoreVariantSnapshot','variantDeltaSummary','ui-rev28']:
    assert marker in js, marker
for marker in ['sweep-overlay-chip','variant-delta-row','geometry-history-actions','variant-restore']:
    assert marker in css, marker
assert "tags:['ui-rev28']" in js
print('REV28_PRODUCT_UI_PASS')