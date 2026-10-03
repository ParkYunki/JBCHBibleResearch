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

/// `QueryIntentCard.Content.entityProfile`의 항목 하나 — 인물 또는 장소.
enum ProfileItem {
    case person(PersonEntity)
    case place(PlaceEntity)

    var verseRefs: [BibleVerseRef] {
        switch self {
        case .person(let person): return person.verseRefs
        case .place(let place): return place.verseRefs
        }
    }
}

/// Handler 조회 결과 하나 — 카테고리(`intent`)와 상태(`status`).
struct QueryIntentCard {
    enum Content {
        case relation([RelationDisplayItem])
        /// `PersonEntity`(보강 컬럼 + 관계 리스트) 기반 — 장소는 포함하지 않는다(콘텐츠 미준비).
        case personProfile([PersonEntity])
        /// 장소(`PlaceEntity`)가 걸린 질의 — 같은 이름의 인물이 있으면 함께 담는다(`ProfileItem`).
        case entityProfile([ProfileItem])
        case prophecy([ProphecyRecord])
        case theme([ThemeRecord])
        case narrative([NarrativeGroup])

        /// 이 카드가 가리키는 성경 좌표 전체 — 화면 순서 그대로, 중복 제거.
        /// `SearchViewModel.applyIntentCardVerses`가 "성경구절" 섹션에 직접 채워, 카드가 이미
        /// 답을 확정한 경우 별도의 키워드 검색 결과가 섞이지 않게 한다.
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
            case .entityProfile(let items):
                return dedup(items.flatMap { $0.verseRefs })
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
            case .entityProfile(let items): return items.count
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

        // "예수님의 (열두) 제자(들)" — 일반 인물 조회보다 먼저 확인한다. 안 그러면 질의 속 "예수"만 걸려 예수 한 사람의
        // 카드가 나온다. 관계/키워드 분류와 무관하게 질의 문구만으로 판정한다.
        if let card = handleGroupLookup(query, store: store) {
            return card
        }

