//
//  WordSummaryPanelController.swift
//  JBCHBibleResearch
//
//  [2026-08-27 신설] 사용자 요청 — "팝업창으로 구현하기를 원함." 사용자가
//  명확히 확인함: 이 전체 논의는 macOS 한정이고 iOS는 기존 인스펙터 방식
//  그대로 유지한다("iOS는 기존기능 그대로 하면 됨") — 그래서 이 파일은 전부
//  `#if os(macOS)`로 감싼다.
//
//  사용자가 확인한 사양 3가지:
//  ① 창 형태 — "떠 있는 도구창 스타일(Floating Panel)": 제목표시줄이 얇고
//     메인 창 위에 항상 떠 있는 느낌(Xcode 인스펙터 팝업과 비슷).
//  ② 닫을 때 — "예, 지금과 동일하게 자동 복원": 번역본 열 좁히기/왼쪽
//     사이드바 숨김을 되돌리는 기존 로직(`BibleReadingContentView.
//     closeWordSummaryEditor()`)을 그대로 재사용한다 — 이 컨트롤러는 그
//     로직을 모르고, 그저 열 때 넘겨받은 `onClose` 클로저를 창이 닫힐 때
//     불러줄 뿐이다.
//  ③ 동시에 몇 개 — "하나만, 기존 이미 열려있으면 그 창으로 포커스 이동":
//     이미 떠 있으면 새 패널을 또 만들지 않고 내용만 바꾸고 앞으로 가져온다.
//
//  왜 SwiftUI `WindowGroup`/`.sheet`/`.popover`가 아니라 AppKit `NSPanel`을
//  직접 만드는가 — 애초에 팝업을 쓰려던 이유가 "팝업 안에 네이티브 에디터
//  툴(서식 팝업 `usesInspectorBar` 등)을 온전히 넣기 위함"이었다(사용자
//  확인). 그런데 이전 시도(같은 창 안의 `.overlay` 카드)에서는 그 네이티브
//  서식 팝업이 여전히 "같은 창" 좌표계 안에서 뜨다 보니 카드 밖(성경 본문
//  쪽)으로 넘치는 문제가 그대로 남았다 — 진짜 별도의 `NSWindow`/`NSPanel`이
//  아니면 이 문제 자체가 근본적으로 해결되지 않는다(네이티브 서식 팝업은
//  텍스트뷰가 속한 그 창의 좌표계 안에서만 위치를 잡으므로, 텍스트뷰가 정말
//  다른 창에 있으면 그 창 밖으로 넘칠 수가 없다). SwiftUI에는 "얇은 제목표시줄의
//  떠 있는 도구창" 전용 Scene 타입이 없어, 이런 패널이 필요한 macOS 앱에서
//  표준적으로 쓰는 방식(AppKit `NSPanel` + `.nonactivatingPanel`/
//  `.utilityWindow` 스타일 + `isFloatingPanel = true` + `NSHostingController`로
//  SwiftUI 콘텐츠를 올리기)을 그대로 따른다.
//
//  ⚠️ [확인 필요] 이 도구(클라우드 세션)에는 Xcode/실기기가 없어, 이 패널이
//  실제로 메인 창 위에 기대한 대로 뜨는지, 초기 크기(420×520, 사용자 확인 없이
//  고른 추정값 — 아래 `present` 참고)가 적당한지, `NSHostingController`에
//  `.environment(\.modelContext, ...)`를 직접 넣어준 것이 자동저장까지 정상
//  동작하게 하는지를 직접 빌드해 확인하지 못했다 — 아래는 AppKit 문서화된
//  표준 패턴과 이 프로젝트의 기존 코드(다른 창에서 `modelContext`를 어떻게
//  주입받는지)에 근거한 구현이다. 실기기에서 이상하면 알려주시면 바로
//  조정하겠다.

#if os(macOS)

import SwiftUI
import SwiftData
import AppKit
import BibleResearchModels

/// [2026-08-27] 이 프로젝트는 프로젝트 전역 기본 액터 격리를 MainActor로
/// 두고 있다(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, 다른 싱글턴
/// `SidebarVisibilityRequest`도 같은 이유로 `@MainActor`를 따로 안 붙인다) —
/// 그 관례를 그대로 따라 여기서도 명시적으로 붙이지 않는다.
final class WordSummaryPanelController: NSObject, NSWindowDelegate {
    static let shared = WordSummaryPanelController()

