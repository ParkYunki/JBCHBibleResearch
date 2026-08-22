import Foundation

//
//  ReferenceEntity.swift
//  BibleResearchModels
//
//  [2026-08-19 신설] `ReferenceDataStore`의 Persons/Places/PersonRelations
//  조회 결과를 담는 값 타입. SwiftData `@Model`이 아니라 평범한 구조체다 —
//  `HanjaCharacterInfo`/`HanjaWordAnnotation`과 같은 원칙(정적 참조 데이터를
//  퍼시스턴스 레이어에 넣지 않는다, `ReferenceDataStore.swift` 상단 주석
//  참고).
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — 배치 위치는
//  일단 `ReferenceData/` 폴더로 뒀지만, 이 패키지의 기존 관례상 더 맞는
//  위치(예: `Models/`)가 있다면 옮겨도 무방하다(이 타입들은 다른 파일을
//  참조하지 않는 순수 값 타입이라 이동 비용이 낮다).
//

/// `Persons`/`Places` 테이블 조회 결과 — 인물/지명 사전 한 항목.
public struct ReferenceEntity {
    public enum Kind {
        case person
        case place
    }

    public let idx: String
    public let word: String
    /// [2026-08-21 삭제] 원본 체크포인트의 "description"(데이터 분석/관계
    /// 추출 전용, 화면에는 애초에 안 쓰였다 — 이 파일 안에서도 `entityRemark`만
    /// 읽혔다) — 사용자 요청 "Persons의 테이블에서 description은 필요없을 것
    /// 같음"에 따라 이 값 타입에서 제거했다. Python 빌드 스크립트
    /// (`build_reference_data.py`)는 이후로도 원본 JSON의 "description"
    /// 필드를 관계 추출 입력으로 계속 쓰지만, 그 결과물인 `ReferenceData.sqlite`
    /// 의 Persons/Places 테이블 자체에는 더 이상 description 컬럼을 쓰지
    /// 않는다 — 이 구조체는 그 테이블을 그대로 읽는 값 타입이라 함께 뺀다.
    /// [2026-08-20 신설, 사용자 요청] "description은 데이터 분석용, remark는
    /// 화면 출력용." 사용자가 관계 추출 정확도를 위해 description을 수기로
    /// 간결하게 다듬으면서(정규식이 잘못 붙잡던 문장·수식어 제거) 화면
    /// 표시용 서술이 줄어드는 부작용이 있었는데, 이 필드에 그 수기 편집
    /// 이전의 원문을 그대로 보존해 화면에는 이쪽을 보여준다
    /// (`build_reference_data.py`의 `Persons.remark`/`Places.remark` 컬럼).
    public let entityRemark: String
    /// 이 이름이 언급되는 성경 좌표 전체 — 여러 동명이인의 verses가 섞여
    /// 있을 수 있다는 같은 한계가 적용된다.
    public let verseRefs: [BibleVerseRef]
    public let kind: Kind

    public init(idx: String, word: String, entityRemark: String, verseRefs: [BibleVerseRef], kind: Kind) {
        self.idx = idx
        self.word = word
        self.entityRemark = entityRemark
        self.verseRefs = verseRefs
        self.kind = kind
    }
}

/// `PersonRelations` 테이블 조회 결과 — 관계 하나("~의 아들/형제/지파" 등).
public struct PersonRelationRecord {
    public let sourceWord: String
    public let relationType: String
    public let targetWord: String
    /// nil이면 규칙 추출은 됐지만 대상 이름이 이 번들 데이터셋(체크포인트가
    /// 일부만 담고 있음) 안에서 확인되지 않은 경우 — 호출부는 이 경우
    /// `ReferenceDataStore.personOrPlace(exactWord:)`를 시도하지 말아야
    /// 한다(어차피 nil이 나옴, 조회 낭비 방지 목적으로 여기서 미리 구분).
    public let targetKind: ReferenceEntity.Kind?
    public let rawSentence: String

    public init(sourceWord: String, relationType: String, targetWord: String, targetKind: ReferenceEntity.Kind?, rawSentence: String) {
        self.sourceWord = sourceWord
        self.relationType = relationType
        self.targetWord = targetWord
        self.targetKind = targetKind
        self.rawSentence = rawSentence
    }
}

/// `VerseSearchIndex`(FTS5 trigram) 조회 결과 한 건.
public struct FullTextVerseMatch {
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let content: String
    /// SQLite `bm25()` 값 — 관례상 낮을수록(더 음수에 가까울수록) 관련성이
    /// 높다. UI에 그대로 노출하기보다는 정렬 기준으로만 쓰는 걸 권장한다
    /// (양수/음수 스케일이 사용자에게 직관적이지 않다).
    public let rank: Double

    public init(bookId: Int, chapter: Int, verse: Int, content: String, rank: Double) {
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.content = content
        self.rank = rank
    }
}

