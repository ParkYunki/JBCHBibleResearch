#!/usr/bin/env python3
"""[2026-11-11 zhprep4] edition_flags.json의 hold 절을 풀어 edition_flags_v2.json을 만든다(원본 파일은 읽기만).

판정 규칙
- STEP 쪽에 제외 대상 표시([TR]/[Byz]/[LXX])가 하나도 없는 hold 절: 제외 단어 없음(excluded=[]), map="resolved_noflag".
- boundary_shift: 장 단위 단어 배열(정규화)이 같으므로 장 안의 위치로 1:1 대응, map="resolved_chapter".
- order_or_text_diff: 단어 수가 같다. 정규화 표면형을 difflib로 맞추고, equal 구간은 그대로, 길이가 같은 replace 구간은
  위치대로 대응한다. 제외 표시가 replace 구간에 걸리면 review=true로 표시한다. map="resolved_diff".
- source_only: OriginalText에 절이 없어 대응 불가, 그대로 hold.
whole_tr(절 전체 TR) 판정은 export_flags.py와 같다.
"""
import collections, difflib, json, os, sqlite3, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE)); sys.path.insert(0, HERE)
import make_packets as M  # noqa
from export_flags import norm, EXCLUDE_NT, EXCLUDE_OT  # noqa

src = os.path.join(HERE, "edition_flags.json")
out = os.path.join(HERE, "edition_flags_v2.json")
if os.path.exists(out):
    sys.exit("edition_flags_v2.json이 이미 있음")
D = json.load(open(src, encoding="utf-8"))
V = D["verses"]
step = M.load_step()
sw = {}
for (bk, c, v), ws in step.items():
    sw[(M.BID[bk], c, v)] = [w for w in ws if w[0] not in ("(title)", "(text)")]
odb = sqlite3.connect(f"file:{os.path.join(M.RES, 'OriginalText.sqlite')}?immutable=1", uri=True)
orig = collections.defaultdict(list)
for b, c, v, t in odb.execute("SELECT book_id,chapter,verse,original_text FROM original_words ORDER BY book_id,chapter,verse,word_order,rowid"):
    orig[(b, c, v)].append(t)

def excl_set(b):
    return EXCLUDE_NT if b >= 40 else EXCLUDE_OT

def finish(ref, k, flags_by_pos, mapname, review=False, note=None):
    b = k[0]; nt = b >= 40
    fl = [flags_by_pos.get(i, "") for i in range(len(orig[k]))]
    whole_tr = nt and all(f in EXCLUDE_NT for f in fl) and any(f == "[TR]" for f in fl)
    rec = dict(V[ref]); rec.update(map=mapname, whole_tr=whole_tr,
        flags={str(i + 1): f for i, f in enumerate(fl) if f},
        excluded=[] if whole_tr else [i + 1 for i, f in enumerate(fl) if f in excl_set(b)])
    if review: rec["review"] = True
    if note: rec["note"] = note
    V[ref] = rec

