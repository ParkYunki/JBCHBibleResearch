import Foundation
import SwiftData

// 설교 관리 모델: 한 설교(`Sermon`)를 여러 모임에서 사용하고(`SermonDelivery`),
// 회차마다 본문을 독립적으로 수정한다.
// 관계의 deleteRule은 배열을 가진 쪽에서만 지정한다(Tags.swift 상단 주석과 동일).
// 새 타입은 `BibleResearchSchema.modelTypes`에 등록해야 CloudKit 동기화에서 빠지지 않는다.

/// 설교 작성 화면의 문단 프리셋 스타일 6종. 문단 하나엔 스타일 하나이며,
/// 어휘는 장/절 개요와 별개로 설교 전용으로 정의한다.
public enum SermonParagraphStyle: String, Codable, Sendable, CaseIterable {
    case mainTheme   // 대주제
    case midTheme    // 중주제
    case subTheme    // 소주제
    case verseQuote  // 말씀구절
    case citation    // 인용
    case body        // 본문
}

/// 설교(`Sermon`) 또는 회차 사본(`SermonDelivery`) 본문 안에서 "말씀구절" 스타일로 작성자가
/// 명시적으로 지정한 성경 좌표. 본문을 정규식으로 재스캔해 자동 추출하는 `VerseMention`과는 별개다.
///
/// ⚠️ `sermon`/`delivery` 중 정확히 하나만 설정되어야 한다. 이 제약은 타입 레벨이 아니라
/// 호출부(에디터 저장 로직)의 책임이다.
@Model
public final class SermonVerseReference {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verseStart: Int = 1
    public var verseEnd: Int?
    /// 본문 안에서 이 참조가 걸린 문단의 순번(0부터 시작) — 에디터가 이 문단을
    /// 다시 찾아 스크롤/하이라이트할 때 사용.
    public var paragraphIndex: Int = 0

    // deleteRule은 배열을 가진 `Sermon.verseReferences`/`SermonDelivery.verseReferences` 쪽에서만 지정한다.
    public var sermon: Sermon?
    public var delivery: SermonDelivery?

    public init(
        id: UUID = UUID(),
        bookId: Int,
        chapter: Int,
        verseStart: Int,
        verseEnd: Int? = nil,
        paragraphIndex: Int = 0,
        sermon: Sermon? = nil,
        delivery: SermonDelivery? = nil
    ) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
        self.paragraphIndex = paragraphIndex
        self.sermon = sermon
        self.delivery = delivery
    }
}

/// 설교가 선포된 모임의 종류(예: 주일설교/청년회 말씀)를 담는 룩업 테이블. 자유 텍스트 대신 두는 이유는
/// 표기 흔들림("주일 예배"/"주일예배")으로 이력 집계·자동완성이 흐트러지는 것을 막기 위해서다.
///
/// 초기 시드값(주일설교, 청년회 말씀, 구역모임, 조모임)은 앱 레이어가 최초 실행 시 생성한다 —
/// 이 모델은 시드 여부를 모른다.
@Model
public final class SermonGathering {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \SermonDelivery.gathering)
    public var deliveries: [SermonDelivery]? = []

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// 메인 설교문. `UserMemo`/`VerseSummary`와 같은 `contentHtml`(현재는 실제 HTML이 아닌 RTF 문자열)+
/// `contentText`(검색·미리보기용) 이원화 패턴을 따른다. 편집은 문단 프리셋 스타일
/// (`SermonParagraphStyle`)을 지원하는 전용 에디터가 담당한다.
@Model
public final class Sermon {
    public var id: UUID = UUID()
    public var title: String = ""
    public var contentHtml: String = ""
    public var contentText: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// 문단별 `SermonParagraphStyle` 태그를 `contentHtml`(RTF)과 별도로 저장한다. RTF는 표준 서식만
    /// 보존해 커스텀 attribute(`.sermonParagraphStyle`)가 인코딩 중 사라지기 때문이다.
    ///
    /// 형식: `SermonParagraphStyleCodec.delimiter`(U+001F)로 이어붙인 `rawValue` 시퀀스. `contentText`의
    /// 문단(줄바꿈) 단위와 1:1 대응하도록 에디터가 저장 시 다시 계산하며, 개수가 어긋나면
    /// `SermonParagraphStyleCodec.apply`가 모자란 자리를 `.body`로 채운다(모델은 정합성을 강제하지 않는다).
    public var paragraphStyles: String = ""

    /// 마지막 저장 시점의 각 `SermonParagraphStyle` 폰트/크기/색(`UserSettingsStore` 값)을 JSON으로 찍어 둔
    /// 스냅샷(`SermonParagraphStyleCodec.StyleSnapshot`).
    ///
    /// 에디터는 문서를 열 때마다 문단 폰트를 현재 설정값으로 다시 계산해 전역 스타일 변경이 소급 반영되게 한다.
    /// 그런데 저장된 폰트만으로는 "프리셋을 따르는 중"인지 "사용자가 수동 지정"한 것인지 구분할 수 없으므로
    /// 스냅샷과 비교한다: 같으면 새 프리셋값으로 재계산하고, 다르면 수동 지정으로 보고 보존한다.
    /// 문단정렬은 프리셋이 항상 `.natural`이라 natural이 아니면 곧 수동 지정이므로 스냅샷이 필요 없다.
    ///
    /// `paragraphStyles`처럼 문서당 하나이며, 커스텀 attribute라 RTF에는 저장되지 않는다.
    public var styleFontSnapshot: String = ""

