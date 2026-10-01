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
- PersonPlaceSeed.json — [2026-08-19 신설, 같은 날 교체] 처음엔 사용자가
  첨부한 bskorea_checkpoint_1.json(1,279건 — 인명 681건/지명 598건, 그중
  452건(66%)이 description 빈 "checkpoint" 원본)을 그대로 옮겼다. 이후
  사용자가 "완성본"이라며 bskorea_인명지명사전.json(2,683건 — 인명
  1,686건/지명 997건)을 첨부해 **전량 교체**했다. ⚠️ [정밀도 관련, 추측
  아니라 실행 확인] "완성본"이라는 이름과 달리, 새 파일이 기존 982개
  항목(구 파일과 idx 기준 공통)의 description을 채워 넣은 경우는 **단
  한 건도 없었다**(실행 확인) — 새 파일이 하는 일은 순전히 표제어를
  1,698건 더 추가하는 것이다. description이 비어 있는 비율은 오히려
  더 높아졌다(인명 66.5%, 지명 85.5% — 구 파일의 인명 66%와 비슷한
  수준이지 개선되지 않았다). 다만 표제어 자체가 크게 늘어난 덕에
  PersonRelations 추출의 "대상 이름 해결률"은 실질적으로 크게
  좋아졌다(아래 build_person_place_tables() 관련 수치 참고) — 관계
  문구가 가리키는 대상이 더 많은 경우 이 파일 안에서 실제로 발견되기
  때문이다. "라흐미=골리앗의 아우"는 이 파일에서도 라흐미 항목 자체의
  description은 여전히 비어 있어 재현되지 않지만, "야일" 항목
  description에 "골리앗의 동생 라흐미를 죽인 엘하난의 아버지"라는
  문장이 있어 (야일 --father_of--> 엘하난) 관계는 실제로 추출된다 —
  라흐미 자신에 대한 관계는 아니지만 관련 정보가 다른 표제어를 통해
  일부 들어왔다는 뜻.

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
2. Persons/Places — PersonPlaceSeed.json 전체(2,683건)를 그대로 옮겨 담은
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
상단 "2026-08-15 신설" 단락 참고). 인물/지명 사전(2,683건, 사용자가 직접
편집하는 데이터가 아님)도 정확히 같은 성격이라 같은 결론을 적용했다.
`ReferenceIndex.swift`의 `PersonIndex`/`PlaceIndex` SwiftData 모델은 지금
코드베이스 전체에서 모델 정의와 스키마 등록 두 곳 외엔 어디서도 참조되지
않는다(실사용 이력 없음, grep으로 확인) — 그대로 둘지 정리할지는 사용자
결정이 필요해 이 스크립트는 그 모델을 건드리지 않는다.

⚠️ [정밀도 관련, 추측 아니라 실행 확인] PersonRelations 추출은 규칙(정규식)
1단계만 구현했다. "완성본" 사전(2,683건, 인명 1,686/지명 997)으로
재실행한 결과: 인명 중 description이 있는 565건에서 총 1,900건의 관계
문구를 뽑았고, 그중 1,647건(86.7%)은 대상 이름이 이 파일 안의 다른
인명/지명 항목과 실제로 일치해 연결됐다(해결됨). 나머지는 대상 이름이 이
파일에 없어 연결하지 못했다(미해결). 최신 수치는 이 스크립트를 실행한
콘솔 출력을 참고할 것(사람 수·description 채움 정도에 따라 계속 바뀜).

