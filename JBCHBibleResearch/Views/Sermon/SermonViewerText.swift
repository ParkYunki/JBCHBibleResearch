//
//  SermonViewerText.swift
//  JBCHBibleResearch
//
//  설교 뷰어의 본문 렌더링 계층 — 편집기(`SermonParagraphEditor`)와 같은 데이터 경로(저장된 RTF →
//  `RichTextCodec.decode` → `SermonParagraphStyleCodec.apply`)로 만든 `NSAttributedString`을 TextKit으로
//  그대로 그린다. 그래서 굵게/기울임/색/문단 여백까지 편집 화면과 똑같이 보인다.
//
//  예전 뷰어는 문단마다 SwiftUI `Text`를 만들고, 페이지 모드에서는 같은 문단을 화면 밖에서 한 번 더 그려
//  높이를 재는 방식이었다. 문서 전체가 메인 스레드에서 한꺼번에 레이아웃되고 상태가 바뀔 때마다 다시
//  계산돼 긴 설교에서 화면이 오래 멈췄다. TextKit은 텍스트를 그릴 때만 필요한 만큼 레이아웃하고,
//  페이지 나누기도 글자 흐름(`NSLayoutManager`의 여러 `NSTextContainer`)으로 한 번에 처리한다.
//
//  구성:
//  - `SermonViewerDocument`: 저장된 본문 → 편집기와 같은 서식의 `NSAttributedString`(글꼴 배율 적용).
//  - `SermonViewerPaginator`: 그 문서를 페이지 크기의 컨테이너 여러 개로 나눠 페이지 수/위치를 안다.
//  - `SermonViewerScrollText`: 세로 스크롤 읽기 전용 텍스트뷰(iOS `UITextView`, macOS `NSTextView`).
//  - iOS `SermonViewerPageCurl`: `UIPageViewController` 페이지 컬(도서 앱과 같은 넘김 효과).
//  - macOS `SermonViewerSinglePage`: 현재 페이지 하나를 그리는 `NSTextView`.
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 뷰어 고정 배경(종이색)

/// 설교 뷰어의 고정 배경 — 설정의 테마 배경색이나 다크 모드와 무관하게 항상 같은 부드러운 미색(#F6F2E9)이다.
/// 배경이 고정 밝은색이라 글자 기본색(레이블 색)도 항상 어둡게 풀리도록 뷰어의 텍스트뷰는 라이트 외형으로 고정한다
/// (iOS `overrideUserInterfaceStyle = .light`, macOS `appearance = .aqua`). 문단 스타일에 저장된 hex 글자색은 그대로 쓴다.
enum SermonViewerPaper {
    private static let red = 246.0 / 255.0
    private static let green = 242.0 / 255.0
    private static let blue = 233.0 / 255.0

    static let platformColor = PlatformColor(red: red, green: green, blue: blue, alpha: 1)
    static let color = Color(red: red, green: green, blue: blue)
}

// MARK: - 문서 만들기

@MainActor
enum SermonViewerDocument {
    /// 편집기(`SermonParagraphEditorRepresentable.loadContent`)와 같은 순서로 본문을 만든다.
    /// 저장된 RTF를 읽고, 문단별 스타일을 현재 설정값으로 다시 입힌 뒤, 뷰어의 글꼴 배율을 곱한다.
    static func build(subject: SermonEditingSubject, settings: UserSettingsStore, scale: Double) -> NSAttributedString {
        let defaultAttributes: [NSAttributedString.Key: Any] = [.font: settings.sermonPlatformFont(for: .body)]
        let decoded = RichTextCodec.decode(subject.contentHtml, defaultAttributes: defaultAttributes)
        let storage = NSTextStorage(attributedString: decoded)
        SermonParagraphStyleCodec.apply(
            subject.paragraphStyles, to: storage, settings: settings, previousSnapshot: subject.styleFontSnapshot
        )
        return scaled(storage, by: CGFloat(scale))
    }

