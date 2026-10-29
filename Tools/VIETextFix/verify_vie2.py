"""vie2 검증. 사용: python3 -I verify_vie2.py BIBLE_BEFORE BIBLE_AFTER LIT_BEFORE LIT_AFTER regen_targets.tsv"""
import sqlite3, sys, csv
bb, ba, lb, la, tsv = sys.argv[1:6]
o = lambda p: sqlite3.connect(f'file:{p}?mode=ro', uri=True)
for p in (bb, ba, lb, la):
    c = o(p); print(p.split('/')[-2] + '/' + p.split('/')[-1], 'integrity', c.execute('pragma integrity_check').fetchone()[0],
                   'journal', c.execute('pragma journal_mode').fetchone()[0])
A, B = o(bb), o(ba)
print('bible schema same', A.execute('select * from sqlite_master').fetchall() == B.execute('select * from sqlite_master').fetchall())
ra = A.execute('select * from BibleVerses order by uid').fetchall(); rb = B.execute('select * from BibleVerses order by uid').fetchall()
print('bible rows', len(ra), len(rb))
diff = [(x, y) for x, y in zip(ra, rb) if x != y]
print('bible changed rows', len(diff), 'non-content diffs', sum(1 for x, y in diff if x[:4] != y[:4] or x[5] != y[5]))
for x, y in diff: print('  ', x[1:4], 'uid', x[0])
L, M = o(lb), o(la)
print('lit schema same', L.execute('select * from sqlite_master').fetchall() == M.execute('select * from sqlite_master').fetchall())
print('LiteralText identical', L.execute('select * from LiteralText order by 1,2,3').fetchall() == M.execute('select * from LiteralText order by 1,2,3').fetchall())
keys = {(r['translation_code'], int(r['book_id']), int(r['chapter']), int(r['verse'])) for r in csv.DictReader(open(tsv), delimiter='\t')}
da = {r[:4]: r for r in L.execute('select * from TranslationDifference')}; db_ = {r[:4]: r for r in M.execute('select * from TranslationDifference')}
print('TD rows', len(da), '->', len(db_), 'expected', len(da) - len(keys))
print('deleted == targets', set(da) - set(db_) == keys, '| remaining rows unchanged', all(da[k] == v for k, v in db_.items()), '| no new rows', not (set(db_) - set(da)))
