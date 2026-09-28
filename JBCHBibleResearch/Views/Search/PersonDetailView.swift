import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

//
//  PersonDetailView.swift
//  JBCHBibleResearch
//
//  [2026-09-15 신설, 2026-09-16 재작성] 통합검색의 "인물 정보" 카드 항목 하나의
//  상세 콘텐츠 — claude/bible-research-platform-search-category-expansion-
//  proposal.md 9~12차 문서(`personOrPlaceInfo` 삭제 후 새 인물/주제 카테고리
//  조회)와 그 설계를 미리 보여준 참고 목업(아티팩트 "인물·주제 상세 화면")을
//  실제 화면으로 옮긴 것.
//
//  [2026-09-16 재작성] 사용자 피드백 — "통합검색 결과에서 인물과 주제가 서로
//  다른 상세 화면으로 열려야 한다는 요구사항은, 통합검색 외 별도 화면이
//  아니라 통합검색 페이지 자체가 바뀌어야 한다는 의미였다." 원래(2026-09-15)
//  이 타입은 `body`가 `List { ... }`를 직접 감싸고 `NavigationLink`로 push되는
//  독립 화면이었다 — 이제는 `SearchContentView`가 자신의 `List` 안에
//  이 콘텐츠를 그대로 끼워 넣거나(아이폰 — 목록 전체를 대체), 별도의 `List`로
//  한 번 감싸 결과 목록 옆 상세 칼럼에 넣는다(맥/아이패드 — split, `SearchView.
//  swift`의 `intentCardSplitDetailColumn` 참고). 그래서 `body`는 이제 `List`를
//  갖지 않고 `Section`들의 묶음(`Group`)만 돌려준다 — 어느 쪽에 끼워 넣어도
//  똑같이 동작한다. `.navigationTitle`/`NavigationLink` push도 함께 없앴다 —
//  더 이상 이 타입 자신이 목적지로 push되는 경우가 없다.
//
//  ⚠️ 목업은 웹(HTML/CSS) 목업이라 커스텀 hex 색·세리프 폰트를 자유롭게 썼지만,
//  이 화면은 `bible-research-platform-screens.md` §10.1 색상 원칙(시스템
//  강조색·시맨틱 시스템 색 사용, 커스텀 hex 지양)과 이 앱이 이미 쓰고 있는
//  테마 시스템(`UserSettingsStore.bibleTextColor`)을 따른다 — 목업의 시각
//  디자인을 문자 그대로 복사하지 않고, "정보구조(카테고리마다 다른 화면,
//  숨김 규칙, 별칭 안내, 관계 문장 목록)"만 그대로 구현했다.
//
//  [2026-09-16 재작성] 사용자 요청 — "인물 정보의 관계 내용은 PersonSeed.json의
//  관계중 기타관계를 제외한 내용(할아버지, 할머니, 아버지, 어머니, 배우자,
//  아들, 딸, 손자, 손녀)를 설명없이 간단하게 표현할것 ... 기타관계는
//  친인척 관계가 아닌 특별한 경우(제자, 동역자, 친구)만 표현할것 ... 관련
//  말씀구절은 통합검색의 성경 검색결과처럼 나올 수 있게 할것." 두 가지를
//  반영했다:
//  1) "관계" 절 — 기존엔 `PersonRelationRecord`(SQL `PersonRelations` 테이블
//     경유)를 `PersonRelationLabeling.sentence(for:)`로 문장화해 보여줬는데,
//     실제 데이터를 확인해보니 그 테이블은 할아버지/할머니, 아버지/어머니,
//     아들/딸, 손자/손녀 4쌍을 "표제어 본인의 성별"만으로 뭉뚱그려 저장해서
//     (build_reference_data.py의 RELATION_TYPE_BY_GENDER 참고) 원래 어느
//     필드였는지 구분이 구조적으로 불가능했다. 그래서 이 9개 필드는
//     `PersonEntity.familyRelations`(Persons 테이블의 전용 `rel_*` 컬럼,
//     PersonSeed.json 원본을 추론 없이 그대로 옮김)에서 직접 읽어 "라벨:
//     이름, 이름" 형식으로만 보여준다(문장/원문 캡션 없음). 기타관계는
//     여전히 `person.relations`를 쓰되 제자(teacher_of 역방향)/동역자
//     (co_worker_of)/친구(friend_of, 이번에 build_reference_data.py에
//     매핑 신설)만 골라낸다 — `familyRelationRows`/`otherRelationRows`
//     참고.
//  2) "관련 성경구절" 절 — 참조 칩(`BibleVerseChipRow`) 대신 통합검색
//     "성경구절" 탭(`SearchView.groupCardBorder`/`verseChapterGroupHeader`/
//     `groupedVerseRow`)과 같은 "장별 카드 + N절) 본문" 스타일로 다시
//     그린다(`groupedVerseReferences`/`verseReferenceGroupCard` 참고) —
//     검색 결과 전용 필드(단어 일치 배지, 선택/복사 버튼)는 의미가 없어
//     시각 스타일만 재현했다.
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — 이 프로젝트의
//  다른 변경들과 같은 caveat. 특히 `LabeledContent`(iOS 16+/macOS 13+)와
//  `.font(.custom(SpecialPurposeFonts.titleSerif, size:relativeTo:))` 호출
//  시그니처는 실기기 빌드로 최종 확인이 필요하다.
//
struct PersonDetailView: View {
    /// [2026-09-16 신설] 사용자 요청 - "인물 관계에서 각 인물을 클릭하면
    /// 해당 인물의 상세페이지로 이동하게 할 것. (검색 결과가 아닌
    /// 상세페이지)." 이 화면은 원래도 NavigationStack push가 아니라 인라인
    /// 컨텐츠로 쓰인다(`SearchView.intentCardSection`/`macSplitCardLayout`
    /// 참고 - `.searchable`이 활성인 화면에서 `NavigationLink(value:)`/
    /// `.navigationDestination(for:)`를 쓰면 아이폰에서 재현되는 "구조적
    /// 결함"이 있어[SearchView.swift 541번째 줄 주석] push 자체를 아예
    /// 쓰지 않기로 확정됐다). 그래서 "다른 인물로 이동"도 push가 아니라,
    /// 이 화면 자신이 그리는 인물을 로컬 스택(`relationStack`)으로 갈아
    /// 끼우는 방식으로 구현한다 - 처음 전달받은 인물은 `initialPerson`에
    /// 저장해 두고, 실제로 화면에 그리는 대상은 `person`(아래 계산
    /// 프로퍼티, `relationStack` 맨 위 우선)이다. 파일 전체에서 이미
    /// `person.xxx`로 쓰던 기존 코드는 전혀 손대지 않아도 그대로 동작한다.
    private let initialPerson: PersonEntity
    @State private var relationStack: [PersonEntity] = []

