//
//  SermonSupport.swift
//  JBCHBibleResearch
//
//  [2026-09-28 신설] "내 설교" 기능의 여러 화면이 공유하는 작은 타입들.
//  - `SermonContentTarget`: 설교 작성(S-SER2)/뷰어(S-SER3)가 메인 `Sermon` 또는
//    특정 회차 `SermonDelivery` 중 어느 쪽을 대상으로 열렸는지 구분해 전달하는
//    값 타입 — `DocumentSearchRequest.swift`(연구문서 S6/검색 창 분리)와 같은
//    이유·같은 패턴: `WindowGroup(for:)`가 모델 인스턴스 자체가 아니라
//    Codable/Hashable 값 하나만 받을 수 있어서다. `PersistentIdentifier` 하나만으론
//    "이게 Sermon인지 SermonDelivery인지"를 구분할 수 없어(둘 다 같은 타입) 종류
//    태그를 함께 싣는다.
//  - `SermonComingSoonView`: 설교 작성 에디터/뷰어는 설계 문서가 정한 3·4단계
//    (에디터/뷰어)에서 구현한다 — 이번 라운드(1·2단계: 모델+목록/상세)에서는
//    아직 없어, 그 자리에 임시로 보여주는 안내 화면이다. `PlaceholderScreens.swift`의
//    기존 `ComingSoonView`와 같은 성격이지만 그 타입이 그 파일 안에 `private`로
//    갇혀 있어 재사용할 수 없어, 여기 별도로 작게 하나 더 둔다 — 다음 단계에서
//    실제 에디터/뷰어 화면이 만들어지면, 이 파일의 `SermonComingSoonView`를 그
//    화면으로 바꿔 끼우기만 하면 된다(호출부의 `WindowGroup`/`NavigationLink`
//    배선은 이미 `SermonContentTarget`을 통해 완성돼 있어 그대로 재사용).
//

import Foundation
import SwiftData
import SwiftUI
import BibleResearchModels

/// 설교 작성/뷰어가 열어야 할 대상 — 메인 설교문(`Sermon`) 또는 특정 회차
/// 사본(`SermonDelivery`) 중 하나를 가리킨다.
struct SermonContentTarget: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case sermon
        case delivery
    }

    let kind: Kind
    let id: PersistentIdentifier

    static func sermon(_ sermon: Sermon) -> SermonContentTarget {
        SermonContentTarget(kind: .sermon, id: sermon.persistentModelID)
    }

    static func delivery(_ delivery: SermonDelivery) -> SermonContentTarget {
        SermonContentTarget(kind: .delivery, id: delivery.persistentModelID)
    }
}

/// [2026-09-29 신설, 버그 수정] 사용자 보고 — "(아이패드) 내 설교 - 리스트
/// 항목 클릭 - 메인 설교의 뷰어 버튼 클릭 반응 없음." 지금까지 "sermon-editor"/
/// "sermon-viewer" 두 `WindowGroup(id:for:)`(JBCHBibleResearchApp.swift)이
/// 정확히 같은 값 타입(`SermonContentTarget`)을 공유하고 있었다 — Apple
/// Developer Forums 등에 여러 차례 보고된 알려진 문제로, 같은 Hashable/
/// Codable 타입을 공유하는 WindowGroup이 둘 이상이면 `openWindow(id:value:)`가
/// 요청한 `id`가 아니라 그 타입의 다른(이미 열려 있는) 창을 재사용/혼동하는
/// 사례가 보고돼 있다. 실제로 사용자가 함께 보고한 증상 — 편집 창은 뜨는데
/// (두 번째 보고: 새 창 자체는 열리고, 닫기 버튼만 문제) 뷰어 창만 "반응
/// 없음" — 은 "편집 창이 먼저 열려 있는 상태에서 같은 타입의 뷰어를
/// 요청하면 시스템이 기존 편집 창을 그대로 재사용/포커스만 하고 새로 열지
/// 않는다"는 이 문제와 정확히 들어맞는다. 두 창의 값 타입 자체를 서로 다르게
/// 만들어 이 모호성을 근본적으로 없앤다 — "sermon-editor"는 기존
/// `SermonContentTarget`을 그대로 쓰고, "sermon-viewer"만 내용이 완전히
/// 같은 이 얇은 래퍼 타입을 새로 쓴다(타입만 다르다).
///
/// ⚠️ [Xcode 확인 필요] 이 세션은 Xcode/실기기 테스트를 할 수 없어, 이 원인이
/// 실제 iPadOS 동작과 정확히 일치하는지는 코드 검토만으로 확정할 수 없다 —
/// 다만 타입을 분리하는 것 자체는 이 모호성을 원천적으로 없애는, 부작용 없는
/// 구조적 개선이라 원인이 다르더라도 해가 되지 않는다. 빌드 후 실기기(특히
/// 아이패드)에서 "메인 설교 뷰어" 버튼이 정상 동작하는지 꼭 확인해 주세요.
struct SermonViewerTarget: Codable, Hashable, Sendable {
    let target: SermonContentTarget

