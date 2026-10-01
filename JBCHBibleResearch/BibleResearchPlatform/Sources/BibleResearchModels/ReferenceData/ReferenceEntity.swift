import Foundation

//
//  ReferenceEntity.swift
//  BibleResearchModels
//
//  `ReferenceDataStore`의 Persons/Places/PersonRelations 등 조회 결과를 담는 값 타입 모음.
//  SwiftData `@Model`이 아니라 평범한 구조체다 — `HanjaCharacterInfo`/`HanjaWordAnnotation`과
//  같은 원칙(정적 참조 데이터를 퍼시스턴스 레이어에 넣지 않는다, `ReferenceDataStore.swift`
//  상단 주석 참고).
//

// `ReferenceEntity.Kind`/`PersonRelationRecord`/`PersonEntity`/`ThemeRecord`는 `Hashable`이다 —
// `Set`/`Dictionary` 키 등으로 쓸 수 있도록 채택해 뒀다(조회 결과를 그대로 들고 다니는 값이라 부작용 없음).

/// `Persons`/`Places` 테이블 조회 결과 — 인물/지명 사전 한 항목.
public struct ReferenceEntity {
    public enum Kind: Hashable {
        case person
        case place
    }

    public let idx: String
    public let word: String
    /// 화면 출력용 서술(`Persons.remark`/`Places.remark` 컬럼). 데이터 분석용 원본 description은
    /// 관계 추출 입력으로만 쓰이며 이 값 타입에는 포함하지 않는다.
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
    /// 빈 문자열이 아니면 `targetWord`가 가리키는 `Persons.idx`가 빌드 시점에 확정된 경우다
    /// (`PersonRelations.target_idx`). 빈 문자열은 "모른다"는 뜻이지 "동명이인이 없다"는 뜻이
    /// 아니므로, 호출부는 이름 기준 동명이인 검사로 폴백해야 한다(`PersonDetailView.resolvedRelationPerson`).
    public let targetIdx: String
    /// `targetIdx`의 대칭 — `sourceWord`의 `Persons.idx`가 PersonSeed.json의 "이름#idx" 태그
    /// (`build_reference_data.py`의 `parse_idx_tag`)로 확정된 경우만 채워진다. 빈 문자열이면
    /// "모른다"는 뜻(동명이인 검사 폴백 필요).
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

/// `PersonContextNotes` 테이블 조회 결과 한 건 — 왕/총독/선지자 등 직함·역할성 기타관계 라벨.
/// `PersonRelationRecord`와 의도적으로 분리했다 — 인물관계 그래프(`PersonRelations`)에는 넣지 않고
/// `PersonDetailView`의 참고 전용 절에서만 표시한다.
public struct PersonContextNoteRecord: Hashable {
    public let sourceWord: String
    /// 원본 라벨 그대로(예: "총독", "왕", "선지자") — 화면에 "라벨: 이름" 형식으로 노출한다.
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

/// `PersonGroups`/`PersonGroupMemberships` 기반 — 이 인물과 같은 그룹에 속한 다른 사람 한 명
/// (자기 자신은 쿼리 단계에서 제외). "열두 제자"/"다윗의 30용사"처럼 가족관계도 개인 직함도
/// 아닌 소속 집단 전용 레코드라 `PersonContextNoteRecord`와 분리했다.
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

/// 친인척 9종(할아버지~손녀, `PersonFamilyRelations`)은 `PersonRelations`가 아니라 `Persons`의
/// 전용 컬럼(`rel_*`, PersonSeed.json 원본 그대로)에서 읽는다 — `PersonRelationRecord`는 같은 세대
/// 그룹(아버지/어머니, 아들/딸 등)을 표제어 성별만으로 son_of/daughter_of 등에 뭉뚱그려 저장해
/// 원래 필드를 구분할 수 없기 때문이다.
///
/// `PersonFamilyRelations`의 이름 하나 — "이름#idx" 태그가 있으면 분리된 상태다. `idx`가 빈
/// 문자열이면 태그가 없던 경우이며, 동명이인 검사 폴백은 `PersonRelationRecord.targetIdx`와 같다.
public struct PersonFamilyMember: Hashable {
    public let name: String
    public let idx: String
    /// "이름#idx(설명)" 형식의 괄호 안 설명(예: "야고보#4057(사도)"의 "사도"). 없으면 "".
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

/// `Places` 테이블 조회 결과(전체 컬럼) — 장소 상세 페이지 전용(PlaceSeed.json 기반).
///
/// 같은 이름의 지명(동명이인, 예: "가나" 3곳)은 이름이 아니라 `idx`로 구분한다 — `remark` 앞의 "1. 2. 3."이
/// 그 구분 표기다. 본문 4개(`introduce`/`bibleContents`/`geography`/`history`)는 데이터가 없거나 "기록 없음"만 있는
/// 칸이 "-"로 저장돼 있다(`build_reference_data.py`의 `normalize_no_record`).
public struct PlaceEntity: Hashable {
    public let idx: String
    public let word: String
    /// 한 줄 설명(예: "1. 예수께서 이적을 행한 갈릴리의 한 동네."). 비어 있을 수 있다.
    public let remark: String
    public let verseRefs: [BibleVerseRef]
    public let introduce: String
    public let bibleContents: String
    public let geography: String
    public let history: String

