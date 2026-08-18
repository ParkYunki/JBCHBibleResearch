//
//  HWPWebViewSupport.swift
//  JBCHBibleResearch
//
//  [2026-08-16 재도입] 사용자 요청 — hwp-swift 네이티브 뷰어만으로는 렌더링이
//  rhwp-studio 온라인 데모만큼 완전하지 않다는 지적을 받아, rhwp(WKWebView + WASM)
//  기반 뷰어를 "두 번째 옵션"으로 다시 추가한다(교체가 아니라 추가 — 사용자가 같은
//  문서를 두 뷰어로 열어 비교할 수 있게 하는 것이 목적, DocumentViewerView.swift의
//  HWPViewerModeToggle 참고).
//
//  이 파일 자체는 이번 세션 초반에 한 번 만들었다가(당시엔 rhwp가 유일한 뷰어였다)
//  hwp-swift 전면 교체 때 삭제했던 것을 구조 변경 없이 그대로 되살린 것이다 — 스킴
//  핸들러/디버그 채널 로직은 그때도 실제로는 문제가 없었다(HTML 로딩 자체는
//  성공했었다 — `navigationFailed`에서 `javascriptFailed`로 증상이 바뀐 것이 그
//  증거). 원인 불명으로 남았던 부분은 `callAsyncJavaScript`가 JS 함수 본문을
//  실행하기 전에 실패하는 문제였다 — 당시 Xcode/DerivedData 상태 문제로 추정하고
//  클린 재시작을 권했었는데, 그 뒤로 프로젝트가 여러 차례(hwp-swift SPM 의존성
//  추가 등) 다시 빌드되면서 그 상태 자체가 이미 여러 번 갈아엎어졌을 가능성이 커서,
//  이번엔 코드 변경 없이 그대로 재시도해 본다.
//
//  왜 커스텀 URL 스킴(`hwpviewer://`)을 쓰는가 — `hwp_viewer.js`(ES 모듈)가
//  `rhwp.js`를 `import`하고, `rhwp.js`가 다시 `fetch(new URL('rhwp_bg.wasm',
//  import.meta.url))`로 wasm 바이너리를 받아오는 경로 전체가 `file://` 스킴이면
//  WKWebView(특히 App Sandbox 안)에서 `fetch()`로 `file://` 리소스를 읽는 것이
//  공식적으로 지원되지 않거나 제약이 많다. `WKURLSchemeHandler`는 **UI
//  프로세스(이 앱 자신)**에서 실행되므로, 리소스를 읽는 데 WebContent 자식
//  프로세스의 샌드박스 제약이 전혀 개입하지 않는다 — `Bundle.main`에서 직접
//  바이트를 읽어 그대로 돌려준다. html/js/wasm이 전부 같은 스킴+호스트
//  (`hwpviewer://local/`) 아래 있으므로 상대 경로 import/fetch도 "같은 origin"으로
//  취급돼 CORS 문제도 생기지 않는다. Capacitor/Ionic 등 WKWebView에 오프라인 웹
//  번들을 넣는 앱들이 흔히 쓰는 정석적인 방식이다.
//
//  DocumentViewerView.swift(S6, rhwp 웹 뷰어 탭) 하나만 이 파일을 쓴다 — 이전엔
//  HWPTextExtractor.swift(오프스크린 텍스트 추출)도 공유했지만, 이번 재도입은
//  "뷰어만"이 사용자 요청 범위라 텍스트 추출은 여전히 hwp-swift
//  (DocumentTextExtractionService.swift)가 전담한다.
//
//  브라우저 콘솔/전역 에러를 직접 Swift로 실어 나르는 디버그 채널을 포함한다 —
//  `hwp_viewer.html`의 인라인(모듈이 아닌, 항상 실행되는) 스크립트가
//  `window.onerror`/`unhandledrejection`을 가로채
//  `window.webkit.messageHandlers.hwpDebug`로 보낸다. 모듈 스크립트 로딩 자체가
//  실패해도 이 인라인 스크립트는 영향을 받지 않으므로, 실패하면 "JavaScript
//  예외가 발생했습니다" 대신 실제 브라우저 에러 문구가 화면에 그대로 뜬다.
//

import Foundation
import WebKit

