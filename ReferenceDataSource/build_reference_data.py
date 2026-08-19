#!/usr/bin/env python3
"""
build_reference_data.py

[2026-08-15 신설] 이 폴더(ReferenceDataSource/)에 있는 원천 JSON에서
JBCHBibleResearch/Resources/ReferenceData.sqlite(앱 번들용, 읽기 전용)를
새로 만든다.

이 폴더 자체는 Xcode 타겟 밖(project.pbxproj의 PBXFileSystemSynchronizedRootGroup
동기화 대상이 아닌, .xcodeproj와 나란한 위치)에 있어 앱 번들에는 들어가지
않는다 — 참고자료 원본을 보관해 두는 용도일 뿐이다. 훈음처럼 손으로 직접
정리한 데이터(HanjaDictionary.json)는 이 파일들이 없으면 다시 만들 수 없으니
절대 지우지 말 것.

사용법: `python3 build_reference_data.py` (같은 폴더에서 실행). 필요한
입력 파일(CrossReferenceSeed.json/MarginalNoteSeed.json/
HanjaAnnotationSeed.json/HanjaDictionary.json/PersonPlaceSeed.json)과,
관주 책약어 해석에 쓰는 JBCHBibleResearch/Resources/books.json,
그리고 FTS 인덱스 원문 소스인 JBCHBibleResearch/Resources/BibleDB.sqlite가
모두 이 스크립트 기준 상대 경로에 있어야 한다.

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
- PersonPlaceSeed.json — [2026-08-19 신설] 사용자가 첨부한
  bskorea_checkpoint_1.json(대한성서공회 계열 인명·지명 사전, 1,279건 —
  인명 681건/지명 598건)을 그대로 옮긴 것. ⚠️ 이 파일 자체가 "checkpoint"라는
  이름대로 미완성 원본이다 — 인명 681건 중 452건(66%)은 description이 아예
  비어 있다(verses만 있음). 더 온전한 버전을 나중에 구하면 이 파일을
  교체하고 스크립트를 다시 돌리면 된다(추출 로직은 그대로 재사용됨).

[2026-08-19 확장] 사용자 요청 — "① 관주 데이터를 검색 파이프라인에 연결할
것(저작권 문제없음 확인함). ④ 인물 관계 데이터는 체크포인트 파일에서
규칙/AI 기반으로 관계를 추출하는 파이프라인을 만들 것. 구조적으로는 SQLite
FTS로 작업하되 한글 검색에 유용한 tokenize를 제안할 것." 이번 확장으로
새로 생기는 것:

1. VerseSearchIndex — FTS5 `unicode61` 토크나이저 기반 전문 검색 인덱스
   (개역한글 31,102절 전체, BibleDB.sqlite에서 읽어옴). Layer 1(FTS).
   [2026-08-19 재확장] 처음엔 `trigram`으로 만들었으나, 실제 31,102절
   전체로 `trigram`과 `unicode61`(+ prefix 검색 `"검색어"*`) 둘 다 인덱스를
   만들어 실측 비교한 결과 `unicode61`로 교체했다 — 상세 근거는
   `build_verse_search_index()` 함수 docstring 참고.
2. Persons/Places — PersonPlaceSeed.json 전체(1,279건)를 그대로 옮겨 담은
   조회용 테이블. `verses` 컬럼은 `CrossReferences.targets`와 완전히 같은
   포맷("book:chapter:verse,book:chapter:verse")을 써서, Swift 쪽의
   기존 `ReferenceDataStore.parseTargets(_:)`를 그대로 재사용할 수 있게
   했다(새 파싱 함수를 또 만들지 않기 위해).
3. PersonRelations — 위 Persons의 description 텍스트에서 규칙 기반으로
   추출한 관계(아들/아내/형제/지파 소속 등, 22종). Layer 2 확장 + 3번
   리랭커 폴백(Apple Intelligence 미지원 기기에서 인물/지명/관주 연결
   여부를 가산 신호로 쓰는 방식)의 데이터 소스로 쓰인다.

⚠️ 왜 SwiftData(PersonIndex/PlaceIndex, ReferenceIndex.swift)가 아니라
여기(번들 SQLite)로 만드는가 — 이 프로젝트가 이미 같은 이유로 한 번 내린
결정과 정확히 같은 논리를 적용했다: "정적 참조 데이터를 굳이 사용자
CloudKit 데이터베이스에 복사해 넣을 이유가 없다"(관주/난외주/한자주석/
한자사전이 SwiftData 1회성 시딩에서 번들 SQLite로 옮겨간 이유, 이 파일
상단 "2026-08-15 신설" 단락 참고). 인물/지명 사전(1,279건, 사용자가 직접
편집하는 데이터가 아님)도 정확히 같은 성격이라 같은 결론을 적용했다.
`ReferenceIndex.swift`의 `PersonIndex`/`PlaceIndex` SwiftData 모델은 지금
코드베이스 전체에서 모델 정의와 스키마 등록 두 곳 외엔 어디서도 참조되지
않는다(실사용 이력 없음, grep으로 확인) — 그대로 둘지 정리할지는 사용자
결정이 필요해 이 스크립트는 그 모델을 건드리지 않는다.

⚠️ [정밀도 관련, 추측 아니라 실행 확인] PersonRelations 추출은 규칙(정규식)
1단계만 구현했다. 인명 681건 중 description이 있는 229건에서 총 180건의
관계(대상 이름이 이 파일 안의 다른 인명/지명 항목과 실제로 일치하는 것만)를
뽑았고, 490건은 관계 문구는 찾았지만 대상 이름이 이 부분 데이터셋에 없어
연결하지 못했다(체크포인트 파일 자체가 전체 사전의 일부만 담고 있어서 —
예: "노아"는 있지만 "에서"는 이 파일에 없음). 210개 문장은 어느 규칙에도
안 걸렸다. 2단계(AI 보조 추출, FoundationModels)는 아직 구현하지 않았다 —
사용자가 원하면 이 unresolved/unmatched 목록을 입력으로 별도 후속 스크립트를
만들 수 있다.
"""
import json
import os
import re
import sqlite3

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BOOKS_JSON_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "books.json")
OUTPUT_DB_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "ReferenceData.sqlite")
BIBLE_DB_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "BibleDB.sqlite")
PERSON_PLACE_SEED_PATH = os.path.join(SCRIPT_DIR, "PersonPlaceSeed.json")

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


