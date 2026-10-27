#!/usr/bin/env python3
"""audit_krv.py가 찾은 개역한글 본문 누락·중복을 BibleDB.sqlite에 고친다.

- 누락: 앱 본문은 그대로 두고, 난외주 개역 사본에서 빠진 말만 그 자리에 끼워 넣는다(앱 표기·띄어쓰기는 유지).
- 중복: 앞 절 본문이 반복된 절은 앱의 기존 표기 방식대로 '(n절에 포함됨)'으로 바꾼다. 절 안 반복은 REPLACE에 적은 대로 고친다.
--dry-run이면 바꿀 내용만 보여 준다. 변경 기록: krv_fixes.tsv(위치, 이전 본문, 새 본문)
"""
import argparse, difflib, json, os, re, sqlite3, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from audit_krv import NAMES, clean, load, norm  # noqa: E402

DB = os.path.join(ROOT, 'JBCHBibleResearch/Resources/BibleDB.sqlite')
# 자동으로 끼워 넣을 수 없는 곳(어순이 바뀌었거나 글자가 섞인 곳)과 절 안 반복(출 8:21)은 손으로 고친다. (이전 → 새 부분)
REPLACE = {
    (2, 8, 21): ('보내지 아니하면 내가 너와 네 신하와 네 백성을 보내지 아니하면 내가 너와 네 신하와 네 백성과',
                 '보내지 아니하면 내가 너와 네 신하와 네 백성과'),
    (2, 31, 14): ('무릇 그날에 일하는 자는', '무릇 그 날을 더럽히는 자는 죽일지며 무릇 그날에 일하는 자는'),
    (7, 11, 8): ('장로들이 대답하되 이제 우리가 당신을 찾아온 것은 우리와 함께 가서 암몬 자손과 싸우려 하게',
                 '장로들이 입다에게 대답하되 이제 우리가 당신을 찾아온 것은 우리와 함께 가서 암몬 자손과 싸우게 하려'),
    (19, 89, 50): ('유력한 모든 민족의 훼방을 기억하소서', '유력한 모든 민족의 훼방이 내 품에 있사오니'),
    (26, 48, 21): ('동향한 그 지계 앞 이만 오천 척이라', '동향한 그 지계 앞 이만 오천 척과 서향한 그 지계 앞 이만 오천 척이라'),
    (42, 11, 7): ('아이들이 함께 나와 침소에', '아이들이 나와 함께 침소에'),
    (43, 6, 46): ('본 자가 다 있는 것이', '본 자가 있다는 것이'),
    (10, 12, 30): ('그 중량이 한 금 달란트라', '그 중량이 금 한 달란트라'),
}
# 사본의 옛 표기를 앱 표기로 바꾼다(끼워 넣는 말에만).
SPELL = (('찌', '지'), ('찐', '진'), ('쌔', '새'), ('숫군', '수꾼'), ('세째', '셋째'), ('네째', '넷째'))


def ref_text(s):
    s = clean(s)
    s = re.sub(r'〔[^〔〕]*(〔[^〕]*〕[^〔〕]*)*〕', '', s)  # 소제목(안에 괄호가 겹친 것 포함)
    s = re.sub(r'[①-⑳]', '', s)
    return re.sub(r'\s+', ' ', s).strip()


def insert_missing(app, ref, segs):
    """ref에서 app에 없는 부분 중 norm 값이 segs에 해당하는 것만 app에 끼워 넣는다."""
    out, pos = [], 0
    sm = difflib.SequenceMatcher(None, app, ref, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        piece = ref[j1:j2]
        n = norm(piece)
        for x, y in SPELL:
            piece = piece.replace(x, y)
        if op == 'insert' and n and any(n in s or s in n for s in segs):
            out.append(piece)
        elif op == 'replace' and n and len(norm(app[i1:i2])) < len(n) and any(s in n for s in segs):
            out.append(piece)          # 앱 쪽 글자가 사본 쪽에 포함된 채 더 긴 경우(예: 한 글자 바뀌며 어구가 빠짐)
        else:
            out.append(app[i1:i2])
    t = re.sub(r'\s+', ' ', ''.join(out)).strip()
    return re.sub(r'\s*（셀라）', '(셀라)', t)  # 앱은 '(셀라)'를 앞말에 붙여 쓴다


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    audit = json.load(open(os.path.join(HERE, 'krv_audit.json'), encoding='utf-8'))
    A = load(DB, 'SELECT book_id, chapter, verse, content FROM BibleVerses')
    M = load(os.path.join(ROOT, 'ReferenceDataSource/02개역난외주.bdb'), 'SELECT book, chapter, verse, btext FROM Bible')
    fixes, bad = [], []
    for k, segs in audit['omit']:
        k = tuple(k)
        if k in REPLACE:
            continue
        old = A[k]
        segs = [s for s in segs]
        new = insert_missing(old, ref_text(M[k]), segs)
        # 끼워 넣은 뒤에도 빠진 말이 남으면 손으로 볼 목록에 둔다.
        still = [s for s in segs if norm(new).count(s) <= norm(old).count(s)]
        (bad if still or new == old else fixes).append((k, old, new, still))
    for k in audit['dup']:
        k = tuple(k)
        first = k[2] - 1
        while (k[0], k[1], first - 1) in A and norm(re.sub(r'^\[[^\]]*\]', '', A[(k[0], k[1], first - 1)])) == norm(re.sub(r'^\[[^\]]*\]', '', A[k])):
            first -= 1
        fixes.append((k, A[k], f'({first}절에 포함됨)', []))
    for k, (x, y) in REPLACE.items():
        assert A[k].count(x) == 1, k
        fixes.append((k, A[k], A[k].replace(x, y), []))
    ref = lambda k: f'{NAMES[k[0] - 1]} {k[1]}:{k[2]}'
    for k, old, new, still in fixes:
        print(f'{ref(k)}\n  - {old}\n  + {new}')
    for k, old, new, still in bad:
        print(f'!! {ref(k)} 남은 말 {still}\n  - {old}\n  + {new}\n  M {ref_text(M[k])}')
    print(f'고침 {len(fixes)}, 확인 필요 {len(bad)}')
    if not a.dry_run:
        con = sqlite3.connect(DB)
        for k, old, new, _ in fixes:
            con.execute('UPDATE BibleVerses SET content=? WHERE book_id=? AND chapter=? AND verse=?', (new, *k))
        con.commit()
        with open(os.path.join(HERE, 'krv_fixes.tsv'), 'a', encoding='utf-8') as f:
            for k, old, new, _ in fixes:
                f.write(f'{ref(k)}\t{old}\t{new}\n')


if __name__ == '__main__':
    main()