    /// 글자 크기와 줄/문단 간격·들여쓰기에 같은 배율을 곱한다(본문 첫 줄 1글자 들여쓰기가 글자 크기를 따라가도록). 원본을 순회하면서
    /// 사본에 쓰므로 순회 중 변경이 없다. 말씀구절 박스 안여백은 글자 크기에 비례해 그려지므로 따로 곱하지 않는다.
    private static func scaled(_ attributed: NSAttributedString, by factor: CGFloat) -> NSAttributedString {
        guard attributed.length > 0, abs(factor - 1) > 0.001 else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: attributed.length)

        attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let font = value as? PlatformFont else { return }
            let newSize = max(1, font.pointSize * factor)
            #if os(iOS)
            result.addAttribute(.font, value: font.withSize(newSize), range: range)
            #elseif os(macOS)
            result.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: newSize) ?? font, range: range)
            #endif
        }
        attributed.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            guard let style = value as? NSParagraphStyle,
                  let copy = style.mutableCopy() as? NSMutableParagraphStyle else { return }
            copy.lineSpacing *= factor
            copy.paragraphSpacing *= factor
            copy.paragraphSpacingBefore *= factor
            copy.headIndent *= factor
            copy.firstLineHeadIndent *= factor
            copy.tailIndent *= factor
            result.addAttribute(.paragraphStyle, value: copy, range: range)
        }
        return result
    }
}

// MARK: - 페이지 나누기

/// 문서를 같은 크기의 페이지(텍스트 컨테이너) 여러 개로 나눈다. 글자는 컨테이너를 차례로 채우며 흘러가므로
/// 한 문단이 페이지보다 길어도 잘리지 않고 다음 페이지로 이어진다.
///
/// `NSTextStorage`/`NSLayoutManager`는 스레드 안전하지 않아 메인 스레드에서만 다룬다. 설교 한 편(수만 자)의
/// 레이아웃은 수십 ms 수준이라 백그라운드로 옮기지 않는다.
@MainActor
final class SermonViewerPaginator {
    /// 페이지 수 상한 — 비정상 입력(높이가 거의 0인 컨테이너 등)에서 무한히 컨테이너를 만들지 않게 하는 안전장치.
    private static let maxPages = 3000

    /// 페이지 텍스트뷰를 컨테이너(글자 영역)보다 위·아래로 이만큼 키운다 — 첫 줄 위/마지막 줄 아래로 삐져나오는
    /// 말씀구절 박스의 안여백이 텍스트뷰 경계에서 잘리지 않게 하는 그리기 여유 공간이다(글자 위치는 그대로).
    static let drawBleed: CGFloat = 40

    let containerSize: CGSize
    private let storage: NSTextStorage
    /// 에디터·스크롤 뷰어와 같은 레이아웃 매니저 — 말씀구절 박스/세로 바와 글자 배경을 같은 코드로 그린다(`SermonTextLayout.swift`).
    private let layoutManager = SermonLayoutManager()
    private(set) var containers: [NSTextContainer] = []

    var pageCount: Int { max(containers.count, 1) }

    init(attributed: NSAttributedString, containerSize: CGSize) {
        self.containerSize = containerSize
        self.storage = NSTextStorage(attributedString: attributed)
        storage.addLayoutManager(layoutManager)
        paginate()
    }

    private func makeContainer() -> NSTextContainer {
        let container = NSTextContainer(size: containerSize)
        // 텍스트뷰가 컨테이너 크기를 마음대로 바꾸지 못하게 하고, 좌우 여백은 페이지 뷰 쪽 inset으로만 준다.
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        containers.append(container)
        return container
    }

    private func paginate() {
        guard storage.length > 0, containerSize.width > 1, containerSize.height > 1 else {
            _ = makeContainer()
            return
        }
        while containers.count < Self.maxPages {
            let container = makeContainer()
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            // 이 컨테이너에 마지막 글리프까지 들어갔으면 끝. 한 글리프도 못 넣었다면(한 줄이 페이지보다 큼)
            // 더 만들어도 같은 결과라 멈춘다.
            if NSMaxRange(glyphRange) >= layoutManager.numberOfGlyphs || glyphRange.length == 0 { break }
        }
    }

