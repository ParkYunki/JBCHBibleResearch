#!/usr/bin/env python3
"""audit_krv.py의 '오탈자 의심'(두 사본이 같은데 앱 본문만 글자가 다른 곳)을 판정해 BibleDB.sqlite에 고친다.

판정: 철자만 현대식으로 바꾼 것(사이시옷, 표준어 철자, 띄어쓰기 등)은 앱 표기를 두고(KEEP),
      나머지(글자 오타, 인명·지명 오기, 조사·어미·낱말이 사본과 다른 것)는 사본대로 고친다.
고칠 때는 앱 본문에서 해당 글자만 바꾸고(SPELL로 앱 표기에 맞춤) 나머지는 그대로 둔다.
--dry-run이면 바꿀 내용만 보여 준다. 변경 기록은 krv_fixes.tsv에 덧붙인다.
"""
import argparse, difflib, json, os, sqlite3, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from audit_krv import NAMES, load, norm  # noqa: E402
from fix_krv import DB, SPELL, ref_text  # noqa: E402

# 앱의 현대식 표기를 그대로 두는 곳: (책, 장, 절, 앱 글자)
KEEP = {
    (2, 14, 2, '닷'),        # 바닷가 ← 바다가
    (3, 6, 9, '위'),         # 단 위 ← 단윗
    (11, 4, 27, '여'),       # 참여 ← 참예
    (12, 4, 16, '돌'), (12, 4, 17, '돌'),   # 돌 ← 돐
    (18, 8, 16, '뻗'),       # 뻗어 ← 벋어
    (21, 8, 8, '무'),        # 머무르게 ← 머므르게
    (30, 5, 23, '랫'),       # 노랫소리 ← 노래 소리
    (41, 13, 19, '조'),      # 창조 ← 창초(사본 오타)
    (42, 22, 44, '핏'),      # 핏방울 ← 피방울
    (44, 2, 25, '었'),       # 뵈었음이여 ← 뵈웠음이여
    (44, 8, 11, '랫'), (44, 20, 11, '랫'),  # 오랫동안 ← 오래 동안
    (47, 6, 4, '란'),        # 곤란 ← 곤난
    (48, 2, 16, '써'),       # 믿음으로써 ← 믿음으로서
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    audit = json.load(open(os.path.join(HERE, 'krv_audit.json'), encoding='utf-8'))
    A = load(DB, 'SELECT book_id, chapter, verse, content FROM BibleVerses')
    M = load(os.path.join(ROOT, 'ReferenceDataSource/02개역난외주.bdb'), 'SELECT book, chapter, verse, btext FROM Bible')
    want = {}
    for k, x, y in audit['subs']:
        k = tuple(k)
        if (*k, x) not in KEEP:
            want.setdefault(k, []).append((x, y))
    new_text, miss = {}, []
    for k, pairs in want.items():
        app, ref = A[k], ref_text(M[k])
        out, done = [], set()
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, app, ref, autojunk=False).get_opcodes():
            piece = ref[j1:j2]
            for s, t in SPELL:
                piece = piece.replace(s, t)
            hit = op == 'replace' and (norm(app[i1:i2]), norm(piece)) in pairs
            if hit:
                done.add((norm(app[i1:i2]), norm(piece)))
                # 띄어쓰기 차이까지 끌고 오지 않도록 앱 쪽 공백 모양을 유지한다.
                piece = piece.strip() if not app[i1:i2].startswith(' ') and not app[i1:i2].endswith(' ') else piece
            out.append(piece if hit else app[i1:i2])
        miss += [(k, p) for p in pairs if p not in done]
        new_text[k] = ''.join(out)
    ref = lambda k: f'{NAMES[k[0] - 1]} {k[1]}:{k[2]}'
    for k, t in new_text.items():
        if t != A[k]:
            print(f'{ref(k)}\n  - {A[k]}\n  + {t}')
    for k, p in miss:
        print(f'!! {ref(k)} 못 고침 {p}')
    print(f'고침 {sum(t != A[k] for k, t in new_text.items())}절, 못 고침 {len(miss)}, 그대로 둠 {len(KEEP)}')
    if not a.dry_run:
        con = sqlite3.connect(DB)
        with open(os.path.join(HERE, 'krv_fixes.tsv'), 'a', encoding='utf-8') as f:
            for k, t in new_text.items():
                if t != A[k]:
                    con.execute('UPDATE BibleVerses SET content=? WHERE book_id=? AND chapter=? AND verse=?', (t, *k))
                    f.write(f'{ref(k)}\t{A[k]}\t{t}\n')
        con.commit()


if __name__ == '__main__':
    main()
