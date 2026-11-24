#!/usr/bin/env python3
"""[2026-11-10 origfill1] STEP(TAGNT/TAHOT)에는 있으나 OriginalText.original_words에 빠진 원어 단어를 채운다.
- 대상: 절마다 비교(결합기호 제거 정규화)해 '삽입만' 있는 절(같음+삽입). 교체·삭제가 섞인 절은 건드리지 않는다.
- 빈 원어([ ] 등 Qere 자리표시)는 넣지 않는다.
- 출력: 패치된 OriginalText 사본 + 절별 old→new 단어 위치 매핑(JSON)."""
import sys, os, re, json, sqlite3, collections, unicodedata, difflib, shutil, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import step_parse as S
import rules as R

def norm(s):
    s = unicodedata.normalize("NFD", s)
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    return re.sub(r"[^\w]", "", s).lower()

TITLE = re.compile(r"^[1-3]?[A-Za-z]{2,3}\.\d+\.0\D")  # 시편 표제(0절): OriginalText·직역 모두 본문에서 제외하는 설계

# 신약: STEP 주 참조는 NRSV 절 번호, [장.절]은 KJV 절 번호. 앱의 한글 성경(BibleDB, 개역한글) 절 구분을
# 절마다 대조해 정했다(2026-11-10). 대부분 KJV와 같고, 아래는 한글 성경이 주 참조(NRSV) 쪽과 같은 곳.
KO_FOLLOWS_MAIN = {(41, 3, 20), (44, 4, 5), (47, 8, 13), (47, 13, 12), (47, 13, 13), (50, 1, 16), (50, 1, 17),
                   (51, 1, 22), (62, 2, 14), (64, 1, 15)}
KO_SPECIAL = {(66, 12, 18): (66, 12, 17)}   # 계 12:18[13.1] "바다 모래 위에 섰더라" — 한글 성경은 12:17 끝
# 책 끝 부기(TR "…에서 썼다")는 기존 DB가 11권에서 포함하므로 같은 규칙으로 넣는다(제외 목록 없음).
SUBSCRIPTION = {}
# 단어 단위 지정({}/() 태그): 살후 1:8{1.7} #1-3 "불꽃 중에" — 한글 성경은 1:7 끝
KO_WORD = {(53, 1, 8, w): (53, 1, 7) for w in (1, 2, 3)}

