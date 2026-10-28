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
    /// 이 행에서 "새로 알게 된 쪽"(예: "갓은 야곱의 아들"에서 갓) 이름과 그 `Persons.idx`(확정 안 됐으면 빈 문자열).
    /// 행을 눌렀을 때 관계 상세 대신 이 인물의 상세를 열기 위한 값이다. 비어 있으면 호출부는 관계 상세로 폴백한다.
    var answerWord: String = ""
    var answerIdx: String = ""
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

        // [2026-10-22 2차] 비한국어 앱의 한글 없는 질의는 번역 경로만 탄다 — 받는 꼴은 "이름 그대로"와 "관계 꼴"(sons of X 등)
        // 두 가지뿐이고, 그 밖(문장형 질문 등)은 nil(카드 없음 → 일반 검색). 1차(같은 날)에는 한국어 데이터 경로를 먼저 돌리고
        // 못 찾으면 번역 경로를 붙였는데, 한글 없는 질의는 한국어 데이터 경로에서 걸리는 것이 없다(Persons/Places/
        // KeywordCategoryIndex/PersonRelations 이름과 분류기 트리거가 모두 한글 — 2026-10-22 DB 실측). 그래서 그 결과를 버려도
        // 지금 데이터로는 달라지는 질의가 없고, 엄격한 꼴 제한을 한 곳에서 판정할 수 있다.
        // 한국어 앱, 그리고 비한국어 앱의 한글 질의는 예전처럼 한국어 데이터 경로다(사용자 확정: "한국어 검색 동작은 모든 언어에서 그대로").
        if !AppLanguage.isKorean, !containsHangul(query) {
            return handleTranslatedQuery(query, store: store)
        }
        return handleWithKoreanData(query, intent: intent, store: store)
    }

    /// 기존 `handle` 본문 그대로(한국어 데이터 기준 조회) — 2026-10-22 번역 이름 검색을 덧붙이려고 함수로만 분리했다.
    private static func handleWithKoreanData(
        _ query: String, intent: QueryIntentClassifier.Intent, store: ReferenceDataStore
    ) -> QueryIntentCard? {
        // "예수님의 (열두) 제자(들)" — 일반 인물 조회보다 먼저 확인한다. 안 그러면 질의 속 "예수"만 걸려 예수 한 사람의
        // 카드가 나온다. 관계/키워드 분류와 무관하게 질의 문구만으로 판정한다.
        if let card = handleGroupLookup(query, store: store) {
            return card
        }

        // [2026-10-22 3차] 관계로 분류됐지만 "X의 <관계어>[들]" 꼴이 아닌 질의. 관계 카드는 내지 않고(아래 switch), 이름 그대로인
        // 질의만 아래 지명·인물 조회로 받는다 — 이름에 관계어가 든 인물/지명("벤아비나답"의 "아비", "빈누이"의 "누이",
        // "롯의 큰 딸")이 이름 질의로 카드를 받게. 두 조회 모두 질의 전체가 이름일 때만 카드를 내므로 "다윗 아내"/"유다 지파"는 nil이다.
        let isUnshapedRelationQuery = intent == .relation && QueryIntentClassifier.koreanRelationShapeNames(query) == nil

        // 지명 질의 — 질의 전체가 지명(·인물) 이름일 때만(`handlePlaceLookup` 참고). 관계(꼴 맞음)/예언/주제 등으로 분류된 질의는
        // 건드리지 않아, "…에 대한 말씀" 같은 질의가 지명 카드에 가려지지 않는다.
        if intent == .general || isUnshapedRelationQuery, let card = handlePlaceLookup(query, store: store) {
            return card
        }

        // `QueryIntentClassifier` 우선순위상 관계 다음 자리. DB 접근이 필요해 classify()(순수
        // 함수)가 아니라 여기서 수행한다. `.relation`으로 확정된 경우는 아래 switch가 처리하므로
        // 건너뛰고(꼴이 맞지 않는 관계 질의는 위 주석대로 시도한다), `.general`이어도 시도한다 — "다윗"처럼 트리거 문구 없는
        // 표제어 질의도 등록된 인물/주제 키워드는 잡아야 한다.
        if intent != .relation || isUnshapedRelationQuery, let card = handleKeywordCategoryLookup(query, store: store) {
            return card
        }

        guard intent != .general else { return nil }
        // [2026-10-22 3차] 한국어 문장형 질의 금지(사용자 확정) — 관계 카드는 질의 전체가 "X의 <관계어>[들]" 꼴일 때만,
        // 예언/주제/서사 안내 카드는 질의 전체가 트리거 낱말일 때만 낸다. 그 밖은 nil(카드 없음 → `SearchViewModel`이 키워드 검색).
        // 분류(`classify`) 자체는 그대로라 "다윗 아내"/"유다 지파"/"처음 사랑"은 여전히 관계로 분류되지만 여기서 nil이 된다.
        switch intent {
        case .relation:
            guard !isUnshapedRelationQuery else { return nil }
            // [2026-10-22 4차] X가 인물이 아니면("하나님의 아들", "사람의 아들", "믿음의 아들") 관계 카드(안내 카드 포함)를 내지 않는다
            // (사용자 확정). X가 인물인지는 관계 경로가 찾는 이름과 같은 범위로 본다(`ReferenceDataStore.isRelationPersonName` —
            // Persons 대표 이름·별칭 + 관계 행 이름). X가 여럿이면 하나라도 인물이면 된다.
            let owners = QueryIntentClassifier.koreanRelationShapeNames(query) ?? []
            guard owners.contains(where: { (try? store.isRelationPersonName($0)) == true }) else { return nil }
            // [2026-10-27 6차] 답 순서 = 답 인물의 성경 첫 등장 순(사용자 확정). 관계 답을 내는 모든 경로(형/동생·형제·삼촌·조카·
            // 동역자 포함)가 `handleRelation` 하나를 지나고, 번역 관계 질의도 이 함수를 다시 타므로 여기 한 곳에서 정렬한다.
            // [7차] 같은 답 인물이 두 줄(부모 쪽 행과 자녀 쪽 행, 이름 행과 idx 행 등)이면 한 줄로 줄인 뒤 정렬한다.
            return sortedRelationAnswers(dedupedRelationAnswers(handleRelation(query, store: store), store: store), store: store)
        case .prophecy:
            guard QueryIntentClassifier.isWholeQueryTriggerTerm(query, for: .prophecy) else { return nil }
            return handleProphecy(query, store: store)
        case .themeOrAttribute:
            guard QueryIntentClassifier.isWholeQueryTriggerTerm(query, for: .themeOrAttribute) else { return nil }
            return handleTheme(query, store: store)
        case .narrative:
            guard QueryIntentClassifier.isWholeQueryTriggerTerm(query, for: .narrative) else { return nil }
            return handleNarrative(query, store: store)
        // switch가 exhaustive해야 해서 `.personProfile`을 다룬다. classify()는 더 이상 이 값을
        // 반환하지 않고 인물 조회는 위 handleKeywordCategoryLookup이 먼저 시도하므로, 여기
        // 도달하면 `.general`과 같이 nil로 처리한다.
        case .personProfile: return nil
        case .placeProfile: return nil
        case .general: return nil
        }
    }

    // MARK: - 번역 이름 검색 (2026-10-22, 비한국어 앱 전용)

    /// 한글(음절·자모)이 하나라도 있으면 true — 이런 질의는 한국어 데이터 경로만 탄다(`TitleFont.isHangul`과 같은 범위).
    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7AF, 0xD7B0...0xD7FF:
                return true
            default:
                return false
            }
        }
    }

    /// 비한국어 앱의 한글 없는 질의 처리(2026-10-22 2차). 순서는 한국어 경로와 같게 관계 꼴 → 이름 그대로다
    /// (한국어도 "롯의 아내"처럼 관계어가 든 질의는 분류기가 관계로 먼저 확정한다).
    ///  1) 관계 꼴(`translatedRelationQuery`)이고 X가 번역 인물 이름과 정확히 같으면 → 같은 뜻의 한국어 질의 "X의 <관계어>"로
    ///     한국어 경로를 그대로 탄다(`handleTranslatedRelation`). X를 못 찾으면 2)로 넘어간다(예: "Daughter of Putiel"은 그 자체가 인물 이름).
    ///  2) 질의 전체가 번역 이름(여럿이면 공백·쉼표로만 구분)이면 → 인물/지명 카드(`handleTranslatedNameLookup`).
    ///  3) 그 밖은 nil — 카드 없이 일반 검색만 한다("Where is Cana?", "Tell me about David" 등).
    private static func handleTranslatedQuery(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        guard let language = store.contentLanguage else { return nil }
        let trimmed = QueryIntentClassifier.trimmingTrailingQueryPunctuation(query)
        guard !trimmed.isEmpty else { return nil }
        if let relation = translatedRelationQuery(trimmed, language: language),
           let card = handleTranslatedRelation(name: relation.name, koreanRelationWord: relation.koreanRelationWord, store: store) {
            return card
        }
        return handleTranslatedNameLookup(trimmed, store: store)
    }

    // MARK: 비한국어 관계 꼴 (2026-10-22 2차)

    /// (번역 관계어, 같은 뜻의 한국어 관계어). 한국어 쪽은 한국어 관계 처리(`detectRelationSubQuery`/`handleSibling`/폴백)가
    /// 이미 받는 말만 쓴다 — 결과·관계 판정을 한국어와 똑같이 하기 위해서다. 목록은 사용자 지정 그대로다.
    private static let englishRelationWords: [(word: String, korean: String)] = [
        ("son", "아들"), ("sons", "아들"), ("daughter", "딸"), ("daughters", "딸"),
        ("father", "아버지"), ("mother", "어머니"), ("wife", "아내"), ("husband", "남편"),
        ("brother", "형제"), ("brothers", "형제"), ("sister", "자매"), ("sisters", "자매"),
        ("grandson", "손자"), ("grandsons", "손자"), ("granddaughter", "손녀"), ("granddaughters", "손녀"),
        ("grandfather", "할아버지"), ("grandmother", "할머니"),
        // [2026-10-22 4차] 삼촌(한국어 경로의 `.uncle` — 삼촌/숙부/백부/외삼촌을 구분하지 않는다).
        ("uncle", "삼촌"), ("uncles", "삼촌"),
    ]
    private static let spanishRelationWords: [(word: String, korean: String)] = [
        ("hijo", "아들"), ("hijos", "아들"), ("hija", "딸"), ("hijas", "딸"),
        ("padre", "아버지"), ("madre", "어머니"), ("esposa", "아내"), ("mujer", "아내"),
        ("esposo", "남편"), ("marido", "남편"),
        ("hermano", "형제"), ("hermanos", "형제"), ("hermana", "자매"), ("hermanas", "자매"),
        ("nieto", "손자"), ("nietos", "손자"), ("nieta", "손녀"), ("nietas", "손녀"),
        ("abuelo", "할아버지"), ("abuela", "할머니"),
        // [2026-10-22 4차] "tío(s)" — 비교는 발음 구별 기호를 뗀 질의(`foldForNameSearch`)라 "tio(s)"로 적는다.
        ("tio", "삼촌"), ("tios", "삼촌"),
    ]
    private static let chineseRelationWords: [(word: String, korean: String)] = [
        ("儿子", "아들"), ("女儿", "딸"), ("父亲", "아버지"), ("母亲", "어머니"), ("妻子", "아내"), ("丈夫", "남편"),
        ("兄弟", "형제"), ("姐妹", "자매"), ("孙子", "손자"), ("孙女", "손녀"), ("祖父", "할아버지"), ("祖母", "할머니"),
        // [2026-10-22 4차] 叔叔(숙부)·伯父(백부)·舅舅(외삼촌) → 삼촌.
        ("叔叔", "삼촌"), ("伯父", "삼촌"), ("舅舅", "삼촌"),
    ]
    /// 영어 소유격 꼬리 — iOS 기본 키보드는 "스마트 구두점"으로 '를 ’로 바꿔 넣으므로 둘 다 받는다. "'s"를 "'"보다 먼저 본다.
    private static let englishPossessiveSuffixes = ["'s", "’s", "'", "’"]

    /// 질의 전체가 지원하는 관계 꼴이면 (X, 한국어 관계어). 비교는 `ReferenceDataStore.foldForNameSearch`로 접은 질의로 한다
    /// (대소문자·발음 구별 기호 무시, 공백 하나로). 받는 꼴(그 밖은 nil):
    ///  - en: "<rel> of X", "X's <rel>", "X' <rel>"
    ///  - es: "<rel> de X"
    ///  - zh: "X的<rel>"(공백 무시)
    private static func translatedRelationQuery(_ query: String, language: String) -> (name: String, koreanRelationWord: String)? {
        let folded = ReferenceDataStore.foldForNameSearch(query)
        func nonEmpty(_ text: Substring) -> String? {
            let name = text.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        switch language {
        case "zh":
            let compact = folded.filter { !$0.isWhitespace }
            for relation in chineseRelationWords where compact.hasSuffix("的" + relation.word) {
                if let name = nonEmpty(compact.dropLast(relation.word.count + 1)) { return (name, relation.korean) }
            }
            return nil
        case "es":
            for relation in spanishRelationWords where folded.hasPrefix(relation.word + " de ") {
                if let name = nonEmpty(folded.dropFirst(relation.word.count + 4)) { return (name, relation.korean) }
            }
            return nil
        default:
            for relation in englishRelationWords {
                if folded.hasPrefix(relation.word + " of ") {
                    if let name = nonEmpty(folded.dropFirst(relation.word.count + 4)) { return (name, relation.korean) }
                }
                if folded.hasSuffix(" " + relation.word) {
                    let head = folded.dropLast(relation.word.count + 1)
                    for suffix in englishPossessiveSuffixes where head.hasSuffix(suffix) {
                        if let name = nonEmpty(head.dropLast(suffix.count)) { return (name, relation.korean) }
                        break
                    }
                }
            }
            return nil
        }
    }

    /// 비한국어 관계 질의 — X(번역 이름)를 인물 idx → 한국어 이름(`Persons.word`)으로 되돌린 뒤 한국어 질의
    /// "<한국어 이름>의 <한국어 관계어>"를 만들어 한국어 경로(`handleWithKoreanData`)를 그대로 탄다. 그래서 관계 판정·방향·성별 검사·
    /// 폴백·안내 문구가 한국어 질의와 똑같고, 화면 문장은 기존 표시층(`PersonRelationLabeling.localizedSentence`)이 번역한다.
    ///  - X는 대표 번역 이름으로 일치한 인물을 먼저 쓰고, 없을 때만 번역 별칭으로 일치한 인물을 쓴다(예: en "Saul"은 사울만 — 바울의 별칭 Saul은 쓰지 않는다).
    ///  - 한국어 이름이 여러 개면(예: en "Zechariah" → 사가랴/스가리야/스가랴) 쉼표로 이어 한 질의("사가랴, 스가리야, 스가랴의 아들")로
    ///    만든다. 한국어 경로가 여러 인물이 든 질의를 다루는 방식 그대로 — 관계 타입이 맞는 행을 모든 이름에서 먼저 모으고, 하나도 없을 때만
    ///    "관계 타입 미지정 폴백"으로 간다. 이름마다 따로 돌려 합치면 한 이름의 폴백 행(예: 스가리야의 신하 관계)이 다른 이름의 아들 행과 섞인다.
    ///    ([2026-10-27 5차] 폴백은 없어지고 그 자리는 안내 카드다. 여러 이름을 한 질의로 묶는 방식은 그대로다.)
    ///  - X에 해당하는 인물이 없으면 nil(호출부가 이름 그대로 판정으로 넘어간다).
    private static func handleTranslatedRelation(
        name: String, koreanRelationWord: String, store: ReferenceDataStore
    ) -> QueryIntentCard? {
        let resolved = store.translatedPersonIdxs(exactName: name)
        let idxs = resolved.primary.isEmpty ? resolved.alias : resolved.primary
        var koreanWords: [String] = []
        for idx in idxs {
            guard let person = try? store.person(idx: idx), !person.word.isEmpty, !koreanWords.contains(person.word) else { continue }
            koreanWords.append(person.word)
        }
        guard !koreanWords.isEmpty else { return nil }
        // 이 질의는 항상 "X의 <관계어>" 꼴이라 분류기가 관계로 확정하고, 한 글자 이름도 `handleRelation`이 정확 일치로 받는다.
        let koreanQuery = "\(koreanWords.joined(separator: ", "))의 \(koreanRelationWord)"
        return handleWithKoreanData(koreanQuery, intent: QueryIntentClassifier.classify(koreanQuery), store: store)
    }

    // MARK: 이름 그대로 (비한국어·한국어 공용 규칙)

    /// "이름 그대로" 질의에서 이름 사이에 허용하는 구분 문자(공백 외). 한국어 인물 판정(`isKoreanNameOnlyQuery`)도 같은 목록을 쓴다.
    private static let nameSeparators: Set<Character> = [",", "，", "、"]

    /// 번역 이름(대표 이름·별칭, `NameSearchI18n`)으로 인물/지명을 찾아 카드로 만든다. 일치 규칙은
    /// `ReferenceDataStore.translatedNameMatches(in:)` 참고. 카드 모양은 한국어 경로와 같다 — 지명이 있으면
    /// `.entityProfile`(인물 먼저, `handlePlaceLookup`과 같은 순서), 인물만이면 `.personProfile`. 못 찾으면 nil.
    ///
    /// [2026-10-22 2차] 질의 전체가 이름이어야 한다 — 걸린 이름들이 질의 글자(공백 제외)를 **모두** 덮을 때만 카드를 낸다.
    /// 이름 사이 구분은 공백과 쉼표(",", "，", "、")만 허용한다(쉼표는 공백으로 바꾼 뒤 판정). 1차의 "절반 이상 덮음(0.5)" 판정은
    /// 이 조건에 포함되므로(전부 ⊂ 절반 이상) 지웠다 — 그 판정이 막으려던 "the sin of pride"/"amor sin fin"은 이제 덮지 못한
    /// 글자가 있어 그대로 걸러진다.
    private static func handleTranslatedNameLookup(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        let separatorsAsSpaces = String(query.map { nameSeparators.contains($0) ? Character(" ") : $0 })
        let result = store.translatedNameMatches(in: separatorsAsSpaces)
        // coverage는 (덮은 글자 수)/(전체 글자 수)라 전부 덮였을 때만 정확히 1.0이다(같은 정수끼리 나눈 IEEE 754 값).
        guard !result.matches.isEmpty, result.coverage >= 1.0 else { return nil }

        var persons: [PersonEntity] = []
        var places: [PlaceEntity] = []
        for match in result.matches {
            switch match.kind {
            case .person:
                // idx로 확정해 부른다 — 이름으로 다시 찾지 않으므로 동명이인이 섞이지 않는다.
                guard let person = try? store.person(idx: match.idx) else { continue }
                persons.append(match.matchedAlias.map { person.replacingMatchedAlias($0) } ?? person)
            case .place:
                guard let place = try? store.place(idx: match.idx) else { continue }
                places.append(place)
            }
        }
        if !places.isEmpty {
            let items = persons.map(ProfileItem.person) + places.map(ProfileItem.place)
            return QueryIntentCard(intent: .placeProfile, status: .found(.entityProfile(items)))
        }
        guard !persons.isEmpty else { return nil }
        return QueryIntentCard(intent: .personProfile, status: .found(.personProfile(persons)))
    }

    // MARK: - 장소 (PlaceSeed.json)

    /// 질의 전체가 지명(·인물) 이름이면 카드를 돌려준다. 판정:
    ///  1) `places(mentionedIn:)`로 질의에 이름이 든 지명을 찾는다(동명이인은 모두). 한 글자 지명("단", "함", "길")은 질의 전체가
    ///     그 이름일 때만 걸린다(같은 함수 참고 — "판단", "길이"에는 안 걸린다).
    ///  2) 같은 이름의 인물이 함께 걸리면 한 카드에 같이 보여준다(예: "가나안" — 인물과 땅, "단" — 인물 단과 지명 단). 더 긴 이름 안에
    ///     포함돼 삼켜지는 쪽은 뺀다.
    ///  3) [2026-10-22 3차] 남은 지명·인물 이름을 질의에서 지웠을 때 남는 글자가 없어야 한다(`isKoreanNameOnlyQuery` — 공백·쉼표·끝의
    ///     "?"/"." 무시). 2차까지의 "조회 말(위치/어디/알려줘 …)을 빼고 이름이 절반 이상" 판정은 지웠다 — "가나 위치", "가나는 어디?",
    ///     "가나에 대해 알려줘"는 이제 카드 없음(한국어 문장형 질의 금지, 사용자 확정).
    /// 해당하지 않으면 nil(일반 흐름 계속 — 인물 조회는 이후 단계가 맡는다).
    private static func handlePlaceLookup(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        // 끝의 "?"/"."를 뗀 질의로 찾는다 — "단?"도 한 글자 지명 정확 일치에 걸리게.
        let trimmed = QueryIntentClassifier.trimmingTrailingQueryPunctuation(query)
        let places = (try? store.places(mentionedIn: trimmed)) ?? []
        guard !places.isEmpty else { return nil }

        let persons = (try? store.persons(mentionedIn: trimmed)) ?? []
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
        let keptNames = keptPlaces.map { $0.word } + keptPersons.map { $0.matchedAlias ?? $0.word }
        guard isKoreanNameOnlyQuery(trimmed, names: keptNames) else { return nil }

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

    /// [2026-10-22 3차] 열두 제자 질의로 받는 명사구 — 끝의 "?"/"."와 공백을 무시한 질의 전체가 아래 꼴일 때만 true
    /// (한국어 문장형 질의 금지, 사용자 확정):
    ///  - "열두 제자(들)", "12제자(들)", "십이제자(들)"
    ///  - "<주인>의 [열두|12|십이] 제자(들)" — 주인은 `twelveDisciplesOwners` 중 하나와 정확히 같아야 하고, 수사가 없으면 주인에
    ///    "예수"/"그리스도"가 들어 있어야 한다(`isTwelveDisciplesQuery`의 기존 조건과 같다 — "주님의 제자"는 예전에도 아니었다).
    /// 예: "예수님의 열두 제자", "예수 그리스도의 열두 제자들", "예수님의 제자" → true.
    /// "예수님의 열두 제자는 누구인가요?", "열두 제자의 이름", "제자" → false.
    /// [2026-10-22 4차] "의"는 없어도 된다("예수님 열두 제자", "주 예수 열두 제자"). 주인 목록에 "주" 붙은 꼴을 더했다
    /// ("주 예수 그리스도의 열두 제자" 등, `twelveDisciplesOwners`). 문장 꼬리("…는 누구인가요?")는 그대로 false다.
    static func isTwelveDisciplesNounPhrase(_ query: String) -> Bool {
        var body = QueryIntentClassifier.trimmingTrailingQueryPunctuation(query)
            .precomposedStringWithCanonicalMapping
            .filter { !$0.isWhitespace }
        if body.hasSuffix("들") { body.removeLast() }
        guard body.hasSuffix("제자") else { return false }
        body.removeLast(2)
        var mentionsTwelve = false
        for numeral in ["열두", "12", "십이"] where body.hasSuffix(numeral) {
            body.removeLast(numeral.count)
            mentionsTwelve = true
            break
        }
        if body.isEmpty { return mentionsTwelve }
        if body.hasSuffix("의") { body.removeLast() }
        guard twelveDisciplesOwners.contains(body) else { return false }
        return mentionsTwelve || body.contains("예수") || body.contains("그리스도")
    }

    /// `isTwelveDisciplesNounPhrase`가 받는 "<주인>[의] …제자"의 주인(공백 뺀 꼴). `isTwelveDisciplesQuery`의 주인 목록 + "예수그리스도".
    /// [2026-10-22 4차] "주" 붙은 꼴: 주예수, 주예수님, 주그리스도, 주예수그리스도("주주님"·"주그리스도님"은 넣지 않았다).
    private static let twelveDisciplesOwners: Set<String> = [
        "예수", "예수님", "그리스도", "그리스도님", "주님", "예수그리스도",
        "주예수", "주예수님", "주그리스도", "주예수그리스도",
    ]

    /// 열두 제자 그룹 카드 — 멤버 12명을 `person(idx:)`로 확정해 인물 카드 목록(`.personProfile`)으로 보여준다.
    /// 그룹 데이터가 없거나 질의가 해당하지 않으면 nil(일반 흐름으로 계속).
    /// [2026-10-22 3차] 명사구 꼴(`isTwelveDisciplesNounPhrase`)을 먼저 본다 — 아니면 DB를 읽지 않고 nil. 기존 판정
    /// (`isTwelveDisciplesQuery`)은 그대로 이어서 적용한다.
    private static func handleGroupLookup(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        guard isTwelveDisciplesNounPhrase(query) else { return nil }
        let members = (try? store.personGroupMembers(groupId: twelveDisciplesGroupId)) ?? []
        guard !members.isEmpty else { return nil }
        let names = members.flatMap { [$0.word] + $0.aliases }
        guard isTwelveDisciplesQuery(query, memberNames: names) else { return nil }
        return QueryIntentCard(intent: .personProfile, status: .found(.personProfile(members)))
    }

    /// 답 인물의 성경 좌표. `idx`가 확정돼 있으면 그 인물 것만 쓴다 — 이름만으로 `personOrPlace(exactWord:)`를 부르면
    /// 동명이인(야고보·요한 등) 중 임의의 한 명(`LIMIT 1`)의 구절이 붙는다(2026-10-21). idx가 없거나 못 찾으면 기존 방식 그대로다.
    private static func answerVerseRefs(word: String, idx: String, store: ReferenceDataStore) -> [BibleVerseRef] {
        if !idx.isEmpty, let person = try? store.person(idx: idx) {
            return person.verseRefs
        }
        return (try? store.personOrPlace(exactWord: word))?.verseRefs ?? []
    }

    /// [2026-10-27 6차] 관계 카드의 답 목록을 답 인물(`answerIdx`, 없으면 `answerWord`가 Persons에서 유일할 때)의 성경 첫 등장 순으로
    /// 정렬한다(`ReferenceDataStore.sortedByFirstAppearance` — 모르는 답은 뒤, 같으면 원래 순서). 안내 카드 등 답 목록이 아닌 카드는 그대로.
    private static func sortedRelationAnswers(_ card: QueryIntentCard, store: ReferenceDataStore) -> QueryIntentCard {
        guard case .found(.relation(let items)) = card.status, items.count > 1 else { return card }
        let sorted = store.sortedByFirstAppearance(items, idx: { $0.answerIdx }, word: { $0.answerWord })
        return QueryIntentCard(intent: card.intent, status: .found(.relation(sorted)))
    }

    /// [2026-10-28 7차] 관계 행 중복 키 — 이름과 idx 모두(`이름#idx|타입|이름#idx`). idx가 빈 행은 같은 이름의 빈 idx 행과만 같다.
    private static func relationRowKey(_ relation: PersonRelationRecord) -> String {
        "\(relation.sourceWord)#\(relation.sourceIdx)|\(relation.relationType)|\(relation.targetWord)#\(relation.targetIdx)"
    }

    /// [2026-10-28 7차] 관계 카드에서 같은 답 인물을 한 줄로 줄인다(사용자 확정).
    /// 같은 인물 판정: 답 `answerIdx`가 있으면 그 idx. 없으면 답 이름이 Persons에서 한 명뿐일 때만 그 사람(`uniquePersonIdx` —
    /// `personGender`·첫 등장 순과 같은 신원 규칙, 동명이인이면 추측하지 않고 이름 그대로 둔다).
    /// 남는 줄은 그 인물이 처음 나온 자리에 놓이고, 문장은 아래 순서로 고른다.
    ///  1) 답 이름이 그 인물의 대표 이름(`Persons.word`)인 줄(예: 세스바살·스룹바벨 = #1586 → 세스바살).
    ///  2) 행에 답 idx가 적힌 줄(같은 이름의 idx 없는 줄보다 먼저).
    ///  3) 답이 주어인 줄(답이 행의 source — 이름과 idx 모두 같을 때. 예: "X의 부모"에서 자녀 쪽 "X는 A의 아들"보다 부모 쪽
    ///     "A는 X의 아버지").
    ///  4) 그래도 같으면 먼저 나온 줄.
    /// 답 이름이 빈 줄은 줄이지 않는다. 안내 카드·답 1개는 그대로. DB 조회는 이름·idx마다 한 번(사전에 둠).
    /// 동명이인 X를 함께 찾은 경우(예: 시므앗이 사밧#3646과 여호사바드#2606의 어머니) 답 인물이 같으면 한 줄이 된다.
    private static func dedupedRelationAnswers(_ card: QueryIntentCard, store: ReferenceDataStore) -> QueryIntentCard {
        guard case .found(.relation(let items)) = card.status, items.count > 1 else { return card }
        var representativeWords: [String: String] = [:]
        func representativeWord(_ idx: String) -> String {
            if let cached = representativeWords[idx] { return cached }
            let word = (try? store.personWord(idx: idx)) ?? ""
            representativeWords[idx] = word
            return word
        }
        var uniqueIdxByWord: [String: String] = [:]
        func identityIdx(_ item: RelationDisplayItem) -> String {
            if !item.answerIdx.isEmpty { return item.answerIdx }
            if let cached = uniqueIdxByWord[item.answerWord] { return cached }
            let idx = (try? store.uniquePersonIdx(word: item.answerWord)) ?? ""
            uniqueIdxByWord[item.answerWord] = idx
            return idx
        }
        func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        /// (대표 이름, 행에 idx, 답이 주어) — 사전식으로 큰 쪽이 남는다.
        func rank(_ item: RelationDisplayItem) -> (Int, Int, Int) {
            let identity = identityIdx(item)
            let isRepresentative = !identity.isEmpty && compact(item.answerWord) == compact(representativeWord(identity))
            let isSubject = item.answerWord == item.relation.sourceWord && item.answerIdx == item.relation.sourceIdx
            return (isRepresentative ? 1 : 0, item.answerIdx.isEmpty ? 0 : 1, isSubject ? 1 : 0)
        }
        var result: [RelationDisplayItem] = []
        var positionByKey: [String: Int] = [:]
        for item in items {
            guard !item.answerWord.isEmpty else {
                result.append(item)
                continue
            }
            let identity = identityIdx(item)
            let key = identity.isEmpty ? "w:\(item.answerWord)" : "#\(identity)"
            if let position = positionByKey[key] {
                if rank(item) > rank(result[position]) { result[position] = item }
            } else {
                positionByKey[key] = result.count
                result.append(item)
            }
        }
        // 줄을 바꾸는 일은 같은 인물이 두 번 나올 때만 생기므로 줄 수가 같으면 입력 그대로다.
        guard result.count != items.count else { return card }
        return QueryIntentCard(intent: card.intent, status: .found(.relation(result)))
    }

    // MARK: - 관계

    /// 정방향(질의의 이름이
    /// source, 예: "다윗의 아들")과 역방향(이름이 target으로만 존재, 예: "골리앗의 동생" —
    /// "골리앗"은 Persons에 행이 없음)을 모두 모은다.
    ///
    /// `detectRelationSubQuery`(질의 부분 문자열)나 `relationSubQuery(forShapeWord:)`("X의 <관계어>"의 관계어)가 정한 관계 타입으로만
    /// 답한다. [2026-10-27 5차] 행이 없으면 어떤 관계어든 안내 카드("질의한 <라벨> 관계가 등록돼 있지 않습니다")다 — 4차까지 아버지/아들 등
    /// 일부 관계어에 남아 있던 "관계 타입 미지정 폴백"(그 인물의 관계 전부 나열)은 지웠다(사용자 확정).
    private static func handleRelation(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        var combined: [RelationDisplayItem] = []
        var seen = Set<String>()
        func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        // `answerFromTarget`이 각 행에서 "새로 알게 된 쪽"(false = source, true = target)을 고르고, 그 인물의 verses를 붙인다.
        // 조회에 실패해도 빈 배열이라 관계 표시 자체는 막히지 않는다.
        // [7차] 예전에는 답 이름을 받아 `answerIdx(of:in:)`(이름이 source와 같으면 source idx)로 idx를 골랐다. 두 이름이 같은 행
        // (예: "요셉 -son_of-> 요셉#4345" — 아들 요셉 항목의 아버지 요셉)에서는 target이 답인데 source idx(빈칸)가 붙어, 같은 답의
        // 한 줄 정리(`dedupedRelationAnswers`)가 그 줄을 다른 사람으로 보았다. 그래서 쪽을 직접 받는다(그 밖의 행은 결과가 같다).
        func add(_ relations: [PersonRelationRecord], answerFromTarget: Bool) {
            for relation in relations {
                // [7차] 키에 idx를 넣는다 — 이름만 쓰면 X idx가 빈(또는 다른) 행이 정확한 idx를 가진 같은 이름 행을 가렸다.
                // idx가 빈 행은 같은 이름의 빈 idx 행끼리만 걸러진다. 같은 인물의 최종 한 줄은 `dedupedRelationAnswers`.
                guard seen.insert(Self.relationRowKey(relation)).inserted else { continue }
                let answer = answerFromTarget ? relation.targetWord : relation.sourceWord
                let answerIdx = answerFromTarget ? relation.targetIdx : relation.sourceIdx
                let verses = Self.answerVerseRefs(word: answer, idx: answerIdx, store: store)
                combined.append(RelationDisplayItem(
                    relation: relation, verseRefs: verses,
                    answerWord: answer, answerIdx: answerIdx
                ))
            }
        }
        /// 배우자 한 명을 (배우자 → 질의 인물) 방향의 wife_of/husband_of 행으로 정리해 더한다(화면 문장 "A는 B의 아내/남편").
        func addSpouse(partnerWord: String, partnerIdx: String, ownerWord: String, ownerIdx: String, answerIsWife: Bool) {
            let record = PersonRelationRecord(
                sourceWord: partnerWord, relationType: answerIsWife ? "wife_of" : "husband_of",
                targetWord: ownerWord, targetKind: .person, rawSentence: "",
                targetIdx: ownerIdx, sourceIdx: partnerIdx
            )
            guard seen.insert(Self.relationRowKey(record)).inserted else { return }
            let verses = Self.answerVerseRefs(word: partnerWord, idx: partnerIdx, store: store)
            combined.append(RelationDisplayItem(
                relation: record, verseRefs: verses, answerWord: partnerWord, answerIdx: partnerIdx
            ))
        }

        // [2026-10-22 2차] 한 글자 이름("함", "셈", "단")은 부분 문자열 조회(2글자 이상)에서 빠지므로, 질의 전체가 "X의 <관계어>" 꼴일 때
        // X 중 한 글자인 이름만 정확 일치로 더한다("함께"/"판단" 같은 낱말 속 글자에는 걸리지 않는다). 그 밖의 질의는 빈 배열이라 예전과 같다.
        let shape = QueryIntentClassifier.koreanRelationShape(query)
        let shortNames = (shape?.names ?? []).filter { $0.count == 1 }
        let ownerNames = Set(shape?.names ?? [])
        let entities = (try? store.personsAndPlaces(mentionedIn: query, shortNamesExactMatch: shortNames)) ?? []
        let personEntities = entities.filter { $0.kind == .person }
        let reverseRows = (try? store.personRelations(targetWordMentionedIn: query, shortNamesExactMatch: shortNames)) ?? []

        // [2026-10-27 5차] 관계 종류는 "X의 <관계어>"의 관계어 하나로 정한다(질의 전체 부분 문자열이 아니라) — X 이름 속 관계어
        // ("롯의 작은 딸의 형제"의 "딸")에 걸리지 않게. 4차까지는 이 경우 엉뚱한 타입으로 조회한 뒤 "관계 전부" 폴백이 가려 줬는데,
        // 폴백을 지우면 "딸 관계가 등록돼 있지 않습니다"가 된다. 기존 관계어는 같은 `detectRelationSubQuery`로 판정하고, 거기 없는
        // 관계어(조카·며느리·오라비 등)는 `relationSubQuery(forShapeWord:)`. 이 함수는 꼴이 맞는 질의만 받으므로 `shape`는 늘 있다
        // (없으면 예전처럼 질의 전체로 판정).
        let relationWord = shape?.word
        let detected: RelationSubQuery?
        if let relationWord = relationWord {
            detected = detectRelationSubQuery(relationWord) ?? relationSubQuery(forShapeWord: relationWord)
        } else {
            detected = detectRelationSubQuery(query)
        }

        // "OO의 형/동생/아우" — 방향과 손위·손아래를 구분해야 해서 아래 일반 흐름과 따로 처리한다(`handleSibling` 참고).
        if detected == nil, let role = detectSiblingRole(relationWord ?? query) {
            return handleSibling(query, role: role, targetRows: reverseRows, shortNames: shortNames, store: store)
        }
        // [2026-10-27 5차] 관계 타입을 정하지 못한 관계 꼴(지금 어휘로는 생기지 않는다 — 관계어마다 타입 또는 안내 카드가 있다)도
        // 관계 전부로 폴백하지 않는다.
        guard let subQuery = detected else {
            return QueryIntentCard(intent: .relation, status: .notReady(
                message: String(localized: "이 질의에서 등록된 인물 관계를 찾지 못했습니다. 아래 검색 결과를 확인해 보세요.")
            ))
        }

        // [2026-10-22 4차] 형제·자매·삼촌 — 질의의 X(공백 무시 정확 일치)가 든 행만 고른다(`handleSiblingGroup`/`handleUncle`).
        // [5차] 오라비·누이(형제·자매와 같은 판정), 조카·후손·증손(정방향), 동역자(양방향), 행 타입이 없는 관계어(안내 카드)도 여기서 끝난다.
        switch subQuery {
        case .sibling(let answerIsMale, let label):
            return handleSiblingGroup(
                query, answerIsMale: answerIsMale, label: label, ownerNames: ownerNames,
                targetRows: reverseRows, shortNames: shortNames, store: store
            )
        case .uncle:
            return handleUncle(ownerNames: ownerNames, targetRows: reverseRows, store: store)
        case .forwardByType(let types, let label):
            return handleOwnerRelationRows(
                query, types: types, label: label, includeReverse: false, ownerNames: ownerNames,
                targetRows: reverseRows, shortNames: shortNames, store: store
            )
        case .mutualByType(let types, let label):
            return handleOwnerRelationRows(
                query, types: types, label: label, includeReverse: true, ownerNames: ownerNames,
                targetRows: reverseRows, shortNames: shortNames, store: store
            )
        case .unregistered(let label):
            return unregisteredRelationCard(label: label)
        case .reverseByType, .parents, .spouse, .grandparent:
            break
        }

        for entity in personEntities {
            // 조사로 방향을 가른다: entity 바로 뒤가 "이/가"(주격)면 entity가 source인 정방향
            // ("노아가 아버지인 사람" → 셈/함/야벳), 그 외(기본 "의")는 역방향("노아의 아버지는?" →
            // 라멕). 아들/딸/손자/아버지/어머니 등 역할이 방향을 가리키는 유형 전부에 같은 이분법이
            // 적용된다.
            func addByType(_ types: [String]) {
                if subjectDirection(for: entity.word, in: query) == true {
                    let forwardRows = (try? store.personRelations(forWord: entity.word)) ?? []
                    add(forwardRows.filter { types.contains($0.relationType) },
                        answerFromTarget: true)
                } else {
                    // "OO의 아들/딸/자녀는?" — source가 OO의 자녀이므로 target=OO 쪽에서 찾는다(역방향).
                    // 답은 source.
                    add(reverseRows.filter { $0.targetWord == entity.word && types.contains($0.relationType) },
                        answerFromTarget: false)
                }
            }
            switch subQuery {
            case .reverseByType(let types, _):
                addByType(types)
            case .grandparent(let type):
                addByType([type])
            case .sibling, .uncle, .forwardByType, .mutualByType, .unregistered:
                break  // 위에서 이미 처리했다(여기 오지 않는다).
            case .parents:
                // "OO의 부모는?" — 부모 항목이 "OO의 아버지/어머니"로 서술된 경우(역방향, 답=source)와
                // OO 항목이 "A와 B 사이의 아들/딸"로 서술된 경우(정방향, 답=target)가 모두 있을 수 있어
                // 합친다.
                add(reverseRows.filter { $0.targetWord == entity.word && ["father_of", "mother_of"].contains($0.relationType) },
                    answerFromTarget: false)
                let forwardRows = (try? store.personRelations(forWord: entity.word)) ?? []
                add(forwardRows.filter { ["son_of", "daughter_of"].contains($0.relationType) },
                    answerFromTarget: true)
            case .spouse(let answerIsWife):
                // 배우자 후보: entity가 source인 행(`forWord`)과 target인 행(`reverseRows`)을 모두 본다(일부는 한쪽만 저장돼 있다).
                // [7차] 행의 X 쪽 idx(forWord 행의 source_idx, reverseRows 행의 target_idx)가 있으면 그 사람이 X다 — 이름이 같은
                // 다른 인물(entity, 예: 갈렙#71)로 바꾸지 않는다(예: 에바#2392 항목의 배우자 "갈렙#243" = 글루배#243). 행에 idx가 없을
                // 때만 entity를 X로 본다. 성별 검사(X가 질의와 모순이면 — 예: "미갈의 아내", 미갈은 여성 — 건너뜀, 모르면 시도)도
                // 그 X로 한다. 상대 idx도 행에 적힌 값을 넘긴다(예전에는 reverseRows 쪽을 ""로 넘김).
                let contradicting = answerIsWife ? "여" : "남"
                var partners: [(word: String, idx: String, ownerIdx: String)] = []
                func addPartner(_ word: String, _ idx: String, rowOwnerIdx: String) {
                    let ownerIdx = rowOwnerIdx.isEmpty ? entity.idx : rowOwnerIdx
                    guard word != entity.word,
                          !partners.contains(where: { $0.word == word && $0.idx == idx && $0.ownerIdx == ownerIdx }) else { return }
                    let ownerGender = (try? store.personGender(idx: ownerIdx, word: "")) ?? ""
                    guard ownerGender != contradicting else { return }
                    partners.append((word, idx, ownerIdx))
                }
                for row in (try? store.personRelations(forWord: entity.word)) ?? [] where row.relationType == "married_to" {
                    addPartner(row.targetWord, row.targetIdx, rowOwnerIdx: row.sourceIdx)
                }
                for row in reverseRows where row.relationType == "married_to" && row.targetWord == entity.word {
                    addPartner(row.sourceWord, row.sourceIdx, rowOwnerIdx: row.targetIdx)
                }
                for partner in partners {
                    addSpouse(partnerWord: partner.word, partnerIdx: partner.idx,
                              ownerWord: entity.word, ownerIdx: partner.ownerIdx, answerIsWife: answerIsWife)
                }
            }
        }
        // [2026-10-22 4차 → 5차 일반화] X가 Persons 대표 이름으로 잡히지 않은 경우(관계 행에만 있는 이름·별칭 — 예: "스보", "게난")는
        // 위 루프가 X를 보지 못한다. 그런 X(공백 뺀 이름)만 골라 관계 행을 이름으로 직접 본다. 4차에는 조부모만 이렇게 했고 나머지는
        // "관계 전부" 폴백이었다. 대표 이름으로 잡힌 X는 다시 보지 않는다(배우자 성별 검사 등 위 판정을 우회하지 않게).
        // [7차] 예전에는 위 루프에 답이 있으면 여기서 바로 돌려줬다. 아래 idx 조회를 이어 붙이려고 반환을 맨 끝 한 곳으로 옮겼고,
        // 이 블록은 예전과 똑같이 "루프에 답이 없을 때만" 돈다(`combined.isEmpty` 조건).
        let resolvedNames = Set(personEntities.map { compact($0.word) })
        let unresolvedOwners = ownerNames.subtracting(resolvedNames)
        if combined.isEmpty, !unresolvedOwners.isEmpty {
            switch subQuery {
            case .reverseByType(let types, _):
                add(reverseRows.filter { types.contains($0.relationType) && unresolvedOwners.contains(compact($0.targetWord)) },
                    answerFromTarget: false)
            case .grandparent(let type):
                add(reverseRows.filter { $0.relationType == type && unresolvedOwners.contains(compact($0.targetWord)) },
                    answerFromTarget: false)
            case .parents:
                add(reverseRows.filter { ["father_of", "mother_of"].contains($0.relationType) && unresolvedOwners.contains(compact($0.targetWord)) },
                    answerFromTarget: false)
                let sourceRows = (try? store.personRelations(sourceWordMentionedIn: query, shortNamesExactMatch: shortNames)) ?? []
                add(sourceRows.filter { ["son_of", "daughter_of"].contains($0.relationType) && unresolvedOwners.contains(compact($0.sourceWord)) },
                    answerFromTarget: true)
            case .spouse(let answerIsWife):
                let contradicting = answerIsWife ? "여" : "남"
                for row in reverseRows where row.relationType == "married_to" && unresolvedOwners.contains(compact(row.targetWord)) {
                    let ownerGender = (try? store.personGender(idx: row.targetIdx, word: row.targetWord)) ?? ""
                    guard ownerGender != contradicting, compact(row.sourceWord) != compact(row.targetWord) else { continue }
                    addSpouse(partnerWord: row.sourceWord, partnerIdx: row.sourceIdx,
                              ownerWord: row.targetWord, ownerIdx: row.targetIdx, answerIsWife: answerIsWife)
                }
                let sourceRows = (try? store.personRelations(sourceWordMentionedIn: query, shortNamesExactMatch: shortNames)) ?? []
                for row in sourceRows where row.relationType == "married_to" && unresolvedOwners.contains(compact(row.sourceWord)) {
                    let ownerGender = (try? store.personGender(idx: row.sourceIdx, word: row.sourceWord)) ?? ""
                    guard ownerGender != contradicting, compact(row.sourceWord) != compact(row.targetWord) else { continue }
                    addSpouse(partnerWord: row.targetWord, partnerIdx: row.targetIdx,
                              ownerWord: row.sourceWord, ownerIdx: row.sourceIdx, answerIsWife: answerIsWife)
                }
            case .sibling, .uncle, .forwardByType, .mutualByType, .unregistered:
                break
            }
        }

        // [7차, 2026-10-28] X를 Persons idx로도 찾는다 — 상대 항목이 X를 별칭으로 적으면(예: 자녀 항목 "스룹바벨#1586", 1586의
        // 대표 이름은 세스바살) 위의 이름 비교(`target_word == X`)로는 그 행을 못 찾는다. X(공백 무시, `word` 또는 `word2` 별칭이
        // 정확히 같은 Persons 전부 — `isRelationPersonName`의 Persons 판정과 같은 규칙)의 idx 집합을 만들고, 그 idx가
        // target_idx(역방향, 답=source)/source_idx(부모의 정방향 son_of/daughter_of, 답=target)인 행을 이름 결과에 더한다.
        // 같은 행은 `add`의 키(source|type|target)로 한 번만 들어가고, 같은 답 인물이 다른 행으로 또 나오면 호출부의
        // `dedupedRelationAnswers`가 한 줄로 줄인다. 이 함수는 "X의 <관계어>" 꼴만 받아 X 뒤는 늘 "의"라 역방향만 본다
        // (루프의 `subjectDirection` 정방향과 같은 경우가 없다).
        // 배우자: married_to 행 중 X idx가 source/target인 행의 상대가 답. 루프와 같은 규칙 — X(그 idx)의 성별이 질의와 모순이면
        // ("X의 아내"인데 X가 여) 그 idx는 건너뛰고, 상대가 X 자신이면(같은 idx·같은 이름) 넣지 않는다. 문장은 `addSpouse`
        // (상대 → X 방향 wife_of/husband_of, X 이름은 그 행에 적힌 대로).
        let ownerTypes: (reverse: [String], forward: [String])?
        var spouseAnswerIsWife: Bool?
        switch subQuery {
        case .reverseByType(let types, _): ownerTypes = (reverse: types, forward: [])
        case .grandparent(let type): ownerTypes = (reverse: [type], forward: [])
        case .parents: ownerTypes = (reverse: ["father_of", "mother_of"], forward: ["son_of", "daughter_of"])
        case .spouse(let answerIsWife):
            ownerTypes = (reverse: [], forward: [])
            spouseAnswerIsWife = answerIsWife
        case .sibling, .uncle, .forwardByType, .mutualByType, .unregistered: ownerTypes = nil
        }
        if let ownerTypes = ownerTypes {
            var ownerIdxs: [String] = []
            for name in ownerNames.sorted() {
                for idx in (try? store.personIdxs(matchingName: name)) ?? [] where !ownerIdxs.contains(idx) {
                    ownerIdxs.append(idx)
                }
            }
            if !ownerIdxs.isEmpty {
                let idxSet = Set(ownerIdxs)
                let idxRows = (try? store.personRelations(sourceOrTargetIdxIn: ownerIdxs)) ?? []
                add(idxRows.filter { ownerTypes.reverse.contains($0.relationType) && idxSet.contains($0.targetIdx) },
                    answerFromTarget: false)
                add(idxRows.filter { ownerTypes.forward.contains($0.relationType) && idxSet.contains($0.sourceIdx) },
                    answerFromTarget: true)
                if let answerIsWife = spouseAnswerIsWife {
                    let contradicting = answerIsWife ? "여" : "남"
                    var allowedOwners = Set<String>()
                    for idx in ownerIdxs where ((try? store.personGender(idx: idx, word: "")) ?? "") != contradicting {
                        allowedOwners.insert(idx)
                    }
                    for row in idxRows where row.relationType == "married_to" {
                        // 한 행에 X idx가 양쪽 다 있으면(자기 자신과의 행) 아래 같은 사람 검사에서 걸러진다.
                        if allowedOwners.contains(row.sourceIdx),
                           row.targetIdx != row.sourceIdx, compact(row.targetWord) != compact(row.sourceWord) {
                            addSpouse(partnerWord: row.targetWord, partnerIdx: row.targetIdx,
                                      ownerWord: row.sourceWord, ownerIdx: row.sourceIdx, answerIsWife: answerIsWife)
                        }
                        if allowedOwners.contains(row.targetIdx),
                           row.targetIdx != row.sourceIdx, compact(row.targetWord) != compact(row.sourceWord) {
                            addSpouse(partnerWord: row.sourceWord, partnerIdx: row.sourceIdx,
                                      ownerWord: row.targetWord, ownerIdx: row.targetIdx, answerIsWife: answerIsWife)
                        }
                    }
                }
            }
        }
        if !combined.isEmpty {
            return QueryIntentCard(intent: .relation, status: .found(.relation(combined)))
        }
        // [7차, 2026-10-28] 5차의 "반대 방향 보완"(X 항목에만 적힌 관계를 상대 쪽에서 읽던 조회)은 지웠다. 시드 가족 관계를
        // 양쪽 항목에 모두 적도록 보완했고, 상대 항목이 X를 별칭으로 적은 경우는 위 idx 조회가 찾는다(사용자 확정).
        // 이 조회로만 답이 나오던 질의 중 상대가 Persons에 없거나 상대 항목에 반대쪽이 없는 경우(1028d 기준 다하스 2건·율리아·네로·
        // 프삼티크 2세·벨렉)는 이제 안내 카드다(CHANGES7.md 3절).
        // 아내/남편(3차), 조부모(4차), [5차] 나머지 관계어 모두 — 결과가 없으면 다른 관계 전체로 폴백하지 않고 안내 카드다.
        return unregisteredRelationCard(label: unregisteredRelationLabel(for: subQuery))
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
        _ query: String, role: SiblingRole, targetRows: [PersonRelationRecord], shortNames: [String], store: ReferenceDataStore
    ) -> QueryIntentCard {
        let sourceRows = (try? store.personRelations(sourceWordMentionedIn: query, shortNamesExactMatch: shortNames)) ?? []

        var items: [RelationDisplayItem] = []
        var seen = Set<String>()
        /// 저장 행 `template` 하나를 "역할 보유자(holder) → 소유자(owner)" 사실로 더한다. `flipped`면 template의 target이 보유자,
        /// `answerIsHolder`면 답이 보유자(아니면 소유자)다. 답 인물의 구절을 붙인다.
        /// [7차] 예전에는 이름으로 뒤집힘(`holder != template.sourceWord`)과 답 idx(`answerIdx(of:in:)`)를 정했고, 뒤집은 행의
        /// 소유자 idx는 버렸으며(""), 구절은 이름(`personOrPlace(exactWord:)`)으로 찾았다. 이제 쪽을 직접 받아 행에 적힌 idx를
        /// 그대로 옮기고, 구절은 idx가 있으면 그 인물 것(`answerVerseRefs`와 같은 규칙), 없을 때만 이름으로 찾는다.
        func append(_ template: PersonRelationRecord, flipped: Bool, answerIsHolder: Bool) {
            let holder = flipped ? template.targetWord : template.sourceWord
            let holderIdx = flipped ? template.targetIdx : template.sourceIdx
            let owner = flipped ? template.sourceWord : template.targetWord
            let ownerIdx = flipped ? template.sourceIdx : template.targetIdx
            let key = "\(holder)#\(holderIdx)|\(role.role)|\(owner)#\(ownerIdx)"  // [7차] idx 포함
            guard seen.insert(key).inserted else { return }
            // 뒤집은 행의 `targetKind`는 알 수 없어 nil(원래 방향이면 원래 값). `PersonRelationRecord.targetKind` 주석 참고.
            let record = PersonRelationRecord(
                sourceWord: holder, relationType: role.role, targetWord: owner,
                targetKind: flipped ? nil : template.targetKind,
                rawSentence: template.rawSentence,
                targetIdx: ownerIdx,
                sourceIdx: holderIdx
            )
            let answer = answerIsHolder ? holder : owner
            let answerIdx = answerIsHolder ? holderIdx : ownerIdx
            let otherWord = answerIsHolder ? owner : holder
            let otherIdx = answerIsHolder ? ownerIdx : holderIdx
            func verses(word: String, idx: String) -> [BibleVerseRef]? {
                if !idx.isEmpty, let person = try? store.person(idx: idx) { return person.verseRefs }
                return (try? store.personOrPlace(exactWord: word))?.verseRefs
            }
            // 답 인물이 Persons에 없으면(예: 골리앗) 질의에 쓴 인물(소유자)의 구절로 대신한다.
            let answerVerses = verses(word: answer, idx: answerIdx) ?? verses(word: otherWord, idx: otherIdx) ?? []
            items.append(RelationDisplayItem(
                relation: record, verseRefs: answerVerses,
                answerWord: answer, answerIdx: answerIdx
            ))
        }

        // 질의 속 이름이 target인 행(저장 방향: source가 target의 ROLE)
        for row in targetRows {
            let nameIsHolder = subjectDirection(for: row.targetWord, in: query) == true
            if !nameIsHolder {
                // "OO(=target)의 ROLE" — 같은 역할로 저장된 행이면 source가 답.
                if row.relationType == role.role {
                    append(row, flipped: false, answerIsHolder: true)
                }
            } else if row.relationType == role.inverse {
                // "OO(=target)가 ROLE인 사람" — 반대 역할로 저장된 행(source가 OO의 반대 역할)을 뒤집어 OO가 보유자.
                append(row, flipped: true, answerIsHolder: false)
            }
        }
        // 질의 속 이름이 source인 행
        for row in sourceRows {
            let nameIsHolder = subjectDirection(for: row.sourceWord, in: query) == true
            if !nameIsHolder {
                // "OO(=source)의 ROLE" — OO가 반대 역할로 저장된 행(예: 골리앗 older_brother_of 라흐미)을 뒤집어 target이 답.
                if row.relationType == role.inverse {
                    append(row, flipped: true, answerIsHolder: true)
                }
            } else if row.relationType == role.role {
                // "OO(=source)가 ROLE인 사람" — 같은 역할로 저장된 행이면 target이 답.
                append(row, flipped: false, answerIsHolder: false)
            }
        }

        guard !items.isEmpty else {
            let label = role == .younger ? String(localized: "동생/아우") : String(localized: "형")
            return QueryIntentCard(intent: .relation, status: .notReady(
                message: String(localized: "질의한 \(label) 관계가 등록돼 있지 않습니다. 아래 검색 결과를 확인해 보세요.")
            ))
        }
        return QueryIntentCard(intent: .relation, status: .found(.relation(items)))
    }

    // MARK: - 형제·자매·삼촌 질의 (2026-10-22 4차)
    //
    // 사용자 확정: "X의 형제/자매/삼촌"은 "관계 타입 미지정 폴백"(그 인물의 관계 전부) 대신 그 관계만 답한다. 행이 없으면 안내 카드.
    // 근거는 명시된 행(PersonSeed 기타관계 → `PersonRelations`)뿐이다. "같은 아버지의 자녀"나 "아버지의 형제"를 이어 붙여 만들지 않는다 —
    // 관계 행은 이름으로 이어지므로 동명이인(예: 라멕 둘)의 자녀가 섞이고, 빌드가 표기 없는 상대의 idx를 "동명이인이면 첫 idx"로 채우기
    // 때문이다(`build_reference_data.py` 기타관계 매핑 주석).
    //
    // X는 `koreanRelationShapeNames`가 준 이름(공백 뺀 꼴)과 행의 이름(공백 뺀 꼴)이 정확히 같을 때만 본다.

    /// 형제 관계 행 타입(source가 target의 형제/형/아우/자매). 형제 관계는 서로 같으므로 X가 source든 target이든 상대가 답이다.
    private static let siblingRelationTypes: Set<String> = ["brother_of", "older_brother_of", "younger_brother_of", "sister_of"]

    /// "X의 형제"(`answerIsMale` true) / "X의 자매"(false), [2026-10-27 5차] "X의 오라비"(true) / "X의 누이"(false) — 같은 규칙, 안내 카드
    /// 라벨(`label`)만 다르다(오라비·누이를 형제·자매로 묶지 않고 명시된 형제·자매 행에서 같은 성별로 답한다). 답 인물을 남/여로 가르는 규칙:
    ///  1) 답 인물의 성별(`ReferenceDataStore.personGender` — idx, 없으면 유일한 이름)을 알면 그것으로.
    ///     예: 미리암(여)은 시드에 "(형제)"로 적힌 행이 있어도 자매 쪽, 롯(남)은 "(자매)"로 적힌 행이 있어도 형제 쪽.
    ///  2) 모르면 행 타입으로: brother_of/older_brother_of/younger_brother_of → 형제, sister_of → 자매.
    /// 화면 문장은 항상 "답 → X" 방향으로 정리한다. 원래 방향이고 타입이 갈래와 맞으면 그 타입(형/아우 구분 유지), 뒤집은 행이면
    /// 형↔아우를 바꾸고, 그 밖은 brother_of/sister_of로 쓴다. 같은 답 인물은 한 번만(먼저 나온 행 — X가 target인 행이 먼저).
    private static func handleSiblingGroup(
        _ query: String, answerIsMale: Bool, label: String, ownerNames: Set<String>,
        targetRows: [PersonRelationRecord], shortNames: [String], store: ReferenceDataStore
    ) -> QueryIntentCard {
        func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        let sourceRows = (try? store.personRelations(sourceWordMentionedIn: query, shortNamesExactMatch: shortNames)) ?? []

        var items: [RelationDisplayItem] = []
        var seen = Set<String>()
        /// 행 하나를 답으로 더한다. `answerIsSource`면 원래 방향(답 = source), 아니면 뒤집은 방향(답 = target).
        func consider(_ row: PersonRelationRecord, answerIsSource: Bool) {
            let answer = answerIsSource ? row.sourceWord : row.targetWord
            let answerIdx = answerIsSource ? row.sourceIdx : row.targetIdx
            let owner = answerIsSource ? row.targetWord : row.sourceWord
            let ownerIdx = answerIsSource ? row.targetIdx : row.sourceIdx
            guard !answer.isEmpty, compact(answer) != compact(owner) else { return }

            let gender = (try? store.personGender(idx: answerIdx, word: answer)) ?? ""
            let isMale: Bool
            if gender == "남" {
                isMale = true
            } else if gender == "여" {
                isMale = false
            } else {
                // 행 타입은 source의 성별만 말해 준다. 뒤집은 행(답 = target)이면 답의 성별을 알 수 없으므로 추측하지 않고 건너뛴다.
                guard answerIsSource else { return }
                isMale = row.relationType != "sister_of"
            }
            guard isMale == answerIsMale else { return }
            guard seen.insert("\(answer)#\(answerIdx)|\(owner)#\(ownerIdx)").inserted else { return }  // [7차] idx 포함

            let displayType: String
            if !answerIsMale {
                displayType = "sister_of"
            } else if answerIsSource {
                displayType = row.relationType == "sister_of" ? "brother_of" : row.relationType
            } else if row.relationType == "older_brother_of" {
                displayType = "younger_brother_of"  // X가 답의 형 → 답은 X의 아우
            } else if row.relationType == "younger_brother_of" {
                displayType = "older_brother_of"    // X가 답의 아우 → 답은 X의 형
            } else {
                displayType = "brother_of"
            }
            let record = PersonRelationRecord(
                sourceWord: answer, relationType: displayType, targetWord: owner,
                targetKind: .person, rawSentence: row.rawSentence,
                targetIdx: ownerIdx, sourceIdx: answerIdx
            )
            let verses = Self.answerVerseRefs(word: answer, idx: answerIdx, store: store)
            items.append(RelationDisplayItem(relation: record, verseRefs: verses, answerWord: answer, answerIdx: answerIdx))
        }

        for row in targetRows where siblingRelationTypes.contains(row.relationType) && ownerNames.contains(compact(row.targetWord)) {
            consider(row, answerIsSource: true)
        }
        for row in sourceRows where siblingRelationTypes.contains(row.relationType) && ownerNames.contains(compact(row.sourceWord)) {
            consider(row, answerIsSource: false)
        }

        guard !items.isEmpty else {
            return unregisteredRelationCard(label: label)
        }
        return QueryIntentCard(intent: .relation, status: .found(.relation(items)))
    }

    /// "X의 삼촌/숙부/백부/외삼촌" — `uncle_of` 행 중 target이 X인 행의 source(삼촌)가 답이다. 시드의 "(숙부)"와 "(조카)"(방향을 뒤집어
    /// 같은 타입으로 저장)가 모두 여기 든다. "(조카)"는 고모일 수도 있어(빌드 주석 "삼촌/고모") 답 인물이 여성으로 확인되면 뺀다.
    /// `uncle_of`는 부계·모계를 구분하지 않으므로 "외삼촌" 질의도 같은 답이다. 화면 문장은 저장된 행 그대로("A는 X의 삼촌").
    private static func handleUncle(
        ownerNames: Set<String>, targetRows: [PersonRelationRecord], store: ReferenceDataStore
    ) -> QueryIntentCard {
        func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        var items: [RelationDisplayItem] = []
        var seen = Set<String>()
        for row in targetRows where row.relationType == "uncle_of" && ownerNames.contains(compact(row.targetWord)) {
            guard compact(row.sourceWord) != compact(row.targetWord) else { continue }
            let gender = (try? store.personGender(idx: row.sourceIdx, word: row.sourceWord)) ?? ""
            guard gender != "여" else { continue }
            guard seen.insert("\(row.sourceWord)#\(row.sourceIdx)|\(row.targetWord)#\(row.targetIdx)").inserted else { continue }  // [7차] idx 포함
            let verses = Self.answerVerseRefs(word: row.sourceWord, idx: row.sourceIdx, store: store)
            items.append(RelationDisplayItem(relation: row, verseRefs: verses, answerWord: row.sourceWord, answerIdx: row.sourceIdx))
        }
        guard !items.isEmpty else {
            return unregisteredRelationCard(label: unregisteredRelationLabel(for: .uncle))
        }
        return QueryIntentCard(intent: .relation, status: .found(.relation(items)))
    }

    /// [5차] "X의 조카/후손/자손/증손"(`includeReverse` false — X가 source인 행의 target이 답) / "X의 동역자"(true — 양방향).
    /// 행 저장 규칙("source가 target의 ROLE"):
    ///  - 조카: (삼촌, uncle_of, 조카) → X(삼촌)가 source인 행의 target
    ///  - 후손·자손: (조상, ancestor_of, 후손) → X가 source인 행의 target. 증손: (증조부, great_grandfather_of, 증손) → 같음
    ///  - 동역자: (Y, co_worker_of, X) — 서로 같은 관계라 X가 target인 행의 source와 X가 source인 행의 target 모두. 화면 문장은 "답 → X"로 정리
    /// 정방향(조카 등)의 화면 문장은 저장된 행 그대로다("아브라함은 롯의 삼촌" — 답은 롯; 기존 `.parents` 정방향 행과 같은 방식).
    /// X는 공백 무시 정확 일치(`handleSiblingGroup`과 같다). 행이 없으면 안내 카드.
    private static func handleOwnerRelationRows(
        _ query: String, types: [String], label: String, includeReverse: Bool, ownerNames: Set<String>,
        targetRows: [PersonRelationRecord], shortNames: [String], store: ReferenceDataStore
    ) -> QueryIntentCard {
        func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        var items: [RelationDisplayItem] = []
        var seen = Set<String>()
        func append(_ record: PersonRelationRecord, answer: String, answerIdx: String, owner: String, ownerIdx: String) {
            // [7차] 키에 idx 포함(답·X 모두 행에 적힌 idx).
            guard !answer.isEmpty, compact(answer) != compact(owner),
                  seen.insert("\(answer)#\(answerIdx)|\(owner)#\(ownerIdx)").inserted else { return }
            let verses = Self.answerVerseRefs(word: answer, idx: answerIdx, store: store)
            items.append(RelationDisplayItem(relation: record, verseRefs: verses, answerWord: answer, answerIdx: answerIdx))
        }
        if includeReverse {
            for row in targetRows where types.contains(row.relationType) && ownerNames.contains(compact(row.targetWord)) {
                append(row, answer: row.sourceWord, answerIdx: row.sourceIdx, owner: row.targetWord, ownerIdx: row.targetIdx)
            }
        }
        let sourceRows = (try? store.personRelations(sourceWordMentionedIn: query, shortNamesExactMatch: shortNames)) ?? []
        for row in sourceRows where types.contains(row.relationType) && ownerNames.contains(compact(row.sourceWord)) {
            if includeReverse {
                // 서로 같은 관계 — 화면 문장이 "답은 X의 동역자"로 읽히게 뒤집는다.
                let flipped = PersonRelationRecord(
                    sourceWord: row.targetWord, relationType: row.relationType, targetWord: row.sourceWord,
                    targetKind: .person, rawSentence: row.rawSentence,
                    targetIdx: row.sourceIdx, sourceIdx: row.targetIdx
                )
                append(flipped, answer: row.targetWord, answerIdx: row.targetIdx, owner: row.sourceWord, ownerIdx: row.sourceIdx)
            } else {
                append(row, answer: row.targetWord, answerIdx: row.targetIdx, owner: row.sourceWord, ownerIdx: row.sourceIdx)
            }
        }
        guard !items.isEmpty else {
            return unregisteredRelationCard(label: label)
        }
        return QueryIntentCard(intent: .relation, status: .found(.relation(items)))
    }

    /// `handleRelation` 전용 — 질의에서 구체적인 관계 타입을 감지한다.
    /// 검사 순서 주의: 더 구체적인 키워드를 먼저 검사해야 한다(예: "외할아버지" ⊃ "할아버지" ⊃ "아버지" — 2026-10-22 3차에 조부모 추가).
    /// [5차] `label`은 행이 없을 때 안내 카드에 넣는 관계 이름(이미 `String(localized:)`로 번역된 값).
    private enum RelationSubQuery {
        /// "OO의 <역할>은?" — target == OO이고 relationType이 목록에 속하는 행의 source를
        /// 답으로 보여준다.
        case reverseByType([String], label: String)
        /// "OO의 부모는?" 전용 — father_of/mother_of(역방향)와 son_of/daughter_of(정방향)를 합친다.
        case parents
        /// "OO의 아내/남편은?" 전용. `PersonRelations`에는 `wife_of`/`husband_of` 행이 한 건도 없고 성별 중립인
        /// `married_to`(PersonSeed 배우자 목록에서 만든 행, 대부분 양방향으로 저장)만 있다. 그래서 `reverseByType(["wife_of"])`로는
        /// 항상 0건이 되어 "관계 타입 미지정 폴백"(그 인물의 아들·신하·대적 등 모든 관계 나열)으로 떨어졌다.
        /// `answerIsWife`가 true면 질의의 인물이 남편, 답이 아내다.
        case spouse(answerIsWife: Bool)
        /// [2026-10-22 4차] "OO의 할아버지/할머니/외할아버지/외할머니" — `reverseByType([type])`과 같은 조회이고, 행이 없으면
        /// 다른 관계 전체로 폴백하지 않고 안내 카드("질의한 할아버지 관계가 등록돼 있지 않습니다")를 낸다(사용자 확정).
        case grandparent(type: String)
        /// [2026-10-22 4차] "OO의 형제"(`answerIsMale` true)/"OO의 자매"(false) — `handleSiblingGroup` 참고. 없으면 안내 카드.
        /// [5차] "OO의 오라비"(true)/"OO의 누이"(false)도 같은 처리 — `label`(안내 카드 관계 이름)만 다르다.
        case sibling(answerIsMale: Bool, label: String)
        /// [2026-10-22 4차] "OO의 삼촌/숙부/백부/외삼촌" — `uncle_of` 행(부계·모계 구분 없음). 없으면 안내 카드.
        case uncle
        /// [5차] X가 source인 행의 target이 답(조카·후손·자손·증손) — `handleOwnerRelationRows`.
        case forwardByType([String], label: String)
        /// [5차] 서로 같은 관계(동역자) — 양방향. `handleOwnerRelationRows`.
        case mutualByType([String], label: String)
        /// [5차] 맞는 relation_type이 DB에 없는 관계어(사촌·장모·이모·고모·지파·여동생·고손) — 조회 없이 안내 카드.
        case unregistered(label: String)
    }

    /// 행이 없을 때 폴백 대신 띄울 안내 카드의 관계 이름. 문구 키는 아내/남편과 같은
    /// "질의한 %@ 관계가 등록돼 있지 않습니다. …"이고, 이름도 `String(localized:)` 키로 번역한다.
    /// [5차] 모든 관계어가 안내 카드를 쓰므로 nil이 없다(4차의 "nil이면 관계 전부 폴백"은 지웠다).
    private static func unregisteredRelationLabel(for subQuery: RelationSubQuery) -> String {
        switch subQuery {
        case .reverseByType(_, let label), .forwardByType(_, let label), .mutualByType(_, let label):
            return label
        case .unregistered(let label):
            return label
        case .sibling(_, let label):
            return label
        case .parents: return String(localized: "부모")
        case .spouse(let answerIsWife): return answerIsWife ? String(localized: "아내") : String(localized: "남편")
        case .grandparent(let type):
            switch type {
            case "maternal_grandfather_of": return String(localized: "외할아버지")
            case "maternal_grandmother_of": return String(localized: "외할머니")
            case "grandmother_of": return String(localized: "할머니")
            default: return String(localized: "할아버지")
            }
        case .uncle: return String(localized: "삼촌")
        }
    }

    private static func unregisteredRelationCard(label: String) -> QueryIntentCard {
        QueryIntentCard(intent: .relation, status: .notReady(
            message: String(localized: "질의한 \(label) 관계가 등록돼 있지 않습니다. 아래 검색 결과를 확인해 보세요.")
        ))
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
        if query.contains("자녀") || query.contains("자식") {
            return .reverseByType(["son_of", "daughter_of"], label: String(localized: "자녀"))
        }
        if query.contains("아들") { return .reverseByType(["son_of"], label: String(localized: "아들")) }
        if query.contains("딸") { return .reverseByType(["daughter_of"], label: String(localized: "딸")) }
        // "손자"/"손녀"는 "아들"/"딸"과 부분 문자열 관계가 없어 검사 순서와 무관하다.
        if query.contains("손자") { return .reverseByType(["grandson_of"], label: String(localized: "손자")) }
        if query.contains("손녀") { return .reverseByType(["granddaughter_of"], label: String(localized: "손녀")) }
        // [2026-10-22 3차] 조부모는 "아버지"/"어머니"보다 먼저 본다 — "할아버지"가 "아버지"를 포함해 father_of(아버지)를 답으로
        // 보여 주던 버그. 외조부모를 조부모보다 먼저 본다("외할아버지" ⊃ "할아버지"). 방향은 father_of와 같다 — 행은
        // "source가 target의 할아버지"(예: (라멕, grandfather_of, 셈))라 "셈의 할아버지"는 target=셈 행의 source(라멕)가 답이다.
        // "외할머니/외조모"(maternal_grandmother_of)는 사용자 목록 밖이지만 넣지 않으면 "할머니"에 걸려 grandmother_of로 답하므로 함께 둔다.
        // [4차] 조부모는 `.grandparent`(조회는 같고, 행이 없으면 안내 카드).
        if query.contains("외할아버지") || query.contains("외조부") { return .grandparent(type: "maternal_grandfather_of") }
        if query.contains("외할머니") || query.contains("외조모") { return .grandparent(type: "maternal_grandmother_of") }
        if query.contains("할아버지") || query.contains("조부") { return .grandparent(type: "grandfather_of") }
        if query.contains("할머니") || query.contains("조모") { return .grandparent(type: "grandmother_of") }
        // [2026-10-27 6차] "시아버지"(남편의 아버지)는 "아버지"를 포함하므로 그보다 먼저 본다 — 빌드가 시드 "Y(시아버지)"를
        // (Y, husbands_father_of, X)로 따로 저장한다("장인" = father_in_law_of와 분리, 사용자 확정). 역방향: "X의 시아버지" → source.
        if query.contains("시아버지") { return .reverseByType(["husbands_father_of"], label: String(localized: "시아버지")) }
        if query.contains("아버지") || query.contains("부친") { return .reverseByType(["father_of"], label: String(localized: "아버지")) }
        if query.contains("어머니") || query.contains("모친") { return .reverseByType(["mother_of"], label: String(localized: "어머니")) }
        // [2026-10-22 4차] 형제·자매·삼촌. 앞의 어떤 관계어와도 부분 문자열 관계가 없어 순서와 무관하다.
        // "형제"가 여기서 잡히므로 `handleRelation`의 형/동생 분기(`detectSiblingRole`, 이 함수가 nil일 때만)는 타지 않는다.
        if query.contains("형제") { return .sibling(answerIsMale: true, label: String(localized: "형제")) }
        if query.contains("자매") { return .sibling(answerIsMale: false, label: String(localized: "자매")) }
        if query.contains("삼촌") || query.contains("숙부") || query.contains("백부") { return .uncle }
        // "아내" 동의어 중 "처"는 한 글자라 "처음"/"처녀"/"출처" 등에 오탐되어 제외했다([5차] "X의 처" 꼴은 `relationSubQuery(forShapeWord:)`가 받는다).
        if query.contains("아내") || query.contains("부인") { return .spouse(answerIsWife: true) }
        if query.contains("남편") { return .spouse(answerIsWife: false) }
        return nil
    }

    /// [2026-10-27 5차] `detectRelationSubQuery`(질의 부분 문자열)가 못 정한 관계어를 "X의 <관계어>" 꼴의 관계어(`QueryIntentClassifier.koreanRelationShape`)로
    /// 정한다. 관계어는 분류기 어휘(`RelationSynonyms` + "형" + `baselineRelationWords`) 중 위 함수에 없는 것 전부다.
    /// 행 저장 규칙은 "source가 target의 ROLE"(`build_reference_data.py` `OTHER_RELATION_LABEL_MAP`, 기타관계 "Y(라벨)" → (Y, type, X)):
    ///  - 아비/아빠 → father_of, 어미/엄마 → mother_of (역방향, 아버지/어머니와 같다)
    ///  - 처 → 아내와 같다
    ///  - 오라비 → 형제와 같은 명시 행 판정(남), 누이 → 자매와 같은 판정(여) — 안내 카드 라벨만 "오라비"/"누이"(사용자: 묶지 않아도 됨)
    ///  - 조상·선조 → ancestor_of 역방향(답 = source). 후손·자손 → ancestor_of 정방향(답 = target). 증손 → great_grandfather_of 정방향
    ///  - 조카 → uncle_of 정방향(답 = target, 시드 "(조카)"/"(숙부)" 모두 (삼촌, uncle_of, 조카)로 저장)
    ///  - 며느리 → daughter_in_law_of, 사위 → son_in_law_of, 장인 → father_in_law_of (역방향 — 시드 "Y(며느리|자부|사위|장인)")
    ///    [6차] 시아버지 → husbands_father_of(시드 "Y(시아버지)", `detectRelationSubQuery`가 "아버지"보다 먼저 받는다)
    ///  - 동역자 → co_worker_of 양방향
    ///  - 여동생·고손·지파·사촌·장모·이모·고모 → DB에 맞는 relation_type이 없어 안내 카드
    ///  - 형·동생·아우·남동생·친아우 → nil(`handleSibling`이 받는다)
    private static func relationSubQuery(forShapeWord word: String) -> RelationSubQuery? {
        switch word {
        case "아비", "아빠": return .reverseByType(["father_of"], label: String(localized: "아버지"))
        case "어미", "엄마": return .reverseByType(["mother_of"], label: String(localized: "어머니"))
        case "처": return .spouse(answerIsWife: true)
        case "오라비": return .sibling(answerIsMale: true, label: String(localized: "오라비"))
        case "누이": return .sibling(answerIsMale: false, label: String(localized: "누이"))
        case "조상": return .reverseByType(["ancestor_of"], label: String(localized: "조상"))
        case "선조": return .reverseByType(["ancestor_of"], label: String(localized: "선조"))
        case "후손": return .forwardByType(["ancestor_of"], label: String(localized: "후손"))
        case "자손": return .forwardByType(["ancestor_of"], label: String(localized: "자손"))
        case "증손": return .forwardByType(["great_grandfather_of"], label: String(localized: "증손"))
        case "조카": return .forwardByType(["uncle_of"], label: String(localized: "조카"))
        case "며느리": return .reverseByType(["daughter_in_law_of"], label: String(localized: "며느리"))
        case "사위": return .reverseByType(["son_in_law_of"], label: String(localized: "사위"))
        case "장인": return .reverseByType(["father_in_law_of"], label: String(localized: "장인"))
        case "동역자": return .mutualByType(["co_worker_of"], label: String(localized: "동역자"))
        case "여동생": return .unregistered(label: String(localized: "여동생"))
        case "고손": return .unregistered(label: String(localized: "고손"))
        case "지파": return .unregistered(label: String(localized: "지파"))
        case "사촌": return .unregistered(label: String(localized: "사촌"))
        case "장모": return .unregistered(label: String(localized: "장모"))
        case "이모": return .unregistered(label: String(localized: "이모"))
        case "고모": return .unregistered(label: String(localized: "고모"))
        default: return nil
        }
    }

    // MARK: - 인물 프로필 / 주제 (키워드·카테고리 조회, personOrPlaceInfo 대체)

    /// `KeywordCategoryIndex`(등록된 인물/주제 표제어)에 질의와 일치하는 표제어가 있는지 먼저
    /// 확인하고, 카테고리에 맞는 저장소(`persons(mentionedIn:)`/`themes(matching:)`)를
    /// 조회한다. 못 찾으면 nil을 돌려준다. 장소는 `KeywordCategoryIndex`가 '인물'/'주제'만 갖고
    /// 있어(Places 콘텐츠 미준비) 반환하지 않는다.
    /// 문서 확정) 이 메서드가 장소를 반환할 일이 구조적으로 없다.
    private static func handleKeywordCategoryLookup(_ query: String, store: ReferenceDataStore) -> QueryIntentCard? {
        // [2026-10-22 3차] 끝의 "?"/"."를 뗀 질의로 조회한다 — 한 글자 이름 정확 일치(`keywordCategories`/`persons(mentionedIn:)`의
        // "질의 전체 = 이름")가 "함?"에서도 걸리게. 부분 문자열 판정은 끝 문장부호와 무관해 결과가 같다.
        let trimmed = QueryIntentClassifier.trimmingTrailingQueryPunctuation(query)
        let categories = (try? store.keywordCategories(mentionedIn: trimmed)) ?? []

        // [2026-10-22 2차] 인물 카드는 "이름 그대로" 질의(`isKoreanNameOnlyQuery`)일 때만 낸다 — "다윗은 누구인가"처럼 이름이 든
        // 문장형 질문은 카드 없이 일반 검색으로 보낸다(사용자 요구). 이렇게 걸러진 분류는 없던 것으로 친다(아래 안내 카드 판정).
        var categoriesRejectedByShape: Set<String> = []
        if categories.contains("인물") {
            let persons = (try? store.persons(mentionedIn: trimmed)) ?? []
            if !persons.isEmpty {
                if isKoreanNameOnlyQuery(trimmed, names: persons.map { $0.matchedAlias ?? $0.word }) {
                    return QueryIntentCard(intent: .personProfile, status: .found(.personProfile(persons)))
                }
                // [2026-10-22 4차] 이름 + 직함 예외(사용자 확정) — 질의 전체가 "예수 그리스도"면 "예수" 인물 카드(base2와 같은 동작).
                // [2026-10-27 5차] 정확히 "예수 그리스도"/"예수그리스도"만(끝의 "?"/"."는 `trimmed`가 이미 뗐다, 연속 공백은 한 칸으로 본다).
                // 4차는 공백을 모두 지워 비교해 "예 수그리스도"처럼 띄어 쓴 꼴도 걸렸다. "그리스도 예수", "주 예수 그리스도"는 받지 않는다(사용자 확정).
                let normalizedQuery = trimmed.precomposedStringWithCanonicalMapping
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
                if let exceptionName = personTitleExceptions[normalizedQuery] {
                    let named = persons.filter { ($0.matchedAlias ?? $0.word) == exceptionName }
                    if !named.isEmpty {
                        return QueryIntentCard(intent: .personProfile, status: .found(.personProfile(named)))
                    }
                }
                categoriesRejectedByShape.insert("인물")
            }
        }
        // [2026-10-22 3차] 주제 카드도 같은 규칙 — 질의 전체가 걸린 주제의 표제어(제목·검색어)여야 한다. "기도" → 카드,
        // "함께 기도하라"/"기도의 방법" → 카드 없음(한국어 문장형 질의 금지, 사용자 확정).
        if categories.contains("주제") {
            let themes = (try? store.themes(matching: trimmed)) ?? []
            if !themes.isEmpty {
                if isKoreanNameOnlyQuery(trimmed, names: themes.flatMap { themeMatchTerms($0) }) {
                    return QueryIntentCard(intent: .themeOrAttribute, status: .found(.theme(themes)))
                }
                categoriesRejectedByShape.insert("주제")
            }
        }
        let remainingCategories = categories.subtracting(categoriesRejectedByShape)
        if !remainingCategories.isEmpty {
            // 인덱스엔 걸렸지만 콘텐츠 조회가 빈 배열인 드문 불일치(예: 대응 행이 그 사이 지워짐) —
            // 카테고리는 이미 알아냈으므로 추가 보완 없이 준비중 카드로 안내한다.
            return QueryIntentCard(intent: .personProfile, status: .notReady(
                message: String(localized: "이 표제어는 등록돼 있으나 상세 콘텐츠를 찾지 못했습니다. 아래 검색 결과를 확인해 보세요.")
            ))
        }

        return nil
    }

    /// [2026-10-22 4차] "이름 그대로" 규칙의 예외 — (질의 전체 → 카드에 낼 인물 이름). 사용자가 정한 것만 둔다.
    /// [5차] 키는 공백을 한 칸으로 맞춘 질의 그대로(공백을 지우지 않는다). "그리스도 예수"·"주 예수 그리스도"는 넣지 않는다(사용자 확정).
    private static let personTitleExceptions: [String: String] = ["예수 그리스도": "예수", "예수그리스도": "예수"]

    /// 질의가 걸린 인물 이름(대표 이름 또는 걸린 별칭)만으로 이뤄졌는지 — 공백·쉼표(`nameSeparators`)와 끝의 "?"/"."는 무시한다.
    /// 예: "다윗", "다윗 솔로몬", "다윗, 솔로몬", "아브라함"(삼켜진 "라함"은 `persons(mentionedIn:)`가 이미 뺐다) → true.
    /// "다윗은 누구인가", "다윗은", "다윗과 솔로몬", "다윗 왕" → false(이름이 아닌 글자가 남는다).
    /// 긴 이름부터 지워 짧은 이름이 긴 이름의 일부만 지우는 일을 막는다.
    /// [2026-10-22 3차] 지명 카드(`handlePlaceLookup` — 지명·인물 이름)와 주제 카드(`themeMatchTerms`)도 같은 함수로 판정한다.
    private static func isKoreanNameOnlyQuery(_ query: String, names: [String]) -> Bool {
        var residual = QueryIntentClassifier.trimmingTrailingQueryPunctuation(query)
            .filter { !$0.isWhitespace && !nameSeparators.contains($0) }
        guard !residual.isEmpty else { return false }
        let compactNames = names.map { $0.filter { !$0.isWhitespace } }.filter { !$0.isEmpty }
        for name in compactNames.sorted(by: { $0.count > $1.count }) {
            residual = residual.replacingOccurrences(of: name, with: "")
        }
        return residual.isEmpty
    }

    /// [2026-10-22 3차] 주제 하나가 질의에 걸릴 수 있는 말 — 제목과 검색어(콤마 구분) 중 2글자 이상인 것.
    /// `ReferenceDataStore.themes(matching:)`의 일치 규칙(`matchesQuery`: 2글자 이상, 부분 문자열)과 같은 말만 돌려준다 —
    /// `isKoreanNameOnlyQuery`가 이 말들을 질의에서 지워 "질의 전체가 주제 표제어인지"를 본다(질의에 없는 말은 지워도 그대로다).
    private static func themeMatchTerms(_ theme: ThemeRecord) -> [String] {
        let keywords = (theme.searchKeywords ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return ([theme.title] + keywords).filter { $0.count >= 2 }
    }

    // MARK: - 예언

    private static func handleProphecy(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        let matches = (try? store.prophecies(matching: query)) ?? []
        guard !matches.isEmpty else {
            return QueryIntentCard(intent: .prophecy, status: .notReady(
                message: String(localized: "예언 데이터가 아직 준비되지 않았거나, 이 질의와 일치하는 항목이 없습니다. 아래 검색 결과를 확인해 보세요.")
            ))
        }
        return QueryIntentCard(intent: .prophecy, status: .found(.prophecy(matches)))
    }

    // MARK: - 주제·속성·교리·유명 본문

    private static func handleTheme(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        let matches = (try? store.themes(matching: query)) ?? []
        guard !matches.isEmpty else {
            return QueryIntentCard(intent: .themeOrAttribute, status: .notReady(
                message: String(localized: "주제·속성 데이터가 아직 준비되지 않았거나, 이 질의와 일치하는 항목이 없습니다. 아래 검색 결과를 확인해 보세요.")
            ))
        }
        return QueryIntentCard(intent: .themeOrAttribute, status: .found(.theme(matches)))
    }

    // MARK: - 내용 추적·서사

    private static func handleNarrative(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        let events = (try? store.timelineEvents(narrativeMentionedIn: query)) ?? []
        guard !events.isEmpty else {
            return QueryIntentCard(intent: .narrative, status: .notReady(
                message: String(localized: "서사·흐름 데이터가 아직 준비되지 않았거나, 이 질의와 일치하는 항목이 없습니다. 아래 검색 결과를 확인해 보세요.")
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
        let withoutTags = raw.replacingOccurrences(of: "#[0-9]+", with: "", options: .regularExpression)
        // [2026-10-22] 비한국어 화면에서는 "이름#idx(라벨)"의 이름(idx → 번역 이름)과 라벨(번역 사전)을 번역한다.
        // 형식이 맞지 않으면 위 기존 결과(태그만 지움) 그대로다. 한국어 화면은 이 분기를 타지 않는다.
        guard !AppLanguage.isKorean, !raw.isEmpty, let store = ReferenceDataProvider.shared.store,
              let translated = translatedRawSentence(raw, store: store) else {
            return withoutTags
        }
        return translated
    }

    /// PersonSeed 기타관계 원문 한 항목("셈#4649(숙부)", "골리앗#0(형)", "요나단#123", "아무개")을 이름·idx·라벨로 나눠 번역한다.
    /// `build_reference_data.py`가 받아들이는 형식(괄호는 0개 또는 끝에 1개, "#" 뒤는 숫자)만 다루고, 그 밖이면 nil(호출부 폴백).
    /// idx가 없거나 `#0`(미상)이면 이름은 원문 그대로, 번역이 없는 라벨도 원문 그대로다.
    private static func translatedRawSentence(_ raw: String, store: ReferenceDataStore) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        var namePart = Substring(trimmed)
        var label = ""
        let openCount = trimmed.filter { $0 == "(" }.count
        let closeCount = trimmed.filter { $0 == ")" }.count
        if openCount == 0 && closeCount == 0 {
            // 라벨 없음
        } else if openCount == 1, closeCount == 1, trimmed.hasSuffix(")"), let open = trimmed.firstIndex(of: "(") {
            label = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            namePart = trimmed[..<open]
        } else {
            return nil
        }
        var name = String(namePart).trimmingCharacters(in: .whitespaces)
        var idx = ""
        if let hash = name.lastIndex(of: "#") {
            let digits = name[name.index(after: hash)...]
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            idx = String(digits)
            name = String(name[..<hash]).trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty else { return nil }
        let shownName = (idx.isEmpty || idx == "0") ? name : store.displayPersonName(idx: idx, fallback: name)
        guard !label.isEmpty else { return shownName }
        return "\(shownName)(\(store.displayRelationLabel(label)))"
    }

    /// 관계 문장에 넣을 이름(글자만, 링크 없음) — idx가 있으면 그 사람의 번역 이름, idx가 없으면 한국어 이름이 유일한
    /// 인물일 때만 번역 이름, 그 밖은 데이터(한국어) 그대로(`ReferenceDataStore.displayPersonName(word:idx:)`).
    /// idx 없는 행이 많다 — `personRelations(targetWordMentionedIn:)`는 idx 열을 읽지 않는다(한국어 로직 보존을 위해 그대로 둠).
    /// 한국어 화면에서는 쓰지 않는다.
    private static func displayName(word: String, idx: String) -> String {
        ReferenceDataProvider.shared.store?.displayPersonName(word: word, idx: idx) ?? word
    }

    static func sentence(for relation: PersonRelationRecord) -> String {
        // 한국어 화면은 아래 기존 문장(조사 자동 선택)을 그대로 쓴다.
        guard AppLanguage.isKorean else { return localizedSentence(for: relation) }
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
        case "husbands_father_of": return "\(source)\(sourceEunNeun) \(target)의 시아버지"
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

    /// 한국어가 아닌 화면용 관계 문장. 한국어 문장은 조사(은/는, 와/과)를 이름의 받침으로 고르지만,
    /// 다른 언어는 조사가 없어 언어별 문장 템플릿(String Catalog)을 그대로 쓴다.
    /// [2026-10-22] 인물 이름은 번역 이름(`PersonsI18n.word`)으로 — idx가 없으면 한국어 이름이 유일한 인물일 때만(`displayName`).
    private static func localizedSentence(for relation: PersonRelationRecord) -> String {
        let source = displayName(word: relation.sourceWord, idx: relation.sourceIdx)
        // 대상이 지명이면 인물 사전으로 번역하지 않는다(우연히 같은 한국어 인물 이름이 있어도 섞이지 않게).
        let target = relation.targetKind == .place ? relation.targetWord : displayName(word: relation.targetWord, idx: relation.targetIdx)
        switch relation.relationType {
        case "son_of": return String(localized: "\(source)은(는) \(target)의 아들", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "daughter_of": return String(localized: "\(source)은(는) \(target)의 딸", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "grandson_of": return String(localized: "\(source)은(는) \(target)의 손자", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "granddaughter_of": return String(localized: "\(source)은(는) \(target)의 손녀", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "grandfather_of": return String(localized: "\(source)은(는) \(target)의 할아버지", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "grandmother_of": return String(localized: "\(source)은(는) \(target)의 할머니", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "maternal_grandfather_of": return String(localized: "\(source)은(는) \(target)의 외할아버지", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "maternal_grandmother_of": return String(localized: "\(source)은(는) \(target)의 외할머니", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "co_worker_of": return String(localized: "\(source)은(는) \(target)의 동역자", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "father_of": return String(localized: "\(source)은(는) \(target)의 아버지", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "mother_of": return String(localized: "\(source)은(는) \(target)의 어머니", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "wife_of": return String(localized: "\(source)은(는) \(target)의 아내", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "husband_of": return String(localized: "\(source)은(는) \(target)의 남편", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "daughter_in_law_of": return String(localized: "\(source)은(는) \(target)의 며느리", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "father_in_law_of": return String(localized: "\(source)은(는) \(target)의 장인", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "husbands_father_of": return String(localized: "\(source)은(는) \(target)의 시아버지", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "son_in_law_of": return String(localized: "\(source)은(는) \(target)의 사위", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "great_grandfather_of": return String(localized: "\(source)은(는) \(target)의 증조부", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "adversary_of": return String(localized: "\(source)은(는) \(target)의 대적", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "ally_of": return String(localized: "\(source)은(는) \(target)의 동맹", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "related_to": return String(localized: "\(source)은(는) \(target)와(과) 관련 있음", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "brother_of": return String(localized: "\(source)은(는) \(target)의 형제", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "younger_brother_of": return String(localized: "\(source)은(는) \(target)의 아우", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "older_brother_of": return String(localized: "\(source)은(는) \(target)의 형", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "sister_of": return String(localized: "\(source)은(는) \(target)의 자매", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "uncle_of": return String(localized: "\(source)은(는) \(target)의 삼촌", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "cousin_of": return String(localized: "\(source)은(는) \(target)의 사촌", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "descendant_of": return String(localized: "\(source)은(는) \(target)의 후손", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "ancestor_of": return String(localized: "\(source)은(는) \(target)의 조상", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "teacher_of": return String(localized: "\(source)은(는) \(target)의 스승", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "king_of": return String(localized: "\(source)은(는) \(target)의 왕", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "married_to": return String(localized: "\(source)은(는) \(target)와(과) 결혼한 사이", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "friend_of": return String(localized: "\(source)은(는) \(target)의 친구", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "tribe_of": return String(localized: "\(source)은(는) \(target) 지파 소속", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "people_of": return String(localized: "\(source)은(는) \(target) 족속 소속", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        case "affiliated_with_place": return String(localized: "\(source)은(는) \(target) 사람(출신)", comment: "인물 관계 문장 — 첫 번째 값: 인물, 두 번째 값: 관계 대상 인물")
        default:
            let cleaned = relation.relationType.replacingOccurrences(of: "_", with: " ")
            return "\(source) - \(cleaned) - \(target)"
        }
    }
}
