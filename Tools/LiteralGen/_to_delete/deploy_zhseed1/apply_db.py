"""zhseed1: ReferenceData.sqlite의 zh 행 텍스트 칸에서 옛 책 이름을 새 표기로 바꾼다(정확한 문자열만).
대상 표: PersonsI18n, PlacesI18n, RelationLabelsI18n (scan_db.py로 찾은 전부). lang='zh' 행만, PK 열은 건드리지 않는다.
사용: python3 -I apply_db.py DB"""
import sqlite3, sys, re, collections
MAP = {'创世纪': '创世记', '腓利比书': '腓立比书', '约翰壹书': '约翰一书', '约翰贰书': '约翰二书', '约翰参书': '约翰三书',
       '創世紀': '創世記', '腓利比書': '腓立比書', '約翰壹書': '約翰一書', '約翰貳書': '約翰二書', '約翰參書': '約翰三書'}
P = re.compile('|'.join(map(re.escape, MAP)))
c = sqlite3.connect(sys.argv[1])
stat = collections.Counter(); hits = collections.Counter()
with c:
    for t in ('PersonsI18n', 'PlacesI18n', 'RelationLabelsI18n'):
        info = list(c.execute(f'pragma table_info("{t}")'))
        cols = [r[1] for r in info]; pk = [r[1] for r in sorted(info, key=lambda r: r[5]) if r[5]]
        assert 'lang' in pk and pk
        for row in c.execute(f'select {", ".join(pk)}, {", ".join(cols)} from "{t}" where lang = ?', ('zh',)).fetchall():
            key, vals = row[:len(pk)], dict(zip(cols, row[len(pk):]))
            upd = {}
            for col, v in vals.items():
                if col in pk or not isinstance(v, str): continue
                nv, n = P.subn(lambda m: MAP[m.group()], v)
                if n: upd[col] = nv; stat[(t, col)] += 1; hits[(t, col)] += n
            if upd:
                cur = c.execute(f'update "{t}" set ' + ', '.join(f'"{k}" = ?' for k in upd) + ' where ' + ' and '.join(f'"{k}" = ?' for k in pk),
                                list(upd.values()) + list(key))
                assert cur.rowcount == 1
for k in sorted(stat): print(f'{k[0]}.{k[1]}\tcells {stat[k]}\thits {hits[k]}')
print('total cells', sum(stat.values()), 'hits', sum(hits.values()))
