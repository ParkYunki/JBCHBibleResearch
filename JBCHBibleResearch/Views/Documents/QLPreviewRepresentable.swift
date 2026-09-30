//
//  QLPreviewRepresentable.swift
//  JBCHBibleResearch
//
//  QuickLook 기반 미리보기 뷰(현재 `.pages` 뷰어에 사용, 다른 형식에도 재사용 가능). Apple 자체 렌더러를
//  쓰므로 Pages.app 설치 여부와 무관하게 동작한다.
//
//  ⚠️ 순수 "보여주기" API라 문서 텍스트를 앱 코드로 돌려주지 않는다 — 검색은 SwiftTextPages로 추출한
//  `DocumentViewerView.extractedTextPane`이 담당하고, `pagesViewerModeToggle`로 두 화면을 오간다.
//
//  macOS(`QLPreviewView`, 인라인)와 iOS(`QLPreviewController`, 모달형)는 프레임워크·API가 달라
//  `#if os(macOS)`로 분기한다.
//

import SwiftUI

#if os(macOS)
import QuickLookUI

struct QLPreviewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        // security-scoped 북마크로 얻은 URL일 수 있다. QLPreviewView가 자기 타이밍에 파일을 읽으므로
        // 화면에 떠 있는 동안 접근을 열어 두고, `dismantleNSView`에서 닫는다.
        context.coordinator.didStartAccessing = url.startAccessingSecurityScopedResource()

        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        // 같은 URL이면 건너뛴다 — 매번 `previewItem`을 재대입하면 QuickLook이 새로 로드해 화면이 깜박일 수 있다.
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
