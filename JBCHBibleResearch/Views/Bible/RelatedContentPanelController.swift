//
//  RelatedContentPanelController.swift
//  JBCHBibleResearch
//
//  macOS 전용: 성경 조회의 "관련 콘텐츠"(개요·메모·말씀 요약·연구문서·내 설교)를 떠 있는 도구창(Floating NSPanel)으로 띄운다.
//  iOS/아이패드는 기존 `.inspector` 방식을 유지하므로 이 파일 전체를 `#if os(macOS)`로 감싼다.
//
//  왜 `.inspector`가 아니라 패널인가(2026-10-01):
//  인스펙터를 열면 창 폭(1072pt)에서 사이드바 + 본문 최소 폭 + 인스펙터가 빠듯해 분할 뷰가 사이드바를 접으며 자식 호스팅 뷰의 최소 크기를
//  제약 갱신 도중 계속 다시 알리는 순환(`SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`)에 빠져
//  "Update Constraints in Window pass" 한도 초과로 앱이 종료됐다. 패널은 분할 뷰 칸이 아니므로 이 순환이 구조적으로 없다.
//
//  동작 규약(사용자 요청 2026-10-01):
//  - 항상 다른 창 위에 떠 있는다(`isFloatingPanel`/`.floating`, 앱이 비활성이어도 유지).
//  - 열 때마다 마지막 위치·크기로 열린다(UserDefaults에 직접 저장 — 아래 `Self.frameDefaultsKey`).
//  - 패널은 앱 전체에서 하나만 유지한다(`WordSummaryPanelController`와 같은 구조). 다른 성경 조회 창이 요청하면 주인만 바뀐다.
//  - 닫힐 때(닫기 버튼이든 `hide`든) 열 때 넘겨받은 `onClose`가 정확히 한 번 호출된다.

#if os(macOS)

import SwiftUI
import SwiftData
import AppKit
import BibleResearchModels

/// 패널에 올라가는 SwiftUI 루트. `BibleReadingContentView`가 계산해서 넘기던 `selectedVerse`를 여기서 직접 계산해야
/// 절 선택이 바뀔 때 패널이 따라 갱신된다(값으로 넘기면 패널을 연 시점의 값에 고정된다). `viewModel`은 `@Observable`이라
/// 이 `body`가 읽는 프로퍼티가 바뀌면 자동으로 다시 그려진다.
struct RelatedContentPanelRoot: View {
    let viewModel: BibleReadingViewModel
    let onSelectMemo: (UserMemo) -> Void
    let onSelectWordSummary: (VerseSummary) -> Void
    let onSelectVerseMention: (VerseMention) -> Void
    let openWindow: OpenWindowAction

    var body: some View {
        ChapterRelatedContentPanel(
            viewModel: viewModel,
            onSelectMemo: onSelectMemo,
            onSelectWordSummary: onSelectWordSummary,
            selectedVerse: viewModel.selectedVerses.count == 1 ? viewModel.selectedVerses.first : nil,
            onSelectVerseMention: onSelectVerseMention,
            injectedOpenWindow: openWindow
        )
        // 패널은 `ContentView`의 `.preferredColorScheme` 밖이라 앱 외형 설정을 직접 적용한다(`AppColorSchemeModifier`와 같은 값).
        .preferredColorScheme(UserSettingsStore.shared.colorSchemePreference.colorScheme)
    }
}

/// 프로젝트 전역 기본 액터 격리가 MainActor라 `WordSummaryPanelController`처럼 `@MainActor`를 따로 붙이지 않는다.
final class RelatedContentPanelController: NSObject, NSWindowDelegate {
    static let shared = RelatedContentPanelController()

    /// 마지막 패널 프레임(`NSStringFromRect`). `setFrameAutosaveName`은 같은 이름의 창이 아직 해제되기 전이면 실패할 수 있어
    /// 값을 직접 저장·복원하고, 복원 시 현재 연결된 화면과 겹치는지 검증한다(모니터를 뺀 뒤 화면 밖에 열리는 것을 막는다).
    private static let frameDefaultsKey = "relatedContentPanel.frame"
    private static let defaultSize = NSSize(width: 340, height: 640)
    private static let minimumSize = NSSize(width: 260, height: 300)

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var onClose: (() -> Void)?
    /// 지금 패널의 주인인 성경 조회 창 식별자(`BibleReadingViewModel`은 창마다 하나라 `ObjectIdentifier`로 구분된다).
    private var ownerToken: ObjectIdentifier?