    init(_ target: SermonContentTarget) {
        self.target = target
    }

    static func sermon(_ sermon: Sermon) -> SermonViewerTarget {
        SermonViewerTarget(.sermon(sermon))
    }

    static func delivery(_ delivery: SermonDelivery) -> SermonViewerTarget {
        SermonViewerTarget(.delivery(delivery))
    }
}

/// [2026-09-29 신설] "마인드맵" 기능 전용 창 대상. `WindowGroup(id:
/// "sermon-mindmap", for: SermonMindMapTarget.self)`(JBCHBibleResearchApp.swift
/// 참고)에 쓴다.
///
/// ⚠️ 왜 `PersistentIdentifier`를 그냥 쓰지 않고 이 얇은 래퍼를 새로 만드는가
/// — 위 `SermonViewerTarget` 선언부 주석이 이미 밝힌 것과 정확히 같은 이유다:
/// `JBCHBibleResearchApp.swift`에 이미 `WindowGroup(id: "document-viewer", for:
/// PersistentIdentifier.self)`와 `WindowGroup(id: "sermon-detail", for:
/// PersistentIdentifier.self)` 두 개가 그 타입을 쓰고 있어, 세 번째로 같은
/// 타입을 또 쓰면 정확히 그 주석이 설명한 "같은 값 타입을 공유하는
/// WindowGroup이 여럿이면 openWindow가 엉뚱한 창을 재사용/혼동한다"는 문제가
/// 재현될 위험이 있다. 마인드맵은 현재 메인 설교문(`Sermon`) 단위로만 존재해
/// (`Sermon.mindMapNodes`, MindMaps.swift 참고 — 회차 사본엔 없음)
/// `SermonContentTarget`처럼 종류(sermon/delivery)를 구분할 필요가 없어,
/// `SermonViewerTarget`보다 더 단순하게 `PersistentIdentifier` 하나만 감싼다.
struct SermonMindMapTarget: Codable, Hashable, Sendable {
    let sermonID: PersistentIdentifier

    static func sermon(_ sermon: Sermon) -> SermonMindMapTarget {
        SermonMindMapTarget(sermonID: sermon.persistentModelID)
    }
}

/// [2026-09-28 3단계(에디터) 신설] 에디터(`SermonEditorView`)가 실제로 편집할
/// 대상 — `SermonContentTarget`(윈도우/네비게이션 전달용, `PersistentIdentifier`만
/// 담음)과 달리 이건 이미 손에 쥔 살아있는 모델 인스턴스를 담는다. `Sermon`/
/// `SermonDelivery`는 공통 프로토콜이 없는 독립된 `@Model` 클래스라(새 프로토콜을
/// 만들어 두 모델에 끼워맞추는 것보다, 이 프로젝트가 이미 쓰는 "대상 종류를 값
/// 하나로 감싼다" 패턴 — `SermonContentTarget`과 같은 결 — 을 재사용하는 편이
/// 더 근거 있는 선택이라 판단) 이 enum으로 감싼다. 두 모델의 `contentHtml`/
/// `contentText`/`paragraphStyles`/`verseReferences`/`updatedAt` 필드 이름이
/// 이미 동일하므로(설계 문서 3장) 브리징이 기계적이다.
enum SermonEditingSubject {
    case sermon(Sermon)
    case delivery(SermonDelivery)

