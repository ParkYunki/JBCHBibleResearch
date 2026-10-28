import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

//
//  PersonDetailView.swift
//  JBCHBibleResearch
//
//  통합검색 "인물 정보" 카드 항목 하나의 상세 콘텐츠(개요/생애/업적/성품, 인물 정보,
//  관계, 소속 그룹, 기타 정보, 관련 성경구절).
//  `body`는 `List`를 갖지 않고 `Section` 묶음(`Group`)만 돌려준다 — `SearchContentView`가
//  자신의 `List`에 그대로 끼우거나(아이폰) 별도 `List`로 감싸 상세 칼럼에 넣는다(맥/아이패드).
//  그래서 `.navigationTitle`/push 목적지로는 쓰이지 않는다.
//
//  색은 시스템 강조색·시맨틱 색과 `UserSettingsStore.bibleTextColor` 테마를 따른다(커스텀 hex 지양).
//  가족 관계 9종은 `PersonEntity.familyRelations`(Persons 테이블 rel_* 컬럼, PersonSeed.json
//  원본 그대로)에서 읽는다 — PersonRelations 테이블은 4쌍을 표제어 성별로만 저장해 원래 필드를
//  구분할 수 없기 때문. 기타관계는 `person.relations`에서 골라낸다.
//  관련 성경구절은 통합검색 "성경구절" 탭과 같은 "장별 카드 + N절) 본문" 스타일로 그린다.
struct PersonDetailView: View {
    /// 관계 목록에서 다른 인물로 이동하기 위한 로컬 스택. `.searchable` 화면에서
    /// `NavigationLink(value:)`/`.navigationDestination`을 쓰면 아이폰에서 구조적 결함이 있어 push를
    /// 쓰지 않고, 화면이 그리는 대상(`person`)을 `relationStack` 맨 위로 갈아 끼운다.
    /// `initialPerson`은 처음 전달받은 인물.
    private let initialPerson: PersonEntity
    @State private var relationStack: [PersonEntity] = []

    init(person: PersonEntity) {
        self.initialPerson = person
    }

    private var person: PersonEntity { relationStack.last ?? initialPerson }

    private var settings: UserSettingsStore { .shared }

    /// 행 구분선. `Divider()`는 시스템 회색 고정이라 카드 배경(`bibleTextColor` 기반 톤)과
    /// 어울리지 않아 같은 톤을 옅게 쓴다.
    private func subtleRowDivider() -> some View {
        Rectangle()
            .fill((settings.bibleTextColor ?? .primary).opacity(0.12))
            .frame(height: 0.75)
    }

    /// "인물 정보" 절에 보여줄 항목 — 빈 값은 목록에서 뺀다.
    /// [2026-10-22] 값은 번역 표시(`display*` — 한국어 앱이면 원본 그대로). 성별 판정 등 로직은 한국어 원본 필드를 쓴다.
    private var infoFacts: [(label: String, value: String)] {
        var facts: [(String, String)] = []
        if !person.displayOrigin.isEmpty { facts.append((String(localized: "출신"), person.displayOrigin)) }
        if !person.displayGender.isEmpty { facts.append((String(localized: "성별"), person.displayGender)) }
        if !person.displayTribe.isEmpty { facts.append((String(localized: "지파"), person.displayTribe)) }
        if !person.displayNation.isEmpty { facts.append((String(localized: "민족"), person.displayNation)) }
        if !person.displayAliases.isEmpty { facts.append((String(localized: "별칭"), person.displayAliases.joined(separator: " · "))) }
        return facts
    }

    /// [2026-10-22] 관계·소속 그룹·기타 정보 행의 이름을 표시용 번역으로 바꾼다(idx가 확정된 이름만 — `displayPersonName`).
    /// 반드시 `uniqueOrdered` **뒤에** 부른다: 먼저 번역하면 idx 없는 한국어 이름과 idx 있는 번역 이름이 같은 사람인데도
    /// 합쳐지지 않는다. idx는 그대로라 링크(`relationRow`의 `resolvedRelationPerson`)는 idx로 확정된다.
    /// 한국어 앱이면(`contentLanguage == nil`) 입력 그대로.
    private func localizedNames(_ items: [(name: String, idx: String)]) -> [(name: String, idx: String)] {
        guard let store = ReferenceDataProvider.shared.store, store.contentLanguage != nil else { return items }
        return items.map { item in
            (name: store.displayPersonName(idx: item.idx, fallback: item.name), idx: item.idx)
        }
    }

