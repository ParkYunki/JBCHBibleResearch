import Foundation
import SwiftData

// Tag 모델과 태그 조인 엔티티들.
//
// SwiftData + CloudKit은 `@Attribute(.unique)`를 지원하지 않아 ModelContainer 로드가 실패하므로
// Tag에 unique를 두지 않는다. 대신 생성 시점 중복 차단 + 동기화 후 잔여 중복 병합의 2단계로
// 대응한다(실제 로직은 Support/TagDeduplication.swift).
//
// CloudKit 제약: non-optional 저장 프로퍼티는 모두 기본값을 가져야 하고, to-many @Relationship도
// 타입 자체가 Optional(`[T]? = []`)이어야 한다. 후자를 어기면 컴파일은 통과하지만 ModelContainer
// 로드 시 CoreData 134060("CloudKit integration requires that all relationships be optional")이 난다.

/// 메모용 Tag와 성경/문서 공용 키워드 마스터(KeywordIndex)를 통합한 단일 테이블. 태그를 선택하면
/// 관련 메모·연구문서·OCR 이미지를 모두 조회할 수 있도록 같은 테이블을 가리킨다.
@Model
public final class Tag {
    public var id: UUID = UUID()
    public var name: String = ""
    public var normalizedForm: String = ""
    public var language: String?
    public var createdAt: Date = Date.now

    /// non-nil = 이 레코드는 병합되어 사라진 "패자". 이 값이 가리키는 id를 가진 Tag가 정본이다.
    /// ⚠️ 태그를 나열하는 모든 쿼리(자동완성, S10 그래프, findOrCreateTag)는
    /// 반드시 `mergedIntoId == nil` 조건을 포함해야 한다.
    public var mergedIntoId: UUID?

    /// 병합 시각 + 유예기간(기본 3일, `TagDeduplication.gracePeriod`)이 지난 뒤에만
    /// 하드 삭제 대상이 된다. 즉시 삭제하지 않는 이유: 병합 스윕이 도는 순간 다른
    /// 화면에서 방금 "패자"가 된 태그를 편집·참조 중일 수 있기 때문.
    public var pendingDeletionAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \MemoTag.tag)
    public var memoTags: [MemoTag]? = []

    /// `VerseSummary` 태그용 관계. `MemoTag`와 같은 구조이며, `VerseSummary`가 `UserMemo`와 별개 모델이라
    /// 조인 테이블도 별도로 둔다.
    @Relationship(deleteRule: .cascade, inverse: \SummaryTag.tag)
    public var summaryTags: [SummaryTag]? = []

    @Relationship(deleteRule: .cascade, inverse: \DocumentAnchor.linkedTag)
    public var documentAnchors: [DocumentAnchor]? = []

    /// 문서 "전체"에 붙는 태그(`documentAnchors`는 문서 내 특정 위치를 가리키는 앵커라 용도가 다르다).
    /// `DocumentAnchor.linkedTag`를 재사용하지 않고 별도 조인 테이블(`DocumentTag`)을 둔다.
    @Relationship(deleteRule: .cascade, inverse: \DocumentTag.tag)
    public var documentTags: [DocumentTag]? = []

    /// 설교 태그용 관계. `MemoTag`/`SummaryTag`/`DocumentTag`와 같은 설계 원칙
    /// (원시 UUID 대신 `sermon: Sermon?` 관계를 직접 쓴다).
    @Relationship(deleteRule: .cascade, inverse: \SermonTag.tag)
    public var sermonTags: [SermonTag]? = []

    /// `SermonDeliveryTag.tag`의 인버스. ⚠️ CloudKit은 모든 관계에 인버스를 요구하므로 이 프로퍼티가 빠지면
    /// CoreData 134060("CloudKit integration requires that all relationships have an inverse")으로
    /// `ModelContainer` 로드가 실패한다(`JBCHBibleResearchApp.swift`의 폴백 단계로 떨어져 저장소가 초기화되는 증상이 났다).
    @Relationship(deleteRule: .cascade, inverse: \SermonDeliveryTag.tag)
    public var sermonDeliveryTags: [SermonDeliveryTag]? = []

    @Relationship(deleteRule: .cascade, inverse: \TagRelation.tagA)
    public var relationsAsA: [TagRelation]? = []

    @Relationship(deleteRule: .cascade, inverse: \TagRelation.tagB)
    public var relationsAsB: [TagRelation]? = []

    /// `KeywordOccurrence`(성경 본문 내 발생)와의 연결. 현재 이를 채우는 화면은 없다(향후 확장용).
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

    /// 병합되어 읽기전용이 된 태그인지 여부(S10 상세 화면의 "병합되어 읽기전용" 상태 판단용).
    public var isMerged: Bool { mergedIntoId != nil }
}

/// 메모 ↔ 태그 조인 엔티티.
/// 메모 ↔ 태그 조인 엔티티. 원시 UUID 필드 대신 `memo: UserMemo?` 관계를 직접 쓴다 — 관계를 쓰면
/// UserMemo 삭제 시 CloudKit 동기화 상으로도 정합성이 자동 유지되고, 수동 정리가 필요한
/// 댕글링 UUID 참조가 생기지 않는다.
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

/// 말씀 요약 ↔ 태그 조인 엔티티. `MemoTag`와 같은 설계 원칙(`summary: VerseSummary?` 관계를 직접 쓴다).
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

/// 연구문서 ↔ 태그 조인 엔티티. `MemoTag`/`SummaryTag`와 같은 설계 원칙
/// (`document: SourceDocument?` 관계를 직접 쓴다).
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

/// 수동 태그-태그 관계. S10에서 실선 엣지로 표시된다.
/// 자동 추론 엣지(점선)는 저장하지 않고 `MemoTag` 동시 등장 빈도를 그때그때 계산한다.
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

/// 설교(`Sermon`) ↔ 태그 조인 엔티티. `MemoTag`/`SummaryTag`/`DocumentTag`와 같은 설계 원칙
/// (`sermon: Sermon?` 관계를 직접 쓴다).
///
/// 이 태그는 메인 설교문 단위이며, 회차 사본(`SermonDelivery`)은 아래 `SermonDeliveryTag`로
/// 메인과 독립된 자기만의 태그를 가진다.
@Model
public final class SermonTag {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Sermon.sermonTags)
    public var sermon: Sermon?

    public var tag: Tag?

    public init(id: UUID = UUID(), sermon: Sermon? = nil, tag: Tag? = nil, createdAt: Date = .now) {
        self.id = id
        self.sermon = sermon
        self.tag = tag
        self.createdAt = createdAt
    }
}

/// 설교 회차 사본(`SermonDelivery`) ↔ 태그 조인 엔티티. `SermonTag`와 같은 모양이지만 메인 설교문의
/// `sermonTags`와 공유하지 않는 독립 태그 집합이다. `SermonTag`에 옵셔널 `delivery`를 얹지 않고
/// 별도 엔티티로 둔 것은 조인의 소속이 타입으로 고정되는 편이 더 단순하기 때문이다.
@Model
public final class SermonDeliveryTag {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \SermonDelivery.deliveryTags)
    public var delivery: SermonDelivery?

    public var tag: Tag?

    public init(id: UUID = UUID(), delivery: SermonDelivery? = nil, tag: Tag? = nil, createdAt: Date = .now) {
        self.id = id
        self.delivery = delivery
        self.tag = tag
        self.createdAt = createdAt
    }
}