    var contentHtml: String {
        get {
            switch self {
            case .sermon(let sermon): return sermon.contentHtml
            case .delivery(let delivery): return delivery.contentHtml
            }
        }
        nonmutating set {
            switch self {
            case .sermon(let sermon): sermon.contentHtml = newValue
            case .delivery(let delivery): delivery.contentHtml = newValue
            }
        }
    }

    var contentText: String {
        get {
            switch self {
            case .sermon(let sermon): return sermon.contentText
            case .delivery(let delivery): return delivery.contentText
            }
        }
        nonmutating set {
            switch self {
            case .sermon(let sermon): sermon.contentText = newValue
            case .delivery(let delivery): delivery.contentText = newValue
            }
        }
    }

    var paragraphStyles: String {
        get {
            switch self {
            case .sermon(let sermon): return sermon.paragraphStyles
            case .delivery(let delivery): return delivery.paragraphStyles
            }
        }
        nonmutating set {
            switch self {
            case .sermon(let sermon): sermon.paragraphStyles = newValue
            case .delivery(let delivery): delivery.paragraphStyles = newValue
            }
        }
    }

    /// `Sermon.styleFontSnapshot`/`SermonDelivery.styleFontSnapshot` 브리징 —
    /// 위 `paragraphStyles`와 같은 패턴(그 프로퍼티 상단 주석 참고).
    var styleFontSnapshot: String {
        get {
            switch self {
            case .sermon(let sermon): return sermon.styleFontSnapshot
            case .delivery(let delivery): return delivery.styleFontSnapshot
            }
        }
        nonmutating set {
            switch self {
            case .sermon(let sermon): sermon.styleFontSnapshot = newValue
            case .delivery(let delivery): delivery.styleFontSnapshot = newValue
            }
        }
    }

    /// 새 `SermonVerseReference`를 이 대상(메인 설교문 또는 회차 사본) 쪽에
    /// 붙여 반환한다 — 관계 양쪽(`sermon`/`delivery`)에 동시에 값을 넣지
    /// 않는다는 `SermonVerseReference` 상단 주석의 배타적 불변식을 호출부
    /// (여기)에서 지킨다.
    func makeVerseReference(bookId: Int, chapter: Int, verseStart: Int, verseEnd: Int?, paragraphIndex: Int) -> SermonVerseReference {
        switch self {
        case .sermon(let sermon):
            return SermonVerseReference(
                bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd,
                paragraphIndex: paragraphIndex, sermon: sermon
            )
        case .delivery(let delivery):
            return SermonVerseReference(
                bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd,
                paragraphIndex: paragraphIndex, delivery: delivery
            )
        }
    }

    func touchUpdatedAt() {
        switch self {
        case .sermon(let sermon): sermon.updatedAt = .now
        case .delivery(let delivery): delivery.updatedAt = .now
        }
    }

    /// `.delivery`일 때만 "참조한 메인 설교" 배너(설계 문서 요구사항 6)가 가리킬
    /// 메인 `Sermon` — `.sermon`(메인 자체를 여는 경우)은 참조할 "더 상위의
    /// 메인"이 없으므로 nil.
    var parentSermon: Sermon? {
        switch self {
        case .sermon: return nil
        case .delivery(let delivery): return delivery.sermon
        }
    }

    var gathering: SermonGathering? {
        switch self {
        case .sermon: return nil
        case .delivery(let delivery): return delivery.gathering
        }
    }