def target(b, c, v, alt, wnum, nt):
    if nt and (b, c, v) in SUBSCRIPTION and wnum in SUBSCRIPTION[(b, c, v)]:
        return None
    if nt and (b, c, v, wnum) in KO_WORD:
        return KO_WORD[(b, c, v, wnum)]
    mk = re.match(r"^\[(\d+)\.(\d+)\]$", alt) if nt else None
    if not mk:
        return (b, c, v)
    if (b, c, v) in KO_SPECIAL:
        return KO_SPECIAL[(b, c, v)]
    if (b, c, v) in KO_FOLLOWS_MAIN:
        return (b, c, v)
    return (b, int(mk.group(1)), int(mk.group(2)))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", required=True); ap.add_argument("--orig", required=True)
    ap.add_argument("--out-db", required=True); ap.add_argument("--out-map", required=True)
    ap.add_argument("--report", required=True)
    a = ap.parse_args()
    st = S.load(a.step, target=target)
    o = sqlite3.connect(f"file:{a.orig}?immutable=1", uri=True)
    cols = [r[1] for r in o.execute("pragma table_info(original_words)")]
    od = collections.defaultdict(list)
    for r in o.execute("select rowid,* from original_words order by book_id,chapter,verse,word_order,rowid"):
        od[(r[1], r[2], r[3])].append(dict(zip(["rowid"] + cols, r)))
    # strong → 가장 흔한 gloss_en
    gl = collections.defaultdict(collections.Counter)
    for s, g in o.execute("select strong_code, gloss_en from original_words where gloss_en is not null and gloss_en<>''"):
        gl[s][g] += 1
    plan, rep = {}, collections.Counter()
    skipped = []
    for k in sorted(st):
        sw = [w for w in st[k] if norm(w["orig"]) and not TITLE.match(w["line"])]
        ow = od.get(k, [])
        a_ = [norm(x["original_text"]) for x in ow]; b_ = [norm(w["orig"]) for w in sw]
        if a_ == b_: continue
        ops = difflib.SequenceMatcher(None, a_, b_, autojunk=False).get_opcodes()
        if any(t not in ("equal", "insert") for t, *_ in ops):
            rep["skip_" + ("missing" if not ow else "mixed")] += 1; skipped.append(k); continue
        plan[k] = (ops, sw, ow)
        rep["insert_verses"] += 1
    if os.path.exists(a.out_db): raise SystemExit("out-db exists")
    shutil.copyfile(a.orig, a.out_db)
    d = sqlite3.connect(a.out_db)
    mapping, newrows, nostrong = {}, 0, []
    for k, (ops, sw, ow) in plan.items():
        b, c, v = k
        seq = []  # ('old', idx) | ('new', stepword)
        for t, i1, i2, j1, j2 in ops:
            if t == "equal": seq += [("old", i) for i in range(i1, i2)]
            else: seq += [("new", sw[j]) for j in range(j1, j2)]
        nt = b >= 40
        old_map = {}
        rows = []
        for pos, (kind, x) in enumerate(seq):
            if kind == "old":
                old_map[x] = pos; r = dict(ow[x]); r["word_order"] = pos + 1; rows.append(r); continue
            w = x
            if nt:
                sc, _, mc = w["sm"].partition("=")
                lemma_gloss = w["lg"].split("=", 1)[1].strip() if "=" in w["lg"] else ""
                r = dict(original_text=R.nt_text(w["orig"]), transliteration=w["translit"], strong_code=R.nt_strong(sc),
                         morph_code=mc, gloss_en=lemma_gloss, translation_en=w["tr"].strip())
            else:
                strong = R.ot_strong(w["strong"])
                g = gl[strong].most_common(1)[0][0] if strong and gl[strong] else ""
                if not g: nostrong.append((k, w["line"]))
                r = dict(original_text=R.ot_text(w["orig"]), transliteration=R.ot_tl(w["translit"]),
                         strong_code=strong, morph_code=w["morph"], gloss_en=g, translation_en=R.clean_tr(w["tr"]))
            r.update(book_id=b, chapter=c, verse=v, word_order=pos + 1, rowid=None)
            rows.append(r); newrows += 1
        mapping[f"{b}:{c}:{v}"] = {"old_n": len(ow), "new_n": len(rows), "map": [old_map[i] for i in range(len(ow))]}
        d.execute("delete from original_words where book_id=? and chapter=? and verse=?", k)
        for r in rows:
            vals = [r.get(cn) for cn in cols]
            if r.get("rowid") is not None:
                d.execute(f"insert into original_words(rowid,{','.join(cols)}) values(?{',?'*len(cols)})", [r["rowid"]] + vals)
            else:
                d.execute(f"insert into original_words({','.join(cols)}) values({','.join('?'*len(cols))})", vals)
    d.commit()
    print("integrity", d.execute("pragma integrity_check").fetchone()[0])
    d.close()
    json.dump(mapping, open(a.out_map, "w"), ensure_ascii=False, indent=0)
    with open(a.report, "w") as f:
        f.write(json.dumps(dict(rep, new_rows=newrows, no_gloss=len(nostrong)), ensure_ascii=False) + "\n")
        for k in skipped: f.write(f"SKIP\t{k}\n")
        for k, l in nostrong: f.write(f"NOGLOSS\t{k}\t{l}\n")
    print(dict(rep), "new_rows", newrows, "no_gloss", len(nostrong))

main()
