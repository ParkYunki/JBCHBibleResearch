//
//  SermonSupport.swift
//  JBCHBibleResearch
//
//  "내 설교" 화면들이 공유하는 작은 타입 모음.
//  - `SermonContentTarget`: 설교 작성/뷰어가 메인 `Sermon`과 회차 `SermonDelivery` 중
//    어느 쪽을 열었는지 구분하는 값 타입. `WindowGroup(for:)`는 Codable/Hashable 값 하나만
//    받고, `PersistentIdentifier`만으로는 두 모델을 구분할 수 없어 종류 태그를 함께 싣는다.
//  - `SermonComingSoonView`: 뷰어 모드용 임시 안내 화면.
//  - `SermonTheme` 등: 내 설교 화면 공통 디자인 토큰과 버튼/배지/토글 스타일.
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

/// 뷰어 창 전용 값 타입 — `SermonContentTarget`을 감싼 얇은 래퍼(내용은 동일).
/// 같은 Hashable/Codable 타입을 공유하는 `WindowGroup`이 둘 이상이면 `openWindow(id:value:)`가
/// 요청한 `id`가 아니라 이미 열린 다른 창을 재사용/혼동하는 사례가 있어, "sermon-editor"는
/// `SermonContentTarget`, "sermon-viewer"는 이 타입을 써서 모호성을 없앤다.
///
/// ⚠️ 이 원인이 실제 iPadOS 동작과 일치하는지는 확정되지 않았다. 타입 분리는 부작용 없는
/// 구조적 개선이다.
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

/// 마인드맵 전용 창 대상(`WindowGroup(id: "sermon-mindmap", for: SermonMindMapTarget.self)`).
///
/// `PersistentIdentifier`를 직접 쓰지 않고 감싸는 이유는 `SermonViewerTarget`과 같다 —
/// "document-viewer"/"sermon-detail" 창이 이미 그 타입을 쓰고 있어 공유하면 창이
/// 혼동될 수 있다. 마인드맵은 메인 설교문(`Sermon`)에만 있어 종류 구분이 필요 없다.
struct SermonMindMapTarget: Codable, Hashable, Sendable {
    let sermonID: PersistentIdentifier

    static func sermon(_ sermon: Sermon) -> SermonMindMapTarget {
        SermonMindMapTarget(sermonID: sermon.persistentModelID)
    }
}