    var deliveredAt: Date? {
        switch self {
        case .sermon: return nil
        case .delivery(let delivery): return delivery.deliveredAt
        }
    }

    // MARK: - 태그 (요구사항 — "태그 입력은 메인 설교문, 모임에 따른 설교문
    // 하단에 추가할 수 있도록 할 것", 2026-09-29)
    //
    // `.sermon`은 기존 `Sermon.sermonTags`를, `.delivery`는 새로 추가한
    // `SermonDelivery.deliveryTags`를 가리킨다 — 사용자 결정("회차마다
    // 독립적인 태그")대로 두 태그 집합은 서로 완전히 독립적이다(`Tags.swift`의
    // `SermonTag`/`SermonDeliveryTag` 주석 참고). `SermonDetailView.tagSection`이
    // 이미 쓰는 "병합된 태그는 걸러낸다"(`!$0.isMerged`) 관례를 그대로 따른다.

    var tags: [Tag] {
        switch self {
        case .sermon(let sermon):
            return (sermon.sermonTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        case .delivery(let delivery):
            return (delivery.deliveryTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        }
    }

    /// 새 태그 조인을 만들어 이 대상에 붙인다. 호출부가 `modelContext.save()`를
    /// 책임진다(`SermonDetailView.addTag`와 같은 관례).
    func addTagJoin(_ tag: Tag, context: ModelContext) {
        switch self {
        case .sermon(let sermon):
            context.insert(SermonTag(sermon: sermon, tag: tag))
        case .delivery(let delivery):
            context.insert(SermonDeliveryTag(delivery: delivery, tag: tag))
        }
    }

    /// 이 대상에 붙은 태그 조인 중 `tag`를 가리키는 것을 찾아 지운다.
    func removeTagJoin(for tag: Tag, context: ModelContext) {
        switch self {
        case .sermon(let sermon):
            if let join = (sermon.sermonTags ?? []).first(where: { $0.tag?.id == tag.id }) {
                context.delete(join)
            }
        case .delivery(let delivery):
            if let join = (delivery.deliveryTags ?? []).first(where: { $0.tag?.id == tag.id }) {
                context.delete(join)
            }
        }
    }
}

/// ⚠️ [임시, 4단계(뷰어)에서 교체 예정] 설계 문서 참고. 에디터(`.editor`)는
/// 3단계에서 `SermonEditorView`로 교체됐다 — 이 타입은 이제 `.viewer` 모드
/// 에서만 실제로 쓰인다(뷰어는 아직 4단계 전이라 안내만 보여줌).
struct SermonComingSoonView: View {
    enum Mode {
        case editor
        case viewer

        var title: String {
            switch self {
            case .editor: return "설교 작성"
            case .viewer: return "설교 뷰어"
            }
        }

        var systemImage: String {
            switch self {
            case .editor: return "square.and.pencil"
            case .viewer: return "text.book.closed"
            }
        }
    }

    let mode: Mode
    let target: SermonContentTarget

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(mode.title)
                .font(.title3)
            Text("다음 업데이트에서 제공됩니다")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(mode.title)
    }
}

/// `WindowGroup(id: "sermon-editor", for: SermonContentTarget.self)`/
/// `WindowGroup(id: "sermon-viewer", for: SermonViewerTarget.self)`(2026-09-29부터
/// 서로 다른 타입 — 위 `SermonViewerTarget` 선언부 주석 참고)
/// (JBCHBibleResearchApp.swift 참고) 전용 창 콘텐츠. `DocumentViewerWindowContent`
/// (Views/Documents/DocumentViewerView.swift)와 같은 이유로 `@Query`를 써서
/// 대상이 창이 떠 있는 동안 삭제돼도 죽은 참조를 읽어 크래시하지 않고 "찾을 수
/// 없음" 메시지로 자연스럽게 넘어가게 한다.
struct SermonContentWindowContent: View {
    @Query private var sermons: [Sermon]
    @Query private var deliveries: [SermonDelivery]
    let mode: SermonComingSoonView.Mode
    let target: SermonContentTarget?
    /// [2026-09-29 신설, 버그 수정] 사용자 보고 — "(아이패드) 모임 설교의
    /// 편집 버튼 클릭후 새창 - 닫기 버튼 없음." 원인: 아래 `contentView(for:
    /// target:)`가 `SermonEditorView`/`SermonViewerView`를 만들 때 지금까지
    /// `onRequestClose`(전자)/`onRequestClose`(후자, 이번에 신설)를 아예
    /// 넘기지 않았다 — 두 화면 모두 "이 화면이 진짜 `WindowGroup` 창 안에서
    /// 열렸을 때는 `@Environment(\.dismiss)`가 기댈 프레젠테이션이 없어 아무
    /// 효과가 없다"(`SermonEditorView.onRequestClose` 선언부 주석, `SermonViewerView.swift`
    /// 상단 "[Xcode 확인 필요] 3번" 주석이 이미 이 우려를 미리 적어 뒀었다)는
    /// 같은 구조적 제약을 갖고 있는데, 정작 "진짜 창"으로 여는 이 타입
    /// (`WindowGroup(id: "sermon-editor"/"sermon-viewer", ...)`의 콘텐츠)이
    /// 그 닫기 클로저를 연결해 주지 않았다. `dismissWindow()`(인자 없음 — 이
    /// 환경 값이 속한 창을 닫는다, `DocumentViewerView`가 이미 쓰는 것과 같은
    /// API)를 호출하는 클로저를 넘겨 실제로 닫히게 한다.
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if let target {
            switch target.kind {
            case .sermon:
                if let sermon = sermons.first(where: { $0.persistentModelID == target.id }) {
                    contentView(for: .sermon(sermon), target: target)
                } else {
                    sermonNotFoundMessage()
                }
            case .delivery:
                if let delivery = deliveries.first(where: { $0.persistentModelID == target.id }) {
                    contentView(for: .delivery(delivery), target: target)
                } else {
                    sermonNotFoundMessage()
                }
            }
        } else {
            sermonNotFoundMessage()
        }
    }

