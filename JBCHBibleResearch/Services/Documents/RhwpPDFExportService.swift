//
//  RhwpPDFExportService.swift
//  JBCHBibleResearch
//
//  rhwp(WASM)의 페이지별 SVG를 PDF로 바꾸거나 페이지 텍스트를 추출하는 서비스.
//
//  rhwp에는 PDF 변환 API가 없고 `renderPageSvg(page_num)`(페이지 단위 SVG)만
//  있다. 그래서 각 쪽의 SVG를 오프스크린 WKWebView에 넣어
//  `WKWebView.createPDF(configuration:)`로 한 쪽씩 PDF로 만든 뒤
//  PDFKit으로 이어붙인다. 기존 `hwpviewer://` 스킴 핸들러와 `hwp_viewer.html`
//  인프라를 재사용한다.
//
//  ⚠️ 웹뷰는 화면 밖 좌표(x: -20000)의 실제 윈도우(NSWindow/UIWindow)에 붙여 둬야
//  한다. 윈도우에 붙지 않은 WKWebView는 RunningBoard
//  어서션(`com.apple.runningboard.assertions.webkit`)을 받지 못해
//  WebContent 프로세스 실행이
//  거부된다(`attachToHiddenWindow`/`detachFromWindow`).
//

import Foundation
import PDFKit
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// hwp/hwpx 문서를 rhwp(WASM)의 페이지별 SVG → 오프스크린
/// `WKWebView.createPDF` 경로로 PDF `Data`로 만드는 서비스.
/// `HWPToPDFPane`(DocumentViewerView.swift)이 호출한다.
///
/// `extractPlainText(documentData:)`는 hwp-swift 파서가 못 여는 문서의
/// 텍스트 추출
/// 폴백(`DocumentTextExtractionService.extractHWPViaRhwp`)이 같은
/// 오프스크린 웹뷰 인프라를 재사용하도록 제공한다. `createPDF`를 호출하지 않는다.
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

    /// 화면에는 보이지 않지만 실제 윈도우(`attachToHiddenWindow`)에는 붙어 있는 웹뷰.
    /// JS 실행과 `createPDF` 스냅샷 용도로만 쓴다.
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

    /// 텍스트 추출 폴백. `exportPDF`와 같은 오프스크린 웹뷰 인프라를 쓰되 `createPDF`
    /// 없이 `window.rhwpGetPageText`(순수 JS/WASM)만 호출해 쪽별 텍스트 배열을
    /// 돌려준다.
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

    /// 오프스크린 웹뷰를 만들어 `hwp_viewer.html`을 로드하고 JS의 "준비 완료"
    /// 신호(`hwpViewerReady`)까지 기다린다. `didFinish`는 모듈 스크립트 실행 완료와
    /// 동기화되지 않아 쓰지 않는다(`RhwpWebViewerPane`과 동일).
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

        // continuation을 등록한 뒤에 load를 시작해야 준비 신호가 등록보다 먼저 도착하는
        // 레이스가 없다.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.readyContinuation = continuation
            view.load(URLRequest(url: HWPViewerBundle.indexURL))
            // 준비 신호가 영영 안 올 수 있는 경우(로드 실패, WebContent 크래시)에 대비해
            // 15초 후 타임아웃으로 continuation을 정리한다.
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

        // 이 페이지 크기에 맞춰 프레임을 다시 잡고 body를 이 페이지의 SVG로 교체한다.
        // `svg`를 `arguments`로 넘기면 WebKit이 안전하게 직렬화하므로 직접
        // 이스케이프하지 않는다.
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

    /// 화면 밖 좌표에 실제 윈도우를 만들어 웹뷰를 넣는다. 사용자에게는 안 보이지만 OS는 화면에 있는
    /// 윈도우로 취급해 WebContent 프로세스가 RunningBoard 어서션을 받는다.
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
        // `orderFront`가 있어야 AppKit이 실제 화면에 있는 윈도우로 취급한다.
        window.orderFront(nil)
        self.hostWindow = window
        #else
        let frame = CGRect(x: -20000, y: -20000, width: 800, height: 1000)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // foregroundActive 씬이 없어도(예: 백그라운드) 연결된 씬이 있으면 그걸
            // 써서 deprecated init(frame:) 폴백을 피한다.
            window = UIWindow(windowScene: scene)
        } else {
            // 연결된 UIWindowScene이 전혀 없을 때만 도달한다. 대체 API가 없어
            // deprecated API를 쓴다(`makeLegacyFallbackWindow`).
            window = Self.makeLegacyFallbackWindow(frame: frame)
        }
        window.frame = frame
        let controller = UIViewController()
        controller.view = webView
        window.rootViewController = controller
        // `isHidden = false`가 있어야 UIKit이 활성 씬에 붙은 윈도우로 취급한다.
        window.isHidden = false
        self.hostWindow = window
        #endif
    }

    #if !os(macOS)
    // 연결된 UIWindowScene이 없을 때만 호출되는 폴백. 대체 API가 없어 deprecated
    // init(frame:)을 이 한 곳에 격리한다.
    @available(iOS, deprecated: 26.0, message: "연결된 UIWindowScene이 없을 때의 마지막 폴백 — 대체 API 없음")
    private static func makeLegacyFallbackWindow(frame: CGRect) -> UIWindow {
        UIWindow(frame: frame)
    }
    #endif

    /// 변환이 끝나면(성공/실패 무관) 숨김 윈도우와 웹뷰를 해제해 WebContent 프로세스를 오래
    /// 붙잡지 않는다.
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
