#!/usr/bin/env python3
"""앱 개역한글 본문(BibleDB.sqlite BibleVerses)의 누락·중복을 독립 사본 두 개와 대조해 찾는다.

비교 사본: ReferenceDataSource/BibleDB_Hanja.bdb(국한문 개역), ReferenceDataSource/02개역난외주.bdb(난외주 개역).
비교 전 정규화: HTML·〔소제목〕·난외주 번호·한자 병기 제거, 한글·숫자만 남김, 표기 차이(찌/지, 세째/셋째, 네째/넷째, 찐/진) 통일.
판정: 두 사본이 모두 가진 말이 앱 본문에만 없으면 '누락', 앱 본문에서 앞 절과 같은 본문이 되풀이되면 '중복'.
       4글자 이상 빠진 말이 앞뒤 두 절 안에 있으면 '절 경계 차이'로 따로 둔다. 시편 표제는 사본에 없으므로 비교하지 않는다.
출력: KRV_누락_점검결과.md, krv_audit.json (이 폴더)
"""
import difflib, json, os, re, sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
NAMES = ('창세기 출애굽기 레위기 민수기 신명기 여호수아 사사기 룻기 사무엘상 사무엘하 열왕기상 열왕기하 역대상 역대하 에스라 느헤미야 에스더 욥기 '
         '시편 잠언 전도서 아가 이사야 예레미야 예레미야애가 에스겔 다니엘 호세아 요엘 아모스 오바댜 요나 미가 나훔 하박국 스바냐 학개 스가랴 말라기 '
         '마태복음 마가복음 누가복음 요한복음 사도행전 로마서 고린도전서 고린도후서 갈라디아서 에베소서 빌립보서 골로새서 데살로니가전서 데살로니가후서 '
         '디모데전서 디모데후서 디도서 빌레몬서 히브리서 야고보서 베드로전서 베드로후서 요한일서 요한이서 요한삼서 유다서 요한계시록').split()


def load(path, q):
    return {r[:3]: r[3] or '' for r in sqlite3.connect(path).execute(q)}


def clean(s):
    return re.sub(r'<[^>]+>', '', s or '').strip()


def norm(s):
    s = clean(s)
    s = re.sub(r'〔[^〕]*〕', '', s)
    s = re.sub(r'[①-⑳]', '', s)
    s = re.sub(r'\([^)]*[一-鿿][^)]*\)', '', s)
    s = re.sub(r'[^가-힣0-9]', '', s)
    for a, b in (('찌', '지'), ('세째', '셋째'), ('네째', '넷째'), ('찐', '진')):
        s = s.replace(a, b)
    return s


def missing(a, r):
    sm = difflib.SequenceMatcher(None, a, r, autojunk=False)
    return [(i1, r[j1:j2]) for op, i1, i2, j1, j2 in sm.get_opcodes() if op in ('insert', 'replace') and (j2 - j1) - (i2 - i1) >= 1]


