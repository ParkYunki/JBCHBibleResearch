//
//  QueryIntentHandler.swift
//  JBCHBibleResearch
//
//  [2026-08-20 신설] `QueryIntentClassifier.swift` 상단 주석의 3계층 구조 중
//  2계층(Handler). Classifier(1계층, 순수 텍스트 패턴)가 정한 카테고리별로
//  실제 테이블(PersonRelations/Persons·Places/Prophecies/Themes/
//  TimelineEvents)을 조회해 "카드" 하나로 정리한다. `SearchView`가 이 카드를
//  일반 검색 결과 목록 맨 위에 보여준다 — 일반 검색(3계층,
//  `SearchViewModel.performKeywordSearch`/`performAIQuerySearch`)은 이 카드의
//  결과와 무관하게 항상 그대로 실행된다(`SearchViewModel.performSearch` 참고).
//  그래서 이 Handler가 못 찾거나(데이터 없음/오분류) 잘못 분류돼도 검색
//  자체가 막히거나 나빠지지 않는다 — 3계층 구조 전체의 안전장치.
//
//  Prophecies/Themes/TimelineEvents 세 테이블은 지금 스키마만 있고 데이터가
//  0건이라(`ReferenceDataStore.swift`/`build_reference_data.py` 참고), 이
//  세 카테고리는 사실상 항상 `.notReady`로 응답한다 — 나중에 데이터가
//  채워지면 이 파일을 손대지 않아도 자동으로 `.found`로 바뀐다(그게 스키마를
//  먼저 만들어 둔 이유).
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — 이 프로젝트의
//  다른 신규 Swift 파일들과 같은 caveat.
//

import Foundation
import BibleResearchModels

/// [2026-08-20 신설, Phase 4] 관계 카드 한 행 + 그 행의 "새로 알게 된 쪽"
/// 인물의 성경 좌표.
///
/// 실사용 리포트: "다윗의 아들들은?" 카드(관계 정보)는 정확한데, 그 아래
/// "성경 구절"이 관계와 무관하다는 문제였다. 원인은 두 가지가 섞여 있었다:
/// 1) (설계상 정상) `SearchView`가 항상 그리는 이 카드는 관계 목록일 뿐이고,
///    카드 아래 "검색 결과" 섹션은 `SearchViewModel.performSearch`가 이
///    카드와 무관하게 항상 실행하는 3계층 일반 검색(질의 원문으로 FTS 매칭)
///    결과다 — 애초에 "이 관계의 근거 구절"이 아니라 "질의 원문과 텍스트가
///    비슷한 구절"이라 관계와 안 맞아 보일 수 있다. 이 계층은 그대로 둔다
///    (`QueryIntentHandler` 상단 주석 — 항상 유지되는 안전장치).
/// 2) (실제 버그, 이번에 수정) 카드 자체(관계 행)엔 애초에 성경 구절이 전혀
///    붙어있지 않았다 — `PersonRelationRecord`엔 `rawSentence`(관계가 추출된
///    원본 설명 문장)만 있고 좌표 필드가 없다. `PersonPlaceSeed.json`에
///    인물별 `verses`가 이미 있으므로, 관계의 "새로 알게 된 쪽" 인물 이름으로
///    `ReferenceDataStore.personOrPlace(exactWord:)`를 조회해 그 인물의
///    verses를 이 행에 붙인다.
///
/// "새로 알게 된 쪽"이 source/target 중 어느 쪽인지는 조회 방향마다 달라
/// 호출부(`handleRelation`)가 `answerWord` 클로저로 명시한다(각 호출 지점
/// 주석 참고) — 예를 들어 "다윗의 아들들은?"에선 다윗은 질의에 이미 있는
/// 정보고 압살롬/솔로몬처럼 나열되는 source가 새 정보다.
struct RelationDisplayItem {
    let relation: PersonRelationRecord
    /// 조회 실패(그 이름이 Persons/Places에 없음 — 체크포인트가 일부만 담긴
    /// 인물 등)면 빈 배열. `SearchView`는 이 경우 내비게이션 없이 텍스트만
    /// 보여준다(`personOrPlaceRow`와 같은 패턴).
    let verseRefs: [BibleVerseRef]
}