    /// 페이지의 첫 글자 위치 — 글꼴 배율/화면 크기가 바뀌어 페이지를 다시 나눌 때 "읽던 자리"를 기억하는 데 쓴다.
    func characterLocation(ofPage index: Int) -> Int {
        guard containers.indices.contains(index) else { return 0 }
        let glyphRange = layoutManager.glyphRange(for: containers[index])
        guard glyphRange.length > 0 else { return 0 }
        return layoutManager.characterIndexForGlyph(at: glyphRange.location)
    }

    /// 주어진 글자 위치가 들어 있는 페이지.
    func pageIndex(containingCharacter location: Int) -> Int {
        for (index, container) in containers.enumerated() {
            let glyphRange = layoutManager.glyphRange(for: container)
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if location < NSMaxRange(characterRange) { return index }
        }
        return max(containers.count - 1, 0)
    }
}

// MARK: - 입력 공통 정의 (탭 영역 / 명령)

/// 뷰어 화면을 가로 위치로 나눈 클릭(탭) 영역 — 왼쪽 22% 이전 쪽, 오른쪽 22% 다음 쪽, 가운데는 상·하단 바 숨김/표시.
/// 스크롤 모드에서는 가운데만 쓰고 양 가장자리는 아무 동작도 하지 않는다.
enum SermonViewerTapZone {
    case previous, center, next

    /// 가장자리 영역 폭(뷰 폭 대비).
    static let edgeFraction: CGFloat = 0.22

    init(horizontalFraction x: CGFloat) {
        if x < Self.edgeFraction {
            self = .previous
        } else if x > 1 - Self.edgeFraction {
            self = .next
        } else {
            self = .center
        }
    }
}

/// AppKit/UIKit 쪽 입력(클릭·키보드·쓸기)이 SwiftUI 뷰어로 올려보내는 명령.
enum SermonViewerCommand {
    case previousPage, nextPage, firstPage, lastPage, toggleChrome

    init(zone: SermonViewerTapZone) {
        switch zone {
        case .previous: self = .previousPage
        case .next: self = .nextPage
        case .center: self = .toggleChrome
        }
    }
}

// MARK: - 세로 스크롤 읽기 전용 텍스트

#if os(iOS)

struct SermonViewerScrollText: UIViewRepresentable {
    let attributed: NSAttributedString
    /// 본문이 새로 만들어질 때마다 바뀌는 값 — 같은 값이면 텍스트를 다시 넣지 않아 스크롤 위치가 유지된다.
    let generation: Int
    /// 글자 영역 좌우 여백.
    let horizontalInset: CGFloat
    /// 글자 영역 위 여백 — 상단 바가 본문 위에 겹쳐 뜨므로 첫 줄이 바 아래에서 시작하도록 확보한다.
    let topInset: CGFloat
    /// 본문 가운데를 한 번 탭했을 때(상·하단 바 숨김/표시).
    let onToggleChrome: () -> Void

    private var insets: UIEdgeInsets {
        UIEdgeInsets(top: topInset, left: horizontalInset, bottom: 48, right: horizontalInset)
    }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1 + `SermonLayoutManager` — 에디터·페이지 뷰어와 같은 코드로 말씀구절 박스/세로 바·글자 배경을 그린다.
        let textView = SermonTextKit1.makeTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = insets
        // 뷰어 고정 종이색 + 라이트 외형(`SermonViewerPaper` 참고).
        textView.overrideUserInterfaceStyle = .light
        textView.backgroundColor = SermonViewerPaper.platformColor
        textView.textStorage.setAttributedString(attributed)
        // 탭은 텍스트뷰의 선택 동작과 함께 인식하고(막지 않음), 선택이 있던 상태의 탭은 선택 해제로만 쓴다.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)
        context.coordinator.onToggleChrome = onToggleChrome
        context.coordinator.generation = generation
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onToggleChrome = onToggleChrome
        if textView.textContainerInset != insets {
            textView.textContainerInset = insets
        }
        guard context.coordinator.generation != generation else { return }
        context.coordinator.generation = generation
        let offset = textView.contentOffset
        textView.textStorage.setAttributedString(attributed)
        // 글꼴 배율만 바뀐 경우 읽던 자리 근처에 머물게 한다(범위를 벗어나면 UIKit이 보정한다).
        textView.setContentOffset(offset, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var generation = -1
        var onToggleChrome: (() -> Void)?
        /// 탭이 시작될 때 선택 영역이 있었는지 — 있었다면 이 탭은 선택 해제로만 쓰고 바를 건드리지 않는다("선택 우선").
        private var hadSelection = false

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let textView = gestureRecognizer.view as? UITextView {
                hadSelection = textView.selectedRange.length > 0
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, !hadSelection, let view = recognizer.view, view.bounds.width > 1 else { return }
            let fraction = recognizer.location(in: view).x / view.bounds.width
            if SermonViewerTapZone(horizontalFraction: fraction) == .center {
                onToggleChrome?()
            }
        }
    }
}

