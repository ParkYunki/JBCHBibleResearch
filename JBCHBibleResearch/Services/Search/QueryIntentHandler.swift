//
//  QueryIntentHandler.swift
//  JBCHBibleResearch
//
//  QueryIntentClassifier의 3계층 구조 중 2계층(Handler). Classifier가 정한 카테고리별로
//  PersonRelations/Persons/Prophecies/Themes/TimelineEvents를 조회해 "카드" 하나로
//  정리하고, `SearchView`가 일반 검색 결과 목록 맨 위에 보여준다.
//  일반 검색(3계층)은 이 카드와 무관하게 항상 실행되므로, Handler가 못 찾거나 오분류해도
//  검색 자체는 막히지 않는다(3계층 구조 전체의 안전장치).
//  Prophecies/Themes/TimelineEvents는 현재 데이터가 0건이라 사실상 항상 `.notReady`로
//  응답하며, 데이터가 채워지면 이 파일 수정 없이 `.found`로 바뀐다.
//

import Foundation
import BibleResearchModels

/// 관계 카드 한 행 + 그 행의 "새로 알게 된 쪽" 인물의 성경 좌표.
///
/// `PersonRelationRecord`에는 좌표 필드가 없어, `handleRelation`이 `answerWord`로 고른
/// 인물 이름을 `ReferenceDataStore.personOrPlace(exactWord:)`로 조회해 그 인물의
/// verses를 붙인다. source/target 중 어느 쪽이 "새로 알게 된 쪽"인지는 조회 방향마다
/// 다르다(예: "다윗의 아들들은?"에서는 나열되는 source).
struct RelationDisplayItem {
    let relation: PersonRelationRecord
    /// 조회 실패(Persons/Places에 없는 이름)면 빈 배열 — `SearchView`는 이 경우
    /// 내비게이션 없이 텍스트만 보여준다.
    let verseRefs: [BibleVerseRef]
}

/// Handler 조회 결과 하나 — 카테고리(`intent`)와 상태(`status`).
struct QueryIntentCard {
    enum Content {
        case relation([RelationDisplayItem])
        /// `PersonEntity`(보강 컬럼 + 관계 리스트) 기반 — 장소는 포함하지 않는다(콘텐츠 미준비).
        case personProfile([PersonEntity])
        case prophecy([ProphecyRecord])
        case theme([ThemeRecord])
        case narrative([NarrativeGroup])

        /// 이 카드가 가리키는 성경 좌표 전체 — 화면 순서 그대로, 중복 제거.
        /// `SearchViewModel.performAIQuerySearch`가 "성경구절" 섹션에 직접 채워, 카드가 이미
        /// 답을 확정한 경우 별도의 근사 검색 결과가 섞이지 않게 한다.
        /// 각 케이스가 이미 가진 verse 필드를 모을 뿐 DB를 새로 조회하지 않는다.
        var verseRefs: [BibleVerseRef] {
            var seen = Set<BibleVerseRef>()
            func dedup(_ refs: [BibleVerseRef]) -> [BibleVerseRef] {
                refs.filter { seen.insert($0).inserted }
            }
            switch self {
            case .relation(let items):
                return dedup(items.flatMap { $0.verseRefs })
            case .personProfile(let persons):
                return dedup(persons.flatMap { $0.verseRefs })
            case .prophecy(let records):
                // 예언 절 + 성취/대응 절을 함께 담는다(성취 절이 없으면 예언 절만 남는다).
                return dedup(records.flatMap { $0.prophecyRefs + $0.fulfillmentRefs })
            case .theme(let records):
                return dedup(records.flatMap { $0.verseRefs })
            case .narrative(let groups):
                return dedup(groups.flatMap { group in group.events.flatMap { $0.verseRefs } })
            }
        }
    }

    enum Status {
        case found(Content)
        /// 데이터가 없거나 질의와 일치하는 항목이 없는 경우 — 구분하지 않고 한 메시지로 합쳤다.
        case notReady(message: String)
    }

    let intent: QueryIntentClassifier.Intent
    let status: Status
}

extension QueryIntentCard {
    /// `.notReady`면 빈 배열. `Content.verseRefs` 참고.
    var verseRefs: [BibleVerseRef] {
        switch status {
        case .notReady: return []
        case .found(let content): return content.verseRefs
        }
    }

