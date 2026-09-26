#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.')
html=(root/'apps/linux_web/static/index.html').read_text(encoding='utf-8')
js=(root/'apps/linux_web/static/app.js').read_text(encoding='utf-8')
css=(root/'apps/linux_web/static/app.css').read_text(encoding='utf-8')
help_text=(root/'apps/shared/help/help-registry.json').read_text(encoding='utf-8')
for marker in ['id="opt-goal"','Лучшее согласование','Максимум усиления','id="opt-goal-note"','id="opt-goal-title"','id="opt-goal-description"']:
    assert marker in html, marker
assert html.count('id="opt-band-start"')==1
assert html.count('id="opt-band-stop"')==1
assert html.find('id="opt-band-start"') < html.find('id="technical-details"')
assert html.find('id="opt-alg"') > html.find('id="technical-details"')
for marker in ['OPT_GOAL_PRESETS','applyOptimizerGoalPreset','markOptimizerGoalCustom',"tags:['ui-rev28','ui-rev29']"]:
    assert marker in js, marker
for marker in ['optimizer-goal-card','optimizer-goal-note','optimizer-simple-band']:
    assert marker in css, marker
assert 'emmana-next.optimizer.goals' in help_text
assert 'ошибка оптимизации' in js
print('REV29_OPTIMIZER_UX_PASS')