stats = collections.Counter(); reviews = []
chap_pos = {}
for ref, rec in list(V.items()):
    if rec.get("map") != "hold":
        continue
    b, c, v = map(int, ref.split(":")); k = (b, c, v)
    s = sw.get(k, []); reason = rec["reason"]
    if reason == "source_only" or k not in orig:
        stats["still_hold"] += 1; continue
    if not any(x[2] in excl_set(b) for x in s) and reason != "boundary_shift":
        finish(ref, k, {}, "resolved_noflag"); stats["noflag"] += 1; continue
    if reason == "boundary_shift":
        if (b, c) not in chap_pos:
            sk = sorted(x for x in sw if x[:2] == (b, c)); ok_ = sorted(x for x in orig if x[:2] == (b, c))
            sseq = [(x, w) for x in sk for w in sw[x]]; oseq = [(x, i) for x in ok_ for i in range(len(orig[x]))]
            otxt = [orig[x][i] for x, i in oseq]
            if len(sseq) != len(oseq) or any(norm(a[1][0]) != norm(t) for a, t in zip(sseq, otxt)):
                sys.exit(f"장 배열 불일치 {b}:{c}")
            m = collections.defaultdict(dict)
            for (sk_, w), (ok2, i) in zip(sseq, oseq):
                if w[2]: m[ok2][i] = w[2]
            chap_pos[(b, c)] = m
        finish(ref, k, chap_pos[(b, c)].get(k, {}), "resolved_chapter"); stats["chapter"] += 1; continue
    if reason == "order_or_text_diff":
        o = orig[k]; a = [norm(x[0]) for x in s]; bb = [norm(t) for t in o]
        sm = difflib.SequenceMatcher(None, a, bb, autojunk=False)
        fb = {}; rev = False; notes = []
        ops = sm.get_opcodes()
        # 제외 표시 단어 묶음이 삭제(delete)로 나오고, 같은 단어열이 다른 자리에 삽입(insert)으로 나오면
        # OriginalText가 그 단어들을 다른 위치에 둔 것이므로 그 자리로 대응한다(대상 14:59 유다 성읍 등).
        used = set()
        for tag, i1, i2, j1, j2 in ops:
            if tag == "delete" and all(s[d][2] in excl_set(b) for d in range(i1, i2)):
                for t2, x1, x2, y1, y2 in ops:
                    if t2 == "insert" and (y1, y2) not in used and bb[y1:y2] == a[i1:i2]:
                        used.add((y1, y2))
                        for d in range(i2 - i1): fb[y1 + d] = s[i1 + d][2]
                        notes.append("재배치 대응 " + " ".join(s[d][0] for d in range(i1, i2)) + f" → {y1+1}-{y2}")
                        break
        moved = {x for (y1, y2) in used for x in range(y1, y2)}
        for tag, i1, i2, j1, j2 in ops:
            if tag == "delete" and any(fb.get(j) for j in moved) and all(s[d][2] in excl_set(b) for d in range(i1, i2)) and any(bb[y1:y2] == a[i1:i2] for (y1, y2) in used):
                continue
            if tag == "equal" or (tag == "replace" and i2 - i1 == j2 - j1):
                for d in range(i2 - i1):
                    f = s[i1 + d][2]
                    if f: fb[j1 + d] = f
                    if tag == "replace" and f in excl_set(b):
                        rev = True; notes.append(f"{s[i1+d][0]}{f}→{o[j1+d]}")
            else:
                for d in range(i1, i2):
                    if s[d][2] in excl_set(b):
                        rev = True; notes.append(f"{s[d][0]}{s[d][2]}→(대응 없음)")
        finish(ref, k, fb, "resolved_diff", rev, "; ".join(notes) or None)
        stats["diff_review" if rev else "diff_auto"] += 1
        if rev: reviews.append(ref)
        continue
    finish(ref, k, {}, "resolved_noflag"); stats["noflag"] += 1
# 수동 대응(자동 판정 결과를 눈으로 확인해 고친 절). 값 = OriginalText 1-기반 제외 단어 번호.
# - 9:13:1 OriginalText는 [LXX] 숫자 '삼십/사십'을 절 끝(10·11)에 붙여 두었다.
# - 13:6:27 [LXX] '그 아들(בְּנֽוֹ, 다게시 있음)·사무엘'이 끝(7·8)에 붙어 있다. 6은 마소라 본문 끝 단어(בְנֽוֹ).
# - 13:6:59 [LXX] '윳다와 그 들'(4단어)이 절 끝(10–13)에 붙어 있다.
MANUAL = {"9:13:1": [10, 11], "13:6:27": [7, 8], "13:6:59": [10, 11, 12, 13]}
for ref, ex in MANUAL.items():
    b = int(ref.split(":")[0]); n = V[ref]["n_orig"]
    tag = "[TR]" if b >= 40 else "[LXX]"
    V[ref].update(map="manual", whole_tr=False, excluded=ex, flags={str(i): tag for i in ex})
    V[ref].pop("review", None); V[ref]["note"] = "수동 대응"
    if ref in reviews: reviews.remove(ref)
    stats["manual"] += 1
D["meta"]["resolve_hold"] = {"stats": dict(stats), "review": reviews, "source_md5": D["meta"].get("original_db_md5")}
json.dump(D, open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(dict(stats)); print("review:", reviews)