    /// `SearchView`의 섹션 헤더 개수 배지용.
    var foundCount: Int {
        switch status {
        case .notReady:
            return 0
        case .found(let content):
            switch content {
            case .relation(let items): return items.count
            case .personProfile(let items): return items.count
            case .prophecy(let items): return items.count
            case .theme(let items): return items.count
            case .narrative(let groups): return groups.reduce(0) { $0 + $1.events.count }
            }
        }
    }
}

/// `TimelineEvents`는 한 서사가 여러 행(사건)이라 `narrative_key` 단위로 묶어 보여준다.
/// `ReferenceDataStore.timelineEvents(narrativeMentionedIn:)`가 `narrative_key ASC,
/// sequence_order ASC`로 정렬해 돌려주므로 같은 key는 연속이며, `groupByNarrative`는
/// 이에 기대어 재정렬 없이 순차 그룹핑만 한다.
struct NarrativeGroup: Identifiable {
    let narrativeKey: String
    let narrativeTitle: String
    let events: [TimelineEventRecord]
    var id: String { narrativeKey }
}

@MainActor
enum QueryIntentHandler {
    /// `intent == .general`이면 nil(`SearchView`는 카드 섹션을 그리지 않는다).
    /// `ReferenceDataProvider.shared.store`가 nil인 경우(번들에 `ReferenceData.sqlite` 없음)도
    /// nil — 데이터 없음이 아니라 설치 문제다.
    static func handle(_ query: String, intent: QueryIntentClassifier.Intent) -> QueryIntentCard? {
        guard let store = ReferenceDataProvider.shared.store else { return nil }

        // `QueryIntentClassifier` 우선순위상 관계 다음 자리. DB 접근이 필요해 classify()(순수
        // 함수)가 아니라 여기서 수행한다. `.relation`으로 확정된 경우는 아래 switch가 처리하므로
        // 건너뛰고, `.general`이어도 시도한다 — "다윗"처럼 트리거 문구 없는 표제어 질의도
        // 등록된 인물/주제 키워드는 잡아야 한다.
        if intent != .relation, let card = handleKeywordCategoryLookup(query, store: store) {
            return card
        }

        guard intent != .general else { return nil }
        switch intent {
        case .relation: return handleRelation(query, store: store)
        case .prophecy: return handleProphecy(query, store: store)
        case .themeOrAttribute: return handleTheme(query, store: store)
        case .narrative: return handleNarrative(query, store: store)
        // switch가 exhaustive해야 해서 `.personProfile`을 다룬다. classify()는 더 이상 이 값을
        // 반환하지 않고 인물 조회는 위 handleKeywordCategoryLookup이 먼저 시도하므로, 여기
        // 도달하면 `.general`과 같이 nil로 처리한다.
        case .personProfile: return nil
        case .general: return nil
        }
    }

    // MARK: - 관계