/// Handler 조회 결과 하나 — 카테고리(`intent`)와 상태(`status`).
struct QueryIntentCard {
    enum Content {
        case relation([RelationDisplayItem])
        case personOrPlace([ReferenceEntity])
        case prophecy([ProphecyRecord])
        case theme([ThemeRecord])
        case narrative([NarrativeGroup])

        /// [2026-08-20 신설, Phase 5] 이 카드가 가리키는 성경 좌표 전체 —
        /// 화면에 나온 순서 그대로, 중복 제거. `SearchViewModel.
        /// performAIQuerySearch`가 이 값을 "성경구절" 섹션에 직접 채운다:
        /// 카드가 이미 정확한 답(관계/인물·지명/예언/주제/서사)을 확정했다면,
        /// 굳이 별도의 근사 검색(임베딩 의미검색 + 키워드 하이브리드 병합)을
        /// 또 돌려 다른(때로는 무관한) 결과를 "성경구절" 섹션에 보여줄 이유가
        /// 없다는 판단 — 사용자 리포트("다윗의 아들들"을 검색하면 성경구절
        /// 섹션에 각 아들의 실제 절이 아니라 키워드 검색 가중치 계산값이
        /// 나온다)에 대한 근본 수정.
        ///
        /// 각 케이스가 이미 들고 있는 verse 필드를 그대로 모을 뿐, DB를 새로
        /// 조회하지 않는다 — `relation`의 `RelationDisplayItem.verseRefs`는
        /// `handleRelation`에서 이미 `personOrPlace(exactWord:)`로 해결해
        /// 뒀고, 나머지 케이스도 각자의 SQL 조회 시점에 이미 채워져 있다.
        var verseRefs: [BibleVerseRef] {
            var seen = Set<BibleVerseRef>()
            func dedup(_ refs: [BibleVerseRef]) -> [BibleVerseRef] {
                refs.filter { seen.insert($0).inserted }
            }
            switch self {
            case .relation(let items):
                return dedup(items.flatMap { $0.verseRefs })
            case .personOrPlace(let entities):
                return dedup(entities.flatMap { $0.verseRefs })
            case .prophecy(let records):
                // 예언 절 + 성취/대응 절 둘 다 "이 예언에 관한 성경구절"이라
                // 함께 담는다 — 성취 절이 없는(아직 이루어지지 않은) 예언은
                // `fulfillmentRefs`가 빈 배열이라 자연히 예언 절만 남는다.
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
        /// 데이터가 아예 없거나(테이블이 비어 있음), 데이터는 있지만 이
        /// 질의와 일치하는 항목이 없는 경우 — 두 경우를 구분하지 않고 한
        /// 메시지로 합쳤다(현재는 항상 전자지만, 문구 자체는 나중에 데이터가
        /// 일부만 채워진 상태에서도 그대로 맞게 만들어 뒀다 — 구분하려면
        /// 테이블 전체 건수를 별도로 세야 하는데, 지금은 그 정도까지 필요한
        /// 상황이 아니라 오버엔지니어링을 피했다).
        case notReady(message: String)
    }

    let intent: QueryIntentClassifier.Intent
    let status: Status
}

extension QueryIntentCard {
    /// `.notReady`면 빈 배열 — `Content.verseRefs` 참고(카드가 확정한 성경
    /// 좌표 전체). `SearchViewModel.performAIQuerySearch`가 이 값이 비어
    /// 있지 않으면 그대로 "성경구절" 섹션에 채운다.
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
            case .personOrPlace(let items): return items.count
            case .prophecy(let items): return items.count
            case .theme(let items): return items.count
            case .narrative(let groups): return groups.reduce(0) { $0 + $1.events.count }
            }
        }
    }
}