    /// `UserMemo.pendingIndexRefresh`와 같은 이유(`UserContent.swift` 참고) — 재인덱싱이 끝나기 전까지
    /// "인덱스가 최신이 아닐 수 있음" 배지를 보여주는 데 쓴다.
    public var pendingIndexRefresh: Bool = false
    /// `UserMemo.isPinned`와 같은 패턴.
    public var isPinned: Bool = false

    public var sermonTags: [SermonTag]? = []

    // deleteRule은 배열을 가진 이쪽에서만 지정한다.
    @Relationship(deleteRule: .cascade, inverse: \SermonVerseReference.sermon)
    public var verseReferences: [SermonVerseReference]? = []

    /// 이 설교의 마인드맵 노드 전체(MindMaps.swift 참고). 마인드맵은 메인 설교문 단위로만 두고
    /// 회차 사본에는 두지 않는다. 설교가 삭제되면 마인드맵도 의미가 없으므로 `.cascade`.
    @Relationship(deleteRule: .cascade, inverse: \MindMapNode.sermon)
    public var mindMapNodes: [MindMapNode]? = []

    /// 이 메인 설교문이 실제로 쓰인 모임별 이력.
    @Relationship(deleteRule: .cascade, inverse: \SermonDelivery.sermon)
    public var deliveries: [SermonDelivery]? = []

    /// 마인드맵 캔버스의 마지막 스크롤 위치·확대율(맵마다 별도). 세 값 모두 Optional — `nil`은 "저장된 적 없음"
    /// (처음 여는 맵, 이 필드 추가 전에 만들어진 설교)을 뜻하며, 이때 화면(`SermonMindMapView`)은 루트 노드를
    /// 화면 중앙에 맞춘다. Optional 스칼라(`Double?`)라 기존 행의 NULL이 그대로 `nil`로 읽혀 마이그레이션 문제가 없다.
    public var mindMapViewportX: Double?
    public var mindMapViewportY: Double?
    public var mindMapZoom: Double?

    public init(
        id: UUID = UUID(),
        title: String,
        contentHtml: String = "",
        contentText: String = "",
        paragraphStyles: String = "",
        styleFontSnapshot: String = "",
        pendingIndexRefresh: Bool = false,
        isPinned: Bool = false,
        mindMapViewportX: Double? = nil,
        mindMapViewportY: Double? = nil,
        mindMapZoom: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.contentHtml = contentHtml
        self.contentText = contentText
        self.paragraphStyles = paragraphStyles
        self.styleFontSnapshot = styleFontSnapshot
        self.pendingIndexRefresh = pendingIndexRefresh
        self.isPinned = isPinned
        self.mindMapViewportX = mindMapViewportX
        self.mindMapViewportY = mindMapViewportY
        self.mindMapZoom = mindMapZoom
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 설교 실행 이력 — 어떤 모임에서 언제 했는지와 그때 실제로 읽은(수정됐을 수 있는) 본문.
/// 생성 시 `Sermon`의 현재 `contentHtml`/`contentText`를 복사해 시작하고 이후 독립적으로 편집된다.
/// "메인과 동일한지"는 플래그를 저장하지 않고 화면에서 `contentText`를 `Sermon.contentText`와
/// 비교해 판단한다(저장할 때마다 플래그를 동기화해야 하는 부담을 피하기 위함).
@Model
public final class SermonDelivery {
    public var id: UUID = UUID()
    public var deliveredAt: Date = Date.now
    public var contentHtml: String = ""
    public var contentText: String = ""
    /// `Sermon.paragraphStyles`와 같은 이유·같은 형식 — 회차 사본은 메인과 독립적으로 편집되므로
    /// 사본마다 별도로 저장한다.
    public var paragraphStyles: String = ""
    /// `Sermon.styleFontSnapshot`과 같은 이유 — 회차 사본은 메인과 독립적으로 편집되므로
    /// 사본마다 별도로 저장한다.
    public var styleFontSnapshot: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var pendingIndexRefresh: Bool = false

    /// 회차마다 독립적인 태그 집합 — 메인 설교문의 `sermonTags`와 공유하지 않는다
    /// (`Tags.swift`의 `SermonDeliveryTag` 참고).
    public var deliveryTags: [SermonDeliveryTag]? = []

    // deleteRule은 `Sermon.deliveries` 쪽에서 지정한다. 메인 설교문이 삭제되면 활용 이력도 함께 정리된다.
    public var sermon: Sermon?

    // deleteRule은 `SermonGathering.deliveries` 쪽에서 `.nullify`로 지정한다 —
    // 모임 종류가 삭제돼도 그 모임에서 했던 설교 이력은 남아야 한다.
    public var gathering: SermonGathering?

    /// 이 회차 사본 본문 안에서 "말씀구절" 스타일로 지정된 성경 좌표.
    /// deleteRule은 배열을 가진 이쪽에서 지정한다.
    @Relationship(deleteRule: .cascade, inverse: \SermonVerseReference.delivery)
    public var verseReferences: [SermonVerseReference]? = []

    public init(
        id: UUID = UUID(),
        deliveredAt: Date = .now,
        contentHtml: String = "",
        contentText: String = "",
        paragraphStyles: String = "",
        styleFontSnapshot: String = "",
        pendingIndexRefresh: Bool = false,
        sermon: Sermon? = nil,
        gathering: SermonGathering? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.deliveredAt = deliveredAt
        self.contentHtml = contentHtml
        self.contentText = contentText
        self.paragraphStyles = paragraphStyles
        self.styleFontSnapshot = styleFontSnapshot
        self.pendingIndexRefresh = pendingIndexRefresh
        self.sermon = sermon
        self.gathering = gathering
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
