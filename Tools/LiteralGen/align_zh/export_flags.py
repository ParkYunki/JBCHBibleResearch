#!/usr/bin/env python3
"""[2026-11-07 zhprep1] 원어 단어(OriginalText.sqlite)에 TAGNT/TAHOT 판본 표시를 붙여 edition_flags.json을 만든다.

- 판본 표시는 make_packets.py의 load_step()을 그대로 쓴다(직역을 만들 때와 같은 표시: [TR] [NA] [Byz] [LXX]).
- 절마다 원어 단어 배열을 비교해, 단어 수와 표면형(악센트·구두점을 뺀 비교용 문자열)이 모두 같을 때만
  위치 순서대로 표시를 붙인다(map=pos). 그 밖의 절은 map=hold로 두고 사유를 적는다. hold 절은 자동 병합 대상이 아니다.
- 비교용 정규화는 판정에만 쓴다. 원어 DB·직역 본문은 읽기만 한다.

사용(저장소의 Tools/LiteralGen에서):
  python3 align_zh/export_flags.py --out align_zh/edition_flags.json
"""
import argparse, collections, datetime, hashlib, json, os, re, sqlite3, sys, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # Tools/LiteralGen
import make_packets as M  # noqa: E402

EXCLUDE_NT = {"[TR]", "[Byz]"}   # 비평 본문(NA28) 기준 직역에서 뺀 말
EXCLUDE_OT = {"[LXX]"}           # 마소라 본문 기준 직역에서 뺀 말


def norm(s: str) -> str:
    """판정용: 결합 기호(악센트·모음 부호·칸틸레이션) 제거, 글자·숫자만 남김, 소문자."""
    s = unicodedata.normalize("NFD", s)
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    return re.sub(r"[^\w]", "", s).lower()


def md5(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    step = M.load_step()
    odb_path = os.path.join(M.RES, "OriginalText.sqlite")
    zdb_path = os.path.join(M.RES, "Literal_zh.sqlite")
    odb = sqlite3.connect(f"file:{odb_path}?immutable=1", uri=True)
    zdb = sqlite3.connect(f"file:{zdb_path}?immutable=1", uri=True)

    orig = collections.defaultdict(list)
    for b, c, v, w, t in odb.execute(
            "SELECT book_id, chapter, verse, word_order, original_text FROM original_words ORDER BY 1,2,3,4"):
        orig[(b, c, v)].append((w, t))
    zh = {r for r in zdb.execute("SELECT book_id, chapter, verse FROM LiteralText")}

    # STEP 쪽: 시편 표제 경계 표시 (title)/(text)는 단어가 아니므로 뺀다.
    sw = {}
    for (bk, c, v), ws in step.items():
        sw[(M.BID[bk], c, v)] = [w for w in ws if w[0] not in ("(title)", "(text)")]

    # 장 단위 비교(절 경계 이동 판정용)
    def chap_seq(src, b, c):
        keys = sorted(k for k in src if k[0] == b and k[1] == c)
        out = []
        for k in keys:
            out += [norm(x[1] if src is orig else x[0]) for x in src[k]]
        return out

    chap_cache = {}

    def chapter_same(b, c):
        if (b, c) not in chap_cache:
            chap_cache[(b, c)] = chap_seq(orig, b, c) == chap_seq(sw, b, c)
        return chap_cache[(b, c)]

    verses = {}
    stats = collections.Counter()
    for key in sorted(set(sw) | set(orig) | zh):
        b, c, v = key
        ref = f"{b}:{c}:{v}"
        s = sw.get(key)
        o = orig.get(key)
        rec = {"in_zh": key in zh}
        if s is None and o is None:
            rec.update(map="none", reason="no_original")          # 직역만 있음(예: 고후 13:14)
        elif o is None:
            rec.update(map="hold", reason="source_only", n_step=len(s))   # OriginalText에 이 절 번호가 없음
        elif s is None:
            rec.update(map="hold", reason="original_only", n_orig=len(o))
        elif len(s) != len(o):
            rec.update(map="hold", reason="boundary_shift" if chapter_same(b, c) else "count_diff",
                       n_orig=len(o), n_step=len(s))
        elif any(norm(t) != norm(x[0]) for (_, t), x in zip(o, s)):
            rec.update(map="hold", reason="order_or_text_diff", n_orig=len(o))
        else:
            nt = b >= 40
            excl = EXCLUDE_NT if nt else EXCLUDE_OT
            flags = [x[2] for x in s]
            whole_tr = nt and all(f in EXCLUDE_NT for f in flags) and any(f == "[TR]" for f in flags)
            # 절 전체가 TR인 절은 TR 단어를 직역했으므로 대상에 넣는다.
            excluded = [] if whole_tr else [i + 1 for i, f in enumerate(flags) if f in excl]
            rec.update(map="pos", n_orig=len(o), whole_tr=whole_tr,
                       flags={str(i + 1): f for i, f in enumerate(flags) if f},
                       excluded=excluded)
        stats[(rec["map"], rec.get("reason", "ok"))] += 1
        verses[ref] = rec

    files = sorted(os.path.basename(f) for f in __import__("glob").glob(os.path.join(M.STEP, "TA*.txt")))
    meta = {
        "created": datetime.datetime.now().isoformat(timespec="seconds"),
        "step_files": {f: md5(os.path.join(M.STEP, f)) for f in files},
        "original_db_md5": md5(odb_path),
        "literal_zh_md5": md5(zdb_path),
        "exclude_nt": sorted(EXCLUDE_NT), "exclude_ot": sorted(EXCLUDE_OT),
        "stats": {f"{k[0]}/{k[1]}": n for k, n in sorted(stats.items())},
        "review_status": "auto",
    }
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "verses": verses}, f, ensure_ascii=False, separators=(",", ":"))
    for k, n in sorted(stats.items()):
        print(f"{k[0]:5} {k[1]:20} {n}")


if __name__ == "__main__":
    main()
