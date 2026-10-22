#!/usr/bin/env python3
"""언어별 직역·차이 설명 생성용 입력 묶음(packet) 만들기.

사용 예 (저장소 루트에서):
  python3 Tools/LiteralGen/make_packets.py --langs es,pt,it,fr --books PHM,RUT
  python3 Tools/LiteralGen/make_packets.py --langs ja --books ALL
출력: Tools/LiteralGen/packets/<언어묶음>/<NN>_<BOOK>/<BOOK>_<장3자리>[_<부분>].txt
      긴 장은 --max 절(기본 30)씩 나눈다. 묶음 안 모든 언어의 출력(outputs/)이 이미 있으면 만들지 않는다(--force로 다시 만듦).

묶음 형식(토큰 절약: 공통 원어·LSV는 한 번만, 언어별 번역본 본문은 뒤에):
  @<BOOK> <장> | verses=<첫>-<끝>
  ==COMMON
  #<절>
  O 원어=문맥번역 …   ([TR] 공인본문에만, [NA] 비평 본문(NA27/28)에만, [Byz] 둘 다에 없는 다른 사본의 말, [LXX] 칠십인역 보충, (title)…(text) 시편 표제 경계)
  E LSV 영어 직역
  ==TARGET lang=<언어> bible=<코드> (<이름>)
  #<절> 대상 번역본 본문     (이 절이 없으면 (none))
  ==TARGET …                  (언어 수만큼 반복)
"""
import argparse, os, re, sqlite3, glob, collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RES = os.path.join(ROOT, 'JBCHBibleResearch', 'Resources')
STEP = os.path.join(ROOT, 'BibleSources', 'STEPBible')

BOOKS = "GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM EZK DAN HOS JOL AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP COL 1TH 2TH 1TI 2TI TIT PHM HEB JAS 1PE 2PE 1JN 2JN 3JN JUD REV".split()
BID = {b: i + 1 for i, b in enumerate(BOOKS)}
# 앱 언어 → (번들 번역본 코드, 이름, 리소스 파일). BundledTranslationCatalog.swift와 같아야 한다.
TARGETS = {
    'en': ('BSB', 'Berean Standard Bible', 'Bible_BSB'),
    'es': ('RV1909', 'Reina-Valera 1909', 'Bible_RV1909'),
    'fr': ('LSG1910', 'Louis Segond 1910', 'Bible_LSG1910'),
    'de': ('LUT1912', 'Lutherbibel 1912', 'Bible_LUT1912'),
    'it': ('RIV1927', 'Riveduta 1927', 'Bible_RIV1927'),
    'pt': ('BPM', 'Bíblia Portuguesa Mundial', 'Bible_BPM'),
    'ru': ('SYN', 'Синодальный перевод', 'Bible_SYN'),
    'vi': ('VIE1934', 'Kinh Thánh 1934', 'Bible_VIE1934'),
    'fil': ('TGLULB', 'Banal na Bibliya (ULB)', 'Bible_TGLULB'),
    'th': ('THKJV', 'พระคัมภีร์ภาษาไทยฉบับ KJV', 'Bible_THKJV'),
    'id': ('AYT', 'Alkitab Yang Terbuka', 'Bible_AYT'),
    'ja': ('JPBUNGO', '文語訳聖書', 'Bible_JPBUNGO'),
    # [2026-10-20] 중국어: 1919 官話和合譯本 上帝版. 직역·설명은 간체로 쓰므로 간체 번들을 대상 본문으로 쓴다.
    'zh': ('CUV1919S', '官话和合译本（上帝版·简体）', 'Bible_CUV1919S'),
    # [2026-10-20] 사용자 추가 번역본(앱에 배포하지 않음) — 차이 설명만 만든다. 본문은 저장소 BibleSources/ext/에만 둔다.
    #   nas/nks = 영어 설명, nak/nkk = 한국어 설명(같은 번역본), abb = 필리핀어 설명. 묶음은 nas·nks·abb로만 만든다.
    'nas': ('NASB1995', 'New American Standard Bible (1995)', os.path.join(ROOT, 'BibleSources', 'ext', 'Bible_NASB1995')),
    'nks': ('NKJV1982', 'New King James Version (1982)', os.path.join(ROOT, 'BibleSources', 'ext', 'Bible_NKJV1982')),
    'abb': ('ABAB', 'Ang Bagong Ang Biblia', os.path.join(ROOT, 'BibleSources', 'ext', 'Bible_ABAB')),
    'nak': ('NASB1995', 'New American Standard Bible (1995)', os.path.join(ROOT, 'BibleSources', 'ext', 'Bible_NASB1995')),
    'nkk': ('NKJV1982', 'New King James Version (1982)', os.path.join(ROOT, 'BibleSources', 'ext', 'Bible_NKJV1982')),
}
REF = re.compile(r'^([1-3][A-Z][a-z]|[A-Z][a-z][a-z])\.(\d+)\.(\d+)[^#]*#\d+=(\S+)')