#elseif os(macOS)

struct SermonViewerScrollText: NSViewRepresentable {
    let attributed: NSAttributedString
    let generation: Int
    let horizontalInset: CGFloat
    let topInset: CGFloat
    let onToggleChrome: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        // `NSTextView.scrollableTextView()`와 같은 구성에 TextKit 1 + `SermonLayoutManager`를 끼우고, 클릭 처리를 위해 하위 클래스 텍스트뷰를 쓴다.
        let (scrollView, textView) = SermonTextKit1.makeScrollView { container, frame in
            SermonViewerNSTextView(frame: frame, textContainer: container)
        }
        scrollView.appearance = NSAppearance(named: .aqua)
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SermonViewerPaper.platformColor

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: horizontalInset, height: topInset)
        textView.drawsBackground = true
        textView.backgroundColor = SermonViewerPaper.platformColor
        textView.textStorage?.setAttributedString(attributed)
        // 스크롤 모드: 가운데 클릭만 바 숨김/표시. 가로 쓸기는 쓰지 않는다.
        guard let clickTextView = textView as? SermonViewerNSTextView else { return scrollView }
        clickTextView.tapReferenceView = scrollView
        clickTextView.clicks.onZone = { [weak coordinator = context.coordinator] zone in
            if zone == .center { coordinator?.onToggleChrome?() }
        }

        context.coordinator.onToggleChrome = onToggleChrome
        context.coordinator.generation = generation
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onToggleChrome = onToggleChrome
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let inset = NSSize(width: horizontalInset, height: topInset)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
        }
        guard context.coordinator.generation != generation else { return }
        context.coordinator.generation = generation
        textView.textStorage?.setAttributedString(attributed)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var generation = -1
        var onToggleChrome: (() -> Void)?
    }
}

#endif

// MARK: - 페이지 모드 — iOS: 페이지 컬

#if os(iOS)

/// 페이지 하나 — 공유 레이아웃의 컨테이너 하나를 그리는 읽기 전용 텍스트뷰를 담는다.
final class SermonViewerPageController: UIViewController {
    let index: Int
    private let textView: UITextView
    private let insets: UIEdgeInsets