    private override init() { super.init() }

    /// 관련 콘텐츠 패널을 띄운다. 이미 떠 있으면 새로 만들지 않고 내용·주인만 바꿔 앞으로 가져온다.
    ///
    /// - Parameters:
    ///   - content: 패널에 올릴 루트 뷰(`RelatedContentPanelRoot`). 패널은 SwiftUI 창 계층 밖이라 필요한 환경 값은 호출자가 넣어 넘긴다.
    ///   - ownerToken: 요청한 성경 조회 창의 식별자.
    ///   - onClose: 패널이 닫힐 때 정확히 한 번 호출된다.
    func present(content: AnyView, ownerToken: ObjectIdentifier, onClose: @escaping () -> Void) {
        if let panel {
            // 다른 창이 가져가는 경우: 이전 주인이 "열림" 표시를 내릴 수 있게 그쪽 `onClose`를 먼저 부른다.
            // 새 주인/콜백을 먼저 확정한 뒤 호출해 재진입(이전 주인이 `hide`를 부르는 경우)이 새 주인을 닫지 않게 한다.
            let previousOnClose = (self.ownerToken != ownerToken) ? self.onClose : nil
            self.ownerToken = ownerToken
            self.onClose = onClose
            previousOnClose?()
            hostingController?.rootView = content
            panel.orderFrontRegardless()
            return
        }

        self.ownerToken = ownerToken
        self.onClose = onClose

        let newHostingController = NSHostingController(rootView: content)
        // 창 크기는 저장된 프레임/사용자 조절이 정한다. 기본값이면 호스팅 컨트롤러가 SwiftUI 콘텐츠의 이상적 크기로 창을 다시 맞춰
        // 복원한 프레임을 덮어쓴다(macOS 13+ `sizingOptions`).
        newHostingController.sizingOptions = []
        hostingController = newHostingController

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "관련 콘텐츠"
        // 항상 일반 창 위에 뜨게 하고, 앱이 비활성화돼도 사라지지 않게 한다(`WordSummaryPanelController`와 같은 설정).
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        // 컨트롤러가 `panel`을 직접 참조로 들고 있으므로 `close()` 시 AppKit의 자동 해제(이중 해제)를 막는다.
        newPanel.isReleasedWhenClosed = false
        newPanel.contentViewController = newHostingController
        newPanel.contentMinSize = Self.minimumSize
        newPanel.delegate = self
        newPanel.setFrame(Self.initialFrame(), display: false)

        panel = newPanel
        newPanel.orderFrontRegardless()
    }

    /// 코드 쪽에서 패널을 닫는다. `owner`가 주어지면 그 창이 주인일 때만 닫는다(다른 창의 패널을 실수로 닫지 않도록).
    /// `close()`가 `windowWillClose(_:)`를 동기 호출하므로 닫기 버튼을 누른 경우와 같은 경로를 탄다.
    func hide(owner: ObjectIdentifier? = nil) {
        if let owner, owner != ownerToken { return }
        panel?.close()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }

    func windowWillClose(_ notification: Notification) {
        saveFrame()
        panel = nil
        hostingController = nil
        ownerToken = nil
        let callback = onClose
        onClose = nil
        callback?()
    }

    // MARK: - 프레임 저장/복원

    private func saveFrame() {
        guard let frame = panel?.frame else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameDefaultsKey)
    }

    /// 저장된 프레임이 있고 지금 연결된 화면과 충분히 겹치면 그것을, 아니면 주 화면 오른쪽 위 기본 위치를 쓴다.
    private static func initialFrame() -> NSRect {
        if let saved = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            var rect = NSRectFromString(saved)
            // 손상된 값(0 크기 등)은 버리고, 최소 크기 아래로 내려가지 않게 한다.
            if rect.width > 0, rect.height > 0 {
                rect.size.width = max(rect.width, minimumSize.width)
                rect.size.height = max(rect.height, minimumSize.height)
                let isVisibleOnSomeScreen = NSScreen.screens.contains { screen in
                    let overlap = screen.visibleFrame.intersection(rect)
                    return overlap.width >= 100 && overlap.height >= 50
                }
                if isVisibleOnSomeScreen { return rect }
            }
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(
            width: min(defaultSize.width, visible.width),
            height: min(defaultSize.height, visible.height)
        )
        return NSRect(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
    }
}

#endif