def clean(s):
    s = s.split(' (')[0]
    s = s.replace('/', '').replace('\\', '').replace('¶', '')
    return re.sub(r'\s+', ' ', s).strip()


def load_step():
    """(book, ch, v) -> [(원어, 문맥번역, 표시)]. 시편 표제(0절)는 1절 앞에 (title)…(text)로 붙인다."""
    words = collections.defaultdict(list)
    for f in sorted(glob.glob(os.path.join(STEP, 'TA*.txt'))):
        nt = 'TAGNT' in os.path.basename(f)
        for line in open(f, encoding='utf-8'):
            m = REF.match(line)
            if not m:
                continue
            b = m.group(1).upper()
            if b not in BID:
                continue
            c, v, wtype = int(m.group(2)), int(m.group(3)), m.group(4)
            cols = line.rstrip('\n').split('\t')
            orig = clean(cols[1])
            tr = clean(cols[2] if nt else cols[3])
            flag = ''
            if nt:
                ed = cols[5] if len(cols) > 5 else ''
                in_crit = 'NA28' in ed or 'NA27' in ed
                in_tr = 'TR' in ed
                if in_tr and not in_crit:
                    flag = '[TR]'
                elif in_crit and not in_tr:
                    flag = '[NA]'
                elif not in_crit and not in_tr:
                    flag = '[Byz]'
            elif wtype.startswith('X'):
                flag = '[LXX]'
            key = (b, c, max(v, 1))
            if v == 0 and not words[key]:
                words[key].append(('(title)', '', ''))
            if v != 0 and words[key] and words[key][0][0] == '(title)' and all(w[0] != '(text)' for w in words[key]):
                words[key].append(('(text)', '', ''))
            words[key].append((orig, tr, flag))
    return words


def verse_map(path):
    db = sqlite3.connect(path)
    return {(r[0], r[1], r[2]): r[3] for r in db.execute('SELECT book_id, chapter, verse, content FROM BibleVerses')}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--langs', required=True, help='쉼표 구분 언어 코드(예: es,pt,it,fr)')
    ap.add_argument('--books', required=True, help='쉼표 구분 책 코드(예: PHM,RUT) 또는 ALL')
    ap.add_argument('--max', type=int, default=30, help='묶음 하나의 최대 절 수')
    ap.add_argument('--force', action='store_true')
    a = ap.parse_args()
    langs = [l.strip() for l in a.langs.split(',') if l.strip()]
    for l in langs:
        if l not in TARGETS:
            raise SystemExit(f'알 수 없는 언어: {l} (가능: {", ".join(sorted(TARGETS))})')
    group = '-'.join(langs)
    books = BOOKS if a.books.upper() == 'ALL' else [b.strip().upper() for b in a.books.split(',')]
    step = load_step()
    odb = sqlite3.connect(os.path.join(RES, 'OriginalText.sqlite'))
    lsv = {(r[0], r[1], r[2]): r[3] for r in odb.execute('SELECT book_id, chapter, verse, text FROM LiteralEnglish')}
    tgts = {l: verse_map(os.path.join(RES, TARGETS[l][2] + '.sqlite')) for l in langs}
    made = skipped = 0
    for b in books:
        bid = BID[b]
        for c in sorted({c for (bb, c, v) in lsv if bb == bid}):
            verses = sorted(v for (bb, cc, v) in lsv if bb == bid and cc == c)
            parts = [verses[i:i + a.max] for i in range(0, len(verses), a.max)]
            for pi, part in enumerate(parts, 1):
                stem = f'{b}_{c:03d}' + (f'_{pi}' if len(parts) > 1 else '')
                outs = [os.path.join(HERE, 'outputs', l, f'{bid:02d}_{b}', stem + '.tsv') for l in langs]
                if all(os.path.exists(o) for o in outs) and not a.force:
                    skipped += 1
                    continue
                lines = [f'@{b} {c} | verses={part[0]}-{part[-1]}', '==COMMON']
                for v in part:
                    ws = step.get((b, c, v), [])
                    o = ' '.join(f'{w}={t}{f}' if t else f'{w}{f}' for w, t, f in ws)
                    lines += [f'#{v}', 'O ' + (o or '-'), 'E ' + lsv.get((bid, c, v), '-')]
                for l in langs:
                    code, name, _ = TARGETS[l]
                    lines.append(f'==TARGET lang={l} bible={code} ({name})')
                    for v in part:
                        lines.append(f'#{v} ' + (tgts[l].get((bid, c, v)) or '(none)'))
                d = os.path.join(HERE, 'packets', group, f'{bid:02d}_{b}')
                os.makedirs(d, exist_ok=True)
                with open(os.path.join(d, stem + '.txt'), 'w', encoding='utf-8') as fh:
                    fh.write('\n'.join(lines) + '\n')
                made += 1
    print(f'packets[{group}]: {made} made, {skipped} skipped (all outputs exist)')


if __name__ == '__main__':
    main()