    /// `BibleStructuralRerankerService.computeBoosts`와 같은 원칙으로 정방향(질의의 이름이
    /// source, 예: "다윗의 아들")과 역방향(이름이 target으로만 존재, 예: "골리앗의 동생" —
    /// "골리앗"은 Persons에 행이 없음)을 모두 모은다.
    ///
    /// `detectRelationSubQuery`가 구체적 관계 타입(자녀/부모/아버지/어머니/손자/아내/남편 등)을
    /// 감지하면 그 타입으로만 필터링하고, 감지되지 않는 관계어는 엔티티 관련 관계 전체를
    /// 나열하는 폴백으로 처리한다(틀린 답은 아니지만 특정 관계만 골라 보여주진 않는다).
    private static func handleRelation(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        var combined: [RelationDisplayItem] = []
        var seen = Set<String>()
        // `answerWord`가 각 행에서 "새로 알게 된 쪽" 이름을 고르고, 그 이름의 verses를 붙인다.
        // 조회에 실패해도 빈 배열이라 관계 표시 자체는 막히지 않는다.
        func add(_ relations: [PersonRelationRecord], answerWord: (PersonRelationRecord) -> String) {
            for relation in relations {
                let key = "\(relation.sourceWord)|\(relation.relationType)|\(relation.targetWord)"
                guard seen.insert(key).inserted else { continue }
                let verses = (try? store.personOrPlace(exactWord: answerWord(relation)))?.verseRefs ?? []
                combined.append(RelationDisplayItem(relation: relation, verseRefs: verses))
            }
        }

        let entities = (try? store.personsAndPlaces(mentionedIn: query)) ?? []
        let personEntities = entities.filter { $0.kind == .person }
        let reverseRows = (try? store.personRelations(targetWordMentionedIn: query)) ?? []

        if let subQuery = detectRelationSubQuery(query), !personEntities.isEmpty {
            for entity in personEntities {
                switch subQuery {
                case .reverseByType(let types):
                    // 조사로 방향을 가른다: entity 바로 뒤가 "이/가"(주격)면 entity가 source인 정방향
                    // ("노아가 아버지인 사람" → 셈/함/야벳), 그 외(기본 "의")는 역방향("노아의 아버지는?" →
                    // 라멕). 아들/딸/손자/아버지/어머니 등 역할이 방향을 가리키는 유형 전부에 같은 이분법이
                    // 적용된다.
                    if subjectDirection(for: entity.word, in: query) == true {
                        let forwardRows = (try? store.personRelations(forWord: entity.word)) ?? []
                        add(forwardRows.filter { types.contains($0.relationType) },
                            answerWord: { $0.targetWord })
                    } else {
                        // "OO의 아들/딸/자녀는?" — source가 OO의 자녀이므로 target=OO 쪽에서 찾는다(역방향).
                        // 답은 source.
                        add(reverseRows.filter { $0.targetWord == entity.word && types.contains($0.relationType) },
                            answerWord: { $0.sourceWord })
                    }
                case .parents:
                    // "OO의 부모는?" — 부모 항목이 "OO의 아버지/어머니"로 서술된 경우(역방향, 답=source)와
                    // OO 항목이 "A와 B 사이의 아들/딸"로 서술된 경우(정방향, 답=target)가 모두 있을 수 있어
                    // 합친다.
                    add(reverseRows.filter { $0.targetWord == entity.word && ["father_of", "mother_of"].contains($0.relationType) },
                        answerWord: { $0.sourceWord })
                    let forwardRows = (try? store.personRelations(forWord: entity.word)) ?? []
                    add(forwardRows.filter { ["son_of", "daughter_of"].contains($0.relationType) },
                        answerWord: { $0.targetWord })
                }
            }
            if !combined.isEmpty {
                return QueryIntentCard(intent: .relation, status: .found(.relation(combined)))
            }
            // 타입 필터링 결과가 비면(해당 관계 데이터 없음) 아래 폴백으로 넘어가 다른 관계라도
            // 보여준다.
        }

        for entity in personEntities {
            // 폴백(관계 타입 미지정) — entity가 source인 정방향 행이라 답은 target
            // (예: (다윗, king_of, 유다) → 유다).
            add((try? store.personRelations(forWord: entity.word)) ?? [], answerWord: { $0.targetWord })
        }
        // 폴백 역방향 행 — entity가 target이라 source가 새 정보.
        add(reverseRows, answerWord: { $0.sourceWord })

        guard !combined.isEmpty else {
            return QueryIntentCard(intent: .relation, status: .notReady(
                message: "이 질의에서 등록된 인물 관계를 찾지 못했습니다. 아래 검색 결과를 확인해 보세요."
            ))
        }
        return QueryIntentCard(intent: .relation, status: .found(.relation(combined)))
    }

    /// `handleRelation` 전용 — 질의에서 구체적인 관계 타입을 감지한다.
    /// 검사 순서 주의: 현재 키워드끼리는 부분 문자열 관계가 없지만, 나중에 추가할 때
    /// (예: "할아버지"는 "아버지"를 포함) 더 구체적인 키워드를 먼저 검사해야 한다.
    private enum RelationSubQuery {
        /// "OO의 <역할>은?" — target == OO이고 relationType이 목록에 속하는 행의 source를
        /// 답으로 보여준다.
        case reverseByType([String])
        /// "OO의 부모는?" 전용 — father_of/mother_of(역방향)와 son_of/daughter_of(정방향)를 합친다.
        case parents
    }