def main():
    A = load(os.path.join(ROOT, 'JBCHBibleResearch/Resources/BibleDB.sqlite'), 'SELECT book_id, chapter, verse, content FROM BibleVerses')
    H = load(os.path.join(ROOT, 'ReferenceDataSource/BibleDB_Hanja.bdb'), 'SELECT book, chapter, verse, btext FROM Bible')
    M = load(os.path.join(ROOT, 'ReferenceDataSource/02개역난외주.bdb'), 'SELECT book, chapter, verse, btext FROM Bible')
    omit, boundary, dup, subs = [], [], [], []
    keys = sorted(A)
    for i, k in enumerate(keys):
        a = norm(A[k])
        body = lambda x: norm(re.sub(r'^\[[^\]]*\]', '', A[x]))  # 시편 표제 [ ]는 빼고 비교
        if i and keys[i - 1][:2] == k[:2] and len(a) > 10 and body(k) == body(keys[i - 1]):
            dup.append(k)
            continue
        if k not in H or k not in M:
            continue
        h, m = norm(H[k]), norm(M[k])
        if not h or not m or a in (h, m):
            continue
        if h == m:
            for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, h, autojunk=False).get_opcodes():
                if op == 'replace':
                    subs.append((k, a[i1:i2], h[j1:j2]))
        im = missing(a, m)
        segs = [s for p, s in missing(a, h) if s != '셀라' and any(abs(p - q) <= 2 and (s in t or t in s) for q, t in im)]
        if k[0] == 19 and '셀라' in h and '셀라' in m and '셀라' not in a:
            segs.append('셀라')
        if not segs:
            continue
        # 4글자 이상인 말이 모두 앞뒤 두 절 안에 있으면 절을 나누어 실은 것(절 경계 차이)으로 본다.
        near = ''.join(norm(A.get((k[0], k[1], k[2] + d), '')) for d in (-2, -1, 1, 2))
        (boundary if all(len(s) >= 4 and s in near for s in segs) else omit).append((k, segs))
    # 2개 사본 모두에서 같은 부분이 반복되지 않는데 앱 본문 안에서만 되풀이되는 경우
    inner = [k for k in keys if k in M and re.search(r'(.{14,}).*\1', norm(A[k])) and not re.search(r'(.{14,}).*\1', norm(M[k]))]
    # 같은 바꿈이 5번 이상이면 앱의 의도적 표기(침례, 파수꾼, 일찍이 등)로 보고 목록에서 뺀다.
    cnt = {}
    for _, x, y in subs:
        cnt[(x, y)] = cnt.get((x, y), 0) + 1
    systematic = sorted(((n, x, y) for (x, y), n in cnt.items() if n >= 5), reverse=True)
    subs = [t for t in subs if cnt[(t[1], t[2])] < 5]
    ref = lambda k: f'{NAMES[k[0] - 1]} {k[1]}:{k[2]}'
    md = ['# 개역한글 본문 누락·중복 점검 결과', '',
          '앱의 `BibleDB.sqlite` `BibleVerses` 개역한글 본문을 독립 사본 두 개(국한문 개역 `BibleDB_Hanja.bdb`, 난외주 개역 `02개역난외주.bdb`)와 절마다 대조한 결과입니다. '
          '두 사본이 모두 가진 말이 앱 본문에만 없는 경우를 누락으로 봤습니다. 표기 차이(찌/지, 세째/셋째 등)와 띄어쓰기, 문장부호, 한자 병기, 소제목은 비교하지 않았습니다. '
          '스크립트: `Tools/KRVTextAudit/audit_krv.py`.', '',
          f'- 누락: {len(omit)}절', f'- 중복(앞 절 본문 반복): {len(dup)}절, 절 안 반복: {len(inner)}절', f'- 절 경계 차이(누락 아님): {len(boundary)}절', f'- 오탈자 의심(글자 바뀜): {len(subs)}곳', '']

    def block(title, items, note=''):
        md.extend([f'## {title}', ''] + ([note, ''] if note else []))
        md.extend(['| 위치 | 빠진 말(정규화) | 앱 본문 | 사본(난외주 개역) |', '|---|---|---|---|'])
        for k, segs in items:
            md.append(f"| {ref(k)} | {' / '.join(segs)} | {A[k]} | {clean(M[k])} |")
        md.append('')

    long_ = [x for x in omit if max(map(len, x[1])) >= 4]
    short = [x for x in omit if max(map(len, x[1])) < 4]
    block('누락 — 어구 이상(4글자 이상)', long_)
    block('누락 — 짧은 말·글자(1–3글자)', short, '조사·어미 한두 글자가 빠진 오탈자도 포함합니다. 빠진 말은 정규화(띄어쓰기 제거)한 형태입니다.')
    block('절 경계 차이 (누락 아님)', boundary, '빠진 말이 앞뒤 절에 실려 있어 절 구분 차이로 보입니다(누락 아님).')
    md.extend(['## 중복', '', '| 위치 | 앱 본문 | 사본(난외주 개역) |', '|---|---|---|'])
    for k in dup + inner:
        md.append(f'| {ref(k)} | {A[k]} | {clean(M.get(k))} |')
    md.append('')
    affected = sorted({k for k, _ in omit} | set(dup) | set(inner))
    md.extend(['## 차이 설명(difference) 재검토가 필요한 절', '',
               '`OriginalText.sqlite` `LiteralTranslation.difference`는 앱 본문을 기준으로 검토했으므로, 위 누락·중복 절의 본문을 고치면 아래 절의 차이 설명도 다시 검토해야 합니다.', '',
               ', '.join(ref(k) for k in affected), ''])
    md.extend(['## 오탈자 의심 (글자 바뀜)', '',
               '두 사본이 같은 말인데 앱 본문만 글자가 다른 곳입니다. 같은 바꿈이 5번 이상 되풀이되는 것은 앱의 의도적 표기로 보고 뺐습니다: '
               + ', '.join(f'{x}←{y}({n})' for n, x, y in systematic) + '. 옛 표기를 현대 표기로 바꾼 정상적인 차이도 섞여 있으니 확인이 필요합니다.', '',
               '| 위치 | 앱 | 사본 | 앱 본문 |', '|---|---|---|---|'])
    for k, x, y in subs:
        md.append(f'| {ref(k)} | {x} | {y} | {A[k]} |')
    md.append('')
    open(os.path.join(HERE, 'KRV_누락_점검결과.md'), 'w', encoding='utf-8').write('\n'.join(md))
    json.dump({'omit': [[list(k), s] for k, s in omit], 'boundary': [[list(k), s] for k, s in boundary],
               'dup': [list(k) for k in dup], 'subs': [[list(k), x, y] for k, x, y in subs], 'inner_repeat': [list(k) for k in inner]},
              open(os.path.join(HERE, 'krv_audit.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'오탈자 의심 {len(subs)}, ', end='')
    print(f'누락 {len(omit)} (4글자 이상 {len(long_)}), 절 경계 {len(boundary)}, 중복 {len(dup)}, 절 안 반복 {len(inner)}')


if __name__ == '__main__':
    main()
