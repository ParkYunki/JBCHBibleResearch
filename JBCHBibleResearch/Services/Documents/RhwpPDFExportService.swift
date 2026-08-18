//
//  RhwpPDFExportService.swift
//  JBCHBibleResearch
//
//  [2026-08-16 신설] 사용자 요청 — "현재 pdf는 네이티브 뷰어와 동일하므로
//  존재 이유가 없음. https://github.com/edwardkim/rhwp 이부분에서 pdf 부분을
//  확인해보고 WKWebView 취약점 범주가 그대로 재발할 수 있는 접근이라 해도
//  한번 구현테스트를 확인할 수 있도록." 조사 결과 — edwardkim/rhwp README의
//  로드맵을 직접 확인하니 "다양한 출력 포맷(PDF, DOCX 등)"은 v2.0.0(아직
//  멀었다, 현재는 v0.7.15 "0.5→1.0 뼈대" 단계)에 배정된 미착수 기능이다 —
//  즉 rhwp/rhwp-studio 어느 버전에도 PDF 변환 API 자체는 없다(이전 조사 —
//  DocumentViewerView.swift의 HWPViewerMode 주석 — 와 일치). 대신 rhwp는
//  `renderPageSvg(page_num)`(페이지 단위 SVG 문자열)는 이미 갖고 있다.
//
//  사용자가 참고로 든 https://github.com/postmelee/alhangeul-macos 의 실제
//  PDF 내보내기(`Sources/HostApp/Services/RhwpStudioPagePDFRenderer.swift`)가
//  바로 이 SVG를 오프스크린 WKWebView에 넣고 `WKWebView.createPDF(configuration:)`
//  로 한 쪽씩 PDF로 바꾼 뒤 PDFKit으로 이어붙이는 방식이었다 — 이 파일은 그
//  방식을 이 프로젝트의 기존 `hwpviewer://` 스킴 핸들러 + `hwp_viewer.html`
//  인프라(이번 세션에 크래시/로딩 버그 둘 다 고쳐 이미 검증됨) 위에 그대로
//  재현한다.
//
//  ⚠️ [알려진 위험, 2026-08-16 실기기에서 실제로 재현됨] 이건 WKWebView를
//  하나 더(화면에 보이지 않는 오프스크린 용도로) 띄우는 접근이라, 이번
//  세션 내내 겪은 것과 같은 범주(App Sandbox/타이밍/커스텀 스킴)의 문제가
//  재발할 수 있다고 미리 경고해 뒀는데, 실기기 테스트에서 그대로 재현됐다:
//
//      Error acquiring assertion: <Error Domain=RBSServiceErrorDomain Code=1
//      "(target is not running or doesn't have entitlement
//      com.apple.runningboard.assertions.webkit AND originator doesn't have
//      entitlement com.apple.runningboard.assertions.webkit)" ...>
//
//  원인 — 처음 버전은 `WKWebView(frame:configuration:)`로 뷰만 만들고 어떤
//  윈도우/뷰 계층에도 붙이지 않았다("SwiftUI 뷰 계층 밖에 순수 오프스크린
//  으로 둔다"는 게 원래 의도였다). WebKit의 WebContent(별도 프로세스)는
//  RunningBoard(iOS/iPadOS의 프로세스 생명주기 관리자, 최신 macOS도 XPC
//  서비스 관리에 일부 공유)로부터 "이 프로세스가 실제로 화면에 보여지고
//  있다"는 어서션을 못 받으면 위 에러로 실행을 거부한다 — 즉 진짜 윈도우에
//  붙어 있지 않은 WKWebView는 WebContent 프로세스를 정상적으로 못 띄운다는
//  뜻이다(alhangeul-macos의 `RhwpStudioPagePDFRenderer`가 "하드닝된 별도
//  웹뷰"라고 부른 게 실제로는 여전히 진짜 윈도우/뷰 계층에는 붙어 있었을
//  가능성이 높다 — 그 세부 배선까지는 읽은 소스에 없었다).
//
//  수정 — 화면 밖으로 멀리(예: x: -20000) 옮긴 실제 윈도우(macOS는
//  `NSWindow`, iOS/iPadOS는 `UIWindow`)에 이 웹뷰를 붙여 둔다 — 사용자
//  눈에는 안 보이지만("화면 밖" 좌표라 어느 디스플레이에도 걸치지 않음)
//  OS 입장에서는 "진짜 화면에 있는 윈도우"라 RunningBoard가 정상적으로
//  어서션을 내준다. `attachToHiddenWindow`/`detachFromWindow` 참고.
//