    init(person: PersonEntity) {
        self.initialPerson = person
    }

    private var person: PersonEntity { relationStack.last ?? initialPerson }

    private var settings: UserSettingsStore { .shared }

    /// [2026-09-16 신설] 사용자 요청 — "인물정보, 관계 내용의 라운드 사각형
    /// 내에 행간에 점선이든 살짝 흐릿한 선이든 선을 그어 구분할 수 있도록."
    /// `Divider()`는 시스템 회색 고정이라 카드 배경(`bibleTextColor` 기반
    /// 톤)과 어울리지 않을 수 있어, 같은 톤을 아주 옅게 쓰는 얇은 사각형으로
    /// 대신한다 — 새 임의 색을 만들지 않는다는 이 파일의 기존 원칙을 그대로
    /// 따름.
    private func subtleRowDivider() -> some View {
        Rectangle()
            .fill((settings.bibleTextColor ?? .primary).opacity(0.12))
            .frame(height: 0.75)
    }

    /// "인물 정보" 절에 보여줄 항목만 — 빈 문자열은 목록에서 아예 뺀다
    /// (목업의 "빈 항목도 표시" 토글이 보여주려던 "기본은 숨김" 규칙을,
    /// 별도 토글 없이 화면 자체의 기본 동작으로 반영했다 — 검토·디버깅용
    /// 토글은 실제 사용자 화면에는 불필요하다고 판단).
    private var infoFacts: [(label: String, value: String)] {
        var facts: [(String, String)] = []
        if !person.origin.isEmpty { facts.append(("출신", person.origin)) }
        if !person.gender.isEmpty { facts.append(("성별", person.gender)) }
        if !person.tribe.isEmpty { facts.append(("지파", person.tribe)) }
        if !person.nation.isEmpty { facts.append(("민족", person.nation)) }
        if !person.aliases.isEmpty { facts.append(("별칭", person.aliases.joined(separator: " · "))) }
        return facts
    }

    /// `BibleVerseChipRow.isPhoneIdiom`과 정확히 같은 판정 — 아이폰에서는
    /// 조상 `NavigationStack`에 `BibleVerseDestinationRegistration`이 없어
    /// `NavigationLink(value:)`를 직접 쓸 수 없다(그 파일 주석 참고). 이
    /// 파일과 그 파일이 각각 독립적으로 이 3줄을 갖는 건, `BibleVerseChipRow`
    /// 헤더 주석이 명시한 대로 이 프로젝트가 3곳 미만에서는 이런 짧은 판정을
    /// 계속 복제해 온 기존 전례를 따른 것이다(근거 없는 추출 지양).
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// [2026-09-16 신설] "관계" 절 — 할아버지~손녀 9종을 라벨 순서대로,
    /// 비어있지 않은 것만. `PersonEntity.familyRelations` 주석 참고 —
    /// 추론 없이 PersonSeed.json 원본을 그대로 옮긴 값이다.
    /// [2026-09-16 수정] 사용자 보고 — "야고보, 요한, 빌립에 대해서는 링크가
    /// 걸리지 않았음." 아래 `otherRelationRows`와 반환 타입을 맞추기 위해
    /// 이름을 `(name, idx)` 쌍으로 감싼다 — 이 9개 필드는 `Persons.rel_*`
    /// 컬럼(콤마 분리 이름만)에서 오므로 idx를 알 방법이 없다(`""` 그대로,
    /// 아래 `relationRow`가 빈 idx면 기존 이름 기준 동명이인 검사로
    /// 자동 폴백한다 — 동작 자체는 전혀 바뀌지 않는다).
    private var familyRelationRows: [(label: String, names: [(name: String, idx: String)])] {
        let f = person.familyRelations
        // [2026-09-16 수정] 사용자 결정 — "이름#idx" 태그(PersonSeed.json
        // 가족관계, "앞으로 입력/수정할 때만" 지원). `PersonFamilyMember.idx`가
        // 채워져 있으면(사람이 직접 태그를 적어 둔 경우) 그 값을 그대로 쓴다 —
        // 태그가 없으면 여전히 ""(기존과 동일하게 이름 기준 동명이인 검사로
        // 폴백, 동작 변화 없음).
        // [2026-09-26 수정] 사용자 요청 — "화면에도 보여주게 해주세요"
        // (PersonSeed.json 가족관계 필드 "이름#idx(설명)"의 괄호 설명, 61건).
        // `relationRow`가 쓰는 공용 타입 `(name, idx)`를 그대로 유지하기 위해
        // 설명을 이름 뒤에 "이름(설명)" 형태로 이어붙여 넣는다 — idx는 태그가
        // 있는 항목엔 항상 함께 있으므로(`resolvedRelationPerson`이 idx를
        // 우선 사용) 링크 동작에는 영향이 없다.
        func wrap(_ members: [PersonFamilyMember]) -> [(name: String, idx: String)] {
            members.map { member in
                let displayName = member.note.isEmpty ? member.name : "\(member.name)(\(member.note))"
                return (name: displayName, idx: member.idx)
            }
        }
        var rows: [(String, [(name: String, idx: String)])] = []
        if !f.grandfathers.isEmpty { rows.append(("할아버지", wrap(f.grandfathers))) }
        if !f.grandmothers.isEmpty { rows.append(("할머니", wrap(f.grandmothers))) }
        if !f.fathers.isEmpty { rows.append(("아버지", wrap(f.fathers))) }
        if !f.mothers.isEmpty { rows.append(("어머니", wrap(f.mothers))) }
        if !f.spouses.isEmpty { rows.append(("배우자", wrap(f.spouses))) }
        if !f.sons.isEmpty { rows.append(("아들", wrap(f.sons))) }
        if !f.daughters.isEmpty { rows.append(("딸", wrap(f.daughters))) }
        if !f.grandsons.isEmpty { rows.append(("손자", wrap(f.grandsons))) }
        if !f.granddaughters.isEmpty { rows.append(("손녀", wrap(f.granddaughters))) }
        return rows
    }

