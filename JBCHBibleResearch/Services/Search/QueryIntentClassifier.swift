//
//  QueryIntentClassifier.swift
//  JBCHBibleResearch
//
//  [2026-08-20 신설] 사용자 요청 — "코딩하지 말고 논의부터, 검색어의 문맥
//  파악이 선행돼야 함"으로 시작된 논의의 결과물. 검색어 하나를 처리하기
//  전에 "관계를 묻는지 / 인물·지명 정보를 묻는지 / 예언을 묻는지 / 주제·
//  속성·교리·유명 본문을 묻는지 / 내용 추적(서사)을 묻는지"를 먼저
//  판정한다 — 사용자 확정: "분류는 정밀하게 고정, 데이터는 항목 단위로
//  점진적으로 채움, 폴백은 항상 유지."
//
//  [3계층 구조 — 이 파일은 그중 1계층]
//  1) Classifier(이 파일) — 순수 함수, DB 접근 없음. 테이블에 실제 데이터가
//     있는지 전혀 모른 채, 오직 질의 문자열의 패턴만으로 카테고리를 정한다.
//     그래서 지금 Themes/Prophecies/TimelineEvents가 비어 있어도(스키마만,
//     `ReferenceDataStore.swift` 참고) 이 분류 로직 자체는 나중에 데이터가
//     채워져도 손댈 필요가 없다.
//  2) Handler(아직 미구현) — 분류 결과별로 해당 테이블(PersonRelations/
//     Persons·Places/Prophecies/Themes/TimelineEvents)에서 질의에 언급된
//     "그 항목"을 찾는다. 있으면 보여주고, 없으면 "아직 준비되지 않음"
//     안내만 띄운다.
//  3) 일반 검색 폴백(기존 `BibleSemanticSearchService`/`SearchViewModel`) —
//     분류 결과와 무관하게 항상 실행한다. 그래서 오분류가 나도 "기존 검색
//     결과보다 나빠지는" 경우가 없다 — 이게 이 구조 전체의 안전장치다.
//
//  [카테고리 우선순위] 아래 `classify(_:)`가 위에서부터 순서대로 시도해서
//  처음 걸리는 카테고리로 확정한다(겹치는 질의는 앞쪽이 이긴다) — 사용자와
//  함께 "다윗의 아들은 누구인가"로 확인한 것처럼, 관계 어휘가 있으면
//  인물·지명 정보보다 먼저 RELATION으로 분류돼야 한다.
//
//  [카테고리별 신뢰도 — 반드시 구분해서 읽을 것]
//  - RELATION: `RelationSynonyms`(이미 927명분 description 코퍼스로 실측
//    검증된 어휘, `BibleKeywordMatching.swift` 참고)를 그대로 재사용해서
//    상대적으로 근거가 탄탄하다.
//  - THEME_OR_ATTRIBUTE: "(주제)+의+(추상명사)" 구조 패턴과 "~에 대한/관한
//    말씀·구절" 꼬리표(`BibleReferenceAIQueryService.swift`의
//    `BibleQueryRefinementService.trailingMetaPhrases`와 같은 값 — 그
//    프로퍼티가 `private`이라 직접 참조는 못 하고 값만 그대로 복사했다,
//    출처 표시)는 사용자가 준 7개 실제 질의로 전부 재현·검증됐다(아래
//    "검증 완료 테스트 케이스" 참고).
//  - PERSON_OR_PLACE_INFO: [2026-08-20 재검토, 아래 상세] 사용자 지적으로
//    "~에 대해 알려줘/궁금해" 같은 주제-무관 표현은 트리거에서 뺐고, 대신
//    "이란 인물"/"라는 장소"처럼 텍스트 자체가 카테고리를 밝히는 경우만
//    남겨 상대적으로 신뢰도가 올라갔다 — 그래도 "OOO는 누구" 부류가 실제
//    질의로 재현 테스트되진 않아 여전히 초안이다.
//  - PROPHECY: [2026-08-20 재검토] 트리거 단어(예언/성취 등)는 여전히
//    초안이지만, 예언 주제어 목록 중 과도하게 넓었던 "환난"을 구체적 형태로
//    좁혀 오탐 위험을 낮췄다(아래 3절 상세).
//  - NARRATIVE: **아직 트리거 어휘 설계에 들어가지 않았다** — 사용자가
//    "정렬 순서가 중요함, 거기까지만 설계하고 보류"로 확정한 대로, 지금은
//    "TimelineEvents는 관련성이 아니라 sequence_order 순으로 반환해야
//    한다"는 요구사항만 `ReferenceDataStore.timelineEvents
//    (narrativeMentionedIn:)`에 반영돼 있다(narrative_key 단위로 묶어서
//    sequence_order ASC로 정렬 — 이미 구현·검증됨). 트리거 어휘 자체(여기
//    아래 목록)는 자리만 잡아 둔 초안이고, 실제 설계는 보류 상태다.
//
//  [검증 완료 테스트 케이스 — 사용자가 직접 준 질의, 전부 아래 로직으로
//  재현 확인함]
//  - "하나님의 속성을 나타내는 성경구절" -> THEME_OR_ATTRIBUTE ("의 속성")
//  - "이스라엘의 회복을 예언한 성경구절" -> PROPHECY ("예언한", RELATION/
//    THEME보다 먼저 걸림)
//  - "이스라엘 회복에 대한 말씀" -> THEME_OR_ATTRIBUTE ("에 대한 말씀")
//  - "칠년환난의 모습" -> PROPHECY ("칠년환난"이 예언 주제어 목록에 있어
//    THEME_OR_ATTRIBUTE보다 먼저 걸림 — 이전에 "예언 키워드 회수율 갭"으로
//    남겨뒀던 바로 그 케이스, 이번에 예언 주제어 목록을 추가해 해결)
//  - "가상칠언의 내용" -> THEME_OR_ATTRIBUTE ("가상칠언"이 이름 붙은 본문
//    목록에 있어 그 자체로 걸림)
//  - "기도의 방법" -> THEME_OR_ATTRIBUTE ("의 방법")
//  - "교제의 중요성" -> THEME_OR_ATTRIBUTE ("의 중요성")
//  - "다윗의 아들은 누구인가" -> RELATION ("아들"이 PERSON_OR_PLACE_INFO
//    트리거 "누구"보다 먼저 걸림 — 사용자 확인 완료)
//  - "골리앗의 동생" -> RELATION ("동생", `RelationSynonyms` 재사용)
//  - [2026-08-20 추가] "이스라엘의 환난이 언제 끝나는가" -> PROPHECY
//    ("이스라엘의 환난"), "환난 날에 어떻게 해야 하나" -> GENERAL(더 이상
//    바로 예언으로 안 걸림 — 아래 3절 상세)
//  - [2026-08-20 추가] "요셉이란 인물에 대해 알려줘" -> PERSON_OR_PLACE_INFO
//    ("이란 인물"), "믿음에 대해 알려줘" -> GENERAL(더 이상 억지로
//    PERSON_OR_PLACE_INFO로 안 걸림 — 아래 2절 상세)
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — 이 프로젝트의
//  다른 신규 Swift 파일들과 같은 caveat. 문자열 패턴 매칭 로직 자체는 위
//  테스트 케이스들을 손으로(문자열 substring 포함 여부) 하나씩 짚어가며
//  검증했다.
//

