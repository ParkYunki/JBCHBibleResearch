//
//  WordSummaryPanelController.swift
//  JBCHBibleResearch
//
//  macOS 전용: "말씀 요약" 편집기를 떠 있는 도구창(Floating NSPanel)으로 띄우는 컨트롤러.
//  iOS는 기존 인스펙터 방식을 유지하므로 이 파일 전체를 `#if os(macOS)`로 감싼다.
//  - 패널은 앱 전체에서 하나만 유지한다. 이미 떠 있으면 새로 만들지 않고 내용만 바꿔 앞으로 가져온다.
//  - 닫힐 때는 열 때 넘겨받은 `onClose` 클로저만 호출한다(번역본 열/사이드바 복원 로직은 호출자 몫).
//  - SwiftUI `WindowGroup`/`.sheet`/`.popover` 대신 AppKit `NSPanel`을 쓰는 이유: 네이티브 서식 팝업은
//    텍스트뷰가 속한 창의 좌표계 안에서만 위치를 잡으므로, 진짜 별도 창이어야 카드 밖으로 넘치지 않는다.

#if os(macOS)

import SwiftUI
import SwiftData
import AppKit
import BibleResearchModels

/// 프로젝트 전역 기본 액터 격리가 MainActor(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)라
/// 다른 싱글턴(`SidebarVisibilityRequest`)처럼 `@MainActor`를 따로 붙이지 않는다.
final class WordSummaryPanelController: NSObject, NSWindowDelegate {
    static let shared = WordSummaryPanelController()

    /// 패널과 성경 조회 창의 하단 액션바([말씀 복사])가 같은 `RichTextEditingProxy`를 봐야
    /// 커서 삽입이 되므로, 앱 전체에서 하나뿐인 이 싱글턴이 프록시를 들고 있는다.
    let proxy = RichTextEditingProxy()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var onClose: (() -> Void)?
    /// 지금 이 패널의 주인인 성경 조회 창의 식별자. 조회 창을 여러 개 띄운 경우에도
    /// "한 번에 하나만"을 지키기 위해 쓴다(`BibleReadingViewModel`은 창마다 하나라 `ObjectIdentifier`로 구분 가능).
    private var ownerToken: ObjectIdentifier?

    private override init() { super.init() }

    /// "말씀 요약" 편집기를 패널로 띄운다.
    ///
    /// - Parameters:
    ///   - summary: 편집할 `VerseSummary`.
    ///   - modelContext: 패널은 일반 SwiftUI 창 계층 밖의 `NSHostingController`에 올라가
    ///     `@Environment(\.modelContext)`를 물려받지 못하므로, 호출자가 명시적으로 넘겨야 자동저장이 반영된다.
    ///   - ownerToken: 요청한 성경 조회 창의 식별자. 다른 창 소유로 이미 떠 있으면
    ///     그 창의 `onClose`부터 실행한 뒤 새 주인으로 넘긴다.
    ///   - onClose: 패널이 닫힐 때(패널 닫기 버튼이든 `hide()`든) 정확히 한 번 호출된다.
    func present(
        summary: VerseSummary,
        modelContext: ModelContext,
        ownerToken: ObjectIdentifier,
        onClose: @escaping () -> Void
    ) {
        if panel != nil, let previousOwnerToken = self.ownerToken, previousOwnerToken != ownerToken {
            // 이전 주인 창의 번역본/사이드바가 좁혀진 채 남지 않도록 뒷정리부터 실행한다.
            let previousOnClose = self.onClose
            previousOnClose?()
        }

        self.ownerToken = ownerToken
        self.onClose = onClose

        let content = AnyView(
            WordSummaryEditorView(
                summary: summary, presentationContext: .contextual, externalProxy: proxy
            )
            .environment(\.modelContext, modelContext)
        )

        if let panel {
            hostingController?.rootView = content
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let newHostingController = NSHostingController(rootView: content)
        hostingController = newHostingController

        // 초기 크기 420×520은 추정값이며 `.resizable`이라 사용자가 조절할 수 있다.
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "말씀 요약"
        // 항상 일반 창 위에 뜨게 하고, 앱이 비활성화돼도 편집 중인 패널이 사라지지 않게 한다.
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        // 컨트롤러가 `panel`을 직접 참조로 들고 있으므로 `close()` 시 AppKit의 자동 해제(이중 해제)를 막는다.
        newPanel.isReleasedWhenClosed = false
        newPanel.contentViewController = newHostingController
        newPanel.delegate = self
        newPanel.center()

        panel = newPanel
        newPanel.makeKeyAndOrderFront(nil)
    }

    /// 코드 쪽에서 패널을 닫는다. `close()`가 `windowWillClose(_:)`를 동기 호출하므로
    /// 사용자가 닫기 버튼을 누른 경우와 같은 경로를 탄다.
    func hide() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        hostingController = nil
        ownerToken = nil
        let callback = onClose
        onClose = nil
        callback?()
    }
}

#endif