    /// `entityWord` 바로 뒤 글자가 주격 조사("이"/"가")면 true(entity=source), 관형격
    /// 조사("의")면 false(entity=target), 그 외/이름 없음이면 nil(호출부가 역방향으로
    /// 폴백). `query.range(of:)`는 첫 등장만 보므로 같은 이름이 두 번 나오면 첫 번째 기준이다.
    private static func subjectDirection(for entityWord: String, in query: String) -> Bool? {
        guard let range = query.range(of: entityWord) else { return nil }
        let after = query[range.upperBound...]
        if after.hasPrefix("이") || after.hasPrefix("가") { return true }
        if after.hasPrefix("의") { return false }
        return nil
    }

    private static func detectRelationSubQuery(_ query: String) -> RelationSubQuery? {
        if query.contains("부모") { return .parents }
        if query.contains("자녀") || query.contains("자식") { return .reverseByType(["son_of", "daughter_of"]) }
        if query.contains("아들") { return .reverseByType(["son_of"]) }
        if query.contains("딸") { return .reverseByType(["daughter_of"]) }
        // "손자"/"손녀"는 "아들"/"딸"과 부분 문자열 관계가 없어 검사 순서와 무관하다.
        if query.contains("손자") { return .reverseByType(["grandson_of"]) }
        if query.contains("손녀") { return .reverseByType(["granddaughter_of"]) }
        if query.contains("아버지") || query.contains("부친") { return .reverseByType(["father_of"]) }
        if query.contains("어머니") || query.contains("모친") { return .reverseByType(["mother_of"]) }
        // "아내" 동의어 중 "처"는 한 글자라 "처음"/"처녀"/"출처" 등에 오탐되어 제외했다.
        // Layer 1(`QueryIntentClassifier.isRelationQuery`)이 넓게 잡으므로 여기서 좁게 잡아도
        // 최악의 경우 아래 폴백으로 떨어질 뿐이다.
        if query.contains("아내") || query.contains("부인") { return .reverseByType(["wife_of"]) }
        if query.contains("남편") { return .reverseByType(["husband_of"]) }
        return nil
    }

    // MARK: - 인물 프로필 / 주제 (키워드·카테고리 조회, personOrPlaceInfo 대체)

    /// `KeywordCategoryIndex`(등록된 인물/주제 표제어)에 질의와 일치하는 표제어가 있는지 먼저
    /// 확인하고, 카테고리에 맞는 저장소(`persons(mentionedIn:)`/`themes(matching:)`)를
    /// 조회한다. 못 찾으면 `personCategoryAIFallback`으로 넘어간다 — 규칙 기반이 먼저이고
    /// AI는 실패했을 때만 보조로 쓴다. 장소는 `KeywordCategoryIndex`가 '인물'/'주제'만 갖고
    /// 있어(Places 콘텐츠 미준비) 반환하지 않는다.
    /// 문서 확정) 이 메서드가 장소를 반환할 일이 구조적으로 없다.
    private static func handleKeywordCategoryLookup(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        let categories = (try? store.keywordCategories(mentionedIn: query)) ?? []

        if categories.contains("인물") {
            let persons = (try? store.persons(mentionedIn: query)) ?? []
            if !persons.isEmpty {
                return QueryIntentCard(intent: .personProfile, status: .found(.personProfile(persons)))
            }
        }
        if categories.contains("주제") {
            let themes = (try? store.themes(matching: query)) ?? []
            if !themes.isEmpty {
                return QueryIntentCard(intent: .themeOrAttribute, status: .found(.theme(themes)))
            }
        }
        if !categories.isEmpty {
            // 인덱스엔 걸렸지만 콘텐츠 조회가 빈 배열인 드문 불일치(예: 대응 행이 그 사이 지워짐) —
            // 카테고리는 이미 알아냈으므로 AI 보완 없이 준비중 카드로 안내한다.
            return QueryIntentCard(intent: .personProfile, status: .notReady(
                message: "이 표제어는 등록돼 있으나 상세 콘텐츠를 찾지 못했습니다. 아래 검색 결과를 확인해 보세요."
            ))
        }

        return personCategoryAIFallback(query, store: store)
    }

