"""vie2: Bible_VIE1934.sqlite(vie1 적용본)에 사용자 결정 2건을 적용한다. content 칸만, 정확한 부분 문자열만 바꾼다.
 1) 'Ý' 탈락 4절(외부 대조본 기준)  2) 대문자 2절의 대문자 부분만
사용: python3 -I apply_vie2_bible.py DB   (연결 폴더 밖 사본, vie1 적용본 md5 53350417…)"""
import sqlite3, sys
EDITS = [  # (book, chapter, verse, old substring, new substring, class)
    (1, 40, 12, 'nói: -nghĩa', 'nói: Ý-nghĩa', 'W'),
    (1, 40, 18, 'rằng: -nghĩa', 'rằng: Ý-nghĩa', 'W'),
    (23, 55, 8, 'phán: tưởng ta', 'phán: Ý tưởng ta', 'W'),
    (40, 6, 10, 'đến; Cha được nên', 'đến; Ý Cha được nên', 'W'),
    (43, 19, 19, 'JÊSUS NGƯùI NA-XA-RẵT, Là VUA DĂN GIU-ĐA', 'JÊSUS NGƯỜI NA-XA-RÉT, LÀ VUA DÂN GIU-ĐA', 'C'),
    (44, 17, 23, 'THù CHúA KHÔNG BIôT', 'THỜ CHÚA KHÔNG BIẾT', 'C'),
]
con = sqlite3.connect(sys.argv[1])
with con:
    for b, c, v, old, new, cls in EDITS:
        uid, t = con.execute('select uid, content from BibleVerses where book_id=? and chapter=? and verse=?', (b, c, v)).fetchone()
        assert t.count(old) == 1, (b, c, v, 'old substring not found exactly once - not the vie1 base?')
        nt = t.replace(old, new, 1)
        assert con.execute('update BibleVerses set content=? where uid=? and content=?', (nt, uid, t)).rowcount == 1
        print(cls, (b, c, v), 'uid', uid, '|', nt)