def resolve_single_verse(v, abbr_index):
    """PersonPlaceSeed.json의 `verses` 배열 원소 하나("수 16:8" 형태)를
    (book_id, chapter, verse)로 변환. 형식이 안 맞거나 책약어를 못 찾으면
    None(호출부가 건너뛴다)."""
    m = TOKEN_RE.match(v.strip())
    if not m:
        return None
    abbr, chapter, verse = m.group(1), int(m.group(2)), int(m.group(3))
    book_id = abbr_index.get(abbr)
    if book_id is None:
        return None
    return (book_id, chapter, verse)


# === Person/Place 관계 추출 (2026-08-19 신설) ===
# 원본: extract_person_relations.py (단독 프로토타입, 검증 완료 — 이 스크립트에
# 그대로 흡수). 관계 어휘 22종 — 원본 대화에서 예로 든 형제/원수/소속 3종에,
# 실제 데이터 샘플을 확인해 실제로 자주 나오는 패턴(아들/딸/아내/남편/손자/
# 조부/자손/아버지/지파/사람/족속/왕)을 더했다.
SENSE_SPLIT_RE = re.compile(r'(?:^|\n)\s*(\d+)\.\s*')
GLOSS_RE = re.compile(r'^「[^」]*」\s*')

RELATION_PATTERNS = [
    (r'([가-힣]{2,6})의\s*(?:막내)?아들', 'son_of', '~의 아들'),
    (r'([가-힣]{2,6})의\s*딸', 'daughter_of', '~의 딸'),
    (r'([가-힣]{2,6})의\s*손자', 'grandson_of', '~의 손자'),
    (r'([가-힣]{2,6})의\s*손녀', 'granddaughter_of', '~의 손녀'),
    (r'([가-힣]{2,6})의\s*조부', 'grandfather_of', '~의 조부(entry가 X의 할아버지)'),
    (r'([가-힣]{2,6})의\s*아버지', 'father_of', '~의 아버지(entry가 X의 아버지)'),
    (r'([가-힣]{2,6})의\s*어머니', 'mother_of', '~의 어머니(entry가 X의 어머니)'),
    (r'([가-힣]{2,6})의\s*아내', 'wife_of', '~의 아내'),
    (r'([가-힣]{2,6})의\s*남편', 'husband_of', '~의 남편'),
    (r'([가-힣]{2,6})의\s*며느리', 'daughter_in_law_of', '~의 며느리'),
    (r'([가-힣]{2,6})와는\s*형제', 'brother_of', '~와는 형제'),
    (r'([가-힣]{2,6})의\s*형제', 'brother_of', '~의 형제'),
    (r'([가-힣]{2,6})의\s*(?:친)?아우', 'younger_brother_of', '~의 아우/동생'),
    (r'([가-힣]{2,6})의\s*형(?!제)', 'older_brother_of', '~의 형'),
    (r'([가-힣]{2,6})의\s*자매', 'sister_of', '~의 자매'),
    (r'([가-힣]{2,6})의\s*숙부', 'uncle_of', '~의 숙부'),
    (r'([가-힣]{2,6})의\s*사촌\s*(?:오라비|형제|누이)', 'cousin_of', '~의 사촌'),
    (r'([가-힣]{2,6})의\s*(?:\d+대\s*)?자손', 'descendant_of', '~의 자손'),
    (r'([가-힣]{2,6})의\s*(?:\d+대\s*)?후손', 'descendant_of', '~의 후손'),
    (r'([가-힣]{2,6})의\s*조상', 'ancestor_of', '~의 조상(entry가 X의 조상)'),
    (r'([가-힣]{2,6})(?:과|와)\s*결혼', 'married_to', '~와 결혼'),
    (r'([가-힣]{2,6})\s*지파', 'tribe_of', '~ 지파 소속'),
    (r'([가-힣]{2,6})\s*족속', 'people_of', '~ 족속 소속'),
    (r'([가-힣]{2,6})\s*사람(?:으로)?', 'affiliated_with_place', '~ 사람(출신/소속)'),
    (r'([가-힣]{2,6})\s*왕(?:으로)?', 'king_of', '~의 왕(entry가 X의 왕)'),
]

