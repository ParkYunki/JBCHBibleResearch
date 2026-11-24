#!/usr/bin/env python3
"""[2026-11-10 origfill1] 원어 단어를 채운 절의 WordAlignment.word_index를 새 위치로 옮긴다(fill1_map.json).
입력 DB는 읽기만 하고 사본(--out)에 쓴다. 직역 본문·phrase·start는 바꾸지 않는다."""
import argparse, json, shutil, sqlite3, os
ap = argparse.ArgumentParser()
ap.add_argument("--map", required=True); ap.add_argument("--db", required=True); ap.add_argument("--out", required=True)
ap.add_argument("--new-orig", required=True)
ap.add_argument("--old-orig", required=True)
a = ap.parse_args()
if os.path.exists(a.out): raise SystemExit("out exists")
mp = json.load(open(a.map))
shutil.copyfile(a.db, a.out)
d = sqlite3.connect(a.out)
o = sqlite3.connect(f"file:{a.new_orig}?immutable=1", uri=True)
po = sqlite3.connect(f"file:{a.old_orig}?immutable=1", uri=True)
def words(db, b, c, v):
    return db.execute("select original_text, strong_code, morph_code from original_words where book_id=? and chapter=? and verse=? order by word_order, rowid", (b, c, v)).fetchall()
moved = 0
for k, x in mp.items():
    b, c, v = map(int, k.split(":"))
    rows = d.execute("select word_index, phrase, start from WordAlignment where book_id=? and chapter=? and verse=?", (b, c, v)).fetchall()
    if not rows: continue
    ow, nw = words(po, b, c, v), words(o, b, c, v)
    if len(ow) != x["old_n"] or len(nw) != x["new_n"] or len(x["map"]) != x["old_n"]:
        raise SystemExit(f"{k}: map/orig mismatch")
    bad = [r for r in rows if r[0] >= x["old_n"] or ow[r[0]] != nw[x["map"][r[0]]]]
    if bad: raise SystemExit(f"{k}: word_index >= old_n {bad}")
    d.execute("delete from WordAlignment where book_id=? and chapter=? and verse=?", (b, c, v))
    for wi, ph, st in rows:
        d.execute("insert into WordAlignment(book_id,chapter,verse,word_index,phrase,start) values(?,?,?,?,?,?)",
                  (b, c, v, x["map"][wi], ph, st))
        moved += 1
d.commit()
# 검증: 모든 행의 word_index가 새 원어 단어 수보다 작은지
n = {}
for b, c, v, cnt in o.execute("select book_id,chapter,verse,count(*) from original_words group by 1,2,3"): n[(b, c, v)] = cnt
over = [r for r in d.execute("select book_id,chapter,verse,word_index from WordAlignment") if r[3] >= n.get(r[:3], 0)]
print(os.path.basename(a.db), "moved", moved, "over", len(over), d.execute("pragma integrity_check").fetchone()[0])
if over or d.execute("pragma integrity_check").fetchone()[0] != "ok":
    raise SystemExit(1)
d.execute("vacuum"); d.close()
