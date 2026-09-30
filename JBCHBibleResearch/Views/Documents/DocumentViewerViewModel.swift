//
//  DocumentViewerViewModel.swift
//  JBCHBibleResearch
//
//  S6(연구문서 원문 뷰어) 상태/데이터 접근. "원본 보기"(네이티브 렌더링)와 "추출 텍스트"
//  (선택 가능한 순수 텍스트) 두 모드를 지원한다 — hwp 뷰어는 시각적 렌더링이라 텍스트를
//  드래그 선택하기 어려워 추출 텍스트 패널이 필요하다. 원본 바이트/PDFDocument/이미지는
//  재계산마다 읽지 않도록 onAppear 이후 한 번만 읽어 캐싱한다.
//

import Foundation
import SwiftData
import Observation
import PDFKit
import BibleResearchModels
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// `PlatformImage` typealias — 이 파일과 `DocumentViewerView.swift`가 함께 쓰며,
// internal이라 같은 모듈의 다른 파일에서도 별도 import 없이 쓸 수 있다.
#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

@MainActor
@Observable
final class DocumentViewerViewModel {
    let document: SourceDocument
    private(set) var resolvedURL: URL?
    private(set) var textLines: [DocumentText] = []
    /// `onAppear`에서 한 번만 읽어 캐싱한다 — 바디 재계산마다 새로 만들어 `PDFView.document`에 다시 대입하면
    /// 스크롤/확대 위치까지 초기화되며 깜박인다(`PDFKitRepresentable.updateNSView`의 동일성 검사와 짝).
    private(set) var pdfDocument: PDFDocument?

    /// `HWPViewerPane`이 `HwpDocumentLoader().load(from:)`에 넘길 원본 바이트. `pdfDocument`와 같은 이유로
    /// `onAppear` 이후 한 번만 읽어 캐싱한다(재계산마다 읽으면 재파싱 낭비/깜박임).
    private(set) var hwpFileData: Data?
    /// 이미지 문서 원본. `readSecurityScopedData`(보안 스코프 열고/닫는 짝)로 읽어 담아 둔다 —
    /// `PlatformImage(contentsOfFile:)`로 직접 읽으면 스코프가 닫혀 있을 때(앱 컨테이너 밖 파일 등) 에러 없이
    /// nil만 돌아와 창을 닫았다 다시 열면 실패할 수 있다. `originalPane`은 파일을 직접 읽지 않고 이 값만 본다.
    private(set) var loadedImage: PlatformImage?

    /// 업로드 시 `DocumentUploadService.generateConvertedPDF`가 미리 만든 `ConvertedPDF` 파일을 읽어 둔 값 —
    /// 있으면 `HWPToPDFPane`이 바로 보여준다. 레코드가 없는 기존 문서는 nil이며 열 때 즉석 변환한다.
    private(set) var convertedPDFDocument: PDFDocument?

    /// `resolvedURL`이 가리키는 원본 파일의 iCloud 다운로드 상태(`UbiquitousFileDownloadMonitor` 참고).
    /// `DocumentViewerView`가 다운로드 중이면 진행률, 실패면 에러 메시지를 보여준다.
    private(set) var downloadStatus: UbiquitousFileDownloadMonitor.Status = .ready
    private var downloadMonitor: UbiquitousFileDownloadMonitor?

    /// `convertedPDFDocument`가 가리키는 별도 파일의 다운로드 상태 — 원본과 독립적이라 상태가 다를 수 있다.
    private(set) var convertedPDFDownloadStatus: UbiquitousFileDownloadMonitor.Status = .ready
    private var convertedPDFDownloadMonitor: UbiquitousFileDownloadMonitor?

    private let modelContext: ModelContext

    init(document: SourceDocument, modelContext: ModelContext) {
        self.document = document
        self.modelContext = modelContext
    }

