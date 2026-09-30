//
//  RhwpWebViewerPane.swift
//  JBCHBibleResearch
//
//  rhwp(WKWebView + WASM) 기반 HWP 웹 뷰어. DocumentViewerView.swift의 뷰어 전환
//  컨트롤(HWPViewerMode)에서 hwp-swift 네이티브 뷰어와 함께 고를 수 있다(설계 배경은
//  Resources/hwp_viewer.html 상단 주석 참고).
//  - Swift ↔ JS 브릿지: window.rhwp* 함수는 예외 대신 `{ pageCount }`/`{ ok }`/`{ error }`를 반환한다.
//  - wasm 응답은 `Content-Type: application/wasm` 헤더가 있어야 instantiateStreaming이 통과한다.
//  - 문서 로딩은 `didFinish`가 아니라 JS가 보내는 `hwpViewerReady` 신호로 시작한다.
//  - 검색 위치의 페이지는 `HwpDocument.getPageOfPosition`으로 구한다.
//  - 캔버스 렌더링이라 DOM에 텍스트가 없어 드래그 선택/복사는 아직 지원하지 않는다.
//

import SwiftUI
import WebKit

/// 페이지(원본 보기)에서 문서 바이트가 준비돼 있을 때 그리는 rhwp 웹 뷰어 화면.
/// 툴바(이전/다음 페이지 + 쪽 번호) + WKWebView 본문 + 로딩/에러 오버레이로
/// 구성된다.
struct RhwpWebViewerPane: View {
    let documentData: Data
    /// 문서가 `.ready`가 되면 이 검색어로 자동 검색하고 첫 매치로 스크롤한다(`controller.searchQuery` 직접 대입과 같은 경로).
    var initialSearchText: String? = nil
    /// 검색은 한 번에 검색어 하나만 받으므로, 부모가 돌려준 리터럴 표현이 있으면 첫 번째를, 없으면 입력 그대로 쓴다.
    var additionalSearchTerms: (String) -> [String] = { _ in [] }
    /// `controller.state`가 `.ready`/`.failed`로 확정될 때마다 보고한다.
    var onAvailabilityChange: ((Bool) -> Void)? = nil
    @State private var controller = RhwpViewerController()

