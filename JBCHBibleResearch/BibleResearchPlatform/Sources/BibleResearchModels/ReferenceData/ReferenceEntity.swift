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

// [2026-09-15 추가, 2026-09-16 배경 변경] `ReferenceEntity.Kind`/
// `PersonRelationRecord`/`PersonEntity`/`ThemeRecord`에 `Hashable`을
// 추가했다. 원래(2026-09-15) 이유는 통합검색의 인물/주제 카드를 상세 화면
// (PersonDetailView/ThemeDetailView)으로 보내는 값 기반 내비게이션
// (`PersonDetailDestination`/`ThemeDetailDestination`)이 `NavigationLink
// (value:)`에 쓰기 위해서였다. 2026-09-16 사용자 피드백("통합검색 페이지
// 자체가 바뀌어야 한다는 의미") 이후 그 별도 push 방식 자체를 없애면서
// `Views/Navigation/PersonThemeDetailDestination.swift`와 그 안의
// `PersonDetailDestination`/`ThemeDetailDestination`은 삭제했지만(`SearchView.
// swift`가 이제 값 기반 push 없이 자신의 `List` 안에서 직접 전환한다), 이
// `Hashable` 채택 자체는 남겨 뒀다 — 제거해도 얻는 이득이 없고(다른 곳에서
// 이 타입들을 `Set`/`Dictionary` 키 등으로 쓸 가능성을 막지 않는 것이 오히려
// 안전하며), 이미 조회 시점에 메모리에 있는 값을 그대로 들고 다니는 것이라
// 기존 저장/조회 로직에 아무 영향도 없는 순수 추가 프로토콜 채택이기 때문이다.

/// `Persons`/`Places` 테이블 조회 결과 — 인물/지명 사전 한 항목.
public struct ReferenceEntity {
    public enum Kind: Hashable {
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
public struct PersonRelationRecord: Hashable {
    public let sourceWord: String
    public let relationType: String
    public let targetWord: String
    /// nil이면 규칙 추출은 됐지만 대상 이름이 이 번들 데이터셋(체크포인트가
    /// 일부만 담고 있음) 안에서 확인되지 않은 경우 — 호출부는 이 경우
    /// `ReferenceDataStore.personOrPlace(exactWord:)`를 시도하지 말아야
    /// 한다(어차피 nil이 나옴, 조회 낭비 방지 목적으로 여기서 미리 구분).
    public let targetKind: ReferenceEntity.Kind?
    public let rawSentence: String
    /// [2026-09-16 신설] 빈 문자열이 아니면 `targetWord`가 가리키는 `Persons.idx`가
    /// 이미 정확히 알려진 경우다(`build_reference_data.py`의 `PersonRelations.
    /// target_idx` 컬럼 참고 — "기타관계 Y(라벨)"에서 target이 표제어 자신인
    /// 경우처럼, 추측 없이 빌드 시점에 확정적으로 아는 경우에만 채워진다).
    /// 빈 문자열이면 "모른다"는 뜻이지 "동명이인이 없다"는 뜻이 아니다 — 호출부는
    /// 여전히 이름 기준 동명이인 검사로 폴백해야 한다(`PersonDetailView.
    /// resolvedRelationPerson` 참고).
    public let targetIdx: String
    /// [2026-09-16 추가] 사용자 요청 — "관계 데이터에 idx를 붙이는 것에
    /// 대해서 어떠한지?" 위 `targetIdx`의 대칭 — `sourceWord`가 가리키는
    /// `Persons.idx`가 정확히 알려진 경우만 채워진다. `target_idx`와 달리
    /// "자기 자신이라 자동으로 앎"이 아니라, PersonSeed.json에 "이름#idx"
    /// 태그(`build_reference_data.py`의 `parse_idx_tag` 참고, "#" 구분자로
    /// 동명이인을 직접 확정하는 표기법)를 사람이 직접 적어 뒀을 때만 채워진다
    /// — 빈 문자열이면 "모른다"는 뜻(동명이인 검사 폴백 필요), targetIdx와
    /// 같은 원칙.
    public let sourceIdx: String