/// `TimelineEvents`는 한 서사가 여러 행(사건)으로 나뉘어 있어, 조회 결과를
/// `narrative_key` 단위로 묶어야 화면에서 서사 하나로 보인다.
/// `ReferenceDataStore.timelineEvents(narrativeMentionedIn:)`가 이미
/// `narrative_key ASC, sequence_order ASC`로 정렬해서 돌려주므로, 같은
/// narrative_key는 항상 연속으로 붙어 있다 — `groupByNarrative`가 이 성질에
/// 기대어 단순 순차 그룹핑만 한다(재정렬하지 않음).
struct NarrativeGroup: Identifiable {
    let narrativeKey: String
    let narrativeTitle: String
    let events: [TimelineEventRecord]
    var id: String { narrativeKey }
}

@MainActor
enum QueryIntentHandler {
    /// `intent == .general`이면 nil — `SearchView`는 이 경우 카드 섹션 자체를
    /// 그리지 않는다. `ReferenceDataProvider.shared.store`가 nil이면(번들에
    /// `ReferenceData.sqlite`가 없는 손상된 설치) 마찬가지로 nil을 돌려준다 —
    /// 이건 이 기능 자체의 "데이터 없음"이 아니라 앱 설치 문제라, 카테고리별
    /// 안내 문구로 설명할 성질이 아니라고 판단했다.
    static func handle(_ query: String, intent: QueryIntentClassifier.Intent) -> QueryIntentCard? {
        guard intent != .general else { return nil }
        guard let store = ReferenceDataProvider.shared.store else { return nil }
        switch intent {
        case .relation: return handleRelation(query, store: store)
        case .personOrPlaceInfo: return handlePersonOrPlace(query, store: store)
        case .prophecy: return handleProphecy(query, store: store)
        case .themeOrAttribute: return handleTheme(query, store: store)
        case .narrative: return handleNarrative(query, store: store)
        case .general: return nil
        }
    }

    // MARK: - 관계