/// hwp 뷰어 번들(html/js/wasm)이 항상 이 URL로 열린다 — `HWPViewerSchemeHandler`가
/// 이 스킴의 모든 요청을 가로채 `Bundle.main`의 실제 리소스로 응답한다.
enum HWPViewerBundle {
    static let scheme = "hwpviewer"
    static let indexURL = URL(string: "hwpviewer://local/hwp_viewer.html")!
    /// `hwp_viewer.html`의 인라인 스크립트가 `window.webkit.messageHandlers.<이 이름>`
    /// 으로 브라우저 콘솔/전역 에러를 보낸다 — Swift 쪽은 `makeConfiguration(onDebugMessage:)`
    /// 로 등록한 핸들러에서 받는다.
    static let debugMessageHandlerName = "hwpDebug"
    /// [2026-08-16 추가] `window.rhwpLoadDocument`/`rhwpGoToPage`/`rhwpSetZoom`
    /// 세 함수가 실제로 정의된 직후 `hwp_viewer.js`가 이 이름으로 "준비 완료"
    /// 신호를 한 번 보낸다 — 아래 `makeConfiguration(onReady:)` 참고. 정적
    /// 텍스트 하나만 보내면 되므로 별도 페이로드 형식은 두지 않는다.
    static let readyMessageHandlerName = "hwpViewerReady"

    /// `WKWebViewConfiguration`에 스킴 핸들러 + 디버그 메시지 채널 + (선택)
    /// "뷰어 준비 완료" 채널을 등록해서 돌려준다 — 호출부(rhwp 웹 뷰어용
    /// `RhwpWebViewRepresentable`)가 매번 새 `WKWebView`를 만들 때 이 설정을
    /// 그대로 쓰면 된다.
    ///
    /// [2026-08-16 추가] `onReady` 매개변수 — `WKNavigationDelegate.didFinish`
    /// (페이지 로딩 완료)가 `<script type="module">`(hwp_viewer.js, rhwp.js
    /// import + wasm init 포함)의 실제 실행 완료와 정확히 동기화되지 않아
    /// `TypeError: window.rhwpLoadDocument is not a function`이 실제로
    /// 재현됐다(RhwpWebViewerPane.swift 상단 주석 참고). 그래서 "페이지 로딩
    /// 완료"가 아니라 "JS가 명시적으로 준비됐다고 알려주는 시점"을 기다리는
    /// 방식으로 바꿨다 — hwp_viewer.js가 세 함수를 다 정의한 직후
    /// `hwpViewerReady` 메시지를 보내고, `RhwpWebViewRepresentable`은
    /// `didFinish`가 아니라 이 신호를 받았을 때 `loadDocument`를 호출한다.
    static func makeConfiguration(onDebugMessage: @escaping (String) -> Void, onReady: @escaping () -> Void) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(HWPViewerSchemeHandler(), forURLScheme: scheme)
        configuration.userContentController.add(
            HWPDebugMessageHandler(onMessage: onDebugMessage),
            name: debugMessageHandlerName
        )
        configuration.userContentController.add(
            HWPReadyMessageHandler(onReady: onReady),
            name: readyMessageHandlerName
        )
        return configuration
    }

    /// hwp_viewer.html/js가 실제로 앱 번들에 포함됐는지(=Resources/에 넣은 파일들이
    /// Xcode 리소스 빌드 단계에 실제로 잡혔는지) 확인하는 용도. `.load(URLRequest(
    /// url: indexURL))`은 스킴 핸들러가 알아서 처리하므로 이 존재 확인이 필수는
    /// 아니지만, 자산이 빠졌을 때 "빈 화면"이 아니라 명확한 안내 문구를 보여주려고
    /// 미리 검사한다.
    static var isBundled: Bool {
        Bundle.main.url(forResource: "hwp_viewer", withExtension: "html") != nil
    }
}

/// `hwpviewer://local/<파일명>` 요청을 `Bundle.main`의 같은 이름 리소스로
/// 그대로 응답하는 최소 구현. 캐싱/조건부 요청(`If-Modified-Since` 등)은
/// 다루지 않는다 — 로컬 정적 자산이라 매번 그대로 돌려줘도 비용이 크지 않다.
final class HWPViewerSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let filename = url.lastPathComponent
        let ext = (filename as NSString).pathExtension
        let resourceName = (filename as NSString).deletingPathExtension

        guard !resourceName.isEmpty,
              let fileURL = Bundle.main.url(forResource: resourceName, withExtension: ext),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        // [2026-08-16 수정] 기존엔 `URLResponse(mimeType:)`를 썼는데, 이건 이
        // 응답의 "타입 힌트" 프로퍼티일 뿐 실제 HTTP `Content-Type` 헤더로
        // 이어지지 않는다 — WKURLSchemeHandler로 응답한 리소스를 `fetch()`로
        // 읽으면 그 `Response` 객체엔 `Content-Type` 헤더 자체가 비어 있었다.
        // `WebAssembly.instantiateStreaming`은 스펙상 `Response.headers.get(
        // 'content-type')`이 정확히 "application/wasm"인지를 검사하므로(단순
        // mimeType 힌트가 아니라 진짜 헤더), 우리 wasm 응답만 이 검사를 통과하지
        // 못해 "Unexpected response MIME type. Expected 'application/wasm'"로
        // 실패하고 있었다(RhwpWebViewerPane.swift 상단 주석 참고).
        // `HTTPURLResponse` + `headerFields`로 명시적인 `Content-Type` 헤더를
        // 채워야 `fetch()` 쪽에서 진짜 헤더로 읽힌다.
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: ext),
                "Content-Length": String(data.count)
            ]
        ) ?? URLResponse(
            url: url,
            mimeType: Self.mimeType(for: ext),
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // 취소된 요청(예: 페이지 이동)을 위한 정리 — 이 핸들러는 요청마다 별도
        // 상태를 들고 있지 않으므로 할 일이 없다.
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js": return "text/javascript"
        // application/wasm이어야 `WebAssembly.instantiateStreaming`(빠른 경로)이
        // 동작한다 — rhwp.js는 이 MIME 타입이 아니어도 `WebAssembly.instantiate`
        // (조금 느린 경로)로 자동 대체하도록 이미 방어돼 있다(rhwp.js
        // `__wbg_load` 참고), 그래도 정확히 맞춰 주는 편이 낫다.
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}