    /// [2026-09-16 신설] "기타관계 중 친인척 관계가 아닌 특별한 경우(제자,
    /// 동역자, 친구)만" — `person.relations`(`PersonRelations` 테이블 경유,
    /// 양방향·중복 제거된 상태로 이미 들어옴)에서 이 3종만 골라낸다.
    ///
    /// - "제자": 원본(PersonSeed.json)엔 "제자"라는 라벨이 직접 존재하지
    ///   않는다 — 대신 제자 본인의 기타관계에 "스승"으로만 기록된다(예:
    ///   "게바"의 관계에 "예수 그리스도(스승)"). build_reference_data.py가
    ///   이걸 이미 (source=스승, teacher_of, target=제자)로 뒤집어
    ///   저장해뒀으므로(OTHER_RELATION_LABEL_MAP의 "스승" 항목, Y_to_X
    ///   방향), 여기서는 "내가 source인 teacher_of"만 골라 target을
    ///   제자로 보여주면 된다 — 한 번 더 뒤집을 필요 없음.
    /// - "동역자"/"친구": 둘 다 상호적 관계(방향에 의미 없음) — source든
    ///   target이든 내가 걸린 쪽의 상대방 이름을 모은다.
    /// 이름이 들어온 순서를 유지하면서 중복만 제거한다. "동역자"/"친구"는
    /// 방향에 의미가 없는 상호관계라, 같은 두 사람 관계가 정규식 추출층과
    /// PersonSeed 구조화 관계층 양쪽에서 서로 다른 방향(예: (가이오,
    /// co_worker_of, 바울) 그리고 (바울, co_worker_of, 가이오))으로 각각
    /// 별도 행으로 존재하는 실제 사례가 있다(둘 다 source/target이 달라
    /// `personRelationRecords(involving:)`의 dedup 키로는 걸러지지 않음) —
    /// 이 화면의 "동역자: 이름, 이름" 목록에 같은 이름이 두 번 나오는 걸
    /// 막기 위해 여기서 한 번 더 중복 제거한다.
    /// [2026-09-16 수정] 위 `familyRelationRows`/아래 `otherRelationRows`가
    /// 이제 이름을 `(name, idx)` 쌍으로 들고 다녀 시그니처를 맞췄다 — 중복
    /// 판정 자체는 여전히 이름만 기준(기존 동작 그대로).
    private func uniqueOrdered(_ items: [(name: String, idx: String)]) -> [(name: String, idx: String)] {
        var order: [String] = []
        var idxByName: [String: String] = [:]
        for item in items {
            if idxByName[item.name] == nil {
                order.append(item.name)
                idxByName[item.name] = item.idx
            } else if idxByName[item.name]?.isEmpty == true && !item.idx.isEmpty {
                idxByName[item.name] = item.idx
            }
        }
        return order.map { (name: $0, idx: idxByName[$0] ?? "") }
    }