/// 에디터(`SermonEditorView`)가 실제로 편집할 대상 — `SermonContentTarget`(창/네비게이션
/// 전달용 식별자)과 달리 살아있는 모델 인스턴스를 담는다. `Sermon`/`SermonDelivery`에는
/// 공통 프로토콜이 없어 enum으로 감싸며, 두 모델의 `contentHtml`/`contentText`/
/// `paragraphStyles`/`verseReferences`/`updatedAt` 필드 이름이 같아 브리징은 기계적이다.
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

    /// `Sermon.styleFontSnapshot`/`SermonDelivery.styleFontSnapshot` 브리징.
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

    /// 새 `SermonVerseReference`를 이 대상 쪽에만 붙여 반환한다 — 관계 양쪽(`sermon`/`delivery`)에
    /// 동시에 값을 넣지 않는다는 `SermonVerseReference`의 배타적 불변식을 여기서 지킨다.
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

    /// `.delivery`일 때만 "참조한 메인 설교" 배너가 가리킬 메인 `Sermon` — `.sermon`은 nil.
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
    // `.sermon`은 `Sermon.sermonTags`, `.delivery`는 `SermonDelivery.deliveryTags`를 가리키며
    // 두 태그 집합은 서로 독립적이다(회차마다 별도). 병합된 태그(`isMerged`)는 걸러낸다.

    var tags: [Tag] {
        switch self {
        case .sermon(let sermon):
            return (sermon.sermonTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        case .delivery(let delivery):
            return (delivery.deliveryTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        }
    }

    /// 새 태그 조인을 만들어 이 대상에 붙인다. `modelContext.save()`는 호출부 책임.
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

/// ⚠️ 임시 안내 화면 — 에디터는 `SermonEditorView`로 교체됐고, 현재 `.viewer` 모드에서만 쓰인다.
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

/// "sermon-editor"(`SermonContentTarget`)/"sermon-viewer"(`SermonViewerTarget`) 창의 콘텐츠.
/// `DocumentViewerWindowContent`와 같은 이유로 `@Query`를 써서, 창이 떠 있는 동안 대상이
/// 삭제돼도 죽은 참조를 읽지 않고 "찾을 수 없음" 메시지로 넘어가게 한다.
struct SermonContentWindowContent: View {
    @Query private var sermons: [Sermon]
    @Query private var deliveries: [SermonDelivery]
    let mode: SermonComingSoonView.Mode
    let target: SermonContentTarget?
    /// 진짜 `WindowGroup` 창에서는 `@Environment(\.dismiss)`가 기댈 프레젠테이션이 없어
    /// 아무 효과가 없으므로, `onRequestClose`에 `dismissWindow()`를 연결해 창을 닫는다.
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

    /// `mode`에 따라 에디터(`SermonEditorView`) 또는 뷰어(`SermonViewerView`)를 보여준다 —
    /// 둘 다 같은 `subject`를 넘긴다.
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
// 목업(HTML)의 색·카드 스타일에 맞춘 토큰이며, 배경·글자색은 다른 화면과 같이
// `UserSettingsStore.bibleBackgroundColor`/`bibleTextColor`(설정 테마색상)를 따른다.
//
// 액센트는 목업의 #7A3B42가 이미 `JBCHCategoryPalette.wine`/`.wineOnDark`로 정의돼 있어
// 새로 만들지 않고 재사용한다. 라이트/다크 판정은 시스템 `colorScheme`이 아니라, 사용자가
// 명시적 배경색을 골랐다면 그 배경의 WCAG 상대휘도로 한다(시스템은 라이트인데 어두운 배경을
// 고른 경우를 위해; `DocumentsHomeView.accentSpineColor`와 같은 공식). 성공/경고 배지 색도
// `DocumentsHomeView`의 statusGreen/statusAmber와 같은 hex를 써서 화면 간 채도를 맞춘다.
enum SermonTheme {
    /// 라이트 모드 액센트 — `JBCHCategoryPalette.wine`(#7A3B42).
    static var accent: Color { JBCHCategoryPalette.wine }
    /// 다크 모드 액센트 — `JBCHCategoryPalette.wineOnDark`(#AF898E, 어두운 배경 대비 4.85:1).
    static var accentOnDark: Color { JBCHCategoryPalette.wineOnDark }

    /// 시스템 `colorScheme`만으로 고르는 판(테마색상 미반영). 테마색상을 반영하는 화면은
    /// 아래 `accent(background:environment:fallbackScheme:)`를 쓴다.
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accentOnDark : accent
    }

    /// 테마색상을 반영한 판 — `background`가 있으면 그 배경의 WCAG 상대휘도로, 없으면
    /// `fallbackScheme`으로 라이트/다크를 판정한다.
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

    /// `DocumentsHomeView.statusGreen`과 동일 hex.
    static let success = Color(hex: "#5E8C5B") ?? .green
    /// `DocumentsHomeView.statusAmber`와 동일 hex.
    static let warning = Color(hex: "#B36A2E") ?? .orange

    /// 카드 채움 — 옅은 `Color.secondary` 불투명도라 라이트/다크 모두 자동 대응한다.
    static let cardFill = Color.secondary.opacity(0.06)
    static let cardCornerRadius: CGFloat = 14
    static let pillCornerRadius: CGFloat = 10
}

/// 목업의 태그/상태 배지 — Capsule + 옅은 배경(`DocumentsHomeView.badge(_:color:)`와 같은 모양).
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

/// 목업의 "필 버튼"(둥근 사각형, 채워짐/은은함 두 톤) — 상세/에디터/뷰어가 함께 쓴다.
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

/// `SermonPillButtonStyle`의 작은 판 — 내용 폭만 차지해 한 줄에 여러 개를 나란히 둘 수 있다.
/// `SermonDetailView`와 `SermonHomeView.sermonSidebar`가 공유하려고 이 파일에 둔다.
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

/// "말씀 단위 묶음/날짜별", "스크롤/페이지" 토글처럼 선택 세그먼트가 채워지는 알약 토글 —
/// 두 화면이 같은 모양을 공유하므로 제네릭 뷰 하나로 둔다.
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

