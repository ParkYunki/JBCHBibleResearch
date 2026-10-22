#!/usr/bin/env python3
"""생성 결과(outputs/<언어>/**/*.tsv)를 검사하고 앱용 DB(Resources/Literal_<언어>.sqlite)로 만든다.

사용 예 (저장소 루트에서):
  python3 Tools/LiteralGen/import_outputs.py --check            # 검사만(전체 언어)
  python3 Tools/LiteralGen/import_outputs.py --check --langs fr  # 한 언어만
  python3 Tools/LiteralGen/import_outputs.py --build --langs fr --generator "모델 이름"
검사 실패 묶음은 Tools/LiteralGen/redo_<언어>.txt에 적힌다 → 그 묶음만 다시 생성한다.

출력 TSV 규칙(한 줄 = 한 절): <절번호>\t<직역>\t<차이 설명>
  - 묶음(packet)의 절 수·순서와 정확히 같아야 한다. 머리글·빈 줄·코드 블록 금지.
  - 영어(en)의 직역 칸은 "=" (LSV를 그대로 쓴다).
"""
import argparse, glob, os, re, sqlite3, sys, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RES = os.path.join(ROOT, 'JBCHBibleResearch', 'Resources')
sys.path.insert(0, HERE)
from make_packets import TARGETS, BID  # noqa: E402

# 언어별 문자 검사(이 문자가 일정 비율 이상 있어야 한다)
SCRIPT = {
    'th': r'[฀-๿]', 'ja': r'[぀-ヿ一-鿿]', 'ru': r'[Ѐ-ӿ]', 'zh': r'[一-鿿]', 'nak': r'[가-힣]', 'nkk': r'[가-힣]',
    'vi': r'[ăâđêôơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ]',
}
# 한국어 설명(nak/nkk)은 영어 설명(nas/nks)과 같은 묶음을 쓴다. [2026-10-20]
PACKET_ALIAS = {'nak': 'nas', 'nkk': 'nks'}
BAD = [r'```', r'\*\*', r'^\s*(Here|Below|Sure)\b', r'^\s*#']


def packet_verses(lang, rel):
    """출력 파일에 대응하는 묶음에서 절 목록을 읽는다(묶음 이름에 언어가 들어간 어느 폴더든)."""
    lang = PACKET_ALIAS.get(lang, lang)
    for p in glob.glob(os.path.join(HERE, 'packets', '*', rel.replace('.tsv', '.txt'))):
        group = os.path.basename(os.path.dirname(os.path.dirname(p))).split('-')
        if lang in group:
            head = open(p, encoding='utf-8').readline()
            m = re.search(r'verses=(\d+)-(\d+)', head)
            return list(range(int(m.group(1)), int(m.group(2)) + 1))
    return None


