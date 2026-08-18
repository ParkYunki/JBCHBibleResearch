//
//  QLPreviewRepresentable.swift
//  JBCHBibleResearch
//
//  [2026-08-16 신설] 사용자 요청 — "pages 뷰어는 QLPreviewController로 보여지게
//  할 것." QuickLook은 Apple 자체 렌더러(Finder 스페이스바 미리보기와 같은
//  경로)를 그대로 재사용하므로 Pages.app 설치 여부와 무관하게 동작하고, 우리가
//  IWA를 직접 그려낼 필요가 없다 — 이전 조사(대화 참고)에서 확인한 대로
//  Pages.app이 없어도 macOS/iOS 모두 시스템에 iWork용 QuickLook 렌더러가
//  내장돼 있다.
//
//  ⚠️ 다만 이건 순수 "보여주기"용 API라 문서 텍스트를 앱 코드로 돌려주지
//  않는다(검토 결과) — 그래서 검색은 이 뷰가 아니라 SwiftTextPages로 추출한
//  `DocumentViewerView.extractedTextPane`이 계속 담당한다. 이 화면과 추출
//  텍스트 화면을 세그먼트로 오갈 수 있게 한 게 `DocumentViewerView.
//  pagesViewerModeToggle` — hwp의 `hwpViewerModeToggle`(hwp-swift 네이티브 ↔
//  rhwp 웹 뷰어)과 같은 이유·같은 모양이다.
//
//  macOS(QuickLookUI의 인라인 `QLPreviewView`)와 iOS(QuickLook의 모달형
//  `QLPreviewController`, `QLPreviewControllerDataSource`로 항목 하나만 공급)가
//  서로 다른 프레임워크·API 모양이라 #if os(macOS)로 완전히 분기한다. 이름은
//  `.pages` 전용으로 짓지 않았다 — 다른 형식에도 그대로 재사용 가능.
//

import SwiftUI

#if os(macOS)
import QuickLookUI

struct QLPreviewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        // security-scoped 북마크로 얻은 URL일 수 있다 — QLPreviewView는 우리가
        // 직접 데이터를 읽어 넘기는 API가 아니라 URL만 쥐고 있다가 자기 타이밍에
        // 파일을 읽으므로, 한 번 읽고 끝나는 `readSecurityScopedData`(다른
        // 뷰모델들의 패턴) 대신 이 뷰가 화면에 떠 있는 동안 계속 접근을 열어
        // 둬야 한다 — 아래 `dismantleNSView`에서 짝을 맞춰 닫는다.
        context.coordinator.didStartAccessing = url.startAccessingSecurityScopedResource()

        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        // [2026-08-15 PDFKitRepresentable 깜박임 fix와 같은 이유] 재계산마다
        // `previewItem`을 무조건 다시 대입하면 QuickLook이 매번 새로 로드하며
        // 화면이 깜박일 수 있다 — 이미 같은 URL을 보여주고 있으면 건너뛴다.
        let current: QLPreviewItem? = nsView.previewItem
        if current?.previewItemURL == url { return }
        nsView.previewItem = url as QLPreviewItem
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: Coordinator) {
        if coordinator.didStartAccessing {
            coordinator.url.stopAccessingSecurityScopedResource()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator {
        let url: URL
        var didStartAccessing = false
        init(url: URL) { self.url = url }
    }
}
#else
import QuickLook

struct QLPreviewRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        context.coordinator.didStartAccessing = url.startAccessingSecurityScopedResource()
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    static func dismantleUIViewController(_ uiViewController: QLPreviewController, coordinator: Coordinator) {
        if coordinator.didStartAccessing {
            coordinator.url.stopAccessingSecurityScopedResource()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        var didStartAccessing = false
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
#endif
