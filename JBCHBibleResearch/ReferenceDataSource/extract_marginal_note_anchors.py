#!/usr/bin/env python3
"""
extract_marginal_note_anchors.py

[2026-08-15 신설] 사용자 요청 — "난외주가 있으면 난외주에 해당하는 단어
왼쪽 상단(윗첨자) 숫자 추가 / 성경구절 클릭했을 때 - 성경구절 밑으로 난외주
숫자순서대로 뜻을 표시할 것." 이어서 59에서 만든 MarginalNoteSeed.json은
각주 "텍스트"만 담고 있었다(원본의 위 첨자 위치 앵커는 "절 단위 목록이면
충분하다"고 판단해 일부러 빼 뒀었다 — 그 판단을 이번 요청으로 뒤집는다).

이 스크립트는 02개역난외주.bdb(원본 첨부 파일, 이 폴더에 그대로 보관)를
다시 열어 각주가 실제로 어느 글자 앞에 붙는지(위 첨자 마커 <SUP>①</SUP> 등의
위치)까지 함께 뽑아내고, 그 위치를 이 프로젝트가 실제로 쓰는 개역한글 본문
(Resources/BibleDB.sqlite BibleVerses.content)의 UTF-16 오프셋으로 맞춰
`MarginalNoteSeed.json`을 다시 만든다(기존 파일을 덮어씀 — 형식이
`notes: [str]`에서 `notes: [{note_text, anchor_offset}]`로 바뀌었으므로
`build_reference_data.py`도 함께 갱신해야 한다).

## 원본 HTML 구조 (02개역난외주.bdb의 Bible.btext 컬럼)
- 소제목: `<FONT COLOR="#996699">〔소제목〕</FONT> ` — 이번에도 제외
  (사용자 결정, 이어서 59). 드물게 소제목 안에 성경 참조가 중첩돼 있다
  (`〔노아의 아들들의 후예<SMALL><FONT COLOR="#FF6095">〔대상 1:5-23〕
  </FONT></SMALL>〕`) — 단순 non-greedy 정규식(`.*?`)으로는 이 중첩된
  `</FONT>`에서 멈춰버려 바깥쪽 `〕</FONT>`가 그대로 남는 버그가 있었다
  (처음 시도에서 실측, 1:10:1 등 723개 절 중 다수가 영향받음) — 아래
  `SUBTITLE_RE`가 중첩 한 겹까지 허용하도록 고쳐서 해결했다.
- 위 첨자 마커(앵커 위치): `<SMALL><FONT COLOR="#FF6095"><SUP>①</SUP>
  </FONT></SMALL>` — 이 마커가 나온 바로 그 자리(청소된 텍스트 기준
  오프셋)가 각주 대상 단어의 시작 위치다. 마커 자체는 시각적 폭이 없으므로
  청소된 텍스트에서는 완전히 제거한다.
- 각주 정의(뜻풀이): `<SMALL><FONT COLOR="#FF6095">〔뜻풀이〕</FONT></SMALL>`
  (SUP 없음) — 보통 절 끝에 모아서 나온다. 위 첨자 마커들과 등장 "순서"가
  1:1로 대응한다(직접 확인 — 사본 이문 하나짜리 절부터 위첨자 4개짜리
  절까지 전부 순서가 어긋나지 않았다).

## 본문 정렬(앵커 오프셋 계산)
이 bdb의 "청소된"(태그 제거) 텍스트가 `BibleDB.sqlite`의 실제 절 본문과
매번 완전히 같지는 않다 — 두 파일이 정확히 같은 디지털화 배치가 아니라서
("육십세" vs "육십 세", "지은고로" vs "지은 고로" 같은 옛 표기/띄어쓰기
차이, 이어서 61의 한자 주석 작업 때 겪은 것과 동일한 종류의 문제). 절
전체가 정확히 일치하면 청소된 텍스트의 오프셋을 그대로 쓰고, 안 맞으면
위 첨자 마커 직후 단어(최대 6자, 공백/문장부호 전까지)를 실제 본문에서
다시 찾는다 — 커서를 이전 매칭 위치 이후로만 전진시켜(절 안에서 같은
단어가 여러 번 나와도 순서를 지키기 위해) 앞에서부터 순서대로 찾는다.
그래도 못 찾으면(예스러운 표기 "찌"/"지" 등 철자 자체가 달라 글자 단위
매칭이 실패하는 소수 사례) `anchor_offset`을 null로 남긴다 — 그 각주는
본문 안 위첨자 없이 절 아래 뜻풀이 목록에만 나온다(전체 1,800개 각주 중
39개, 97.8% 성공 — 한자 주석 작업 때의 손실률과 비슷한 수준으로 판단해
받아들였다).
"""
import json
import os
import re
import sqlite3

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_BDB = os.path.join(SCRIPT_DIR, "02개역난외주.bdb")
BIBLE_DB = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "BibleDB.sqlite")
OUTPUT_JSON = os.path.join(SCRIPT_DIR, "MarginalNoteSeed.json")

