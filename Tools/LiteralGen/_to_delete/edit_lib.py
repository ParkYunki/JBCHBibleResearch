"""원본 JSON 항목 단위 편집 도구(edit_1027*.py 공용)."""
import json, re, sys, os
dec = json.JSONDecoder()

def find_entry(s, idx):
    hits = [m.start() for m in re.finditer(r'"idx"\s*:\s*"%s"' % idx, s)]
    assert len(hits) == 1, (idx, len(hits))
    st = s.rfind('{', 0, hits[0])
    obj, end = dec.raw_decode(s, st)
    assert obj['idx'] == idx
    return st, end, obj

def render(s, st, obj):
    line_start = s.rfind('\n', 0, st) + 1
    base = s[line_start:st]
    m = re.match(r'\{\s*\n([ \t]*)"', s[st:st + 200])
    if m:
        unit = len(m.group(1)) - len(base)
        txt = json.dumps(obj, ensure_ascii=False, indent=unit)
        return txt.replace('\n', '\n' + base)
    return json.dumps(obj, ensure_ascii=False)

def edit(s, idx, fn):
    st, end, obj = find_entry(s, idx)
    before = json.dumps(obj, ensure_ascii=False)
    fn(obj)
    assert json.dumps(obj, ensure_ascii=False) != before, ('변경 없음', idx)
    return s[:st] + render(s, st, obj) + s[end:]

def R(o):
    return o['description']['관계'][0]

def as_list(v):
    return v if isinstance(v, list) else ([v] if v else [])