/// 위 파일 상단 주석 참고 — `hwp_viewer.html`의 인라인 스크립트가 보내는 디버그
/// 메시지(브라우저 `window.onerror`/`unhandledrejection`)를 그대로 받아
/// `onMessage` 클로저에 전달하는 최소 `WKScriptMessageHandler`. 메시지 본문은
/// 문자열 하나로 통일했다(JS 쪽에서 이미 사람이 읽을 문자열로 조립해서 보낸다 —
/// hwp_viewer.html 참고).
final class HWPDebugMessageHandler: NSObject, WKScriptMessageHandler {
    private let onMessage: (String) -> Void

    init(onMessage: @escaping (String) -> Void) {
        self.onMessage = onMessage
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage((message.body as? String) ?? String(describing: message.body))
    }
}

/// `HWPViewerBundle.readyMessageHandlerName` 채널 전용 — 메시지 본문은 보지
/// 않는다(hwp_viewer.js가 어떤 값을 보내든 "신호가 왔다"는 사실 자체만 쓴다).
final class HWPReadyMessageHandler: NSObject, WKScriptMessageHandler {
    private let onReady: () -> Void

    init(onReady: @escaping () -> Void) {
        self.onReady = onReady
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onReady()
    }
}

/// [2026-08-15 원 작성 당시 수정 사유 유지] 원래는
/// `NSError.userInfo[WKJavaScriptExceptionMessageErrorKey]`로 실제 JS 예외
/// 메시지를 꺼내려 했으나, 그 이름이 실존하지 않는 심볼이라 Xcode 컴파일
/// 에러로 확인됐다(WebKit이 JS 예외의 상세 메시지를 꺼낼 수 있는 공식
/// 문서화된 `NSError.userInfo` 키를 공개하지 않는다). 그래서 근본적으로 접근을
/// 바꿨다 — hwp_viewer.js의 두 진입점(`rhwpLoadDocument`/`rhwpGoToPage`)이
/// JS 예외를 throw하지 않고 직접 try/catch해서 `{ error: "메시지" }`를 정상
/// 반환값으로 돌려준다. 그러면 Swift 쪽은 `callAsyncJavaScript`의
/// `.success(value)` 분기에서 `value` 안의 `error` 키를 확인하면 되고, 이
/// 함수(`.failure(error)` 쪽만 다루는)는 정말로 "JS 함수 호출 자체가 안 된"
/// 드문 전송 계층 실패에만 쓰인다.
///
/// [2026-08-16 추가] 실제로 그 "드문 전송 계층 실패"가 재현됐다(`didFinish`
/// 레이스 컨디션 — RhwpWebViewerPane.swift 상단 주석 참고) — 그때
/// `localizedDescription`은 "JavaScript 예외가 발생했습니다"라는 일반 문구만
/// 줘서 원인 파악에 시간이 걸렸다. `WKJavaScriptExceptionMessageErrorKey`라는
/// **Swift 심볼**은 이 SDK에 없지만, `NSError.userInfo`는 그냥
/// `[String: Any]` 딕셔너리라 컴파일 타임 심볼 없이도 **문자열 키**로 실제
/// WebKit이 채워 넣는 값(`WKJavaScriptExceptionMessage` 등, 진단 중 실측으로
/// 확인함)을 직접 조회할 수 있다 — 있으면 훨씬 구체적인 메시지를 보여주고,
/// 없으면 기존처럼 일반 문구로 대체한다.
func hwpJavaScriptErrorDescription(_ error: Error) -> String {
    let nsError = error as NSError
    if let jsMessage = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String, !jsMessage.isEmpty {
        var detail = "JS 예외: \(jsMessage)"
        if let line = nsError.userInfo["WKJavaScriptExceptionLineNumber"] {
            detail += " (line \(line))"
        }
        if let sourceURL = nsError.userInfo["WKJavaScriptExceptionSourceURL"] {
            detail += " @ \(sourceURL)"
        }
        return detail
    }
    return nsError.localizedDescription
}