# 소제목 — 중첩된 FF6095(성경 참조) 블록 한 겹까지 허용하고서야 진짜
# 바깥쪽 </FONT>에서 멈춘다(위 모듈 docstring 참고).
SUBTITLE_RE = re.compile(
    r'^<FONT COLOR="#996699">'
    r'(?:[^<]|<SMALL><FONT COLOR="#FF6095">[^<]*</FONT></SMALL>)*'
    r'</FONT>\s*'
)
SUP_RE = re.compile(r'<SMALL><FONT COLOR="#FF6095"><SUP>([^<]*)</SUP></FONT></SMALL>')
DEF_RE = re.compile(r'\s?<SMALL><FONT COLOR="#FF6095">〔([^〕]*)〕</FONT></SMALL>')

ANCHOR_WORD_MAX_LEN = 6


def load_bible_content():
    conn = sqlite3.connect(BIBLE_DB)
    cur = conn.cursor()
    cur.execute("select book_id, chapter, verse, content from BibleVerses")
    return {(b, c, v): content for b, c, v, content in cur.fetchall()}


def clean_and_extract(btext):
    """원본 btext -> (청소된 텍스트, [앵커 오프셋...], [각주 텍스트...])."""
    text = SUBTITLE_RE.sub("", btext)
    anchors = []
    defs = []
    out = []
    i = 0
    n = len(text)
    while i < n:
        sup_m = SUP_RE.match(text, i)
        if sup_m:
            anchors.append(len("".join(out)))
            i = sup_m.end()
            continue
        def_m = DEF_RE.match(text, i)
        if def_m:
            defs.append(def_m.group(1))
            i = def_m.end()
            continue
        out.append(text[i])
        i += 1
    return "".join(out), anchors, defs


def anchor_word_after(clean_text, offset, max_len=ANCHOR_WORD_MAX_LEN):
    end = offset
    n = len(clean_text)
    count = 0
    while end < n and count < max_len and not clean_text[end].isspace():
        end += 1
        count += 1
    return clean_text[offset:end]


def fuzzy_find(anchor_word, haystack, start_from):
    """anchor_word를 haystack(start_from 이후)에서 글자 사이 공백만 선택적으로
    허용하며 찾는다(이어서 61 한자 주석 추출 때와 같은 원리) — 철자 자체가
    다르면(예: '찌'/'지') 못 찾는다, 그건 의도된 한계다(위 모듈 주석 참고)."""
    if not anchor_word:
        return None
    pattern = r"\s?".join(re.escape(c) for c in anchor_word)
    m = re.compile(pattern).search(haystack, start_from)
    return m.start() if m else None


def main():
    bible = load_bible_content()
    conn = sqlite3.connect(SRC_BDB)
    cur = conn.cursor()
    cur.execute("select book, chapter, verse, btext from Bible")
    rows = cur.fetchall()

    results = []
    exact_match = mismatch = 0
    total_notes = matched_notes = unmatched_notes = 0

    for book, chapter, verse, btext in rows:
        if "#FF6095" not in btext:
            continue
        clean_text, anchors, defs = clean_and_extract(btext)
        if len(anchors) != len(defs):
            mismatch += 1
            continue

        actual = bible.get((book, chapter, verse))
        notes = []
        if actual is not None and actual == clean_text:
            exact_match += 1
            for off, note_text in zip(anchors, defs):
                notes.append({"note_text": note_text, "anchor_offset": off})
                total_notes += 1
                matched_notes += 1
        else:
            if actual is not None:
                mismatch += 1
            cursor = 0
            for off, note_text in zip(anchors, defs):
                total_notes += 1
                word = anchor_word_after(clean_text, off)
                found = fuzzy_find(word, actual, cursor) if actual is not None else None
                if found is not None:
                    notes.append({"note_text": note_text, "anchor_offset": found})
                    cursor = found
                    matched_notes += 1
                else:
                    notes.append({"note_text": note_text, "anchor_offset": None})
                    unmatched_notes += 1

        if notes:
            results.append({"book_id": book, "chapter": chapter, "verse": verse, "notes": notes})

    print("절 수:", len(results))
    print("본문 완전 일치 절:", exact_match, "/ 불일치(정렬 필요) 절:", mismatch)
    print("총 각주:", total_notes, "오프셋 매칭:", matched_notes, "실패(오프셋 없음):", unmatched_notes)
    print("매칭률: {:.2f}%".format(matched_notes / total_notes * 100 if total_notes else 0))

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=None)
    print("저장:", OUTPUT_JSON)


if __name__ == "__main__":
    main()
