#!/usr/bin/env python3
"""
build_reference_data.py

[2026-08-15 신설] 이 폴더(ReferenceDataSource/)에 있는 4개 원천 JSON에서
JBCHBibleResearch/Resources/ReferenceData.sqlite(앱 번들용, 읽기 전용)를
새로 만든다.

이 폴더 자체는 Xcode 타겟 밖(project.pbxproj의 PBXFileSystemSynchronizedRootGroup
동기화 대상이 아닌, .xcodeproj와 나란한 위치)에 있어 앱 번들에는 들어가지
않는다 — 참고자료 원본을 보관해 두는 용도일 뿐이다. 훈음처럼 손으로 직접
정리한 데이터(HanjaDictionary.json)는 이 파일들이 없으면 다시 만들 수 없으니
절대 지우지 말 것.

사용법: `python3 build_reference_data.py` (같은 폴더에서 실행). 필요한
입력 파일 4개(CrossReferenceSeed.json/MarginalNoteSeed.json/
HanjaAnnotationSeed.json/HanjaDictionary.json)와, 관주 책약어 해석에 쓰는
JBCHBibleResearch/Resources/books.json이 모두 이 스크립트 기준 상대 경로에
있어야 한다.

원본 데이터 출처(전부 README "이어서 58/59/60/61/62/65" 참고):
- CrossReferenceSeed.json — 사용자가 업로드한 output.json(관주, 28,380건).
  저작권 출처 미확인 상태(대한성서공회 확인 전) — README 참고.
- MarginalNoteSeed.json — 02개역난외주.bdb에서 각주만 추출(소제목 제외).
  [2026-08-15 갱신] 처음엔 각주 텍스트만 담았지만("절 단위 목록이면
  충분"하다고 판단, 이어서 59), 사용자 요청("난외주 위첨자 위치 표시")으로
  `extract_marginal_note_anchors.py`가 원본 위 첨자 위치까지 다시 뽑아
  `notes: [{note_text, anchor_offset}]` 형식으로 갱신했다. [2026-08-15
  재갱신, 이어서 67] 사용자 질문("원본 태그 번호를 유지했는가?")에 답하며
  드러난 사실 — 앱이 절마다 새로 매긴 번호(①②③...)는 원본 번호(장 전체에
  걸쳐 이어지고, 반복 단어는 번호를 재사용하기도 함)와 57%가 달랐다.
  사용자가 "원본 글자 그대로"를 선택해 `notes: [{note_text, anchor_offset,
  marker_text}]`로 다시 갱신했다 — 자세한 추출 로직/버그 수정 이력은 그
  스크립트 자체의 모듈 docstring 참고.
- HanjaAnnotationSeed.json — 02개역국한문.bdb를 개역한글 본문과 대조해
  단어 단위 UTF-16 오프셋을 미리 계산.
- HanjaDictionary.json — Claude가 학습 지식으로 직접 정리한 2,002자 훈음
  (unicode.org Unihan 데이터를 이 환경에서 받아올 수 없어 사용자 승인 하에
  대체한 방식 — README "이어서 60" 참고).
"""
import json
import os
import re
import sqlite3

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BOOKS_JSON_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "books.json")
OUTPUT_DB_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "ReferenceData.sqlite")

TOKEN_RE = re.compile(r'^([가-힣]+)\s*(\d+):(\d+)$')


def load_abbreviation_index():
    books = json.load(open(BOOKS_JSON_PATH, encoding="utf-8"))
    index = {}
    for b in books:
        for a in b["abbreviation"]:
            index[a] = b["bookId"]
    return index


def parse_targets(content, abbr_index):
    """CrossReferenceSeedImporter.parseTargets(Swift, 이제 삭제됨)와 정확히
    같은 규칙 — 토큰 하나가 형식에 안 맞거나 책약어를 못 찾으면 그 토큰만
    건너뛴다."""
    targets = []
    if not content:
        return targets
    for raw in content.split(","):
        token = raw.strip()
        if not token:
            continue
        m = TOKEN_RE.match(token)
        if not m:
            continue
        abbr, chapter, verse = m.group(1), int(m.group(2)), int(m.group(3))
        book_id = abbr_index.get(abbr)
        if book_id is None:
            continue
        targets.append((book_id, chapter, verse))
    return targets


