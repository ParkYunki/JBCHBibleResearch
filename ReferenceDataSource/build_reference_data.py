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
import json
import os
import re
import sqlite3

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BOOKS_JSON_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "books.json")
OUTPUT_DB_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "ReferenceData.sqlite")
BIBLE_DB_PATH = os.path.join(SCRIPT_DIR, "..", "JBCHBibleResearch", "Resources", "BibleDB.sqlite")
PERSON_PLACE_SEED_PATH = os.path.join(SCRIPT_DIR, "PersonPlaceSeed.json")
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
SENSE_SPLIT_RE = re.compile(r'(?:^|\n)\s*(\d+)\.\s*')
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
    (r'([가-힣]{2,6})의\s*(?:아버지|부친|아비(?![가-힣]))', 'father_of', '~의 아버지/부친/아비(entry가 X의 아버지) [2026-08-19 동의어 확장]'),
    (r'([가-힣]{2,6})의\s*어머니', 'mother_of', '~의 어머니(entry가 X의 어머니)'),
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


def extract_relations_from_sense(word, idx, sense_index, sentence, known_person_words, known_place_words):
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

    def overlaps_joint_parent(span):
        return any(a < span[1] and span[0] < b for a, b in matched_spans)

    for pattern, relation_type, label in RELATION_PATTERNS:
        for m in re.finditer(pattern, sentence):
            if overlaps_joint_parent(m.span()):
                continue  # 이미 위 JOINT_PARENT_RE가 처리한 구간(예: "사이의 아들")은 중복 추출하지 않는다
            target = m.group(1)
            if target == word or is_probable_noise(target, relation_type) or is_stopword_target(target):
                continue
            target, target_kind = resolve_target_kind(target, known_person_words, known_place_words)
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
    unmatched_sentences = []  # [2026-08-19 신설] 2단계(AI 보조 추출) 입력으로 내보낼 목록
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

    cur.executemany(
        "INSERT INTO PersonRelations "
        "(source_word, source_idx, sense_index, relation_type, pattern_label, target_word, target_kind, "
        "raw_sentence, extraction_method) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'regex')",
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
        "raw_sentence, extraction_method) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'manual')",
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
            "raw_sentence, extraction_method) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'ai')",
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
        raw_sentence TEXT NOT NULL,
        extraction_method TEXT NOT NULL DEFAULT 'regex'
    );
    CREATE INDEX idx_person_relations_source ON PersonRelations(source_word);
    CREATE INDEX idx_person_relations_target ON PersonRelations(target_word);
    CREATE INDEX idx_person_relations_method ON PersonRelations(extraction_method);
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