    public init(
        sourceWord: String, relationType: String, targetWord: String,
        targetKind: ReferenceEntity.Kind?, rawSentence: String, targetIdx: String = "",
        sourceIdx: String = ""
    ) {
        self.sourceWord = sourceWord
        self.relationType = relationType
        self.targetWord = targetWord
        self.targetKind = targetKind
        self.rawSentence = rawSentence
        self.targetIdx = targetIdx
        self.sourceIdx = sourceIdx
    }
}

/// [2026-09-22 신설, B그룹] `PersonContextNotes` 테이블 조회 결과 한 건 —
/// 왕/총독/선지자 등 직함·역할성 기타관계 라벨(build_reference_data.py의
/// `is_context_label` 판정) 하나. `PersonRelationRecord`와 의도적으로 분리된
/// 별도 타입이다 — 사용자 확정("인물관계에는 넣지 않더라도 보여주기를
/// 원함")에 따라 `PersonRelations`(인물관계 그래프, 검색/관계 카드/
/// QueryIntentHandler가 관계로 취급하는 테이블)에는 아예 들어가지 않고,
/// `PersonDetailView`의 참고 전용 절에서만 표시된다.
public struct PersonContextNoteRecord: Hashable {
    public let sourceWord: String
    /// 원본 라벨 그대로(예: "총독", "왕", "선지자") — 화면에 "라벨: 이름"
    /// 형식으로 그대로 노출한다(가공하지 않음, 추측 금지).
    public let label: String
    public let targetWord: String
    public let targetKind: ReferenceEntity.Kind?
    /// `PersonRelationRecord.targetIdx`와 같은 규칙 — 빈 문자열이면 동명이인
    /// 검사 폴백 필요, 아니면 "이름#idx" 태그로 정확히 확정된 값.
    public let targetIdx: String
    public let rawSentence: String

    public init(
        sourceWord: String, label: String, targetWord: String,
        targetKind: ReferenceEntity.Kind?, targetIdx: String, rawSentence: String
    ) {
        self.sourceWord = sourceWord
        self.label = label
        self.targetWord = targetWord
        self.targetKind = targetKind
        self.targetIdx = targetIdx
        self.rawSentence = rawSentence
    }
}

/// [2026-09-27 신설, C그룹] "PersonGroups/PersonGroupMemberships" 참고 —
/// 이 인물과 "같은 그룹"에 속한 다른 사람 한 명(자기 자신은 제외, 쿼리
/// 단계에서 이미 걸러짐). "열두 제자"/"다윗의 30용사"/"다윗의 3대용사"처럼
/// 가족관계도 개인 직함도 아닌 "소속 집단"을 위한 전용 레코드 —
/// PersonContextNoteRecord(B그룹, 직함/역할)와 의도적으로 분리한다.
public struct PersonGroupMembershipRow: Hashable {
    /// PersonGroups.group_id — 원문 라벨 그대로(예: "열두 제자").
    public let groupId: String
    public let otherMemberWord: String
    /// 비어 있을 수 있음(원본 "이름#idx" 태그에 idx가 없거나 Persons에
    /// 존재하지 않는 경우) — `PersonRelationRecord.targetIdx`와 같은 규칙,
    /// 화면은 비어 있으면 이름 기준 동명이인 검사로 폴백한다.
    public let otherMemberIdx: String

