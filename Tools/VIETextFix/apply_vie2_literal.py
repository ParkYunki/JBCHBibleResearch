"""vie2: Literal_vi.sqlite TranslationDifference 에서 깨진 VIE1934 본문을 인용한 행을 지운다(행 삭제).
LiteralText 는 건드리지 않는다. 대상 = regen_targets.tsv (translation_code, book_id, chapter, verse).
삭제 뒤 VACUUM 한다(논리 내용 외 변화 없음).
사용: python3 -I apply_vie2_literal.py Literal_vi.sqlite regen_targets.tsv   (연결 폴더 밖 사본)"""
import sqlite3, sys, csv
db, tsv = sys.argv[1:3]
keys = [(r['translation_code'], int(r['book_id']), int(r['chapter']), int(r['verse']))
        for r in csv.DictReader(open(tsv, encoding='utf-8'), delimiter='\t')]
con = sqlite3.connect(db)
before = con.execute('select count(*) from TranslationDifference').fetchone()[0]
with con:
    n = 0
    for k in keys:
        n += con.execute('delete from TranslationDifference where translation_code=? and book_id=? and chapter=? and verse=?', k).rowcount
assert n == len(keys), (n, len(keys))
con.execute('VACUUM'); con.close()
print('deleted', n, 'rows:', before, '->', before - n)