import Foundation
import PDFKit
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// hwp/hwpx 문서를 rhwp(WASM)의 페이지별 SVG(`renderPageSvg`) → 오프스크린
/// `WKWebView.createPDF` 경로로 PDF `Data`를 만드는 서비스. `HWPToPDFPane`
/// (DocumentViewerView.swift)이 이 서비스를 호출한다.
///
/// [2026-08-16 텍스트 추출 폴백 추가] `extractPlainText(documentData:)`도
/// 같이 제공한다 — hwp-swift 네이티브 파서가 못 여는 문서의 텍스트 추출
/// 폴백(`DocumentTextExtractionService.extractHWPViaRhwp` 참고)이 이미
/// 검증된 "오프스크린 웹뷰에 rhwp로 문서 로드" 인프라를 그대로 재사용한다 —
/// `createPDF` 호출이 없어(순수 JS/WASM만 씀) PDF 내보내기보다 낮은 위험으로
/// 기대한다.
///
/// alhangeul-macos의 `RhwpStudioPagePDFRenderer`와 달리(비영속 데이터
/// 스토어, JS 실행 금지, 엄격한 CSP로 감싼 별도 하드닝 웹뷰) 여기서는 이미
/// 검증된 `HWPViewerBundle.makeConfiguration`(우리 자신이 만든 로컬
/// `hwpviewer://` 콘텐츠만 신뢰하고, 문서 바이트도 이 앱 안에서만 오가므로
/// 원본이 신뢰할 수 없는 외부 콘텐츠는 아니다)을 그대로 재사용한다 — 대신
/// 다른 앱들처럼 실제 문서(신뢰 안 되는 hwp/hwpx 바이트)를 이미 파싱해
/// 렌더링하는 데는 이 스킴 핸들러를 그대로 쓰고 있었으므로 신뢰 경계가 이미
/// 동일하다.
@MainActor
final class RhwpPDFExportService: NSObject {
    enum ExportError: LocalizedError {
        case documentLoadFailed(String)
        case missingPageDimensions(Int)
        case pageSvgFailed(Int, String)
        case invalidPDFPageData(Int)
        case mergeFailed
        case timedOut
        case textExtractionFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .documentLoadFailed(let message):
                return "문서를 열지 못했습니다: \(message)"
            case .missingPageDimensions(let page):
                return "\(page + 1)쪽의 크기 정보를 가져오지 못했습니다."
            case .pageSvgFailed(let page, let message):
                return "\(page + 1)쪽을 SVG로 만들지 못했습니다: \(message)"
            case .invalidPDFPageData(let page):
                return "\(page + 1)쪽 PDF 데이터가 올바르지 않습니다."
            case .mergeFailed:
                return "각 쪽을 하나의 PDF로 합치지 못했습니다."
            case .timedOut:
                return "PDF 변환용 뷰어 준비가 시간 내에 끝나지 않았습니다."
            case .textExtractionFailed(let page, let message):
                return "\(page + 1)쪽 텍스트를 가져오지 못했습니다: \(message)"
            }
        }
    }

    /// SwiftUI 뷰 계층과는 무관하지만(사용자에게 보이지 않는다는 뜻), 실제
    /// 윈도우(`attachToHiddenWindow` 참고)에는 붙어 있는 웹뷰 — 순수하게 JS
    /// 실행 + `createPDF` 스냅샷 용도로만 쓴다. "SwiftUI 뷰 계층 밖"과 "AppKit/
    /// UIKit 윈도우 밖"은 서로 다른 얘기라는 걸 실기기 RunningBoard 에러로
    /// 확인했다 — 위 [알려진 위험] 섹션 참고.
    private var webView: WKWebView?
    private var readyContinuation: CheckedContinuation<Void, Error>?

    #if os(macOS)
    private var hostWindow: NSWindow?
    #else
    private var hostWindow: UIWindow?
    #endif

    /// 문서 전체를 PDF `Data`로 변환한다. `onProgress`는 매 페이지 렌더링
    /// 직전에 `(완료한 쪽 수, 전체 쪽 수)`로 호출된다.
    func exportPDF(documentData: Data, onProgress: ((Int, Int) -> Void)? = nil) async throws -> Data {
        defer { detachFromWindow() }
        let view = try await prepareWebView()
        let pageCount = try await loadDocument(documentData: documentData, webView: view)

        let combined = PDFDocument()
        for pageIndex in 0..<pageCount {
            onProgress?(pageIndex, pageCount)
            let pageData = try await renderPagePDF(pageIndex: pageIndex, webView: view)
            guard let pagePDF = PDFDocument(data: pageData), let page = pagePDF.page(at: 0) else {
                throw ExportError.invalidPDFPageData(pageIndex)
            }
            combined.insert(page, at: combined.pageCount)
        }
        onProgress?(pageCount, pageCount)

        guard let data = combined.dataRepresentation() else {
            throw ExportError.mergeFailed
        }
        return data
    }

    /// [2026-08-16 추가] 사용자 지적 — hwp-swift 네이티브 파서가 특정 문서를
    /// 못 여는 사례(`DocumentTextExtractionService.swift` 상단 주석 참고)에
    /// 대응하는 텍스트 추출 폴백. `exportPDF`와 같은 "오프스크린 웹뷰에 문서를
    /// 로드" 인프라를 재사용하되, `createPDF`(화면 합성 스냅샷이 필요해 실기기
    /// RunningBoard 문제가 발생했던 지점)는 전혀 호출하지 않고 `hwp_viewer.js`의
    /// `window.rhwpGetPageText`(순수 JS/WASM 호출)만 쓴다 — 그래서 PDF
    /// 내보내기보다 실패 가능성이 낮을 것으로 기대한다(다만 오프스크린 웹뷰
    /// 자체의 위험 범주는 여전히 남아 있다 — 위 [알려진 위험] 참고).
    func extractPlainText(documentData: Data) async throws -> [String] {
        defer { detachFromWindow() }
        let view = try await prepareWebView()
        let pageCount = try await loadDocument(documentData: documentData, webView: view)

        var pages: [String] = []
        pages.reserveCapacity(pageCount)
        for pageIndex in 0..<pageCount {
            let result = try await callAsyncJS(
                "return await window.rhwpGetPageText(pageIndex)",
                arguments: ["pageIndex": pageIndex],
                webView: view
            )
            guard let dict = result as? [String: Any] else {
                throw ExportError.textExtractionFailed(pageIndex, "응답을 해석하지 못했습니다.")
            }
            if let errorMessage = dict["error"] as? String {
                throw ExportError.textExtractionFailed(pageIndex, errorMessage)
            }
            pages.append(dict["text"] as? String ?? "")
        }
        return pages
    }

    /// `exportPDF`/`extractPlainText`가 공유하는 "문서를 base64로 넘겨 열고
    /// 페이지 수를 받는다" 단계.
    private func loadDocument(documentData: Data, webView: WKWebView) async throws -> Int {
        let base64 = documentData.base64EncodedString()
        let loadResult = try await callAsyncJS(
            "return await window.rhwpLoadDocument(base64)",
            arguments: ["base64": base64],
            webView: webView
        )
        guard let loadDict = loadResult as? [String: Any] else {
            throw ExportError.documentLoadFailed("문서 로딩 응답을 해석하지 못했습니다.")
        }
        if let errorMessage = loadDict["error"] as? String {
            throw ExportError.documentLoadFailed(errorMessage)
        }
        guard let pageCount = (loadDict["pageCount"] as? NSNumber)?.intValue, pageCount > 0 else {
            throw ExportError.documentLoadFailed("페이지 수를 확인할 수 없습니다.")
        }
        return pageCount
    }

    /// 오프스크린 웹뷰를 새로 만들어 `hwp_viewer.html`을 로드하고, JS가 보내는
    /// "준비 완료" 신호(`hwpViewerReady`)까지 기다린다 — 화면에 보이는 웹 탭
    /// (`RhwpWebViewerPane`)과 똑같이 `didFinish`가 아니라 이 신호를 쓴다
    /// (이유는 그쪽 상단 주석 참고 — 이번 세션에 실측으로 확인한 레이스
    /// 컨디션).
    private func prepareWebView() async throws -> WKWebView {
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 1000),
            configuration: HWPViewerBundle.makeConfiguration(
                onDebugMessage: { message in
                    print("[RhwpPDFExport JS] \(message)")
                },
                onReady: { [weak self] in
                    self?.readyContinuation?.resume()
                    self?.readyContinuation = nil
                }
            )
        )
        self.webView = view
        attachToHiddenWindow(view)

        // `onReady` 클로저는 위에서 configuration을 만들 때 이미 self에 캡처돼
        // 있으므로, 여기서 continuation을 등록한 "다음에" load를 시작해야
        // "로드가 먼저 끝나고 준비 신호가 continuation 등록보다 먼저 오는"
        // 레이스가 없다 — RhwpWebViewerPane.swift의 같은 패턴을 그대로 따른다.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.readyContinuation = continuation
            view.load(URLRequest(url: HWPViewerBundle.indexURL))
            // 준비 신호(`onReady`)가 영영 안 올 수도 있는 경우(예: 로드 실패,
            // WebContent 프로세스 크래시)에 대비한 안전장치 — 그대로 두면
            // exportPDF가 영원히 멈춘다. 15초 안에 안 오면 타임아웃으로
            // continuation을 정리한다.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, self.readyContinuation != nil else { return }
                self.readyContinuation?.resume(throwing: ExportError.timedOut)
                self.readyContinuation = nil
            }
        }
        return view
    }

    private func renderPagePDF(pageIndex: Int, webView: WKWebView) async throws -> Data {
        let svgResult = try await callAsyncJS(
            "return await window.rhwpGetPageSvg(pageIndex)",
            arguments: ["pageIndex": pageIndex],
            webView: webView
        )
        guard let svgDict = svgResult as? [String: Any] else {
            throw ExportError.missingPageDimensions(pageIndex)
        }
        if let errorMessage = svgDict["error"] as? String {
            throw ExportError.pageSvgFailed(pageIndex, errorMessage)
        }
        guard let svg = svgDict["svg"] as? String,
              let width = (svgDict["width"] as? NSNumber)?.doubleValue, width > 0,
              let height = (svgDict["height"] as? NSNumber)?.doubleValue, height > 0
        else {
            throw ExportError.missingPageDimensions(pageIndex)
        }

        // 이 페이지 크기에 맞춰 오프스크린 웹뷰의 프레임을 다시 잡고, body를
        // 이 페이지의 SVG 하나로 교체한다 — alhangeul-macos의
        // `RhwpStudioPagePDFRenderer`와 같은 방식(페이지별 SVG →
        // `WKWebView.createPDF`). `svg`를 `callAsyncJavaScript`의
        // `arguments`로 넘기면 WebKit이 안전하게 JS 문자열로 직렬화해 주므로
        // 직접 이스케이프할 필요가 없다.
        webView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        _ = try await callAsyncJS(
            "document.body.style.margin = '0'; document.body.innerHTML = svgMarkup; return true;",
            arguments: ["svgMarkup": svg],
            webView: webView
        )

        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)

        return try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// [2026-08-16 추가] 실기기 RunningBoard 에러 수정 — 위 [알려진 위험]
    /// 섹션 참고. 화면 밖 멀리 떨어진 좌표에 실제 윈도우를 하나 만들어 그
    /// 안에 웹뷰를 넣는다 — 사용자에게는 안 보이지만, OS 입장에서는 "화면에
    /// 있는 진짜 윈도우"라 WebContent 프로세스가 RunningBoard 어서션을
    /// 정상적으로 받을 수 있다.
    private func attachToHiddenWindow(_ webView: WKWebView) {
        #if os(macOS)
        let window = NSWindow(
            contentRect: CGRect(x: -20000, y: -20000, width: 800, height: 1000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        // `orderFront`가 있어야 AppKit이 이 윈도우를 "실제로 화면에 있는
        // 윈도우"로 취급한다 — `-20000` 좌표라 어차피 어느 디스플레이에도
        // 걸치지 않아 사용자 눈엔 안 보인다.
        window.orderFront(nil)
        self.hostWindow = window
        #else
        let frame = CGRect(x: -20000, y: -20000, width: 800, height: 1000)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // foregroundActive 씬이 없어도(예: 백그라운드 변환 중) 연결된 씬이
            // 하나라도 있으면 그걸 쓴다 — deprecated init(frame:) 폴백을
            // 최대한 피하기 위함.
            window = UIWindow(windowScene: scene)
        } else {
            // 연결된 UIWindowScene이 전혀 없는 극단적 예외 상황에서만 도달 —
            // UIKit이 이 경우를 위한 대체 API를 제공하지 않으므로 의도적으로
            // deprecated API를 쓴다(RhwpPDFExportService.makeLegacyFallbackWindow 참고).
            window = Self.makeLegacyFallbackWindow(frame: frame)
        }
        window.frame = frame
        let controller = UIViewController()
        controller.view = webView
        window.rootViewController = controller
        // `isHidden = false`가 있어야 UIKit이 이 윈도우를 활성 씬에 실제로
        // 붙은 윈도우로 취급한다 — 화면 밖 좌표라 사용자 눈엔 안 보인다.
        window.isHidden = false
        self.hostWindow = window
        #endif
    }

    #if !os(macOS)
    // 연결된 UIWindowScene이 전혀 없을 때만 호출되는 극단적 폴백 —
    // UIKit이 대체 API를 제공하지 않아 deprecated init(frame:)을 여기 한
    // 곳에만 격리해 의도를 명시한다.
    @available(iOS, deprecated: 26.0, message: "연결된 UIWindowScene이 없을 때의 마지막 폴백 — 대체 API 없음")
    private static func makeLegacyFallbackWindow(frame: CGRect) -> UIWindow {
        UIWindow(frame: frame)
    }
    #endif

    /// 변환이 끝나면(성공/실패 무관) 숨김 윈도우와 웹뷰를 놓아준다 —
    /// WebContent 프로세스를 필요 이상으로 오래 붙잡아 두지 않기 위해서다.
    private func detachFromWindow() {
        #if os(macOS)
        hostWindow?.contentView = nil
        hostWindow?.orderOut(nil)
        #else
        hostWindow?.isHidden = true
        hostWindow?.rootViewController = nil
        #endif
        hostWindow = nil
        webView = nil
    }

    private func callAsyncJS(_ script: String, arguments: [String: Any], webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