import Foundation

/// 검색어 하나를 5개 카테고리 중 하나로 분류하거나, 어디에도 안 걸리면
/// `.general`(기존 일반 검색 파이프라인)로 넘긴다. 순수 함수 — 이 타입은
/// 어떤 DB에도 접근하지 않고, 어떤 테이블에 데이터가 있는지도 모른다.
public enum QueryIntentClassifier {
    public enum Intent: String, Equatable {
        /// "OOO의 [관계어]" — `PersonRelations` 테이블이 대상.
        case relation
        /// 인물/지명 이름 자체를 묻는 질의 — `Persons`/`Places` 테이블이 대상.
        case personOrPlaceInfo
        /// 예언/성취, 또는 메시아·마지막 때·마지막 전쟁 관련 주제어 —
        /// `Prophecies` 테이블이 대상.
        case prophecy
        /// "(주제)+의+(속성/방법/의미 등 추상명사)" 구조, "~에 대한/관한
        /// 말씀·구절" 꼬리표, 또는 이름 붙은 본문(가상칠언 등) — `Themes`
        /// 테이블이 대상.
        case themeOrAttribute
        /// 서사·시간순 추적 — `TimelineEvents` 테이블이 대상.
        case narrative
        /// 위 다섯 카테고리 중 어디에도 안 걸림 — 기존 일반 검색 그대로.
        case general
    }

