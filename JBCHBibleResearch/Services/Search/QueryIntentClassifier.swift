//
//  QueryIntentClassifier.swift
//  JBCHBibleResearch
//
//  검색어 하나를 처리하기 전에 "관계를 묻는지 / 인물 정보를 묻는지 / 예언을
//  묻는지 / 주제·속성·교리·유명 본문을 묻는지 / 내용 추적(서사)을 묻는지"를
//  먼저 판정한다. 분류는 정밀하게 고정하고, 데이터는 항목 단위로 점진적으로
//  채우며, 폴백은 항상 유지한다.
//
//  [3계층 구조 — 이 파일은 1계층]
//  1) Classifier(이 파일) — 순수 함수, DB 접근 없음. 테이블에 데이터가 있는지
//     모른 채 질의 문자열의 패턴만으로 카테고리를 정하므로, 데이터가 채워져도
//     이 로직은 바꿀 필요가 없다.
//  2) Handler(`QueryIntentHandler`) — 분류 결과별로 해당 테이블에서 질의에
//     언급된 항목을 찾는다. 없으면 "아직 준비되지 않음" 안내만 띄운다.
//  3) 일반 검색 폴백(`SearchViewModel`의 키워드 검색) — 분류
//     결과와 무관하게 항상 실행한다. 오분류가 나도 기존 검색보다 나빠지지
//     않는 것이 이 구조의 안전장치다.
//
//  [카테고리 우선순위] `classify(_:)`가 위에서부터 순서대로 시도해 처음 걸리는
//  카테고리로 확정한다(겹치는 질의는 앞쪽이 이긴다). 예: "다윗의 아들은
//  누구인가"는 관계 어휘가 있으므로 RELATION이다.
//
//  [카테고리별 신뢰도]
//  - RELATION: `RelationSynonyms`(927명분 description 코퍼스로 검증된 어휘,
//    `BibleKeywordMatching.swift`)를 재사용해 근거가 탄탄하다.
//  - THEME_OR_ATTRIBUTE: "(주제)+의+(추상명사)" 구조와 "~에 대한/관한 말씀·구절"
//    꼬리표는 실제 질의 예시로 재현·검증됐다.
//  - PROPHECY: 트리거 단어와 예언 주제어 목록은 아직 초안이다. 오탐을 줄이려
//    "환난"은 단독으로 넣지 않고 구체적 형태로만 둔다(아래 3절).
//  - NARRATIVE: 트리거 어휘는 자리만 잡아 둔 초안이고 설계는 보류 상태다.
//    "TimelineEvents는 관련성이 아니라 sequence_order 순으로 반환"한다는
//    요구사항만 `ReferenceDataStore.timelineEvents(narrativeMentionedIn:)`에
//    구현돼 있다.
//
//  [검증된 질의 예시]
//  - "하나님의 속성을 나타내는 성경구절" -> THEME_OR_ATTRIBUTE ("의 속성")
//  - "이스라엘의 회복을 예언한 성경구절" -> PROPHECY ("예언한", RELATION/
//    THEME보다 먼저 걸림)
//  - "이스라엘 회복에 대한 말씀" -> THEME_OR_ATTRIBUTE ("에 대한 말씀")
//  - "칠년환난의 모습" -> PROPHECY ("칠년환난"이 예언 주제어라 THEME보다 먼저 걸림)
//  - "가상칠언의 내용" -> THEME_OR_ATTRIBUTE ("가상칠언"이 이름 붙은 본문)
//  - "기도의 방법" / "교제의 중요성" -> THEME_OR_ATTRIBUTE ("의 방법"/"의 중요성")
//  - "다윗의 아들은 누구인가" -> RELATION ("아들")
//  - "골리앗의 동생" -> RELATION ("동생", `RelationSynonyms` 재사용)
//  - "이스라엘의 환난이 언제 끝나는가" -> PROPHECY ("이스라엘의 환난"),
//    "환난 날에 어떻게 해야 하나" -> GENERAL
//  - "믿음에 대해 알려줘" -> GENERAL (주제-무관 표현은 트리거에서 제외)
//

import Foundation

