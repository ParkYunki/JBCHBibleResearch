#!/usr/bin/env python3
"""개역한글 본문을 고친 절의 차이 설명 재검토 결과(reviews_rereview/*.tsv)를 검사하고 DB에 반영한다.

입력 줄: <NN_CCC>\t<절>\tOK  또는  <NN_CCC>\t<절>\tFIX\t<새 설명>
packets_rereview/<같은 이름>.txt의 항목(=== NN_CCC 절 v)과 같은 순서·개수여야 한다.
사용: python3 Tools/KRVDiffReview/apply_rereview.py [--apply] <이름 …>   (예: group_0 typo_3)
변경 기록: changes/rereview_<이름>.tsv  (<NN_CCC>\t<절>\t<이전 설명>\t<새 설명>)
"""
import argparse, os, re, sqlite3, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from apply_reviews import DB, META  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('names', nargs='+')
    a = ap.parse_args()
    con = sqlite3.connect(DB)
    total = 0
    for name in a.names:
        want = re.findall(r'^=== (\d\d_\d{3}) 절 (\d+)', open(os.path.join(HERE, 'packets_rereview', name + '.txt'), encoding='utf-8').read(), re.M)
        rows = [l.rstrip('\n').split('\t') for l in open(os.path.join(HERE, 'reviews_rereview', name + '.tsv'), encoding='utf-8') if l.strip()]
        errs = []
        if [(r[0], r[1]) for r in rows] != want:
            errs.append('항목 목록이 묶음과 다름')
        for r in rows:
            if not ((len(r) == 3 and r[2] == 'OK') or (len(r) == 4 and r[2] == 'FIX' and r[3].strip())):
                errs.append(f'형식: {r[:3]}')
            elif r[2] == 'FIX' and (len(r[3]) > 400 or META.search(r[3])):
                errs.append(f'{r[0]}:{r[1]} 길이·메타 표현')
        if errs:
            print(name, '; '.join(errs))
            continue
        fixes = [r for r in rows if r[2] == 'FIX']
        total += len(fixes)
        print(name, f'OK {len(rows) - len(fixes)}, FIX {len(fixes)}')
        if a.apply:
            log = []
            for ch, v, _, t in fixes:
                k = (int(ch[:2]), int(ch[3:]), int(v))
                old = con.execute('SELECT difference FROM LiteralTranslation WHERE book_id=? AND chapter=? AND verse=?', k).fetchone()[0]
                con.execute('UPDATE LiteralTranslation SET difference=? WHERE book_id=? AND chapter=? AND verse=?', (t.strip(), *k))
                log.append(f'{ch}\t{v}\t{old}\t{t.strip()}')
            with open(os.path.join(HERE, 'changes', f'rereview_{name}.tsv'), 'w', encoding='utf-8') as f:
                f.write('\n'.join(log) + '\n')
    if a.apply:
        con.commit()
    print('FIX 합계', total)


if __name__ == '__main__':
    main()
