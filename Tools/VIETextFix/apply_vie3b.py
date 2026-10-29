"""vie3b: 2차 검증에서 대조본(bible.com VIE1925 / kinhthanh.httlvn.org VI1934)으로 확인된 5절 + TGLULB 렘 47:5 끝 공백.
욥 33:17은 철자(nguời→người)만 고친다(YV의 'chở' 추가는 단일 출처라 보류).
사용: python3 -I apply_vie3b.py <dir with Bible_VIE1934.sqlite Literal_vi.sqlite Bible_TGLULB.sqlite> <regen_out.tsv>"""
import sqlite3, sys, os, csv
d, out = sys.argv[1:3]
E = [((13,12,8),'có ó ững người','có những người'),((18,33,17),'loài nguời','loài người'),
     ((19,135,11),'Từc là','Tức là'),((38,12,6),'ỡ chỗ mình','ở chỗ mình'),((45,16,9),'Eâch-ta-chy','Ếch-ta-chy')]
b = sqlite3.connect(os.path.join(d,'Bible_VIE1934.sqlite'))
with b:
    for (bk,c,v),o,n in E:
        (uid,t), = b.execute('select uid,content from BibleVerses where book_id=? and chapter=? and verse=?',(bk,c,v)).fetchall()
        assert t.count(o)==1,(bk,c,v)
        assert b.execute('update BibleVerses set content=? where uid=? and content=?',(t.replace(o,n),uid,t)).rowcount==1
b.execute('VACUUM'); b.close()
L = sqlite3.connect(os.path.join(d,'Literal_vi.sqlite')); rows=[]
with L:
    for k in [(13,12,8),(38,12,6)]:
        r = L.execute("select translation_code,book_id,chapter,verse,explanation from TranslationDifference where translation_code='VIE1934' and book_id=? and chapter=? and verse=?",k).fetchall()
        assert len(r)==1 and ('ó ững' in r[0][4] or '“ỡ”' in r[0][4]), r
        rows += r
        assert L.execute("delete from TranslationDifference where translation_code='VIE1934' and book_id=? and chapter=? and verse=?",k).rowcount==1
L.execute('VACUUM'); L.close()
with open(out,'w',encoding='utf-8',newline='') as f:
    w=csv.writer(f,delimiter='\t'); w.writerow(['translation_code','book_id','chapter','verse','explanation_deleted']); w.writerows(rows)
t = sqlite3.connect(os.path.join(d,'Bible_TGLULB.sqlite'))
with t:
    (uid,c), = t.execute("select uid,content from BibleVerses where book_id=24 and chapter=47 and verse=5").fetchall()
    assert c.endswith('? ') and not c.endswith('  ')
    assert t.execute('update BibleVerses set content=? where uid=? and content=?',(c.rstrip(' '),uid,c)).rowcount==1
t.execute('VACUUM'); t.close()
print('ok: 5 VIE verses, 2 TD rows deleted, TGLULB Jer 47:5 trimmed')