    public init(groupId: String, otherMemberWord: String, otherMemberIdx: String) {
        self.groupId = groupId
        self.otherMemberWord = otherMemberWord
        self.otherMemberIdx = otherMemberIdx
    }
}

/// [2026-09-16 신설] 사용자 요청 — "인물 정보의 관계 내용은 PersonSeed.json의
/// 관계중 기타관계를 제외한 내용(할아버지, 할머니, 아버지, 어머니, 배우자,
/// 아들, 딸, 손자, 손녀)를 설명없이 간단하게 표현할것." `PersonRelationRecord`
/// (아래, `PersonRelations` 테이블 경유)는 이 9개 필드 중 같은 세대 그룹
/// (예: 아버지/어머니, 아들/딸, 할아버지/할머니, 손자/손녀)을 표제어 본인의
/// 성별만으로 son_of/daughter_of 등에 뭉뚱그려 저장하기 때문에(빌드 스크립트
/// `RELATION_TYPE_BY_GENDER` 참고), relationType만으로는 원래 어느 필드였는지
/// 구분이 구조적으로 불가능하다 — 그래서 이 9개 필드는 `PersonRelationRecord`를
/// 거치지 않고 `Persons` 테이블의 전용 컬럼(`rel_*`, PersonSeed.json 원본을
/// 추론 없이 그대로 옮김)에서 직접 읽어 이 별도 타입에 담는다. 이름은
/// 콤마 분리된 배열 그대로 — 화면이 "라벨: 이름, 이름" 형식으로 렌더링한다.
/// [2026-09-16 신설] 사용자 요청 — "PersonSeed.json의 관계(할아버지~손녀)...
/// 데이터 안에 앞에 인덱스 숫자를 붙이는 것에 대해서 어떠한지?" 위
/// `PersonFamilyRelations`의 이름 하나("이름#idx" 태그 있으면 분리된 상태,
/// `ReferenceDataStore`의 파싱 참고). `idx`가 빈 문자열이면 태그가 없던
/// 경우(기존 데이터 그대로, 하위 호환) — 화면 쪽 동명이인 검사 폴백은
/// `PersonRelationRecord.targetIdx`와 완전히 같은 규칙을 그대로 쓴다.
public struct PersonFamilyMember: Hashable {
    public let name: String
    public let idx: String
    /// [2026-09-26 신설] 사용자 요청 — "화면에도 보여주게 해주세요"(PersonSeed.json
    /// 가족관계 필드의 "이름#idx(설명)" 형식 중 괄호 안 설명, 예: "야고보#4057(사도)"의
    /// "사도"). 태그가 없거나 설명이 없으면 "" — 하위 호환, 기존 데이터는 동작 변화 없음.
    public let note: String

    public init(name: String, idx: String, note: String = "") {
        self.name = name
        self.idx = idx
        self.note = note
    }
}

public struct PersonFamilyRelations: Hashable {
    public let grandfathers: [PersonFamilyMember]
    public let grandmothers: [PersonFamilyMember]
    public let fathers: [PersonFamilyMember]
    public let mothers: [PersonFamilyMember]
    public let spouses: [PersonFamilyMember]
    public let sons: [PersonFamilyMember]
    public let daughters: [PersonFamilyMember]
    public let grandsons: [PersonFamilyMember]
    public let granddaughters: [PersonFamilyMember]

    public var isEmpty: Bool {
        grandfathers.isEmpty && grandmothers.isEmpty && fathers.isEmpty && mothers.isEmpty
            && spouses.isEmpty && sons.isEmpty && daughters.isEmpty && grandsons.isEmpty
            && granddaughters.isEmpty
    }