    var body: some View {
        if HWPViewerBundle.isBundled {
            VStack(spacing: 0) {
                toolbar
                Divider()
                ZStack {
                    RhwpWebViewRepresentable(documentData: documentData, controller: controller)
                    statusOverlay
                }
            }
            .onChange(of: controller.state) { _, newState in
                switch newState {
                case .ready:
                    onAvailabilityChange?(true)
                    if let initialSearchText, !initialSearchText.isEmpty {
                        let resolvedTerm = additionalSearchTerms(initialSearchText).first ?? initialSearchText
                        controller.searchQuery = resolvedTerm
                    }
                case .failed:
                    onAvailabilityChange?(false)
                case .idle, .loadingViewer, .loadingDocument:
                    break
                }
            }
        } else {
            // ⚠️ 리소스 번들 누락에 대비해, 조용히 크래시하는 대신 안내 문구를 보여준다.
            VStack(spacing: 8) {
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("rhwp 웹 뷰어 자산을 찾을 수 없습니다.")
                    .foregroundStyle(.secondary)
                Text("Resources/hwp_viewer.html이 앱 번들에 포함됐는지 확인해주세요.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { onAvailabilityChange?(false) }
        }
    }

    @ViewBuilder
    /// 검색창(입력 + "N/M" 일치 개수 + 이전/다음)과 확대/축소/원본크기 버튼 툴바. `.ready`일 때만 보인다.
    /// `@Bindable var controller = controller`는 `$controller.searchQuery` 바인딩을 얻기 위한 셰도잉이다.
    private var toolbar: some View {
        if case .ready = controller.state {
            @Bindable var controller = controller
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("검색", text: $controller.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit { controller.goToNextSearchMatch() }

                if !controller.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(controller.searchMatchCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button {
                        controller.goToPreviousSearchMatch()
                    } label: {
                        Image(systemName: "chevron.up")
                            .foregroundStyle(Color("AccentColor"))
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.searchMatchCount == 0)
                    .help("이전 일치 항목")

                    Button {
                        controller.goToNextSearchMatch()
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(Color("AccentColor"))
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.searchMatchCount == 0)
                    .help("다음 일치 항목")
                }

                Spacer(minLength: 8)

                // 강조색 12% 원형 배경 + 35% 테두리(28pt) 스타일은 `OutlineQuickViewWindowContent.header`와 같다.
                // 원본 크기 아이콘은 심볼 폭이 넓어 12pt(확대/축소는 14pt)여야 시각적 크기가 맞는다.
                Button {
                    controller.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                        .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("확대")

                Button {
                    controller.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                        .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("축소")

                Button {
                    controller.resetZoom()
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                        .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("원본 크기 (\(Int((controller.zoomScale * 100).rounded()))%)")
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch controller.state {
        case .idle, .loadingViewer:
            ProgressView("뷰어를 준비하는 중…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .loadingDocument:
            ProgressView("문서를 여는 중…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("hwp 문서를 열지 못했습니다.")
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                // 자동 재시도(1회)까지 실패했을 때의 수동 재시도 — `RhwpViewerController.retry()`.
                Button("다시 시도") {
                    controller.retry()
                }
                .buttonStyle(.bordered)
                .tint(Color("AccentColor"))
                .padding(.top, 4)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .ready:
            EmptyView()
        }
    }
}

/// 실제 `WKWebView`에 대한 참조를 들고 있다가, SwiftUI 쪽 액션(검색·줌·페이지 이동)이
/// 일어날 때 웹뷰 안 JS 함수를 직접 호출하는 명령형(imperative) 브릿지.
///
/// `hwp_viewer.js`가 노출하는 `window.rhwp*` 진입점만 호출한다(rhwp의 나머지 편집 API는
/// "원본 보기"에 필요 없다). 모든 페이지를 한 번에 그리므로 `rhwpGoToPage`는 "해당 페이지로
/// 스크롤"이다 — `goToNext`/`goToPrevious`/`currentPage`는 UI 버튼 없이 남겨 둔 재사용용이다.
@MainActor
@Observable
final class RhwpViewerController {
    enum LoadState: Equatable {
        case idle
        /// WKWebView가 로컬 hwp_viewer.html/js/wasm을 아직 로딩 중 — 이 동안은
        /// `window.rhwpLoadDocument`가 아직 정의돼 있지 않을 수 있어 호출하지 않는다.
        case loadingViewer
        /// 뷰어 페이지는 로드됐고, 문서 바이트를 WASM 파서에 넘겨 파싱 중.
        case loadingDocument
        case ready(pageCount: Int)
        case failed(String)
    }

    /// `RhwpWebViewRepresentable.makeNSView`/`makeUIView`가 실제 `WKWebView`가
    /// 만들어지는 대로 연결해 준다. 뷰가 SwiftUI 계층에서 소유하므로 순환 참조를
    /// 막기 위해 `weak`로 둔다.
    weak var webView: WKWebView?
    private(set) var state: LoadState = .loadingViewer
    private(set) var currentPage: Int = 0
    /// `window.rhwpSetZoom(scale)`과 짝을 이룬다. 1.0 = 100%.
    private(set) var zoomScale: CGFloat = 1.0

    /// `hwp_viewer.html`의 `window.onerror`/`unhandledrejection` 캡처가 보내는
    /// 메시지를 쌓아 둔다. 실패 상태 문구에 그대로 이어 붙여서, "JavaScript
    /// 예외가 발생했습니다" 대신 실제 브라우저 에러가 화면에 보이게 한다.
    private(set) var debugLog: [String] = []

    func appendDebugMessage(_ message: String) {
        debugLog.append(message)
        print("[RhwpWebViewer JS] \(message)")
    }

    private func composedFailureMessage(_ base: String) -> String {
        guard !debugLog.isEmpty else { return base }
        return base + "\n\n[디버그 로그]\n" + debugLog.joined(separator: "\n")
    }

    /// `Coordinator.webView(_:didFinish:)`가 로컬 HTML 로딩이 끝난 시점에 호출.
    func loadDocument(data: Data) {
        guard let webView else { return }
        state = .loadingDocument
        currentPage = 0
        zoomScale = 1.0
        // 이전 문서의 검색 상태가 남지 않도록 비운다(`searchQuery`의 didSet이 결과를 초기화한다).
        searchQuery = ""
        let base64 = data.base64EncodedString()
        webView.callAsyncJavaScript(
            "return await window.rhwpLoadDocument(base64)",
            arguments: ["base64": base64],
            in: nil,
            in: .page
        ) { [weak self] result in
            self?.handleLoadResult(result)
        }
    }

    func goToNext() {
        guard case .ready(let pageCount) = state, currentPage + 1 < pageCount else { return }
        goToPage(currentPage + 1)
    }

    func goToPrevious() {
        guard case .ready = state, currentPage > 0 else { return }
        goToPage(currentPage - 1)
    }

    /// 확대/축소 범위(0.5~3.0, 0.1 단위)는 `pdfSearchBar`/`HWPViewerPane.searchAndZoomBar`와 같다.
    static let minZoom: CGFloat = 0.5
    static let maxZoom: CGFloat = 3.0
    static let zoomStep: CGFloat = 0.1

    func zoomIn() {
        setZoom(min(Self.maxZoom, zoomScale + Self.zoomStep))
    }

    func zoomOut() {
        setZoom(max(Self.minZoom, zoomScale - Self.zoomStep))
    }

    func resetZoom() {
        setZoom(1.0)
    }

    private func setZoom(_ scale: CGFloat) {
        guard let webView, case .ready = state else { return }
        let previousZoom = zoomScale
        zoomScale = scale
        webView.callAsyncJavaScript(
            "return await window.rhwpSetZoom(scale)",
            arguments: ["scale": scale],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            let jsErrorMessage: String?
            switch result {
            case .success(let value):
                jsErrorMessage = (value as? [String: Any])?["error"] as? String
            case .failure(let error):
                jsErrorMessage = hwpJavaScriptErrorDescription(error)
            }
            if let jsErrorMessage {
                self.zoomScale = previousZoom
                print("[RhwpViewerController] 확대/축소 실패: \(jsErrorMessage)")
            }
        }
    }

    // MARK: - 검색(2026-08-16 추가)

    /// 검색창과 양방향 바인딩된다(`PDFSearchController.query`와 같은 패턴) — 값이 바뀔 때마다 재검색한다.
    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            performSearch()
        }
    }
    private(set) var searchMatchCount: Int = 0
    private(set) var currentSearchMatchIndex: Int = 0

    var searchMatchCountText: String {
        searchMatchCount == 0 ? "0/0" : "\(currentSearchMatchIndex + 1)/\(searchMatchCount)"
    }

    /// `window.rhwpSearchText(query)`로 일치 개수를 받아온다. 빈 검색어면 JS 호출 없이 상태만 비운다.
    private func performSearch() {
        currentSearchMatchIndex = 0
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let webView, !trimmed.isEmpty else {
            searchMatchCount = 0
            return
        }
        webView.callAsyncJavaScript(
            "return await window.rhwpSearchText(query)",
            arguments: ["query": trimmed],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let dict = value as? [String: Any]
                if let errorMessage = dict?["error"] as? String {
                    print("[RhwpViewerController] 검색 실패: \(errorMessage)")
                    self.searchMatchCount = 0
                    return
                }
                self.searchMatchCount = (dict?["count"] as? NSNumber)?.intValue ?? 0
                if self.searchMatchCount > 0 {
                    self.goToSearchMatch(0)
                }
            case .failure(let error):
                print("[RhwpViewerController] 검색 실패: \(hwpJavaScriptErrorDescription(error))")
                self.searchMatchCount = 0
            }
        }
    }

    func goToNextSearchMatch() {
        guard searchMatchCount > 0 else { return }
        currentSearchMatchIndex = (currentSearchMatchIndex + 1) % searchMatchCount
        goToSearchMatch(currentSearchMatchIndex)
    }

    func goToPreviousSearchMatch() {
        guard searchMatchCount > 0 else { return }
        currentSearchMatchIndex = (currentSearchMatchIndex - 1 + searchMatchCount) % searchMatchCount
        goToSearchMatch(currentSearchMatchIndex)
    }

    /// `window.rhwpGoToSearchMatch(index)`로 해당 일치 항목이 있는 페이지로 스크롤한다.
    private func goToSearchMatch(_ index: Int) {
        guard let webView else { return }
        webView.callAsyncJavaScript(
            "return await window.rhwpGoToSearchMatch(index)",
            arguments: ["index": index],
            in: nil,
            in: .page
        ) { result in
            let jsErrorMessage: String?
            switch result {
            case .success(let value):
                jsErrorMessage = (value as? [String: Any])?["error"] as? String
            case .failure(let error):
                jsErrorMessage = hwpJavaScriptErrorDescription(error)
            }
            if let jsErrorMessage {
                print("[RhwpViewerController] 검색 결과 이동 실패: \(jsErrorMessage)")
            }
        }
    }

    /// `Coordinator.webView(_:didFail:)`가 로컬 HTML 로딩 자체가 실패했을 때 호출.
    func markViewerLoadFailed(_ message: String) {
        state = .failed(composedFailureMessage(message))
    }

    /// WebContent 프로세스 종료(RunningBoard/XPC 관련 로그)는 가끔 일어나는 복구 가능한 이벤트다.
    /// `Coordinator.webViewWebContentProcessDidTerminate(_:)`가 호출하며, 처음 1회는 뷰어 페이지를
    /// 자동으로 다시 로드하고 또 종료되면 "다시 시도" 버튼이 있는 실패 화면을 보여준다.
    private var crashRetryCount = 0
    private static let maxCrashRetries = 1

    func handleWebContentProcessCrash() {
        appendDebugMessage("WebContent 프로세스가 종료됨(크래시) — RunningBoard/XPC 관련 시스템 로그는 Xcode 콘솔 참고")
        guard let webView else {
            state = .failed(composedFailureMessage("뷰어 프로세스가 종료됐습니다."))
            return
        }
        if crashRetryCount < Self.maxCrashRetries {
            crashRetryCount += 1
            state = .loadingViewer
            webView.load(URLRequest(url: HWPViewerBundle.indexURL))
        } else {
            state = .failed(composedFailureMessage("뷰어 프로세스가 반복해서 종료됐습니다. '다시 시도'를 눌러 다시 시도해 주세요."))
        }
    }

    /// `RhwpWebViewerPane`의 실패 화면 "다시 시도" 버튼이 호출한다.
    func retry() {
        guard let webView else { return }
        crashRetryCount = 0
        debugLog.removeAll()
        searchQuery = ""
        state = .loadingViewer
        webView.load(URLRequest(url: HWPViewerBundle.indexURL))
    }

    private func goToPage(_ page: Int) {
        guard let webView else { return }
        let previousPage = currentPage
        currentPage = page
        webView.callAsyncJavaScript(
            "return await window.rhwpGoToPage(pageNum)",
            arguments: ["pageNum": page],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            // JS는 예외 대신 `{ error: "..." }`를 정상 반환하므로(`hwpJavaScriptErrorDescription` 참고) `.success`의 `error` 키를 먼저 확인한다.
            let jsErrorMessage: String?
            switch result {
            case .success(let value):
                jsErrorMessage = (value as? [String: Any])?["error"] as? String
            case .failure(let error):
                jsErrorMessage = hwpJavaScriptErrorDescription(error)
            }
            if let jsErrorMessage {
                // 페이지 이동 실패로 문서 전체를 실패 상태로 만들지 않는다 — 이전 페이지 번호로 되돌리고 콘솔에만 남긴다.
                self.currentPage = previousPage
                print("[RhwpViewerController] 페이지 이동 실패: \(jsErrorMessage)")
            }
        }
    }

    private func handleLoadResult(_ result: Result<Any, Error>) {
        switch result {
        case .success(let value):
            let dict = value as? [String: Any]
            if let errorMessage = dict?["error"] as? String {
                state = .failed(composedFailureMessage(errorMessage))
                return
            }
            if let pageCount = (dict?["pageCount"] as? NSNumber)?.intValue {
                state = .ready(pageCount: pageCount)
            } else {
                state = .failed(composedFailureMessage("문서를 읽었지만 페이지 수를 확인할 수 없습니다."))
            }
        case .failure(let error):
            state = .failed(composedFailureMessage(hwpJavaScriptErrorDescription(error)))
        }
    }
}

#if os(macOS)
struct RhwpWebViewRepresentable: NSViewRepresentable {
    let documentData: Data
    let controller: RhwpViewerController

    func makeNSView(context: Context) -> WKWebView {
        // 문서 로딩은 `didFinish`가 아니라 JS의 "뷰어 준비 완료" 신호(`onReady`)로 시작한다(HWPWebViewSupport.swift 참고).
        let view = WKWebView(frame: .zero, configuration: HWPViewerBundle.makeConfiguration(
            onDebugMessage: controller.appendDebugMessage,
            onReady: { controller.loadDocument(data: documentData) }
        ))
        view.navigationDelegate = context.coordinator
        controller.webView = view
        view.load(URLRequest(url: HWPViewerBundle.indexURL))
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> RhwpViewerCoordinator {
        RhwpViewerCoordinator(controller: controller)
    }
}
#else
struct RhwpWebViewRepresentable: UIViewRepresentable {
    let documentData: Data
    let controller: RhwpViewerController

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: HWPViewerBundle.makeConfiguration(
            onDebugMessage: controller.appendDebugMessage,
            onReady: { controller.loadDocument(data: documentData) }
        ))
        view.navigationDelegate = context.coordinator
        controller.webView = view
        view.load(URLRequest(url: HWPViewerBundle.indexURL))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> RhwpViewerCoordinator {
        RhwpViewerCoordinator(controller: controller)
    }
}
#endif

/// macOS/iOS 두 `RhwpWebViewRepresentable` 변형이 공유하는 내비게이션 델리게이트.
///
/// 문서 로딩 트리거는 `didFinish`가 아니라 `onReady`(JS의 준비 신호)에 있다 — `didFinish`가
/// 모듈 스크립트 실행 완료보다 먼저 올 수 있어서다. 이 코디네이터는 에러 처리(로딩 실패/크래시)만 담당한다.
final class RhwpViewerCoordinator: NSObject, WKNavigationDelegate {
    let controller: RhwpViewerController

    init(controller: RhwpViewerController) {
        self.controller = controller
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        controller.markViewerLoadFailed("뷰어 페이지 로딩 실패: \(hwpJavaScriptErrorDescription(error))")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        controller.markViewerLoadFailed("뷰어 페이지 로딩 실패: \(hwpJavaScriptErrorDescription(error))")
    }

    /// WebContent 렌더러 프로세스가 죽으면 호출된다 — `RhwpViewerController.handleWebContentProcessCrash()` 참고.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        controller.handleWebContentProcessCrash()
    }
}
