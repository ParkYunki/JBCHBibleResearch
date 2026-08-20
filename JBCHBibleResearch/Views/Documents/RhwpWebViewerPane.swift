//
//  RhwpWebViewerPane.swift
//  JBCHBibleResearch
//
//  [2026-08-16 신설] 사용자 요청 — hwp-swift 네이티브 뷰어(DocumentViewerView.swift의
//  HWPViewerPane)만으로는 렌더링이 완전하지 않다는 지적을 받아, rhwp(WKWebView + WASM,
//  https://github.com/edwardkim/rhwp, MIT) 기반 뷰어를 "두 번째 옵션"으로 다시
//  추가한다 — DocumentViewerView.swift의 뷰어 전환 컨트롤(HWPViewerMode)이 이 뷰와
//  hwp-swift 네이티브 뷰 중 하나를 고르게 해 준다. 자세한 설계 배경(왜 WKWebView로
//  돌아왔는지, 왜 `@rhwp/editor`가 아니라 `@rhwp/core`를 쓰는지, `renderPageToCanvas`를
//  고른 이유)은 Resources/hwp_viewer.html 상단 주석에 정리했다.
//
//  이 파일의 구조는 이번 세션 초반 hwp-swift로 교체되기 전 DocumentViewerView.swift
//  안에 있던 HWPViewerController/HWPWebViewRepresentable/HWPViewerCoordinator를
//  그대로 옮겨 온 것이다(같은 파일 안에 두 뷰어 구현이 섞이면 읽기 어려워져 별도
//  파일로 분리했다) — 로직 변경은 없다(호스트 JS 쪽만 SVG → Canvas 렌더링으로
//  바뀌었을 뿐, Swift ↔ JS 브릿지 계약(`rhwpLoadDocument`/`rhwpGoToPage`,
//  `{ pageCount }`/`{ ok }`/`{ error }` 반환 모양)은 그대로다).
//
//  [2026-08-16 참고 조사] 사용자가 실제로 겪은 WebContent 크래시 로그(RunningBoard
//  assertion 획득 실패, "Specified target process ... does not exist" 등)를 보고
//  https://github.com/postmelee/alhangeul-macos (rhwp-studio를 WKWebView에 그대로
//  번들해 signed/notarized DMG로 배포 중인 오픈소스 macOS 앱, 215 stars, MIT)의
//  `Sources/HostApp/Views/RhwpStudioWebView.swift`를 참고 조사했다. 확인한 점:
//  (1) 우리와 거의 같은 entitlements(app-sandbox, network.client 등)로도 실제
//  배포 앱이 문제없이 동작한다 — 즉 앱 엔타이틀먼트를 더 추가해야 하는 문제가
//  아니다. (2) 그 앱도 `WKNavigationDelegate.webViewWebContentProcessDidTerminate`
//  를 구현해 WebContent 프로세스 종료를 "가끔 있는, 복구 가능한 정상 이벤트"로
//  명시적으로 다룬다(`mydocs/tech/project_architecture.md`: "main WebContent
//  process가 종료되면 ... 요청을 무효화하고 늦게 도착한 응답을 무시한다") — 우리
//  `RhwpViewerCoordinator`엔 이 델리게이트 콜백이 아예 없었다. 그래서 이번에
//  `RhwpViewerController.handleWebContentProcessCrash()` + `Coordinator.
//  webViewWebContentProcessDidTerminate(_:)`를 추가했다(자동 1회 재시도 + 수동
//  "다시 시도" 버튼). (3) 그 앱은 `@rhwp/core` 대신 rhwp-studio 전체를 Rust FFI로
//  감싸 번들하는 훨씬 큰 아키텍처를 쓴다 — 우리 규모(뷰어 비교용)에는 과하다고
//  판단해 그대로 따라가지는 않았다.
//
//  [2026-08-16 크래시/로딩 실패 진단 — 해결 완료] rhwp 웹 뷰어가 실기기에서
//  계속 크래시/로딩 실패해, 진단용 임시 뷰어 탭 3단계(단순 WKWebView → 커스텀
//  스킴 핸들러만 → rhwp.js import/wasm init 단독 실행)로 단계별로 변수를
//  하나씩 제거하며 원인을 좁혔다(문제 해결 확인 후 진단용 탭/리소스는 모두
//  제거했다). 처음엔 `log stream`에 찍힌 RunningBoard 거부 로그만 보고 "이
//  Mac의 샌드박스 서브시스템 자체가 손상됐다"고 오판했으나, 단계별 진단
//  결과 실제로는 다음 두 가지 별개의, 앱 코드 안에서 고칠 수 있는 버그였다:
//
//  (1) wasm MIME 타입 버그 — `HWPViewerSchemeHandler`(HWPWebViewSupport.swift)
//  가 wasm 응답에 `URLResponse(mimeType:)`만 썼는데, 이건 "타입 힌트"일 뿐
//  실제 HTTP `Content-Type` 헤더로 이어지지 않는다. `WebAssembly.
//  instantiateStreaming`은 진짜 헤더를 스펙대로 검사하므로 "Unexpected
//  response MIME type. Expected 'application/wasm'"로 항상 실패했다(html/js는
//  이 검사를 안 받아 늘 정상 로드됐다). 수정: `HTTPURLResponse(headerFields:
//  ["Content-Type": ...])`로 명시적인 헤더를 채운다.
//
//  (2) `didFinish` 레이스 컨디션 — 위 (1)을 고친 뒤에도 "JavaScript 예외가
//  발생했습니다"로 실패했는데, `hwpJavaScriptErrorDescription`에 `NSError.
//  userInfo` 원시 조회를 추가해 실제 메시지를 꺼내 보니 `TypeError: window.
//  rhwpLoadDocument is not a function`이었다 — `WKNavigationDelegate.
//  didFinish`(페이지 로딩 완료)가 `hwp_viewer.js`(모듈 스크립트) 실행 완료보다
//  먼저 와서, 함수가 정의되기 전에 Swift가 호출한 것이었다. 수정: `didFinish`에
//  의존하는 대신 `hwp_viewer.js`가 세 `window.rhwp*` 함수를 다 정의한 직후
//  `hwpViewerReady` 전용 메시지 채널로 "준비 완료" 신호를 명시적으로 보내고,
//  Swift는 그 신호를 받았을 때만 문서를 로드한다(`HWPWebViewSupport.swift`의
//  `makeConfiguration(onReady:)`/`HWPReadyMessageHandler`, `RhwpViewerCoordinator`
//  는 이제 에러 처리만 담당) — Capacitor/Ionic류 WKWebView 브릿지의 표준
//  "JS가 준비 신호를 보내고 네이티브는 그걸 기다린다" 패턴.
//
//  두 버그를 모두 고친 뒤 사용자가 실제 hwp 문서 1페이지 렌더링을 확인했다.
//  이어서 "전체페이지가 다 나올 수 있도록" 요청으로, 캔버스 1개에 현재
//  페이지만 그리던 것을 `hwp_viewer.js`의 `renderAllPages`가 모든 페이지를
//  세로로 이어붙여 그리는 방식(pdf 뷰어처럼 스크롤로 전체 문서 보기)으로
//  바꿨다. 검색(`toolbar` 참고)까지 붙인 뒤 사용자가 실기기에서 세 가지를
//  더 지적했다:
//  (3) 확대/축소가 실제로는 안 먹힘 — `Resources/hwp_viewer.html`의
//  `.hwp-page-canvas`에 `max-width: 100%; height: auto;`가 남아 있어서,
//  `hwp_viewer.js`가 인라인으로 넣어 주는 정확한 표시 크기를 컨테이너 너비
//  이하로 다시 눌러 버리고 있었다 — 그 두 CSS 속성을 제거해 고쳤다.
//  (4) 검색 결과 이동이 안 됨 — 처음엔 매치 객체 필드 이름을 몇 가지 후보로
//  추측했는데, 사용자가 실기기 로그로 실제 매치 형태가
//  `{"sec":0,"para":N,"charOffset":N,"length":N}`(페이지 번호 필드 없음)임을
//  확인해 줬다. rhwp.js를 다시 조사해 진짜 API `HwpDocument.getPageOfPosition
//  (section_idx, para_idx)`("위치에 해당하는 글로벌 쪽 번호 반환")를 찾아
//  그걸로 바꿨다(`hwp_viewer.js`의 `parsePageNumber`/`rhwpGoToSearchMatch`
//  참고) — 응답이 순수 숫자 문자열인지 JSON인지 rhwp에 타입 선언이 없어
//  둘 다 시도하고, 실패하면 원본 응답을 디버그 로그로 남긴다.
//  (5) 텍스트 드래그 선택/복사가 안 됨 — 캔버스 렌더링은 DOM에 실제 텍스트가
//  없어 브라우저 기본 선택 자체가 불가능하다(PDF.js 등이 하는 것처럼 캔버스
//  위에 투명한 선택 가능 텍스트 레이어를 별도로 얹어야 한다). rhwp.js의
//  `getPageTextLayout(page_num)`이 "각 TextRun의 위치, 텍스트, 글자별 X 좌표
//  경계값"을 준다고 문서화돼 있어 오버레이를 만들 재료는 있지만, 정확한 JSON
//  필드 이름/좌표 단위를 알려주는 공개 타입 선언이 없어 실제 오버레이 구현
//  전에 원본 데이터를 먼저 봐야 한다 — 문서를 열 때 0쪽의
//  `getPageTextLayout(0)` 원본을 디버그 로그로 남기도록 `rhwpLoadDocument`에
//  추가만 해 뒀다(hwp_viewer.js 참고). 이 로그를 받으면 이어서 실제 오버레이를
//  구현한다 — 아직 화면 동작 변화는 없다.
//

