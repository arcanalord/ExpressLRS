#!/usr/bin/env python3
import json, sys
from pathlib import Path
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
data=json.loads((root/'apps/shared/help/help-registry.json').read_text(encoding='utf-8'))
topics=data['topics']; ids=[x['id'] for x in topics]
assert len(ids)==len(set(ids)) and data['fallbackTopic'] in set(ids)
required={'id','title','summary','body','keywords','category'}
for t in topics:
    assert required <= set(t), t['id']
    for rid in t.get('relatedTopics',[]): assert rid in ids, (t['id'],rid)
for code,tid in data.get('errorMap',{}).items(): assert code and tid in ids
blob=lambda t:' '.join([t['id'],t['title'],t['summary'],t['body'],*t.get('keywords',[]),*t.get('aliases',[])]).lower()
for q in ['b02','zin','vswr','ground','pec','nec2']:
    assert any(q in blob(t) for t in topics), q
assert any(t['id']=='emmana-next.error.invalid-ground-terminal' for t in topics)
print(f'HELP REGISTRY CONTENT PASS: {len(topics)} topics, {len(data.get("errorMap",{}))} error mappings')