    public init(
        idx: String, word: String, remark: String, verseRefs: [BibleVerseRef],
        introduce: String, bibleContents: String, geography: String, history: String
    ) {
        self.idx = idx
        self.word = word
        self.remark = remark
        self.verseRefs = verseRefs
        self.introduce = introduce
        self.bibleContents = bibleContents
        self.geography = geography
        self.history = history
    }
}

/// `Persons` 테이블 조회 결과(전체 컬럼) — 인물 프로필 카드 전용.
/// 5컬럼 고정인 `ReferenceEntity`와 별도 타입인 이유는 `ReferenceDataStore.swift` 상단 주석 참고 —
/// PersonSeed.json 기반 보강 컬럼을 `UNION ALL` 구조의 기존 조회로는 담을 수 없다.
public struct PersonEntity: Hashable {
    public let idx: String
    /// 대표 이름 — 화면 제목은 별칭으로 검색됐어도 항상 이 값을 쓴다(`matchedAlias` 참고).
    public let word: String
    /// `word2` 콤마 분리 — 이표기/별칭 전체 목록.
    public let aliases: [String]
    public let entityRemark: String
    public let verseRefs: [BibleVerseRef]
    /// 별칭(`aliases`) 중 하나로 매칭됐을 때만 그 별칭 문자열, 대표 이름으로 매칭됐으면 nil.
    /// 화면은 이 값이 있을 때만 "별칭 OOO로 검색됨" 같은 부제를 보여준다(제목은 항상 `word`).
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
    /// 이 인물이 source든 target이든 걸린 `PersonRelations` 전부(양방향, 중복 제거) —
    /// `PersonRelationLabeling.sentence(for:)`로 문장을 만든다. 친인척 9종은 `familyRelations`가
    /// 담당하므로 이 배열은 "기타관계"(제자/동역자/친구 등) 표시에만 쓴다.
    public let relations: [PersonRelationRecord]
    /// 친인척 9종 — `PersonFamilyRelations` 참고.
    public let familyRelations: PersonFamilyRelations
    /// 이 인물이 source인 참고 정보만 담는다(방향에 의미가 있어 역방향은 없음) —
    /// `PersonContextNoteRecord` 참고.
    public let contextNotes: [PersonContextNoteRecord]
    /// 이 인물이 속한 각 그룹의 "다른" 멤버들(자기 자신 제외) — `PersonGroupMembershipRow` 참고.
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
// 세 테이블은 "같은 토픽"이 아니라 컬럼 구조 자체가 달라서 하나로 합치지 않았다.
// - Themes: 주제 하나 = 근거 절 목록 하나(교리/실천/속성, 이름 붙은 본문 묶음 포함).
// - Prophecies: "예언 절 -> 성취/대응 절" 쌍 + 시대 구분. 메시아 예언/마지막 때 예언/마지막 전쟁은
//   구조가 같아 `category` 컬럼으로만 구분한다.
// - TimelineEvents: 서사 하나가 여러 행(사건)으로 구성되며, 관련성 순이 아니라
//   `sequence_order` 그대로 반환해야 한다.
//
// `category`/`timelinePeriod`/`era` 등은 값 종류가 정해져 있어도 Swift enum이 아니라 `String`이다 —
// DB 스키마에 CHECK 제약이 없는 자유 텍스트라 닫힌 집합을 강제하면 DB와 타입이 어긋날 수 있다
// (`PersonRelationRecord.relationType`과 같은 이유).

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
    /// nullable, 자유 텍스트(`TimelineEventRecord.era`와 같은 어휘 공유 — 위 MARK 주석 참고).
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