/// 검색어 하나를 5개 카테고리 중 하나로 분류하거나, 어디에도 안 걸리면
/// `.general`(기존 일반 검색 파이프라인)로 넘긴다. 순수 함수 — 이 타입은
/// 어떤 DB에도 접근하지 않고, 어떤 테이블에 데이터가 있는지도 모른다.
public enum QueryIntentClassifier {
    public enum Intent: String, Equatable {
        /// "OOO의 [관계어]" — `PersonRelations` 테이블이 대상.
        case relation
        /// 인물 이름 자체를 묻는 질의 — `Persons` 테이블이 대상. `KeywordCategoryIndex`
        /// 조회가 필요해 순수 함수 계층의 책임을 벗어나므로, 실제 판정은
        /// `QueryIntentHandler.handle`이 수행하고(우선순위는 관계 다음) 이 case는
        /// 그 결과를 담는 태그일 뿐이다. 장소는 콘텐츠가 준비되지 않아 묶지 않는다.
        case personProfile
        /// 지명 이름 자체를 묻는 질의 — `Places` 테이블이 대상(PlaceSeed.json). 인물처럼 DB 조회가 필요해
        /// `classify()`는 반환하지 않고 `QueryIntentHandler.handle`이 결과를 담는 태그로만 쓴다. 같은 이름의
        /// 인물이 함께 걸리면 한 카드에 인물·장소를 같이 보여준다.
        case placeProfile
        /// 예언/성취, 또는 메시아·마지막 때·마지막 전쟁 관련 주제어 —
        /// `Prophecies` 테이블이 대상.
        case prophecy
        /// "(주제)+의+(속성/방법/의미 등 추상명사)" 구조, "~에 대한/관한
        /// 말씀·구절" 꼬리표, 또는 이름 붙은 본문(가상칠언 등) — `Themes`
        /// 테이블이 대상. 키워드·카테고리 조회가 주제 키워드를 먼저 잡아내므로
        /// 사실상 그 폴백 역할이다.
        case themeOrAttribute
        /// 서사·시간순 추적 — `TimelineEvents` 테이블이 대상.
        case narrative
        /// 위 다섯 카테고리 중 어디에도 안 걸림 — 기존 일반 검색 그대로.
        case general
    }

    /// 우선순위: 관계 -> 예언 -> 주제·속성·교리·유명 본문 -> 내용 추적·서사
    /// -> 일반. 위에서부터 순서대로 시도해 처음 걸리는 카테고리로 확정한다.
    ///
    /// 인물 판정(`Intent.personProfile`)은 DB 조회가 필요해 이 함수에 없다 — 그 자리
    /// (관계 다음, 예언 이전)는 `QueryIntentHandler.handle`이 별도로 채운다.
    public static func classify(_ rawQuery: String) -> Intent {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .general }