    /// `BibleStructuralRerankerService.computeBoosts`의 1)+2)+2b) 블록과 같은
    /// 원칙 — 정방향(질의에 나온 이름이 source인 경우, 예: "다윗의 아들")과
    /// 역방향(질의에 나온 이름이 target으로만 있는 경우, 예: "골리앗의 동생" —
    /// "골리앗"은 Persons에 행이 없어 정방향만으로는 못 찾음)을 둘 다 모아야
    /// 빠짐없이 찾는다.
    ///
    /// [2026-08-20 갱신] 사용자가 구체적인 정확도 기준을 제시함 — "아브라함의
    /// 아들은? / 이삭의 아버지는? / 다윗의 아들들은? / 압살롬의 부모는?"이
    /// 정확히 나와야 함. 기존 로직(엔티티와 관련된 모든 관계를 타입 구분 없이
    /// 나열)은 이 네 질문에 대해 "관계는 찾지만 다른 관계와 뒤섞여 나오거나
    /// (아들/아들들), 필요한 관계 타입 자체가 원본 텍스트에서 누락돼 있어
    /// (이삭의 아버지 — `build_reference_data.py`의 괄호 병기 추출 개선으로
    /// 별도 해결) 정확히 답하지 못했다. `detectRelationSubQuery`로 질의에서
    /// 구체적 관계 타입을 감지해, 감지되면 그 타입으로만 정확히 필터링한다.
    /// 감지되지 않는 관계어(형제/할아버지/스승 등 나머지 18종)는 아래 기존
    /// 폴백(엔티티 관련 관계 전체 나열)으로 처리한다 — 틀린 답을 주진 않지만
    /// 원하는 관계만 콕 집어 보여주진 못한다는 뜻이다. 이번 개선 범위를
    /// 사용자가 실측으로 요구·검증한 위 4가지 질문 패턴으로 한정했다(근거
    /// 없이 24종 전체를 미리 다 매핑하지 않음).
    ///
    /// [2026-08-20 갱신, Phase 5] 사용자가 "다윗의 아내"를 실측해 관계정보가
    /// 엉망(타입 필터링 없이 다윗의 모든 관계가 섞여 나옴)임을 지적 — "아내"/
    /// "남편"(wife_of/husband_of)을 위 정밀 필터링 목록에 추가해 6종으로
    /// 늘렸다(`detectRelationSubQuery` 참고). 나머지 16종은 여전히 폴백.
    private static func handleRelation(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        var combined: [RelationDisplayItem] = []
        var seen = Set<String>()
        // [2026-08-20 갱신, Phase 4] `answerWord`가 이 행에서 "새로 알게 된
        // 쪽"의 이름을 골라준다 — 그 이름으로 `personOrPlace(exactWord:)`를
        // 조회해 verses를 붙인다(`RelationDisplayItem` 주석 참고). 조회
        // 실패(이름이 없거나 Persons/Places에 없음)해도 빈 배열로 안전하게
        // 처리되므로 관계 표시 자체는 막히지 않는다.
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
                    // [2026-08-21 수정] 사용자 지적 — "노아의 아버지는?"(역방향,
                    // 라멕이 정답)과 "노아가 아버지인 사람"(정방향, 셈/함/야벳이
                    // 정답)이 지금까지는 둘 다 같은 역방향 조회로 처리돼 후자가
                    // 틀린 답(라멕)을 냈다 — 조사를 전혀 안 봤기 때문. entity
                    // 이름 바로 뒤 조사가 "이/가"(주격)면 entity가 source인
                    // 정방향으로, 그 외(기본값 "의" 등)는 기존처럼 역방향으로
                    // 조회한다. 이 이분법은 아들/딸/손자/손녀/아버지/어머니처럼
                    // "역할이 방향을 가리키는" 유형 전부에 똑같이 적용된다(예:
                    // "노아가 아들인 사람"도 같은 논리로 노아의 아버지를 찾아야
                    // 맞다) — 타입별로 따로 분기하지 않고 한 번에 처리.
                    if subjectDirection(for: entity.word, in: query) == true {
                        let forwardRows = (try? store.personRelations(forWord: entity.word)) ?? []
                        add(forwardRows.filter { types.contains($0.relationType) },
                            answerWord: { $0.targetWord })
                    } else {
                        // "OO의 아들/딸/자녀는?" — source가 OO의 자녀임을 뜻하는
                        // 타입이므로 target=OO 쪽에서 찾는다(역방향). 새로 알게
                        // 된 답은 source(자녀 이름)다.
                        add(reverseRows.filter { $0.targetWord == entity.word && types.contains($0.relationType) },
                            answerWord: { $0.sourceWord })
                    }
                case .parents:
                    // "OO의 부모는?" — 부모 쪽 항목이 "OO의 아버지/어머니이다"로
                    // 직접 서술된 경우(역방향, target=OO, 답은 source=부모)와,
                    // OO 자신의 항목이 "A와 B 사이의 아들/딸이다"로 양쪽 부모를
                    // 서술한 경우(정방향, source=OO, 답은 target=부모) 둘 다
                    // 있을 수 있어 합친다 — 두 방향의 "답 쪽"이 서로 반대다.
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
            // 타입 필터링 결과가 비어 있으면(질문 유형은 알아냈지만 해당 관계
            // 데이터가 아직 없음) 아래 기존 폴백으로 넘어간다 — 관련 있을 법한
            // 다른 관계라도 보여주는 게 빈 카드보다 낫다고 판단.
        }