    init(index: Int, container: NSTextContainer, insets: UIEdgeInsets) {
        self.index = index
        self.insets = insets
        self.textView = UITextView(frame: .zero, textContainer: container)
        super.init(nibName: nil, bundle: nil)
        textView.isEditable = false
        // 선택 제스처가 페이지 넘김(탭/스와이프)과 겹치지 않게 끈다.
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainerInset = .zero
        textView.backgroundColor = .clear
        textView.overrideUserInterfaceStyle = .light
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 페이지 컬의 뒷면이 비쳐 보일 때도 종이 색이 같도록 불투명한 바탕을 둔다.
        overrideUserInterfaceStyle = .light
        view.backgroundColor = SermonViewerPaper.platformColor
        view.addSubview(textView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 위·아래로 `drawBleed`만큼 키우고 같은 양을 컨테이너 inset으로 되돌려, 글자 위치는 그대로 두고 박스 안여백을 그릴 자리를 만든다.
        let bleed = SermonViewerPaginator.drawBleed
        textView.textContainerInset = UIEdgeInsets(top: bleed, left: 0, bottom: bleed, right: 0)
        textView.frame = view.bounds.inset(by: insets).insetBy(dx: 0, dy: -bleed)
    }
}

struct SermonViewerPageCurl: UIViewControllerRepresentable {
    let paginator: SermonViewerPaginator
    let insets: UIEdgeInsets
    @Binding var currentIndex: Int
    /// 본문 가운데를 한 번 탭했을 때(상·하단 바 숨김/표시). 양 가장자리 탭은 페이지 컬이 직접 처리한다.
    let onCenterTap: () -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        pageViewController.isDoubleSided = false
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.overrideUserInterfaceStyle = .light
        pageViewController.view.backgroundColor = SermonViewerPaper.platformColor
        // 페이지 컬 자체의 탭/팬 인식을 막지 않고 가운데 탭만 따로 받는다.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        pageViewController.view.addGestureRecognizer(tap)
        context.coordinator.paginator = paginator
        context.coordinator.insets = insets
        context.coordinator.show(index: currentIndex, animated: false, in: pageViewController)
        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.paginator !== paginator {
            // 페이지를 다시 나눴다 — 옛 컨테이너를 든 페이지 뷰는 버리고 새로 만든다.
            coordinator.paginator = paginator
            coordinator.insets = insets
            coordinator.pageCache = [:]
            coordinator.show(index: min(currentIndex, paginator.pageCount - 1), animated: false, in: pageViewController)
        } else if coordinator.shownIndex != currentIndex {
            coordinator.show(index: currentIndex, animated: true, in: pageViewController)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: SermonViewerPageCurl
        var paginator: SermonViewerPaginator?
        var insets: UIEdgeInsets = .zero
        /// 만든 페이지를 붙들어 둔다 — 텍스트 컨테이너는 한 번에 텍스트뷰 하나에만 물릴 수 있어,
        /// 같은 페이지를 넘길 때마다 새로 만들지 않고 재사용한다.
        var pageCache: [Int: SermonViewerPageController] = [:]
        var shownIndex = -1

        init(_ parent: SermonViewerPageCurl) { self.parent = parent }

        func page(at index: Int) -> SermonViewerPageController? {
            guard let paginator, paginator.containers.indices.contains(index) else { return nil }
            if let cached = pageCache[index] { return cached }
            let controller = SermonViewerPageController(index: index, container: paginator.containers[index], insets: insets)
            pageCache[index] = controller
            return controller
        }

        func show(index: Int, animated: Bool, in pageViewController: UIPageViewController) {
            guard let target = page(at: index) else { return }
            let direction: UIPageViewController.NavigationDirection = index >= shownIndex ? .forward : .reverse
            pageViewController.setViewControllers([target], direction: direction, animated: animated && shownIndex >= 0)
            shownIndex = index
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? SermonViewerPageController else { return nil }
            return page(at: current.index - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? SermonViewerPageController else { return nil }
            return page(at: current.index + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController], transitionCompleted completed: Bool
        ) {
            guard completed, let visible = pageViewController.viewControllers?.first as? SermonViewerPageController else { return }
            shownIndex = visible.index
            if parent.currentIndex != visible.index {
                parent.currentIndex = visible.index
            }
        }

        // MARK: 가운데 탭

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view, view.bounds.width > 1 else { return }
            let fraction = recognizer.location(in: view).x / view.bounds.width
            if SermonViewerTapZone(horizontalFraction: fraction) == .center {
                parent.onCenterTap()
            }
        }
    }
}

#elseif os(macOS)

// MARK: - 페이지 모드 — macOS: 한 페이지씩

/// 클릭 한 번을 이동/바 숨김 명령으로 바꿔 전달한다. 글자 위에서 시작한 클릭은 더블클릭(단어 선택)일 수 있어
/// 시스템 더블클릭 간격만큼 기다렸다가, 두 번째 클릭이나 드래그 선택이 없을 때만 실행한다("선택 우선").
@MainActor
final class SermonViewerClickDispatcher {
    var onZone: ((SermonViewerTapZone) -> Void)?
    private var pending: Task<Void, Never>?

    func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    func fire(_ zone: SermonViewerTapZone, deferred: Bool) {
        cancelPending()
        guard deferred else {
            onZone?(zone)
            return
        }
        let delay = NSEvent.doubleClickInterval
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.onZone?(zone)
        }
    }
}

/// 트랙패드 두 손가락 가로 쓸기 → 이전/다음 쪽. 한 번의 쓸기(관성 포함)에 한 번만 넘긴다.
@MainActor
final class SermonViewerSwipeTracker {
    var onCommand: ((SermonViewerCommand) -> Void)?
    private var accumulated: CGFloat = 0
    private var didFire = false