def check_file(lang, path):
    rel = os.path.relpath(path, os.path.join(HERE, 'outputs', lang))
    errs = []
    rows = [l.rstrip('\n') for l in open(path, encoding='utf-8') if l.strip()]
    verses = packet_verses(lang, rel)
    got = []
    for i, line in enumerate(rows, 1):
        f = line.split('\t')
        if len(f) != 3:
            errs.append(f'{i}행: 칸 수 {len(f)} (3이어야 함)')
            continue
        v, lit, diff = f
        if not v.strip().isdigit():
            errs.append(f'{i}행: 절 번호 아님 "{v[:10]}"')
            continue
        got.append(int(v))
        if not lit.strip() or not diff.strip():
            errs.append(f'{v}절: 빈 칸')
        if lang == 'en' and lit.strip() != '=':
            errs.append(f'{v}절: en 직역 칸은 "="')
        for pat in BAD:
            if re.search(pat, lit) or re.search(pat, diff):
                errs.append(f'{v}절: 형식 문자 포함({pat})')
        if lang in SCRIPT and lang != 'en':
            for name, txt in (('직역', lit), ('설명', diff)):
                letters = re.findall(r'\w', txt)
                hits = re.findall(SCRIPT[lang], txt, flags=re.I)
                if letters and len(hits) / len(letters) < (0.05 if lang == 'vi' else 0.3):
                    errs.append(f'{v}절: {name}이 {lang} 글자가 아님')
        if len(diff) > 700:
            errs.append(f'{v}절: 설명이 너무 김({len(diff)}자)')
    if verses is None:
        pass  # 묶음을 지운 뒤(또는 시범분)에는 절 수 비교를 건너뛴다. 절 번호 연속성만 본다.
        if got and got != list(range(got[0], got[0] + len(got))):
            errs.append('절 번호가 연속되지 않음(묶음 없음)')
    elif got != verses:
        errs.append(f'절 목록 불일치: 묶음 {verses[0]}-{verses[-1]}({len(verses)}절), 출력 {len(got)}절')
    return errs, rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--langs', default='ALL')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--build', action='store_true')
    ap.add_argument('--generator', default='AI')
    a = ap.parse_args()
    langs = sorted(TARGETS) if a.langs.upper() == 'ALL' else a.langs.split(',')
    total_bad = 0
    for lang in langs:
        files = sorted(glob.glob(os.path.join(HERE, 'outputs', lang, '*', '*.tsv')))
        bad = []
        data = []
        for p in files:
            errs, rows = check_file(lang, p)
            if errs:
                bad.append((p, errs))
            else:
                book = os.path.basename(os.path.dirname(p)).split('_', 1)[1]
                ch = int(os.path.basename(p).split('_')[1].split('.')[0])
                for r in rows:
                    v, lit, diff = r.split('\t')
                    data.append((BID[book], ch, int(v), lit.strip(), diff.strip()))
        redo = os.path.join(HERE, f'redo_{lang}.txt')
        if bad or os.path.exists(redo):
            with open(redo, 'w', encoding='utf-8') as fh:
                for p, errs in bad:
                    fh.write(os.path.relpath(p, HERE) + '\n' + ''.join(f'  - {e}\n' for e in errs[:8]))
        print(f'{lang}: 파일 {len(files)}, 통과 {len(files) - len(bad)}, 실패 {len(bad)}, 절 {len(data)}' + (f' → {os.path.basename(redo)}' if bad else ''))
        total_bad += len(bad)
        if a.build and data:
            build(lang, data, a.generator)
    sys.exit(1 if (a.check and total_bad) else 0)


def build(lang, data, generator):
    code = TARGETS[lang][0]
    now = datetime.date.today().isoformat()
    out = os.path.join(RES, f'Literal_{lang}.sqlite')
    tmp = out + '.tmp'
    if os.path.exists(tmp):
        os.remove(tmp)
    lsv = {}
    if lang == 'en':
        o = sqlite3.connect(os.path.join(RES, 'OriginalText.sqlite'))
        lsv = {(r[0], r[1], r[2]): r[3] for r in o.execute('SELECT book_id, chapter, verse, text FROM LiteralEnglish')}
    db = sqlite3.connect(tmp)
    db.execute('''CREATE TABLE LiteralText (book_id INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
        text TEXT NOT NULL, basis TEXT, generator TEXT, generated_at TEXT, review_status TEXT,
        PRIMARY KEY(book_id, chapter, verse)) WITHOUT ROWID''')
    db.execute('''CREATE TABLE TranslationDifference (translation_code TEXT NOT NULL, book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL, verse INTEGER NOT NULL, explanation TEXT NOT NULL, generator TEXT, generated_at TEXT,
        review_status TEXT, PRIMARY KEY(translation_code, book_id, chapter, verse)) WITHOUT ROWID''')
    lit_rows, diff_rows = [], []
    for b, c, v, lit, diff in data:
        if lit == '=':
            text, basis, gen = lsv.get((b, c, v), ''), 'LSV', 'copy'
        else:
            text, basis, gen = lit, 'original+LSV', generator
        if text:
            lit_rows.append((b, c, v, text, basis, gen, now, 'ai'))
        diff_rows.append((code, b, c, v, diff, generator, now, 'ai'))
    db.executemany('INSERT OR REPLACE INTO LiteralText VALUES (?,?,?,?,?,?,?,?)', lit_rows)
    db.executemany('INSERT OR REPLACE INTO TranslationDifference VALUES (?,?,?,?,?,?,?,?)', diff_rows)
    db.commit()
    db.execute('VACUUM')
    db.close()
    os.replace(tmp, out)
    print(f'  → {os.path.relpath(out, ROOT)} (직역 {len(lit_rows)}, 설명 {len(diff_rows)})')


if __name__ == '__main__':
    main()