    /// [2026-09-28 4단계(뷰어) 갱신] `mode`가 `.editor`면 에디터
    /// (`SermonEditorView`)를, `.viewer`면 뷰어(`SermonViewerView`, 4단계
    /// 완료)를 보여준다 — 둘 다 같은 `subject`(살아있는 모델 인스턴스)를
    /// 그대로 넘긴다.
    @ViewBuilder
    private func contentView(for subject: SermonEditingSubject, target: SermonContentTarget) -> some View {
        switch mode {
        case .editor:
            SermonEditorView(subject: subject, onRequestClose: { dismissWindow() })
        case .viewer:
            SermonViewerView(subject: subject, onRequestClose: { dismissWindow() })
        }
    }

    private func sermonNotFoundMessage() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("설교를 찾을 수 없습니다")
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 디자인 토큰 (2026-09-28 목업 정합화, 2026-09-29 테마색상 반영)
//
// [2026-09-28 신설] 사용자 지적 — "디자인이 목업 html과 너무 차이가 큼."
// 설계 문서에 첨부된 HTML 목업(Claude 아티팩트 "내 설교 관리 화면 목업",
// `Main/Detail/Editor/Viewer.dc.html` 등)과 실제 구현(1~4단계에서는 색·카드
// 스타일 없이 시스템 기본 `List`/`Menu`만 썼다)의 시각적 차이를 좁힌다.
//
// ⚠️ [2026-09-29 번복] 아래 두 문단은 원래 "내 설교는 설정 테마색상 적용
// 대상에서 뺀다"고 확정했던 결정이었다. 사용자가 이번에 명시적으로 "설정-
// 테마색상에 따른 디자인 색상 변화 필요"를 요청해 그 결정을 뒤집는다 —
// `DocumentsHomeView`/`BibleReadingView`/`WordNoteHomeView`/`SearchView`와
// 똑같이 `UserSettingsStore.bibleBackgroundColor`/`bibleTextColor`를 배경·
// 글자색에 적용한다(각 화면의 `.background(settings.bibleBackgroundColor ??
// Color.clear)` / `.foregroundStyle(settings.bibleTextColor ?? .primary)`
// 관례를 그대로 따름 — 새 패턴을 만들지 않는다).
//
// ⚠️ [액센트 색 자체는 여전히 새로 고르지 않음] 목업의 액센트(--accent:#7A3B42,
// 와인 적갈)는 이미 `JBCHCategoryPalette.wine`/`.wineOnDark`로 정확히 같은
// hex가 정의돼 있다 — 새 팔레트를 만들지 않고 그대로 재사용한다. 다만 라이트/
// 다크 "어느 쪽을 쓸지" 판정은 더 이상 시스템 `colorScheme`만 보지 않는다 —
// 사용자가 테마색상에서 명시적 배경색을 골랐다면(`bibleBackgroundColor != nil`)
// 시스템 다크모드 여부와 그 배경이 실제로 어둡게 보이는지가 어긋날 수 있어
// (예: 시스템은 라이트인데 사용자가 "밤빛 서재"처럼 어두운 배경색을 고른
// 경우), `DocumentsHomeView.accentSpineColor`가 이미 쓰는 것과 완전히 같은
// WCAG 상대휘도 공식으로 "지금 실제로 보이는 배경이 어두운지"를 판정한다
// (그 프로퍼티는 `private`라 재사용하지 못해 같은 공식만 옮겨 왔다 — 그 파일
// 주석이 이미 밝힌 관례). 성공/경고 배지 톤도 `DocumentsHomeView`가 이미 쓰는
// statusGreen(#5E8C5B)/statusAmber(#B36A2E)와 정확히 같은 hex를 그대로
// 옮겨, 앱 전체에서 "성공=초록/경고=주황"의 채도가 화면마다 어긋나지 않게
// 한다(그 파일은 이 값들을 `private`로 갖고 있어 직접 참조할 수 없어 값만
// 옮겨 왔다 — 같은 이유로 이 파일도 각 화면이 필요하면 참조할 수 있게 공개
// 상수로 둔다).
enum SermonTheme {
    /// 라이트 모드 액센트 — `JBCHCategoryPalette.wine`과 동일(#7A3B42).
    static var accent: Color { JBCHCategoryPalette.wine }
    /// 다크 모드 액센트 — `JBCHCategoryPalette.wineOnDark`와 동일(#AF898E,
    /// 흰색과 40% 섞어 어두운 배경 대비 4.85:1을 이미 확인해 둔 값).
    static var accentOnDark: Color { JBCHCategoryPalette.wineOnDark }