    /// `BibleVerseChipRow.isPhoneIdiom`과 같은 판정 — 아이폰은 조상 `NavigationStack`에
    /// `BibleVerseDestinationRegistration`이 없어 `NavigationLink(value:)`를 직접 쓸 수 없다.
    /// 짧은 판정이라 추출하지 않고 복제했다.
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// "관계" 절 — 할아버지~손녀 9종을 라벨 순서대로, 비어있지 않은 것만.
    /// `PersonEntity.familyRelations`(PersonSeed.json 원본 그대로)를 쓰며, `otherRelationRows`와
    /// 타입을 맞추려 이름을 `(name, idx)` 쌍으로 감싼다.
    private var familyRelationRows: [(label: String, names: [(name: String, idx: String)])] {
        let f = person.familyRelations
        // `PersonFamilyMember.idx`("이름#idx" 태그)가 있으면 그대로 쓰고, 없으면 ""(이름 기준
        // 동명이인 검사로 폴백). 괄호 설명(note)은 `(name, idx)` 타입을 유지하려고 "이름(설명)"으로
        // 이어붙인다.
        // [2026-10-22] 이름은 idx로(`displayPersonName`), 괄호 설명은 번역 사전으로(`displayRelationLabel`) 표시만 번역한다.
        // 한국어 앱이면 두 사전이 비어 있어 결과가 이전과 같다.
        let store = ReferenceDataProvider.shared.store
        // [2026-10-27 6차] 한 라벨 안의 이름은 성경 첫 등장 순(사용자 확정 — 시드에 적힌 순서 대신). 모르는 이름은 뒤, 같으면 시드 순서.
        // 표시용 "이름(설명)"으로 바꾸기 전에 원래 이름·idx로 정렬한다.
        func wrap(_ members: [PersonFamilyMember]) -> [(name: String, idx: String)] {
            let ordered = store?.sortedByFirstAppearance(members, idx: { $0.idx }, word: { $0.name }) ?? members
            return ordered.map { member in
                let name = store?.displayPersonName(idx: member.idx, fallback: member.name) ?? member.name
                let note = member.note.isEmpty ? "" : (store?.displayRelationLabel(member.note) ?? member.note)
                let displayName = note.isEmpty ? name : "\(name)(\(note))"
                return (name: displayName, idx: member.idx)
            }
        }
        var rows: [(String, [(name: String, idx: String)])] = []
        if !f.grandfathers.isEmpty { rows.append((String(localized: "할아버지"), wrap(f.grandfathers))) }
        if !f.grandmothers.isEmpty { rows.append((String(localized: "할머니"), wrap(f.grandmothers))) }
        if !f.fathers.isEmpty { rows.append((String(localized: "아버지"), wrap(f.fathers))) }
        if !f.mothers.isEmpty { rows.append((String(localized: "어머니"), wrap(f.mothers))) }
        if !f.spouses.isEmpty { rows.append((String(localized: "배우자"), wrap(f.spouses))) }
        if !f.sons.isEmpty { rows.append((String(localized: "아들"), wrap(f.sons))) }
        if !f.daughters.isEmpty { rows.append((String(localized: "딸"), wrap(f.daughters))) }
        if !f.grandsons.isEmpty { rows.append((String(localized: "손자"), wrap(f.grandsons))) }
        if !f.granddaughters.isEmpty { rows.append((String(localized: "손녀"), wrap(f.granddaughters))) }
        return rows
    }

    /// 같은 사람이 두 번 나오지 않게 중복을 제거하되 들어온 순서를 유지한다. 기준은 idx가 있으면 idx, 없으면 이름이다 —
    /// 이름만 보면 열두 제자의 "야고보"(#2261)와 "야고보"(#4055)처럼 이름만 같은 서로 다른 사람이 하나로 합쳐진다.
    /// idx가 빈 항목은 같은 이름의 항목이 이미 있으면 그쪽에 합치고(뒤에 온 idx가 있으면 채움), 이름이 같은 항목이
    /// idx로 이미 구분돼 여럿이면 어느 쪽인지 알 수 없어 새로 더하지 않는다.
    /// "동역자"/"친구" 같은 상호관계는 (가이오, co_worker_of, 바울)과 (바울, co_worker_of, 가이오)가
    /// 별개 행으로 존재할 수 있어 `personRelationRecords`의 중복 제거로 걸러지지 않으므로 여기서 한 번 더 제거한다.
    private func uniqueOrdered(_ items: [(name: String, idx: String)]) -> [(name: String, idx: String)] {
        var result: [(name: String, idx: String)] = []
        for item in items {
            if !item.idx.isEmpty {
                if result.contains(where: { $0.idx == item.idx }) { continue }
                if let emptyIndex = result.firstIndex(where: { $0.idx.isEmpty && $0.name == item.name }) {
                    result[emptyIndex].idx = item.idx
                } else {
                    result.append(item)
                }
            } else if !result.contains(where: { $0.name == item.name }) {
                result.append(item)
            }
        }
        return result
    }

    /// 관계 행에서 이 인물이 source/target 쪽인지 판단한다. 이름(`person.word`) 비교가 아니라 idx 비교가 기본이다 —
    /// 동명이인("예수" 3명, "야고보" 2명)은 이름이 같아 방향을 가를 수 없고, 별칭(word2)으로 적힌 행
    /// (source_word "스보" = Persons "스비")은 이름이 달라 놓친다. idx가 없는 행(빌드 시점에 신원 미확정)만
    /// 이름으로 비교한다.
    private func isSource(_ relation: PersonRelationRecord) -> Bool {
        relation.sourceIdx.isEmpty ? relation.sourceWord == person.word : relation.sourceIdx == person.idx
    }

    private func isTarget(_ relation: PersonRelationRecord) -> Bool {
        relation.targetIdx.isEmpty ? relation.targetWord == person.word : relation.targetIdx == person.idx
    }

