import Foundation
import SwiftData

// [2026-09-28 신설] 사용자 요청 — "[설교 관리] 기능 추가. 한 설교 문서를 여러
// 모임에서 사용할 수 있고(어떤 모임/언제 했는지 확인), 메인 설교문을 모임마다
// 조금씩 수정할 수 있어야 한다(메인↔활용 이력 추적)." 설계 근거와 화면 기획은
// `claude/sermon-management-screens-and-schema.md`(프로젝트 문서, 2026-09-28) 참고.
//
// ⚠️ 이 파일은 Xcode 빌드로 검증되지 않았습니다(이 세션은 사용자 Mac의 파일
// 시스템에는 접근하지만 Xcode/Swift 툴체인은 실행할 수 없습니다). 아래는
// UserMemo/VerseSummary(UserContent.swift)와 Tag/MemoTag/SummaryTag(Tags.swift)의
// 기존 관례를 그대로 따랐지만, 실제 빌드 시 다음을 반드시 재확인해 주세요:
//   1. `BibleResearchSchema.modelTypes`에 새 타입들을 등록했는지(이 커밋에 포함,
//      3.2 참고) — 빠지면 CloudKit 동기화에서 조용히 제외됨.
//   2. SermonVerseReference의 sermon/delivery 관계 양쪽에 @Relationship을 중복
//      지정하지 않았는지 — Tags.swift 상단 주석의 "같은 관계 양쪽에 deleteRule을
//      중복 지정하지 않는다" 원칙을 그대로 따랐습니다(배열을 가진 쪽에만 지정).
//   3. 실제 CloudKit 컨테이너에 새 레코드 타입이 처음 생성될 때 Xcode 콘솔에
//      CoreData 134060(옵셔널 관계 위반) 등 스키마 오류가 없는지.

/// 설교 작성 화면의 문단 프리셋 스타일 6종.
/// `bible-research-platform-screens.md` 6.8(개요/머릿말/부머릿말/본문/목록)과
/// "문단 하나엔 스타일 하나" 원칙은 같지만, 어휘 자체는 설교 전용으로 새로
/// 정의한다 — 장/절 개요와 설교는 문단이 담는 의미가 다르므로 그 세트를 그대로
/// 재사용하지 않는다(설계 문서 2.2 S-SER2 참고).
public enum SermonParagraphStyle: String, Codable, Sendable, CaseIterable {
    case mainTheme   // 대주제
    case midTheme    // 중주제
    case subTheme    // 소주제
    case verseQuote  // 말씀구절
    case citation    // 인용
    case body        // 본문
}

/// 설교(`Sermon`) 또는 그 특정 회차 사본(`SermonDelivery`) 본문 안에서 "말씀구절"
/// 스타일로 작성자가 명시적으로 지정한 성경 좌표. `VerseMention`(본문 전체를
/// 정규식으로 재스캔해 자동 추출하는 언급, `VerseMentions.swift`)과는 별개다 —
/// 이쪽은 저자가 "+ 추가" UI로 직접 책/장/절을 선택해 만든 구조적 참조라 자동
/// 추출보다 정확도가 높고, 에디터가 그 문단을 다시 찾아 스크롤/하이라이트할 때도
/// 쓰인다(설계 문서 3장).
///
/// ⚠️ 설계 결정: `sermon`/`delivery` 중 정확히 하나만 설정되어야 한다(하나의
/// 참조는 메인 설교문 또는 그 회차 사본 중 한쪽에만 속한다) — 이 배타적 제약은
/// 현재 이 모델 타입 레벨에서 강제하지 않고 호출부(에디터 저장 로직)의 책임으로
/// 둔다. 이 프로젝트의 `Tag.mergedIntoId`처럼 주석으로 불변식을 명시하고 타입을
/// 억지로 복잡하게 만들지 않는 기존 관례를 따른다.
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

    // deleteRule은 Sermon.verseReferences / SermonDelivery.verseReferences 쪽(배열을
    // 가진 쪽)에서만 지정한다 — 같은 관계 양쪽에 중복 지정하지 않는다는 이 파일의
    // 원칙(Tags.swift 상단 주석과 동일)을 그대로 따른다.
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

