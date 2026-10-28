"""2026-10-27 원본 오류 수정 2: 아브라함 아들 목록, 수아 족속 #3717 부모, 야곱#4059의 아들.
사용: python3 edit_1027b.py <ReferenceDataSource 폴더>"""
import json, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edit_lib import edit, R, as_list
D = sys.argv[1]
pp = os.path.join(D, 'PersonSeed.json')
s = open(pp, encoding='utf-8').read()

def abraham(o):
    r = R(o); a = as_list(r['아들'])
    for x in ('미스마#1018', '에벨#4109', '수아#3717'):
        assert x in a, x
    r['아들'] = [('수아#3715' if x == '수아#3717' else x) for x in a if x not in ('미스마#1018', '에벨#4109')]
s = edit(s, '2036', abraham)

def shuhite(o):
    r = R(o); assert r['아버지'] == '아브라함#2036' and r['어머니'] == '그두라#202', (r['아버지'], r['어머니'])
    r['아버지'] = ''; r['어머니'] = ''
s = edit(s, '3717', shuhite)

def jacob(o):
    r = R(o); assert r['아들'] == '요셉#2717', r['아들']; r['아들'] = '요셉#4345'
s = edit(s, '4059', jacob)
json.loads(s)
open(pp, 'w', encoding='utf-8').write(s)
print('ok')