    /// [2026-09-16 추가] 사용자 요청 — "가르가스 기타관계에 아하수에로가
    /// 있는데, idx3995인 아하수에로로 확실하게 지정할 수 있는가?" 위
    /// `otherRelationRows` 주석의 "제자"(teacher_of 역방향)와 완전히 같은
    /// 패턴 — "신하"도 원본엔 라벨이 직접 없고, 주군 쪽(예: idx3995
    /// 아하수에로) 기타관계에 "가르가스(신하)"로 기록해 두면
    /// build_reference_data.py가 (source=가르가스, servant_of,
    /// target=주군) 방향으로 저장한다(OTHER_RELATION_LABEL_MAP의 "신하"
    /// 항목, Y_to_X 방향 — target=자기 자신이라 idx를 정확히 앎). 그래서
    /// "내가 source인 servant_of"는 "주군"으로(내가 누구의 신하인지),
    /// "내가 target인 servant_of"는 "신하"로(누가 내 신하인지) 보여준다 —
    /// 동역자/친구와 달리 방향에 따라 라벨 자체가 다르다(스승/제자 쌍과
    /// 같은 이유).
    private var otherRelationRows: [(label: String, names: [(name: String, idx: String)])] {
        var disciples: [(name: String, idx: String)] = []
        var coWorkers: [(name: String, idx: String)] = []
        var friends: [(name: String, idx: String)] = []
        var lords: [(name: String, idx: String)] = []
        var servants: [(name: String, idx: String)] = []
        // [2026-09-16 추가] 사용자 요청 — "기타관계의 내용이 현재 제자, 동역자만
        // 나오는데 다 나올 수 있도록 수정할 것." PersonSeed.json 실제 데이터를
        // 스캔해보니 OTHER_RELATION_LABEL_MAP(build_reference_data.py)에 이미
        // 매핑되어 PersonRelations 테이블에 저장까지 됐지만, 이 switch에
        // case가 없어(default:로 조용히 버려져) 화면엔 안 보이던 친족성
        // 라벨 11종(형제 98건/아우 13건/형 10건/누이 7건/숙부 6건/오라비
        // 6건(→형제와 동일 relationType)/언니 5건(→누이와 동일 relationType)/
        // 조카 5건/친형제 2건(→형제와 동일)/자부 2건/선조 1건/외조부 1건)이
        // 있었다. 사용자 확인 결과 — "(1)만 추가" (친족성 기타관계만 확장,
        // 왕/총독/대적/사도 등 역할·직함성 라벨 70종은 아직 Python 쪽에
        // 매핑조차 안 돼 있고 "누이/아론의 아내" 같은 복합 라벨도 있어
        // 자동 매핑이 위험하다고 판단해 이번 범위에서 제외).
        //
        // 방향 판단 기준(추측 금지 원칙 그대로 적용):
        // - "형제"(brother_of): 상호적 관계(형/아우 구분 없음) — source든
        //   target이든 내가 걸린 쪽 모두 "형제"로 표시(동역자/친구와 동일
        //   패턴). "오라비"/"친형제" 라벨도 같은 relationType으로 매핑돼
        //   있어(Python 쪽 그대로, 이번엔 안 건드림) 함께 "형제"로 나온다.
        // - "아우"/"형"/"누이"(younger_brother_of/older_brother_of/
        //   sister_of): Y_to_X로만 저장됨(source=목록의 사람, target=그
        //   라벨을 직접 적어 넣은 표제어 본인). 표제어 자신의 페이지
        //   (target == person)에서만 "아우: 이름"/"형: 이름"/"누이: 이름"으로
        //   보여준다 — 이건 표제어 자신이 원본에 직접 적은 그대로라 추측이
        //   전혀 없다. 반대 방향(내가 source, 즉 남이 나를 "아우"라고 적은
        //   경우)은 내 쪽에서 상대를 "형"이라 불러야 할지 "누나"라 불러야
        //   할지 성별을 알아야 하는데 그걸 안전하게 추론할 근거가 없어
        //   표시하지 않는다(기존 teacher_of가 반대 방향을 안 보여주던 것과
        //   같은 이유) — "누이"는 "언니" 라벨도 같은 relationType이라 함께
        //   묶여 나온다.
        // - "숙부"/"조카"(uncle_of): 두 라벨이 정확히 반대 방향으로 같은
        //   relationType에 매핑돼 있어(build_reference_data.py 주석 참고 —
        //   "조카"는 uncle_of를 방향만 뒤집어 쓴 것) 두 방향 다 안전하게
        //   구분된다 — target==person이면 source가 내 "숙부", source==person
        //   이면 target이 내 "조카".
        // - "선조"/"자부"/"외조부"(ancestor_of/daughter_in_law_of/
        //   maternal_grandfather_of): "아우"/"형"/"누이"와 같은 이유로
        //   표제어 본인 페이지(target == person)에서만 보여준다.
        var siblings: [(name: String, idx: String)] = []
        var youngerBrothers: [(name: String, idx: String)] = []
        var olderBrothers: [(name: String, idx: String)] = []
        var sisters: [(name: String, idx: String)] = []
        var uncles: [(name: String, idx: String)] = []
        var nephews: [(name: String, idx: String)] = []
        var ancestors: [(name: String, idx: String)] = []
        var daughtersInLaw: [(name: String, idx: String)] = []
        var maternalGrandfathers: [(name: String, idx: String)] = []
        // [2026-09-22 추가, 사용자 확정 "A그룹 — 바로 반영"] 위 2026-09-16
        // 주석의 "(1)만 추가"에서 보류됐던 나머지 가족관계성 기타관계
        // 라벨들 — build_reference_data.py에 새로 매핑된 relation_type과
        // 정확히 같은 이름으로 맞췄다(그 파일의 2026-09-22 주석 참고).
        var fathersInLaw: [(name: String, idx: String)] = []
        var sonsInLaw: [(name: String, idx: String)] = []
        var grandchildrenViaDaughter: [(name: String, idx: String)] = []
        var greatGrandfathers: [(name: String, idx: String)] = []
        var maternalGrandmothers: [(name: String, idx: String)] = []
        // [2026-09-22 추가, 사용자 확정 "대적/동맹은 상호관계라 별도로
        // 반영"] "동역자"/"친구"와 같은 상호관계 패턴.
        var adversaries: [(name: String, idx: String)] = []
        var allies: [(name: String, idx: String)] = []
        // [2026-09-22 추가, 사용자 확정 "D그룹 — related_to 신설해서 최소
        // 반영"] 라벨이 없거나("이름#idx"만 있음) "기타"였던 항목 — 구체적
        // 관계 유형은 모르지만 관련이 있다는 사실 자체는 보여준다. 상호관계
        // 패턴(동역자/친구와 동일, 방향에 의미 없음)이라 양방향 다 담는다.
        var relatedPeople: [(name: String, idx: String)] = []
        for relation in person.relations {
            switch relation.relationType {
            case "teacher_of":
                if relation.sourceWord == person.word { disciples.append((name: relation.targetWord, idx: relation.targetIdx)) }
            case "co_worker_of":
                if relation.sourceWord == person.word { coWorkers.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if relation.targetWord == person.word { coWorkers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "friend_of":
                if relation.sourceWord == person.word { friends.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if relation.targetWord == person.word { friends.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "servant_of":
                if relation.sourceWord == person.word { lords.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if relation.targetWord == person.word { servants.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "brother_of":
                if relation.sourceWord == person.word { siblings.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if relation.targetWord == person.word { siblings.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "younger_brother_of":
                if relation.targetWord == person.word { youngerBrothers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "older_brother_of":
                if relation.targetWord == person.word { olderBrothers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "sister_of":
                if relation.targetWord == person.word { sisters.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "uncle_of":
                if relation.targetWord == person.word { uncles.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
                else if relation.sourceWord == person.word { nephews.append((name: relation.targetWord, idx: relation.targetIdx)) }
            case "ancestor_of":
                if relation.targetWord == person.word { ancestors.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "daughter_in_law_of":
                if relation.targetWord == person.word { daughtersInLaw.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "father_in_law_of":
                // [2026-09-22 추가] "장인"/"시아버지" 공통 relation_type —
                // "자부"/"daughter_in_law_of"와 같은 이유로 표제어 본인
                // 페이지(target == person)에서만 "장인: 이름"으로 보여준다.
                if relation.targetWord == person.word { fathersInLaw.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "son_in_law_of":
                if relation.targetWord == person.word { sonsInLaw.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "maternal_grandfather_of":
                if relation.targetWord == person.word { maternalGrandfathers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
                // [2026-09-22 추가] "외손자"/"외손주" — "숙부"/"조카"(uncle_of)와
                // 완전히 같은 패턴으로 같은 relationType을 반대 방향(내가
                // source, 즉 내가 조부)으로 재사용한다.
                else if relation.sourceWord == person.word { grandchildrenViaDaughter.append((name: relation.targetWord, idx: relation.targetIdx)) }
            case "maternal_grandmother_of":
                if relation.targetWord == person.word { maternalGrandmothers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "great_grandfather_of":
                if relation.targetWord == person.word { greatGrandfathers.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "adversary_of":
                if relation.sourceWord == person.word { adversaries.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if relation.targetWord == person.word { adversaries.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "ally_of":
                if relation.sourceWord == person.word { allies.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if relation.targetWord == person.word { allies.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
            case "related_to":
                if relation.sourceWord == person.word { relatedPeople.append((name: relation.targetWord, idx: relation.targetIdx)) }
                else if relation.targetWord == person.word { relatedPeople.append((name: relation.sourceWord, idx: relation.sourceIdx)) }
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
        let uniqueSonsInLaw = uniqueOrdered(sonsInLaw)
        let uniqueGrandchildrenViaDaughter = uniqueOrdered(grandchildrenViaDaughter)
        let uniqueGreatGrandfathers = uniqueOrdered(greatGrandfathers)
        let uniqueMaternalGrandmothers = uniqueOrdered(maternalGrandmothers)
        let uniqueAdversaries = uniqueOrdered(adversaries)
        let uniqueAllies = uniqueOrdered(allies)
        let uniqueRelatedPeople = uniqueOrdered(relatedPeople)
        if !uniqueDisciples.isEmpty { rows.append(("제자", uniqueDisciples)) }
        if !uniqueCoWorkers.isEmpty { rows.append(("동역자", uniqueCoWorkers)) }
        if !uniqueFriends.isEmpty { rows.append(("친구", uniqueFriends)) }
        if !uniqueLords.isEmpty { rows.append(("주군", uniqueLords)) }
        if !uniqueServants.isEmpty { rows.append(("신하", uniqueServants)) }
        if !uniqueSiblings.isEmpty { rows.append(("형제", uniqueSiblings)) }
        if !uniqueYoungerBrothers.isEmpty { rows.append(("아우", uniqueYoungerBrothers)) }
        if !uniqueOlderBrothers.isEmpty { rows.append(("형", uniqueOlderBrothers)) }
        if !uniqueSisters.isEmpty { rows.append(("누이", uniqueSisters)) }
        if !uniqueUncles.isEmpty { rows.append(("숙부", uniqueUncles)) }
        if !uniqueNephews.isEmpty { rows.append(("조카", uniqueNephews)) }
        if !uniqueAncestors.isEmpty { rows.append(("선조", uniqueAncestors)) }
        if !uniqueDaughtersInLaw.isEmpty { rows.append(("자부", uniqueDaughtersInLaw)) }
        if !uniqueMaternalGrandfathers.isEmpty { rows.append(("외조부", uniqueMaternalGrandfathers)) }
        if !uniqueFathersInLaw.isEmpty { rows.append(("장인", uniqueFathersInLaw)) }
        if !uniqueSonsInLaw.isEmpty { rows.append(("사위", uniqueSonsInLaw)) }
        if !uniqueGrandchildrenViaDaughter.isEmpty { rows.append(("외손자", uniqueGrandchildrenViaDaughter)) }
        if !uniqueGreatGrandfathers.isEmpty { rows.append(("증조부", uniqueGreatGrandfathers)) }
        if !uniqueMaternalGrandmothers.isEmpty { rows.append(("외조모", uniqueMaternalGrandmothers)) }
        if !uniqueAdversaries.isEmpty { rows.append(("대적", uniqueAdversaries)) }
        if !uniqueAllies.isEmpty { rows.append(("동맹", uniqueAllies)) }
        if !uniqueRelatedPeople.isEmpty { rows.append(("관련 인물", uniqueRelatedPeople)) }
        return rows
    }

    /// [2026-09-22 신설, B그룹 — 사용자 확정 "인물관계에는 넣지 않더라도
    /// 보여주기를 원함"] `person.contextNotes`(`PersonContextNotes` 테이블,
    /// 왕/총독/선지자 등 직함·역할성 라벨 — `PersonRelations` 인물관계
    /// 그래프와 분리된 참고 전용 데이터, 위 `PersonContextNoteRecord` 참고)를
    /// 라벨별로 묶는다. `familyRelationRows`/`otherRelationRows`와 똑같은
    /// (label, names) 모양이라 같은 `relationRow(_:)`로 그대로 그릴 수
    /// 있지만, 사용자가 "인물관계에는 넣지 않더라도"라고 명시적으로
    /// 구분했으므로 화면에서도 "관계" 카드가 아니라 별도의 "기타 정보"
    /// 카드로 보여준다(아래 body 참고).
    private var contextNoteRows: [(label: String, names: [(name: String, idx: String)])] {
        var order: [String] = []
        var byLabel: [String: [(name: String, idx: String)]] = [:]
        for note in person.contextNotes {
            if byLabel[note.label] == nil { order.append(note.label) }
            byLabel[note.label, default: []].append((name: note.targetWord, idx: note.targetIdx))
        }
        return order.map { label in (label: label, names: uniqueOrdered(byLabel[label] ?? [])) }
    }

    /// [2026-09-27 신설, C그룹] `person.groupMemberships`(`PersonGroupMemberships`
    /// 테이블, "열두 제자"/"다윗의 30용사"/"다윗의 3대용사"처럼 가족관계도
    /// 개인 직함도 아닌 "소속 집단" 전용 데이터 — 위 `PersonGroupMembershipRow`
    /// 참고)를 그룹별로 묶는다. `contextNoteRows`와 정확히 같은 (label, names)
    /// 모양이라 같은 `relationRow(_:)`로 그대로 그릴 수 있다 — 다만 "관계"/
    /// "기타 정보"와도 별도인 "소속 그룹" 전용 카드로 분리해서 보여준다(아래
    /// body 참고, HTML 목업으로 먼저 확인받은 배치).
    private var groupMembershipRows: [(label: String, names: [(name: String, idx: String)])] {
        var order: [String] = []
        var byLabel: [String: [(name: String, idx: String)]] = [:]
        for membership in person.groupMemberships {
            if byLabel[membership.groupId] == nil { order.append(membership.groupId) }
            byLabel[membership.groupId, default: []].append((name: membership.otherMemberWord, idx: membership.otherMemberIdx))
        }
        return order.map { label in (label: label, names: uniqueOrdered(byLabel[label] ?? [])) }
    }

    /// [2026-09-16 신설] 사용자 요청 - "인물 관계에서 각 인물을 클릭하면
    /// 해당 인물의 상세페이지로 이동하게 할 것." 이름 하나가 `Persons`
    /// 테이블에서 정확히(동명이인 없이) 하나로만 특정될 때만 링크로
    /// 만든다 - 동명이인이라 어느 쪽을 가리키는지 추측할 근거가 없으면
    /// (예: "야고보"가 세베대의 아들/알패오의 아들 둘 다 있는 경우) 그냥
    /// 평범한 텍스트로 남겨 잘못된 인물로 잘못 이동하는 일을 막는다 -
    /// 근거 없는 추측을 하지 않는다는 이 프로젝트 원칙을 그대로 따름.
    /// `ReferenceDataStore.persons(mentionedIn:)`을 재사용한다(이 화면이
    /// 이미 알고 있는 "아브라함/라함" 오탐 방지 필터가 적용된 함수라 이
    /// 짧은 이름 조회에도 안전하다).
    private func resolvedRelationPerson(named name: String, idx: String = "") -> PersonEntity? {
        guard let store = ReferenceDataProvider.shared.store else { return nil }
        if !idx.isEmpty, let exact = try? store.person(idx: idx) {
            return exact
        }
        let candidates = (try? store.persons(mentionedIn: name)) ?? []
        let exactMatches = candidates.filter { ($0.matchedAlias ?? $0.word) == name }
        guard exactMatches.count == 1 else { return nil }
        return exactMatches.first
    }

    /// "라벨: 이름, 이름" 한 줄 — 설명 문장이나 원문 캡션 없이 사용자가
    /// 예시로 준 형식 그대로("아들: xxx, xxx, xxx"). [2026-09-16 수정]
    /// 위 `resolvedRelationPerson`으로 유일하게 특정되는 이름만
    /// `personref:///이름` 링크로 만든다 - 링크 색은 이 화면이 이미
    /// 성경구절 링크에 쓰는 `JBCHCategoryPalette.gold`와 구분되도록
    /// `JBCHCategoryPalette.slateTeal`(같은 브랜드 팔레트, 새 임의 색
    /// 아님)을 썼다.
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

    /// [2026-09-16 신설] "관련 성경구절" 절 전용 — `SearchViewModel.
    /// VerseSearchResultGroup`과 같은 모양(책/장 단위 그룹)이지만, 검색
    /// 전용 필드(매치 개수, 참조 일치 등)가 없는 훨씬 단순한 버전이다.
    private struct VerseReferenceGroup: Identifiable {
        let bookId: Int
        let chapter: Int
        let bookNameKo: String
        let verses: [(verse: Int, content: String)]
        var id: String { "\(bookId)-\(chapter)" }
    }

    /// `person.verseRefs`를 실제 절 본문과 함께 책/장 단위로 묶는다.
    /// `SearchViewModel.resolveVerseResults(_:)`(관계/인물 카드가 이미 쓰는
    /// 같은 목적의 변환, 2026-08-20 Phase 5)와 정확히 같은 방식으로
    /// `BibleReferenceStore`를 열어 조회한다 — 그 메서드는 `private`이라
    /// 재사용은 못 하고 같은 패턴을 이 파일에 맞게 다시 구현했다(SearchView
    /// 쪽 코드는 건드리지 않음). 그 메서드와 같은 근거로 30개에서 자른다.
    /// 그룹 정렬은 검색 결과의 "매치 개수" 같은 관련성 지표가 이 화면엔
    /// 없으므로, `SearchViewModel.groupByChapter`가 매치 개수가 같을 때
    /// 쓰는 2차 기준(정경순 — 책ID/장 오름차순)을 그대로 1차 기준으로
    /// 쓴다 — 그룹 안 절 순서(오름차순)는 동일하다.
    private var groupedVerseReferences: [VerseReferenceGroup] {
        guard let store = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedBundledDatabaseURL().path) else {
            return []
        }
        var versesByChapter: [String: (bookId: Int, chapter: Int, bookNameKo: String, verses: [(Int, String)])] = [:]
        var orderedKeys: [String] = []
        for ref in person.verseRefs.prefix(30) {
            guard let verse = try? store.verse(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse) else { continue }
            let key = "\(ref.bookId)-\(ref.chapter)"
            if versesByChapter[key] == nil {
                let bookName = BooksProvider.shared.book(id: ref.bookId)?.nameKo ?? "책 \(ref.bookId)"
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

    /// `SearchView.groupCardBorder` + `verseChapterGroupHeader` + `groupedVerseRow`
    /// 3종이 함께 만드는 시각(둥근 사각 테두리 카드, "책 N장" 헤더 + 절 수,
    /// "N절) 본문" 행)을 재현한다 — 이 화면은 `List` 밖(부모가 이미 List로
    /// 감싸 쓰는 `Section` 안)이라 `groupCardBorder`가 쓰는 `.listRowInsets`/
    /// `.listRowSeparator(.hidden)`는 그대로 가져오되(부모 List의 기본 행
    /// 여백을 지우는 같은 역할), `List` 자체를 새로 만들지는 않는다.
    /// `BibleVerseChipRow.chipButton`과 정확히 같은 분기·같은 이유 — 아이폰은
    /// 크로스탭(성경 탭으로 좌표만 전달), 맥/아이패드는 조상 `NavigationStack`에
    /// 이미 등록된 `BibleVerseDestinationRegistration`을 이용한 값 기반 push.
    /// [2026-09-16 수정] 사용자 요청 - "관련 성경구절의 스타일 조정 (절
    /// 영역 만큼 들여쓰기) 할것." 기존엔 "N절) 본문"을 한 `Text`로 합쳐서
    /// 본문이 줄바꿈되면 둘째 줄부터 화면 맨 왼쪽까지 붙었다.
    /// `HStack(alignment: .top)`으로 "N절)" 접두어와 본문을 별도 `Text`로
    /// 나란히 두면, 본문 `Text`는 접두어 폭만큼 오른쪽에서부터 시작하는
    /// 자기 칸 안에서만 줄바꿈되므로 둘째 줄부터도 접두어 폭만큼 자동으로
    /// 들여쓰기된다(SwiftUI가 "매달린 들여쓰기"를 직접 지원하지 않아 고른
    /// 우회법).
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

    /// [2026-09-16 신설] 사용자 요청 — "검색 결과 상세 컨텐츠에 나오는
    /// 성경구절은 성경약어로 표현하고, 링크를 걸어 클릭하면 해당 성경으로
    /// 이동할 수 있게 할것." 개요/주요 생애/업적과 사건/성품과 특징은
    /// PersonSeed.json의 자유 서술 문장이라 "(창세기 17:5)" 같은 인용이
    /// 본문 중간에 섞여 있다 — `BibleReferenceExtractor`(메모/연구문서
    /// 자유 텍스트에서 "책 이름+장:절"을 찾는 기존 정규식 파서, 2026-08-11
    /// 신설)를 그대로 재사용해 위치를 찾고, 이 화면 전용으로 "책 이름
    /// 부분만 약어로 바꿔 링크를 건" `AttributedString`을 만든다.
    ///
    /// 범위 인용("창세기 9:22-25")은 그 파서가 절 하나하나로 펼쳐 여러
    /// `Match`를 돌려주지만, 전부 원문 안의 같은 위치(`range`)를 공유한다
    /// (`BulkCrossReferenceParser.swift` 헤더 주석이 설명하는 것과 같은
    /// "책+장+절 하나 = Match 하나, 정규식 매치 하나가 여러 Match로
    /// 펼쳐짐" 규약) — 그래서 연속으로 같은 `range`를 가진 Match들은 한
    /// 그룹으로 묶어 링크 하나만 만든다(그룹의 첫 절로 이동).
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
                // [주의] "책+장"까지만 있고 절이 없는 인용("창세기 17장")은
                // `verse`가 nil로 온다 — 그 장 자체로는 이동할 수 없으니
                // (BibleVerseDestination이 절 좌표를 요구) 1절로 이동한다.
                verse: match.verse ?? 1
            ))
        }
        return groups
    }

    /// 매치된 원문("창세기 17:5")에서 책 이름 부분(숫자가 시작되기 전까지)만
    /// 표준 약어로 바꾸고, 나머지(장:절/범위 표기)는 사용자가 원래 쓴 그대로
    /// 둔다 — 성경약어 표기 규칙만 적용하고 인용 자체를 다시 조합하지
    /// 않는다(추측 없이 원문 보존).
    private func abbreviatedCitationLabel(_ matchedText: String, bookId: Int) -> String {
        guard let firstDigitIndex = matchedText.firstIndex(where: { $0.isNumber }) else { return matchedText }
        let book = BooksProvider.shared.book(id: bookId)
        let abbreviation = book?.abbreviation.first ?? book?.nameKo
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
            // [2026-09-16 수정] 사용자 요청 - "성경 구절 링크 스타일을
            // 심플한 언더라인이 아니라 다른 디자인을 도입하기 바람 (캡슐형
            // 링크? 아이콘?) 링크 텍스트는 조금 작아도 됨." 앞에 작은 책
            // 아이콘을 붙이고, 언더라인 대신 옅은 배경 하이라이트(칩과
            // 비슷한 느낌)를 주는 방식으로 바꿨다 - 색은 카드 테두리와 같은
            // `JBCHCategoryPalette.gold`(브랜드 팔레트, 새 임의 색 아님)를
            // 써서 본문(`bibleTextColor`)과 확실히 구분되게 했다.
            // [주의] 문단 안에 흐르는 `Text`라 실제 여백이 있는 둥근 캡슐
            // 모양(패딩+모서리 둥글기)은 SwiftUI가 지원하지 않는다 -
            // `AttributedString.backgroundColor`는 텍스트 줄에 딱 붙는
            // 사각형 하이라이트만 그린다. 이 세션엔 Xcode가 없어 실기기
            // 렌더링 확인이 필요하다.
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

    /// 위 링크(`bibleReferenceLinkedText`)가 만드는 `bibleref:///책ID/장/절`
    /// URL을 실제 이동으로 바꾼다. `NavigationLink(value:)`(맥/아이패드가
    /// 보통 쓰는 값 기반 push, `BibleVerseChipRow`/`verseReferenceRow` 참고)는
    /// `NavigationPath`에 바인딩된 뷰 트리 안에서만 되는데, `.environment(
    /// \.openURL)` 핸들러엔 그 경로에 접근할 방법이 없다 — 그래서 플랫폼
    /// 구분 없이 이 앱이 이미 어디서든 성경 조회로 이동할 때 쓰는 범용
    /// 크로스탭 메커니즘(`AppNavigationRequest`+`BibleVerseNavigationRequest`,
    /// `SidebarNavigationView`/`PhoneTabView` 양쪽 다 관찰함)을 그대로 쓴다.
    private func handleBibleReferenceLink(_ url: URL) -> OpenURLAction.Result {
        // [2026-09-16 추가] 위 `relationRow`가 만드는 `personref:///이름`
        // 링크 - `relationStack`에 그 인물을 밀어 넣어(위 struct 선언부
        // 주석 참고) 이 화면 자체가 그 인물의 상세로 바뀌게 한다.
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

    /// [2026-09-16 신설] 사용자 요청 — "각 요소의 소제목과 그에 따른 본문이
    /// 구분선의 구분 보다는 디자인의 요소로 구분될 수 있도록 할 것." 기본
    /// `Section("제목")`의 옅은 시스템 구분선 대신, 이 화면이 "관련
    /// 성경구절" 절에 이미 쓰고 있던 것과 같은 둥근 테두리 카드(같은
    /// `JBCHCategoryPalette.wood` 톤 — 그 카드 헤더 주석이 밝힌 "새 임의
    /// 색을 만들지 않는다" 원칙을 그대로 따름)로 소제목마다 카드를 나눈다.
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
                    // [2026-09-16 확대] 사용자 요청 — "소주제 (개요, 주요
                    // 생애, 업적과 사건, 성품과 특징, 인물정보, 관계, 관련성경
                    // 구절) 크기를 현재 '인물 정보' 텍스트 크기처럼 키울 것."
                    // 통합검색 목록의 "인물 정보" 절 제목이 쓰는
                    // `SearchView.sectionHeader`의 제목 폰트(`.title3.weight(
                    // .semibold)`)와 정확히 맞췄다.
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(settings.bibleTextColor ?? .primary)
            .textCase(nil)
            .padding(.leading, 16)
        }
    }

    var body: some View {
        Group {
            // [2026-09-16 신설] 사용자 요청 - "인물 관계에서 각 인물을
            // 클릭하면 해당 인물의 상세페이지로 이동." `relationStack`이
            // 비어있지 않으면(관계에서 다른 인물로 넘어와 있는 상태) 위
            // `intentCardSection`의 "목록으로" 버튼과 같은 스타일로 뒤로
            // 갈 수 있는 버튼을 보여준다 - push가 아니라 로컬 스택을 pop할
            // 뿐이라 NavigationStack 없이도 동작한다.
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
            // [2026-09-16 수정] 사용자 보고 — "'목록으로'와 '개요' 사이의
            // 내용이 왼쪽으로 붙어있음." 원래 `EdgeInsets()`(전부 0)라 제목/
            // 태그/인용구가 화면 맨 왼쪽 끝에 그대로 달라붙어 있었다 — 아래
            // 카드 섹션들과 같은 좌우 여백(16)을 주고, 위아래도 숨쉴 틈을
            // 뒀다.
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if !person.introduce.isEmpty {
                cardSection("개요", icon: "doc.text.fill") {
                    bibleReferenceLinkedText(person.introduce).font(.body)
                }
            }
            if !person.lifetime.isEmpty {
                cardSection("주요 생애", icon: "calendar") {
                    bibleReferenceLinkedText(person.lifetime).font(.body)
                }
            }
            if !person.event.isEmpty {
                cardSection("업적과 사건", icon: "flag.fill") {
                    bibleReferenceLinkedText(person.event).font(.body)
                }
            }
            if !person.character.isEmpty {
                cardSection("성품과 특징", icon: "sparkles") {
                    bibleReferenceLinkedText(person.character).font(.body)
                }
            }
            if !infoFacts.isEmpty {
                cardSection("인물 정보", icon: "info.circle.fill") {
                    ForEach(Array(infoFacts.enumerated()), id: \.offset) { index, fact in
                        LabeledContent(fact.label, value: fact.value)
                        if index < infoFacts.count - 1 {
                            subtleRowDivider()
                        }
                    }
                }
            }
            if !familyRelationRows.isEmpty || !otherRelationRows.isEmpty {
                // [2026-09-16 수정] 위 `subtleRowDivider` 참고 — 할아버지~손녀
                // 그룹과 제자/동역자/친구 그룹을 하나의 목록으로 이어 붙여
                // 행 사이마다(두 그룹의 경계 포함) 옅은 구분선을 넣는다.
                let allRelationRows = familyRelationRows + otherRelationRows
                cardSection("관계", icon: "person.2.fill") {
                    ForEach(Array(allRelationRows.enumerated()), id: \.offset) { index, row in
                        relationRow(row)
                        if index < allRelationRows.count - 1 {
                            subtleRowDivider()
                        }
                    }
                }
            }
            if !groupMembershipRows.isEmpty {
                // [2026-09-27 신설, C그룹] 위 `groupMembershipRows` 참고 —
                // "열두 제자"/"다윗의 30·3대용사"처럼 특정 소속 라벨이 정확히
                // 붙은 경우만 여기 모인다("관계" 카드의 "관련 인물"(D그룹,
                // 라벨 없음/"기타")·"기타 정보" 카드(B그룹, 왕/선지자 등
                // 직함)와는 서로 다른 자리 — HTML 목업으로 먼저 확인받은
                // 배치·스타일 그대로).
                cardSection("소속 그룹", icon: "person.3.fill") {
                    ForEach(Array(groupMembershipRows.enumerated()), id: \.offset) { index, row in
                        relationRow(row)
                        if index < groupMembershipRows.count - 1 {
                            subtleRowDivider()
                        }
                    }
                }
            }
            if !contextNoteRows.isEmpty {
                // [2026-09-22 신설, B그룹 — 사용자 확정 "인물관계에는 넣지
                // 않더라도 보여주기를 원함"] 위 `contextNoteRows` 참고 —
                // 왕/총독/선지자 등은 위 "관계" 카드와 의도적으로 분리된
                // 별도 카드다(인물관계 그래프에 넣지 않기로 한 결정을
                // 화면에서도 그대로 지킨다).
                cardSection("기타 정보", icon: "info.circle.fill") {
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
                            // [2026-09-16 확대] 위 `cardSection` 헤더와 같은
                            // 이유로 같은 폰트로 맞췄다.
                            .font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .textCase(nil)
                    .padding(.leading, 16)
                }
            }
            // [2026-09-16 삭제] 사용자 요청 — "참고는 뺄 것." 기존 "참고"
            // 절(`person.entityRemark`)을 통째로 없앴다.
        }
        // [2026-09-16 신설] 위 `bibleReferenceLinkedText`/
        // `handleBibleReferenceLink` 참고 — 본문 안 성경 인용 링크를 탭하면
        // 시스템 브라우저로 가는 기본 동작 대신 앱 안에서 성경 조회로
        // 이동하도록 가로챈다. `Group` 하나에만 걸어도 그 안의 모든
        // `Section`/`Text`에 환경값으로 전파된다.
        .environment(\.openURL, OpenURLAction(handler: handleBibleReferenceLink))
        // [2026-09-16 신설] 사용자 보고 - "관계의 또다른 인물 클릭 -> 검색란의
        // 새로운 검색어로 검색하면, 검색한 인물이 아니라 여전히 관계에서
        // 넘어간 인물이 나온다. '이전 인물로'를 눌러야만 검색어로 검색한
        // 인물이 나온다." 원인: `initialPerson`은 매 렌더마다 새 검색 결과로
        // 갱신되지만, `@State private var relationStack`은 SwiftUI가 이
        // `PersonDetailView`를 트리 안에서 "같은 자리"로 보는 한(값 기반
        // 식별자가 없어) 렌더를 넘어 그대로 남아있다 - 그래서 검색어를
        // 바꿔도 관계 내비게이션으로 쌓아둔 스택이 새 검색 결과를 계속
        // 가리고 있었다. `initialPerson.idx`가 바뀌었다는 것은 곧 "다른
        // 검색으로 새 인물이 들어왔다"는 뜻이므로, 이때는 무조건 스택을
        // 비운다 - 사용자 확인: "검색어로 검색하면 스택은 초기화해야 함.
        // 검색어로 검색하면 '이전 인물로' 기능 자체가 없어야 함."
        .onChange(of: initialPerson.idx) { _, _ in
            relationStack.removeAll()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(person.word)
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 28, relativeTo: .largeTitle))
                    .fontWeight(.bold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Spacer(minLength: 0)
            }
            // [확정, claude/bible-research-platform-search-category-expansion-
            // proposal.md 11차 문서] 별칭(word2)으로 매칭됐어도 제목은 항상
            // 대표 이름(위 person.word) — 여기서는 그 사실을 부제로만 안내한다.
            if let alias = person.matchedAlias {
                Text("별칭 \u{201C}\(alias)\u{201D}로 검색됨")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
            if !person.callTitle.isEmpty {
                Text(person.callTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !person.occupation.isEmpty {
                // [주의] 화면 폭이 좁은 아이폰에서 직업이 여러 개면 줄바꿈이
                // 필요할 수 있다 — `HStack`은 줄바꿈하지 않으므로 `WrappingHStack`류
                // 커스텀 레이아웃 없이는 넘칠 수 있다. 이 프로젝트엔 아직 그런
                // 범용 줄바꿈 레이아웃이 없어(근거 없이 새로 만들지 않음),
                // 실기기에서 직업이 3개 이상인 인물로 확인이 필요한 부분이다.
                HStack(spacing: 6) {
                    ForEach(person.occupation, id: \.self) { role in
                        // [2026-09-16 수정] 사용자 요청 - "인물 이름 밑에
                        // 파란색 계열 캡슐 : 색상을 디자인 테마와 맞출것.
                        // 파란색이 이질감처럼 느껴짐. 말씀노트의 탭 캡슐의
                        // 디자인이 적당하지 않을까 함." 기존
                        // `Color.accentColor`(파란색 계열)를 이 화면이 이미
                        // 카드 테두리에 쓰고 있는 `JBCHCategoryPalette.wood`로
                        // 바꾸고, 크기/굵기도 말씀노트 카테고리 배지
                        // (`WordNoteRowView.categoryBadge`: `.caption2.bold()`
                        // + 가로 6/세로 2 패딩 + 15% 배경)와 맞췄다 - 새 임의
                        // 색을 만들지 않는다는 원칙을 그대로 따름.
                        Text(role)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(JBCHCategoryPalette.wood.opacity(0.15), in: Capsule())
                            .foregroundStyle(JBCHCategoryPalette.wood)
                    }
                }
            }
            if !person.meaning.isEmpty {
                Text("\u{201C}\(person.meaning)\u{201D}")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

}
