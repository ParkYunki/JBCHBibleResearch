import Foundation
import SwiftData

// 근거: bible-research-platform-screens.md 6.3(태그 정규화 + 관계) +
// bible-research-platform-review-addendum.md 1장(크리티컬 이슈 — @Attribute(.unique) + CloudKit 조합 불가).
//
// 원본 6.3은 `Tag(id, name UNIQUE, ...)`였으나, SwiftData + CloudKit 조합에서 unique
// 제약은 지원되지 않아 ModelContainer 로드 자체가 실패한다(addendum 1.1). 아래 구현은
// addendum 1.2/1.3에서 확정된 2단계 대응(생성 시점 중복 차단 + 동기화 후 잔여 중복 병합)을
// 그대로 반영한다. 실제 병합/차단 로직은 Support/TagDeduplication.swift에 있다.
//
// 📝 구현 결정(문서에 없던 세부사항, 이번 구현에서 확정):
// SwiftData + CloudKit은 "모든 저장 프로퍼티가 기본값을 갖거나 옵셔널이어야 한다"는
// 제약이 있다(schema.md 8장 5번 항목에서 "최종 스펙 정리" 대상으로 남겨뒀던 부분).
// 이 파일부터는 그 제약을 실제로 적용해 모든 non-optional 프로퍼티에 기본값을 준다.
//
// ⚠️ 2026-08-06 실기기 런타임 오류로 확인된 추가 제약: to-many @Relationship도
// **타입 자체가 Optional**이어야 한다(`[T] = []`로는 부족하고 `[T]? = []`여야 함).
// 컴파일은 통과하지만 실제 ModelContainer 로드 시점에 CoreData 134060 에러
// ("CloudKit integration requires that all relationships be optional")로 걸린다.
// 아래 모든 to-many 관계에 반영했다.

/// 메모용 Tag + 원본 스키마의 KeywordIndex(성경/문서 공용 키워드 마스터)를 통합한 단일 테이블.
/// 근거: 6.3 — "태그를 선택하면 관련 메모·연구문서·OCR 이미지를 모두 조회할 수 있어야 함"
/// 요구사항에 따라 메모 태그와 문서 키워드가 같은 테이블을 가리켜야 함.
@Model
public final class Tag {
    public var id: UUID = UUID()
    public var name: String = ""
    public var normalizedForm: String = ""
    public var language: String?
    public var createdAt: Date = Date.now

    /// non-nil = 이 레코드는 병합되어 사라진 "패자". 이 값이 가리키는 id를 가진 Tag가 정본이다.
    /// ⚠️ 태그를 나열하는 모든 쿼리(자동완성, S10 그래프, findOrCreateTag)는
    /// 반드시 `mergedIntoId == nil` 조건을 포함해야 한다. (addendum 1.3)
    public var mergedIntoId: UUID?

    /// 병합 시각 + 유예기간(기본 3일, `TagDeduplication.gracePeriod`)이 지난 뒤에만
    /// 하드 삭제 대상이 된다. 즉시 삭제하지 않는 이유: 병합 스윕이 도는 순간 다른
    /// 화면에서 방금 "패자"가 된 태그를 편집·참조 중일 수 있기 때문(addendum 1.3).
    public var pendingDeletionAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \MemoTag.tag)
    public var memoTags: [MemoTag]? = []

    /// [2026-08-14 신설] 사용자 요청 — "말씀 요약의 글을 클릭했을 때에도 개인
    /// 묵상 유형의 글처럼 태그를 입력할 수 있게 할것." `MemoTag`와 완전히 같은
    /// 이유/구조(관계로 연결해 `VerseSummary` 삭제 시 정합성 자동 유지) — 다만
    /// `VerseSummary`가 `UserMemo`와 별개 모델(폴더 없음, 저널 성격)이라 조인
    /// 테이블도 별도로 둔다.
    @Relationship(deleteRule: .cascade, inverse: \SummaryTag.tag)
    public var summaryTags: [SummaryTag]? = []

    @Relationship(deleteRule: .cascade, inverse: \DocumentAnchor.linkedTag)
    public var documentAnchors: [DocumentAnchor]? = []

    /// [2026-08-16 신설] 사용자 요청 — "각 뷰어에 tag를 추가할 수 있도록 하단에
    /// 태그 추가/수정 라인 삽입." 위 `documentAnchors`(문서 내 특정 위치를
    /// 가리키는 앵커)와는 다른 목적 — 이건 문서 "전체"에 붙는 태그다(메모의
    /// `memoTags`와 같은 성격). `DocumentAnchor.linkedTag`를 재사용하지 않고
    /// 별도 조인 테이블(`DocumentTag`)을 새로 둔 이유도 이 차이 때문.
    @Relationship(deleteRule: .cascade, inverse: \DocumentTag.tag)
    public var documentTags: [DocumentTag]? = []

    @Relationship(deleteRule: .cascade, inverse: \TagRelation.tagA)
    public var relationsAsA: [TagRelation]? = []

    @Relationship(deleteRule: .cascade, inverse: \TagRelation.tagB)
    public var relationsAsB: [TagRelation]? = []

    /// 원본 스키마의 KeywordOccurrence(성경 본문 내 발생)와의 연결.
    /// 6.3: "원본의 keyword_id → tag_id로 통일. 현재 어떤 화면도 이걸 채우도록
    /// 설계 안 됨 — 향후 확장 여지로만 유지."
    @Relationship(deleteRule: .cascade, inverse: \KeywordOccurrence.tag)
    public var keywordOccurrences: [KeywordOccurrence]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        normalizedForm: String,
        language: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.normalizedForm = normalizedForm
        self.language = language
        self.createdAt = createdAt
    }

    /// 편의 프로퍼티 — 병합되어 읽기전용이 된 태그인지. S10 상세 화면에서
    /// "병합되어 읽기전용" 상태(addendum 5장 상태 변형 목록) 판단에 사용.
    public var isMerged: Bool { mergedIntoId != nil }
}

