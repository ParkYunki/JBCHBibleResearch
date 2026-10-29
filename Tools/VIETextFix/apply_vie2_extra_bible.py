"""(선택) vie1에서 빠진 VNI 찌꺼기 13곳: 대문자 O + VNI 'á'(=^+sắc) 바이트가 'oa' 이중모음처럼 보여 정상 음절 검사를
통과했다. Oát→Ốt(Ốt-ni-ên/Ốt-ni), Oáng→Ống, Oái→Ối. 단어 첫머리 토큰만, 정확히 13곳일 때만 적용한다.
사용: python3 -I apply_vie2_extra_bible.py Bible_VIE1934.sqlite  (vie2 적용본 사본)"""
import sqlite3, sys, re
MAP = {'Oát': 'Ốt', 'Oáng': 'Ống', 'Oái': 'Ối'}
P = re.compile(r'(?<![^\W\d_])(Oát|Oáng|Oái)(?![^\W\d_])')
con = sqlite3.connect(sys.argv[1]); total = 0; upd = []
for uid, t in con.execute('select uid, content from BibleVerses'):
    nt, n = P.subn(lambda m: MAP[m.group(1)], t)
    if n: upd.append((nt, uid, t)); total += n
assert total == 13, total
with con:
    for nt, uid, t in upd:
        assert con.execute('update BibleVerses set content=? where uid=? and content=?', (nt, uid, t)).rowcount == 1
print('replaced', total, 'in', len(upd), 'verses')