        for entity in personEntities {
            // 폴백(관계 타입 미지정) — entity가 source인 정방향 행이라 target이
            // 새 정보(예: entity="다윗", 행=(다윗, king_of, 유다) → 답=유다).
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

    /// `handleRelation` 전용 — 질의 문자열에서 구체적인 관계 타입을 감지한다.
    /// 검사 순서가 중요하다: 지금은 서로 겹치는 부분 문자열이 없음을 직접
    /// 확인했지만("부모"/"자녀"/"자식"/"아들"/"딸"/"아버지"/"부친"/"어머니"/
    /// "모친" 중 어느 것도 다른 것의 부분 문자열이 아님), 나중에 키워드를
    /// 추가할 땐(예: "할아버지"는 "아버지"를 부분 문자열로 포함) 반드시 더
    /// 구체적인 키워드를 먼저 검사하도록 순서를 조정해야 한다.
    private enum RelationSubQuery {
        /// "OO의 <역할>은?" — target == OO, relationType이 이 목록에 속하는
        /// 행만 골라 source를 답으로 보여준다(예: 아들/딸/자녀/아버지/어머니).
        case reverseByType([String])
        /// "OO의 부모는?" 전용 — 위 reverseByType(father_of/mother_of)과
        /// forward(son_of/daughter_of)를 합친다(주석 참고).
        case parents
    }

    /// [2026-08-21 신설] `entityWord` 바로 뒤(공백 없이 붙어서)에 오는 글자가
    /// 주격 조사("이"/"가")면 true(entity가 문장의 주어 = source), 관형격
    /// 조사("의")면 false(entity가 소유자 = target), 그 외/조사 없음/이름을
    /// 못 찾음이면 nil(호출부가 기존 동작인 역방향으로 안전하게 폴백)을
    /// 돌려준다. `query.range(of:)`는 첫 등장만 찾으므로, 같은 이름이 질의에
    /// 두 번 나오는 드문 경우엔 첫 번째 등장 기준으로 판단한다 — 실사용
    /// 질의(짧은 검색어)에서 발생 가능성이 낮다고 보고 오버엔지니어링을
    /// 피했다.
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
        // [2026-08-21 추가] 사용자 신고 — "노아의 손자"가 정밀 필터링 없이
        // 폴백(엔티티 관련 모든 관계 무차별 나열)으로 빠져 아들/아버지/후손이
        // 뒤섞여 나왔다. `grandson_of`(61건)/`granddaughter_of`(1건) 데이터가
        // 실제로 있으므로 다른 6종과 같은 방식으로 추가한다 — "손자"가
        // "아들"/"딸" 어느 것의 부분 문자열도 아님을 확인(순서 무관).
        if query.contains("손자") { return .reverseByType(["grandson_of"]) }
        if query.contains("손녀") { return .reverseByType(["granddaughter_of"]) }
        if query.contains("아버지") || query.contains("부친") { return .reverseByType(["father_of"]) }
        if query.contains("어머니") || query.contains("모친") { return .reverseByType(["mother_of"]) }
        // [2026-08-20 추가, Phase 5] 사용자 리포트 — "다윗의 아내"라고 검색하면
        // 관계정보가 엉망(타입 구분 없이 다윗의 모든 관계가 섞여 나옴). "아내"/
        // "남편"이 여기 없어서 위 5종과 달리 정밀 필터링 없이 아래 폴백(엔티티
        // 관련 관계 전체 나열)으로 빠졌던 것 — 5종과 같은 방식으로 추가한다.
        // `RelationSynonyms`의 "아내" 그룹엔 "부인"/"처"도 있지만, "처"는 한
        // 글자라 "처음"/"처녀"/"출처" 같은 무관한 단어에도 부분 문자열로
        // 걸릴 위험이 커서(`build_reference_data.py`가 추출 패턴에서 같은
        // 이유로 "처"를 뺀 것과 같은 근거) 여기(관계 타입 정밀 판정)엔 넣지
        // 않았다 — Layer 1 분류(`QueryIntentClassifier.isRelationQuery`)는
        // 이미 `RelationSynonyms.allWords`로 "처"까지 넓게 잡아 relation
        // 카테고리 자체는 놓치지 않으므로, 여기서 좁게 잡아도 최악의 경우
        // 아래 폴백(전체 나열)으로만 떨어질 뿐 관계 자체를 못 찾는 건 아니다.
        if query.contains("아내") || query.contains("부인") { return .reverseByType(["wife_of"]) }
        if query.contains("남편") { return .reverseByType(["husband_of"]) }
        return nil
    }

