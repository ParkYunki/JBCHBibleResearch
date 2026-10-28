"""2026-10-27 원본 오류 수정: 유다의 아들 셀라 새 항목(#4799)과 관계 정리, 지명 577·3158 설명.
사용: python3 edit_1027.py <ReferenceDataSource 폴더>  — 항목 단위로 그 부분 글만 바꾼다."""
import json, re, sys, os
D = sys.argv[1]
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

# ---------- 인물 ----------
pp = os.path.join(D, 'PersonSeed.json')
s = open(pp, encoding='utf-8').read()

def judah(o):
    r = R(o); a = as_list(r['아들'])
    assert a == ['엘#2387', '오난#2648'], a
    r['아들'] = ['엘#2387', '오난#2648', '셀라#4799', '베레스#3582', '세라#3694']
s = edit(s, '3237', judah)

def zerah(o):
    r = R(o); assert r['아버지'] == '', r['아버지']; r['아버지'] = '유다#3237'
s = edit(s, '3694', zerah)

def shua(o):
    r = R(o); r['손자'] = as_list(r['손자']) + ['셀라#4799(외손자)']
s = edit(s, '3714', shua)

for i in ('2387', '2648'):
    def bro(o):
        r = R(o); r['기타관계'] = as_list(r['기타관계']) + ['셀라#4799(동생)']
    s = edit(s, i, bro)

for i in ('648', '4099'):
    def repoint(o):
        r = R(o); n = 0
        for k, v in r.items():
            if isinstance(v, list):
                r[k] = [x.replace('셀라#3232', '셀라#4799') for x in v]; n += sum('셀라#3232' in x for x in v)
            elif isinstance(v, str) and '셀라#3232' in v:
                r[k] = v.replace('셀라#3232', '셀라#4799'); n += 1
        assert n == 1, (o['idx'], n)
    s = edit(s, i, repoint)

assert '"idx": "4799"' not in s
new = {
    "idx": "4799", "kind2": "0", "kind": "인명", "word": "셀라", "word2": [],
    "call": "유다의 셋째 아들(셀라 가족의 조상)",
    "meaning": "-",
    "introduce": "셀라는 유다가 가나안 사람 수아의 딸에게서 얻은 셋째 아들로, 엘과 오난의 동생이다(창 38:2-5, 대상 2:3). 그가 태어날 때 유다는 거십에 있었다(창 38:5).",
    "lifetime": "엘과 오난이 죽은 뒤 유다는 며느리 다말에게 셀라가 장성하기를 기다리라고 하였으나, 셀라가 장성한 뒤에도 그를 다말에게 주지 않았다(창 38:11, 14, 26). 셀라는 야곱과 함께 애굽으로 내려간 유다의 아들들 가운데 기록되어 있다(창 46:12).",
    "event": "민수기의 인구 조사에서 셀라에게서 난 셀라 가족이 유다 자손의 종족으로 기록된다(민 26:20). 역대상은 셀라의 자손으로 레가의 아비 에르와 마레사의 아비 라아다 등을 기록한다(대상 4:21).",
    "character": "-",
    "description": {"출신": "", "민족": "이스라엘", "지파": "유다", "성별": "남", "직업/직위": [],
                    "관계": [{"할아버지": ["야곱#2262", "수아#3714(외조부)"], "할머니": "레아#3221", "아버지": "유다#3237", "어머니": "",
                              "배우자": "", "아들": ["에르#4099", "라아다#648"], "딸": "", "손자": "", "손녀": "",
                              "기타관계": ["엘#2387(형)", "오난#2648(형)"]}]},
    "verses": ["창 38:5", "창 38:11", "창 38:14", "창 38:26", "창 46:12", "민 26:20", "대상 2:3", "대상 4:21"],
}
# 마지막 항목 뒤에 넣는다(마지막 항목과 같은 들여쓰기)
end = s.rstrip().rfind(']')
last_brace = s.rfind('}', 0, end)
st_last = None
m = list(re.finditer(r'\n(  )\{\n', s))
base = '  '
txt = json.dumps(new, ensure_ascii=False, indent=2).replace('\n', '\n' + base)
s = s[:last_brace + 1] + ',\n' + base + txt + s[last_brace + 1:]
json.loads(s)
open(pp, 'w', encoding='utf-8').write(s)

# ---------- 지명 ----------
lp = os.path.join(D, 'PlaceSeed.json')
s = open(lp, encoding='utf-8').read()
def telaim(o):
    old = '여호수아 15:32에는 르마라는 지명이 없으므로 이를 근거로 동일한 장소라고 단정할 수 없다.'
    assert o['geography'].count(old) == 1
    o['geography'] = o['geography'].replace(old, '여호수아 15:24의 델렘과 같은 곳으로 보기도 하나, 본문만으로 단정할 수는 없다.')
s = edit(s, '577', telaim)
def lubim(o):
    old = '본문만으로 정확한 거주지를 정할 수 없으며, 함께 나오는 숩이나 룹과 자동으로 동일시할 수 없다.'
    assert o['geography'].count(old) == 1
    o['geography'] = o['geography'].replace(old, '히브리어 원문에서는 대하 16:8의 룹(리비아 사람)과 같은 이름이다. 본문만으로 정확한 거주지를 정할 수는 없다.')
s = edit(s, '3158', lubim)
json.loads(s)
open(lp, 'w', encoding='utf-8').write(s)
print('ok')
