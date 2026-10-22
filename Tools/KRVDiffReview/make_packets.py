#!/usr/bin/env python3
"""KRV 차이 설명(OriginalText.sqlite LiteralTranslation.difference) 검토용 입력 묶음을 장 단위로 만든다.

사용 예 (저장소 루트에서):
  python3 Tools/KRVDiffReview/make_packets.py --books 8,57
  python3 Tools/KRVDiffReview/make_packets.py --books ALL
출력: Tools/KRVDiffReview/packets/<NN>/<NN>_<장3자리>.txt  (packets/는 git에 넣지 않는다)

묶음 형식:
  @<책번호> <장> | OT|NT
  #<절>
  K: 개역한글(BibleDB.sqlite BibleVerses)        — (없음) = 개역한글에 이 절 본문이 없다
  O: 원어=문맥 영어 뜻 … (STEPBible. [TR] 공인본문에만, [NA] 비평 본문에만, [Byz] 둘 다 아님,
     [LXX] 칠십인역 보충, (title)…(text) 시편 표제 경계. STEP에 없으면 original_words로 대신한다)
  E: LSV 영어 직역(LiteralEnglish)
  L: 한글 직역(LiteralTranslation.literal_translation)
  D: 현재 차이 설명(LiteralTranslation.difference) — 검토 대상
  LiteralTranslation 행이 없고 개역한글에만 있는 절은 `#<절> (개역한글만)`과 K 줄만 넣는다(문맥 참고용).
"""
import argparse, os, sqlite3, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RES = os.path.join(ROOT, 'JBCHBibleResearch', 'Resources')
sys.path.insert(0, os.path.join(ROOT, 'Tools', 'LiteralGen'))
from make_packets import BOOKS, load_step  # noqa: E402  (STEPBible 원어 읽기는 LiteralGen과 같게)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--books', default='ALL', help='쉼표 구분 책 번호(예: 8,57) 또는 ALL')
    ap.add_argument('--out', default=os.path.join(HERE, 'packets'))
    a = ap.parse_args()
    books = None if a.books.upper() == 'ALL' else {int(x) for x in a.books.split(',')}
    c = sqlite3.connect(os.path.join(RES, 'OriginalText.sqlite'))
    c.execute('ATTACH ? AS b', (os.path.join(RES, 'BibleDB.sqlite'),))
    # BibleVerses에는 (book_id, chapter, verse) 색인이 없어 JOIN이 매우 느리므로 사전으로 읽는다.
    krv = {r[:3]: r[3] for r in c.execute('SELECT book_id, chapter, verse, content FROM b.BibleVerses')}
    eng = {r[:3]: r[3] for r in c.execute('SELECT book_id, chapter, verse, text FROM LiteralEnglish')}
    ow = {}
    for b, ch, v, o, g in c.execute('SELECT book_id, chapter, verse, original_text, gloss_en FROM original_words '
                                    'ORDER BY book_id, chapter, verse, word_order'):
        ow.setdefault((b, ch, v), []).append(f'{o}={g}' if g else o)
    step = load_step()
    lt = {r[:3]: r[3:] for r in c.execute('SELECT book_id, chapter, verse, literal_translation, difference FROM LiteralTranslation')}
    keys = sorted(set(lt) | set(krv))
    chapters = {}
    for k in keys:
        if books and k[0] not in books:
            continue
        chapters.setdefault(k[:2], []).append(k)
    for (b, ch), ks in chapters.items():
        d = os.path.join(a.out, f'{b:02d}')
        os.makedirs(d, exist_ok=True)
        lines = [f"@{b} {ch} | {'OT' if b <= 39 else 'NT'}"]
        for k in ks:
            v = k[2]
            if k not in lt:
                lines += [f'#{v} (개역한글만)', f'K: {krv[k]}']
                continue
            sw = step.get((BOOKS[b - 1], ch, v))
            o = ' '.join(f'{w}={t}{f}' if t else f'{w}{f}' for w, t, f in sw) if sw else ' '.join(ow.get(k, []))
            lines += [f'#{v}', f"K: {krv.get(k) or '(없음)'}", f'O: {o or "-"}', f"E: {eng.get(k) or '-'}",
                      f'L: {lt[k][0]}', f'D: {lt[k][1]}']
        with open(os.path.join(d, f'{b:02d}_{ch:03d}.txt'), 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')
    print(len(chapters), 'chapters')


if __name__ == '__main__':
    main()