    public init(
        grandfathers: [PersonFamilyMember], grandmothers: [PersonFamilyMember], fathers: [PersonFamilyMember], mothers: [PersonFamilyMember],
        spouses: [PersonFamilyMember], sons: [PersonFamilyMember], daughters: [PersonFamilyMember], grandsons: [PersonFamilyMember],
        granddaughters: [PersonFamilyMember]
    ) {
        self.grandfathers = grandfathers
        self.grandmothers = grandmothers
        self.fathers = fathers
        self.mothers = mothers
        self.spouses = spouses
        self.sons = sons
        self.daughters = daughters
        self.grandsons = grandsons
        self.granddaughters = granddaughters
    }
}

/// `Persons` 테이블 조회 결과(전체 컬럼) — 인물 프로필 카드 전용.
/// [2026-09-15 신설] `personOrPlaceInfo` 인텐트를 대체하는 새 파이프라인
/// (`QueryIntentHandler.handleKeywordCategoryLookup`)이 쓴다. 기존
/// `ReferenceEntity`(5컬럼 고정, `handleRelation`이 여전히 씀)와 별도 타입인
/// 이유는 `ReferenceDataStore.swift` 상단 주석 참고 — `Persons` 테이블에
/// 2026-09-15에 추가된 13개 보강 컬럼(PersonSeed.json 기반)을 `UNION ALL`
/// 구조인 기존 조회로는 구조적으로 담을 수 없다.
public struct PersonEntity: Hashable {
    public let idx: String
    /// 대표 이름 — 화면 제목은 별칭으로 검색됐어도 항상 이 값을 쓴다
    /// (`matchedAlias` 참고, claude/bible-research-platform-search-
    /// category-expansion-proposal.md 11차 문서 확정).
    public let word: String
    /// `word2` 콤마 분리 — 이표기/별칭 전체 목록.
    public let aliases: [String]
    public let entityRemark: String
    public let verseRefs: [BibleVerseRef]
    /// 별칭(`aliases`) 중 하나로 매칭됐을 때만 그 별칭 문자열, 대표 이름
    /// 자체로 매칭됐으면 nil. 화면은 이 값이 있을 때만 "별칭 OOO로 검색됨"
    /// 같은 부제를 보여주면 된다 — 제목(`word`)은 이 값과 무관하게 항상
    /// 고정(11차 문서 확정).
    public let matchedAlias: String?
    public let callTitle: String
    public let meaning: String
    public let introduce: String
    public let lifetime: String
    public let event: String
    public let character: String
    public let origin: String
    public let nation: String
    public let tribe: String
    public let gender: String
    public let occupation: [String]
    public let seedMemo: String
    /// 이 인물이 source든 target이든 걸린 `PersonRelations` 전부(양방향,
    /// 중복 제거) — `PersonRelationLabeling.sentence(for:)`로 문장을 만들어
    /// 보여주면 된다(기존 관계 카드 렌더링 재사용, 새로 만들 필요 없음).
    /// [2026-09-16] "관계" 절의 친인척 9종(할아버지~손녀)은 더 이상 이 배열을
    /// 쓰지 않는다 — 위 `PersonFamilyRelations` 주석 참고. 이 배열은 이제
    /// "기타관계"(제자/동역자/친구 등) 표시에만 쓰인다.
    public let relations: [PersonRelationRecord]
    /// [2026-09-16 신설] 위 `PersonFamilyRelations` 참고.
    public let familyRelations: PersonFamilyRelations
    /// [2026-09-22 신설, B그룹] 위 `PersonContextNoteRecord` 참고 — 이
    /// 인물이 source인(자기 자신의 PersonSeed 기타관계 목록에 있는) 것만
    /// 담는다(관계와 달리 방향에 의미가 있는 참고 정보라 역방향은 없음).
    public let contextNotes: [PersonContextNoteRecord]
    /// [2026-09-27 신설, C그룹] 위 `PersonGroupMembershipRow` 참고 — 이
    /// 인물이 속한 각 그룹의 "다른" 멤버들(자기 자신 제외, 쿼리 단계에서
    /// 이미 걸러짐).
    public let groupMemberships: [PersonGroupMembershipRow]

    public init(
        idx: String, word: String, aliases: [String], entityRemark: String,
        verseRefs: [BibleVerseRef], matchedAlias: String?, callTitle: String, meaning: String,
        introduce: String, lifetime: String, event: String, character: String, origin: String,
        nation: String, tribe: String, gender: String, occupation: [String], seedMemo: String,
        relations: [PersonRelationRecord], familyRelations: PersonFamilyRelations,
        contextNotes: [PersonContextNoteRecord] = [],
        groupMemberships: [PersonGroupMembershipRow] = []
    ) {
        self.idx = idx
        self.word = word
        self.aliases = aliases
        self.entityRemark = entityRemark
        self.verseRefs = verseRefs
        self.matchedAlias = matchedAlias
        self.callTitle = callTitle
        self.meaning = meaning
        self.introduce = introduce
        self.lifetime = lifetime
        self.event = event
        self.character = character
        self.origin = origin
        self.nation = nation
        self.tribe = tribe
        self.gender = gender
        self.occupation = occupation
        self.seedMemo = seedMemo
        self.relations = relations
        self.familyRelations = familyRelations
        self.contextNotes = contextNotes
        self.groupMemberships = groupMemberships
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
public struct ThemeRecord: Hashable {
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