        if isRelationQuery(query) { return .relation }
        if isProphecyQuery(query) { return .prophecy }
        if isThemeOrAttributeQuery(query) { return .themeOrAttribute }
        if isNarrativeQuery(query) { return .narrative }
        return .general
    }

    // MARK: - 1) 관계 (RELATION)
    //
    // `RelationSynonyms.allWords`(`BibleKeywordMatching.swift`)를 재사용하고, 검색어
    // 확장용인 그 파일에 없는 기본 친족 명사를 몇 개 더했다(오매칭 여지가 거의 없는
    // 기초 어휘만, 별도 실측 검증은 안 함).

    private static let baselineRelationWords: [String] = [
        "아들", "딸", "부모", "남편", "지파", "조카", "사촌",
        "며느리", "사위", "장인", "장모", "이모", "고모", "손자", "손녀", "자녀",
    ]

    private static func isRelationQuery(_ query: String) -> Bool {
        if RelationSynonyms.allWords.contains(where: { query.contains($0) }) { return true }
        return baselineRelationWords.contains(where: { query.contains($0) })
    }

    // MARK: - 2) 인물 프로필 (PERSON_PROFILE) — [2026-09-15 이동]
    //
    // 인물 판정은 등록된 이름(`KeywordCategoryIndex`)이 질의에 부분 문자열로 있는지로
    // 하므로 DB 접근이 필요하다 — 이 파일이 아니라
    // `QueryIntentHandler.handleKeywordCategoryLookup`과
    // `ReferenceDataStore.keywordCategories(mentionedIn:)`/`persons(mentionedIn:)`가 맡는다.

    // MARK: - 3) 예언 (PROPHECY)
    //
    // 트리거 단어(예언/성취 등)와 "예언 주제어" 목록(메시아/재림/종말/마지막 때/마지막
    // 전쟁 관련)을 함께 쓴다. "칠년환난의 모습"처럼 추상명사 구조에만 걸리던 질의가
    // PROPHECY로 먼저 분류되도록 주제어 목록에 직접 넣었다.
    //
    // "환난"은 단독으로 넣지 않는다 — "환난 중에도 감사하라는 말씀" 같은 개인적
    // 시련 질의가 예언으로 오분류되기 때문이다. "이스라엘(의) 환난"/"칠년환난"/
    // "대환난"처럼 특정 종말론적 사건을 가리키는 형태만 둔다.
    //
    // 두 목록 모두 초안이다. 폴백 덕분에 "검색이 안 되는" 사고는 없지만
    // (Handler가 못 찾으면 일반 검색으로 넘어감) 계속 재검토·보강이 필요하다.

    private static let prophecyTriggerWords: [String] = [
        "예언", "예언한", "예언된", "성취", "성취된", "이루어진", "이루어질", "응하신",
    ]

    private static let prophecyTopicNouns: [String] = [
        "메시아", "재림", "종말", "말세", "마지막 때", "마지막날", "심판", "휴거",
        "적그리스도", "짐승", "천년왕국", "새 하늘과 새 땅", "아마겟돈", "곡과 마곡",
        "칠년환난", "대환난", "이스라엘 환난", "이스라엘의 환난",
        "인봉", "나팔 심판", "대접 심판",
    ]

    private static func isProphecyQuery(_ query: String) -> Bool {
        if prophecyTriggerWords.contains(where: { query.contains($0) }) { return true }
        return prophecyTopicNouns.contains(where: { query.contains($0) })
    }

    // MARK: - 4) 주제·속성·교리·유명 본문 (THEME_OR_ATTRIBUTE)
    //
    // 세 가지 신호 중 하나라도 있으면 이 카테고리다:
    // (a) 이름 붙은 본문(named_passage)을 직접 언급 — 초안 예시 목록이라 데이터를
    //     채우면서 보강해야 한다.
    // (b) "~에 대한/관한 말씀·구절"류 꼬리표.
    // (c) "(주제)+의+(추상명사)" 구조 — 방법/중요성/의미/이유/목적/역할/모습/내용/
    //     특징/속성/성품/본질/정의라는 질문 형태를 나타내는 닫힌 명사 집합에 기댄다.
    //     주제어 목록은 끝이 없어 나열식으로는 회수율 구멍이 생기지만, "주제 + 이
    //     추상명사" 문형은 주제 수와 상관없이 걸린다.

    private static let namedPassages: [String] = [
        "가상칠언", "팔복", "주기도문", "십계명", "사도신경",
    ]

    /// "에 대하여"/"에 관하여"는 `Themes` 시드 데이터 제목이 전부 "OOO에 대하여"
    /// 형식이라 그 표현과 일치시키기 위해 포함한다.
    private static let topicSuffixPhrases: [String] = [
        "이라는 말씀", "라는 말씀", "하는 말씀", "에 대한 말씀", "에 관한 말씀",
        "이라는 구절", "라는 구절", "하는 구절", "에 대한 구절", "에 관한 구절",
        "라는 뜻", "이라는 뜻", "에 대하여", "에 관하여",
    ]

    private static let abstractQuestionNouns: [String] = [
        "방법", "중요성", "의미", "이유", "목적", "역할", "모습", "내용",
        "특징", "속성", "성품", "본질", "정의",
    ]

    private static func isThemeOrAttributeQuery(_ query: String) -> Bool {
        if namedPassages.contains(where: { query.contains($0) }) { return true }
        if topicSuffixPhrases.contains(where: { query.contains($0) }) { return true }
        return containsPossessiveAbstractNoun(query, nouns: abstractQuestionNouns)
    }

    /// "(주제)의 (명사)" 구조 — 띄어쓴 경우("기도의 방법")와 붙여쓴 경우("기도의방법")를
    /// 모두 잡는다(검색창 입력에서는 붙여쓰기도 흔하다).
    private static func containsPossessiveAbstractNoun(_ query: String, nouns: [String]) -> Bool {
        nouns.contains { noun in
            query.contains("의 \(noun)") || query.contains("의\(noun)")
        }
    }

    // MARK: - 5) 내용 추적·서사 (NARRATIVE)
    //
    // ⚠️ 보류된 카테고리다. 핵심 요구사항 — 조회 결과를 관련성 순이 아니라 서사 안
    // 사건 순서(`sequence_order`)로 반환 — 은 `ReferenceDataStore.timelineEvents
    // (narrativeMentionedIn:)`에 구현돼 있다(narrative_key로 묶어 sequence_order
    // ASC 정렬, 일부 행만 매칭돼도 같은 서사의 나머지 행까지 반환).
    //
    // 아래 트리거 어휘 목록은 자리만 잡아 둔 초안이고, 다섯 카테고리 중 실제 질의로
    // 가장 적게 검증됐다.

    private static let narrativeTriggers: [String] = [
        "여정", "전도여행", "순서대로", "어떤 순서로", "몇 번째", "과정에서", "흐름",
    ]

    private static func isNarrativeQuery(_ query: String) -> Bool {
        narrativeTriggers.contains(where: { query.contains($0) })
    }
}