    /// 가로가 우세한 트랙패드 쓸기를 처리했으면 true(이벤트를 소비).
    func handle(_ event: NSEvent) -> Bool {
        guard onCommand != nil, event.hasPreciseScrollingDeltas else { return false }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            accumulated = 0
            didFire = false
        }
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard abs(deltaX) > abs(deltaY) else { return false }
        // 관성 구간은 무시한다.
        if event.momentumPhase.isEmpty {
            accumulated += deltaX
            if !didFire, abs(accumulated) > 60 {
                didFire = true
                // 콘텐츠가 왼쪽으로 밀리는 방향(음수)이 다음 쪽.
                onCommand?(accumulated < 0 ? .nextPage : .previousPage)
            }
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            accumulated = 0
            didFire = false
        }
        return true
    }
}

/// 읽기 전용 텍스트뷰 — 드래그 선택은 AppKit 기본 동작을 그대로 두고(선택 우선),
/// 이동 없는 한 번 클릭만 영역별 명령으로 올려보낸다.
final class SermonViewerNSTextView: NSTextView {
    let clicks = SermonViewerClickDispatcher()
    let swipe = SermonViewerSwipeTracker()
    /// 클릭 가로 위치의 기준 뷰(페이지 모드: 페이지 전체 뷰, 스크롤 모드: 스크롤 뷰). nil이면 superview.
    weak var tapReferenceView: NSView?

    override func mouseDown(with event: NSEvent) {
        // 더블/트리플 클릭은 단어·문단 선택 — 대기 중이던 첫 클릭 동작도 취소한다.
        if event.clickCount > 1 {
            clicks.cancelPending()
            super.mouseDown(with: event)
            return
        }
        let hadSelection = selectedRange().length > 0
        let startPoint = event.locationInWindow
        super.mouseDown(with: event) // 드래그 선택이 끝날 때까지 돌아오지 않는다
        // 선택이 있었거나(이번 클릭은 선택 해제) 드래그로 선택이 생겼다면 명령을 내지 않는다.
        guard !hadSelection, selectedRange().length == 0 else {
            clicks.cancelPending()
            return
        }
        let endPoint = window?.mouseLocationOutsideOfEventStream ?? startPoint
        guard hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) < 4 else { return }
        guard let reference = tapReferenceView ?? superview, reference.bounds.width > 1 else { return }
        let fraction = reference.convert(startPoint, from: nil).x / reference.bounds.width
        clicks.fire(SermonViewerTapZone(horizontalFraction: fraction), deferred: true)
    }

    override func scrollWheel(with event: NSEvent) {
        if !swipe.handle(event) {
            super.scrollWheel(with: event)
        }
    }
}

/// 페이지 모드의 바탕 뷰 — 글자 영역 바깥(좌우·위아래 여백)의 클릭을 받는다. 여백에는 글자가 없어 바로 실행한다.
final class SermonViewerPageNSView: NSView {
    let clicks = SermonViewerClickDispatcher()
    let swipe = SermonViewerSwipeTracker()

    /// 위쪽이 원점 — 텍스트뷰의 y 위치를 "위 여백"으로 줄 수 있게 한다(위·아래 여백이 달라도 같은 값으로 위치가 정해진다).
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard bounds.width > 1 else { return }
        let fraction = convert(event.locationInWindow, from: nil).x / bounds.width
        clicks.fire(SermonViewerTapZone(horizontalFraction: fraction), deferred: false)
    }

    override func scrollWheel(with event: NSEvent) {
        if !swipe.handle(event) {
            super.scrollWheel(with: event)
        }
    }
}

/// 현재 페이지 하나를 그리는 읽기 전용 텍스트뷰. 페이지 이동은 SwiftUI 쪽이 `index`를 바꿔 처리하고,
/// 클릭 영역·트랙패드 쓸기는 `onCommand`로 올려보낸다.
struct SermonViewerSinglePage: NSViewRepresentable {
    let paginator: SermonViewerPaginator
    let index: Int
    let insets: NSSize
    let onCommand: (SermonViewerCommand) -> Void