    /// 규칙 기반으로 못 찾았을 때의 Apple Intelligence 폴백 자리 — 미구현이라 항상 nil.
    /// 검증되지 않은 `@Generable`/`@Guide` 호출을 넣지 않으려고 자리만 두었으며,
    /// FoundationModels 문서와 대조해 실제 구현을 채워야 한다.
    private static func personCategoryAIFallback(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        nil
    }

    // MARK: - 예언

    private static func handleProphecy(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        let matches = (try? store.prophecies(matching: query)) ?? []
        guard !matches.isEmpty else {
            return QueryIntentCard(intent: .prophecy, status: .notReady(
                message: "예언 데이터가 아직 준비되지 않았거나, 이 질의와 일치하는 항목이 없습니다. 아래 검색 결과를 확인해 보세요."
            ))
        }
        return QueryIntentCard(intent: .prophecy, status: .found(.prophecy(matches)))
    }

    // MARK: - 주제·속성·교리·유명 본문

    private static func handleTheme(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        let matches = (try? store.themes(matching: query)) ?? []
        guard !matches.isEmpty else {
            return QueryIntentCard(intent: .themeOrAttribute, status: .notReady(
                message: "주제·속성 데이터가 아직 준비되지 않았거나, 이 질의와 일치하는 항목이 없습니다. 아래 검색 결과를 확인해 보세요."
            ))
        }
        return QueryIntentCard(intent: .themeOrAttribute, status: .found(.theme(matches)))
    }

    // MARK: - 내용 추적·서사

    private static func handleNarrative(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        let events = (try? store.timelineEvents(narrativeMentionedIn: query)) ?? []
        guard !events.isEmpty else {
            return QueryIntentCard(intent: .narrative, status: .notReady(
                message: "서사·흐름 데이터가 아직 준비되지 않았거나, 이 질의와 일치하는 항목이 없습니다. 아래 검색 결과를 확인해 보세요."
            ))
        }
        return QueryIntentCard(intent: .narrative, status: .found(.narrative(groupByNarrative(events))))
    }

    private static func groupByNarrative(_ events: [TimelineEventRecord]) -> [NarrativeGroup] {
        var groups: [NarrativeGroup] = []
        for event in events {
            if let lastIndex = groups.indices.last, groups[lastIndex].narrativeKey == event.narrativeKey {
                groups[lastIndex] = NarrativeGroup(
                    narrativeKey: groups[lastIndex].narrativeKey,
                    narrativeTitle: groups[lastIndex].narrativeTitle,
                    events: groups[lastIndex].events + [event]
                )
            } else {
                groups.append(NarrativeGroup(narrativeKey: event.narrativeKey, narrativeTitle: event.narrativeTitle, events: [event]))
            }
        }
        return groups
    }
}

/// `PersonRelations.relation_type`(예: `younger_brother_of`)을 사람이 읽을 문장으로 바꾼다.
///
/// `pattern_label` 컬럼은 정규식 매치를 기록하는 개발용 메모라 화면에 노출하기 어색해
/// 재사용하지 않고, 고정 어휘인 `relation_type`으로 화면 전용 문장을 하드코딩 매핑한다.
///
/// 방향 규칙: 모든 relation_type은 "source가 target의 ROLE"(예: `(라흐미,
/// younger_brother_of, 골리앗)` == "라흐미는 골리앗의 아우"). 단 `tribe_of`/`people_of`/
/// `affiliated_with_place`는 반대로 "source가 target 소속"이다.
enum PersonRelationLabeling {
    // 조사는 받침 유무로 정한다: source 뒤 은/는, `married_to`/`related_to`의 target 뒤 와/과
    // ("의"는 받침과 무관). 완성형 한글 음절(U+AC00~U+D7A3)은 `(코드값 - 0xAC00) % 28`이
    // 0이 아니면 받침이 있다. 한글 음절이 아닌 문자로 끝나면 판정 불가이므로 "는"/"와"로
    // 폴백한다.
    private static func hasBatchim(_ text: String) -> Bool? {
        guard let last = text.unicodeScalars.last else { return nil }
        let value = last.value
        guard value >= 0xAC00, value <= 0xD7A3 else { return nil }
        return (value - 0xAC00) % 28 != 0
    }