        // 지명 질의 — 질의가 지명 이름 중심일 때만(`handlePlaceLookup` 참고). 관계/예언/주제 등으로 분류된 질의는
        // 건드리지 않아, "…에 대한 말씀" 같은 질의가 지명 카드에 가려지지 않는다.
        if intent == .general, let card = handlePlaceLookup(query, store: store) {
            return card
        }

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
        case .placeProfile: return nil
        case .general: return nil
        }
    }

    // MARK: - 장소 (PlaceSeed.json)

    /// 질의에서 이름 말고 남는 "조회 말" — 이런 말만 덧붙은 질의("가나 위치", "가나는 어디?")도 지명 질의로 본다.
    private static let placeLookupFillers = [
        "어디에있어", "어디있어", "어디에", "어디", "위치", "지리", "역사", "소개", "정보", "에대해서", "에대해", "에대하여",
        "알려줘", "알려주세요", "설명해줘", "설명", "이란", "란", "은", "는", "이", "가", "의", "?", "？", "."
    ]

    /// 이름 중심의 지명 질의면 카드를 돌려준다. 판정:
    ///  1) `places(mentionedIn:)`로 질의에 이름이 든 지명을 찾는다(동명이인은 모두).
    ///  2) 조회 말(위 목록)을 뺀 질의에서 가장 긴 지명 이름이 차지하는 비율이 절반 이상이어야 한다 — 질의 속에 우연히
    ///     지명과 같은 글자가 있을 뿐인 문장("광야 40년의 의미")이 일반 검색 결과를 가리지 않도록.
    ///  3) 같은 이름의 인물이 함께 걸리면 한 카드에 같이 보여준다(예: "가나안" — 인물과 땅). 더 긴 이름 안에 포함돼
    ///     삼켜지는 쪽은 뺀다.
    /// 지명이 하나도 남지 않으면 nil(일반 흐름 계속 — 인물 조회는 이후 단계가 맡는다).
    private static func handlePlaceLookup(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        let places = (try? store.places(mentionedIn: query)) ?? []
        guard !places.isEmpty else { return nil }

        var residual = query.filter { !$0.isWhitespace }
        for filler in placeLookupFillers.sorted(by: { $0.count > $1.count }) {
            residual = residual.replacingOccurrences(of: filler, with: "")
        }
        // 위에서 조회 말로 이름 일부가 지워졌을 수 있어(예: "이스라엘"의 "이") 비율 계산은 지우기 전 길이가 아니라
        // 조회 말을 뺀 질의 길이로 하되, 이름이 질의에 그대로 들어 있는지는 이미 `places(mentionedIn:)`가 확인했다.
        let compactQuery = query.filter { !$0.isWhitespace }
        let longestName = places.map { $0.word.filter { !$0.isWhitespace }.count }.max() ?? 0
        let denominator = max(residual.count, longestName)
        guard denominator > 0, Double(longestName) / Double(denominator) >= 0.5, longestName <= compactQuery.count else {
            return nil
        }

        let persons = (try? store.persons(mentionedIn: query)) ?? []
        func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        let placeNames = places.map { compact($0.word) }
        let personNames = persons.map { compact($0.matchedAlias ?? $0.word) }
        let keptPersons = persons.filter { person in
            let name = compact(person.matchedAlias ?? person.word)
            return !placeNames.contains { $0.count > name.count && $0.contains(name) }
        }
        let keptPlaces = places.filter { place in
            let name = compact(place.word)
            return !personNames.contains { $0.count > name.count && $0.contains(name) }
        }
        guard !keptPlaces.isEmpty else { return nil }

        let items = keptPersons.map(ProfileItem.person) + keptPlaces.map(ProfileItem.place)
        return QueryIntentCard(intent: .placeProfile, status: .found(.entityProfile(items)))
    }

    // MARK: - 그룹 (예수님의 열두 제자)

    /// `PersonGroups.group_id` — `build_reference_data.py`의 `GROUP_LABEL_DEFS`와 같은 원문 라벨.
    private static let twelveDisciplesGroupId = "열두 제자"

    /// 질의가 "예수님의 제자(들)" 또는 "예수님의 열두 제자(들)"(열두제자, 12제자 포함)를 가리키는지 판정한다.
    ///
    /// 오판을 막기 위해 아래 경우는 일부러 제외하고 일반 검색 흐름에 맡긴다:
    ///  - "엘리사의 제자들", "세례 요한의 제자" 등 제자의 주인이 예수가 아닌 경우(`…의 제자` 바로 앞 단어로 판단).
    ///  - "예수님의 제자 베드로"처럼 열두 제자 중 특정 인물 이름이 함께 들어간 경우(그 인물을 찾는 질의).
    ///  - "제자훈련", "제자도" 등 제자 자체가 아니라 주제를 묻는 말.
    /// 판정 근거는 공백을 모두 뺀 문자열이므로 "열두 제자"/"열두제자"/"12 제자"를 구분하지 않는다.
    static func isTwelveDisciplesQuery(_ query: String, memberNames: [String]) -> Bool {
        let compact = query.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard compact.contains("제자") else { return false }

        let mentionsTwelve = compact.contains("열두") || compact.contains("12") || compact.contains("십이")
        let mentionsJesus = compact.contains("예수") || compact.contains("그리스도")
        guard mentionsTwelve || mentionsJesus else { return false }

        // 제자 자체가 아니라 신앙 주제를 묻는 표현.
        let topicalSuffixes = ["제자훈련", "제자도", "제자삼", "제자양육", "제자화", "제자의삶", "제자의길"]
        if topicalSuffixes.contains(where: { compact.contains($0) }) { return false }

        // "<주인>의 제자" — 주인이 예수(님)/그리스도/주님이 아니면 그 사람의 제자들 질의다.
        var searchRange = compact.startIndex..<compact.endIndex
        while let hit = compact.range(of: "의제자", range: searchRange) {
            let owner = String(compact[compact.startIndex..<hit.lowerBound])
            let jesusOwners = ["예수", "예수님", "그리스도", "그리스도님", "주님"]
            if !jesusOwners.contains(where: { owner.hasSuffix($0) }) { return false }
            searchRange = hit.upperBound..<compact.endIndex
        }

        // 특정 제자 이름이 들어 있으면 그 사람을 찾는 질의다(2글자 미만 이름은 오탐이 커 제외).
        if memberNames.contains(where: { $0.count >= 2 && compact.contains($0) }) { return false }
        return true
    }

    /// 열두 제자 그룹 카드 — 멤버 12명을 `person(idx:)`로 확정해 인물 카드 목록(`.personProfile`)으로 보여준다.
    /// 그룹 데이터가 없거나 질의가 해당하지 않으면 nil(일반 흐름으로 계속).
    private static func handleGroupLookup(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        let members = (try? store.personGroupMembers(groupId: twelveDisciplesGroupId)) ?? []
        guard !members.isEmpty else { return nil }
        let names = members.flatMap { [$0.word] + $0.aliases }
        guard isTwelveDisciplesQuery(query, memberNames: names) else { return nil }
        return QueryIntentCard(intent: .personProfile, status: .found(.personProfile(members)))
    }

    // MARK: - 관계

    /// 정방향(질의의 이름이
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

        // "OO의 형/동생/아우" — 방향과 손위·손아래를 구분해야 해서 아래 일반 흐름과 따로 처리한다(`handleSibling` 참고).
        // 다른 관계 어휘(아들/아버지 등)가 함께 있으면 기존 흐름에 맡긴다.
        if detectRelationSubQuery(query) == nil, let role = detectSiblingRole(query) {
            return handleSibling(query, role: role, targetRows: reverseRows, store: store)
        }

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

    // MARK: - 형제(형/동생/아우) 질의 (2026-10-02)
    //
    // 증상: "골리앗의 동생/아우"와 "라흐미의 형"은 결과가 없었고, "라흐미의 동생"은 질의와 반대 방향 행
    // ("골리앗은 라흐미의 형")이 답처럼 나왔다. 원인 셋:
    //  1) 분류기가 "형"을 관계어로 인식하지 못함(`QueryIntentClassifier.containsElderBrotherWord`로 해결).
    //  2) 이름 조회를 `personsAndPlaces`(Persons/Places 등록 이름)로만 해서, PersonSeed에 "골리앗#0"처럼 미상으로만 적힌
    //     이름(골리앗)은 질의에 있어도 관계 조회가 시작되지 않음(`personRelations(sourceWordMentionedIn:)` 신설로 해결).
    //  3) 형/동생에 대한 하위 질의가 없어 "관계 타입 미지정 폴백"이 해당 인물의 모든 행을 방향 무시하고 보여줌.
    // 관계 행은 "source가 target의 ROLE"(예: 골리앗 older_brother_of 라흐미 = 골리앗은 라흐미의 형)이므로, 같은 사실이
    // 반대 어휘로도 질의된다: "골리앗의 동생" → 저장된 (골리앗 older_brother_of 라흐미)를 뒤집어 (라흐미 younger_brother_of 골리앗)로 답한다.

    private enum SiblingRole {
        case younger  // 동생/아우/남동생
        case older    // 형

        /// 질의가 찾는 역할(`source가 target의 ROLE`의 ROLE)과 그 반대 역할의 relation_type.
        var role: String { self == .younger ? "younger_brother_of" : "older_brother_of" }
        var inverse: String { self == .younger ? "older_brother_of" : "younger_brother_of" }
    }

    /// 손위/손아래 형제 질의인지 감지한다. "여동생"은 자매(`sister_of`)라 제외하고, 형과 동생이 함께 있으면(모호) nil.
    private static func detectSiblingRole(_ query: String) -> SiblingRole? {
        let withoutSister = query.replacingOccurrences(of: "여동생", with: "")
        let younger = withoutSister.contains("동생") || withoutSister.contains("아우")
        let older = QueryIntentClassifier.containsElderBrotherWord(withoutSister)
        if younger == older { return nil }  // 둘 다 true(모호) 또는 둘 다 false
        return younger ? .younger : .older
    }

    /// "OO의 형/동생"(OO=소유자, 기본)과 "OO가 형/동생인 사람"(OO=역할 보유자, 이름 뒤 "이/가") 모두 처리한다.
    /// 저장 행은 항상 `RelationDisplayItem`에 "역할 보유자 → 소유자" 방향으로 정리해, 화면 문장이 "A는 B의 형/아우"로 읽히게 한다.
    /// 일치하는 행이 없으면 다른 관계로 폴백하지 않는다 — 폴백이 질의와 반대되는 사실을 답처럼 보여줬기 때문이다.
    private static func handleSibling(
        _ query: String, role: SiblingRole, targetRows: [PersonRelationRecord], store: ReferenceDataStore
    ) -> QueryIntentCard {
        let sourceRows = (try? store.personRelations(sourceWordMentionedIn: query)) ?? []

        var items: [RelationDisplayItem] = []
        var seen = Set<String>()
        /// `holder`가 `owner`의 ROLE인 사실 하나를 추가한다. 답은 질의에 없는 쪽(`answer`)이고 그 인물의 구절을 붙인다.
        func append(holder: String, owner: String, answer: String, template: PersonRelationRecord) {
            let key = "\(holder)|\(role.role)|\(owner)"
            guard seen.insert(key).inserted else { return }
            // 뒤집은 행의 `targetKind`는 알 수 없어 nil(원래 방향이면 원래 값). `PersonRelationRecord.targetKind` 주석 참고.
            let flipped = holder != template.sourceWord
            let record = PersonRelationRecord(
                sourceWord: holder, relationType: role.role, targetWord: owner,
                targetKind: flipped ? nil : template.targetKind,
                rawSentence: template.rawSentence,
                targetIdx: flipped ? "" : template.targetIdx,
                sourceIdx: flipped ? template.targetIdx : template.sourceIdx
            )
            // 답 인물이 Persons에 없으면(예: 골리앗) 질의에 쓴 인물(소유자)의 구절로 대신한다.
            let ownerWord = answer == holder ? owner : holder
            let verses = (try? store.personOrPlace(exactWord: answer))?.verseRefs
                ?? (try? store.personOrPlace(exactWord: ownerWord))?.verseRefs ?? []
            items.append(RelationDisplayItem(relation: record, verseRefs: verses))
        }

        // 질의 속 이름이 target인 행(저장 방향: source가 target의 ROLE)
        for row in targetRows {
            let nameIsHolder = subjectDirection(for: row.targetWord, in: query) == true
            if !nameIsHolder {
                // "OO(=target)의 ROLE" — 같은 역할로 저장된 행이면 source가 답.
                if row.relationType == role.role {
                    append(holder: row.sourceWord, owner: row.targetWord, answer: row.sourceWord, template: row)
                }
            } else if row.relationType == role.inverse {
                // "OO(=target)가 ROLE인 사람" — 반대 역할로 저장된 행(source가 OO의 반대 역할)을 뒤집어 OO가 보유자.
                append(holder: row.targetWord, owner: row.sourceWord, answer: row.sourceWord, template: row)
            }
        }
        // 질의 속 이름이 source인 행
        for row in sourceRows {
            let nameIsHolder = subjectDirection(for: row.sourceWord, in: query) == true
            if !nameIsHolder {
                // "OO(=source)의 ROLE" — OO가 반대 역할로 저장된 행(예: 골리앗 older_brother_of 라흐미)을 뒤집어 target이 답.
                if row.relationType == role.inverse {
                    append(holder: row.targetWord, owner: row.sourceWord, answer: row.targetWord, template: row)
                }
            } else if row.relationType == role.role {
                // "OO(=source)가 ROLE인 사람" — 같은 역할로 저장된 행이면 target이 답.
                append(holder: row.sourceWord, owner: row.targetWord, answer: row.targetWord, template: row)
            }
        }

        guard !items.isEmpty else {
            let label = role == .younger ? "동생/아우" : "형"
            return QueryIntentCard(intent: .relation, status: .notReady(
                message: "질의한 \(label) 관계가 등록돼 있지 않습니다. 아래 검색 결과를 확인해 보세요."
            ))
        }
        return QueryIntentCard(intent: .relation, status: .found(.relation(items)))
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
    /// 조회한다. 못 찾으면 nil을 돌려준다. 장소는 `KeywordCategoryIndex`가 '인물'/'주제'만 갖고
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
            // 카테고리는 이미 알아냈으므로 추가 보완 없이 준비중 카드로 안내한다.
            return QueryIntentCard(intent: .personProfile, status: .notReady(
                message: "이 표제어는 등록돼 있으나 상세 콘텐츠를 찾지 못했습니다. 아래 검색 결과를 확인해 보세요."
            ))
        }

        return nil
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

    /// 관계 행의 "원문" 표시용 — PersonSeed 기타관계 원문("골리앗#0(형)")에 붙은 `#idx` 태그(`#0`=미상 포함)는
    /// 빌드용 식별자라 사용자에게 보이지 않게 지운다(→ "골리앗(형)"). 태그가 없는 문장은 그대로다.
    static func displayRawSentence(_ raw: String) -> String {
        raw.replacingOccurrences(of: "#[0-9]+", with: "", options: .regularExpression)
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