    func onAppear() {
        // originalFilePath가 있으면 그걸로(다른 기기에서도 항상 성공), 없으면 북마크로 폴백하고 성공 시 소급 채운다.
        // 해석 에러를 `try?`로 삼키면 `resolvedURL`이 nil이 되어 다운로드 모니터가 시작되지 않고 진단 정보 없는
        // 폴백 메시지만 보이므로, 실제 사유를 `downloadStatus`에 담아 화면에 보여준다.
        do {
            resolvedURL = try DocumentUploadService.resolveOriginalFileURL(for: document, context: modelContext)
        } catch {
            resolvedURL = nil
            let message = "원본 파일 위치를 확인하지 못했습니다: \(error)"
            downloadStatus = .failed(message)
            // 화면 메시지는 창을 닫으면 사라지므로 상세 오류는 로그 파일에도 남긴다.
            DocumentViewerErrorLog.log(context: document.originalFilename, message: message)
        }

        // 다운로드 모니터가 먼저 상태를 확인하고(로컬에 있으면 즉시, 아니면 다운로드 요청 후 진행률 관찰)
        // `.ready`일 때만 실제 파일 읽기(`loadPrimaryFileContent`)를 수행한다.
        // `.doc`는 `supportsNativePreview`가 항상 false라 추출 텍스트 패널만 보이므로 제외한다 —
        // 보지 않을 원본을 iCloud에서 몰래 받아오는 부작용을 피하기 위함.
        if document.originalFormat == .doc {
            downloadStatus = .ready
        } else if let resolvedURL {
            let monitor = UbiquitousFileDownloadMonitor { [weak self] status in
                guard let self else { return }
                self.downloadStatus = status
                switch status {
                case .ready:
                    self.loadPrimaryFileContent(from: resolvedURL)
                case .failed(let message):
                    // 위 catch 블록과 같은 이유로 로그 파일에 남긴다.
                    DocumentViewerErrorLog.log(context: self.document.originalFilename, message: message)
                case .downloading:
                    break
                }
            }
            downloadMonitor = monitor
            monitor.beginMonitoring(url: resolvedURL)
        }
        // resolvedURL이 nil이면(위 catch에서 처리) `.ready`로 덮어쓰지 않는다 — 방금 담은 실패 사유가 지워진다.

        // hwp/hwpx/docx는 사전 변환된 `ConvertedPDF`(같은 모델·로딩 경로)를 읽는다. 변환 실행
        // (`generateConvertedPDFForDocx`)만 macOS 전용이고 결과 PDF는 iCloud로 동기화되므로, macOS에서 변환된
        // 문서는 iOS에서도 열린다. 예외: iOS에서 직접 업로드한 docx는 변환이 시도되지 않아 PDF가 없다 —
        // macOS 앱에서 재시도(`DocumentsViewModel.retry`)하면 변환된다.
        if (document.originalFormat == .hwp || document.originalFormat == .hwpx || document.originalFormat == .docx),
           let convertedPDF = (document.convertedPDFs ?? []).first,
           let containerURL = FileManager.default.url(
               forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
           ) {
            // `ConvertedPDF.pdfPath`는 컨테이너의 "Documents/" 바로 아래부터의 상대 경로다.
            let pdfURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(convertedPDF.pdfPath, isDirectory: false)

            // 원본과 같은 이유로 이 PDF도 독립적으로 다운로드 상태를 확인한다.
            let monitor = UbiquitousFileDownloadMonitor { [weak self] status in
                guard let self else { return }
                self.convertedPDFDownloadStatus = status
                switch status {
                case .ready:
                    self.convertedPDFDocument = PDFDocument(url: pdfURL)
                case .failed(let message):
                    // 위 catch 블록과 같은 이유. 원본과 구분되도록 컨텍스트에 "(PDF 변환)"을 덧붙인다.
                    DocumentViewerErrorLog.log(context: "\(self.document.originalFilename) (PDF 변환)", message: message)
                case .downloading:
                    break
                }
            }
            convertedPDFDownloadMonitor = monitor
            monitor.beginMonitoring(url: pdfURL)
        }
        loadTextLines()
    }

    /// `downloadStatus`가 `.ready`가 된 시점(이미 로컬에 있었거나 다운로드가 막 끝남)에 원본 파일 바이트를 읽어 캐싱한다.
    /// hwp/hwpx/이미지는 큰 파일(스캔 강의안 등 수십MB)일 수 있어 `Task.detached`로 메인 액터 밖에서 읽는다 —
    /// 다운로드 직후 메인 스레드에서 동기 읽기를 하면 iOS 워치독이 앱을 종료할 수 있다(크래시 로그로 확정된
    /// 원인은 아닌 방어적 조치). 결과만 메인 액터에서 대입하며, `.pdf` 분기는 이 범위 밖이라 그대로 둔다.
    private func loadPrimaryFileContent(from resolvedURL: URL) {
        if document.originalFormat == .pdf {
            pdfDocument = PDFDocument(url: resolvedURL)
        }
        if document.originalFormat == .hwp || document.originalFormat == .hwpx {
            Task { [weak self] in
                let data = await Task.detached(priority: .userInitiated) {
                    try? Self.readSecurityScopedData(from: resolvedURL)
                }.value
                self?.hwpFileData = data
            }
        }
        if document.originalFormat == .image {
            Task { [weak self] in
                let data = await Task.detached(priority: .userInitiated) {
                    try? Self.readSecurityScopedData(from: resolvedURL)
                }.value
                guard let data else { return }
                self?.loadedImage = PlatformImage(data: data)
            }
        }
    }

    /// security-scoped URL에서 파일 바이트를 읽는다 — 접근 권한 열고/닫는 짝(`startAccessingSecurityScopedResource`
    /// / `defer { stop... }`)은 다른 파일 읽기 지점들과 동일하다.
    /// `nonisolated` — 타입이 `@MainActor`라 없으면 `Task.detached` 안에서 호출해도 메인 액터로 홉해
    /// 디스크 읽기가 메인 스레드에서 실행된다. `self`를 건드리지 않는 순수 파일 I/O라 안전하다.
    private nonisolated static func readSecurityScopedData(from url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// `#Predicate`의 옵셔널 관계 비교(`sourceDocument?.id == ...`)는 SwiftData 버전별 지원 범위가 불확실해 쓰지 않고,
    /// 역관계 `SourceDocument.documentTexts`를 그대로 정렬해 쓴다.
    private func loadTextLines() {
        textLines = (document.documentTexts ?? []).sorted {
            ($0.pageNumber, $0.lineIndex) < ($1.pageNumber, $1.lineIndex)
        }
    }

    /// 원본 렌더링(네이티브 뷰어)이 이 형식에서 의미가 있는지. `.doc`/`.pages`는 전용 렌더러가 없어 "추출 텍스트" 탭만 쓴다.
    /// `.docx`는 `DocumentViewerView.docxContent`가 세그먼트 토글("미리보기"/"PDF 변환")로 직접 고르게 해 이 값이
    /// 쓰이지 않지만, `convertedPDFDocument` 유무를 반영해 남겨 둔다.
    var supportsNativePreview: Bool {
        switch document.originalFormat {
        case .pdf, .image, .hwp, .hwpx: return true
        case .docx: return convertedPDFDocument != nil
        case .doc, .pages: return false // [2026-08-16 pages 추가] .doc과 동일 — 추출된 텍스트 뷰로 폴백
        }
    }
}
