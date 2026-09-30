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

    /// [2026-09-28 신설] 사용자 요청 — "[설교 관리] 기능... 태그가 기존 기능에
    /// 잘 녹아들어야 함." `MemoTag`/`SummaryTag`/`DocumentTag`와 완전히 같은
    /// 설계 원칙(원시 UUID 대신 `sermon: Sermon?` 관계를 직접 쓴다) — 위 세
    /// 조인 엔티티 상단 주석과 같은 이유.
    @Relationship(deleteRule: .cascade, inverse: \SermonTag.tag)
    public var sermonTags: [SermonTag]? = []

    /// [2026-09-29 신설, 버그 수정] 위 `sermonTags`와 완전히 같은 이유 —
    /// `SermonDeliveryTag`(회차별 독립 태그, 이 파일 하단 참고) 쪽의
    /// 인버스. 이 프로퍼티가 빠져 있으면 CloudKit 스키마 검증이 "SermonDeliveryTag:
    /// tag에 인버스가 없다"(CoreData 134060, "CloudKit integration requires
    /// that all relationships have an inverse")로 실패해 `ModelContainer`
    /// 로드 자체가 막힌다 — 실기기 Xcode 콘솔 로그로 실제 확인된 크래시
    /// 원인(2026-09-29, 사용자 보고: "'내 설교' 기능이 추가된 이후에 이전의
    /// 데이터가 삭제됨"). `SermonTag`를 추가할 때는 `Tag` 쪽 인버스를 같이
    /// 추가했는데, 뒤이어 `SermonDeliveryTag`를 추가할 때 이 짝을 빠뜨린
    /// 것이 원인 — `JBCHBibleResearchApp.swift`의 3단계 폴백(CloudKit 포함
    /// 디스크 → CloudKit 제외 디스크 → in-memory)이 실제로 이 실패를 잡아
    /// "데이터가 사라진 것처럼 보이는" 증상(2번째 폴백 단계로 떨어지며 매번
    /// 새 로컬 저장소를 만드는 게 아니라, 최종적으로 3번째 in-memory 폴백까지
    /// 떨어져 앱을 껐다 켤 때마다 저장소가 초기화됐던 것)을 만든 근본 원인이다.
    /// 이 인버스를 추가하면 애초에 폴백까지 갈 필요 없이 정상적으로 CloudKit
    /// 포함 디스크 컨테이너가 로드되어야 한다.
    @Relationship(deleteRule: .cascade, inverse: \SermonDeliveryTag.tag)
    public var sermonDeliveryTags: [SermonDeliveryTag]? = []

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

/// 설교(`Sermon`) ↔ 태그 조인 엔티티. [2026-09-28 신설] 사용자 요청 — "[설교
/// 관리] 기능... 태그가 기존 기능에 잘 녹아들어야 함." `MemoTag`/`SummaryTag`/
/// `DocumentTag`와 완전히 같은 설계 원칙(원시 UUID 대신 `sermon: Sermon?` 관계를
/// 직접 쓴다 — 설교가 삭제되면 CloudKit 동기화 상으로도 정합성이 자동 유지된다)
/// — 위 세 조인 엔티티 상단 주석 참고.
///
/// ⚠️ [2026-09-29 설계 결정 번복] 이 주석은 원래 "`SermonDelivery`(모임별
/// 사본)에는 별도 태그를 붙이지 않는다 — 태그는 메인 설교문(`Sermon`) 단위로만
/// 붙는다"고 명시했었다. 사용자가 이번에 명시적으로 다시 확인한 결정으로 그
/// 제약을 뒤집는다 — 회차(`SermonDelivery`)마다 메인 설교문과 완전히 독립된
/// 자기만의 태그를 가질 수 있다(예: 메인은 #은혜 #거듭남, 특정 수요예배 사본만
/// #단회용). 그 독립 태그 조인 엔티티가 바로 아래 `SermonDeliveryTag`다 — 이
/// 타입과 완전히 같은 설계 원칙(원시 UUID 대신 관계 직접 참조)을 그대로 따른다.
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

/// 설교 회차 사본(`SermonDelivery`) ↔ 태그 조인 엔티티. [2026-09-29 신설]
/// 사용자 결정 — "회차마다 독립적인 태그"(위 `SermonTag` 주석의 "설계 결정
/// 번복" 참고). `SermonTag`와 완전히 같은 설계 원칙·같은 모양이며, 가리키는
/// 대상만 `Sermon` 대신 `SermonDelivery`다 — 메인 설교문의 `sermonTags`와는
/// 서로 완전히 독립된 별도 태그 집합이라(공유하지 않음) 새 조인 엔티티를
/// 하나 더 둔다(기존 `SermonTag`에 옵셔널 `delivery` 필드를 얹는 대신 —
/// `SermonVerseReference`가 `sermon`/`delivery` 중 하나만 채우는 배타적
/// 필드를 쓰는 것과 달리, 태그는 "이 조인이 어느 쪽 소속인지"가 타입 자체로
/// 고정되는 편이 더 단순하다고 판단).
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