    /// 우선순위: 관계 -> 인물·지명 정보 -> 예언 -> 주제·속성·교리·유명 본문
    /// -> 내용 추적·서사 -> 일반. 위에서부터 순서대로 시도해 처음 걸리는
    /// 카테고리로 확정한다.
    public static func classify(_ rawQuery: String) -> Intent {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .general }

        if isRelationQuery(query) { return .relation }
        if isPersonOrPlaceInfoQuery(query) { return .personOrPlaceInfo }
        if isProphecyQuery(query) { return .prophecy }
        if isThemeOrAttributeQuery(query) { return .themeOrAttribute }
        if isNarrativeQuery(query) { return .narrative }
        return .general
    }

    // MARK: - 1) 관계 (RELATION)
    //
    // `RelationSynonyms.allWords`(`BibleKeywordMatching.swift`, 이미 927명분
    // description 코퍼스로 실측 검증된 어휘)를 그대로 재사용한다. 여기에,
    // 검색어 확장 목적(그 파일)과 달리 "관계 질의인지 아닌지 판정"이 목적이라
    // 그 파일에는 없는 기본 국어 친족 명사(사전적 어휘일 뿐, 별도 실측 검증은
    // 안 했다 — "아들"/"딸"처럼 오매칭 여지가 거의 없는 기초 어휘만 추가)를
    // 몇 개 더했다.

    private static let baselineRelationWords: [String] = [
        "아들", "딸", "부모", "남편", "지파", "조카", "사촌",
        "며느리", "사위", "장인", "장모", "이모", "고모", "손자", "손녀", "자녀",
    ]

    private static func isRelationQuery(_ query: String) -> Bool {
        if RelationSynonyms.allWords.contains(where: { query.contains($0) }) { return true }
        return baselineRelationWords.contains(where: { query.contains($0) })
    }

    // MARK: - 2) 인물·지명 정보 (PERSON_OR_PLACE_INFO)
    //
    // [2026-08-20 재검토] 처음엔 "에 대해 알려"/"에 대해 설명"도 트리거에
    // 넣었었는데, 사용자가 지적한 문제가 있다 — 이 표현은 "주제 자체"를
    // 가리키지 않는다("~ 앞의 단어로 인물/장소/정의/... 로 구분되어야 하지
    // 않을까함"). "요셉에 대해 알려줘"뿐 아니라 "믿음에 대해 알려줘"도 똑같은
    // 형태라서, 이 트리거만으로는 인물·지명 질문인지 주제·속성 질문인지 텍스트
    // 자체에서 구분이 안 된다. 실제로 어느 쪽인지 알려면 "요셉"/"믿음"이라는
    // 그 단어가 Persons/Places 테이블에 있는지 찾아봐야 하는데, 그건 DB 접근이
    // 필요한 일이라 이 계층(순수 텍스트 패턴)의 책임 범위를 벗어난다. 그래서
    // 이 두 트리거는 뺐다 — 애매한 경우는 억지로 이 카테고리에 우겨넣기보다
    // GENERAL(일반 검색)로 그냥 넘기는 쪽이 안전하다(틀리게 확신하는 것보다
    // 낫다).
    //
    // 대신 텍스트 자체가 카테고리를 직접 밝히는 경우("~이란 인물"/"~라는
    // 장소"처럼 "인물"/"장소"/"지명"이라는 단어가 그대로 딸려 나오는 경우)는
    // DB 없이도 확실히 판정할 수 있어 남겨 뒀다 — 사용자 요청("~이란 인물 ->
    // 이라는 텍스트는 인물 검색")을 그대로 반영했고, 같은 논리로 대칭되는
    // "장소"/"지명" 형태도 추가했다(⚠️ 이 대칭 확장은 사용자가 직접 요청한
    // 건 아니고, 같은 규칙을 인물 쪽에서 장소 쪽으로 자연스럽게 넓힌 것 —
    // 필요 없으면 빼도 된다).
    //
    // ⚠️ [여전히 초안] "OOO는 누구/어디(인가)" 같은 질문 구조는 별도로 실제
    // 질의를 모아 재현 테스트하지는 못했다. 실제 이름이 무엇인지(어느 단어가
    // 그 "OOO"인지)는 이 계층이 아니라 Handler가
    // `ReferenceDataStore.personsAndPlaces(mentionedIn:)`로 알아낸다 —
    // 여기서는 "이런 종류의 질문이다"만 판정한다.

    private static let personOrPlaceInfoTriggers: [String] = [
        "는 누구", "은 누구", "가 누구", "이 누구",
        "는 어디", "은 어디",
        "는 어떤 사람", "은 어떤 사람",
        "는 어떤 곳", "은 어떤 곳",
        "이란 인물", "라는 인물", "이라는 인물",
        "이란 장소", "라는 장소", "이라는 장소",
        "이란 지명", "라는 지명", "이라는 지명",
    ]

    private static func isPersonOrPlaceInfoQuery(_ query: String) -> Bool {
        personOrPlaceInfoTriggers.contains(where: { query.contains($0) })
    }

    // MARK: - 3) 예언 (PROPHECY)
    //
    // ⚠️ [초안, 단 회수율 갭 하나는 이번에 해결] 트리거 단어(예언/성취 등)에
    // 더해 "예언 주제어" 목록(메시아/재림/종말/마지막 때/마지막 전쟁 관련)을
    // 뒀다 — 이전 논의에서 "칠년환난의 모습" 같은 질의가 추상명사 구조
    // (THEME_OR_ATTRIBUTE)로만 걸러지다 보니 예언 카테고리를 못 타는 회수율
    // 문제가 있었는데, "칠년환난"을 이 주제어 목록에 직접 추가해 PROPHECY가
    // THEME보다 먼저(우선순위상) 걸리도록 해결했다.
    //
    // [2026-08-20 재검토] 처음엔 이 목록에 "환난"을 단독으로도 넣었는데,
    // 사용자가 지적한 대로 "환난 중에도 감사하라는 말씀"처럼 예언이 아니라
    // 개인적 시련/인내를 묻는 질의까지 예언으로 잘못 분류될 위험이 있었다.
    // 사용자 요청대로 "이스라엘(의) 환난"/"칠년환난"처럼 구체적인 형태로만
    // 좁혔다 — "대환난"은 (사용자가 명시하진 않았지만) "칠년환난"과 같은
    // 성격의, 그 자체로 이미 특정 종말론적 사건만을 가리키는 합성어라
    // 오탐 위험이 낮다고 판단해 그대로 남겨 뒀다.
    //
    // 위 두 항목(트리거 단어/주제어 목록) 모두 여전히 실제 질의로 전부
    // 재현 테스트되진 않은 초안이다. 폴백 구조 덕분에 "검색이 안 되는" 사고는
    // 안 나지만(Handler가 못 찾으면 그냥 일반 검색으로 넘어감), Handler를
    // 실제로 연결하기 전에 계속 재검토·보강이 필요하다.

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
    // (a) 이름 붙은 본문(named_passage) 자체를 직접 언급 — ⚠️초안 예시 목록,
    //     실제 데이터를 채우면서 계속 보강해야 한다.
    // (b) "~에 대한/관한 말씀·구절"류 꼬리표 — `BibleReferenceAIQueryService
    //     .swift`의 `BibleQueryRefinementService.trailingMetaPhrases`와 같은
    //     값(그 프로퍼티가 private라 값만 그대로 복사, 이미 실사용 중인
    //     목록이라 신뢰도가 높다).
    // (c) "(주제)+의+(추상명사)" 구조 — 방법/중요성/의미/이유/목적/역할/모습/
    //     내용/특징/속성/성품/본질/정의라는 "열린 주제에 안 걸리는, 질문
    //     형태 자체를 나타내는 닫힌 명사 집합"에 기댄다(사용자와 함께 두
    //     차례, 총 7개 실제 질의로 재현 검증 완료 — 위 파일 상단 "검증 완료
    //     테스트 케이스" 참고). 주제어를 일일이 나열하는 대신 이 구조를
    //     쓰는 이유: 주제어 목록은 근본적으로 끝이 없어(성경 주제가 수백~
    //     수천 개) 나열식으로는 반드시 회수율 구멍이 생기지만, "무엇이든
    //     주제 + 이 추상명사"라는 문형은 주제가 몇 개든 상관없이 걸린다.

    private static let namedPassages: [String] = [
        "가상칠언", "팔복", "주기도문", "십계명", "사도신경",
    ]

    /// `BibleReferenceAIQueryService.swift`의 `BibleQueryRefinementService
    /// .trailingMetaPhrases`와 동일한 값(출처 인용, 위 MARK 주석 참고) —
    /// [2026-08-20 신설] "에 대하여"/"에 관하여" 두 개를 함께 추가했으니 그
    /// 파일도 같이 갱신할 것(두 배열을 계속 동일하게 유지하는 게 이 주석의
    /// 취지). 추가 이유: 28차에서 실제로 채운 `Themes` 시드 데이터("주제별
    /// 말씀01.txt")의 제목이 전부 "OOO에 대하여" 형식인데, 기존 트리거
    /// 목록엔 "~에 대한 말씀"/"~에 관한 말씀"만 있어 "성경에 대하여"라고
    /// 그대로 쳐도 이 분류기가 themeOrAttribute로 분류하지 못했다(사용자가
    /// "주제별 말씀을 검색어로 어떻게 쳐야 하나" 질문 → 직접 로직을
    /// 시뮬레이션해 확인한 실측 결과, 어떤 검색어를 쳐도 카드가 안 뜨는
    /// 상태였음). 실제 제목 표현과 정확히 일치시켜 갭을 없앤다.
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

    /// "(주제)의 (명사)" 구조 — 띄어쓰기가 있는 경우("기도의 방법")와 없는
    /// 경우("기도의방법") 둘 다 잡는다. `query.contains("의 \(noun)")`처럼
    /// "의"와 명사 사이를 정확히 한 칸으로 고정하지 않고 붙여쓴 경우도
    /// 별도로 확인하는 이유는, 사용자가 준 실제 예시("기도의 방법" 등)는
    /// 전부 띄어쓴 형태였지만 검색창 입력에서는 붙여쓰기도 흔하기 때문이다.
    private static func containsPossessiveAbstractNoun(_ query: String, nouns: [String]) -> Bool {
        nouns.contains { noun in
            query.contains("의 \(noun)") || query.contains("의\(noun)")
        }
    }

    // MARK: - 5) 내용 추적·서사 (NARRATIVE)
    //
    // ⚠️ [보류 — 사용자 확정] "정렬 순서가 중요함, 우선 거기까지만 설계하고
    // 보류"로 확정된 카테고리다. 이 카테고리의 핵심 요구사항 — 조회 결과를
    // 관련성 순이 아니라 서사 안 사건 순서(`sequence_order`) 그대로 반환해야
    // 한다는 것 — 은 이미 `ReferenceDataStore.timelineEvents
    // (narrativeMentionedIn:)`에 구현·검증돼 있다(narrative_key로 묶은 뒤
    // sequence_order ASC 정렬, 한 서사에 속한 행 중 일부만 매칭돼도 나머지
    // 행까지 전부 함께 반환 — `ReferenceDataStore.swift` 참고).
    //
    // 아래 트리거 어휘 목록("여정"/"~차 전도여행" 등)은 자리만 잡아 둔
    // 초안이고, 다섯 카테고리 중 실제 질의로 가장 적게 검증됐다(논의에서
    // "이번 범위에 넣되 데이터는 추후"로만 확정됐을 뿐, 트리거 어휘 자체를
    // 예시 질의로 눌러보지는 못했다) — 사용자가 이 카테고리를 다시 다루기로
    // 할 때까지 더 손대지 않고 보류한다.

    private static let narrativeTriggers: [String] = [
        "여정", "전도여행", "순서대로", "어떤 순서로", "몇 번째", "과정에서", "흐름",
    ]

    private static func isNarrativeQuery(_ query: String) -> Bool {
        narrativeTriggers.contains(where: { query.contains($0) })
    }
}