    /// [2026-08-27 신설] macOS에서는 "말씀 요약" 편집기가 더 이상 성경 조회
    /// 창의 인스펙터가 아니라 이 별도 패널에서 열린다 — 그 패널과 성경 조회
    /// 창의 하단 액션바([말씀 복사])가 항상 같은 `RichTextEditingProxy`를
    /// 봐야 커서 삽입이 되므로, 창마다 따로 두지 않고 앱 전체에서 하나뿐인
    /// 이 싱글턴이 프록시를 들고 있는다(`BibleReadingView.swift`의
    /// `wordSummaryProxy` 상단 주석 참고 — 그 프로퍼티가 macOS에서는 이
    /// 프록시를 그대로 가리키도록 바뀌었다).
    let proxy = RichTextEditingProxy()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var onClose: (() -> Void)?
    /// [2026-08-27 신설] "한 번에 하나만" 요구를 mac에서 성경 조회 창을 여러
    /// 개(각 창의 "새 창" 아이콘) 띄워 둔 극단적인 경우까지 안전하게 만족시키기
    /// 위한 식별자 — 어느 성경 조회 창이 지금 이 패널의 주인인지 기억한다.
    /// `BibleReadingViewModel`은 창마다 하나씩 생성되는 `final class`라
    /// `ObjectIdentifier`로 안정적인 창 식별자를 얻을 수 있다.
    private var ownerToken: ObjectIdentifier?

    private override init() { super.init() }

    /// "말씀 요약" 편집기를 패널로 띄운다.
    ///
    /// - Parameters:
    ///   - summary: 편집할 `VerseSummary`.
    ///   - modelContext: 이 패널은 앱의 일반 SwiftUI 창 계층 밖에서
    ///     `NSHostingController`로 직접 띄우므로, `WordSummaryEditorView`가
    ///     쓰는 `@Environment(\.modelContext)`를 자동으로 물려받지 못한다 —
    ///     호출자(성경 조회 창, 이미 이 환경값을 갖고 있다)가 명시적으로
    ///     넘겨줘야 자동저장이 올바른 SwiftData 컨테이너에 실제로 반영된다.
    ///   - ownerToken: 지금 요청한 성경 조회 창의 식별자(위 `ownerToken`
    ///     프로퍼티 설명 참고) — 이미 다른 창 소유로 패널이 떠 있으면, 그
    ///     창 쪽 뒷정리(`onClose`)부터 실행한 뒤 이 패널을 새 주인으로 넘긴다.
    ///   - onClose: 패널이 닫힐 때(사용자가 패널 자체의 닫기 버튼을 누르든,
    ///     호출자가 `hide()`로 프로그램적으로 닫든) 정확히 한 번 불린다 —
    ///     호출자는 여기에 기존 `closeWordSummaryEditor()`를 그대로 넘긴다.
    func present(
        summary: VerseSummary,
        modelContext: ModelContext,
        ownerToken: ObjectIdentifier,
        onClose: @escaping () -> Void
    ) {
        if panel != nil, let previousOwnerToken = self.ownerToken, previousOwnerToken != ownerToken {
            // 다른 성경 조회 창이 열어 둔 채였다면, 그 창 쪽 번역본/사이드바가
            // 좁혀진 채로 영영 남지 않도록 뒷정리부터 실행한다.
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

        // ⚠️ [확인 필요] 420×520은 사용자에게 직접 확인받지 않은 추정값이다 —
        // 이전에 인스펙터 열 폭으로 쓰던 640은 "네이티브 서식 팝업이 좁은 열
        // 밖으로 넘치는 문제"를 피하려던 값이었는데(위 상단 주석 참고), 진짜
        // 별도 창이 되면서 그 문제 자체가 사라져 더 넓을 이유가 없어졌다.
        // `.resizable`이라 사용자가 직접 조절할 수 있다.
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "말씀 요약"
        // 사용자 확인 — "떠 있는 도구창 스타일(제목표시줄이 없거나 얇고, 메인
        // 창 위에 항상 떠 있는 느낌)". `isFloatingPanel`/`level = .floating`으로
        // 항상 다른 일반 창보다 위에 뜨게 하고, `hidesOnDeactivate = false`로
        // 앱이 잠깐 비활성화돼도(다른 앱으로 전환 등) 편집 중이던 내용이 갑자기
        // 화면에서 사라지지 않게 한다.
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        // 이 컨트롤러가 `panel`을 계속 들고 참조하므로, AppKit이 `close()` 시점에
        // 자동으로 해제하지 않게 막는다(창을 직접 참조로 들고 있을 때의 표준
        // 권장 설정 — 이중 해제 위험을 없앤다).
        newPanel.isReleasedWhenClosed = false
        newPanel.contentViewController = newHostingController
        newPanel.delegate = self
        newPanel.center()

        panel = newPanel
        newPanel.makeKeyAndOrderFront(nil)
    }

    /// 코드 쪽(`closeWordSummaryEditor()`)에서 패널을 닫는다 — 실제 닫기는
    /// `NSPanel.close()`가 아래 `windowWillClose(_:)`를 동기적으로 불러주므로,
    /// 사용자가 패널 자체의 닫기 버튼을 눌렀을 때와 완전히 같은 경로를 탄다.
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
