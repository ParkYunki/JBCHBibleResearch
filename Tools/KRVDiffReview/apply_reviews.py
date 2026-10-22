#!/usr/bin/env python3
"""검토 결과(reviews/)를 검사하고 OriginalText.sqlite LiteralTranslation.difference에 반영한다.

사용 예 (저장소 루트에서):
  python3 Tools/KRVDiffReview/apply_reviews.py --check           # 형식 검사, 누락 장 목록
  python3 Tools/KRVDiffReview/apply_reviews.py --apply           # 통과한 장을 DB에 반영, changes/에 변경 기록
검사: 묶음의 절(개역한글만 제외)과 같은 절·순서, OK/FIX, FIX 글이 비어 있지 않음, 길이(400자 이하), 메타 표현 없음.
변경 기록: changes/<NN>/<NN>_<장>.tsv  (<절>\t<이전 설명>\t<새 설명>)
"""
import argparse, glob, os, re, sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
DB = os.path.join(ROOT, 'JBCHBibleResearch', 'Resources', 'OriginalText.sqlite')
META = re.compile(r'제공된|본 데이터|입력|직역에서는|본 직역|대상 구절의 (텍스트 )?범위')


def packet_verses(path):
    return [int(l[1:].split()[0]) for l in open(path, encoding='utf-8') if l.startswith('#') and '(개역한글만)' not in l]


def check(pkt, rev):
    errs, out = [], []
    want = packet_verses(pkt)
    lines = [l.rstrip('\n') for l in open(rev, encoding='utf-8') if l.strip()]
    got = []
    for l in lines:
        f = l.split('\t')
        if not f[0].strip().isdigit() or f[1:2] not in (['OK'], ['FIX']) or (f[1] == 'OK' and len(f) != 2) or (f[1] == 'FIX' and len(f) != 3):
            errs.append(f'형식: {l[:60]}')
            continue
        v = int(f[0])
        got.append(v)
        if f[1] == 'FIX':
            t = f[2].strip()
            if not t:
                errs.append(f'{v}: 빈 설명')
            elif len(t) > 400:
                errs.append(f'{v}: 길이 {len(t)}')
            elif META.search(t):
                errs.append(f'{v}: 메타 표현')
            out.append((v, t))
    if got != want:
        errs.append(f'절 목록 불일치: 빠짐 {sorted(set(want) - set(got))} 남음 {sorted(set(got) - set(want))}')
    return errs, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--apply', action='store_true')
    a = ap.parse_args()
    pkts = sorted(glob.glob(os.path.join(HERE, 'packets', '*', '*.txt')))
    con = sqlite3.connect(DB)
    missing, bad, ok, fixes = [], 0, 0, 0
    for p in pkts:
        name = os.path.splitext(os.path.basename(p))[0]
        bk = os.path.basename(os.path.dirname(p))
        rev = os.path.join(HERE, 'reviews', bk, name + '.tsv')
        if not os.path.exists(rev):
            missing.append(name)
            continue
        errs, out = check(p, rev)
        if errs:
            bad += 1
            print(name, '; '.join(errs))
            continue
        ok += 1
        fixes += len(out)
        if a.apply and out:
            b, ch = int(bk), int(name.split('_')[1])
            log = []
            for v, t in out:
                old = con.execute('SELECT difference FROM LiteralTranslation WHERE book_id=? AND chapter=? AND verse=?', (b, ch, v)).fetchone()[0]
                if old != t:
                    con.execute('UPDATE LiteralTranslation SET difference=? WHERE book_id=? AND chapter=? AND verse=?', (t, b, ch, v))
                    log.append(f'{v}\t{old}\t{t}')
            if log:
                d = os.path.join(HERE, 'changes', bk)
                os.makedirs(d, exist_ok=True)
                with open(os.path.join(d, name + '.tsv'), 'w', encoding='utf-8') as f:
                    f.write('\n'.join(log) + '\n')
    if a.apply:
        con.commit()
    print(f'통과 {ok}장 (FIX {fixes}절), 실패 {bad}장, 미검토 {len(missing)}장')
    if missing and len(missing) <= 40:
        print('미검토:', ' '.join(missing))


if __name__ == '__main__':
    main()
