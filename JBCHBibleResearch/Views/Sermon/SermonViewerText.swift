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

    /// 글자 크기와 줄/문단 간격에 같은 배율을 곱한다. 원본을 순회하면서 사본에 쓰므로 순회 중 변경이 없다.
    /// 들여쓰기(말씀구절/인용의 고정 10~14pt)는 스타일의 모양이라 배율을 곱하지 않는다.
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

    let containerSize: CGSize
    private let storage: NSTextStorage
    private let layoutManager = NSLayoutManager()
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

// MARK: - 세로 스크롤 읽기 전용 텍스트

#if os(iOS)

struct SermonViewerScrollText: UIViewRepresentable {
    let attributed: NSAttributedString
    /// 본문이 새로 만들어질 때마다 바뀌는 값 — 같은 값이면 텍스트를 다시 넣지 않아 스크롤 위치가 유지된다.
    let generation: Int

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16)
        // 뷰어 고정 종이색 + 라이트 외형(`SermonViewerPaper` 참고).
        textView.overrideUserInterfaceStyle = .light
        textView.backgroundColor = SermonViewerPaper.platformColor
        textView.attributedText = attributed
        context.coordinator.generation = generation
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard context.coordinator.generation != generation else { return }
        context.coordinator.generation = generation
        let offset = textView.contentOffset
        textView.attributedText = attributed
        // 글꼴 배율만 바뀐 경우 읽던 자리 근처에 머물게 한다(범위를 벗어나면 UIKit이 보정한다).
        textView.setContentOffset(offset, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var generation = -1
    }
}

#elseif os(macOS)

struct SermonViewerScrollText: NSViewRepresentable {
    let attributed: NSAttributedString
    let generation: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.appearance = NSAppearance(named: .aqua)
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SermonViewerPaper.platformColor
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = true
            textView.textContainerInset = NSSize(width: 16, height: 16)
            textView.drawsBackground = true
            textView.backgroundColor = SermonViewerPaper.platformColor
            textView.textStorage?.setAttributedString(attributed)
        }
        context.coordinator.generation = generation
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.generation != generation,
              let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.generation = generation
        textView.textStorage?.setAttributedString(attributed)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var generation = -1
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
        textView.frame = view.bounds.inset(by: insets)
    }
}

struct SermonViewerPageCurl: UIViewControllerRepresentable {
    let paginator: SermonViewerPaginator
    let insets: UIEdgeInsets
    @Binding var currentIndex: Int

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        pageViewController.isDoubleSided = false
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.overrideUserInterfaceStyle = .light
        pageViewController.view.backgroundColor = SermonViewerPaper.platformColor
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

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
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
    }
}

#elseif os(macOS)

/// 현재 페이지 하나를 그리는 읽기 전용 텍스트뷰. 페이지 이동은 SwiftUI 쪽(버튼/스와이프)이 `index`를 바꿔 처리한다.
struct SermonViewerSinglePage: NSViewRepresentable {
    let paginator: SermonViewerPaginator
    let index: Int
    let insets: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        // SwiftUI가 다른 이유로 이 뷰를 갱신할 때 텍스트뷰를 매번 다시 만들지 않는다.
        guard coordinator.paginator !== paginator || coordinator.index != index else { return }
        coordinator.paginator = paginator
        coordinator.index = index
        nsView.subviews.forEach { $0.removeFromSuperview() }
        guard paginator.containers.indices.contains(index) else { return }
        let frame = NSRect(
            x: insets.width, y: insets.height,
            width: paginator.containerSize.width, height: paginator.containerSize.height
        )
        let textView = NSTextView(frame: frame, textContainer: paginator.containers[index])
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.drawsBackground = false
        textView.appearance = NSAppearance(named: .aqua)
        nsView.addSubview(textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var paginator: SermonViewerPaginator?
        var index = -1
    }
}

#endif