    func makeNSView(context: Context) -> SermonViewerPageNSView {
        let view = SermonViewerPageNSView()
        view.appearance = NSAppearance(named: .aqua)
        wire(view.clicks, view.swipe, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: SermonViewerPageNSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onCommand = onCommand
        // SwiftUI가 다른 이유로 이 뷰를 갱신할 때 텍스트뷰를 매번 다시 만들지 않는다.
        guard coordinator.paginator !== paginator || coordinator.index != index || coordinator.insets != insets else { return }
        coordinator.paginator = paginator
        coordinator.index = index
        coordinator.insets = insets
        nsView.subviews.forEach { $0.removeFromSuperview() }
        guard paginator.containers.indices.contains(index) else { return }
        // 위·아래로 `drawBleed`만큼 키우고 같은 양을 컨테이너 inset으로 되돌려, 글자 위치는 그대로 두고 박스 안여백을 그릴 자리를 만든다.
        let bleed = SermonViewerPaginator.drawBleed
        let frame = NSRect(
            x: insets.width, y: insets.height - bleed,
            width: paginator.containerSize.width, height: paginator.containerSize.height + bleed * 2
        )
        let textView = SermonViewerNSTextView(frame: frame, textContainer: paginator.containers[index])
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: bleed)
        textView.drawsBackground = false
        textView.appearance = NSAppearance(named: .aqua)
        textView.tapReferenceView = nsView
        wire(textView.clicks, textView.swipe, coordinator: coordinator)
        nsView.addSubview(textView)
    }

    private func wire(_ clicks: SermonViewerClickDispatcher, _ swipe: SermonViewerSwipeTracker, coordinator: Coordinator) {
        coordinator.onCommand = onCommand
        clicks.onZone = { [weak coordinator] zone in
            coordinator?.onCommand(SermonViewerCommand(zone: zone))
        }
        swipe.onCommand = { [weak coordinator] command in
            coordinator?.onCommand(command)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var paginator: SermonViewerPaginator?
        var index = -1
        var insets = NSSize.zero
        var onCommand: (SermonViewerCommand) -> Void = { _ in }
    }
}

// MARK: - macOS 키보드

/// 뷰어 창이 키 입력을 받는 동안 ←/→, PageUp/PageDown, Space(Shift+Space는 이전), Home/End, H를 명령으로 바꿔 전달한다.
/// 텍스트뷰가 포커스를 가져가도 동작하도록 `NSEvent` 로컬 모니터로 받는다. 처리한 키(`handler`가 true)만 소비한다.
struct SermonViewerKeyCatcher: NSViewRepresentable {
    let handler: (SermonViewerCommand) -> Bool

    func makeNSView(context: Context) -> SermonViewerKeyCatcherView {
        let view = SermonViewerKeyCatcherView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: SermonViewerKeyCatcherView, context: Context) {
        nsView.handler = handler
    }
}

final class SermonViewerKeyCatcherView: NSView {
    var handler: ((SermonViewerCommand) -> Bool)?
    private var monitor: Any?

    // 마우스 클릭을 가로채지 않는다.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, let command = Self.command(for: event) else { return event }
            // 편집 가능한 입력이나 슬라이더가 키를 쓰는 중이면 그쪽을 우선한다.
            if let responder = self.window?.firstResponder {
                if (responder as? NSTextView)?.isEditable == true { return event }
                if responder is NSSlider, [123, 124, 115, 119].contains(event.keyCode) { return event }
            }
            return (self.handler?(command) ?? false) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private static func command(for event: NSEvent) -> SermonViewerCommand? {
        let flags = event.modifierFlags
        guard flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        let shift = flags.contains(.shift)
        switch event.keyCode {
        case 49: return shift ? .previousPage : .nextPage // Space
        case 123 where !shift, 116 where !shift: return .previousPage // ←, PageUp
        case 124 where !shift, 121 where !shift: return .nextPage // →, PageDown
        case 115: return .firstPage // Home
        case 119: return .lastPage // End
        default: break
        }
        if !shift, event.charactersIgnoringModifiers?.lowercased() == "h" { return .toggleChrome }
        return nil
    }
}

#endif