import SwiftUI
import WebKit

/// 페이지(원본 보기)에서 문서 바이트가 준비돼 있을 때 그리는 rhwp 웹 뷰어 화면.
/// 툴바(이전/다음 페이지 + 쪽 번호) + WKWebView 본문 + 로딩/에러 오버레이로
/// 구성된다.
struct RhwpWebViewerPane: View {
    let documentData: Data
    /// [2026-08-20 추가] 사용자 요청 — "hwp 한글파일 클릭시 pdf 탭으로 열리는데,
    /// 해당 내용으로 바로 갈 수 있도록 검색어 자동 하이라이트 기능 추가하고,
    /// 모든 뷰어에 동일하게 추가할 것." `HWPViewerPane`(네이티브 탭)에만 있던
    /// 배선을 이 웹 뷰어 탭에도 똑같이 추가한다 — 문서가 `.ready` 상태가 된
    /// 직후(아래 `.onChange`) `controller.searchQuery`에 대입하면
    /// `RhwpViewerController.searchQuery`의 `didSet`이 알아서 검색을 실행하고
    /// (일치 개수가 1개 이상이면) 첫 매치로 스크롤까지 한다 — 사용자가 직접
    /// 검색창에 입력하는 것과 완전히 같은 경로다.
    var initialSearchText: String? = nil
    /// [2026-08-16 추가] `DocumentViewerView.reportViewerAvailability` 참고 —
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
                        controller.searchQuery = initialSearchText
                    }
                case .failed:
                    onAvailabilityChange?(false)
                case .idle, .loadingViewer, .loadingDocument:
                    break
                }
            }
        } else {
            // ⚠️ 이론상 발생하면 안 된다(Resources/hwp_viewer.html이 항상 함께
            // 번들된다) — 그래도 리소스 번들 문제로 못 찾을 가능성을 대비해
            // 조용히 크래시하는 대신 안내 문구를 보여준다.
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
    /// [2026-08-16 교체] 사용자 요청 — "hwp 뷰어를 pdf뷰어와 UI를 비슷하게 맞출것
    /// (page 이동버튼 삭제, 검색기능 옆에 줌기능 버튼 세개(개요처럼))." 이전/다음
    /// 쪽 버튼 + 쪽 번호 텍스트를 없애고, `HWPViewerPane.searchAndZoomBar`/
    /// `pdfSearchBar`/`OutlineQuickViewWindowContent.header`와 같은 돋보기 아이콘
    /// 3개(확대/축소/원본크기)를 오른쪽에 둔다.
    ///
    /// [2026-08-16 해결] 페이지 이동 버튼을 없앤 대신, `hwp_viewer.js`가 이제
    /// 모든 페이지를 세로로 이어붙여 그린다(`renderAllPages` 참고) — pdf
    /// 뷰어처럼 스크롤로 전체 문서를 볼 수 있다(이전엔 캔버스 1개에 현재
    /// 페이지만 그려서 여러 쪽 문서는 1쪽만 보였다).
    ///
    /// [2026-08-16 추가] 사용자 요청 — "개요 창처럼 검색 기능/검색결과/검색이동...
    /// 동일하게." `pdfSearchBar`/`OutlineQuickViewWindowContent.header`와 정확히
    /// 같은 구성(돋보기 아이콘 + 검색어 입력 + "N/M" 일치 개수 + 이전/다음 버튼)을
    /// 확대/축소 버튼 왼쪽에 둔다. `@Bindable var controller = controller`는
    /// `pdfSearchBar`가 쓰는 것과 같은 셰도잉 패턴 — `$controller.searchQuery`
    /// 양방향 바인딩을 얻기 위해서다.
    ///
    /// ⚠️ [알려진 한계] `rhwp.js`의 `HwpDocument.searchAllText`가 돌려주는 매치
    /// 객체의 정확한 필드 구성(페이지 위치를 어떤 이름으로 담는지)을 알려주는
    /// 공개 타입 선언(.d.ts)이 없다 — `RhwpViewerController.searchMatchCount`
    /// (일치 개수)는 신뢰할 수 있지만, "다음/이전 일치 항목으로 이동"(스크롤)은
    /// `hwp_viewer.js`의 `window.rhwpGoToSearchMatch`가 몇 가지 후보 필드 이름을
    /// 순서대로 시도하는 방식이라 실기기에서 검증이 더 필요하다 — 실패하면
    /// Xcode 콘솔의 `rhwpSearchText` 디버그 로그(매치 객체 원본 JSON)를 보고
    /// 정확한 필드 이름으로 좁힐 수 있다.
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
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.searchMatchCount == 0)
                    .help("이전 일치 항목")

                    Button {
                        controller.goToNextSearchMatch()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.searchMatchCount == 0)
                    .help("다음 일치 항목")
                }

                Spacer(minLength: 8)

                Button {
                    controller.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("확대")

                Button {
                    controller.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("축소")

                Button {
                    controller.resetZoom()
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .buttonStyle(.plain)
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
                // [2026-08-16 추가] WebContent 프로세스 크래시(RunningBoard/XPC
                // 관련 로그) 뒤 자동 재시도(1회)까지 실패하면 이 버튼으로 수동
                // 재시도할 수 있다 — `RhwpViewerController.retry()` 참고.
                Button("다시 시도") {
                    controller.retry()
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .ready:
            EmptyView()
        }
    }
}

/// 실제 `WKWebView`에 대한 참조를 들고 있다가, SwiftUI 쪽 버튼 액션(이전/다음
/// 쪽)이 눌릴 때마다 그 웹뷰 안 JS 함수를 직접 호출하는 명령형(imperative) 브릿지.
///
/// `Resources/hwp_viewer.js`가 `window.rhwpLoadDocument`/`window.rhwpGoToPage`/
/// `window.rhwpSetZoom` 세 함수만 노출하므로, 이 컨트롤러도 그 세 진입점만
/// 호출한다 — rhwp가 노출하는 나머지 수백 개 편집 API(rhwp.d.ts의
/// `HwpDocument`)는 이 앱이 "원본 보기"만 필요하므로 애초에 건드리지 않는다.
///
/// [2026-08-16] 페이지 이동 버튼은 pdf 뷰어 UI 통일 요청으로 제거했지만,
/// `goToNext`/`goToPrevious`/`currentPage`는 남겨 뒀다 — `hwp_viewer.js`가
/// 이제 모든 페이지를 한 번에 그리므로(`toolbar` 상단 주석 참고)
/// `window.rhwpGoToPage`도 "다시 그리기"가 아니라 "해당 페이지로 스크롤"로
/// 의미가 바뀌었다 — UI 버튼 없이도 나중에 재사용 가능.
///
/// [2026-08-16 추가] 문서 내 텍스트 검색 — `hwp_viewer.js`의
/// `window.rhwpSearchText`/`window.rhwpGoToSearchMatch` 두 진입점을 호출한다
/// (아래 검색 관련 프로퍼티/메서드 참고). `toolbar` 상단 주석의 "알려진 한계"도
/// 참고 — 일치 개수는 신뢰할 수 있지만 "이동"은 실기기 검증이 더 필요하다.
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
    /// [2026-08-16 추가] `hwp_viewer.js`의 `window.rhwpSetZoom(scale)`과 짝을
    /// 이룬다 — `RhwpWebViewerPane.zoomButtons`(pdfSearchBar/OutlineQuickView와
    /// 같은 돋보기 아이콘 3개 패턴)가 이 값을 바꾼다. 1.0 = 100%.
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
        // 새 문서를 열면 이전 문서의 검색 상태(검색어/일치 개수)가 그대로
        // 남아 있으면 안 된다 — `searchQuery`의 didSet이 알아서 결과를 비운다
        // (빈 문자열이면 performSearch()가 matchCount를 0으로 되돌린다).
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

    /// [2026-08-16 추가] `RhwpWebViewerPane.zoomButtons`(확대/축소/원본크기 3개
    /// 아이콘)이 호출. 세 메서드 모두 `pdfSearchBar`/`HWPViewerPane.searchAndZoomBar`
    /// 와 같은 범위(0.5~3.0, 0.1 단위)를 쓴다.
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

    /// `RhwpWebViewerPane.toolbar`의 검색창이 `$controller.searchQuery`로
    /// 양방향 바인딩한다 — `PDFSearchController.query`와 같은 패턴(값이 바뀔
    /// 때마다 자동으로 다시 검색한다).
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

    /// `hwp_viewer.js`의 `window.rhwpSearchText(query)`를 호출해 일치 개수를
    /// 받아온다. 검색어가 비어 있으면 JS를 호출하지 않고 바로 상태를 비운다.
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

    /// `hwp_viewer.js`의 `window.rhwpGoToSearchMatch(index)`를 호출해 해당
    /// 일치 항목이 있는 페이지로 스크롤한다 — `toolbar` 상단 주석의 "알려진
    /// 한계" 참고(정확한 필드 이름은 실기기 검증이 더 필요할 수 있다).
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

    /// [2026-08-16 추가] 사용자가 실제로 겪은 크래시(`Error acquiring assertion:
    /// RBS[Service|Assertion]ErrorDomain ...`, `WebContent[pid]`가 재시작되는
    /// 로그)에 대한 대응 — `postmelee/alhangeul-macos`(rhwp-studio를 그대로
    /// 번들해 signed/notarized로 배포 중인 macOS 앱, 215 stars) 소스를 참고했다.
    /// 그 앱의 `RhwpStudioWebView.Coordinator`도 `webViewWebContentProcessDidTerminate`를
    /// 구현해 WebContent 프로세스 종료를 "가끔 있는, 복구 가능한 정상 이벤트"로
    /// 다룬다(`project_architecture.md`: "문서 load identity가 바뀌거나 main
    /// WebContent process가 종료되면 ... 요청을 무효화") — 우리 쪽엔 이 델리게이트
    /// 콜백 자체가 아예 없어서, 프로세스가 죽으면 그냥 `callAsyncJavaScript`가
    /// 조용히 "JavaScript 예외가 발생했습니다"로만 실패하고 끝났다(사용자가 본
    /// 그 화면). 그 자체가 별도 크래시 원인이라기보다, 흔한 크래시를 그냥
    /// 못 받아내고 있었을 뿐일 가능성이 크다.
    ///
    /// `Coordinator.webViewWebContentProcessDidTerminate(_:)`가 호출한다. 1회는
    /// 자동으로 뷰어 페이지를 다시 로드해 보고(alhangeul-macos도 프로세스 종료를
    /// "무효화 후 재시도 가능한" 상태로만 다룬다), 그래도 또 죽으면 사용자가
    /// 수동으로 누를 수 있는 "다시 시도" 버튼이 있는 실패 화면을 보여준다.
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
            // `hwp_viewer.js`는 예외를 throw하지 않고 `{ error: "..." }`를
            // 정상 반환하므로(HWPWebViewSupport.swift `hwpJavaScriptErrorDescription`
            // 상단 주석 참고), 여기서도 `.success` 안의 `error` 키를 먼저 확인한다.
            let jsErrorMessage: String?
            switch result {
            case .success(let value):
                jsErrorMessage = (value as? [String: Any])?["error"] as? String
            case .failure(let error):
                jsErrorMessage = hwpJavaScriptErrorDescription(error)
            }
            if let jsErrorMessage {
                // 페이지 이동 자체가 실패해도 전체 문서를 "실패" 상태로 되돌리진
                // 않는다(이미 열려 있던 페이지는 계속 보여줄 수 있으므로) — 이전
                // 페이지 번호로 되돌리고 조용히 콘솔에만 남긴다.
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
        // [2026-08-16 수정] `onReady` 참고(HWPWebViewSupport.swift) — 문서
        // 로딩은 이제 `didFinish`가 아니라 JS가 보내는 "뷰어 준비 완료" 신호로
        // 시작한다. `documentData`는 이 representable의 로컬 상수라 클로저가
        // 바로 캡처할 수 있다(coordinator를 거칠 필요 없음).
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
/// [2026-08-16 수정] 예전엔 `didFinish`(페이지 로딩 완료) 시점에
/// `controller.loadDocument`를 호출했는데, 실측 결과 `didFinish`가
/// `hwp_viewer.js`(모듈 스크립트, rhwp.js import + wasm init 포함)의 실제
/// 실행 완료보다 먼저 올 수 있다는 게 확인됐다(`TypeError: window.
/// rhwpLoadDocument is not a function` — Xcode 콘솔로 직접 확인). 그래서 문서
/// 로딩 트리거는 `RhwpWebViewRepresentable.makeNSView/makeUIView`의 `onReady`
/// 클로저(JS가 명시적으로 보내는 "준비 완료" 신호)로 옮겼다 — 이 코디네이터는
/// 이제 에러 처리(로딩 실패/크래시)만 담당한다.
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

    /// [2026-08-16 추가] `RhwpViewerController.handleWebContentProcessCrash()`
    /// 상단 주석 참고 — WKWebView의 렌더러 프로세스(WebContent)가 죽으면 macOS가
    /// 이 델리게이트 메서드를 호출한다. 이전엔 이 메서드가 아예 없어서 크래시가
    /// 조용히 "JavaScript 예외가 발생했습니다"로만 보였다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        controller.handleWebContentProcessCrash()
    }
}