    /// [2026-09-28] 시스템 `colorScheme`만으로 고르는 판(테마색상 미반영
    /// 시절의 옛 시그니처) — 테마색상을 반영한 화면은 대신 아래
    /// `accent(background:environment:fallbackScheme:)`를 쓴다. 다른 호출부가
    /// 아직 있을 수 있어 그대로 남겨 둔다(제거는 별도 확인 없이 하지 않음).
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accentOnDark : accent
    }

    /// [2026-09-29 신설] 테마색상을 반영한 화면(`SermonHomeView`/
    /// `SermonDetailView`/`SermonEditorView`)이 쓰는 판 — `background`가
    /// 있으면(사용자가 성경 조회 테마에서 명시적 배경색을 골랐으면) 그 배경의
    /// WCAG 상대휘도로, 없으면(시스템 기본) `fallbackScheme`으로 판정한다.
    /// `DocumentsHomeView.accentSpineColor`와 완전히 같은 공식(그 파일 1698~
    /// 1707행) — 새 공식을 만들지 않고 그대로 옮겨 왔다.
    static func accent(background: Color?, environment: EnvironmentValues, fallbackScheme: ColorScheme) -> Color {
        let isDark: Bool
        if let background {
            let resolved = background.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            isDark = luminance < 0.5
        } else {
            isDark = fallbackScheme == .dark
        }
        return isDark ? accentOnDark : accent
    }