/// 설교가 실제로 선포된 모임의 종류(예: 주일설교/청년회 말씀) — `MemoFolder`/
/// `ImageCategory`와 같은 성격의 단순 룩업 테이블. 자유 텍스트 대신 이 테이블을
/// 두는 이유: "주일예배"를 매번 다르게 타이핑(주일 예배/주일예배)하면 이력
/// 집계·자동완성이 흐트러지므로, 기존 값 자동완성 + 신규 생성 즉시 반영(`Tag`의
/// findOrCreate 패턴과 동일)으로 통일한다.
///
/// 초기 시드값(사용자 확정, 2026-09-28): 주일설교, 청년회 말씀, 구역모임, 조모임
/// 4개를 최초 실행 시 미리 생성해 둔다(시딩 로직은 앱 레이어 책임 — 이 모델
/// 자체는 시드 여부를 모른다). 이후 사용자가 자유롭게 추가/수정 가능.
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

/// 메인 설교문. `UserMemo`/`VerseSummary`와 동일한 `contentHtml`(현재는 RTF
/// 문자열 — `RichTextEditor.swift` 상단 주석 참고, 실제 HTML 아님)+`contentText`
/// (검색·미리보기용) 이원화 패턴을 그대로 따른다.
///
/// ⚠️ 설계 문서 5장에서 확정된 대로, 이 모델은 기존 `RichTextEditor` 컴포넌트가
/// 아니라 문단 프리셋 스타일(`SermonParagraphStyle`)을 지원하는 새 에디터
/// 컴포넌트로 편집된다 — `contentHtml`의 실제 저장 포맷(RTF에 문단 스타일을
/// 어떻게 인코딩할지)은 그 에디터 컴포넌트 구현 단계(2단계, 화면/에디터)에서
/// 확정한다. 이 파일(1단계, 모델)은 저장 포맷 세부사항을 앞서 정하지 않는다.
@Model
public final class Sermon {
    public var id: UUID = UUID()
    public var title: String = ""
    public var contentHtml: String = ""
    public var contentText: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// [2026-09-28 3단계(에디터) 추가] 문단별 `SermonParagraphStyle` 태그를
    /// `contentHtml`(RTF)과 나란히 저장한다.
    ///
    /// ⚠️ 왜 `contentHtml` 안에 같이 넣지 않았는가 — `RichTextEditor.swift` 상단
    /// 주석에서 직접 확인한 사실: `contentHtml`은 2026-08-09부터 실제 RTF
    /// 문자열이고(`NSAttributedString.rtf(from:documentAttributes:)`로 생성),
    /// RTF는 폰트/색상/문단정렬 같은 "표준" 서식만 보존한다 — 이 앱이 새로
    /// 정의하는 커스텀 attribute(`.sermonParagraphStyle`, `SermonParagraphEditor.swift`
    /// 참고)는 RTF 인코딩 과정에서 조용히 사라진다. 그래서 의미적 문단 스타일은
    /// RTF 바깥에 별도 필드로 병행 저장한다.
    ///
    /// 저장 형식 — `SermonParagraphStyleCodec.delimiter`(ASCII Unit Separator,
    /// U+001F)로 이어붙인 `SermonParagraphStyle.rawValue` 시퀀스. `contentText`를
    /// 문단(줄바꿈) 단위로 나눈 것과 1:1 대응하도록 에디터가 매 저장 시 다시
    /// 계산해 넣는다 — 개수가 어긋나는 경우(과거 데이터, 수동 편집 등)는
    /// `SermonParagraphStyleCodec.apply`가 모자란 자리를 `.body`로 채우는
    /// 방어적 처리를 한다(모델 자체는 정합성을 강제하지 않는다).
    public var paragraphStyles: String = ""