NOISE_SUFFIX_RE = re.compile(r'(한|된|할|될|는|은)$')
KOREAN_NUMERALS = {'하나', '둘', '셋', '넷', '다섯', '여섯', '일곱', '여덟', '아홉', '열',
                    '일', '이', '삼', '사', '오', '육', '칠', '팔', '구', '십'}
LOOSE_PATTERNS = {'tribe_of', 'people_of', 'affiliated_with_place', 'king_of'}


def split_senses(description):
    text = GLOSS_RE.sub('', description).strip()
    if not text:
        return []
    parts = SENSE_SPLIT_RE.split(text)
    if len(parts) == 1:
        return [(1, text.strip())] if text.strip() else []
    senses = []
    i = 1
    while i < len(parts) - 1:
        num_str, content = parts[i], parts[i + 1]
        content = content.strip()
        if content:
            senses.append((int(num_str), content))
        i += 2
    return senses


def is_probable_noise(target, relation_type):
    if relation_type not in LOOSE_PATTERNS:
        return False
    if target in KOREAN_NUMERALS:
        return True
    if NOISE_SUFFIX_RE.search(target):
        return True
    return False


def extract_relations_from_sense(word, idx, sense_index, sentence, known_person_words, known_place_words):
    found = []
    for pattern, relation_type, label in RELATION_PATTERNS:
        for m in re.finditer(pattern, sentence):
            target = m.group(1)
            if target == word or is_probable_noise(target, relation_type):
                continue
            if target in known_person_words:
                target_kind = 'person'
            elif target in known_place_words:
                target_kind = 'place'
            else:
                target_kind = None
            found.append((word, idx, sense_index, relation_type, label, target, target_kind, sentence))
    return found