    // MARK: - 인물·지명 정보

    private static func handlePersonOrPlace(_ query: String, store: ReferenceDataStore) -> QueryIntentCard {
        let entities = (try? store.personsAndPlaces(mentionedIn: query)) ?? []
        guard !entities.isEmpty else {
            return QueryIntentCard(intent: .personOrPlaceInfo, status: .notReady(
                message: "이 질의에서 등록된 인물·지명을 찾지 못했습니다. 아래 검색 결과를 확인해 보세요."
            ))
        }
        return QueryIntentCard(intent: .personOrPlaceInfo, status: .found(.personOrPlace(entities)))
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

/// [2026-08-20 신설] `PersonRelations.relation_type`(예: `younger_brother_of`)을
/// 사람이 읽을 문장으로 바꾼다.
///
/// `PersonRelations.pattern_label` 컬럼을 재사용하지 않고 새로 만든 이유:
/// 그 컬럼은 "정규식 패턴이 무엇을 매치했는지" 기록하는 개발용 주석이라
/// "[2026-08-19 동의어 확장]"/"(entry가 X의 아버지)" 같은 구현 메모가 그대로
/// 섞여 있다(`build_reference_data.py`의 `RELATION_PATTERNS` 참고) — 검색
/// 화면에 그대로 노출하면 어색하다. `RelationSynonyms`(검색어 확장 목적)가
/// 원본 추출 정규식과 별도로 유지되는 것과 같은 논리로("성격이 다른 목적은
/// 별도로 큐레이션한다", `BibleKeywordMatching.swift` 상단 주석 참고),
/// `relation_type`(28종 — 2026-08-19 기준 24종 + 2026-08-20 신설
/// grandmother_of/maternal_grandfather_of/maternal_grandmother_of/
/// co_worker_of, `RELATION_PATTERNS`를 전수 확인해 빠짐없이 옮겼다)
/// 만 가지고 화면 전용 문장을 새로 만들었다 — 개수가 작고 거의 안 늘어나는
/// 고정 어휘라는 점에서 `relation_type` 자체를 정규화 테이블 대신 TEXT로 둔
/// 이 프로젝트의 기존 원칙과 같은 이유로, 하드코딩 매핑이 안전하다.
///
/// 방향 규칙: `build_reference_data.py` 상단 주석 — "모든 relation_type은
/// source가 target의 ROLE"(예: `(라흐미, younger_brother_of, 골리앗)` ==
/// "라흐미는 골리앗의 아우"). 단 `tribe_of`/`people_of`/`affiliated_with_place`
/// 세 개("느슨한 4종" 중 `king_of`를 뺀 나머지, 그 파일 주석 참고)는 방향이
/// 반대다 — "source가 target 소속"이다(원본 정규식이 "~ 지파"/"~ 족속"/"~
/// 사람"처럼 entry 자신의 소속을 서술하는 문장에서 나오기 때문).
enum PersonRelationLabeling {
    // [2026-08-21 신설] 사용자 신고 — "룻는 노아의 손자", "레멕는 노아의 손자"가
    // 아니라 "룻은 노아의 손자", "레멕은 노아의 손자"가 맞는 표기(받침 있으면
    // "은", 없으면 "는"). 28차에 이미 같은 유형("다윗는")으로 발견됐었으나
    // 그때는 미수정 상태로 남겨뒀던 것 — 이번에 아래 `source` 뒤 조사를 전부
    // 계산해서 붙이도록 고친다. `married_to`의 "\(target)와"도 같은 문제(받침
    // 있으면 "과")라 함께 고쳤다 — 이 파일에서 받침에 따라 갈리는 조사는 이
    // 두 자리(소스 뒤 은/는, married_to의 타깃 뒤 와/과)뿐임을 전수 확인했다
    // ("의"는 받침 유무와 무관하게 항상 "의"라 그대로 둠).
    //
    // 받침 판정 근거: 완성형 한글 음절(U+AC00~U+D7A3)은 코드값이
    // `0xAC00 + (초성*21 + 중성)*28 + 종성` 순으로 배열돼 있어(유니코드
    // 한글 음절 조합 규칙, KS X 1001/유니코드 표준), `(코드값 - 0xAC00) % 28`이
    // 0이면 종성(받침)이 없고, 0이 아니면 있다 — 예: "아"(U+C544, 받침 없음)는
    // (0xC544-0xAC00)%28 == 0, "룻"(U+B987, ㅅ받침)은 0이 아님. 실제 이름
    // 13개(노아/룻/레멕/다윗/가나안/야곱/모세/다시스/엘리사/훌/라멕/예수/바울)로
    // 파이썬으로 미리 검산해 전부 기대한 은/는·과/와가 나오는 것을 확인했다.
    // 한글 완성형 음절이 아닌 문자로 끝나는 이름(현재 데이터엔 없음)은 판정
    // 불가이므로 기존 동작과 같은 "는"/"와"로 안전하게 폴백한다.
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
        // [2026-08-20 신설] 사용자 요청으로 build_reference_data.py에 신설된
        // 4종(grandmother_of/maternal_grandfather_of/maternal_grandmother_of/
        // co_worker_of)의 화면 표시 문장. 방어적 폴백(아래 default)이 있어
        // 이 case들을 안 넣어도 완전히 깨지진 않지만("(source) - grandmother
        // of - (target)" 같은 어색한 문구), 자연스러운 한국어 문장을 위해
        // 24종과 동일한 방식으로 추가했다.
        case "grandmother_of": return "\(source)\(sourceEunNeun) \(target)의 할머니"
        case "maternal_grandfather_of": return "\(source)\(sourceEunNeun) \(target)의 외할아버지"
        case "maternal_grandmother_of": return "\(source)\(sourceEunNeun) \(target)의 외할머니"
        case "co_worker_of": return "\(source)\(sourceEunNeun) \(target)의 동역자"
        case "father_of": return "\(source)\(sourceEunNeun) \(target)의 아버지"
        case "mother_of": return "\(source)\(sourceEunNeun) \(target)의 어머니"
        case "wife_of": return "\(source)\(sourceEunNeun) \(target)의 아내"
        case "husband_of": return "\(source)\(sourceEunNeun) \(target)의 남편"
        case "daughter_in_law_of": return "\(source)\(sourceEunNeun) \(target)의 며느리"
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
        case "tribe_of": return "\(source)\(sourceEunNeun) \(target) 지파 소속"
        case "people_of": return "\(source)\(sourceEunNeun) \(target) 족속 소속"
        case "affiliated_with_place": return "\(source)\(sourceEunNeun) \(target) 사람(출신)"
        default:
            // [방어적 폴백] 위 28종은 RELATION_PATTERNS를 전수 확인한 결과라
            // 이 분기를 타지 않는 게 정상이다 — 새 relation_type이 추가됐는데
            // 이 매핑이 못 따라간 경우에도 값을 숨기지 않고 최소한의 정리
            // (밑줄→공백)만 해서 보여준다.
            let cleaned = relation.relationType.replacingOccurrences(of: "_", with: " ")
            return "\(source) - \(cleaned) - \(target)"
        }
    }
}