    /// [2026-09-29 5번 항목(문단 서식 수동 지정) 추가] 마지막 저장 시점에
    /// 각 `SermonParagraphStyle`이 실제로 어떤 폰트/크기/색이었는지(그 시점의
    /// `UserSettingsStore` 값)를 JSON으로 찍어 둔 스냅샷 —
    /// `SermonParagraphStyleCodec.StyleSnapshot`/`captureSnapshot(settings:)`
    /// 참고.
    ///
    /// ⚠️ 왜 필요한가 — 이 에디터는 문서를 열 때마다 각 문단의 폰트를 "그
    /// 순간의" `UserSettingsStore` 값으로 다시 계산해 덮어쓴다(설계 의도,
    /// `SermonParagraphEditor.swift` 상단 주석 — 나중에 전역 스타일 설정을
    /// 바꾸면 기존 문서에도 소급 반영되게 하기 위함). 그런데 사용자가 에디터
    /// 툴바에서 특정 문단/글자에 수동으로 색상·크기·글꼴·정렬을 지정한 경우
    /// (사용자 확정 — "항상 유지") 그 값은 다음에 열었을 때 이 소급 재계산에
    /// 덮어써지면 안 된다. 문제는 "지금 이 글자의 폰트가 프리셋값을 그대로
    /// 따르는 중인지, 아니면 사용자가 일부러 바꾼 것인지"를 저장된 폰트/색
    /// 값만 보고는 구분할 수 없다는 것 — 그래서 "마지막 저장 시점에 프리셋이
    /// 실제로 어떤 값이었는지"를 별도로 함께 저장해 두고, 다음에 열 때 현재
    /// 값과 비교한다: 저장된 스냅샷과 정확히 같으면("프리셋을 그대로 따르고
    /// 있었다") 새 프리셋값으로 다시 계산하고, 다르면("사용자가 수동으로
    /// 바꿔 뒀다") 그 값을 그대로 보존한다. 문단정렬은 별도 스냅샷이 필요
    /// 없다 — 프리셋 자체가 정렬을 지정하지 않아(항상 `.natural`) "정렬이
    /// natural이 아니면 곧 수동 지정"으로 판단할 수 있기 때문.
    ///
    /// `paragraphStyles`처럼 문서마다 통째로 하나씩만 있고(문단별이 아니라
    /// 스타일 6종별), 커스텀 attribute라 RTF(`contentHtml`)엔 저장되지 않아
    /// 이렇게 별도 필드가 필요하다(`paragraphStyles` 상단 주석과 같은 이유).
    public var styleFontSnapshot: String = ""

    /// `UserMemo.pendingIndexRefresh`와 완전히 같은 이유 — 그 프로퍼티 상단 주석
    /// (`UserContent.swift`) 참고. 검색/관련구절 재인덱싱이 끝나기 전까지 목록에
    /// "인덱스가 최신이 아닐 수 있음" 배지를 보여주는 데 쓴다.
    public var pendingIndexRefresh: Bool = false
    /// `UserMemo.isPinned`와 같은 패턴.
    public var isPinned: Bool = false

    public var sermonTags: [SermonTag]? = []

    // deleteRule은 배열을 가진 이쪽(Sermon)에서만 지정한다 — 위 SermonVerseReference/
    // SermonDelivery 상단 주석의 원칙과 동일.
    @Relationship(deleteRule: .cascade, inverse: \SermonVerseReference.sermon)
    public var verseReferences: [SermonVerseReference]? = []

    /// [2026-09-29 신설] "마인드맵" 기능 — 이 설교의 마인드맵을 이루는 노드
    /// 전체(MindMaps.swift 참고). 메인 설교문(`Sermon`) 단위로만 두고 회차
    /// 사본(`SermonDelivery`)에는 두지 않는다 — 사용자 요청 원문("내 설교
    /// 리스트 항목 밑에... Map 버튼 추가")이 가리키는 자리가 메인 설교문
    /// 목록 행이고, 모임별 활용 이력에 각각 별도 마인드맵을 두라는 요청은
    /// 없었다(필요해지면 그때 SermonVerseReference처럼 sermon/delivery 양쪽을
    /// 갖는 형태로 넓히면 된다 — 지금 미리 만들지 않는다, "근거 없는
    /// 리팩토링 금지" 원칙). 설교가 삭제되면 마인드맵도 함께 사라지는 게
    /// 맞다고 판단해 `.cascade`를 쓴다 — `verseReferences`와 같은 근거
    /// (본문이 없으면 마인드맵도 의미가 없음).
    @Relationship(deleteRule: .cascade, inverse: \MindMapNode.sermon)
    public var mindMapNodes: [MindMapNode]? = []

    /// 이 메인 설교문이 실제로 쓰인 모임별 이력 — 요구사항 1/2의 핵심 관계.
    @Relationship(deleteRule: .cascade, inverse: \SermonDelivery.sermon)
    public var deliveries: [SermonDelivery]? = []