def main():
    abbr_index = load_abbreviation_index()

    if os.path.exists(OUTPUT_DB_PATH):
        os.remove(OUTPUT_DB_PATH)
    conn = sqlite3.connect(OUTPUT_DB_PATH)
    cur = conn.cursor()

    cur.executescript("""
    CREATE TABLE CrossReferences (
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        targets TEXT NOT NULL
    );
    CREATE INDEX idx_cross_references_bcv ON CrossReferences(book_id, chapter, verse);

    CREATE TABLE MarginalNotes (
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        note_index INTEGER NOT NULL,
        note_text TEXT NOT NULL,
        anchor_offset INTEGER,
        marker_text TEXT
    );
    CREATE INDEX idx_marginal_notes_bcv ON MarginalNotes(book_id, chapter, verse);

    CREATE TABLE HanjaAnnotations (
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        word_index INTEGER NOT NULL,
        ko TEXT NOT NULL,
        hanja TEXT NOT NULL,
        range_start INTEGER NOT NULL,
        range_end INTEGER NOT NULL
    );
    CREATE INDEX idx_hanja_annotations_bcv ON HanjaAnnotations(book_id, chapter, verse);

    CREATE TABLE HanjaDictionary (
        char TEXT PRIMARY KEY,
        eum TEXT NOT NULL,
        hun TEXT NOT NULL,
        count INTEGER NOT NULL,
        confidence TEXT NOT NULL
    );
    """)

    # 1) CrossReferences
    cross_data = json.load(open(os.path.join(SCRIPT_DIR, "CrossReferenceSeed.json"), encoding="utf-8"))
    cross_rows = []
    for entry in cross_data:
        targets = parse_targets(entry.get("content", ""), abbr_index)
        if not targets:
            continue
        targets_str = ",".join(f"{b}:{c}:{v}" for b, c, v in targets)
        cross_rows.append((entry["book_id"], entry["chapter"], entry["verse"], targets_str))
    cur.executemany("INSERT INTO CrossReferences (book_id, chapter, verse, targets) VALUES (?, ?, ?, ?)", cross_rows)
    print("CrossReferences 삽입:", len(cross_rows))

    # 2) MarginalNotes
    # [2026-08-15 갱신] `notes`가 이제 단순 문자열 배열이 아니라
    # `{note_text, anchor_offset, marker_text}` 객체 배열이다 — anchor_offset은
    # 없을 수 있다(원본 철자가 실제 본문과 달라 위치를 못 찾은 소수 사례,
    # `extract_marginal_note_anchors.py` 참고) — 그 경우 NULL로 저장한다.
    # [2026-08-15 재갱신, 이어서 67] marker_text — 앱이 번호를 새로 매기지
    # 않고 원본 <SUP> 태그 글자(①②③, `*` 등)를 그대로 화면에 보여주기로
    # 했다(위 모듈 docstring의 이어서 67 항목 참고).
    marginal_data = json.load(open(os.path.join(SCRIPT_DIR, "MarginalNoteSeed.json"), encoding="utf-8"))
    marginal_rows = []
    for entry in marginal_data:
        for idx, note in enumerate(entry.get("notes", [])):
            marginal_rows.append((
                entry["book_id"], entry["chapter"], entry["verse"], idx,
                note["note_text"], note.get("anchor_offset"), note.get("marker_text"),
            ))
    cur.executemany(
        "INSERT INTO MarginalNotes (book_id, chapter, verse, note_index, note_text, anchor_offset, marker_text) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        marginal_rows,
    )
    print("MarginalNotes 삽입:", len(marginal_rows))

    # 3) HanjaAnnotations
    hanja_ann_data = json.load(open(os.path.join(SCRIPT_DIR, "HanjaAnnotationSeed.json"), encoding="utf-8"))
    hanja_ann_rows = []
    for entry in hanja_ann_data:
        for idx, word in enumerate(entry.get("words", [])):
            hanja_ann_rows.append((
                entry["book_id"], entry["chapter"], entry["verse"], idx,
                word["ko"], word["hanja"], word["start"], word["start"] + word["length"],
            ))
    cur.executemany(
        "INSERT INTO HanjaAnnotations (book_id, chapter, verse, word_index, ko, hanja, range_start, range_end) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        hanja_ann_rows,
    )
    print("HanjaAnnotations 삽입:", len(hanja_ann_rows))

    # 4) HanjaDictionary
    hanja_dict_data = json.load(open(os.path.join(SCRIPT_DIR, "HanjaDictionary.json"), encoding="utf-8"))
    dict_rows = [(d["char"], d["eum"], d["hun"], d["count"], d["confidence"]) for d in hanja_dict_data]
    cur.executemany(
        "INSERT INTO HanjaDictionary (char, eum, hun, count, confidence) VALUES (?, ?, ?, ?, ?)", dict_rows
    )
    print("HanjaDictionary 삽입:", len(dict_rows))

    conn.commit()
    conn.close()
    print("완료:", OUTPUT_DB_PATH, "-", os.path.getsize(OUTPUT_DB_PATH), "bytes")


if __name__ == "__main__":
    main()