    /// `DocumentsHomeView.statusGreen`과 동일 hex — 새로 고르지 않음.
    static let success = Color(hex: "#5E8C5B") ?? .green
    /// `DocumentsHomeView.statusAmber`와 동일 hex — 새로 고르지 않음.
    static let warning = Color(hex: "#B36A2E") ?? .orange

    /// 카드 채움 — `DocumentsHomeView`의 문서함 카드/선택 강조와 동일한
    /// "옅은 `Color.secondary` 불투명도" 관례(그 파일 630~660행 참고). 별도
    /// 하드코딩 hex가 아니라 시스템 색 기반이라 라이트/다크 모두 자동 대응.
    static let cardFill = Color.secondary.opacity(0.06)
    static let cardCornerRadius: CGFloat = 14
    static let pillCornerRadius: CGFloat = 10
}

/// 목업의 태그/상태 배지 — Capsule + 옅은 배경(`color.opacity(0.15)`).
/// `DocumentsHomeView.badge(_:color:)`와 정확히 같은 모양(그 파일 참고,
/// 새 모양을 만들지 않고 그대로 재사용).
struct SermonBadge: View {
    let text: String
    var color: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

/// 목업의 "필 버튼"(둥근 사각형, 채워짐/은은함 두 톤) — 상세/에디터/뷰어가
/// 함께 쓴다. 표준 `ButtonStyle` 확장점이라 새 컴포넌트 체계를 만드는 게
/// 아니라 SwiftUI가 이미 제공하는 지점을 쓰는 것뿐이다.
struct SermonPillButtonStyle: ButtonStyle {
    var isFilled: Bool
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(isFilled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary.opacity(0.12)))
            .foregroundStyle(isFilled ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: SermonTheme.pillCornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// [2026-09-29 이전, 원래 `SermonDetailView.swift`에 `private`로 있던 타입]
/// 사용자 지적 — "내 설교 - 왼쪽 영역으로 '본문편집'버튼, '뷰어로 보기' 이동"
/// 으로 `SermonHomeView.sermonSidebar`도 이 스타일을 써야 하게 돼, 두 파일이
/// 공유할 수 있도록 이 파일(`SermonSupport.swift`, "내 설교" 화면들의 공유
/// 타입 모음)로 옮겼다 — `SermonPillButtonStyle`의 작은 판(카드 한 줄에
/// 여러 개가 나란히 있는 자리용, 큰 판처럼 `frame(maxWidth: .infinity)`로
/// 꽉 채우지 않고 내용 폭만 차지). `SermonDetailView.deliveryEditorLink`/
/// `deliveryViewerLink`, `SermonHomeView.sermonSidebar` 행의 "편집"/"뷰어"
/// 버튼이 함께 쓴다.
struct SermonMiniPillButtonStyle: ButtonStyle {
    var isFilled: Bool
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isFilled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary.opacity(0.12)))
            .foregroundStyle(isFilled ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 목업이 "말씀 단위 묶음/날짜별"(Main.dc.html), "스크롤/페이지"(Viewer.dc.html)
/// 양쪽에서 똑같이 쓰는 "둥근 알약 안에 선택 세그먼트가 채워지는" 토글 —
/// 두 화면이 같은 모양을 공유하므로 제네릭 뷰 하나로 둔다(중복 정의 방지).
struct SermonSegmentedPill<Tag: Hashable>: View {
    struct Item {
        let tag: Tag
        let label: String
        var systemImage: String? = nil
    }

    let items: [Item]
    @Binding var selection: Tag
    var accent: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.tag) { item in
                Button {
                    selection = item.tag
                } label: {
                    HStack(spacing: 5) {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage)
                        }
                        Text(item.label)
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(selection == item.tag ? accent : Color.clear)
                    .foregroundStyle(selection == item.tag ? Color.white : Color.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

