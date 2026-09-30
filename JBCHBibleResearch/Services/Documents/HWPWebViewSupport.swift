//
//  HWPWebViewSupport.swift
//  JBCHBibleResearch
//
//  rhwp(WKWebView + WASM) 웹 뷰어가 쓰는 번들 스킴 핸들러와 JS 메시지 채널.
//
//  커스텀 URL 스킴(`hwpviewer://`)을 쓰는 이유: `hwp_viewer.js`(ES 모듈)가
//  `rhwp.js`를 import하고 `rhwp.js`가 다시 `fetch`로 wasm을 받는데,
//  `file://` 스킴에서는 WKWebView(특히 App Sandbox)의 fetch가 지원되지 않거나
//  제약이 많다. `WKURLSchemeHandler`는 UI 프로세스(앱 자신)에서 실행되므로
//  WebContent 프로세스의 샌드박스 제약 없이 `Bundle.main`에서 바이트를 읽어 돌려준다.
//  html/js/wasm이 같은 스킴+호스트(`hwpviewer://local/`) 아래 있어 상대 경로
//  import/fetch도 같은 origin으로 취급되므로 CORS 문제가 없다.
//
//  디버그 채널: `hwp_viewer.html`의 인라인(항상 실행되는) 스크립트가
//  `window.onerror`/`unhandledrejection`을 `hwpDebug` 핸들러로 보낸다.
//  모듈 스크립트 로딩이 실패해도 실제 브라우저 에러 문구를 화면에 띄울 수 있다.
//

import Foundation
import WebKit

/// hwp 뷰어 번들(html/js/wasm)이 항상 이 URL로 열린다 — `HWPViewerSchemeHandler`가
/// 이 스킴의 모든 요청을 가로채 `Bundle.main`의 실제 리소스로 응답한다.
enum HWPViewerBundle {
    static let scheme = "hwpviewer"
    static let indexURL = URL(string: "hwpviewer://local/hwp_viewer.html")!
    /// `hwp_viewer.html`의 인라인 스크립트가
    /// `window.webkit.messageHandlers.<이 이름>`으로 브라우저 콘솔/전역 에러를
    /// 보낸다.
    static let debugMessageHandlerName = "hwpDebug"
    /// `hwp_viewer.js`가
    /// `window.rhwpLoadDocument`/`rhwpGoToPage`/`rhwpSetZoom`
    /// 정의 직후 이 이름으로 "준비 완료" 신호를 한 번 보낸다. 본문은 쓰지 않는다.
    static let readyMessageHandlerName = "hwpViewerReady"

    /// `WKWebViewConfiguration`에 스킴 핸들러, 디버그 메시지 채널, "뷰어 준비 완료"
    /// 채널을 등록해 돌려준다.
    ///
    /// `WKNavigationDelegate.didFinish`는 `<script
    /// type="module">`(rhwp.js import + wasm init 포함) 실행 완료와
    /// 동기화되지 않아 `window.rhwpLoadDocument is not a function`이
    /// 재현됐다. 호출부는 `didFinish`가 아니라 `onReady` 신호를 받은 뒤
    /// `loadDocument`를 호출해야 한다.
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

    /// hwp_viewer.html/js가 앱 번들에 포함됐는지 확인한다. 자산이 빠졌을 때 빈 화면 대신
    /// 안내 문구를 보여주기 위한 사전 검사다.
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

        // `URLResponse(mimeType:)`의 mimeType은 실제 HTTP
        // `Content-Type` 헤더로 이어지지 않는다.
        // `WebAssembly.instantiateStreaming`은
        // `Response.headers`의 content-type이 정확히
        // "application/wasm"인지 검사하므로, `HTTPURLResponse` +
        // `headerFields`로 헤더를 명시해야 한다.
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
        // 요청별 상태를 들고 있지 않아 정리할 것이 없다.
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js": return "text/javascript"
        // application/wasm이어야
        // `WebAssembly.instantiateStreaming`(빠른 경로)이 동작한다.
        // rhwp.js는 다른 타입이면 `WebAssembly.instantiate`로 대체하도록 방어돼
        // 있지만 정확히 맞춰 준다.
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}

/// `hwp_viewer.html`의 인라인 스크립트가 보내는 디버그
/// 메시지(`window.onerror`/`unhandledrejection`)를 `onMessage`로
/// 전달하는 핸들러. 본문은 JS 쪽에서 조립한 문자열 하나다.
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
/// 않고 신호가 왔다는 사실만 쓴다.
final class HWPReadyMessageHandler: NSObject, WKScriptMessageHandler {
    private let onReady: () -> Void

    init(onReady: @escaping () -> Void) {
        self.onReady = onReady
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onReady()
    }
}

/// `callAsyncJavaScript` 실패 오류를 사람이 읽을 문자열로 바꾼다.
/// `hwp_viewer.js` 진입점은 예외를 throw하지 않고 `{ error }`를 반환하므로, 이
/// 함수는 JS 호출 자체가 안 된 전송 계층 실패에만 쓰인다.
///
/// `WKJavaScriptExceptionMessageErrorKey`라는 Swift 심볼은 SDK에 없지만
/// `NSError.userInfo`는 `[String: Any]`라 문자열
/// 키(`WKJavaScriptExceptionMessage` 등)로 조회할 수 있다. 없으면
/// `localizedDescription`으로 대체한다.
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