/// 메모 ↔ 태그 조인 엔티티.
/// ⚠️ addendum 1.3의 `reassignRelationships` 예시 코드는 `memoTag.memoId`(원시 UUID
/// 비교)를 가정했지만, addendum 자신도 "실제 모델 프로퍼티명에 맞춰 조정하라"고
/// 명시했다(1.3 각주). 이 구현에서는 원시 UUID 필드 대신 `memo: UserMemo?` 관계를
/// 직접 쓰기로 확정한다 — 관계를 쓰면 UserMemo가 삭제될 때 CloudKit 동기화 상으로도
/// 정합성이 자동 유지되지만, 원시 UUID를 따로 들고 있으면 memo 삭제 시 수동으로
/// 정리해줘야 하는 댕글링 참조가 하나 더 생기기 때문이다. `TagDeduplication.swift`의
/// `reassignRelationships`도 이 필드명(`memo`)에 맞춰 작성했다.
@Model
public final class MemoTag {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \UserMemo.memoTags)
    public var memo: UserMemo?

    public var tag: Tag?

    public init(id: UUID = UUID(), memo: UserMemo? = nil, tag: Tag? = nil, createdAt: Date = .now) {
        self.id = id
        self.memo = memo
        self.tag = tag
        self.createdAt = createdAt
    }
}

/// 말씀 요약 ↔ 태그 조인 엔티티. `MemoTag`와 완전히 같은 설계 원칙(원시 UUID
/// 대신 `summary: VerseSummary?` 관계를 직접 쓴다) — 위 `Tag.summaryTags` 상단
/// 주석 참고.
@Model
public final class SummaryTag {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \VerseSummary.summaryTags)
    public var summary: VerseSummary?

    public var tag: Tag?

    public init(id: UUID = UUID(), summary: VerseSummary? = nil, tag: Tag? = nil, createdAt: Date = .now) {
        self.id = id
        self.summary = summary
        self.tag = tag
        self.createdAt = createdAt
    }
}

/// 연구문서 ↔ 태그 조인 엔티티. [2026-08-16 신설] 사용자 요청 — "각 뷰어에 tag를
/// 추가할 수 있도록 하단에 태그 추가/수정 라인 삽입." `MemoTag`/`SummaryTag`와
/// 완전히 같은 설계 원칙(원시 UUID 대신 `document: SourceDocument?` 관계를
/// 직접 쓴다 — 문서가 삭제되면 CloudKit 동기화 상으로도 정합성이 자동
/// 유지된다) — 위 두 조인 엔티티 상단 주석 참고.
@Model
public final class DocumentTag {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \SourceDocument.documentTags)
    public var document: SourceDocument?

    public var tag: Tag?

    public init(id: UUID = UUID(), document: SourceDocument? = nil, tag: Tag? = nil, createdAt: Date = .now) {
        self.id = id
        self.document = document
        self.tag = tag
        self.createdAt = createdAt
    }
}

/// 수동 태그-태그 관계(6.3). S10에서 실선으로 표시되는 엣지.
/// 자동 추론 엣지(점선)는 저장하지 않고 `MemoTag` 동시 등장 빈도를 그때그때 계산한다
/// (6.3: "MemoTag를 조인해 같은 메모에 동시 등장한 빈도를 S10에서 계산").
@Model
public final class TagRelation {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now

    public var tagA: Tag?
    public var tagB: Tag?

    public init(id: UUID = UUID(), tagA: Tag? = nil, tagB: Tag? = nil, createdAt: Date = .now) {
        self.id = id
        self.tagA = tagA
        self.tagB = tagB
        self.createdAt = createdAt
    }
}