def build_person_place_tables(cur, abbr_index):
    with open(PERSON_PLACE_SEED_PATH, encoding="utf-8") as f:
        raw = json.load(f)

    # 원본 체크포인트 파일 자체에 중복 항목이 있음(실행 확인 — 같은 idx가
    # 두 번 나오는 경우 존재). 같은 (kind, idx)가 반복되면 마지막 것을
    # 최종본으로 취급한다.
    dedup = {}
    for entry in raw:
        dedup[(entry["kind"], entry["idx"])] = entry
    entries = list(dedup.values())

    persons = [e for e in entries if e["kind"] == "인명"]
    places = [e for e in entries if e["kind"] == "지명"]
    known_person_words = {e["word"] for e in persons}
    known_place_words = {e["word"] for e in places}

    def verses_str(verse_list):
        resolved = [resolve_single_verse(v, abbr_index) for v in verse_list]
        resolved = [r for r in resolved if r is not None]
        return ",".join(f"{b}:{c}:{v}" for b, c, v in resolved)

    person_rows = [
        (e["idx"], e["word"], e.get("description", "") or "", verses_str(e.get("verses", [])))
        for e in persons
    ]
    place_rows = [
        (e["idx"], e["word"], e.get("description", "") or "", verses_str(e.get("verses", [])))
        for e in places
    ]
    cur.executemany(
        "INSERT INTO Persons (idx, word, description, verses) VALUES (?, ?, ?, ?)", person_rows
    )
    cur.executemany(
        "INSERT INTO Places (idx, word, description, verses) VALUES (?, ?, ?, ?)", place_rows
    )
    print("Persons 삽입:", len(person_rows), "/ Places 삽입:", len(place_rows))

    relation_rows = []
    empty_description_count = 0
    unmatched_sentence_count = 0
    for e in persons:
        description = e.get("description", "") or ""
        if not description.strip():
            empty_description_count += 1
            continue
        for sense_index, sentence in split_senses(description):
            relations = extract_relations_from_sense(
                e["word"], e["idx"], sense_index, sentence, known_person_words, known_place_words
            )
            if not relations:
                unmatched_sentence_count += 1
                continue
            relation_rows.extend(relations)
    cur.executemany(
        "INSERT INTO PersonRelations "
        "(source_word, source_idx, sense_index, relation_type, pattern_label, target_word, target_kind, raw_sentence) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        relation_rows,
    )
    resolved_count = sum(1 for r in relation_rows if r[6] is not None)
    print(
        f"PersonRelations 삽입: {len(relation_rows)}건 "
        f"(해결됨 {resolved_count} / 미해결 {len(relation_rows) - resolved_count}) — "
        f"description 빈 항목 {empty_description_count}건, 패턴 미매치 문장 {unmatched_sentence_count}건"
    )