    private static func eunNeun(after text: String) -> String {
        (hasBatchim(text) ?? false) ? "은" : "는"
    }

    private static func gwaWa(after text: String) -> String {
        (hasBatchim(text) ?? false) ? "과" : "와"
    }

    static func sentence(for relation: PersonRelationRecord) -> String {
        let source = relation.sourceWord
        let target = relation.targetWord
        let sourceEunNeun = eunNeun(after: source)
        switch relation.relationType {
        case "son_of": return "\(source)\(sourceEunNeun) \(target)의 아들"
        case "daughter_of": return "\(source)\(sourceEunNeun) \(target)의 딸"
        case "grandson_of": return "\(source)\(sourceEunNeun) \(target)의 손자"
        case "granddaughter_of": return "\(source)\(sourceEunNeun) \(target)의 손녀"
        case "grandfather_of": return "\(source)\(sourceEunNeun) \(target)의 할아버지"
        // 아래 default 폴백만으로도 동작하지만, 자연스러운 한국어 문장을 위해 각 타입을 명시한다.
        case "grandmother_of": return "\(source)\(sourceEunNeun) \(target)의 할머니"
        case "maternal_grandfather_of": return "\(source)\(sourceEunNeun) \(target)의 외할아버지"
        case "maternal_grandmother_of": return "\(source)\(sourceEunNeun) \(target)의 외할머니"
        case "co_worker_of": return "\(source)\(sourceEunNeun) \(target)의 동역자"
        case "father_of": return "\(source)\(sourceEunNeun) \(target)의 아버지"
        case "mother_of": return "\(source)\(sourceEunNeun) \(target)의 어머니"
        case "wife_of": return "\(source)\(sourceEunNeun) \(target)의 아내"
        case "husband_of": return "\(source)\(sourceEunNeun) \(target)의 남편"
        case "daughter_in_law_of": return "\(source)\(sourceEunNeun) \(target)의 며느리"
        case "father_in_law_of": return "\(source)\(sourceEunNeun) \(target)의 장인"
        case "son_in_law_of": return "\(source)\(sourceEunNeun) \(target)의 사위"
        case "great_grandfather_of": return "\(source)\(sourceEunNeun) \(target)의 증조부"
        case "adversary_of": return "\(source)\(sourceEunNeun) \(target)의 대적"
        case "ally_of": return "\(source)\(sourceEunNeun) \(target)의 동맹"
        case "related_to": return "\(source)\(sourceEunNeun) \(target)\(gwaWa(after: target)) 관련 있음"
        case "brother_of": return "\(source)\(sourceEunNeun) \(target)의 형제"
        case "younger_brother_of": return "\(source)\(sourceEunNeun) \(target)의 아우"
        case "older_brother_of": return "\(source)\(sourceEunNeun) \(target)의 형"
        case "sister_of": return "\(source)\(sourceEunNeun) \(target)의 자매"
        case "uncle_of": return "\(source)\(sourceEunNeun) \(target)의 삼촌"
        case "cousin_of": return "\(source)\(sourceEunNeun) \(target)의 사촌"
        case "descendant_of": return "\(source)\(sourceEunNeun) \(target)의 후손"
        case "ancestor_of": return "\(source)\(sourceEunNeun) \(target)의 조상"
        case "teacher_of": return "\(source)\(sourceEunNeun) \(target)의 스승"
        case "king_of": return "\(source)\(sourceEunNeun) \(target)의 왕"
        case "married_to": return "\(source)\(sourceEunNeun) \(target)\(gwaWa(after: target)) 결혼한 사이"
        case "friend_of": return "\(source)\(sourceEunNeun) \(target)의 친구"
        case "tribe_of": return "\(source)\(sourceEunNeun) \(target) 지파 소속"
        case "people_of": return "\(source)\(sourceEunNeun) \(target) 족속 소속"
        case "affiliated_with_place": return "\(source)\(sourceEunNeun) \(target) 사람(출신)"
        default:
            // 방어적 폴백 — 새 relation_type이 매핑에 없어도 값을 숨기지 않고 밑줄→공백만 적용해 보여준다.
            let cleaned = relation.relationType.replacingOccurrences(of: "_", with: " ")
            return "\(source) - \(cleaned) - \(target)"
        }
    }
}
