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
import ImageIO
import UniformTypeIdentifiers
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

    // MARK: 이미지 쪽(여러 장 = 한 문서)

    /// 이 문서의 쪽 번호 목록(쪽 행이 없으면 [0] = 원본 1장).
    private(set) var imagePageNumbers: [Int] = [0]
    /// 지금 보는 쪽의 `imagePageNumbers` 안 위치.
    private(set) var currentImagePageIndex: Int = 0
    /// 썸네일 줄용 축소 이미지 — 쪽 번호별. 파일이 아직 이 기기에 없으면 비어 있어 번호만 보인다.
    private(set) var imageThumbnails: [Int: PlatformImage] = [:]
    /// 쪽 추가/삭제 결과 안내. 화면이 알림으로 보여 준 뒤 nil로 지운다.
    var imagePageMessage: String?
    private(set) var isModifyingImagePages = false
    /// 쪽을 넘길 때마다 새로 발급해, 늦게 도착한 이전 쪽의 로딩 결과가 지금 쪽을 덮어쓰지 못하게 한다.
    private var imageLoadToken = UUID()

    private let modelContext: ModelContext

    init(document: SourceDocument, modelContext: ModelContext) {
        self.document = document
        self.modelContext = modelContext
    }

    /// `initialSearchText`는 이미지 문서에서만 쓴다 — 검색어와 일치하는 글자가 있는 첫 쪽으로 열기 위해서다.
    func onAppear(initialSearchText: String? = nil) {
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
        } else if document.originalFormat == .image {
            // 이미지는 쪽마다 파일이 달라 `openImagePage`가 쪽별로 다운로드 확인과 읽기를 한다(아래 `loadTextLines()` 뒤).
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

        if document.originalFormat == .image {
            reloadImagePages()
            let matchCounts = imageMatchCounts(for: initialSearchText)
            let firstMatchIndex = imagePageNumbers.firstIndex { (matchCounts[$0] ?? 0) > 0 } ?? 0
            openImagePage(at: firstMatchIndex)
            loadImageThumbnailsIfNeeded()
        }
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
        // 이미지 문서는 쪽 단위로 `openImagePage`가 읽는다(이 함수는 PDF/hwp 전용).
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

    // MARK: - 이미지 쪽 조작

    var imagePageCount: Int { imagePageNumbers.count }

    /// 지금 보는 쪽의 번호(0부터) — OCR 줄(`DocumentText.pageNumber`)과 같은 값.
    var currentImagePageNumber: Int {
        imagePageNumbers.indices.contains(currentImagePageIndex) ? imagePageNumbers[currentImagePageIndex] : 0
    }

    /// 쪽 행에서 쪽 번호 목록을 다시 읽는다(추가/삭제 뒤). 현재 위치는 범위 안으로 맞춘다.
    func reloadImagePages() {
        imagePageNumbers = DocumentImagePageService.pageNumbers(for: document)
        currentImagePageIndex = min(currentImagePageIndex, max(imagePageNumbers.count - 1, 0))
    }

    /// 검색어와 일치하는 OCR 줄 수 — 쪽 번호별. 검색어가 없으면 빈 딕셔너리(썸네일 표시·첫 일치 쪽 이동에 쓴다).
    func imageMatchCounts(for query: String?) -> [Int: Int] {
        let trimmed = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        var counts: [Int: Int] = [:]
        for line in textLines where line.lineText.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            counts[line.pageNumber, default: 0] += 1
        }
        return counts
    }

    /// 이미지 `index`번째 쪽을 연다 — 그 쪽 파일의 iCloud 다운로드를 확인하고 읽어 `loadedImage`에 담는다.
    func openImagePage(at index: Int) {
        guard document.originalFormat == .image, imagePageNumbers.indices.contains(index) else { return }
        currentImagePageIndex = index
        let token = UUID()
        imageLoadToken = token
        loadedImage = nil

        let pageNumber = imagePageNumbers[index]
        do {
            let url = try DocumentImagePageService.resolveURL(pageNumber: pageNumber, for: document, context: modelContext)
            resolvedURL = url
            let monitor = UbiquitousFileDownloadMonitor { [weak self] status in
                guard let self, self.imageLoadToken == token else { return }
                self.downloadStatus = status
                switch status {
                case .ready:
                    self.loadImageData(from: url, token: token)
                case .failed(let message):
                    DocumentViewerErrorLog.log(context: "\(self.document.originalFilename) (\(pageNumber + 1)쪽)", message: message)
                case .downloading:
                    break
                }
            }
            downloadMonitor = monitor
            monitor.beginMonitoring(url: url)
        } catch {
            let message = "이미지 \(pageNumber + 1)쪽 위치를 확인하지 못했습니다: \(error)"
            downloadStatus = .failed(message)
            DocumentViewerErrorLog.log(context: document.originalFilename, message: message)
        }
    }

    func showPreviousImagePage() { openImagePage(at: currentImagePageIndex - 1) }
    func showNextImagePage() { openImagePage(at: currentImagePageIndex + 1) }

    /// 쪽 파일 바이트를 메인 액터 밖에서 읽는다(큰 스캔 이미지). 그 사이 다른 쪽으로 넘어갔으면(`token` 불일치) 버린다.
    private func loadImageData(from url: URL, token: UUID) {
        Task { [weak self] in
            let data = await Task.detached(priority: .userInitiated) {
                try? Self.readSecurityScopedData(from: url)
            }.value
            guard let self, self.imageLoadToken == token, let data else { return }
            self.loadedImage = PlatformImage(data: data)
        }
    }

    /// 썸네일 줄에 쓸 축소 이미지를 아직 없는 쪽만 차례로 만든다. 파일이 이 기기에 아직 없으면 그 쪽은 건너뛴다.
    func loadImageThumbnailsIfNeeded() {
        guard imagePageNumbers.count > 1 else { return }
        var targets: [(pageNumber: Int, url: URL)] = []
        for pageNumber in imagePageNumbers where imageThumbnails[pageNumber] == nil {
            if let url = try? DocumentImagePageService.resolveURL(pageNumber: pageNumber, for: document, context: modelContext) {
                targets.append((pageNumber, url))
            }
        }
        guard !targets.isEmpty else { return }
        Task { [weak self] in
            for target in targets {
                let data = await Task.detached(priority: .utility) {
                    Self.makeThumbnailData(from: target.url)
                }.value
                guard let self else { return }
                if let data, let image = PlatformImage(data: data) {
                    self.imageThumbnails[target.pageNumber] = image
                }
            }
        }
    }

    /// ImageIO로 긴 변 240px 썸네일(JPEG)을 만든다 — 원본 전체를 디코딩하지 않아 큰 이미지에도 가볍다.
    private nonisolated static func makeThumbnailData(from url: URL) -> Data? {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 선택한 이미지들을 이 문서 맨 끝에 더하고(새 쪽만 OCR) 첫 새 쪽으로 이동한다.
    func appendImages(urls: [URL]) {
        guard document.originalFormat == .image, !urls.isEmpty, !isModifyingImagePages else { return }
        isModifyingImagePages = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DocumentImagePageService.appendImages(urls: urls, to: self.document, context: self.modelContext)
                self.reloadImagePages()
                self.loadTextLines()
                if let first = result.addedPageNumbers.first, let index = self.imagePageNumbers.firstIndex(of: first) {
                    self.openImagePage(at: index)
                }
                self.loadImageThumbnailsIfNeeded()
                if !result.failedFilenames.isEmpty {
                    self.imagePageMessage = "\(result.failedFilenames.joined(separator: ", "))을(를) 더하지 못했습니다."
                }
            } catch {
                self.imagePageMessage = "이미지를 추가하지 못했습니다: \(error.localizedDescription)"
            }
            self.isModifyingImagePages = false
        }
    }

    /// 지금 보는 쪽을 지운다. 뒤쪽 번호가 당겨지므로 썸네일 캐시는 비우고 다시 만든다.
    func deleteCurrentImagePage() {
        guard document.originalFormat == .image, !isModifyingImagePages else { return }
        let index = currentImagePageIndex
        do {
            try DocumentImagePageService.deletePage(pageNumber: currentImagePageNumber, from: document, context: modelContext)
            imageThumbnails = [:]
            reloadImagePages()
            loadTextLines()
            openImagePage(at: min(index, max(imagePageNumbers.count - 1, 0)))
            loadImageThumbnailsIfNeeded()
        } catch {
            imagePageMessage = error.localizedDescription
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