    /// 기타관계 중 표시 대상만 골라 라벨별로 묶는다.
    /// "제자"는 원본에 라벨이 없고 제자 본인 쪽에 "스승"으로 기록되며, build_reference_data.py가
    /// (source=스승, teacher_of, target=제자)로 뒤집어 저장하므로 "내가 source인 teacher_of"의
    /// target을 제자로 보여준다. "신하"도 같은 패턴(servant_of, source=신하, target=주군)이라
    /// 내가 source면 "주군", target이면 "신하"로 방향에 따라 라벨이 달라진다.
    /// 동역자/친구 등 상호관계는 방향과 무관하게 상대 이름을 모은다.
    private var otherRelationRows: [(label: String, names: [(name: String, idx: String)])] {
        var disciples: [(name: String, idx: String)] = []
        var coWorkers: [(name: String, idx: String)] = []
        var friends: [(name: String, idx: String)] = []
        var lords: [(name: String, idx: String)] = []
        var servants: [(name: String, idx: String)] = []
        // 방향 판단 원칙(추측 금지):
        // - 상호관계(형제·동역자·친구·대적·동맹·관련 인물): source/target 어느 쪽이든 상대 이름을
        //   모은다. "오라비"/"친형제"는 "형제"와 같은 relationType이라 함께 나온다.
        // - "아우"/"형"/"누이": Y_to_X로만 저장되어(target = 라벨을 직접 적은 표제어 본인)
        //   target == person일 때만 보여준다. 반대 방향은 형/누나 구분에 성별 추론이 필요해 표시하지
        //   않는다("언니"는 "누이"와 같은 relationType).
        // - "숙부"/"조카"(uncle_of): 같은 relationType을 반대 방향으로 재사용 — target == person이면
        //   source가 "숙부", source == person이면 target이 "조카".
        // - "선조"/"자부"/"외조부": "아우"/"형"과 같은 이유로 target == person일 때만.
        var siblings: [(name: String, idx: String)] = []
        var youngerBrothers: [(name: String, idx: String)] = []
        var olderBrothers: [(name: String, idx: String)] = []
        var sisters: [(name: String, idx: String)] = []
        var uncles: [(name: String, idx: String)] = []
        var nephews: [(name: String, idx: String)] = []
        var ancestors: [(name: String, idx: String)] = []
        var daughtersInLaw: [(name: String, idx: String)] = []
        var maternalGrandfathers: [(name: String, idx: String)] = []
        // 나머지 가족관계성 기타관계 — build_reference_data.py에 매핑된 relation_type과 같은 이름.
        var fathersInLaw: [(name: String, idx: String)] = []
        // [2026-10-27 6차] "시아버지"(husbands_father_of) — 빌드가 "장인"(father_in_law_of)과 분리해 저장한다.
        var husbandsFathers: [(name: String, idx: String)] = []
        var sonsInLaw: [(name: String, idx: String)] = []
        var grandchildrenViaDaughter: [(name: String, idx: String)] = []
        var greatGrandfathers: [(name: String, idx: String)] = []
        var maternalGrandmothers: [(name: String, idx: String)] = []
        // 상호관계 패턴("동역자"/"친구"와 동일).
        var adversaries: [(name: String, idx: String)] = []
        var allies: [(name: String, idx: String)] = []
        // 라벨이 없거나 "기타"인 항목 — 구체적 유형은 모르지만 관련이 있다는 사실은 보여준다.
        // 상호관계라 양방향을 다 담는다.
        var relatedPeople: [(name: String, idx: String)] = []
        for relation in person.relations {
            switch relation.relationType {
            case "teacher_of":
                if isSource(relation) { disciples.append((name: relation.targetWord, idx: relation.targetIdx)) }
            case "co_worker_of":
                if isSource(relation) { coWorkers.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if isTarget(relation) { coWorkers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "friend_of":
                if isSource(relation) { friends.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if isTarget(relation) { friends.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "servant_of":
                if isSource(relation) { lords.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if isTarget(relation) { servants.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "brother_of":
                if isSource(relation) { siblings.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if isTarget(relation) { siblings.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "younger_brother_of":
                if isTarget(relation) { youngerBrothers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "older_brother_of":
                if isTarget(relation) { olderBrothers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "sister_of":
                if isTarget(relation) { sisters.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "uncle_of":
                if isTarget(relation) { uncles.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
                else if isSource(relation) { nephews.append((name: relation.targetWord, idx: relation.targetIdx)) }
            case "ancestor_of":
                if isTarget(relation) { ancestors.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "daughter_in_law_of":
                if isTarget(relation) { daughtersInLaw.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "father_in_law_of":
                // "장인" — "자부"와 같은 이유로 target == person일 때만. [6차] "시아버지"는 아래 husbands_father_of로 분리됐다.
                if isTarget(relation) { fathersInLaw.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "husbands_father_of":
                if isTarget(relation) { husbandsFathers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "son_in_law_of":
                if isTarget(relation) { sonsInLaw.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "maternal_grandfather_of":
                if isTarget(relation) { maternalGrandfathers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
                // "외손자"/"외손주" — "숙부"/"조카"처럼 같은 relationType을 반대 방향(내가 source)으로 재사용.
                else if isSource(relation) { grandchildrenViaDaughter.append((name: relation.targetWord, idx: relation.targetIdx)) }
            case "maternal_grandmother_of":
                if isTarget(relation) { maternalGrandmothers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "great_grandfather_of":
                if isTarget(relation) { greatGrandfathers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "adversary_of":
                if isSource(relation) { adversaries.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if isTarget(relation) { adversaries.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "ally_of":
                if isSource(relation) { allies.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if isTarget(relation) { allies.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "related_to":
                if isSource(relation) { relatedPeople.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if isTarget(relation) { relatedPeople.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            default:
                break
            }
        }
        var rows: [(String, [(name: String, idx: String)])] = []
        let uniqueDisciples = uniqueOrdered(disciples)
        let uniqueCoWorkers = uniqueOrdered(coWorkers)
        let uniqueFriends = uniqueOrdered(friends)
        let uniqueLords = uniqueOrdered(lords)
        let uniqueServants = uniqueOrdered(servants)
        let uniqueSiblings = uniqueOrdered(siblings)
        let uniqueYoungerBrothers = uniqueOrdered(youngerBrothers)
        let uniqueOlderBrothers = uniqueOrdered(olderBrothers)
        let uniqueSisters = uniqueOrdered(sisters)
        let uniqueUncles = uniqueOrdered(uncles)
        let uniqueNephews = uniqueOrdered(nephews)
        let uniqueAncestors = uniqueOrdered(ancestors)
        let uniqueDaughtersInLaw = uniqueOrdered(daughtersInLaw)
        let uniqueMaternalGrandfathers = uniqueOrdered(maternalGrandfathers)
        let uniqueFathersInLaw = uniqueOrdered(fathersInLaw)
        let uniqueHusbandsFathers = uniqueOrdered(husbandsFathers)
        let uniqueSonsInLaw = uniqueOrdered(sonsInLaw)
        let uniqueGrandchildrenViaDaughter = uniqueOrdered(grandchildrenViaDaughter)
        let uniqueGreatGrandfathers = uniqueOrdered(greatGrandfathers)
        let uniqueMaternalGrandmothers = uniqueOrdered(maternalGrandmothers)
        let uniqueAdversaries = uniqueOrdered(adversaries)
        let uniqueAllies = uniqueOrdered(allies)
        let uniqueRelatedPeople = uniqueOrdered(relatedPeople)
        if !uniqueDisciples.isEmpty { rows.append((String(localized: "제자"), uniqueDisciples)) }
        if !uniqueCoWorkers.isEmpty { rows.append((String(localized: "동역자"), uniqueCoWorkers)) }
        if !uniqueFriends.isEmpty { rows.append((String(localized: "친구"), uniqueFriends)) }
        if !uniqueLords.isEmpty { rows.append((String(localized: "주군"), uniqueLords)) }
        if !uniqueServants.isEmpty { rows.append((String(localized: "신하"), uniqueServants)) }
        if !uniqueSiblings.isEmpty { rows.append((String(localized: "형제"), uniqueSiblings)) }
        if !uniqueYoungerBrothers.isEmpty { rows.append((String(localized: "아우"), uniqueYoungerBrothers)) }
        if !uniqueOlderBrothers.isEmpty { rows.append((String(localized: "형"), uniqueOlderBrothers)) }
        if !uniqueSisters.isEmpty { rows.append((String(localized: "누이"), uniqueSisters)) }
        if !uniqueUncles.isEmpty { rows.append((String(localized: "숙부"), uniqueUncles)) }
        if !uniqueNephews.isEmpty { rows.append((String(localized: "조카"), uniqueNephews)) }
        if !uniqueAncestors.isEmpty { rows.append((String(localized: "선조"), uniqueAncestors)) }
        if !uniqueDaughtersInLaw.isEmpty { rows.append((String(localized: "자부"), uniqueDaughtersInLaw)) }
        if !uniqueMaternalGrandfathers.isEmpty { rows.append((String(localized: "외조부"), uniqueMaternalGrandfathers)) }
        if !uniqueFathersInLaw.isEmpty { rows.append((String(localized: "장인"), uniqueFathersInLaw)) }
        if !uniqueHusbandsFathers.isEmpty { rows.append((String(localized: "시아버지"), uniqueHusbandsFathers)) }
        if !uniqueSonsInLaw.isEmpty { rows.append((String(localized: "사위"), uniqueSonsInLaw)) }
        if !uniqueGrandchildrenViaDaughter.isEmpty { rows.append((String(localized: "외손자"), uniqueGrandchildrenViaDaughter)) }
        if !uniqueGreatGrandfathers.isEmpty { rows.append((String(localized: "증조부"), uniqueGreatGrandfathers)) }
        if !uniqueMaternalGrandmothers.isEmpty { rows.append((String(localized: "외조모"), uniqueMaternalGrandmothers)) }
        if !uniqueAdversaries.isEmpty { rows.append((String(localized: "대적"), uniqueAdversaries)) }
        if !uniqueAllies.isEmpty { rows.append((String(localized: "동맹"), uniqueAllies)) }
        if !uniqueRelatedPeople.isEmpty { rows.append((String(localized: "관련 인물"), uniqueRelatedPeople)) }
        // 이름 번역은 중복 제거(`uniqueOrdered`)가 끝난 뒤에 한다(`localizedNames` 주석 참고).
        // [2026-10-27 6차] 한 라벨 안의 이름은 성경 첫 등장 순(번역 전 한국어 이름·idx로 정렬, 모르는 이름은 뒤, 같으면 원래 순서).
        let store = ReferenceDataProvider.shared.store
        return rows.map { row -> (label: String, names: [(name: String, idx: String)]) in
            let ordered = store?.sortedByFirstAppearance(row.1, idx: { $0.idx }, word: { $0.name }) ?? row.1
            return (label: row.0, names: localizedNames(ordered))
        }
    }

    /// `person.contextNotes`(`PersonContextNotes` 테이블 — 왕/총독/선지자 등 직함·역할성 참고
    /// 전용 데이터)를 라벨별로 묶는다. 인물관계 그래프와 분리하기로 했으므로 "관계" 카드가 아닌
    /// 별도 "기타 정보" 카드로 그린다. 다른 행과 같은 (label, names) 모양이라 `relationRow(_:)`를 쓴다.
    private var contextNoteRows: [(label: String, names: [(name: String, idx: String)])] {
        var order: [String] = []
        var byLabel: [String: [(name: String, idx: String)]] = [:]
        for note in person.contextNotes {
            if byLabel[note.label] == nil { order.append(note.label) }
            byLabel[note.label, default: []].append((name: note.targetWord, idx: note.targetIdx))
        }
        // 묶는 키(`order`/`byLabel`)는 한국어 라벨 그대로, 화면 라벨만 번역한다.
        let store = ReferenceDataProvider.shared.store
        return order.map { label in
            (label: store?.displayRelationLabel(label) ?? label, names: localizedNames(uniqueOrdered(byLabel[label] ?? [])))
        }
    }

    /// `person.groupMemberships`("열두 제자"/"다윗의 30용사" 등 소속 집단)를 그룹별로 묶는다.
    /// `contextNoteRows`와 같은 모양이며 "소속 그룹" 전용 카드로 분리해 보여준다.
    private var groupMembershipRows: [(label: String, names: [(name: String, idx: String)])] {
        var order: [String] = []
        var byLabel: [String: [(name: String, idx: String)]] = [:]
        for membership in person.groupMemberships {
            if byLabel[membership.groupId] == nil { order.append(membership.groupId) }
            byLabel[membership.groupId, default: []].append((name: membership.otherMemberWord, idx: membership.otherMemberIdx))
        }
        // 묶는 키는 group_id(원문 라벨) 그대로, 화면 그룹 이름만 번역한다(`PersonGroupsI18n`).
        // [2026-10-27 6차] 멤버 순서는 저장소가 이미 정했다(`personGroupMemberships` — 열두 제자는 마 10:2-4, 그 밖은 첫 등장 순).
        // 근거 구절이 있는 그룹은 라벨 뒤에 "(마 10:2-4 순)"을 붙인다(줄 모양은 그대로, 라벨 글자만).
        let store = ReferenceDataProvider.shared.store
        return order.map { groupId -> (label: String, names: [(name: String, idx: String)]) in
            let groupName = store?.displayGroupName(groupId) ?? groupId
            var label = groupName
            if let basis = store?.groupMemberOrderBasis(groupId: groupId), let basisLabel = Self.orderBasisLabel(basis) {
                label = "\(groupName) (\(basisLabel))"
            }
            return (label: label, names: localizedNames(uniqueOrdered(byLabel[groupId] ?? [])))
        }
    }

    /// [6차] 그룹 멤버 순서 근거 표시 — 예: ko "마 10:2-4 순", en "Order as in Matt 10:2-4". 책 약칭은 앱 언어(`displayShortName`).
    /// 책을 찾지 못하면 nil(라벨을 붙이지 않는다).
    private static func orderBasisLabel(_ basis: PersonGroupOrderBasis) -> String? {
        guard let book = BooksProvider.shared.book(id: basis.bookId) else { return nil }
        let verses = basis.startVerse == basis.endVerse ? "\(basis.startVerse)" : "\(basis.startVerse)-\(basis.endVerse)"
        let reference = "\(book.displayShortName) \(basis.chapter):\(verses)"
        return String(localized: "\(reference) 순", comment: "그룹 멤버 순서의 성경 근거(예: 마 10:2-4 순) — 값: 책 약칭 장:절-절")
    }

    /// 이름이 `Persons`에서 정확히 하나로 특정될 때만 링크 대상을 돌려준다. idx가 있으면 그것으로
    /// 직접 조회하고, 없으면 동명이인(예: "야고보")이 있을 때 잘못된 인물로 이동하지 않도록 nil.
    /// `persons(mentionedIn:)`은 "아브라함/라함" 오탐 방지 필터가 적용된 함수라 짧은 이름 조회에도 안전하다.
    private func resolvedRelationPerson(named name: String, idx: String = "") -> PersonEntity? {
        Self.resolvePerson(named: name, idx: idx)
    }

    /// `resolvedRelationPerson`의 본체. 통합검색의 관계 행(`SearchView`)이 "답 인물" 상세를 열 때도 같은 규칙을 쓰도록 static으로 둔다.
    static func resolvePerson(named name: String, idx: String = "") -> PersonEntity? {
        guard let store = ReferenceDataProvider.shared.store else { return nil }
        if !idx.isEmpty, let exact = try? store.person(idx: idx) {
            return exact
        }
        let candidates = (try? store.persons(mentionedIn: name)) ?? []
        let exactMatches = candidates.filter { ($0.matchedAlias ?? $0.word) == name }
        guard exactMatches.count == 1 else { return nil }
        return exactMatches.first
    }

    /// "라벨: 이름, 이름" 한 줄. `resolvedRelationPerson`으로 특정되는 이름만 `personref:///이름`
    /// 링크로 만들며, 성경구절 링크(`gold`)와 구분되도록 `slateTeal`을 쓴다.
    @ViewBuilder
    private func relationRow(_ row: (label: String, names: [(name: String, idx: String)])) -> some View {
        let text: Text = {
            var result = AttributedString("\(row.label): ")
            result.foregroundColor = settings.bibleTextColor ?? .primary
            for (index, item) in row.names.enumerated() {
                if index > 0 {
                    result += AttributedString(", ")
                }
                var linkURL: URL?
                if resolvedRelationPerson(named: item.name, idx: item.idx) != nil,
                   let encodedName = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                    var components = URLComponents()
                    components.scheme = "personref"
                    components.path = "/\(encodedName)"
                    if !item.idx.isEmpty {
                        components.queryItems = [URLQueryItem(name: "idx", value: item.idx)]
                    }
                    linkURL = components.url
                }
                if let url = linkURL {
                    var linked = AttributedString(item.name)
                    linked.link = url
                    linked.foregroundColor = JBCHCategoryPalette.slateTeal
                    linked.font = .body.weight(.semibold)
                    result += linked
                } else {
                    var plain = AttributedString(item.name)
                    plain.foregroundColor = settings.bibleTextColor ?? .primary
                    result += plain
                }
            }
            return Text(result)
        }()
        text
            .font(.body)
            .padding(.vertical, 2)
    }

    /// "관련 성경구절" 절용 책/장 단위 그룹 — `SearchViewModel.VerseSearchResultGroup`에서
    /// 검색 전용 필드를 뺀 단순 버전.
    private struct VerseReferenceGroup: Identifiable {
        let bookId: Int
        let chapter: Int
        let bookNameKo: String
        let verses: [(verse: Int, content: String)]
        var id: String { "\(bookId)-\(chapter)" }
    }

    /// `person.verseRefs`를 절 본문과 함께 책/장 단위로 묶는다. `SearchViewModel.resolveVerseResults(_:)`와
    /// 같은 방식으로 `BibleReferenceStore`를 열어 조회하며(그쪽은 `private`이라 재사용 불가) 같은
    /// 이유로 30개에서 자른다. 관련성 지표가 없어 정경순(책ID/장 오름차순)으로 정렬한다.
    private var groupedVerseReferences: [VerseReferenceGroup] {
        // 앱 언어의 기본 번들 성경으로 보여준다(2026-10-12, `BundledTranslationCatalog.current`).
        guard let store = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedCurrentLanguageBundledDatabaseURL().path) else {
            return []
        }
        var versesByChapter: [String: (bookId: Int, chapter: Int, bookNameKo: String, verses: [(Int, String)])] = [:]
        var orderedKeys: [String] = []
        for ref in person.verseRefs.prefix(30) {
            guard let verse = try? store.verse(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse) else { continue }
            let key = "\(ref.bookId)-\(ref.chapter)"
            if versesByChapter[key] == nil {
                let bookName = BooksProvider.shared.book(id: ref.bookId)?.displayName ?? String(localized: "책 \(ref.bookId)")
                versesByChapter[key] = (ref.bookId, ref.chapter, bookName, [])
                orderedKeys.append(key)
            }
            versesByChapter[key]?.verses.append((verse.verse, verse.content))
        }
        let groups = orderedKeys.compactMap { key -> VerseReferenceGroup? in
            guard let g = versesByChapter[key] else { return nil }
            return VerseReferenceGroup(
                bookId: g.bookId, chapter: g.chapter, bookNameKo: g.bookNameKo,
                verses: g.verses.sorted { $0.0 < $1.0 }
            )
        }
        return groups.sorted { ($0.bookId, $0.chapter) < ($1.bookId, $1.chapter) }
    }

    /// 통합검색 "성경구절" 탭의 `groupedVerseRow`와 같은 "N절) 본문" 행. 아이폰은 크로스탭(성경 탭으로
    /// 좌표 전달), 맥/아이패드는 조상 `NavigationStack`의 `BibleVerseDestinationRegistration`을 이용한
    /// 값 기반 push(`BibleVerseChipRow.chipButton`과 같은 분기).
    /// "N절)" 접두어와 본문을 별도 `Text`로 `HStack(alignment: .top)`에 두어 본문이 줄바꿈돼도
    /// 접두어 폭만큼 들여쓰기되게 한다(SwiftUI에 매달린 들여쓰기가 없어 쓰는 우회법).
    @ViewBuilder
    private func verseReferenceRow(group: VerseReferenceGroup, verse: (verse: Int, content: String)) -> some View {
        let label = HStack(alignment: .top, spacing: 0) {
            Text("\(verse.verse)절) ")
                .font(.body)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .fixedSize()
            Text(verse.content)
                .font(.body)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if isPhoneIdiom {
            Button {
                AppNavigationRequest.shared.request(.bibleReading)
                BibleVerseNavigationRequest.shared.request(bookId: group.bookId, chapter: group.chapter, verse: verse.verse)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        } else {
            NavigationLink(value: BibleVerseDestination(bookId: group.bookId, chapter: group.chapter, verse: verse.verse)) {
                label
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func verseReferenceGroupCard(_ group: VerseReferenceGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .frame(width: 18)
                Text("\(group.bookNameKo) \(group.chapter)장")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(group.verses.count)절")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            ForEach(Array(group.verses.enumerated()), id: \.offset) { _, verse in
                verseReferenceRow(group: group, verse: verse)
            }
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(JBCHCategoryPalette.wood.opacity(0.3), lineWidth: 1)
        )
        .padding(.vertical, 5)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }

    /// 본문(PersonSeed.json 자유 서술)에 섞인 "(창세기 17:5)" 같은 성경 인용 하나의 위치 그룹.
    /// `BibleReferenceExtractor`는 범위 인용("창세기 9:22-25")을 절마다 Match로 펼치되 모두 같은
    /// `range`를 공유하므로, 연속으로 같은 `range`인 Match를 한 그룹으로 묶어 링크 하나(첫 절)만 만든다.
    private struct BibleReferenceLinkGroup {
        let range: Range<String.Index>
        let bookId: Int
        let chapter: Int
        let verse: Int
    }

    private func bibleReferenceLinkGroups(in text: String) -> [BibleReferenceLinkGroup] {
        let matches = BibleReferenceExtractor.extract(from: text)
        var groups: [BibleReferenceLinkGroup] = []
        for match in matches {
            if let last = groups.last, last.range == match.range { continue }
            groups.append(BibleReferenceLinkGroup(
                range: match.range, bookId: match.bookId, chapter: match.chapter,
                // [주의] 절 없는 인용("창세기 17장")은 `verse`가 nil이고 `BibleVerseDestination`이 절 좌표를
                // 요구하므로 1절로 이동한다.
                verse: match.verse ?? 1
            ))
        }
        return groups
    }

    /// 매치된 원문("창세기 17:5")에서 책 이름 부분(첫 숫자 앞)만 표준 약어로 바꾸고, 장:절/범위
    /// 표기는 원문 그대로 둔다.
    private func abbreviatedCitationLabel(_ matchedText: String, bookId: Int) -> String {
        guard let firstDigitIndex = matchedText.firstIndex(where: { $0.isNumber }) else { return matchedText }
        let book = BooksProvider.shared.book(id: bookId)
        let abbreviation = book?.displayShortName
            ?? matchedText[..<firstDigitIndex].trimmingCharacters(in: .whitespaces)
        let rest = matchedText[firstDigitIndex...]
        return "\(abbreviation) \(rest)"
    }

    /// 본문 중 성경 인용 부분만 약어로 바꾸고 탭하면 이동하는 링크로 바꾼
    /// `Text`. 인용이 하나도 없으면(대부분의 문장) 원문 그대로 돌려준다.
    private func bibleReferenceLinkedText(_ text: String) -> Text {
        let groups = bibleReferenceLinkGroups(in: text)
        guard !groups.isEmpty else { return Text(text) }

        var result = AttributedString()
        var cursor = text.startIndex
        for group in groups {
            if cursor < group.range.lowerBound {
                result += AttributedString(String(text[cursor..<group.range.lowerBound]))
            }
            let matchedText = String(text[group.range])
            // 앞에 책 아이콘을 붙이고 옅은 배경 하이라이트(`gold`)로 본문과 구분한다.
            // [주의] 문단 안에 흐르는 `Text`라 패딩·둥근 모서리 캡슐은 불가능하다 —
            // `AttributedString.backgroundColor`는 줄에 붙는 사각형 하이라이트만 그린다.
            var linked = AttributedString("📖 " + abbreviatedCitationLabel(matchedText, bookId: group.bookId))
            linked.link = URL(string: "bibleref:///\(group.bookId)/\(group.chapter)/\(group.verse)")
            linked.font = .footnote.weight(.semibold)
            linked.foregroundColor = JBCHCategoryPalette.gold
            linked.backgroundColor = JBCHCategoryPalette.gold.opacity(0.15)
            result += linked
            cursor = group.range.upperBound
        }
        if cursor < text.endIndex {
            result += AttributedString(String(text[cursor...]))
        }
        return Text(result)
    }

    /// `bibleref:///책ID/장/절` URL을 실제 이동으로 바꾼다. `openURL` 핸들러에서는 `NavigationPath`에
    /// 접근할 수 없어 값 기반 push 대신 앱 공용 크로스탭 메커니즘(`AppNavigationRequest` +
    /// `BibleVerseNavigationRequest`)을 플랫폼 구분 없이 쓴다.
    private func handleBibleReferenceLink(_ url: URL) -> OpenURLAction.Result {
        // `personref:///이름` 링크 — `relationStack`에 밀어 넣어 이 화면 자체가 그 인물의 상세로 바뀌게 한다.
        if url.scheme == "personref" {
            guard let name = url.pathComponents.filter({ $0 != "/" }).first else {
                return .systemAction
            }
            let idx = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "idx" })?.value ?? ""
            guard let target = resolvedRelationPerson(named: name, idx: idx) else {
                return .systemAction
            }
            relationStack.append(target)
            return .handled
        }
        guard url.scheme == "bibleref" else { return .systemAction }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3,
              let bookId = Int(parts[0]), let chapter = Int(parts[1]), let verse = Int(parts[2]) else {
            return .systemAction
        }
        AppNavigationRequest.shared.request(.bibleReading)
        BibleVerseNavigationRequest.shared.request(bookId: bookId, chapter: chapter, verse: verse)
        return .handled
    }

    /// 소제목마다 둥근 테두리 카드(`wood` 톤)로 구분한다 — 기본 `Section("제목")`의 옅은 시스템
    /// 구분선 대신 "관련 성경구절" 절과 같은 카드 스타일을 쓴다.
    @ViewBuilder
    private func cardSection<Content: View>(
        _ title: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill((settings.bibleTextColor ?? .primary).opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(JBCHCategoryPalette.wood.opacity(0.3), lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    // 제목 폰트는 통합검색 목록의 `SearchView.sectionHeader`와 맞춘다.
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(settings.bibleTextColor ?? .primary)
            .textCase(nil)
            .padding(.leading, 16)
        }
    }

    var body: some View {
        Group {
            // `relationStack`이 비어있지 않으면(관계에서 다른 인물로 넘어온 상태) 뒤로 가는 버튼을 보여준다 —
            // 로컬 스택을 pop할 뿐이라 NavigationStack 없이 동작한다.
            if !relationStack.isEmpty {
                Section {
                    Button {
                        relationStack.removeLast()
                    } label: {
                        Label("이전 인물로", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                header
            }
            // 제목/태그/인용구가 화면 왼쪽 끝에 붙지 않도록 카드 섹션과 같은 좌우 여백(16)을 준다.
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // [2026-10-22] 본문 카드는 번역 표시(`display*`). 노출 여부는 한국어와 같다(빌드가 한국어 칸 기준으로 ""/"-"를 맞춘다).
            if !person.displayIntroduce.isEmpty {
                cardSection(String(localized: "detail.overview", defaultValue: "개요", comment: "인물·지명 상세 카드 — 소개(성경 개요 화면과 구분)"), icon: "doc.text.fill") {
                    bibleReferenceLinkedText(person.displayIntroduce).font(.body)
                }
            }
            if !person.displayLifetime.isEmpty {
                cardSection(String(localized: "주요 생애"), icon: "calendar") {
                    bibleReferenceLinkedText(person.displayLifetime).font(.body)
                }
            }
            if !person.displayEvent.isEmpty {
                cardSection(String(localized: "업적과 사건"), icon: "flag.fill") {
                    bibleReferenceLinkedText(person.displayEvent).font(.body)
                }
            }
            if !person.displayCharacter.isEmpty {
                cardSection(String(localized: "성품과 특징"), icon: "sparkles") {
                    bibleReferenceLinkedText(person.displayCharacter).font(.body)
                }
            }
            if !infoFacts.isEmpty {
                cardSection(String(localized: "인물 정보"), icon: "info.circle.fill") {
                    ForEach(Array(infoFacts.enumerated()), id: \.offset) { index, fact in
                        LabeledContent(fact.label, value: fact.value)
                        if index < infoFacts.count - 1 {
                            subtleRowDivider()
                        }
                    }
                }
            }
            if !familyRelationRows.isEmpty || !otherRelationRows.isEmpty {
                // 가족 그룹과 기타관계 그룹을 하나의 목록으로 이어 붙여 두 그룹의 경계에도 구분선을 넣는다.
                let allRelationRows = familyRelationRows + otherRelationRows
                cardSection(String(localized: "관계"), icon: "person.2.fill") {
                    ForEach(Array(allRelationRows.enumerated()), id: \.offset) { index, row in
                        relationRow(row)
                        if index < allRelationRows.count - 1 {
                            subtleRowDivider()
                        }
                    }
                }
            }
            if !groupMembershipRows.isEmpty {
                // "열두 제자"/"다윗의 30·3대용사"처럼 소속 라벨이 정확히 붙은 경우만 — "관계" 카드의
                // "관련 인물"(라벨 없음/"기타")·"기타 정보" 카드(직함)와는 별도 자리.
                cardSection(String(localized: "소속 그룹"), icon: "person.3.fill") {
                    ForEach(Array(groupMembershipRows.enumerated()), id: \.offset) { index, row in
                        relationRow(row)
                        if index < groupMembershipRows.count - 1 {
                            subtleRowDivider()
                        }
                    }
                }
            }
            if !contextNoteRows.isEmpty {
                // 왕/총독/선지자 등은 인물관계 그래프에 넣지 않기로 한 결정에 맞춰 "관계" 카드와 분리한다.
                cardSection(String(localized: "기타 정보"), icon: "info.circle.fill") {
                    ForEach(Array(contextNoteRows.enumerated()), id: \.offset) { index, row in
                        relationRow(row)
                        if index < contextNoteRows.count - 1 {
                            subtleRowDivider()
                        }
                    }
                }
            }
            if !groupedVerseReferences.isEmpty {
                Section {
                    ForEach(groupedVerseReferences) { group in
                        verseReferenceGroupCard(group)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("관련 성경구절")
                            // 위 `cardSection` 헤더와 같은 폰트.
                            .font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .textCase(nil)
                    .padding(.leading, 16)
                }
            }
        }
        // 본문 안 성경 인용 링크가 시스템 브라우저로 가지 않고 앱 안 성경 조회로 이동하도록 가로챈다.
        // `Group` 하나에만 걸어도 안쪽 모든 `Section`/`Text`에 환경값으로 전파된다.
        .environment(\.openURL, OpenURLAction(handler: handleBibleReferenceLink))
        // `initialPerson`은 새 검색 결과로 갱신되지만 `@State relationStack`은 SwiftUI가 이 뷰를
        // "같은 자리"로 보는 한 렌더를 넘어 유지되어, 검색어를 바꿔도 관계 이동 스택이 새 검색 결과를
        // 가린다. `initialPerson.idx`가 바뀌면 새 검색으로 새 인물이 들어온 것이므로 스택을 비운다.
        .onChange(of: initialPerson.idx) { _, _ in
            relationStack.removeAll()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // [2026-10-22] 제목은 번역 표시(한국어 앱이면 원본). 글꼴은 실제로 그리는 문자열로 고른다(`TitleFont`).
                Text(person.displayWord)
                    .font(.titleSerif(person.displayWord, size: 28, relativeTo: .largeTitle))
                    .fontWeight(.bold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Spacer(minLength: 0)
            }
            // 별칭(word2)으로 매칭돼도 제목은 항상 대표 이름(`person.word`) — 별칭은 부제로만 안내한다.
            if let alias = person.matchedAlias {
                Text("별칭 \u{201C}\(alias)\u{201D}로 검색됨")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
            if !person.displayCallTitle.isEmpty {
                Text(person.displayCallTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !person.displayOccupation.isEmpty {
                // [주의] `HStack`은 줄바꿈하지 않아 좁은 아이폰에서 직업이 많으면 넘칠 수 있다. 범용 줄바꿈
                // 레이아웃이 아직 없어 새로 만들지 않았다 — 직업이 3개 이상인 인물로 실기기 확인이 필요하다.
                HStack(spacing: 6) {
                    ForEach(person.displayOccupation, id: \.self) { role in
                        // 색은 카드 테두리와 같은 `wood`, 크기/굵기/패딩은 말씀노트 카테고리 배지
                        // (`WordNoteRowView.categoryBadge`)와 맞춘다.
                        Text(role)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(JBCHCategoryPalette.wood.opacity(0.15), in: Capsule())
                            .foregroundStyle(JBCHCategoryPalette.wood)
                    }
                }
            }
            if !person.displayMeaning.isEmpty {
                Text("\u{201C}\(person.displayMeaning)\u{201D}")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

}