[2026-08-19 신설, 2단계(AI 보조 추출) 파이프라인 구현] 1단계(정규식)가
못 잡은 문장은 매 빌드마다 `UnmatchedRelationSentences.json`으로 자동
내보낸다. 이 파일을 입력으로 `AIRelationExtractor`(별도 Swift 패키지,
`ReferenceDataSource/AIRelationExtractor/`)를 Apple Intelligence 지원
기기에서 실행하면 FoundationModels(`SystemLanguageModel`, on-device,
무료)로 문장의 문법적 주어를 실제로 이해해 관계를 추출한다 — 정규식
방식의 근본 한계(문장 속 제3자 언급을 표제어 본인의 관계로 오추출하는
문제, 8·9차 갱신에서 11건 확인·고지됨)를 겨냥한 설계다. 그 결과물
(`AIExtractedRelations.json`)을 이 폴더에 두면 **다음 빌드 때 자동으로
읽어 병합**한다(없어도 빌드는 정상 진행 — 1단계만으로 동작). 정규식
결과와 완전히 동일한 (관계유형, 대상)은 중복 삽입하지 않는다.
`PersonRelations.extraction_method` 컬럼('regex'|'ai')으로 출처를 항상
구분할 수 있다. ⚠️ `AIRelationExtractor`는 FoundationModels가 실제
Apple Intelligence 지원 기기(Xcode 필요)에서만 동작해 이 빌드 스크립트를
실행하는 환경(Python, 기기 무관)에서는 실행·검증이 불가능하다 — 코드는
공식 문서(Apple Developer Documentation, developer.apple.com/documentation/
foundationmodels)를 실행 시점 기준으로 직접 조회해 작성했지만, 실제
컴파일·실행 검증은 사용자가 자신의 기기에서 해야 한다(자세한 사용법은
`AIRelationExtractor/README.md` 참고).
"""
import collections
import json
import os
import re
import sqlite3

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BOOKS_JSON_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "books.json")
OUTPUT_DB_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "ReferenceData.sqlite")
BIBLE_DB_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "BibleDB.sqlite")
PERSON_PLACE_SEED_PATH = os.path.join(SCRIPT_DIR, "PersonPlaceSeed.json")
# [2026-09-15 신설] 통합검색 카테고리 확장(인물/장소/주제) 개선안 —
# claude/bible-research-platform-search-category-expansion-proposal.md 4차
# 갱신에서 사용자가 확정한 방향: PersonSeed.json(3,067건, description이
# call/meaning/introduce/lifetime/event/character + 구조화된 관계 딕셔너리를
# 담고 있음)으로 Persons 콘텐츠를 보강하고, theme01.json(20건)으로 Themes를
# 채운다. 기존 PersonPlaceSeed.json 기반 정규식 관계추출(build_person_place_tables
# 내부)은 description이 자유 텍스트라는 전제라 손대지 않고 그대로 둔다 —
# PersonSeed.json은 별도 함수(enrich_persons_from_seed)로 순수 추가만 한다.
PERSON_SEED_PATH = os.path.join(SCRIPT_DIR, "PersonSeed.json")
THEME01_SEED_PATH = os.path.join(SCRIPT_DIR, "theme01.json")
# [2026-08-19 신설, 2단계 AI 보조 추출 파이프라인]
# UNMATCHED: 1단계(정규식)가 어느 패턴에도 걸리지 않은 문장을 이 스크립트가
#   실행될 때마다 이 경로로 내보낸다(Swift AIRelationExtractor 도구의 입력).
# AI_EXTRACTED: 위 도구가 실제 기기에서 FoundationModels로 그 문장들을 처리한
#   "결과"를 사용자가 이 경로에 갖다 놓으면, 다음 빌드 때 자동으로 읽어
#   PersonRelations에 병합한다(파일이 없으면 그냥 건너뛴다 — 필수 아님).
UNMATCHED_SENTENCES_PATH = os.path.join(SCRIPT_DIR, "UnmatchedRelationSentences.json")
AI_EXTRACTED_RELATIONS_PATH = os.path.join(SCRIPT_DIR, "AIExtractedRelations.json")

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


# [2026-10-01 신설, 사용자 확정] 시드의 `verses` 원소는 한 절("마 26:14")뿐 아니라 범위("마 26:14-16",
# "사8:1-4", "창세기 30:5-6", "왕하 15:8–12")로도 적혀 있다. 범위는 절 하나하나로 풀어 등록한다 —
# 예) "마 26:14-16" -> 마26:14, 마26:15, 마26:16. 책 이름은 약어/전체 이름 모두(`books.json`의 abbreviation에
# 둘 다 들어 있음), 책과 장 사이 공백은 있어도 없어도 되며, 구분 기호는 -, –(en dash), —(em dash), ~를 받는다.
# 형식에 안 맞거나 책을 못 찾거나 끝 절이 시작 절보다 작으면(예: "5-3") 추측하지 않고 빈 목록을 돌려주며,
# 호출부(`expand_verse_list`)가 경고로 모아 출력한다. 장을 넘는 범위("창 1:1-2:3")는 현재 시드에 없어 지원하지 않는다.
VERSE_RANGE_RE = re.compile(r'^([가-힣]+)\s*(\d+)\s*:\s*(\d+)(?:\s*[-\u2013\u2014~]\s*(\d+))?$')


def resolve_verse_refs(v, abbr_index):
    """시드 구절 문자열 하나를 [(book_id, chapter, verse), ...]로 푼다. 한 절이면 원소 1개, 범위면 절마다 1개."""
    m = VERSE_RANGE_RE.match((v or "").strip())
    if not m:
        return []
    abbr, chapter, start = m.group(1), int(m.group(2)), int(m.group(3))
    end = int(m.group(4)) if m.group(4) else start
    book_id = abbr_index.get(abbr)
    if book_id is None or end < start:
        return []
    return [(book_id, chapter, verse) for verse in range(start, end + 1)]


def expand_verse_list(verse_list, abbr_index, warnings=None, label=""):
    """`verses` 배열 전체를 "book:chapter:verse,book:chapter:verse" 문자열(CrossReferences.targets와 같은 포맷)로 만든다.
    범위는 절 단위로 풀고, 같은 절이 중복되면 첫 번째만 남긴다(순서 유지). 풀지 못한 원소는 `warnings`에
    (label, 원문)으로 모아 호출부가 출력하게 한다 — 조용히 버리지 않는다."""
    seen = set()
    parts = []
    for raw in (verse_list or []):
        refs = resolve_verse_refs(raw, abbr_index)
        if not refs:
            if warnings is not None:
                warnings.append((label, raw))
            continue
        for b, c, v in refs:
            if (b, c, v) not in seen:
                seen.add((b, c, v))
                parts.append(f"{b}:{c}:{v}")
    return ",".join(parts)


def report_unresolved_verses(title, warnings):
    if not warnings:
        print(f"{title}: 구절 변환 실패 0건")
        return
    print(f"  ⚠️ {title}: 구절 {len(warnings)}건을 변환하지 못함(형식 확인 필요) — 처음 20건:")
    for label, raw in warnings[:20]:
        print(f"     - {label}: {raw!r}")


def report_missing_bible_verses(title, labeled_targets):
    """변환된 구절이 BibleDB.sqlite에 실제로 존재하는지 확인해 없는 것만 경고한다(삭제하지는 않는다 — 앱은 없는 절을 건너뜀)."""
    if not os.path.exists(BIBLE_DB_PATH):
        return
    conn = sqlite3.connect(BIBLE_DB_PATH)
    cache = {}
    missing = []
    try:
        for label, targets in labeled_targets:
            for token in (targets or "").split(","):
                if not token:
                    continue
                b, c, v = (int(x) for x in token.split(":"))
                key = (b, c, v)
                if key not in cache:
                    cache[key] = conn.execute(
                        "SELECT 1 FROM BibleVerses WHERE book_id=? AND chapter=? AND verse=? LIMIT 1", key
                    ).fetchone() is not None
                if not cache[key]:
                    missing.append((label, token))
    finally:
        conn.close()
    if missing:
        print(f"  ⚠️ {title}: BibleDB에 없는 절 {len(missing)}건 — 책/장/절 오기 가능성(처음 20건):")
        for label, token in missing[:20]:
            print(f"     - {label}: {token}")
    else:
        print(f"{title}: 변환된 모든 절이 BibleDB에 존재")


# [2026-10-01 신설, 사용자 요청 "기록이 없다는 문구는 화면에 '-' 표시"] 본문 필드(소개/생애/사건/성품/지리/역사 등)가
# "~기록되어 있지 않다" 류 문장**만**으로 이뤄졌으면 "-"로 바꾼다. 실제 정보가 함께 들어 있는 필드는 건드리지 않는다:
#  - 문장 중 하나라도 "기록 없음" 표현이 없으면(=다른 정보 문장이 있음) 원문 유지.
#  - 대조/보충 표현(다만, 외에, 뿐, 으나, 으며 …)이 있으면 그 뒤에 정보가 이어지는 것이라 원문 유지.
#  - 빈 값은 "-" (사용자 시드가 비어 있는 칸을 "-"로 적는 관례와 같음).
# 성경 인용 괄호("(역대상 4:15)")와 흩어진 "-" 표시는 판정에서만 지우고 원문은 건드리지 않는다.
NO_RECORD_RE = re.compile(
    r'기록되어 있지 않|기록이 존재하지 않|기록은 존재하지 않|기록이 나타나지 않|기록이 없|'
    r'나타나지 않|확인되지 않|확인할 수 없|존재하지 않|언급되지 않|전해지지 않|알려져 있지 않|명시되어 있지 않|기술되어 있지 않'
)
NO_RECORD_CONTRAST_RE = re.compile(r'다만|외에|이외|뿐|단지|오직|만이|으나|지만|으며|이며|으로만|그러나|하지만|반면|[가-힣]나,|므로|추정|분류|묘사|보이|것으로|용도|으로,')


def normalize_no_record(text):
    value = (text or "").strip()
    if not value or value == "-":
        return "-"
    cleaned = re.sub(r'\([^)]*\)', ' ', value)          # (성경 인용) 제거
    cleaned = re.sub(r'(?:^|\s)-(?=\s|$)', ' ', cleaned)   # 홀로 놓인 "-" 제거
    sentences = [x.strip() for x in re.split(r'(?<=[.。])\s*', cleaned) if x.strip()]
    if not sentences:
        return "-"
    for sentence in sentences:
        if not NO_RECORD_RE.search(sentence) or NO_RECORD_CONTRAST_RE.search(sentence) or len(sentence) > 90:
            return value
    return "-"


# === 주제별 말씀(Themes) 시드 텍스트 파싱 (2026-08-20 신설, 사용자 요청) ===
# 사용자가 "주제별 말씀01.txt"를 올리고 "분석볼것"이라고 지시 — 실제로 열어
# 확인해 보니 "N. 제목" 헤더 아래 성경 구절 목록이 줄줄이 나열된 형태였고,
# 이는 16차에 스키마만 만들어 두고 데이터가 0건이던 Themes 테이블
# (category/title/search_keywords/verse_refs/tags/description)에 정확히
# 대응하는 내용이었다. 사용자에게 확인받은 세 가지 방침:
#   ① search_keywords/tags/description은 이 txt에 없으므로 일단 비워둔다
#      (title만으로 매칭 — ReferenceDataStore.matchesQuery가 이미 title
#      부분일치를 지원하므로 당장도 동작함, 나중에 채워 넣으면 그때부터
#      search_keywords 매칭도 추가로 반영됨).
#   ② "16~17"(범위)·"9,11"(콤마 나열)·"시편133"(절 번호 없는 장 전체) 같은
#      형태는 모두 개별 절로 전개해 verse_refs에 담는다(관계 카드 등 다른
#      기능과 동일하게 "book:chapter:verse,..." 콤마 목록 포맷 유지 —
#      Swift `ReferenceDataStore.parseTargets(_:)`를 그대로 재사용).
#   ③ "주제별 말씀02.txt", "03.txt" 등 후속 파일이 더 있을 예정이라고
#      확인받아, 파일 하나에 특정하지 않고 "주제별 말씀*.txt" 패턴에
#      매칭되는 모든 파일을 정렬된 순서로 읽어들이는 재사용 가능한 구조로
#      만들었다.
#
# ⚠️ [정밀도 관련, 추측 아니라 실행 확인] 실제 첨부된 01.txt(20개 주제,
# 원본 구절 244줄)를 이 파서로 직접 돌려 전량 검증했다 — 파싱 실패 0건,
# 전개된 절 394개 전부가 BibleDB.sqlite(BibleVerses)에 실제로 존재하는
# 절인지 대조까지 완료(존재하지 않는 절이 나오면 그 줄 전체를 건너뛰고
# 콘솔에 경고를 남긴다 — 원문 오타를 조용히 삼키지 않기 위함).
TOPIC_HEADER_RE = re.compile(r'^(\d+)\.\s*(.+)$')
TOPIC_REF_LINE_RE = re.compile(r'^([가-힣]+)\s*(\d+)(?:\s*:\s*(.+))?$')
TOPIC_VERSE_SEG_RANGE_RE = re.compile(r'^(\d+)\s*~\s*(\d+)$')
TOPIC_VERSE_SEG_SINGLE_RE = re.compile(r'^(\d+)$')
TOPIC_SEED_GLOB = os.path.join(SCRIPT_DIR, "주제별 말씀*.txt")


def _parse_topic_verse_spec(spec):
    """콜론 뒤 절 지정 부분("16~17", "9,11", "12")을 정수 절 번호 리스트로
    전개한다. 세그먼트 하나라도 형식이 안 맞으면 None을 담아 호출부가
    그 줄 전체를 실패로 처리하게 한다(부분적으로만 성공한 절 목록을
    조용히 반쪽만 넣지 않기 위함)."""
    verses = []
    for raw_seg in spec.split(","):
        seg = raw_seg.strip()
        m_range = TOPIC_VERSE_SEG_RANGE_RE.match(seg)
        if m_range:
            start, end = int(m_range.group(1)), int(m_range.group(2))
            if end < start:
                verses.append(None)
                continue
            verses.extend(range(start, end + 1))
            continue
        m_single = TOPIC_VERSE_SEG_SINGLE_RE.match(seg)
        if m_single:
            verses.append(int(m_single.group(1)))
            continue
        verses.append(None)
    return verses


def resolve_topic_ref_line(line, abbr_index, all_bible_verses):
    """"주제별 말씀" txt의 절 참조 한 줄을 (book_id, chapter, verse) 튜플
    리스트로 전개한다. 콜론이 없으면 장 전체(예: "시편133")로 취급해 그
    장의 실제 절 전부를 BibleDB.sqlite에서 조회해 채운다. 실패하면
    (None, 에러메시지) — 호출부가 그 줄을 건너뛰고 로그에 남긴다."""
    m = TOPIC_REF_LINE_RE.match(line.strip())
    if not m:
        return None, f"형식 불일치: {line!r}"
    abbr, chapter_str, verse_spec = m.group(1), m.group(2), m.group(3)
    book_id = abbr_index.get(abbr)
    if book_id is None:
        return None, f"책 약어 못 찾음({abbr!r}): {line!r}"
    chapter = int(chapter_str)
    if verse_spec is None:
        verses = sorted(v for (b, c, v) in all_bible_verses if b == book_id and c == chapter)
        if not verses:
            return None, f"해당 장이 BibleDB에 없음: {line!r}"
        refs = [(book_id, chapter, v) for v in verses]
    else:
        verse_numbers = _parse_topic_verse_spec(verse_spec)
        if None in verse_numbers:
            return None, f"절 지정 형식 불일치({verse_spec!r}): {line!r}"
        refs = [(book_id, chapter, v) for v in verse_numbers]
    invalid = [r for r in refs if r not in all_bible_verses]
    if invalid:
        return None, f"BibleDB에 없는 절 {invalid}: {line!r}"
    return refs, None


def load_topic_seed_files(cur, abbr_index):
    """"주제별 말씀*.txt" 파일들을 전부 읽어 Themes 테이블(category='topic')에
    삽입한다. 파일이 하나도 없으면 조용히 0건으로 넘어간다(필수 입력 아님 —
    기존 UNMATCHED/AI_EXTRACTED 파일들과 같은 관례)."""
    import glob

    paths = sorted(glob.glob(TOPIC_SEED_GLOB))
    if not paths:
        return 0, 0

    bible_con = sqlite3.connect(BIBLE_DB_PATH)
    all_bible_verses = set(bible_con.execute("SELECT book_id, chapter, verse FROM BibleVerses").fetchall())
    bible_con.close()

    theme_rows = []
    skipped = []
    for path in paths:
        with open(path, encoding="utf-8") as f:
            lines = [l.rstrip("\n") for l in f]
        current_title = None
        current_refs = []

        def flush():
            if current_title is not None and current_refs:
                verse_refs_str = ",".join(f"{b}:{c}:{v}" for b, c, v in current_refs)
                theme_rows.append(("topic", current_title, None, verse_refs_str, None, None))

        for raw_line in lines:
            line = raw_line.strip()
            if not line:
                continue
            header_m = TOPIC_HEADER_RE.match(line)
            if header_m:
                flush()
                current_title = header_m.group(2).strip()
                current_refs = []
                continue
            if current_title is None:
                continue  # 첫 헤더 이전의 잡음(빈 줄 등)은 무시
            refs, err = resolve_topic_ref_line(line, abbr_index, all_bible_verses)
            if err:
                skipped.append(f"{os.path.basename(path)}: {err}")
                continue
            current_refs.extend(refs)
        flush()

    cur.executemany(
        "INSERT INTO Themes (category, title, search_keywords, verse_refs, tags, description) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        theme_rows,
    )
    if skipped:
        print(f"  ⚠️ 주제별 말씀 파싱 중 {len(skipped)}줄 건너뜀:")
        for s in skipped:
            print("    -", s)
    return len(paths), len(theme_rows)


# === Person/Place 관계 추출 (2026-08-19 신설, 같은 날 정규식 개선) ===
# 원본: extract_person_relations.py (단독 프로토타입, 검증 완료 — 이 스크립트에
# 그대로 흡수). 관계 어휘 24종 — 원본 대화에서 예로 든 형제/원수/소속 3종에,
# 실제 데이터 샘플을 확인해 실제로 자주 나오는 패턴(아들/딸/아내/남편/손자/
# 조부/자손/아버지/지파/사람/족속/왕)을 더했다.
#
# [2026-08-19 정규식 개선] "완성본" 사전(2,683건)으로 재실행한 뒤 미해결
# 452건 전체를 pattern_label별로 직접 훑어 실제 오류 유형을 확인하고
# (추측이 아니라 실행해서 확인한 것) 아래 4가지를 고쳤다:
#
# 1. 느슨한 4개 패턴(지파/족속/사람/왕)이 조사(의/이/가/은/는)까지 통째로
#    캡처해버리는 버그 — 예: "이스라엘의 왕" -> 대상이 "이스라엘의"로
#    캡처됨(조사 포함), "다윗이 왕이 된" -> "다윗이"로 캡처됨. 원인은
#    `\s*왕` 앞에 조사를 명시적으로 처리하는 부분이 없어 탐욕적 캡처가
#    조사까지 삼켜버린 것. 비탐욕(non-greedy) 캡처(`{2,6}?`) + 조사를
#    별도의 선택적 그룹으로 뺀 형태로 교체해 실제 검증(이스라엘의->이스라엘,
#    다윗이->다윗, 암몬의->암몬 등 정상화 확인).
# 2. "OO의 아들/딸" 패턴이 "막내"만 인식하고 "큰아들/맏아들/일곱째 아들"
#    같은 흔한 수식어를 놓쳐 문장 전체가 미매치로 빠지는 경우 — 예:
#    "아담과 하와의 큰아들"(가인), "야곱의 일곱째 아들"(갓). 수식어
#    화이트리스트를 확장했다.
# 3. "OO의 증손/고손"(증손자·고손자)이 어떤 패턴에도 안 걸리는 경우 —
#    기존엔 "자손/후손"(+선택적 "N대")만 인식했다. descendant_of에
#    증손/고손도 추가.
# 4. "OO의 스승"(사제 관계) — 기존 22종에 아예 없던 관계라 통째로
#    패턴 미매치로 빠졌다. teacher_of를 신설했다("가말리엘: 사도
#    바울의 스승" 같은 문장에서 실제로 뽑히는 것 확인).
#
# 그 외에 "이방 여자와 결혼한", "여호사밧 왕이 사람들을" 처럼 대상 자리에
# 특정 이름이 아니라 "여자/사람/가족/왕" 같은 일반명사가 캡처되는 경우가
# 많이 발견됐다 — 이건 정규식으로 "이름인지 아닌지" 완벽히 구분할 방법이
# 없어서(고유명사 판별에는 실제 형태소 분석이 필요함), GENERIC_NOUN_STOPWORDS
# 목록으로 알려진 일반명사만 걸러내는 보수적인 방식을 택했다. 완벽하지
# 않다 — "호리 족속의 조상"처럼 진짜 이름("호리")이 중간에 낀 명사구
# ("족속")에 가려 대상이 아예 못 뽑히는 경우는 이번 개선 범위 밖이다
# (형태소 분석 없이는 "족속 앞의 수식어가 진짜 이름"이라고 일반화해
# 안전하게 판단할 수 없어서 — 잘못 건드리면 다른 정상 케이스를 깨뜨릴
# 위험이 더 크다고 판단했다).
# [2026-08-21 수정, 사용자 신고] "노아의 손자" 검색 오염 신고를 조사하다 발견 —
# 원래는 "N."이 줄바꿈 뒤에 와야만 새 sense로 인식했는데, 실제 데이터 상당수가
# 여러 sense를 줄바꿈 없이 한 줄에 이어 쓴다(예: 노아=384 "1. 라멕의 아들. ...
# 2. 슬로브핫의 딸." — "2."가 줄바꿈이 아니라 그냥 마침표+공백 뒤에 옴). 이
# 때문에 서로 다른 두 성경 인물(홍수의 노아 / 슬로브핫의 딸 노아)의 서술이 한
# sense로 합쳐져 추출되고, "노아, daughter_of, 슬로브핫"처럼 무관한 관계가
# 섞여 나왔다. 927명분 전체를 실측한 결과 이 패턴이 544건에서 발견됨(문서
# claude/bible-research-platform-search-architecture-feasibility.md 31차
# 참고) — 개별 오탐이 아니라 광범위한 구조적 문제라 정규식 자체를 고친다.
#
# 새 조건: "N."이 (문자열 시작) 또는 (줄바꿈) 또는 (마침표·느낌표·물음표·
# 닫는 괄호/따옴표 뒤에 공백이 온 자리) 앞에 있으면 새 sense 경계로 인정한다
# — 즉 "이전 문장이 끝난 자리"라는 조건은 유지하되 줄바꿈일 필요는 없게
# 완화했다. 544건 전수를 이 정규식으로 실행해 번호가 1,2,3...(또는 암묵적
# 1번 생략 후 2,3,4...)처럼 자연스럽게 이어지는지 확인했고, 그렇지 않은 18건
# (예: 므술람=976 "...7. 바니의 아들. 11. 베레갸의 아들..."처럼 번호가
# 비연속이거나, 느다넬=398의 "67."처럼 두 번호가 붙어버린 경우)은 정규식
# 오작동이 아니라 원본 텍스트 자체의 번호 누락/오타로 확인됨 — 이런 항목은
# "잘못 나뉜 것"이 아니라 "원문에 있는 번호 그대로 나뉜 것"이라 정규식을
# 더 손대지 않고 사용자에게 데이터 확인을 요청하는 쪽을 택했다(추측으로
# 번호를 보정하지 않음).
SENSE_SPLIT_RE = re.compile(r'(?:^|\n|(?<=[.!?)」"\'])\s+)(\d+)\.\s*')
GLOSS_RE = re.compile(r'^「[^」]*」\s*')

_ORDINAL_MOD = r'(?:막내|큰|맏|첫째|둘째|셋째|넷째|다섯째|여섯째|일곱째|여덟째|아홉째|열째)?'

# [2026-08-19 신설, 동의어 확장] 사용자 질문("아우와 동생, 아내와 부인/처를 같은
# 말로 인식하는가?")에 실제 코드를 확인해 "아니오"라고 답한 뒤, 사용자가 "그것
# 말고도 동의어를 찾아 적용할 것"이라고 지시해 실제 927명분 description 전체
# 코퍼스를 대상으로 후보 동의어를 하나씩 정규식으로 실행해 실측 확인하고(추측
# 아님) 아래 기준으로 반영했다:
#   ① 실제 매치 건수와 그 전체 원문을 직접 읽어 "표제어 본인에 대한 직접 서술"인지
#      확인 — 제3자(부모/형제 등)의 관계를 괄호나 삽입절로 언급한 것이면 기존
#      11건 오탐과 동일한 구조적 문제이므로 추가하지 않거나(순이익이 없으면
#      스킵), 추가하되 그 특정 사례만 MANUAL_RELATION_REMOVE로 배제한다.
#   ② 이름·다른 단어의 일부로 오매칭될 위험이 있으면(예: "아비"가 "아비멜렉"
#      같은 고유명사 앞부분과 겹침, "백부"가 "백부장"과 겹침, "처"가 "처형/처음/
#      처녀"와 겹침) 부정형 lookahead로 차단하거나, 근거(실제 올바른 매치)가
#      전혀 없으면 아예 추가하지 않았다("백부", "처" 단독 동의어는 실측 결과
#      전부 오매칭뿐이라 제외).
#   ③ 실제 매치가 0건이거나 전부 오매칭인 후보(모친, 백부, 처)는 추가하지 않았다.
# 상세 실측 근거는 프로젝트 문서(claude/bible-research-platform-search-architecture-
# feasibility.md) 12차 갱신 절 참고.
RELATION_PATTERNS = [
    (r'([가-힣]{2,6})의\s*' + _ORDINAL_MOD + r'\s*아들', 'son_of', '~의 아들'),
    (r'([가-힣]{2,6})의\s*' + _ORDINAL_MOD + r'\s*딸', 'daughter_of', '~의 딸'),
    (r'([가-힣]{2,6})의\s*손자', 'grandson_of', '~의 손자'),
    (r'([가-힣]{2,6})의\s*손녀', 'granddaughter_of', '~의 손녀'),
    (r'([가-힣]{2,6})의\s*(?:조부|할아버지)', 'grandfather_of', '~의 조부/할아버지(entry가 X의 할아버지) [2026-08-19 동의어 확장]'),
    # [2026-08-20 신설, 사용자 요청 — "관계에 ... 할머니 조모 외할아버지 외조부
    # 외할머니 외조모 ... 추가할 것"] grandfather_of(조부/할아버지)의 반대짝
    # grandmother_of가 원래 없었다 — 신설. 그리고 "외조부/외할아버지"·
    # "외조모/외할머니"(모계)는 grandfather_of/grandmother_of(부계)와 실제로
    # 다른 사람을 가리키므로(예: 다윗의 할아버지 이새 ≠ 다윗의 외할아버지) 같은
    # relation_type으로 합치지 않고 별도 타입으로 신설했다 — uncle_of가
    # 숙부/삼촌을 하나로 합친 것과는 다른 근거다(그 둘은 애초에 같은 사람을
    # 가리키는 순수 동의어였지만, 부계/모계 조부모는 서로 다른 두 사람이다).
    # 실측(927명분 description 전체, 정규식 실행): "OO의 외할아버지"/"OO의
    # 외조부" 형태로 매치되는 문장은 코퍼스에 0건이었다(디브리=606, 아다야=1897
    # 두 항목이 실제로 외조부/외할아버지 관계를 서술하지만, 둘 다 캡처 대상
    # 자리에 "~ 왕"/"~ 자" 같이 공백으로 분리된 1음절 명사가 와서 {2,6} 최소
    # 길이 요건을 못 채워 애초에 매치가 안 됨 — 이건 기존 "왕"/"자" 같은 칭호가
    # 낀 문장을 못 뽑는 것과 같은 종류의 이미 알려진 한계이지 이번 신설로 새로
    # 생긴 문제가 아니다). 그래도 이 패턴을 추가하는 이유: (a) 검색어 확장
    # 쪽(`RelationSynonyms`, 검색 목적)은 이 코퍼스 추출과 별개로 그대로
    # 효과가 있고, (b) 향후 description 문장이 이 형태로 작성되면 자동으로
    # 뽑히게 되므로. "외조모/외할머니"는 실제로 1건 매치 확인함(로이스=717,
    # "디모데의 외할머니" — 로이스 -> maternal_grandmother_of -> 디모데, 문장
    # 구조가 단순해 정상 매치).
    (r'([가-힣]{2,6})의\s*(?:조모|할머니)', 'grandmother_of', '~의 조모/할머니(entry가 X의 할머니) [2026-08-20 신설]'),
    (r'([가-힣]{2,6})의\s*(?:외조부|외할아버지)', 'maternal_grandfather_of', '~의 외조부/외할아버지(entry가 X의 외할아버지=모계, 부계 조부와 별도 타입) [2026-08-20 신설]'),
    (r'([가-힣]{2,6})의\s*(?:외조모|외할머니)', 'maternal_grandmother_of', '~의 외조모/외할머니(entry가 X의 외할머니=모계, 부계 조모와 별도 타입) [2026-08-20 신설]'),
    (r'([가-힣]{2,6})의\s*(?:아버지|부친|아비(?![가-힣])|아빠)', 'father_of', '~의 아버지/부친/아비/아빠(entry가 X의 아버지) [2026-08-20 동의어 확장]'),
    (r'([가-힣]{2,6})의\s*(?:어머니|엄마)', 'mother_of', '~의 어머니/엄마(entry가 X의 어머니) [2026-08-20 동의어 확장]'),
    (r'([가-힣]{2,6})의\s*' + _ORDINAL_MOD + r'\s*(?:아내|부인)', 'wife_of', '~의 아내/부인 [2026-08-19 동의어 확장]'),
    (r'([가-힣]{2,6})의\s*남편', 'husband_of', '~의 남편'),
    (r'([가-힣]{2,6})의\s*며느리', 'daughter_in_law_of', '~의 며느리'),
    (r'([가-힣]{2,6})와는\s*형제', 'brother_of', '~와는 형제'),
    (r'([가-힣]{2,6})의\s*형제', 'brother_of', '~의 형제'),
    (r'([가-힣]{2,6})의\s*오라비', 'brother_of', '~의 오라비 [2026-08-19 동의어 확장]'),
    (r'([가-힣]{2,6})의\s*(?:(?:친)?아우|남동생)', 'younger_brother_of', '~의 아우/남동생 [2026-08-19 동의어 확장]'),
    (r'([가-힣]{2,6})의\s*형(?!제)', 'older_brother_of', '~의 형'),
    (r'([가-힣]{2,6})의\s*(?:자매|누이|여동생)', 'sister_of', '~의 자매/누이/여동생 [2026-08-19 동의어 확장]'),
    (r'([가-힣]{2,6})의\s*(?:숙부|삼촌)', 'uncle_of', '~의 숙부/삼촌 [2026-08-19 동의어 확장]'),
    (r'([가-힣]{2,6})의\s*사촌\s*(?:오라비|형제|누이)', 'cousin_of', '~의 사촌'),
    (r'([가-힣]{2,6})의\s*(?:\d+대\s*)?자손', 'descendant_of', '~의 자손'),
    (r'([가-힣]{2,6})의\s*(?:\d+대\s*)?후손', 'descendant_of', '~의 후손'),
    (r'([가-힣]{2,6})의\s*증손', 'descendant_of', '~의 증손 [2026-08-19 신설]'),
    (r'([가-힣]{2,6})의\s*고손', 'descendant_of', '~의 고손 [2026-08-19 신설]'),
    (r'([가-힣]{2,6})의\s*(?:조상|선조)', 'ancestor_of', '~의 조상/선조(entry가 X의 조상) [2026-08-19 동의어 확장]'),
    (r'([가-힣]{2,6})(?:과|와)\s*결혼', 'married_to', '~와 결혼'),
    (r'([가-힣]{2,6})의\s*스승', 'teacher_of', '~의 스승 [2026-08-19 신설]'),
    # [2026-08-20 신설, 사용자 요청 — "관계에 동역자도 추가할 것"] 실측(927명분
    # description 전체, 정규식 실행): "OO의 동역자" 형태로 11건 매치 — 그 중
    # 10건은 전부 "바울"(가이오/그레스게/두기고/드로비모/디도/브리스가/세나/
    # 아리스다고/예수(=유스도)/우르바노, 모두 사도 바울의 동역자로 실제 서술된
    # 정확한 관계)이고, 나머지 1건(우르바노=2759)은 "복음의 동역자, 성도"라는
    # 문장에서 "복음"이 대상으로 잘못 캡처됨(같은 항목에 "바울의 동역자로
    # 수고함"이라는 올바른 문장도 별도로 있어 그건 정상 추출됨). "복음"은
    # 아래 GENERIC_NOUN_STOPWORDS에 실측 근거로 추가해 이 1건만 걸러냈다 —
    # 정규식으로 "복음"이 사람 이름이 아님을 구분할 방법이 없다는 점은 기존
    # "여자/사람/왕" 등과 같은 구조적 한계라 같은 방식(화이트리스트)으로
    # 대응한다. "선교 동역자"/"선지자, 선교 동역자"(실루아노=1828, 아굴라=1860)
    # 처럼 "OO의" 없이 명사가 바로 붙는 문장은 이 패턴이 원래 못 잡는다(다른
    # 관계유형들도 전부 "~의 ROLE" 어순만 다루는 것과 동일한 기존 설계 범위) —
    # 새 버그가 아니라 이번 신설로도 그대로 남는, 이미 알려진 한계다.
    (r'([가-힣]{2,6})의\s*동역자', 'co_worker_of', '~의 동역자 [2026-08-20 신설]'),
    # 느슨한 4종 — [2026-08-19 개선] 비탐욕(non-greedy) 캡처 + 조사(의/이/가/은/는)를
    # 별도 선택 그룹으로 분리해, 조사가 대상 이름에 붙어 캡처되는 버그를 없앴다.
    (r'([가-힣]{2,6}?)(?:의|이|가|은|는)?\s*지파', 'tribe_of', '~ 지파 소속'),
    (r'([가-힣]{2,6}?)(?:의|이|가|은|는)?\s*족속', 'people_of', '~ 족속 소속'),
    (r'([가-힣]{2,6}?)(?:의|이|가|은|는)?\s*사람(?:으로)?', 'affiliated_with_place', '~ 사람(출신/소속)'),
    (r'([가-힣]{2,6}?)(?:의|이|가|은|는)?\s*왕(?:으로)?', 'king_of', '~의 왕(entry가 X의 왕)'),
]

# [2026-08-19 신설] "A와 B 사이의 아들/딸" — 부모 두 명을 한 문장에서
# 같이 언급하는 구문. 기존 단일 캡처 패턴으로는 "사이"라는 엉뚱한 단어가
# 대상으로 잡혔었다(예: "유다와 다말 사이의 아들" -> 대상="사이"). 부모
# 이름 둘을 각각 별도 관계로 뽑는다.
JOINT_PARENT_RE = re.compile(
    r'([가-힣]{2,6})(?:과|와)\s*([가-힣]{2,6})\s*사이의\s*' + _ORDINAL_MOD + r'\s*(아들|딸)'
)

# [2026-08-20 신설, 사용자 요청] "OOO가 아버지이다"/"OOO가 어머니이다" — 표제어
# 자신의 부모를 주어-선행 어순으로 서술하는 문장(예: 게셋 "나홀이 아버지이다.
# 밀가가 어머니이다."). 기존 father_of/mother_of 패턴(RELATION_PATTERNS의
# "[가-힣]{2,6}의 아버지/어머니")은 전부 "TARGET의 ROLE이다"(목적어+의+ROLE)
# 어순만 다뤄 이 반대 어순(주어+이/가+ROLE)을 놓쳤다 — 24차에서 아켈라오
# 사례("헤롯 대왕이 아버지이다")로 처음 발견·보고했는데, 전체 코퍼스를 실행해
# 보니 게셋/스와에도 이미 같은 어순이 있어(사용자의 이번 수정과 무관하게 기존
# 원본 텍스트에 있었음) 총 3명분 6문장이 해당됨을 확인했다.
#
# ⚠️ 방향이 기존 father_of/mother_of 패턴과 정반대라는 게 핵심이다 — 이 문장은
# "표제어 자신의 부모가 누구인지"를 말하므로, 캡처된 이름이 부모(source)이고
# 표제어 자신이 자녀(target)다. RELATION_PATTERNS 메인 루프는 항상 표제어를
# source로 고정하는 구조라(모든 기존 패턴이 "표제어가 스스로를 ROLE로 서술"하는
# 문장이라 성립하는 전제) 이 반대 방향을 표현할 수 없다 — JOINT_PARENT_RE와
# 같은 이유로 메인 루프 밖에서 별도 처리한다. JOINT_PARENT_RE와의 차이:
# JOINT_PARENT_RE가 다루는 "아들/딸" 역할은 표제어 자신에게 붙는 역할이라
# (표제어가 source) 방향이 안 바뀌지만, 여기 "아버지/어머니" 역할은 캡처된
# 이름에게 붙는 역할이라(그 이름이 source) 방향이 바뀐다.
SUBJECT_FIRST_PARENT_RE = re.compile(
    r'([가-힣]{2,6})(?:이|가)\s*(아버지|어머니)(?:이다|이었다|였다|다)'
)

# [2026-08-19 신설, 잔존 오탐 11건 수기 교정] 8·9차 갱신에서 disclose한 11건의
# 잔존 오탐(정규식이 문장의 문법적 주어를 판별 못해 제3자 언급을 표제어 본인의
# 관계로 잘못 추출한 사례)을, 사용자가 직접 원문을 확인해 준 교정 내역대로
# 정정한다. **AI 추론이나 성경 지식으로 유추한 것이 전혀 아니고, 사용자가
# 채팅으로 직접 전달한 교정 목록을 코드로 그대로 옮긴 것**이다(2026-08-19,
# "잔존 오탐 11건 중 10건 수기 수정" 메시지 원문 그대로).
#
# 나하래·호세야는 대체할 올바른 관계가 없어("-") 오탐만 제거하고 새로
# 추가하지 않는다. 나머지 8명(라흐미/리배/로단/엘하난/노하/디르하나/여델/
# 하아하스다리)은 오탐을 제거하고 사용자가 확인해 준 올바른 관계로 교체한다.
# 로단의 경우 "로단의 누이-딤나"(로단의 여동생이 딤나)는 방향을 뒤집어
# (딤나 --sister_of--> 로단)으로 넣었다 — 기존 관계유형 표기 관례(예:
# father_of/king_of/teacher_of 주석에 명시된 "entry가 X의 ROLE"과 동일하게,
# 모든 relation_type은 "source가 target의 ROLE"을 뜻하므로 "로단의 누이는
# 딤나"는 "딤나가 로단의 자매(sister_of)"로 표현해야 관례와 일치한다.
#
# REMOVE: 정규식이 잘못 추출한 (source_word, relation_type, target_word) 삼중항.
# ADD: 사용자가 확인해 준 올바른 (source_word, relation_type, target_word) 삼중항
#      — target_kind는 다른 관계와 동일하게 Persons/Places 표제어 집합과
#      대조해 자동 해결한다(수기로 단정하지 않음).
MANUAL_RELATION_REMOVE = [
    ('나하래', 'son_of', '스루야'),
    ('라흐미', 'son_of', '야일'),
    ('리배', 'son_of', '사울'),
    ('리배', 'father_of', '자들'),
    ('로단', 'son_of', '에서'),
    ('엘하난', 'younger_brother_of', '골리앗'),
    ('노하', 'son_of', '야곱'),
    ('디르하나', 'son_of', '헤스론'),
    ('여델', 'father_of', '아마사'),
    ('하아하스다리', 'father_of', '드고아'),
    ('호세야', 'father_of', '장관'),
    # [2026-08-19 신설, 동의어 확장 중 자체 발견] 위 11건과 달리 사용자가
    # 확인해 준 것이 아니라, 동의어 패턴(아비/누이/부인)을 새로 추가하면서
    # 전체 코퍼스를 실측 대조하는 과정에서 제가 직접 원문을 읽고 확인한
    # 오탐 4건. 전부 "표제어 본인이 아니라 그 부모/문맥 속 다른 인물의
    # 관계를 괄호·조건절로 언급"한 동일한 구조적 문제(기존 11건과 같은
    # 유형)이며, 새 패턴이 없었다면애초 미매치로 빠져 있던 문장들이다.
    #  - 살마: "훌(부) 또는 나손의 자녀이다(보아스의 아비 살몬과 동일시될
    #    경우)." — "~일 경우"라는 조건부 가정일 뿐, 살마 본인이 보아스의
    #    아버지라는 확정 서술이 아님(호세야의 "이거나"와 동일한 유형).
    #  - 아비새: "스루야의 자녀이다(다윗의 누이)." — "다윗의 누이"는 아비새의
    #    어머니 스루야를 가리키는 삽입구. 아비새 본인은 남성 군사령관으로
    #    다윗의 조카이지 누이가 아님.
    #  - 아사헬: "다윗의 누이 스루야의 아들." — 위와 동일한 구조(스루야에 대한
    #    수식어절), 아사헬 본인이 아님.
    #  - 달매: "다윗의 부인 마아가의 아버지로 그술 왕." — "다윗의 부인"은
    #    딸 마아가를 가리키는 수식어. 달매 본인(그술 왕, 남성)은 다윗의
    #    아내가 아님.
    ('살마', 'father_of', '보아스'),
    ('아비새', 'sister_of', '다윗'),
    ('아사헬', 'sister_of', '다윗'),
    ('달매', 'wife_of', '다윗'),
    # [2026-08-20 신설, 사용자가 "다윗의 부모" 검색 결과 이상 신고 → 직접
    # 원문 대조로 확인] 위 15건과 동일한 구조적 문제(제3자 언급 오추출) 2건을
    # 추가로 발견 — 사용자가 "삼마는 다윗의 아버지"처럼 검색 결과가 이상하다고
    # 신고해서 원인을 조사하다가 직접 찾았다. 추측이 아니라 raw_sentence
    # 원문을 읽고 확인:
    #  - 삼마: "다윗의 아버지 이새의 셋째 아들." — "다윗의 아버지"는 삼마
    #    본인이 아니라 이새를 가리키는 수식어("이새는 다윗의 아버지")이고,
    #    삼마 본인은 그 이새의 셋째 아들(=다윗의 형제)이다. 실제로는
    #    (삼마, son_of, 이새)가 같은 문장에서 이미 별도로 정상 추출되어
    #    있어 이 오탐을 제거해도 정보 손실은 없다.
    #  - 요셉: "예수의 어머니 마리아의 남편." — "예수의 어머니"는 요셉 본인이
    #    아니라 마리아를 가리키는 수식어이고, 요셉 본인은 그 마리아의
    #    남편이다(남성이 mother_of일 수 없다는 것 자체가 이미 모순). 실제로는
    #    (요셉, husband_of, 마리아)와 (마리아, mother_of, 예수)가 각각 별도
    #    문장/항목에서 이미 정상 추출되어 있어 이 오탐을 제거해도 정보 손실은
    #    없다.
    # ⚠️ 비슷한 표면 구조("TARGET의 아버지/어머니 다른이름의")를 가진 다른
    # 후보도 코퍼스 전체에서 실행해 확인했으나(사독→아킴, "아킴의 아버지
    # 예수의 조상") 이건 실제로 마태복음 1:14 족보(아소르→사독→아킴→엘리웃)와
    # 일치하는 정확한 관계라 제외했다 — 표면 패턴만으로 자동 판별하지 않고
    # 건마다 직접 확인한 것.
    ('삼마', 'father_of', '다윗'),
    ('요셉', 'mother_of', '예수'),
]
MANUAL_RELATION_ADD = [
    ('라흐미', 'younger_brother_of', '골리앗'),
    ('리배', 'father_of', '바아나'),
    ('리배', 'father_of', '레갑'),
    ('로단', 'father_of', '호리'),
    ('로단', 'father_of', '호맘'),
    ('딤나', 'sister_of', '로단'),
    ('엘하난', 'son_of', '야일'),
    ('노하', 'son_of', '베냐민'),
    ('디르하나', 'son_of', '갈렙'),
    ('여델', 'son_of', '기드온'),
    ('하아하스다리', 'son_of', '나아라'),
]
MANUAL_CORRECTION_LABEL = '~ [사용자 수기 검증/교정, 2026-08-19 — 잔존 오탐 정정]'
MANUAL_CORRECTION_NOTE = '(정규식 1단계가 제3자 언급을 오추출한 것을 사용자가 원문 대조로 직접 교정함 — 이 문장은 자동 추출된 것이 아니라 교정 근거를 남기기 위한 메모임)'

# 정규식으로는 "진짜 고유명사인가"를 판별할 수 없어서, 실제로 미해결
# 목록에서 반복 관찰된 일반명사를 화이트리스트 방식으로 걸러낸다
# (완벽한 해법은 아니라는 점을 위 모듈 docstring에 명시했다).
GENERIC_NOUN_STOPWORDS = {
    '여자', '여인', '사람', '가족', '친구', '족속', '지파', '왕', '조상', '후손', '자손',
    '예언자', '유대인', '그리스도', '대왕', '계통', '아들', '딸', '사이', '가문', '형제',
    '자매', '남편', '아내', '어머니', '아버지', '손자', '손녀',
    # [2026-08-19 재개선] 274건 잔여 미해결 목록을 실제로 훑어 추가 확인한
    # 대명사/부정관형사/역할명사 — 절대 고유명사일 수 없는 것들만 추가했다.
    '그의', '다른', '대신에', '마지막', '문지기',
    # [2026-08-19 신설, 동의어 확장] "자신의 여동생을 ..." 같은 재귀대명사
    # 문장에서 "여동생" 패턴을 새로 추가하며 "자신"이 대상으로 잘못 캡처되는
    # 것을 실측으로 확인해 추가(다브네스 사례). 재귀대명사는 절대 고유명사일
    # 수 없다.
    '자신',
    # [2026-08-20 신설, 동역자 패턴 추가] 우르바노(2759) "복음의 동역자,
    # 성도." 문장에서 "복음"이 대상으로 잘못 캡처되는 것을 co_worker_of
    # 패턴 신설 시 실측으로 확인해 추가(같은 항목의 "바울의 동역자로 수고함"은
    # 별도로 정상 추출되므로 이 필터를 추가해도 정보 손실 없음).
    '복음',
}
TRAILING_PARTICLES = ('으로', '의', '이', '가', '은', '는', '을', '를', '과', '와', '도', '만')

NOISE_SUFFIX_RE = re.compile(r'(한|된|할|될|는|은|던|힌|운|낸)$')
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
    # [2026-08-21 신설] 위 SENSE_SPLIT_RE 완화로 "번호 없는 암묵적 1번 문장 +
    # 2.부터 시작하는 명시적 sense" 패턴(예: 가이오=52 "마게도냐 사람. 바울의
    # 동역자. 2. 더베 사람. 3. ...")이 새로 걸리게 됐다. `re.split`은 첫
    # 매치 이전 텍스트를 parts[0]에 담는데, 기존 코드는 i=1부터 순회해
    # parts[0]을 아예 안 읽었다 — "1."로 시작하는 기존 정상 케이스는 parts[0]가
    # 항상 빈 문자열이라 문제가 없었지만, 이번에 새로 걸리는 "암묵적 1번" 케이스는
    # parts[0]에 실제 문장(예: "바울의 동역자")이 들어있어 그냥 버리면 그 문장이
    # 통째로 추출 대상에서 사라진다(정보 손실 회귀). 그래서 parts[0]가
    # 비어있지 않으면 별도 sense로 보존한다 — 번호는 다음에 나오는 명시적
    # 번호보다 하나 작은 값(자연스러운 추정, 2.부터 시작하면 1로 추정)을 쓰되,
    # 다음 번호가 1 이하인 비정상 케이스에 대비해 최소 1로 방어한다.
    preamble = parts[0].strip()
    if preamble:
        next_num = int(parts[1]) if len(parts) > 1 else 2
        senses.append((max(1, next_num - 1), preamble))
    i = 1
    while i < len(parts) - 1:
        num_str, content = parts[i], parts[i + 1]
        content = content.strip()
        if content:
            senses.append((int(num_str), content))
        i += 2
    return senses


def strip_trailing_particle(word):
    """캡처된 대상 끝에 조사 하나가 남아있으면 떼어낸다(예: '왕이' -> '왕',
    '이스라엘의' -> '이스라엘'). 표제어 대조에 실패했을 때의 구제책으로만
    쓴다 — 무조건 잘라내면 조사처럼 끝나는 진짜 짧은 이름을 훼손할 수
    있어서다."""
    for p in TRAILING_PARTICLES:
        if word.endswith(p) and len(word) > len(p):
            return word[: -len(p)]
    return word


def is_stopword_target(target):
    if target in GENERIC_NOUN_STOPWORDS:
        return True
    stripped = strip_trailing_particle(target)
    return stripped != target and stripped in GENERIC_NOUN_STOPWORDS


def is_probable_noise(target, relation_type):
    if relation_type not in LOOSE_PATTERNS:
        return False
    if target in KOREAN_NUMERALS:
        return True
    if NOISE_SUFFIX_RE.search(target):
        return True
    return False


# [2026-09-16 신설] 사용자 요청 — "PersonSeed.json의 관계(할아버지~손녀)와
# 기타관계 데이터에 앞에 인덱스 숫자를 붙이는 것에 대해서 어떠한지?" 동명이인이
# 있는 이름을 가족관계/기타관계에 적을 때 "이름#idx"(예: "노아#384")로 적으면
# 어느 Persons.idx를 가리키는지 추측 없이 100% 확정할 수 있게 하는 표기법이다.
# 구분자는 "#"(사용자 확정) — 실제 데이터 검사 결과 "70명의 아들"/"12사도"처럼
# 숫자로 시작하는 기존 서술형 값이 있어(구분자 없는 순수 접두 숫자 방식은 이런
# 값을 오인식함) 콜론/하이픈 등 후보 중 "#"을 골랐다(PersonSeed.json 전체에
# "#" 문자가 기존에 전혀 안 쓰이고 있음을 확인함). [2026-09-16, 사용자 결정]
# "앞으로 입력/수정할 때만" 지원 — 기존 3,068건 데이터에 소급 일괄 적용은
# 하지 않는다. 태그가 없는 기존 값은 지금처럼 이름 그대로 처리된다(하위 호환,
# 동작 변화 없음).
IDX_TAG_RE = re.compile(r"^(.*)#(\d+)$")
# [2026-09-26 추가] 사용자가 PersonSeed.json을 재정리하면서 가족관계 필드에도
# "이름#idx(설명)" 형식(예: "야고보#4057(사도)", "리노#770(전승)")을 쓰기
# 시작했다 — 위 IDX_TAG_RE는 "#idx"가 문자열 "끝"이어야 매치되므로 뒤에
# "(설명)"이 붙으면 통째로 매치 실패해 idx를 못 뽑고, `resolve_target_kind`가
# "야고보#4057(사도)"라는 문자열 그대로를 이름처럼 취급해 어떤 인물과도
# 매칭되지 않는 채로 PersonRelations.target_word에 그 원문이 그대로 들어가는
# 버그가 있었다(전수 스캔 결과 61건 확인). "#idx" 뒤에 괄호 설명이 붙는
# 경우도 추가로 매치하는 관대한 정규식을 하나 더 두고, 있으면 그쪽으로
# 폴백한다 — 괄호 안 내용은 자유 서술(사도/양자/전승/왕조 대응 등 고정
# 어휘가 아님)이라 relation_type 판정에는 쓸 수 없어 그대로 버린다(현재는
# 화면에도 노출되지 않는다 — 필요하면 별도 컬럼으로 보존하는 건 후속 논의).
IDX_TAG_WITH_NOTE_RE = re.compile(r"^(.*)#(\d+)\([^()]*\)$")


def parse_idx_tag(raw):
    """`raw`(가족관계/기타관계 원문 항목 하나)에서 "#idx" 태그를 분리한다.
    태그가 있으면 (표시용 이름, idx 문자열)을, 없으면 (raw 그대로, "")를
    돌려준다 — 태그 없는 값은 100% 기존과 동일하게 동작한다. "#idx(설명)"
    형식(위 `IDX_TAG_WITH_NOTE_RE` 참고)도 idx는 그대로 인정하고 괄호 설명만
    버린다."""
    m = IDX_TAG_RE.match(raw)
    if not m:
        m = IDX_TAG_WITH_NOTE_RE.match(raw)
    if not m:
        return raw, ""
    name = m.group(1).strip()
    idx = m.group(2)
    if not name:
        return raw, ""
    return name, idx


def resolve_target_kind(target, known_person_words, known_place_words):
    """대상 이름을 표제어 집합과 대조한다. 원문 그대로 먼저 확인하고,
    실패하면 조사 하나를 떼어낸 형태로 한 번 더 확인한다(느슨한
    패턴이 조사까지 캡처해버린 잔여 사례를 구제하기 위함). 조사를
    뗀 형태로 찾은 경우 대상 표기 자체도 그 형태로 정규화해서
    돌려준다."""
    if target in known_person_words:
        return target, 'person'
    if target in known_place_words:
        return target, 'place'
    stripped = strip_trailing_particle(target)
    if stripped != target:
        if stripped in known_person_words:
            return stripped, 'person'
        if stripped in known_place_words:
            return stripped, 'place'
    return target, None


# [2026-08-20 신설] "OO의 아버지이다(압살롬, 암논 등)"처럼 이름이 두 개
# 이상 병기된 문장에서, 정규식 그룹 하나로는 첫 번째 이름만 잡히고 괄호
# 속 나머지는 그동안 버려졌다. 실측 확인(전수 94건 중 37건이 괄호 안에
# 실제 Persons/Places 표제어를 포함 — 예: 다윗 "솔로몬의 아버지이다(압살롬,
# 암논 등)"에서 압살롬·암논 누락, 아브라함 "이스마엘의 아버지이다(이삭
# 등)"에서 이삭 누락). 괄호 안 토큰을 쉼표로 나눠 known_person_words/
# known_place_words와 "정확히" 일치할 때만(조사 제거 구제까지 포함,
# resolve_target_kind 재사용) 같은 relation_type으로 추가한다 — 일치하지
# 않는 토큰("제3대", "건립자", "1세", "아들 디모데" 등)은 이름이 아니거나
# 이름 앞에 다른 말이 붙어 있어 조용히 버려진다(성별·관계를 추론하는 게
# 아니라 원문에 이미 명시된 사실만 옮기는 것 — 나머지 57건과 미해결
# 잔여분은 "추측 금지" 원칙상 이번 개선 범위 밖으로 남겨 둔다).
#
# king_of는 이 집합에서 제외했다 — 실측 중 반례를 하나 발견함: 하무달
# "두 명의 유다 왕(여호아하스, 시드기야)을 낳은 어머니"에서 "유다 왕"이
# king_of로 매치되고 그 직후 괄호가 "(여호아하스, 시드기야)"라, 이 로직을
# 적용하면 "하무달은 여호아하스/시드기야의 왕"이라는 틀린 관계가 생긴다
# (실제로는 그 둘의 어머니 — mother_of 쪽에서 이미 별도로 정확히 잡힘).
# father_of/mother_of의 괄호는 항상 "같은 사람이 낳은 다른 자녀"를 가리켜
# 안전했지만, king_of의 괄호는 "그 왕이 누구를 낳았는지" 등 문법적으로 전혀
# 다른 역할로도 쓰여서 일반화할 수 없다고 판단했다. teacher_of/
# grandfather_of는 실제 코퍼스에 괄호-부기 사례가 0건이라(실행 확인) 이번
# 개선의 실익이 없어 범위에서 뺐다 — 나중에 실제 사례가 생기면 그때
# king_of와 같은 기준으로 개별 검토한다.
PARENTHETICAL_MULTI_TARGET_TYPES = {'father_of', 'mother_of'}
TRAILING_PAREN_RE = re.compile(r'^\s*(?:이었다|이다|이며|였다)?\s*\(([^)]*)\)')


def extract_parenthetical_targets(sentence, match_end, relation_type, primary_target, word, known_person_words, known_place_words):
    """`match_end`(주 대상을 캡처한 패턴의 끝 위치) 바로 다음에 괄호가
    이어지면, 그 안의 이름을 쉼표로 나눠 실제 표제어와 일치하는 것만
    추가 대상으로 돌려준다. 일치하지 않으면 빈 리스트."""
    if relation_type not in PARENTHETICAL_MULTI_TARGET_TYPES:
        return []
    paren_match = TRAILING_PAREN_RE.match(sentence[match_end:])
    if not paren_match:
        return []
    extras = []
    for tok in re.split(r'[,、]', paren_match.group(1)):
        tok = re.sub(r'등\s*$', '', tok.strip()).strip()
        if not tok or tok == word or tok == primary_target:
            continue
        extra_target, extra_kind = resolve_target_kind(tok, known_person_words, known_place_words)
        if extra_kind is None or extra_target == primary_target:
            continue
        extras.append((extra_target, extra_kind))
    return extras


# [2026-08-20 신설, 사용자 수기 검토로 발견] "OO의 아버지이다(XX, YY)"(위
# `PARENTHETICAL_MULTI_TARGET_TYPES`)와 반대 방향 — "요셉, 베냐민의
# 어머니이다."처럼 이름을 쉼표로 나열한 뒤 마지막 이름에만 "의 아버지/
# 어머니"가 붙는 문장. 정규식 그룹 하나는 쉼표 바로 앞 이름(베냐민)만
# 잡고, 그 앞에 나열된 이름(요셉)은 그동안 버려졌다 — 실측 사례: 라헬
# "요셉, 베냐민의 어머니이다."에서 요셉 누락(수기 교정 전엔 "요셉의
# 어머니이다(베냐민)."이라 위 괄호 병기 추출로 잡혔었는데, 문장 구조가
# 바뀌면서 새로 생긴 구멍). 매치 시작 위치 바로 앞이 문장 경계(문단 시작
# 또는 "~다. ")로 시작하는 쉼표-나열이면 각 이름을 같은 relation_type으로
# 추가한다 — 문장 중간에서 아무 데나 쉼표로 끊긴 구절을 잘못 끌어오는
# 걸 막기 위해 경계 조건을 걸었다. father_of/mother_of만 대상으로 한
# 이유는 위 괄호 병기 확장과 동일(king_of 등은 개별 검토 필요).
LEADING_LIST_TYPES = {'father_of', 'mother_of'}
LEADING_LIST_RE = re.compile(r'(?:^|다\.\s*|^\s*|[.]\s*)((?:[가-힣]{2,6}\s*,\s*)+)$')


def extract_leading_list_targets(sentence, match_start, relation_type, primary_target, word, known_person_words, known_place_words):
    """`match_start`(주 대상을 캡처한 패턴의 시작 위치) 바로 앞이 문장 경계로
    시작하는 쉼표-나열이면, 나열된 이름 중 실제 표제어와 일치하는 것만
    추가 대상으로 돌려준다. 일치하지 않으면 빈 리스트."""
    if relation_type not in LEADING_LIST_TYPES:
        return []
    preceding = sentence[:match_start]
    list_match = LEADING_LIST_RE.search(preceding)
    if not list_match:
        return []
    extras = []
    for tok in re.split(r'[,、]', list_match.group(1)):
        tok = tok.strip()
        if not tok or tok == word or tok == primary_target:
            continue
        extra_target, extra_kind = resolve_target_kind(tok, known_person_words, known_place_words)
        if extra_kind is None or extra_target == primary_target:
            continue
        extras.append((extra_target, extra_kind))
    return extras


def extract_relations_from_sense(
    word, idx, sense_index, sentence, known_person_words, known_place_words, person_idx_by_word=None
):
    person_idx_by_word = person_idx_by_word or {}
    found = []
    matched_spans = []
    for m in JOINT_PARENT_RE.finditer(sentence):
        parent1, parent2, child_kind = m.group(1), m.group(2), m.group(3)
        relation_type = 'son_of' if child_kind == '아들' else 'daughter_of'
        label = '~와 ~ 사이의 아들/딸 [2026-08-19 신설]'
        for parent in (parent1, parent2):
            if parent == word or is_stopword_target(parent):
                continue
            target, target_kind = resolve_target_kind(parent, known_person_words, known_place_words)
            found.append((word, idx, sense_index, relation_type, label, target, target_kind, sentence))
        matched_spans.append(m.span())

    # [2026-08-20 신설] SUBJECT_FIRST_PARENT_RE — 그 정의부 주석 참고. 방향이
    # 반대라 found 튜플의 word/idx 자리에 "표제어"가 아니라 "캡처된 부모
    # 이름"을 넣는다. source_idx는 이 함수가 원래 표제어의 idx만 받으므로
    # 부모 자신의 idx를 알아내려면 별도로 person_idx_by_word를 조회해야
    # 한다(동명이인이 여러 idx를 가지면 사전 순서상 첫 번째를 쓴다 — 이
    # 필드는 앱(Swift) 쪽에서 전혀 읽지 않고 Python 빌드 파이프라인 내부
    # 참고용일 뿐이라, 여러 idx 중 어느 걸 골라도 기능에 영향 없음). 못 찾으면
    # 표제어 자신의 idx로 대체한다(완전히 정확친 않지만 다른 컬럼이 이 값을
    # 신뢰해 조회하는 곳이 없어 안전한 폴백).
    for m in SUBJECT_FIRST_PARENT_RE.finditer(sentence):
        parent, role = m.group(1), m.group(2)
        relation_type = 'father_of' if role == '아버지' else 'mother_of'
        label = '~가 아버지/어머니이다(주어-선행 어순, entry가 X의 자녀) [2026-08-20 신설]'
        if parent == word or is_stopword_target(parent):
            matched_spans.append(m.span())
            continue
        parent_idx = person_idx_by_word.get(parent, [idx])[0]
        # target(자녀 = 표제어 자신)은 항상 인명이다 — 이 함수가 인명(persons)만
        # 대상으로 호출되기 때문(build_person_place_tables 참고).
        found.append((parent, parent_idx, sense_index, relation_type, label, word, 'person', sentence))
        matched_spans.append(m.span())

    def overlaps_special_case(span):
        return any(a < span[1] and span[0] < b for a, b in matched_spans)

    for pattern, relation_type, label in RELATION_PATTERNS:
        for m in re.finditer(pattern, sentence):
            if overlaps_special_case(m.span()):
                continue  # 이미 위 JOINT_PARENT_RE/SUBJECT_FIRST_PARENT_RE가 처리한 구간은 중복 추출하지 않는다
            target = m.group(1)
            if target == word or is_probable_noise(target, relation_type) or is_stopword_target(target):
                continue
            target, target_kind = resolve_target_kind(target, known_person_words, known_place_words)
            found.append((word, idx, sense_index, relation_type, label, target, target_kind, sentence))
            for extra_target, extra_kind in extract_parenthetical_targets(
                sentence, m.end(), relation_type, target, word, known_person_words, known_place_words
            ):
                found.append((
                    word, idx, sense_index, relation_type,
                    label + ' [괄호 병기, 2026-08-20 신설]', extra_target, extra_kind, sentence,
                ))
            for extra_target, extra_kind in extract_leading_list_targets(
                sentence, m.start(), relation_type, target, word, known_person_words, known_place_words
            ):
                found.append((
                    word, idx, sense_index, relation_type,
                    label + ' [쉼표 나열, 2026-08-20 신설]', extra_target, extra_kind, sentence,
                ))
    return found


# [2026-08-21 신설] 사용자 요청 2번 — "Persons의 테이블에서 description은
# 필요없을 것 같음. 다만 relation_person에 Persons의 idx값을 구분자로
# 구분하여 넣어주면 추후에 데이터로 활용될 수 있지 않을까?" "단순 idx
# 나열임. ~와 관련이 있음 의 데이터에는 관계 유형이 따로 있지 않음."(사용자
# 확인) — relation_type 없이 idx만 쉼표로 나열한다(Persons.verses_str의
# ",".join 관례와 동일).
#
# remark에서 뽑는다(description이 아니라) — 사용자가 지금 description을
# 손보면서 "~와 관련이 있다" 절을 빼고 있는 반면 remark는 원문을 그대로
# 보존하므로(위 person_rows 주석 참고), remark 쪽이 이 추출에 더 안정적이다.
#
# [2026-08-21 실측, 보수적 정확 일치만 허용하는 근거] 927명(현재 1,685명)분
# remark 전체에 이 패턴을 돌려 본 결과:
#   - 총 언급 1,069건 중 851건(80%)이 Persons.word와 정확히 일치해 연결된다.
#   - 나머지 218건은 두 갈래다. (1) 179건은 이 시드에 그 이름의 Persons
#     항목 자체가 없다(예: 느헤미야 39건, 예수님 26건, 에스더 13건, 그리스도
#     10건, 다니엘 7건, 이사야 7건, 빌립 5건, 요압 5건 등 — 주요 인물인데도
#     항목이 없는 경우가 섞여 있어 원본 데이터 공백으로 사용자에게 별도
#     보고함). (2) 39건은 Persons.word 안에 부분 문자열로만 들어 있다(예:
#     "베드로"는 실제론 "시몬 베드로"로만 존재, "빌라도"는 "본디오 빌라도"로만
#     존재) — 이 경우 부분 일치를 허용해 자동으로 연결하면 오히려 위험하다.
#     실측 중 "셀라"가(실제로는 별개 인물) 그저 글자가 겹친다는 이유로
#     "므두셀라"에 잘못 연결되는 사례, "아사"가 "바아사"/"아사렐라"/"아사헬"
#     중 어느 쪽인지 알 수 없는 사례를 직접 확인했다 — "추측 금지" 원칙에
#     따라 정확 일치(exact match)만 연결하고 나머지는 그냥 비워 둔다(idx
#     목록이 비면 relation_person도 빈 문자열).
RELATION_PERSON_MENTION_RE = re.compile(
    r'([가-힣]{2,6}(?:\s*[,、]\s*[가-힣]{2,6})*)\s*(?:과|와)\s*관련이\s*있다'
)


def extract_relation_person_idxs(remark, person_idx_by_word):
    if not remark:
        return ""
    linked_idxs = []
    for m in RELATION_PERSON_MENTION_RE.finditer(remark):
        for name in re.split(r'[,、]', m.group(1)):
            name = name.strip()
            if not name:
                continue
            idxs = person_idx_by_word.get(name)
            if not idxs:
                continue
            # 동명이인이면 person_idx_by_word와 같은 관례로 첫 번째 idx를 쓴다
            # (source_idx 선택과 동일한 근거 — 위 person_idx_by_word 주석 참고).
            first_idx = idxs[0]
            if first_idx not in linked_idxs:
                linked_idxs.append(first_idx)
    return ",".join(linked_idxs)


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
    # [2026-08-20 신설] SUBJECT_FIRST_PARENT_RE(주어-선행 어순 부모 관계)가 캡처한
    # "부모 이름"의 idx를 찾기 위한 역인덱스. 동명이인이면 여러 idx가 쌓이는데,
    # source_idx는 Swift 쪽에서 전혀 읽지 않는 필드라(extract_relations_from_sense
    # 정의부 주석 참고) 어느 idx를 골라도 기능에 영향이 없다 — 등장 순서상 첫
    # 번째를 쓴다.
    person_idx_by_word = {}
    for e in persons:
        person_idx_by_word.setdefault(e["word"], []).append(e["idx"])

    def verses_str(verse_list):
        resolved = [resolve_single_verse(v, abbr_index) for v in verse_list]
        resolved = [r for r in resolved if r is not None]
        return ",".join(f"{b}:{c}:{v}" for b, c, v in resolved)

    # [2026-08-20 신설, 사용자 요청] description은 관계 추출(정규식) 등 데이터
    # 분석 전용으로 남기고, 화면에 사람이 읽을 원문은 별도 remark 컬럼에
    # 둔다 — 사용자가 description을 수기로 간결하게 다듬으면서(정규식이
    # 잘못 붙잡던 문장 정리) 화면 표시용 서술 문장이 줄어드는 부작용이
    # 있었는데, remark에 수기 편집 이전 원문을 그대로 보존해 화면에는 그걸
    # 보여준다. remark가 없는 시드 항목(과거 포맷과의 호환)은 description을
    # 그대로 폴백으로 쓴다.
    # [2026-08-21 수정] description 자체는 더 이상 Persons/Places 테이블
    # 컬럼으로 내보내지 않는다(위 CREATE TABLE 주석 참고) — 이 로컬 변수의
    # description 읽기는 remark 폴백 계산에만 남아 있고, 튜플에는 담기지
    # 않는다. relation_person(Persons만)은 위 extract_relation_person_idxs
    # 참고.
    # [2026-09-15 변경] Persons는 더 이상 여기서 만들지 않는다 — PersonSeed.json
    # 단일 소스로 build_persons_from_person_seed()가 전담한다(사용자 확정:
    # "PersonSeed.json 데이터가 정확하니 Persons 테이블을 다 비우고 다시
    # PersonSeed.json 데이터로 채울 것"). Places는 기존 그대로 여기서 만든다
    # (이번 라운드 범위 밖 — 사용자 확정 "장소는 아직 준비중").
    place_rows = [
        (
            e["idx"], e["word"],
            e.get("remark", "") or e.get("description", "") or "",
            verses_str(e.get("verses", [])),
        )
        for e in places
    ]
    cur.executemany(
        "INSERT INTO Places (idx, word, remark, verses) VALUES (?, ?, ?, ?)", place_rows
    )
    print("Places 삽입:", len(place_rows), "(Persons는 build_persons_from_person_seed()에서 별도 삽입)")

    # 관계 추출(아래)에서 쓸 known_person_words/known_place_words는 원본 JSON
    # 리스트가 아니라 실제로 삽입된(될) 테이블 기준으로 다시 계산한다 — "함"
    # 오매칭(4차 문서 §4)과 같은 부류의 문제를 정규식 추출 쪽에서도 막기 위함.
    # Persons는 이 함수 실행 시점에 아직 비어 있을 수 있으므로, 호출부
    # (main())가 build_persons_from_person_seed()를 먼저 실행한 뒤 이 함수를
    # 불러야 한다 — 그래야 아래 조회가 최신 Persons를 반영한다.
    known_person_words = {row[0] for row in cur.execute("SELECT DISTINCT word FROM Persons").fetchall()} or known_person_words
    known_place_words = {row[0] for row in cur.execute("SELECT DISTINCT word FROM Places").fetchall()} or known_place_words

    relation_rows = []
    empty_description_count = 0
    unmatched_sentences = []  # [2026-08-19 신설] 2단계(AI 보조 추출) 입력으로 내보낼 목록
    for e in persons:
        description = e.get("description", "") or ""
        if not description.strip():
            empty_description_count += 1
            continue
        for sense_index, sentence in split_senses(description):
            relations = extract_relations_from_sense(
                e["word"], e["idx"], sense_index, sentence, known_person_words, known_place_words,
                person_idx_by_word=person_idx_by_word,
            )
            if not relations:
                unmatched_sentences.append({
                    "source_word": e["word"], "source_idx": e["idx"],
                    "sense_index": sense_index, "sentence": sentence,
                })
                continue
            relation_rows.extend(relations)

    # [2026-08-19 신설] 잔존 오탐 11건 수기 교정 — REMOVE: 정규식이 잘못 뽑은
    # (source_word, relation_type, target_word) 삼중항과 정확히 일치하는 행을
    # regex 결과에서 제거한다(사용자가 원문 대조로 확인해 준 11건, 위
    # MANUAL_RELATION_REMOVE 정의부 주석 참고).
    remove_set = set(MANUAL_RELATION_REMOVE)
    before_remove = len(relation_rows)
    relation_rows = [r for r in relation_rows if (r[0], r[3], r[5]) not in remove_set]
    manual_removed = before_remove - len(relation_rows)

    # [2026-09-15 신설] Persons에서 빠진 legacy 표제어(PersonSeed.json에
    # 없어 흡수된 11건)를 source로 하는 관계 행을, 흡수한 정식 표제어의
    # idx/word로 재귀속한다 — dangling source_idx(존재하지 않는 Persons.idx를
    # 가리키는 행)를 만들지 않으면서도 정보를 버리지 않는다. 대응하는 표제어가
    # 없는 나머지("겔")는 그 행만 드롭한다(실행 확인 — 1건, tribe_of 유다).
    LEGACY_WORD_REMAP = {
        "고니야": "여호야긴", "디두모": "도마", "맛다니야": "시드기야", "사래": "사라",
        "아브람": "아브라함", "아사랴": None,  # 아사랴는 여러 명(아벳느고/웃시야 등)과 겹쳐 자동 재귀속 보류
        "여고냐": "여호야긴", "여디디야": "솔로몬", "여룹바알": "기드온",
        "이스라엘": "야곱", "임마누엘": "예수", "겔": None,
    }
    canonical_idx_by_word = {}
    for canon_word in set(v for v in LEGACY_WORD_REMAP.values() if v):
        rows = cur.execute("SELECT idx FROM Persons WHERE word=?", (canon_word,)).fetchall()
        if len(rows) == 1:
            canonical_idx_by_word[canon_word] = rows[0][0]
        # 동명이인으로 후보가 여럿이면 자동 재귀속하지 않는다(오귀속 위험) —
        # 아래 루프에서 canonical_idx_by_word에 없으면 그 행은 드롭된다.

    remapped_count = 0
    dropped_count = 0
    final_relation_rows = []
    for r in relation_rows:
        source_word = r[0]
        if source_word in LEGACY_WORD_REMAP:
            canon = LEGACY_WORD_REMAP[source_word]
            canon_idx = canonical_idx_by_word.get(canon) if canon else None
            if canon_idx is None:
                dropped_count += 1
                continue
            r = (canon, canon_idx) + r[2:]
            remapped_count += 1
        final_relation_rows.append(r)
    relation_rows = final_relation_rows
    if remapped_count or dropped_count:
        print(f"  (legacy 표제어 관계 행 재귀속 {remapped_count}건, 대응 표제어 없어 드롭 {dropped_count}건)")

    cur.executemany(
        "INSERT INTO PersonRelations "
        "(source_word, source_idx, sense_index, relation_type, pattern_label, target_word, target_kind, "
        "raw_sentence, target_idx, extraction_method) VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', 'regex')",
        relation_rows,
    )
    resolved_count = sum(1 for r in relation_rows if r[6] is not None)
    print(
        f"PersonRelations(1단계/정규식) 삽입: {len(relation_rows)}건 "
        f"(해결됨 {resolved_count} / 미해결 {len(relation_rows) - resolved_count}) — "
        f"수기 교정으로 제거된 오탐 {manual_removed}건 — "
        f"description 빈 항목 {empty_description_count}건, 패턴 미매치 문장 {len(unmatched_sentences)}건"
    )

    with open(UNMATCHED_SENTENCES_PATH, "w", encoding="utf-8") as f:
        json.dump(unmatched_sentences, f, ensure_ascii=False, indent=1)
    print(f"패턴 미매치 문장 {len(unmatched_sentences)}건 -> {UNMATCHED_SENTENCES_PATH} 로 내보냄"
          f"(AIRelationExtractor 입력용)")

    # [2026-08-19 신설] 잔존 오탐 11건 수기 교정 — ADD: 사용자가 확인해 준 올바른
    # 관계를 추가한다. source_idx는 Persons에서 표제어로 조회한다(동명이인으로
    # 같은 표제어가 여러 idx를 가질 수 있는데, 여기 등장하는 9개 이름은 전부
    # "완성본" 사전에서 정확히 1개 idx만 가지고 있음을 실행 확인함 — 여러 개일
    # 경우 첫 번째를 쓰고 경고를 남긴다).
    word_to_idx = {}
    for e in persons:
        word_to_idx.setdefault(e["word"], []).append(e["idx"])

    # [2026-08-19 신설, 동의어 확장] regex_dedup_keys: 정규식 1단계(동의어 확장
    # 포함)가 이미 뽑아낸 (source_word, relation_type, target_word)와 정확히
    # 겹치는 수기 교정 항목은 중복 삽입하지 않는다 — 예: "딤나 sister_of 로단"은
    # 원래 정규식이 못 잡아 수기로 추가했었는데, 이번에 "누이" 동의어를 추가하며
    # 정규식이 스스로 잡아내게 됐다(딤나: "로단의 누이." 문장). 이런 경우 수기
    # 항목을 또 넣으면 완전히 같은 사실이 두 줄로 중복된다.
    regex_dedup_keys = {(r[0], r[3], r[5]) for r in relation_rows}

    manual_add_rows = []
    manual_add_skipped = 0
    manual_add_dedup_skipped = 0
    for source_word, relation_type, target in MANUAL_RELATION_ADD:
        target_word_probe, _ = resolve_target_kind(target, known_person_words, known_place_words)
        if (source_word, relation_type, target_word_probe) in regex_dedup_keys:
            print(f"  (정규식이 이미 동일 관계를 추출해 수기 항목 스킵: "
                  f"{source_word} {relation_type} {target_word_probe})")
            manual_add_dedup_skipped += 1
            continue
        idxs = word_to_idx.get(source_word)
        if not idxs:
            print(f"  ⚠ 수기 교정 추가 스킵 — '{source_word}'가 Persons 표제어에 없음: "
                  f"{source_word} {relation_type} {target}")
            manual_add_skipped += 1
            continue
        if len(idxs) > 1:
            print(f"  ⚠ '{source_word}'가 동명이인으로 {len(idxs)}건 존재 — 첫 idx({idxs[0]}) 사용")
        target_word, target_kind = resolve_target_kind(target, known_person_words, known_place_words)
        manual_add_rows.append((
            source_word, idxs[0], 0, relation_type, MANUAL_CORRECTION_LABEL,
            target_word, target_kind, MANUAL_CORRECTION_NOTE,
        ))
    cur.executemany(
        "INSERT INTO PersonRelations "
        "(source_word, source_idx, sense_index, relation_type, pattern_label, target_word, target_kind, "
        "raw_sentence, target_idx, extraction_method) VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', 'manual')",
        manual_add_rows,
    )
    manual_add_resolved = sum(1 for r in manual_add_rows if r[6] is not None)
    print(
        f"PersonRelations(수기 교정) 추가: {len(manual_add_rows)}건(해결됨 {manual_add_resolved}) — "
        f"제거 {manual_removed}건, 스킵 {manual_add_skipped}건, 정규식과 중복이라 스킵 {manual_add_dedup_skipped}건"
    )

    # [2026-08-19 신설] 2단계 — AIExtractedRelations.json이 있으면(사용자가
    # 실제 Apple Intelligence 기기에서 AIRelationExtractor(Swift, FoundationModels)를
    # 돌려 만든 결과물) 읽어 병합한다. 없으면 그냥 건너뛴다(필수 아님, 1단계만으로도
    # 정상 빌드된다). 같은 (source_word, source_idx, sense_index)에 대해 정규식이
    # 이미 뽑아낸 것과 정확히 동일한 (relation_type, target_word) 조합은 중복
    # 삽입하지 않는다 — AI가 "같은 문장에서 정규식과 동일한 관계"를 다시 찾아낸
    # 경우까지 겹쳐 넣을 필요는 없어서다(다만 다른 relation_type/target을 새로
    # 찾아낸 경우는 그대로 추가한다).
    ai_inserted = 0
    ai_skipped_duplicate = 0
    ai_skipped_unmatched_key = 0
    if os.path.exists(AI_EXTRACTED_RELATIONS_PATH):
        with open(AI_EXTRACTED_RELATIONS_PATH, encoding="utf-8") as f:
            ai_raw = json.load(f)

        # 정규식 결과와 중복 판정용 키 집합
        regex_keys = {(r[0], r[1], r[2], r[3], r[5]) for r in relation_rows}
        # AIRelationExtractor는 UnmatchedRelationSentences.json에 있던 문장만
        # 처리했어야 한다 — 그 목록에 없는 (source_word, source_idx, sense_index)가
        # 섞여 들어오면(예: 오래된 결과 파일을 재사용) 조용히 건너뛰고 카운트만 한다.
        valid_keys = {(u["source_word"], u["source_idx"], u["sense_index"]) for u in unmatched_sentences}

        ai_rows = []
        for item in ai_raw:
            key3 = (item.get("source_word"), item.get("source_idx"), item.get("sense_index"))
            if key3 not in valid_keys:
                ai_skipped_unmatched_key += 1
                continue
            target = (item.get("target_word") or "").strip()
            relation_type = item.get("relation_type")
            if not target or not relation_type or relation_type == "none":
                continue  # AI가 "이 문장엔 관계 없음"으로 답한 경우
            dedup_key = (item["source_word"], item["source_idx"], item["sense_index"], relation_type, target)
            if dedup_key in regex_keys:
                ai_skipped_duplicate += 1
                continue
            target_word, target_kind = resolve_target_kind(target, known_person_words, known_place_words)
            label = f"~ [AI 보조 추출, FoundationModels — {item.get('model_version', '버전 미기록')}]"
            ai_rows.append((
                item["source_word"], item["source_idx"], item["sense_index"], relation_type, label,
                target_word, target_kind, item.get("raw_sentence", ""),
            ))
            regex_keys.add(dedup_key)

        cur.executemany(
            "INSERT INTO PersonRelations "
            "(source_word, source_idx, sense_index, relation_type, pattern_label, target_word, target_kind, "
            "raw_sentence, target_idx, extraction_method) VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', 'ai')",
            ai_rows,
        )
        ai_inserted = len(ai_rows)
        ai_resolved = sum(1 for r in ai_rows if r[6] is not None)
        print(
            f"PersonRelations(2단계/AI) 삽입: {ai_inserted}건(해결됨 {ai_resolved}) — "
            f"중복 제외 {ai_skipped_duplicate}건, 대상 문장 불일치로 제외 {ai_skipped_unmatched_key}건"
        )
    else:
        print(f"({AI_EXTRACTED_RELATIONS_PATH} 없음 — 2단계 AI 보조 추출 결과 미병합, 1단계만 반영됨)")


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


# === PersonSeed.json 보강 (2026-09-15 신설) ===
# 기존 build_person_place_tables()의 정규식 관계추출은 손대지 않는다 — 이
# 함수는 그 뒤에 순수 추가(UPDATE 또는 신규 INSERT)만 한다.
def build_persons_from_person_seed(cur, abbr_index):
    """[2026-09-15 신설, 이전 enrich_persons_from_seed() 대체] 사용자 확정 —
    "PersonSeed.json 데이터가 정확하니 Persons 테이블을 다 비우고 다시
    PersonSeed.json 데이터로 채울 것". PersonPlaceSeed.json 기반 Persons
    INSERT는 build_person_place_tables()에서 완전히 제거했다(Places만 거기서
    유지) — Persons는 이제 이 함수 하나가 전담한다. 3,067건 전부를 UPDATE/
    INSERT 구분 없이 그대로 삽입한다."""
    if not os.path.exists(PERSON_SEED_PATH):
        print(f"({PERSON_SEED_PATH} 없음 — Persons 테이블을 채울 수 없음, 중단)")
        raise SystemExit(1)

    with open(PERSON_SEED_PATH, encoding="utf-8") as f:
        seed_entries = json.load(f)

    # [2026-10-01 변경] 범위("마 26:14-16")를 절 단위로 풀어 등록한다(`expand_verse_list` 참고).
    verse_warnings = []
    labeled_targets = []

    def verses_str(verse_list, label=""):
        result = expand_verse_list(verse_list, abbr_index, verse_warnings, label)
        labeled_targets.append((label, result))
        return result

    def seed_relation_names(rel, field):
        """[2026-09-16 신설] `rel`(관계 딕셔너리 하나)에서 `field`(할아버지·
        할머니·아버지·어머니·배우자·아들·딸·손자·손녀 중 하나) 값을 콤마
        구분 문자열로 정규화한다 — 원본이 단일 문자열이든 리스트든 결과는
        항상 "이름,이름" 형태(값이 없으면 빈 문자열)다. 이름 자체는 원본
        그대로 옮긴다(괄호 주석 등 어떤 가공도 하지 않음 — 추측 금지 원칙,
        위 CREATE TABLE 주석 참고)."""
        val = rel.get(field)
        if not val:
            return ""
        items = val if isinstance(val, list) else [val]
        names = [str(v).strip() for v in items if v and str(v).strip()]
        return ",".join(names)

    person_rows = []
    for e in seed_entries:
        desc = e.get("description") or {}
        occupation = desc.get("직업/직위")
        occupation_str = ",".join(occupation) if isinstance(occupation, list) else (occupation or "")
        remark = e.get("remark") or e.get("introduce") or ""
        rel = desc.get("관계")
        if isinstance(rel, list) and rel:
            rel = rel[0]
        if not isinstance(rel, dict):
            rel = {}
        person_rows.append((
            e["idx"], e["word"], remark, verses_str(e.get("verses"), f"인물 {e['idx']} {e['word']}"), "",
            ",".join(e.get("word2") or []), e.get("call") or "", e.get("meaning") or "",
            # [2026-10-01] "기록 없음"만 있는 본문은 "-"로(`normalize_no_record`). 빈 값은 기존대로 빈 문자열을 유지해
            # 화면이 그 카드를 숨기는 동작을 바꾸지 않는다 — 시드가 직접 "-"를 적은 칸은 원래부터 "-"다.
            normalize_no_record(e.get("introduce")) if (e.get("introduce") or "").strip() else "",
            normalize_no_record(e.get("lifetime")) if (e.get("lifetime") or "").strip() else "",
            normalize_no_record(e.get("event")) if (e.get("event") or "").strip() else "",
            normalize_no_record(e.get("character")) if (e.get("character") or "").strip() else "",
            desc.get("출신") or "", desc.get("민족") or "",
            desc.get("지파") or "", desc.get("성별") or "", occupation_str, e.get("memo") or "",
            seed_relation_names(rel, "할아버지"), seed_relation_names(rel, "할머니"),
            seed_relation_names(rel, "아버지"), seed_relation_names(rel, "어머니"),
            seed_relation_names(rel, "배우자"), seed_relation_names(rel, "아들"),
            seed_relation_names(rel, "딸"), seed_relation_names(rel, "손자"),
            seed_relation_names(rel, "손녀"),
        ))

    cur.executemany(
        "INSERT INTO Persons (idx, word, remark, verses, relation_person, word2, call_title, meaning, "
        "introduce, lifetime, event, character, origin, nation, tribe, gender, occupation, seed_memo, "
        "rel_grandfather, rel_grandmother, rel_father, rel_mother, rel_spouse, rel_sons, rel_daughters, "
        "rel_grandsons, rel_granddaughters) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        person_rows,
    )
    print(f"Persons(PersonSeed.json 단일 소스) 삽입: {len(person_rows)}건")
    report_unresolved_verses("Persons 구절", verse_warnings)
    report_missing_bible_verses("Persons 구절", labeled_targets)


# === PlaceSeed.json -> Places (2026-10-01 신설) ===
PLACE_SEED_PATH = os.path.join(SCRIPT_DIR, "PlaceSeed.json")


def build_places_from_place_seed(cur, abbr_index):
    """[2026-10-01 신설, 사용자 확정] PlaceSeed.json(지명 사전, 소개·성경 내용·지리·역사 필드 포함)을 Places 테이블에
    그대로 담는다. PersonPlaceSeed.json은 삭제됐고(2026-09-20 사용 중단, 이후 파일 삭제) 이 파일이 지명의 단일 소스다.

    - idx는 PlaceSeed.json의 값을 그대로 쓴다(유일, 실행 확인 — 중복이면 마지막 항목이 이긴다고 가정하지 않고 오류로 중단).
    - 동명이인(같은 word)은 행이 여러 개이며 remark 앞 "1. 2. 3."으로 구분된다 — 합치지 않는다.
    - introduce/biblecontents/geography/history: 비어 있거나 "기록 없음"만 있으면 "-"(`normalize_no_record`).
    - verses: 범위를 절 단위로 풀어 `book:chapter:verse,...`로 저장한다."""
    if not os.path.exists(PLACE_SEED_PATH):
        print(f"({PLACE_SEED_PATH} 없음 — Places 테이블을 채울 수 없음, 중단)")
        raise SystemExit(1)
    with open(PLACE_SEED_PATH, encoding="utf-8") as f:
        entries = json.load(f)

    idxs = [e["idx"] for e in entries]
    if len(idxs) != len(set(idxs)):
        dup = sorted({i for i in idxs if idxs.count(i) > 1})
        print(f"PlaceSeed.json에 중복 idx가 있습니다: {dup[:20]} — 중단")
        raise SystemExit(1)

    verse_warnings = []
    labeled_targets = []
    rows = []
    for e in entries:
        label = f"장소 {e['idx']} {e['word']}"
        verses = expand_verse_list(e.get("verses"), abbr_index, verse_warnings, label)
        labeled_targets.append((label, verses))
        rows.append((
            e["idx"], e["word"], e.get("remark") or "", verses,
            normalize_no_record(e.get("introduce")), normalize_no_record(e.get("biblecontents")),
            normalize_no_record(e.get("geography")), normalize_no_record(e.get("history")),
        ))
    cur.executemany(
        "INSERT INTO Places (idx, word, remark, verses, introduce, biblecontents, geography, history) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", rows,
    )
    dash = {name: sum(1 for r in rows if r[i] == "-") for name, i in
            (("introduce", 4), ("biblecontents", 5), ("geography", 6), ("history", 7))}
    print(f"Places(PlaceSeed.json) 삽입: {len(rows)}건 — '-' 표시 칸 수 {dash}")
    report_unresolved_verses("Places 구절", verse_warnings)
    report_missing_bible_verses("Places 구절", labeled_targets)


def build_structured_person_relations(cur):
    """PersonSeed.json의 description.관계(구조화된 딕셔너리)를 PersonRelations에
    직접 반영한다 — 정규식 추정이 필요 없는 명시적 데이터라 extraction_method=
    'structured_v2'로 구분한다. Persons/Places가 이미 채워진 뒤 호출해야
    known_person_words/known_place_words가 정확하다."""
    if not os.path.exists(PERSON_SEED_PATH):
        return

    with open(PERSON_SEED_PATH, encoding="utf-8") as f:
        seed_entries = json.load(f)

    known_person_words = {row[0] for row in cur.execute("SELECT DISTINCT word FROM Persons").fetchall()}
    known_place_words = {row[0] for row in cur.execute("SELECT DISTINCT word FROM Places").fetchall()}
    person_word_to_idx = {}
    for w, i in cur.execute("SELECT word, idx FROM Persons").fetchall():
        person_word_to_idx.setdefault(w, i)  # 동명이인이면 첫 idx만 사용(기존 관례와 동일)
    known_idx_set = {row[0] for row in cur.execute("SELECT idx FROM Persons").fetchall()}
    # [2026-09-22 추가] "동생"(성별 무관 라벨) 처리에 필요 — 태그된 idx가
    # 있으면 그 사람의 실제 성별로, 없고 이름이 동명이인 없이 하나뿐이면
    # 그 사람의 성별로 "아우"/"누이" 중 정확히 결정한다(추측 금지 원칙 —
    # 결정 불가하면 스킵, 아래 resolve_dongsaeng_label 참고).
    idx_to_gender = {}
    word_to_genders = {}
    for w, i, g in cur.execute("SELECT word, idx, gender FROM Persons").fetchall():
        idx_to_gender[i] = g
        word_to_genders.setdefault(w, []).append(g)
    invalid_idx_tags = []  # [2026-09-22 추가] "이름#idx" 태그의 idx가 Persons에 실제로
    # 존재하지 않는 경우(오타 등)를 여기 모아 마지막에 경고로 출력한다 — 추측
    # 보정 없이 원본 그대로 로그만 남기고 target_idx는 빈 값(미상)으로 둔다.

    def resolve_tagged_idx(name, tagged_idx):
        """[2026-09-22 신설] `parse_idx_tag`가 뽑아낸 태그 문자열을 검증한다.
        - 태그 없음("") -> 그대로 "" (기존과 동일, 추측하지 않음).
        - "#0" -> 사용자 확인(2026-09-22, 채팅): "자세한 정보를 수집하지 못해
          링크를 걸지 못하는" 경우를 표시하는 전용 기호다(실제 idx 0번인
          사람은 Persons에 없음, idx 범위는 2~4636). 태그가 없는 것과 동일하게
          취급해 target_idx는 "" 로 남긴다(경고 없음 — 사용자가 의도적으로
          표시한 "미상"이므로 오류가 아니다).
        - 그 외 값인데 Persons.idx에 실제로 존재하지 않으면 오타로 간주해
          invalid_idx_tags에 기록하고 "" 로 폴백한다(정확히 아는 경우만
          채운다는 target_idx 컬럼 원칙 — 위 CREATE TABLE 주석 참고, 추측
          금지 원칙에 따라 임의로 후보를 골라 보정하지 않는다).
        - Persons.idx에 실제로 존재하면 그 값을 그대로 쓴다."""
        if not tagged_idx or tagged_idx == "0":
            return ""
        if tagged_idx not in known_idx_set:
            invalid_idx_tags.append((name, tagged_idx))
            return ""
        return tagged_idx

    RELATION_TYPE_BY_GENDER = {
        "부모": {"남": "son_of", "여": "daughter_of", None: "son_of"},
        "조부모": {"남": "grandson_of", "여": "granddaughter_of", None: "grandson_of"},
        "자녀": {"남": "father_of", "여": "mother_of", None: "father_of"},
        "손주": {"남": "grandfather_of", "여": "grandmother_of", None: "grandfather_of"},
    }

    def gender_key(desc):
        g = (desc or {}).get("성별")
        return g if g in ("남", "여") else None

    relation_rows = []
    other_relation_skipped = 0
    spouse_skipped = 0
    # [2026-09-22 버그 수정] 아래로 옮기기 전엔 이 셋이 `for e in seed_entries:`
    # 루프 "안"에서 매번 새로 선언돼(원래 OTHER_RELATION_LABEL_MAP 딕셔너리가
    # 루프 안에 있던 기존 구조를 그대로 따라가다 생긴 실수), 사람마다 리셋되고
    # 최종적으로 마지막 한 명 분량만 남아 있었다(실행해보니 related_to/
    # PersonContextNotes가 0건으로 나와 발견) — relation_rows와 같은 스코프인
    # 여기로 옮겨 전체 인물에 걸쳐 누적되게 한다.
    context_note_rows = []
    related_to_count = 0
    context_note_count = 0

    for e in seed_entries:
        desc = e.get("description") or {}
        rel = desc.get("관계")
        if isinstance(rel, list) and rel:
            rel = rel[0]
        if not isinstance(rel, dict):
            continue
        gk = gender_key(desc)
        src_word, src_idx = e["word"], e["idx"]

        def add(field, rtype_group, single=True):
            nonlocal other_relation_skipped
            val = rel.get(field)
            if not val:
                return
            targets = [val] if (single and isinstance(val, str)) else (val if isinstance(val, list) else [val])
            for t in targets:
                t = (t or "").strip()
                if not t:
                    continue
                # [2026-09-16 추가] 위 `parse_idx_tag` 주석 참고 — "이름#idx"
                # 태그가 있으면 그 idx를 추측 없이 그대로 쓴다.
                t, tagged_idx = parse_idx_tag(t)
                tagged_idx = resolve_tagged_idx(t, tagged_idx)
                rtype = RELATION_TYPE_BY_GENDER[rtype_group][gk]
                target_word, target_kind = resolve_target_kind(t, known_person_words, known_place_words)
                if target_kind == "place":
                    # 가족관계는 정의상 대상이 사람이어야 한다(4차 문서 §4) —
                    # 동음이의 지명과의 우연한 매칭을 걸러낸다.
                    target_kind = None
                relation_rows.append((
                    src_word, src_idx, 0, rtype, "[PersonSeed 구조화 관계]",
                    target_word, target_kind, "", tagged_idx, "structured_v2",
                ))

        add("할아버지", "조부모")
        add("할머니", "조부모")
        add("아버지", "부모")
        add("어머니", "부모")
        add("아들", "자녀", single=False)
        add("딸", "자녀", single=False)
        add("손자", "손주", single=False)
        add("손녀", "손주", single=False)

        spouse = rel.get("배우자")
        if spouse:
            spouse_list = spouse if isinstance(spouse, list) else [spouse]
            for sp in spouse_list:
                sp = (sp or "").strip()
                if not sp:
                    continue
                # [2026-09-15, 6차 문서 §2 승인] 괄호가 있으면 앞부분만 이름으로
                # 추출한다("푸데(전승)" -> "푸데"). 괄호가 아예 없는 순수 서술형
                # ("포로에서 귀환한 사람으로 성전 문지기")은 추출할 이름 자체가
                # 없으므로 여전히 스킵한다.
                if "(" in sp:
                    name_part = sp.split("(", 1)[0].strip()
                else:
                    name_part = sp
                # [2026-09-16 추가] 위 `parse_idx_tag` 주석 참고 — 괄호
                # 서술(전승 등)을 뗀 뒤 "이름#idx" 태그가 있으면 분리한다.
                name_part, tagged_idx = parse_idx_tag(name_part)
                if not name_part or len(name_part) > 8:
                    spouse_skipped += 1
                    continue
                tagged_idx = resolve_tagged_idx(name_part, tagged_idx)
                target_word, target_kind = resolve_target_kind(name_part, known_person_words, known_place_words)
                if target_kind == "place":
                    target_kind = None
                relation_rows.append((
                    src_word, src_idx, 0, "married_to", "[PersonSeed 구조화 관계]",
                    target_word, target_kind, "", tagged_idx, "structured_v2",
                ))

        # [2026-09-15, 6차 문서 §4 승인] 기타관계 182건 매핑. "Y(라벨)"이 X의
        # 기타관계 목록에 있다는 건 "Y는 X의 [라벨]"이라는 뜻이라, 대부분
        # source=Y(목록의 사람)/target=X(표제어) 순서로 넣어야 문장이 맞는다
        # (PersonRelationLabeling.sentence(for:)가 "source는 target의 [라벨]"로
        # 렌더링하기 때문). "조카"만 예외 — 대응하는 relation_type이 없어
        # uncle_of를 방향을 뒤집어 쓴다(X가 Y의 삼촌/고모라는 동치 표현).
        # [2026-09-16 추가] 사용자 요청 — 기타관계 중 "친인척 관계가 아닌
        # 특별한 경우(제자, 동역자, 친구)"만 화면에 표현. "동역자"/"스승"은
        # 이미 매핑돼 있었다(스승은 방향을 뒤집어 읽으면 "제자" — 화면
        # 쪽에서 teacher_of를 source=현재 인물 기준으로 뒤집어 "제자"로
        # 보여준다, PersonDetailView 참고). "친구"만 매핑이 아예 없어 원본에
        # 있는 사례(다윗-요나단, "다윗: 요나단(친구)")조차 지금까지 아래
        # `other_relation_skipped`로 조용히 드랍되고 있었다 — 신설.
        # "동역자"와 같은 성격(상호적 관계, 방향 구분 의미 없음)이라 같은
        # "Y_to_X" 패턴을 그대로 따른다 — 화면은 source/target 어느 쪽이든
        # 현재 인물이 걸린 friend_of 관계를 모두 "친구" 목록에 담는다.
        OTHER_RELATION_LABEL_MAP = {
            "형제": ("brother_of", "Y_to_X"), "동역자": ("co_worker_of", "Y_to_X"),
            "아우": ("younger_brother_of", "Y_to_X"), "형": ("older_brother_of", "Y_to_X"),
            "누이": ("sister_of", "Y_to_X"), "숙부": ("uncle_of", "Y_to_X"),
            "오라비": ("brother_of", "Y_to_X"), "조카": ("uncle_of", "X_to_Y"),
            "언니": ("sister_of", "Y_to_X"), "스승": ("teacher_of", "Y_to_X"),
            "친형제": ("brother_of", "Y_to_X"), "자부": ("daughter_in_law_of", "Y_to_X"),
            "선조": ("ancestor_of", "Y_to_X"), "외조부": ("maternal_grandfather_of", "Y_to_X"),
            "친구": ("friend_of", "Y_to_X"),
            # [2026-09-16 추가] 사용자 요청 — "가르가스 기타관계에 아하수에로가
            # 있는데, idx3995인 아하수에로로 확실하게 지정할 수 있는가?" 원래
            # 라벨 "주군"이 이 맵에 아예 없어 가르가스→아하수에로 관계 자체가
            # 지금까지 조용히 드롭되고 있었다(핵심 원인). "주군"/"신하"를
            # 새로 매핑한다 — "신하"는 "스승"과 완전히 같은 패턴(Y_to_X,
            # target=자기 자신이라 idx 정확히 앎)이라, 동명이인이 있는
            # 상대(예: 아하수에로 3명)를 가리킬 때도 "주군 쪽 레코드에
            # '이름(신하)'를 적어 두면" 추측 없이 100% 정확하게 연결된다
            # (이번 아하수에로 idx3995 케이스에 이 방법을 실제로 적용했다 —
            # PersonSeed.json에서 idx3995 기타관계에 "가르가스(신하)" 추가,
            # 가르가스 쪽의 원래 애매한 "아하수에로(주군)"는 제거). "주군"은
            # "조카"(uncle_of를 뒤집어 쓰는 것)와 같은 이유로 X_to_Y 방향으로
            # 매핑해 둔다 — 상대(주군) 이름만 아는 쪽(신하 본인)이 자기
            # 기타관계에 "이름(주군)"이라고만 적어도 최소한 관계 자체는
            # 기록되게(다만 상대가 동명이인이면 기존 관례대로 첫 idx 추측이
            # 적용된다 — "조카"와 동일한 리스크, 새로 만든 리스크 아님).
            "신하": ("servant_of", "Y_to_X"), "주군": ("servant_of", "X_to_Y"),
            # [2026-09-22 추가, 사용자 확정 "A그룹 — 바로 반영"] PersonSeed.json에
            # idx 태그 작업과 함께 새로 채워진 가족관계성 기타관계 라벨들.
            # 기존 있는 relation_type의 동의어("며느리"=자부, "시아버지"=장인,
            # "자매"=누이/언니, "이복형제/이복오라비"=형제 — "이복"이라는
            # 구분은 화면에선 생략됨, "쌍둥이 형"=형 — "쌍둥이"라는 구분도
            # 생략됨, "조상"=선조)는 새 relation_type 없이 그대로 합류시키고,
            # 정확히 대응하는 게 없는 것만 신설했다:
            #   - "장인"/"시아버지" -> father_in_law_of(신설, "사위"와 대칭)
            #   - "사위" -> son_in_law_of(신설)
            #   - "외손자"/"외손주" -> maternal_grandfather_of를 "외조부"와
            #     반대 방향(X_to_Y)으로 재사용 — "조카"가 uncle_of를 방향만
            #     뒤집어 쓰는 것과 완전히 같은 패턴(표제어 자신이 조부이고
            #     목록의 사람이 그 손주라는 뜻).
            #   - "증조부" -> great_grandfather_of(신설)
            #   - "외조모" -> maternal_grandmother_of(신설, QueryIntentHandler
            #     쪽엔 이미 문장 case가 있었음 — 과거 정규식 파이프라인용으로
            #     선반영돼 있던 것을 이번에 실제로 채움)
            "며느리": ("daughter_in_law_of", "Y_to_X"),
            "장인": ("father_in_law_of", "Y_to_X"), "시아버지": ("father_in_law_of", "Y_to_X"),
            "사위": ("son_in_law_of", "Y_to_X"),
            "외손자": ("maternal_grandfather_of", "X_to_Y"), "외손주": ("maternal_grandfather_of", "X_to_Y"),
            "이복형제": ("brother_of", "Y_to_X"), "이복오라비": ("brother_of", "Y_to_X"),
            "자매": ("sister_of", "Y_to_X"), "쌍둥이 형": ("older_brother_of", "Y_to_X"),
            "증조부": ("great_grandfather_of", "Y_to_X"), "외조모": ("maternal_grandmother_of", "Y_to_X"),
            "조상": ("ancestor_of", "Y_to_X"),
            # [2026-09-22 추가] "대적"/"동맹"은 가족관계가 아니라 상호관계
            # (방향에 의미 없음) — "동역자"/"친구"와 완전히 같은 성격이라
            # 같은 Y_to_X 저장 패턴을 그대로 따른다.
            "대적": ("adversary_of", "Y_to_X"), "동맹": ("ally_of", "Y_to_X"),
        }

        def resolve_dongsaeng_label(name, idx):
            """[2026-09-22 신설] "동생"은 성별을 명시하지 않는 라벨이라 그대로
            매핑할 relation_type이 없다 — idx가 태그돼 있으면 그 사람의 실제
            성별로, 없으면 이름이 동명이인 없이 하나뿐일 때만 그 성별로
            "아우"(남)/"누이"(여)로 정확히 치환한다. 성별을 확정할 근거가
            없으면 None을 돌려줘 호출부에서 미매핑 처리하게 한다(추측 금지)."""
            g = idx_to_gender.get(idx) if idx else None
            if g not in ("남", "여"):
                cands = {gg for gg in word_to_genders.get(name, []) if gg in ("남", "여")}
                g = cands.pop() if len(cands) == 1 else None
            if g == "남":
                return "아우"
            if g == "여":
                return "누이"
            return None

        def is_context_label(label):
            """[2026-09-22 신설, B그룹 — 사용자 확정 "인물관계에는 넣지
            않더라도 보여주기를 원함"] 특정 relation_type으로 정식 편입하지
            않기로 한 직함/역할/사건성 라벨("왕","총독","선지자","피고" 등)을
            인물관계 그래프(PersonRelations)엔 넣지 않되, 데이터 자체는
            버리지 않고 PersonContextNotes(참고용 전용 테이블, 검색/인물관계
            그래프에는 노출되지 않음)에 보존해 화면에 표시할 수 있게 한다.
            "/"가 섞인 복합 라벨("누이/아론의 아내" 등)은 여러 사실이 뭉쳐
            있어 의미가 불명확하므로 여기서도 제외한다(기존과 동일하게
            미매핑 유지 — 추측 금지).

            [2026-09-27 수정] "열두 제자"/"다윗의 30용사"/"다윗의 3대용사"
            (GROUP_LABEL_DEFS, C그룹)는 이제 build_person_groups()가 전담
            추출한다 — 여기서도 함께 잡히면 PersonContextNotes에 "열두 제자"
            항목이 12번(멤버 수만큼) 중복으로 쌓이는 걸 실행 확인으로
            발견했다(같은 정보가 화면 "기타 정보"와 "소속 그룹" 두 카드에
            같은 모양 없이 중복 노출됨). GROUP_LABEL_DEFS는 이 함수보다
            뒤에 정의되지만 모듈 전체가 먼저 로드된 뒤 main()이 호출되므로
            (실행 시점 기준) 문제 없다."""
            return bool(label) and "/" not in label and label not in GROUP_LABEL_DEFS

        others = rel.get("기타관계")
        if others:
            other_items = others if isinstance(others, list) else [others]
            for it in other_items:
                it = (it or "").strip()
                if not it:
                    continue
                # [2026-09-22 수정, 사용자 확정 "D그룹 — related_to 신설해서
                # 최소 반영"] 괄호(라벨)가 아예 없는 "이름#idx" 항목은 예전엔
                # 여기 도달하지도 못하고 이 아래 "괄호 1개 아니면 스킵" 검사에
                # 걸려 조용히 버려졌다 — 이제는 라벨 없음을 나타내는
                # label_part=""로 통일해서 아래 공통 로직(related_to 처리)을
                # 그대로 태운다. 괄호가 여러 개거나 닫는 괄호로 안 끝나는 등
                # 진짜 형식이 어긋난 것만 여전히 미매핑 처리한다(복합 라벨
                # "누이/아론의 아내" 등은 애초에 "(" 자체가 있어 이 분기로
                # 안 오고 아래 label_part 매칭 단계에서 걸러진다).
                if "(" not in it:
                    name_part, label_part = it, ""
                elif it.count("(") == 1 and it.endswith(")"):
                    name_part, _, label_part = it[:-1].partition("(")
                    name_part = name_part.strip()
                    label_part = label_part.strip()
                else:
                    other_relation_skipped += 1
                    continue
                if not name_part:
                    other_relation_skipped += 1
                    continue
                # [2026-09-16 추가] 위 `parse_idx_tag` 주석 참고 — "이름#idx"
                # 태그가 있으면 이 항목이 가리키는 사람의 idx를 추측 없이
                # 정확히 안다(사용자가 직접 지정한 값이라 target_idx 컬럼의
                # "추측 금지" 원칙에 어긋나지 않음).
                name_part, tagged_idx = parse_idx_tag(name_part)
                tagged_idx = resolve_tagged_idx(name_part, tagged_idx)

                # [2026-09-22 추가] "동생"은 성별에 따라 아우/누이 중 하나로
                # 확정해야 기존 relation_type에 태울 수 있다 — 확정 못 하면
                # (동명이인이라 성별을 모르면) 추측하지 않고 미매핑 처리.
                if label_part == "동생":
                    resolved = resolve_dongsaeng_label(name_part, tagged_idx)
                    if resolved is None:
                        other_relation_skipped += 1
                        continue
                    label_part = resolved

                if label_part == "" or label_part == "기타":
                    # [2026-09-22, D그룹] 구체적 관계 유형은 모르지만(라벨
                    # 없음 또는 "기타") 관련이 있다는 사실 자체는 살린다.
                    mapping = ("related_to", "Y_to_X")
                    is_related_to = True
                else:
                    mapping = OTHER_RELATION_LABEL_MAP.get(label_part)
                    is_related_to = False

                if not mapping:
                    if is_context_label(label_part):
                        # [2026-09-22, B그룹] 인물관계 그래프(PersonRelations)엔
                        # 넣지 않고 참고용 전용 테이블에만 남긴다.
                        target_word, target_kind = resolve_target_kind(
                            name_part, known_person_words, known_place_words
                        )
                        if target_kind == "place":
                            target_kind = None
                        context_note_rows.append((
                            src_word, src_idx, label_part, target_word, target_kind,
                            tagged_idx, it,
                        ))
                        context_note_count += 1
                        continue
                    other_relation_skipped += 1
                    continue
                rtype, direction = mapping
                if direction == "Y_to_X":
                    row_source_word, row_source_idx = name_part, (tagged_idx or None)
                    row_target_word = src_word
                    # target(row_target_word)이 바로 이 항목(src_word/src_idx)
                    # 자신이라 idx를 조회 없이 정확히 안다 — person_word_to_idx의
                    # "동명이인이면 첫 idx" 폴백이 전혀 필요 없는 유일한 경우.
                    row_target_idx = src_idx
                else:  # "X_to_Y" — 조카 전용, source=표제어(X), target=목록의 사람(Y)
                    row_source_word, row_source_idx = src_word, src_idx
                    row_target_word = name_part
                    row_target_idx = tagged_idx or None
                if row_source_idx is None:
                    # 목록에 적힌 사람(Y)의 idx를 Persons에서 실제로 조회한다
                    # (동명이인이면 첫 idx, 못 찾으면 빈 문자열 폴백).
                    row_source_idx = person_word_to_idx.get(name_part, "")
                if row_target_idx is None:
                    # "조카" 방향 전용 — source_idx와 같은 폴백을 target 쪽에도
                    # 그대로 적용한다(새 추측 아님, 기존 관례 재사용).
                    row_target_idx = person_word_to_idx.get(row_target_word, "")
                target_word, target_kind = resolve_target_kind(
                    row_target_word if direction == "Y_to_X" else name_part,
                    known_person_words, known_place_words,
                )
                if target_kind == "place":
                    target_kind = None
                relation_rows.append((
                    row_source_word, row_source_idx, 0, rtype, "[PersonSeed 기타관계]",
                    target_word, target_kind, it, row_target_idx, "structured_v2",
                ))
                if is_related_to:
                    related_to_count += 1

    cur.executemany(
        "INSERT INTO PersonRelations "
        "(source_word, source_idx, sense_index, relation_type, pattern_label, target_word, target_kind, "
        "raw_sentence, target_idx, extraction_method) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        relation_rows,
    )
    # [2026-09-22 신설, B그룹 — "인물관계에는 넣지 않더라도 보여주기를 원함"]
    # 왕/총독/선지자 등 직함·역할성 기타관계 라벨은 PersonRelations(인물관계
    # 그래프)엔 넣지 않되, 참고용으로 보존해 화면에 표시할 수 있도록 별도
    # 테이블에 적재한다 — is_context_label() 판정 결과가 여기 모인다.
    cur.executemany(
        "INSERT INTO PersonContextNotes "
        "(source_word, source_idx, label, target_word, target_kind, target_idx, raw_sentence) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        context_note_rows,
    )
    print(
        f"PersonRelations(structured_v2) 삽입: {len(relation_rows)}건 "
        f"(이 중 related_to(D그룹, 라벨없음/\"기타\") {related_to_count}건 — "
        f"기타관계 미매핑 스킵 {other_relation_skipped}건, 배우자 서술형/리스트 스킵 {spouse_skipped}건 — "
        f"claude/bible-research-platform-search-category-expansion-proposal.md 6차 문서 참고)"
    )
    print(f"PersonContextNotes(B그룹 — 직함/역할성, 참고용) 삽입: {len(context_note_rows)}건")
    if invalid_idx_tags:
        print(f"  ⚠️ idx 태그 오류(Persons에 존재하지 않는 idx) {len(invalid_idx_tags)}건 "
              f"— target_idx는 빈 값(미상)으로 처리함, PersonSeed.json에서 직접 확인 필요:")
        for name, idx in invalid_idx_tags:
            print(f"     - {name}#{idx}")


# [2026-09-26 신설, C그룹] "PersonGroups 같은 별도 테이블 설계부터 검토"(사용자
# 확정) — 열두 제자/다윗의 30용사/다윗의 3대용사처럼 "여러 사람이 공유하는
# 소속 집단"을 PersonRelations(가족·개인 간 관계 그래프)와 분리해서 담는다.
#
# [2026-09-27 수정] 처음엔 "열두 제자"만 "언급한 사람 자신도 멤버"
# (include_source=True)로 특별 취급했다 — 그 시점엔 12명이 서로를 참조하는
# 완전 대칭 mesh였기 때문(소스 12명 = 타겟 12명, 실행 확인). 그런데 그 뒤
# 사용자가 예수#2641의 기타관계에도 "베드로#1777(열두 제자)" 등 같은 라벨을
# 10건 추가하면서, include_source=True 규칙이 "예수도 열두 제자의 일원"이라는
# 잘못된 13번째 멤버를 만들어내는 걸 재빌드로 발견했다 — 예수는 이 라벨을
# 언급하는 사람이지 열두 제자의 "멤버"가 아니다. "타겟(라벨이 붙어 참조된
# 사람)만 멤버로 센다"는 규칙 하나로 통일해도(예수 제외하고) 여전히 정확히
# 12명이 나오는 걸 실행 확인했다(mesh 구조상 진짜 멤버는 결국 누군가의
# 타겟으로 한 번은 등장하기 때문) — 그래서 include_source 특별 취급을
# 완전히 없앴다. "다윗의 30용사"/"다윗의 3대용사"도 원래부터 다윗#468만
# 언급하는 사람이라 타겟만 세는 이 규칙과 이미 맞았다(변경 없음). 이 편이
# PersonSeed.json이 계속 수기로 바뀌어도(오늘처럼 새 멘션이 추가돼도) 더
# 안전하다 — "누가 이 라벨을 언급했는가"가 아니라 "누가 이 라벨로
# 지목됐는가"만 보므로 예수 같은 비-멤버가 자기 발언 때문에 잘못
# 끼어들 여지가 없다.
# 이 딕셔너리에 없는 라벨은 그룹으로 취급하지 않는다(추측 금지 — 새 그룹은
# 사용자가 확인 후 이 딕셔너리에 명시적으로 추가해야 한다).
GROUP_LABEL_DEFS = {
    "열두 제자": {
        "description": "예수께서 부르신 열두 사도",
    },
    "다윗의 30용사": {
        "description": "다윗을 섬긴 정예 용사 집단(삼하 23장/대상 11장)",
    },
    "다윗의 3대용사": {
        "description": "다윗의 30용사 중에서도 특히 뛰어난 세 용사",
    },
}

# [2026-09-26 추가] 라벨 표기가 미세하게 달라졌는데(예: "다윗의 30 용사"처럼
# 띄어쓰기가 다르거나 "삼십용사"처럼 다르게 표기) GROUP_LABEL_DEFS의 정확한
# 문자열과 일치하지 않으면 조용히 그룹 추출에서 빠지기만 하고 아무 경고도
# 없이 넘어가는 걸 막기 위한 안전장치 — "제자"/"용사"가 들어간 라벨인데
# GROUP_LABEL_DEFS의 어느 것과도 정확히 일치하지 않으면 후보로 모아뒀다가
# 마지막에 경고로 출력한다(자동 보정은 하지 않음 — 추측 금지).
GROUP_LABEL_NEAR_MISS_KEYWORDS = ("제자", "용사")


def build_person_groups(cur):
    """PersonSeed.json의 기타관계 라벨 중 GROUP_LABEL_DEFS에 정의된 "소속
    집단" 라벨만 뽑아 PersonGroups/PersonGroupMemberships에 채운다. Persons가
    이미 채워진 뒤 호출해야 idx 검증이 정확하다(build_structured_person_relations
    와 동일한 전제)."""
    if not os.path.exists(PERSON_SEED_PATH):
        return

    with open(PERSON_SEED_PATH, encoding="utf-8") as f:
        seed_entries = json.load(f)

    known_idx_set = {row[0] for row in cur.execute("SELECT idx FROM Persons").fetchall()}
    idx_to_word = dict(cur.execute("SELECT idx, word FROM Persons").fetchall())

    def resolve_tagged_idx(tagged_idx):
        # [2026-09-22 resolve_tagged_idx와 동일 관례] "#0"은 "미상" 전용
        # 기호(사용자 확인) — 태그 없음과 동일하게 처리, 경고 없음.
        if not tagged_idx or tagged_idx == "0":
            return ""
        if tagged_idx not in known_idx_set:
            return None  # 존재하지 않는 idx — 호출부에서 invalid로 기록
        return tagged_idx

    def canonical_identity(name, idx):
        """idx가 확정되면 Persons.word(정식 표기)로 통일해서 별칭 표기 차이
        (예: "유다"/"가룟 유다"가 같은 idx 4631)로 중복 행이 생기는 걸 막는다
        — idx가 없으면 원문 이름을 그대로 쓴다(더 나은 판단 근거가 없음)."""
        if idx and idx in idx_to_word:
            return idx_to_word[idx], idx
        return name, idx

    membership_rows = []
    seen = set()  # (group_id, person_word, person_idx) — Python 쪽 선제 dedup
    invalid_idx_tags = []
    near_miss_labels = collections.Counter()

    def add_member(group_id, name, idx, role_note, source_field):
        word, idx = canonical_identity(name, idx)
        key = (group_id, word, idx)
        if key in seen:
            return
        seen.add(key)
        membership_rows.append((group_id, word, idx, role_note, source_field))

    for e in seed_entries:
        word = e.get("word", "")
        idx = e.get("idx", "")
        rel_list = (e.get("description") or {}).get("관계") or [{}]
        rel = rel_list[0] if rel_list else {}
        other = rel.get("기타관계")
        if not isinstance(other, list):
            continue
        for raw in other:
            if not isinstance(raw, str):
                continue
            matched_label = None
            for label in GROUP_LABEL_DEFS:
                if raw.endswith(f"({label})"):
                    matched_label = label
                    break
            if matched_label is None:
                if any(kw in raw for kw in GROUP_LABEL_NEAR_MISS_KEYWORDS):
                    near_miss_labels[raw] += 1
                continue
            name_part = raw[: -(len(matched_label) + 2)]  # "(라벨)" 길이만큼 제거
            target_name, target_idx = parse_idx_tag(name_part)
            resolved_idx = resolve_tagged_idx(target_idx)
            if resolved_idx is None:
                invalid_idx_tags.append((target_name, target_idx))
                resolved_idx = ""
            # [2026-09-27 수정] "언급한 사람 자신"(word/idx)은 더 이상 멤버로
            # 넣지 않는다 — 위 GROUP_LABEL_DEFS 주석 참고(예수가 스스로
            # 언급한 것 때문에 열두 제자 "멤버"로 잘못 들어가던 버그).
            add_member(matched_label, target_name, resolved_idx, matched_label, "기타관계(target)")

    cur.executemany(
        "INSERT INTO PersonGroups (group_id, group_name, description) VALUES (?, ?, ?)",
        [(label, label, defn["description"]) for label, defn in GROUP_LABEL_DEFS.items()],
    )
    cur.executemany(
        "INSERT OR IGNORE INTO PersonGroupMemberships "
        "(group_id, person_word, person_idx, role_note, source_field) VALUES (?, ?, ?, ?, ?)",
        membership_rows,
    )
    per_group_counts = collections.Counter(row[0] for row in membership_rows)
    summary = ", ".join(f"{label} {per_group_counts.get(label, 0)}명" for label in GROUP_LABEL_DEFS)
    print(f"PersonGroups {len(GROUP_LABEL_DEFS)}건 / PersonGroupMemberships {len(membership_rows)}건 삽입 ({summary})")
    if invalid_idx_tags:
        print(f"  ⚠️ PersonGroups 쪽 idx 태그 오류 {len(invalid_idx_tags)}건 — PersonSeed.json에서 직접 확인 필요:")
        for name, tagged_idx in invalid_idx_tags:
            print(f"     - {name}#{tagged_idx}")
    if near_miss_labels:
        print(f"  ⚠️ \"제자\"/\"용사\"가 포함되지만 GROUP_LABEL_DEFS의 라벨과 정확히 일치하지 않는 기타관계 값 "
              f"{sum(near_miss_labels.values())}건 — 표기가 달라졌을 수 있으니 확인 필요:")
        for label, count in near_miss_labels.most_common():
            print(f"     - {label!r} ({count}건)")


# === theme01.json -> Themes (2026-09-15 신설) ===
# load_topic_seed_files()(주제별 말씀*.txt)와 별개로, book/chapter/start/end
# 숫자 형식인 theme01.json을 위한 전용 로더. idx는 지정하지 않고 SQLite
# rowid 자동 할당에 맡긴다(주제별 말씀*.txt 로더와 동일한 관례) — theme01.json
# 자체의 "id"(1~20)는 그대로 쓰지 않는다(다른 Themes 유입 경로와 충돌 방지).
TRAILING_META_SUFFIXES = ["에 대하여", "에 관하여"]


def _strip_theme_title(title):
    for suf in sorted(TRAILING_META_SUFFIXES, key=len, reverse=True):
        if title.endswith(suf):
            return title[: -len(suf)].strip()
    return title


def load_theme01_seed(cur):
    if not os.path.exists(THEME01_SEED_PATH):
        print(f"({THEME01_SEED_PATH} 없음 — theme01 스킵)")
        return 0

    with open(THEME01_SEED_PATH, encoding="utf-8") as f:
        raw = json.load(f)

    bible_con = sqlite3.connect(BIBLE_DB_PATH)
    all_bible_verses = set(bible_con.execute("SELECT book_id, chapter, verse FROM BibleVerses").fetchall())
    bible_con.close()

    theme_rows = []
    missing = 0
    for t in raw:
        refs = []
        for r in t["references"]:
            book, ch, start, end = r["book"], r["chapter"], r["start"], r["end"]
            for v in range(start, end + 1):
                key = (book, ch, v)
                if key in all_bible_verses:
                    refs.append(key)
                else:
                    missing += 1
        verse_refs_str = ",".join(f"{b}:{c}:{v}" for b, c, v in refs)
        keyword = _strip_theme_title(t["title"])
        theme_rows.append(("topic", t["title"], keyword, verse_refs_str, None, None))

    cur.executemany(
        "INSERT INTO Themes (category, title, search_keywords, verse_refs, tags, description) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        theme_rows,
    )
    if missing:
        print(f"  \u26a0\ufe0f theme01.json — BibleDB에 없는 절 {missing}건 스킵")
    return len(theme_rows)


# === KeywordCategoryIndex 생성 (2026-09-15 신설) ===
# JSON을 다시 파싱하지 않고, 이미 채워진 Persons/Themes 테이블 자체에서
# 뽑는다(단일 진실 공급원 유지 — 두 번 파싱하면 서로 어긋날 위험).
def build_keyword_category_index(cur):
    index_rows = []
    seen = set()

    for idx, word, word2 in cur.execute("SELECT idx, word, word2 FROM Persons").fetchall():
        words = [word] + [w for w in (word2 or "").split(",") if w]
        for w in words:
            key = (w, "인물", "Persons", idx)
            if key not in seen:
                seen.add(key)
                index_rows.append(key)

    for idx, search_keywords in cur.execute(
        "SELECT idx, search_keywords FROM Themes WHERE search_keywords IS NOT NULL AND search_keywords != ''"
    ).fetchall():
        for kw in search_keywords.split(","):
            kw = kw.strip()
            if not kw:
                continue
            key = (kw, "주제", "Themes", str(idx))
            if key not in seen:
                seen.add(key)
                index_rows.append(key)

    cur.executemany(
        "INSERT INTO KeywordCategoryIndex (keyword, category, source_table, source_idx) VALUES (?, ?, ?, ?)",
        index_rows,
    )
    return len(index_rows)


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

    -- [2026-08-21 수정] description 컬럼 제거 — 사용자 요청 "Persons의 테이블에서
    -- description은 필요없을 것 같음". description은 여전히 관계 추출(정규식)
    -- 입력으로는 쓰이지만(원본 JSON 단계, build_person_place_tables 참고),
    -- 그 결과물인 이 두 테이블에는 더 이상 담지 않는다 — 화면 표시는 이미
    -- remark만 쓰고 있었고(2026-08-20 분리), Swift `ReferenceDataStore`의
    -- Persons/Places UNION ALL 조회가 두 테이블 컬럼 구성이 같아야 하므로
    -- Places도 함께 뺐다.
    -- relation_person: 사용자 요청 — "relation_person에 Persons의 idx값을
    -- 구분자로 구분하여 넣어주면 추후에 데이터로 활용될 수 있지 않을까?"
    -- Places에는 두지 않는다(build_person_place_tables 안 relation_person_idxs
    -- 주석의 실측 참고 — Places.remark엔 "~와 관련이 있다" 언급이 3건뿐이라
    -- 이 컬럼을 둘 실익이 없다는 것을 확인함).
    CREATE TABLE Persons (
        idx TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        remark TEXT NOT NULL,
        verses TEXT NOT NULL,
        relation_person TEXT NOT NULL DEFAULT '',
        -- [2026-09-15 신설] PersonSeed.json 보강 컬럼 — 전부 nullable/빈 문자열
        -- 기본값. PersonPlaceSeed.json에만 있고 PersonSeed.json엔 없는(아직
        -- 보강 안 된) 인물은 이 컬럼들이 전부 빈 문자열로 남는다(화면에서
        -- 빈 값이면 해당 섹션을 숨기는 처리는 Swift 쪽 책임).
        word2 TEXT NOT NULL DEFAULT '',        -- 이표기/별칭, 콤마 구분
        call_title TEXT NOT NULL DEFAULT '',   -- PersonSeed.call — 짧은 호칭/요약
        meaning TEXT NOT NULL DEFAULT '',
        introduce TEXT NOT NULL DEFAULT '',
        lifetime TEXT NOT NULL DEFAULT '',
        event TEXT NOT NULL DEFAULT '',
        character TEXT NOT NULL DEFAULT '',
        origin TEXT NOT NULL DEFAULT '',       -- description.출신
        nation TEXT NOT NULL DEFAULT '',       -- description.민족
        tribe TEXT NOT NULL DEFAULT '',        -- description.지파
        gender TEXT NOT NULL DEFAULT '',       -- description.성별
        occupation TEXT NOT NULL DEFAULT '',   -- description.직업/직위, 콤마 구분
        seed_memo TEXT NOT NULL DEFAULT '',    -- PersonSeed.memo
        -- [2026-09-16 신설] 사용자 요청 — "인물 정보의 관계 내용은
        -- PersonSeed.json의 관계중 기타관계를 제외한 내용(할아버지, 할머니,
        -- 아버지, 어머니, 배우자, 아들, 딸, 손자, 손녀)를 설명없이 간단하게
        -- 표현할것". 기존 PersonRelations 테이블(아래 CREATE TABLE
        -- PersonRelations)은 이 9개 필드 중 같은 세대 그룹(예: 아버지/어머니)을
        -- "표제어 본인의 성별"만으로 son_of/daughter_of 등에 뭉뚱그려
        -- 저장해서(build_structured_person_relations의 RELATION_TYPE_BY_GENDER
        -- 참고) 원래 어느 필드였는지 relationType만으로 역추적이 구조적으로
        -- 불가능하다(예: "아버지" 필드였는지 "어머니" 필드였는지 구분 안 됨).
        -- 화면이 "라벨: 이름" 형식으로 정확히 구분해 보여줘야 해서, 추론 없이
        -- PersonSeed.json 원본 값을 그대로 옮겨 담는 전용 컬럼을 새로 뒀다
        -- (콤마 구분 — 배우자/아들/딸/손자/손녀는 원본이 리스트인 경우가
        -- 있고, 할아버지/할머니/아버지/어머니는 원본에 항상 단일 문자열뿐
        -- 이지만 일관성을 위해 전부 같은 콤마 구분 표현을 쓴다).
        rel_grandfather TEXT NOT NULL DEFAULT '',
        rel_grandmother TEXT NOT NULL DEFAULT '',
        rel_father TEXT NOT NULL DEFAULT '',
        rel_mother TEXT NOT NULL DEFAULT '',
        rel_spouse TEXT NOT NULL DEFAULT '',
        rel_sons TEXT NOT NULL DEFAULT '',
        rel_daughters TEXT NOT NULL DEFAULT '',
        rel_grandsons TEXT NOT NULL DEFAULT '',
        rel_granddaughters TEXT NOT NULL DEFAULT ''
    );
    CREATE INDEX idx_persons_word ON Persons(word);

    -- [2026-10-01 변경] PlaceSeed.json(1,094건)으로 채운다. 같은 이름의 지명(동명이인, 68개 표제어)은 idx로 구분하고
    -- remark 앞 "1. 2. 3."이 그 구분이다. introduce/biblecontents/geography/history는 화면 표시용 본문이며 비어 있거나
    -- "기록 없음"만 있는 칸은 "-"로 저장한다(build_places_from_place_seed 참고).
    CREATE TABLE Places (
        idx TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        remark TEXT NOT NULL,
        verses TEXT NOT NULL,
        introduce TEXT NOT NULL DEFAULT '-',
        biblecontents TEXT NOT NULL DEFAULT '-',
        geography TEXT NOT NULL DEFAULT '-',
        history TEXT NOT NULL DEFAULT '-'
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
        raw_sentence TEXT NOT NULL,
        -- [2026-09-16 신설] target(target_word)이 Persons.idx로 정확히
        -- 특정될 때만 채운다(예: 기타관계 "Y(스승)" -> target=표제어 자신,
        -- idx가 이미 정확히 알려져 있음). 모르면 빈 문자열 — "추측 금지"
        -- 원칙에 따라 person_word_to_idx의 "동명이인이면 첫 idx" 폴백을
        -- 이 컬럼에는 절대 쓰지 않는다(정확히 아는 경우만 채움).
        target_idx TEXT NOT NULL DEFAULT '',
        extraction_method TEXT NOT NULL DEFAULT 'regex'
    );
    CREATE INDEX idx_person_relations_source ON PersonRelations(source_word);
    CREATE INDEX idx_person_relations_target ON PersonRelations(target_word);
    CREATE INDEX idx_person_relations_method ON PersonRelations(extraction_method);

    -- [2026-09-22 신설, B그룹] 왕/총독/선지자 등 직함·역할성 기타관계
    -- 라벨(is_context_label() 판정) — 가족관계도 아니고 상호적 인물관계도
    -- 아니라서 PersonRelations(인물관계 그래프, 검색/QueryIntentHandler가
    -- 관계로 취급) 대신 여기 별도로 보존한다. "인물관계에는 넣지 않더라도
    -- 보여주기를 원함"(사용자 확정) — 화면(PersonDetailView)에서 표제어
    -- 자신의 기타 정보로만 참고 표시하고, 관계 검색/카드 등 다른 화면에는
    -- 노출하지 않는다.
    CREATE TABLE PersonContextNotes (
        source_word TEXT NOT NULL,
        source_idx TEXT NOT NULL,
        label TEXT NOT NULL,
        target_word TEXT NOT NULL,
        target_kind TEXT,
        target_idx TEXT NOT NULL DEFAULT '',
        raw_sentence TEXT NOT NULL
    );
    CREATE INDEX idx_person_context_notes_source ON PersonContextNotes(source_word);

    -- [2026-09-26 신설, C그룹] "열두 제자"/"다윗의 30용사"/"다윗의 3대용사"처럼
    -- 가족관계도 아니고(PersonRelations 대상 아님) 개인 직함·역할성도 아닌
    -- (PersonContextNotes 대상 아님) "여러 사람이 공유하는 소속 집단"을 위한
    -- 전용 테이블 — 사용자 확정("PersonGroups 같은 별도 테이블 설계부터
    -- 검토"). group_id는 영문 슬러그를 새로 만들지 않고 PersonSeed.json
    -- 원문 라벨 문자열을 그대로 쓴다(예: "열두 제자") — 소스 데이터와 1:1
    -- 대응이라 그룹이 늘어나도 별도 매핑 레이어가 필요 없다.
    CREATE TABLE PersonGroups (
        group_id TEXT PRIMARY KEY,
        group_name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT ''
    );

    -- person_idx는 "이름#idx" 태그가 있고 그 idx가 Persons에 실제 존재할
    -- 때만 채운다(추측 금지 원칙 — PersonRelations/PersonContextNotes와
    -- 동일 관례). UNIQUE 제약은 오늘 이 세션에서 반복적으로 발견한 "같은
    -- 사람이 수기 편집 중 같은 관계/목록에 실수로 두 번 등재되는" 버그
    -- 패턴이 그룹 데이터에도 재발할 가능성에 대비한 방어 장치 — 위반 시
    -- INSERT OR IGNORE로 조용히 걸러지므로(경고는 별도 카운트로 출력),
    -- 데이터가 계속 수기로 바뀌어도 그룹 멤버 목록에 중복이 쌓이지 않는다.
    CREATE TABLE PersonGroupMemberships (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id TEXT NOT NULL,
        person_word TEXT NOT NULL,
        person_idx TEXT NOT NULL DEFAULT '',
        role_note TEXT NOT NULL DEFAULT '',
        source_field TEXT NOT NULL DEFAULT '',
        UNIQUE(group_id, person_word, person_idx)
    );
    CREATE INDEX idx_person_group_memberships_person ON PersonGroupMemberships(person_idx);
    CREATE INDEX idx_person_group_memberships_group ON PersonGroupMemberships(group_id);

    -- [2026-08-20 신설, 스키마만 — 데이터는 추후] 사용자 요청 — 검색 질의를
    -- "관계/인물정보/예언/주제·속성/서사(내용 추적)/일반"으로 먼저 분류한 뒤
    -- 카테고리별로 정확한 데이터를 찾아가는 구조. 분류기(QueryIntentClassifier,
    -- Swift)는 이 세션에서 함께 구현하지만, 여기 세 테이블은 지금은 빈 채로
    -- 만들기만 한다 — 사용자가 "배포 전까지 항목 단위로 점진적으로 채워
    -- 넣겠다"고 확정했다(claude/bible-research-platform-search-architecture-
    -- feasibility.md 참고). 분류기 코드는 테이블에 실제 행이 있든 없든 항상
    -- 똑같이 동작하고, 못 찾으면 "아직 준비되지 않음" 안내 + 일반 검색으로
    -- 폴백한다 — 그래서 이 스키마를 미리 만들어 둬도, 나중에 행만 INSERT하면
    -- 코드 변경 없이 검색 결과가 좋아진다.
    --
    -- Themes — "정의/속성/교리/실천 주제" + "가상칠언 같은 이름 붙은 본문
    -- 묶음"까지 한 테이블에 담는다(둘 다 "주제 하나 = 근거/구성 절 목록
    -- 하나"라는 같은 구조라서). category로 표시 방식만 구분한다(교리·주제는
    -- "근거 절 목록", named_passage는 "완결된 본문 그대로" — 순서를 재정렬하지
    -- 않는 이유).
    CREATE TABLE Themes (
        idx INTEGER PRIMARY KEY,
        category TEXT NOT NULL,        -- 'doctrine' | 'practice' | 'topic' | 'named_passage'
        title TEXT NOT NULL,
        search_keywords TEXT,          -- 검색 매칭용 이표기/동의어, 콤마 구분(nullable)
        verse_refs TEXT NOT NULL,      -- "book:chapter:verse,...". named_passage는 전통적 순서 그대로 보존
        tags TEXT,
        description TEXT
    );
    CREATE INDEX idx_themes_title ON Themes(title);
    CREATE INDEX idx_themes_category ON Themes(category);

    -- [2026-09-15 신설] 통합검색 키워드->카테고리 분류 전용 인덱스. 콘텐츠는
    -- 담지 않는다(claude/bible-research-platform-search-category-expansion-
    -- proposal.md 4차 갱신 §2.1 — 분류 인덱스와 콘텐츠 테이블을 분리 유지하기로
    -- 확정). 같은 keyword가 여러 행을 가질 수 있다("가나안"처럼 동명이인/동음이의
    -- 케이스) — 그 경우를 하나로 합치지 않고 전부 반환해 화면 구성에서 처리하기로
    -- 확정했다(같은 문서 §2.1). Prophecies는 Themes와 구조가 겹칠 수 있어(사용자
    -- 판단) 이번 인덱스에서 제외 — "기타말씀" 라운드에서 재검토.
    CREATE TABLE KeywordCategoryIndex (
        idx INTEGER PRIMARY KEY,
        keyword TEXT NOT NULL,
        category TEXT NOT NULL,       -- '인물' | '주제' (이번 라운드, 장소 제외 — 장소 콘텐츠 미준비)
        source_table TEXT NOT NULL,   -- 'Persons' | 'Themes'
        source_idx TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',  -- 'pending' | 'active' — AI 폴백으로 유입된 신규 키워드용
        UNIQUE(keyword, category, source_table, source_idx)
    );
    CREATE INDEX idx_keyword_category_index_keyword ON KeywordCategoryIndex(keyword);

    -- [2026-09-15 신설] 핵심표현(트리거) 테이블 — QueryIntentClassifier(순수
    -- 함수, 하드코딩 트리거)는 그대로 두고, 그 옆에서 자동 학습형 트리거를
    -- 쌓는 별도 저장소. hit_count가 임계값(N=3, 사용자 확정)에 도달하면
    -- status가 'active'로 승격된다(같은 문서 §2.2) — 그 전까지는 pending으로만
    -- 남아 오분류 하나가 바로 서비스에 영향을 주지 않는다.
    CREATE TABLE ClassificationTrigger (
        idx INTEGER PRIMARY KEY,
        expression TEXT NOT NULL,
        category TEXT NOT NULL,
        source TEXT NOT NULL,          -- 'ai_auto' | 'user_confirmed'
        hit_count INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        last_hit_at TEXT NOT NULL,
        UNIQUE(expression, category)
    );

    -- Prophecies — 메시아 예언/마지막 때 예언/마지막 전쟁을 category로만
    -- 구분한 한 테이블. 셋 다 "예언(이전 절) -> 성취/대응(이후 절)" +
    -- "시대 구분"이라는 같은 구조라서(Themes와는 구조 자체가 달라 별도
    -- 테이블 — 근거는 프로젝트 문서 참고).
    CREATE TABLE Prophecies (
        idx INTEGER PRIMARY KEY,
        category TEXT NOT NULL,        -- 'messianic' | 'end_times' | 'final_war' | 'other'
        title TEXT NOT NULL,
        search_keywords TEXT,
        prophecy_refs TEXT NOT NULL,   -- 예언(구약/이전) 절
        fulfillment_refs TEXT,         -- 성취/대응 절, nullable — 미래(아직 안 이루어진) 예언은 없음
        timeline_period TEXT,          -- nullable, 아래 TimelineEvents.era와 같은 시대 어휘 공유(별도 정규화 테이블
                                        -- 없이 자유 텍스트 — 창조와 족장시대/출애굽과 광야/사사시대/통일왕국/
                                        -- 분열왕국/포로기/포로귀환/중간사/예수님의 생애/초대교회/종말(미래) 정도로
                                        -- 개수가 작고 거의 안 늘어나는 고정 어휘라, relation_type처럼 그냥 TEXT로 둠)
        tags TEXT,
        description TEXT
    );
    CREATE INDEX idx_prophecies_title ON Prophecies(title);
    CREATE INDEX idx_prophecies_category ON Prophecies(category);

    -- TimelineEvents — "바울의 3차 전도여행" 같은 서사 하나가 여러 행(사건)
    -- 으로 구성된다는 점이 Themes/Prophecies와 근본적으로 다르다(한 행 =
    -- 주제 하나가 아니라 한 행 = 사건 하나, sequence_order로 묶어야 서사
    --하나가 완성됨) — 조회할 때도 관련성 순이 아니라 순서 그대로 반환해야
    -- 하므로 표에서부터 구조가 달라야 한다.
    CREATE TABLE TimelineEvents (
        idx INTEGER PRIMARY KEY,
        narrative_key TEXT NOT NULL,    -- 같은 서사로 묶는 키, 예: "바울의_3차_전도여행"
        narrative_title TEXT NOT NULL,
        sequence_order INTEGER NOT NULL,
        event_title TEXT NOT NULL,
        verse_refs TEXT NOT NULL,
        era TEXT,                       -- nullable, Prophecies.timeline_period와 같은 시대 어휘 공유
        location TEXT,                  -- nullable, 장소명(있으면 Places와 자연스럽게 겹침)
        search_keywords TEXT,
        description TEXT
    );
    CREATE INDEX idx_timeline_events_key ON TimelineEvents(narrative_key, sequence_order);
    CREATE INDEX idx_timeline_events_title ON TimelineEvents(narrative_title);
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

    # 5) Persons(PersonSeed.json 단일 소스) -> Places/PersonRelations(정규식) 순서로
    #    실행해야 관계추출이 최신 Persons를 기준으로 known_person_words를 계산한다
    #    [2026-09-15 순서 변경]
    build_persons_from_person_seed(cur, abbr_index)
    # [2026-10-01] 지명은 PlaceSeed.json이 단일 소스다(PersonPlaceSeed.json은 삭제됨). 아래 build_person_place_tables()
    # 호출은 계속 중단 상태로 두며, 그 함수/PERSON_PLACE_SEED_PATH는 삭제된 파일을 가리키는 죽은 코드다.
    build_places_from_place_seed(cur, abbr_index)
    # [2026-09-20 중단, 사용자 확정] "PersonPlaceSeed.json 이 파일은 쓰지 말도록."
    # 이 파일로만 만들던 두 가지 — Places 테이블(999건)과, 이 파일 속 인물
    # 설명문을 정규식으로 분석해 만드는 PersonRelations 1단계(3463건) +
    # UnmatchedRelationSentences.json/AIExtractedRelations.json 2단계(AI 보조
    # 추출) 파이프라인 전체 — 를 함께 중단한다(사용자가 둘 다 중단을 확정,
    # Places는 기존에도 "아직 준비중"으로 남겨 둔 상태였다). 인물 관계는
    # 이제 아래 build_structured_person_relations()(PersonSeed.json 자체의
    # 구조화된 관계 딕셔너리, structured_v2)만 쓴다 — 그쪽은 이 함수의 정규식
    # 추출 로직·MANUAL_RELATION_ADD/REMOVE·known_person_words 등 무엇도
    # 공유하지 않아(직접 확인) 이 줄만 빼도 안전하게 분리된다.
    #
    # `build_person_place_tables()` 함수 정의 자체와 PERSON_PLACE_SEED_PATH,
    # 관련 정규식 헬퍼(`extract_relations_from_sense` 등)는 지우지 않고 그대로
    # 남겨 둔다 — 나중에 장소(Places) 데이터를 다른 소스로 다시 채우기로
    # 하거나, 이 파이프라인이 다시 필요해지면 이 호출 한 줄만 되살리면 된다.
    # `UnmatchedRelationSentences.json`(기존 727건)은 이제 이 스크립트가 더
    # 이상 갱신하지 않는다 — 지우지는 않았으니(위 파일 상단 "손으로 정리한
    # 데이터는 절대 지우지 말 것" 원칙과 별개로, 이건 자동 생성물이라 지워도
    # 되지만 사용자가 직접 결정할 사안이라 그대로 뒀다) 필요 없으면 직접 지워도
    # 된다.
    # build_person_place_tables(cur, abbr_index)
    build_structured_person_relations(cur)
    build_person_groups(cur)

    # 6) VerseSearchIndex(FTS5 unicode61) [2026-08-19 신설, 같은 날 재확장]
    build_verse_search_index(cur)

    # 7) Themes / Prophecies / TimelineEvents [2026-08-20 신설, 스키마만]
    # 위 executescript에서 테이블은 이미 만들었다. Themes는 이번에 "주제별
    # 말씀*.txt" 로더를 추가해 실제로 채운다(위 load_topic_seed_files
    # docstring 참고) — Prophecies/TimelineEvents는 아직 대응하는 시드가
    # 없어 계속 0건.
    topic_file_count, theme_row_count = load_topic_seed_files(cur, abbr_index)
    if topic_file_count:
        print(f"Themes 삽입: {theme_row_count}건 (주제별 말씀 파일 {topic_file_count}개)")
    else:
        print("Themes: 0건 (주제별 말씀*.txt 파일 없음)")
    print("Prophecies/TimelineEvents 테이블 생성: 0건 (스키마만, 데이터는 추후 항목 단위로 채울 예정)")

    theme01_row_count = load_theme01_seed(cur)
    print(f"Themes(theme01.json) 삽입: {theme01_row_count}건")

    keyword_index_count = build_keyword_category_index(cur)
    print(f"KeywordCategoryIndex 삽입: {keyword_index_count}건 (인물 word/word2 + 주제 search_keywords)")

    conn.commit()
    conn.close()
    print("완료:", OUTPUT_DB_PATH, "-", os.path.getsize(OUTPUT_DB_PATH), "bytes")


if __name__ == "__main__":
    main()