    /// [2026-09-30 신설] 마인드맵 캔버스의 마지막 스크롤 위치·확대율 — 사용자
    /// 요청 "맵을 종료하면 화면 좌표를 기억해서 다시 시작했을 때 마지막
    /// 화면 좌표로 시작할 것(맵마다 상이)." 설교(`Sermon`) 하나에 마인드맵이
    /// 하나씩만 있어(`mindMapNodes` 주석 참고) 이 설교 자체에 저장하는 것이
    /// 가장 자연스럽다. 세 값 모두 Optional로 둬 "저장된 적 없음"(처음
    /// 여는 맵, 또는 이 필드가 생기기 전에 만들어진 기존 설교)을 `0`/`1.0`
    /// 이라는 유효한 값과 구분한다 — `nil`이면 화면(`SermonMindMapView`)은
    /// 대신 루트 노드를 화면 중앙에 오도록 자동으로 맞춘다. ⚠️ 이 세 필드는
    /// 전부 `Double?`(Optional 스칼라)이라 `MindMapNode`의 `borderColor` 등
    /// (enum, `String` rawValue) 크래시와 같은 문제가 재현될 위험이 없다 —
    /// 그 크래시의 실제 원인(SwiftMaps.swift의 "크래시 원인 확정 및 조치"
    /// 주석 참고)은 "새로 추가된 enum 속성이 기존 행에서 라이트웨이트
    /// 마이그레이션으로 채워지지 않아 NULL로 남는" 것이었는데, `Double`
    /// 같은 순수 스칼라 속성은 실제 데이터로 이미 정상 백필됨이 확인됐고,
    /// 게다가 이 세 필드는 애초에 Optional이라 NULL이어도(기존 설교 전부가
    /// 그럴 것이다) 정상적으로 `nil`로 읽힐 뿐 크래시하지 않는다.
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

/// 설교 실행 이력 — "어떤 모임에서 언제" + "그때 실제로 읽은(수정됐을 수 있는)
/// 본문". 생성 시 `Sermon`의 현재 `contentHtml`/`contentText`를 그대로 복사해
/// 시작하고(설계 문서 2.2 S-SER1a "이 설교로 새 모임에서 사용" 흐름), 이후
/// 독립적으로 편집된다(요구사항 2 — "메인 설교문서를 모임마다 기본으로 조금씩
/// 수정"). "메인과 동일한지"는 별도 저장 플래그를 두지 않고, 화면에서 이
/// `contentText`를 `Sermon.contentText`와 비교해 판단한다(저장할 때마다 플래그를
/// 함께 갱신해야 하는 동기화 부담을 피하기 위함 — 설계 문서 2.2 S-SER1a 참고).
@Model
public final class SermonDelivery {
    public var id: UUID = UUID()
    public var deliveredAt: Date = Date.now
    public var contentHtml: String = ""
    public var contentText: String = ""
    /// `Sermon.paragraphStyles`와 완전히 같은 이유·같은 형식(상단 주석 참고) —
    /// 이 회차 사본은 메인과 독립적으로 편집되므로(요구사항 2) 문단 스타일도
    /// 사본마다 별도로 저장한다.
    public var paragraphStyles: String = ""
    /// `Sermon.styleFontSnapshot`과 완전히 같은 이유(그 프로퍼티 상단 주석
    /// 참고) — 이 회차 사본도 메인과 독립적으로 편집되므로(요구사항 2) 스냅샷도
    /// 사본마다 별도로 저장한다.
    public var styleFontSnapshot: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var pendingIndexRefresh: Bool = false

    /// [2026-09-29 신설] 사용자 결정 — "회차마다 독립적인 태그". `Sermon.
    /// sermonTags`와 서로 완전히 독립된 별도 태그 집합 — 이 회차 사본만의
    /// 태그이며 메인 설교문의 태그와 공유하지 않는다(`Tags.swift`의
    /// `SermonDeliveryTag`/`SermonTag` 주석 참고).
    public var deliveryTags: [SermonDeliveryTag]? = []

    // deleteRule은 Sermon.deliveries 쪽(배열을 가진 쪽)에서만 지정한다 — 이
    // 파일 상단 주석의 원칙과 동일. 메인 설교문이 삭제되면 그 활용 이력도
    // 함께 정리되는 게 맞다(사본만 남아 메인 없이 떠도는 상태를 만들지 않음).
    public var sermon: Sermon?

    // deleteRule은 SermonGathering.deliveries 쪽에서 지정(위 SermonGathering
    // 참고, .nullify — 모임 종류가 삭제돼도 그 모임에서 했던 설교 이력 자체는
    // 남아야 하므로 cascade가 아니라 nullify).
    public var gathering: SermonGathering?

    /// 이 회차 사본 본문 안에서 "말씀구절" 스타일로 지정된 성경 좌표.
    /// deleteRule은 배열을 가진 이쪽(SermonDelivery)에서 지정한다 — 위
    /// SermonVerseReference/Sermon 상단 주석의 원칙과 동일.
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