// MARK: - Themes / Prophecies / TimelineEvents (2026-08-20 신설, 스키마만)
//
// [2026-08-20 신설] 질의 분류(QueryIntentClassifier) 논의의 결과 — "관계/
// 인물정보"만 데이터가 있고 "예언/주제·속성/서사"는 아직 없다는 걸 사용자가
// 확인한 뒤, "분류는 정밀하게 고정, 데이터는 항목 단위로 점진적으로 채움,
// 폴백은 항상 유지"라는 원칙으로 나머지 세 테이블 스키마도 지금 먼저 만들기로
// 확정했다(`claude/bible-research-platform-search-architecture-feasibility.md`
// 참고). `ReferenceDataStore.themes/prophecies/timelineEvents(matching:)`가
// 이 세 값 타입을 돌려준다 — 지금은 테이블이 비어 있어(스키마만) 항상 빈
// 배열이 나온다.
//
// 세 테이블이 하나로 합쳐지지 않고 따로인 이유는 "같은 토픽이라서"가 아니라
// "컬럼 구조 자체가 다르기 때문"이다(사용자 확인 완료):
// - Themes: 주제 하나 = 근거 절 목록 하나(교리/실천/속성 + 가상칠언 같은
//   이름 붙은 본문 묶음까지 — 전부 "주제 -> 절 목록"이라는 같은 모양).
// - Prophecies: "예언 절 -> 성취/대응 절" 쌍 + 시대 구분이 있어야 해서
//   Themes와 모양 자체가 다르다. 메시아 예언/마지막 때 예언/마지막 전쟁은
//   이 쌍 구조가 똑같아서 `category` 컬럼 하나로만 구분한다.
// - TimelineEvents: 서사 하나(예: "바울의 3차 전도여행")가 여러 행(사건)으로
//   구성되고, 조회 시 관련성 순이 아니라 `sequence_order` 그대로 반환해야
//   한다는 점이 Themes/Prophecies와 근본적으로 다르다.
//
// `category`/`timelinePeriod`/`era` 등은 값의 종류가 정해져 있어도(예:
// Themes.category는 'doctrine'|'practice'|'topic'|'named_passage') Swift
// enum이 아니라 `String`이다 — 위 `PersonRelationRecord.relationType`과
// 같은 이유(DB 스키마에 CHECK 제약이 없는 자유 텍스트라, Swift 쪽에서
// 임의로 닫힌 집합을 강제하면 오히려 DB와 타입이 어긋날 위험이 생긴다).

/// `Themes` 테이블 조회 결과 — 주제/교리/실천 또는 이름 붙은 본문 묶음 하나.
public struct ThemeRecord {
    public let idx: Int
    /// 'doctrine' | 'practice' | 'topic' | 'named_passage'
    public let category: String
    public let title: String
    /// 검색 매칭용 이표기/동의어, 콤마 구분(nullable).
    public let searchKeywords: String?
    public let verseRefs: [BibleVerseRef]
    public let tags: String?
    public let themeDescription: String?

    public init(
        idx: Int, category: String, title: String, searchKeywords: String?,
        verseRefs: [BibleVerseRef], tags: String?, themeDescription: String?
    ) {
        self.idx = idx
        self.category = category
        self.title = title
        self.searchKeywords = searchKeywords
        self.verseRefs = verseRefs
        self.tags = tags
        self.themeDescription = themeDescription
    }
}

/// `Prophecies` 테이블 조회 결과 — 예언 하나("예언 절 -> 성취/대응 절" 쌍).
public struct ProphecyRecord {
    public let idx: Int
    /// 'messianic' | 'end_times' | 'final_war' | 'other'
    public let category: String
    public let title: String
    public let searchKeywords: String?
    public let prophecyRefs: [BibleVerseRef]
    /// 성취/대응 절 — 아직 이루어지지 않은 예언(예: 마지막 때 예언 일부)은
    /// 빈 배열일 수 있다(DB의 nullable `fulfillment_refs`와 대응).
    public let fulfillmentRefs: [BibleVerseRef]
    /// nullable, 자유 텍스트(정규화 테이블 없이 `TimelineEventRecord.era`와
    /// 같은 어휘 공유 — 위 MARK 주석 참고).
    public let timelinePeriod: String?
    public let tags: String?
    public let prophecyDescription: String?

    public init(
        idx: Int, category: String, title: String, searchKeywords: String?,
        prophecyRefs: [BibleVerseRef], fulfillmentRefs: [BibleVerseRef],
        timelinePeriod: String?, tags: String?, prophecyDescription: String?
    ) {
        self.idx = idx
        self.category = category
        self.title = title
        self.searchKeywords = searchKeywords
        self.prophecyRefs = prophecyRefs
        self.fulfillmentRefs = fulfillmentRefs
        self.timelinePeriod = timelinePeriod
        self.tags = tags
        self.prophecyDescription = prophecyDescription
    }
}

/// `TimelineEvents` 테이블 조회 결과 — 서사 하나를 이루는 사건 한 행.
/// 같은 `narrativeKey`를 가진 행들을 `sequenceOrder` 순서로 모아야 서사
/// 하나가 완성된다(관련성 순 정렬 대상이 아님 — 위 MARK 주석 참고).
public struct TimelineEventRecord {
    public let idx: Int
    /// 같은 서사로 묶는 키, 예: "바울의_3차_전도여행".
    public let narrativeKey: String
    public let narrativeTitle: String
    public let sequenceOrder: Int
    public let eventTitle: String
    public let verseRefs: [BibleVerseRef]
    /// nullable, `ProphecyRecord.timelinePeriod`와 같은 어휘 공유.
    public let era: String?
    /// nullable, 장소명(있으면 Places와 자연스럽게 겹칠 수 있음).
    public let location: String?
    public let searchKeywords: String?
    public let eventDescription: String?

    public init(
        idx: Int, narrativeKey: String, narrativeTitle: String, sequenceOrder: Int,
        eventTitle: String, verseRefs: [BibleVerseRef], era: String?, location: String?,
        searchKeywords: String?, eventDescription: String?
    ) {
        self.idx = idx
        self.narrativeKey = narrativeKey
        self.narrativeTitle = narrativeTitle
        self.sequenceOrder = sequenceOrder
        self.eventTitle = eventTitle
        self.verseRefs = verseRefs
        self.era = era
        self.location = location
        self.searchKeywords = searchKeywords
        self.eventDescription = eventDescription
    }
}