def build_verse_search_index(cur):
    """[2026-08-19 신설, 같은 날 재확장] Layer 1(FTS) — SQLite FTS5 `unicode61`
    토크나이저(기본 옵션 그대로. remove_diacritics는 라틴 문자 악센트 제거
    옵션이라 한글에는 전혀 영향이 없다 — 31,102절 전체로 remove_diacritics
    기본값/2 두 인덱스를 만들어 모든 테스트 쿼리 결과가 완전히 동일함을
    실행 확인했다).

    [경위] 처음엔 `trigram`을 썼다. 한글 조사(을/를/이/가 등)가 어절 끝에
    붙어 단어 경계 토크나이저로는 "지혜를"/"지혜가"가 다른 토큰이 된다는
    문제를 우회하려는 목적이었다. 그런데 실제 31,102절 전체로 `trigram`과
    `unicode61`+prefix 검색(`"검색어"*`)을 나란히 만들어 실측한 결과, 애초
    가정이 틀렸다는 게 드러났다:
    - `trigram`은 검색어가 정확히 3글자 미만이면(믿음/사랑/은혜 등 매우
      흔한 2글자 한글 신학 용어) 3-gram을 아예 못 만들어 조용히 0건을
      반환한다 — 실행 확인.
    - `trigram`으로 "지혜를"을 검색해도 "지혜가"가 있는 절은 실제로는
      안 잡힌다(각각 62건/57건, 서로 다른 집합) — "trigram이 조사 변화에
      안정적으로 매칭된다"는 애초 가정 자체가 실측으로 반증됨. trigram이
      실제로 잘하는 건 "토큰 중간/끝 부분 문자열까지 겹치면 잡는다"는
      것이지 조사 무관 매칭이 아니었다.
    - 한국어는 조사/어미가 항상 어근 **뒤에만** 붙는 교착어라, `unicode61`
      기본 토크나이저(공백 기준 어절) + prefix 쿼리(`"지혜"*`)가 오히려
      훨씬 잘 맞는다 — "지혜*"로 검색하면 지혜를/지혜가/지혜의/지혜로운/
      지혜롭게 412건이 전부 잡힌다(정확 문자열 매치는 41건뿐). 2글자
      검색어도 문제없이 그대로 매칭된다(trigram의 근본 한계가 없음).
    - 인덱스 크기도 실측 8.5MB(unicode61) vs 15.9MB(trigram)로 거의 절반.
    - 단점은 prefix 매칭이라 토큰 "맨 앞부터"만 잡힌다는 것(단어 중간
      부분 문자열은 못 잡음)인데, 실사용에서 단어 중간 조각만 검색할
      일은 거의 없어 trigram의 제약(2글자 검색어 완전 실패)보다 훨씬
      영향이 작다고 판단했다.

    ⚠️ 이 인덱스는 순수 데이터 구축만 담당한다. 실제 검색 시 반드시
    prefix 검색(`"검색어"*` — 큰따옴표로 감싸 리터럴 처리한 뒤 그 바깥에
    `*`를 붙이는 형태)으로 질의해야 한다는 점, 그리고 이제는 짧은 검색어를
    LIKE로 우회시킬 필요가 없어졌다는 점은 Swift 쪽 조회 계층
    (`ReferenceDataStore.searchVersesFullText`, 별도 전달)의 책임이다.
    """
    bible_con = sqlite3.connect(BIBLE_DB_PATH)
    rows = bible_con.execute("SELECT book_id, chapter, verse, content FROM BibleVerses").fetchall()
    bible_con.close()

    cur.execute("""
        CREATE VIRTUAL TABLE VerseSearchIndex USING fts5(
            book_id UNINDEXED, chapter UNINDEXED, verse UNINDEXED, content,
            tokenize = 'unicode61'
        )
    """)
    cur.executemany(
        "INSERT INTO VerseSearchIndex (book_id, chapter, verse, content) VALUES (?, ?, ?, ?)", rows
    )
    print("VerseSearchIndex(FTS5 unicode61) 삽입:", len(rows), "절 (개역한글, BibleDB.sqlite 기준)")


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

    CREATE TABLE Persons (
        idx TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        description TEXT NOT NULL,
        verses TEXT NOT NULL
    );
    CREATE INDEX idx_persons_word ON Persons(word);

    CREATE TABLE Places (
        idx TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        description TEXT NOT NULL,
        verses TEXT NOT NULL
    );
    CREATE INDEX idx_places_word ON Places(word);

    CREATE TABLE PersonRelations (
        source_word TEXT NOT NULL,
        source_idx TEXT NOT NULL,
        sense_index INTEGER NOT NULL,
        relation_type TEXT NOT NULL,
        pattern_label TEXT NOT NULL,
        target_word TEXT NOT NULL,
        target_kind TEXT,
        raw_sentence TEXT NOT NULL
    );
    CREATE INDEX idx_person_relations_source ON PersonRelations(source_word);
    CREATE INDEX idx_person_relations_target ON PersonRelations(target_word);
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

    # 5) Persons / Places / PersonRelations [2026-08-19 신설]
    build_person_place_tables(cur, abbr_index)

    # 6) VerseSearchIndex(FTS5 unicode61) [2026-08-19 신설, 같은 날 재확장]
    build_verse_search_index(cur)

    conn.commit()
    conn.close()
    print("완료:", OUTPUT_DB_PATH, "-", os.path.getsize(OUTPUT_DB_PATH), "bytes")


if __name__ == "__main__":
    main()
