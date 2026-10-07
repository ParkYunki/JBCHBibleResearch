//
//  DocumentUploadService.swift
//  JBCHBibleResearch
//
//  업로드 직후 SourceDocument를 생성한다(형식 공통). 툴바 업로드 버튼, 드래그앤드롭,
//  드롭존 클릭 세 진입점이 모두 이 서비스 하나를 공유한다.
//
//  원본은 제자리에 두지 않고 앱의 iCloud 컨테이너(CloudKit과 같은 식별자) 아래
//  Documents/연구 문서(이미지는 Documents/OCR 이미지)로 "복사"한다(원본은 지우지 않는다).
//  컨테이너는 의도적으로 비공개다. iCloud capability가 없으면
//  `url(forUbiquityContainerIdentifier:)`가 nil을 돌려주고, 업로드는 원본 위치 참조로 조용히 폴백한다.
//
//  ⚠️ fileBookmark 생성 옵션은 플랫폼별로 다르다(macOS는 `.withSecurityScope`, iOS는 옵션 없음).
//  ⚠️ `storage_location_kind` 판별은 경로 문자열에 의존하는 휴리스틱이며, iCloud 저장 실패로
//  폴백할 때만 쓴다.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import PDFKit
import BibleResearchModels

enum DocumentUploadError: Error, CustomStringConvertible {
    case unsupportedFormat(String)
    case securityScopedAccessFailed
    case bookmarkCreationFailed(String)
    /// iCloud Drive 컨테이너를 쓸 수 없을 때(로그인 안 됨, capability 미설정 등). `createSourceDocument`가
    /// 잡아서 원본 위치 참조로 폴백하므로 사용자에게 직접 노출되는 경우는 거의 없다.
    case iCloudContainerUnavailable

    var description: String {
        switch self {
        case .unsupportedFormat(let ext):
            return "지원하지 않는 파일 형식입니다(.\(ext))."
        case .securityScopedAccessFailed:
            return "파일에 접근할 권한을 얻지 못했습니다."
        case .bookmarkCreationFailed(let message):
            return "파일 위치를 저장하지 못했습니다: \(message)"
        case .iCloudContainerUnavailable:
            return "iCloud Drive를 사용할 수 없습니다 — iCloud 로그인 상태와 저장공간을 확인해주세요."
        }
    }
}

@MainActor
enum DocumentUploadService {
    /// iCloud 복사 실패로 원본 위치 참조로 폴백했을 때의 사유. 호출부(`DocumentsViewModel.upload`)가
    /// 읽어 사용자에게 알린다. 다음 업로드 때 갱신되고, 성공하면 nil로 지워진다.
    static private(set) var lastICloudCopyFailureReason: String?

    /// 파일 선택기에 노출되는 "새로 고를 수 있는 형식" 목록(pdf, 이미지, `allowHWP`일 때 hwp/hwpx).
    /// doc/docx/pages 업로드는 막혀 있다. 드래그앤드롭은 이 목록을 거치지 않으므로 `createSourceDocument`의
    /// 확장자 스위치에서 별도로 막는다. 이미 업로드된 doc/docx/pages 문서는 계속 열람·검색된다.
    static func supportedContentTypes(allowHWP: Bool) -> [UTType] {
        var types: [UTType] = [.pdf, .jpeg, .png, .heic]
        if allowHWP {
            // hwp/hwpx는 표준 UTType이 없어 확장자 기반으로 직접 선언한다.
            if let hwp = UTType(filenameExtension: "hwp") { types.append(hwp) }
            if let hwpx = UTType(filenameExtension: "hwpx") { types.append(hwpx) }
        }
        return types
    }

    /// 세 업로드 진입점이 공유하는 단일 경로. `SourceDocument`를 만들어 저장하기까지만 책임지며,
    /// 형식별 텍스트 추출은 호출부가 `DocumentTextExtractionService`로 이어서 트리거한다.
    /// `relatedChapterRef`는 검증 없이 모델에 그대로 싣는다(유효성은 호출부의 `BookChapterPicker`가 보장).
    /// `category` 필수 입력은 UI(업로드 확인 시트)가 강제하므로 여기서는 옵셔널로 둔다 — UI 정책과 데이터 제약을 분리.
    static func createSourceDocument(
        from url: URL, context: ModelContext, relatedChapterRef: BibleChapterRef? = nil, category: ImageCategory? = nil
    ) throws -> SourceDocument {
        let ext = url.pathExtension.lowercased()
        let format: OriginalFormat
        switch ext {
        case "hwp": format = .hwp
        case "hwpx": format = .hwpx
        case "pdf": format = .pdf
        // doc/docx/pages 업로드 차단: 드래그앤드롭은 확장자를 가리지 않고 이 함수까지 넘기므로,
        // 실제 차단 지점은 `default` 분기의 unsupportedFormat이다(기존 문서 열람에는 영향 없음).
        case "jpg", "jpeg", "png", "heic", "heif": format = .image
        default:
            throw DocumentUploadError.unsupportedFormat(ext)
        }

        // 원본을 앱의 iCloud Drive 폴더로 복사한다(이미지는 "OCR 이미지", 그 외는 "연구 문서"). 실패하면
        // 업로드를 막지 않고 원본 위치 참조 + 휴리스틱 판별로 폴백한다.
        let storageURL: URL
        let storageKind: StorageLocationKind
        // originalFilePath: icloudDrive 저장 성공 시에만 설정되는 컨테이너 Documents/ 기준 상대경로
        // (ConvertedPDF.pdfPath와 같은 규칙). copyIntoICloudDocuments가 이름 충돌 시 "이름 2.ext"로 바꿔
        // 돌려줄 수 있어 url이 아니라 실제 저장된 파일명을 쓴다.
        let subfolder = format == .image ? "OCR 이미지" : "연구 문서"
        var originalFilePath: String?
        do {
            storageURL = try copyIntoICloudDocuments(sourceURL: url, subfolder: subfolder)
            storageKind = .icloudDrive
            originalFilePath = "\(subfolder)/\(storageURL.lastPathComponent)"
            lastICloudCopyFailureReason = nil
        } catch {
            let reason = describe(error)
            print("[DocumentUploadService] iCloud Drive 저장 실패, 원본 위치 참조로 폴백: \(reason)")
            lastICloudCopyFailureReason = reason
            storageURL = url
            storageKind = inferStorageLocationKind(for: url)
        }

        // icloudDrive여도 북마크는 만들어 둔다 — originalFilePath 계산이 실패하는 예외 상황에 대비한
        // 이중 안전장치이며, 정상 시 원본 열기는 resolveOriginalFileURL이 상대경로로 처리한다.
        let bookmark = try makeSecurityScopedBookmark(for: storageURL)

        let document = SourceDocument(
            originalFilename: url.lastPathComponent,
            originalFormat: format,
            fileBookmark: bookmark,
            originalFilePath: originalFilePath,
            storageLocationKind: storageKind,
            conversionStatus: .pending,
            indexStatus: .notIndexed,
            converterUsed: .none,
            category: category,
            relatedChapterRef: relatedChapterRef,
            uploadedAt: .now
        )
        context.insert(document)
        try context.save()
        return document
    }

    // Error → 문자열. `error as? CustomStringConvertible` 캐스팅은 Apple 플랫폼에서 항상 성공해 경고를 내므로,
    // `LocalizedError.errorDescription`을 먼저 보고 없으면 `String(describing:)`으로 폴백한다.
    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return String(describing: error)
    }

    // MARK: - hwp/hwpx → PDF 사전 변환 (2026-08-16 신설)

    /// 업로드 직후 hwp/hwpx(macOS는 docx도)를 PDF로 사전 변환해 `ConvertedPDF`로 남긴다. 해당 형식이 아니면
    /// 아무것도 하지 않아 호출부가 모든 업로드에 무조건 호출해도 안전하다. 이미 `ConvertedPDF`가 있으면
    /// 건너뛰고(멱등), 실패해도 throw하지 않고 로그만 남긴다 — 뷰어(`HWPToPDFPane`)가 레코드가 없으면
    /// 즉시 변환 경로로 대체한다.
    static func generateConvertedPDF(for document: SourceDocument, context: ModelContext) async {
        if document.originalFormat == .hwp || document.originalFormat == .hwpx {
            await generateConvertedPDFForHWP(for: document, context: context)
        }
        #if os(macOS)
        if document.originalFormat == .docx {
            await generateConvertedPDFForDocx(for: document, context: context)
        }
        #endif
    }

    private static func generateConvertedPDFForHWP(for document: SourceDocument, context: ModelContext) async {
        guard (document.convertedPDFs ?? []).isEmpty else { return }

        do {
            // 북마크 대신 resolveOriginalFileURL — 다른 기기에서 재시도돼도 originalFilePath로 원본을 찾을 수 있다.
            let sourceURL = try resolveOriginalFileURL(for: document, context: context)
            let hwpData = try readSecurityScopedData(from: sourceURL)
            let pdfData = try await RhwpPDFExportService().exportPDF(documentData: hwpData)

            guard let containerURL = FileManager.default.url(
                forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
            ) else {
                print("[DocumentUploadService] hwp → PDF 변환은 성공했지만 iCloud 컨테이너를 쓸 수 없어 저장하지 못함: \(document.originalFilename)")
                return
            }

            let subfolder = "연구 문서"
            let folderURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // hwp 원본과 같은 기본 파일명에 확장자만 .pdf로 바꾼다. 이름이 겹치면 `uniqueDestinationURL`이
            // "이름 2.pdf" 식으로 비켜 준다.
            let baseName = (document.originalFilename as NSString).deletingPathExtension
            let destinationURL = uniqueDestinationURL(in: folderURL, filename: baseName + ".pdf")

            var coordinatorError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(
                writingItemAt: destinationURL, options: [], error: &coordinatorError
            ) { writeURL in
                do {
                    try pdfData.write(to: writeURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let coordinatorError { throw coordinatorError }
            if let writeError { throw writeError }

            // 컨테이너의 절대 경로는 기기/재설치마다 달라질 수 있어 "Documents/" 아래 상대 경로만 저장한다
            // (ConvertedPDF.pdfPath 참고).
            let relativePath = "\(subfolder)/\(destinationURL.lastPathComponent)"
            let pageCount = PDFDocument(data: pdfData)?.pageCount ?? 0

            let converted = ConvertedPDF(
                pdfPath: relativePath,
                pageCount: pageCount,
                converterUsed: .rhwpWebViewPDFExport,
                sourceDocument: document
            )
            context.insert(converted)
            try context.save()
        } catch {
            print("[DocumentUploadService] hwp → PDF 사전 변환 실패(\(document.originalFilename)): \(error)")
        }
    }

    // MARK: - docx → PDF 사전 변환 (2026-08-16 신설, macOS 전용)

    #if os(macOS)
    /// docx → PDF 사전 변환(macOS 전용). hwp용 함수와 같은 원칙(멱등, 실패해도 throw 안 함)을 따른다.
    /// 변환기(`DocxToPDFConverter`)가 파일 경로에 직접 쓰는 API라, iCloud 컨테이너에 바로 쓰지 않고 임시
    /// 파일에 먼저 쓴 뒤 NSFileCoordinator의 coordinated move로 옮긴다 — Rust 쪽 쓰기는 Swift 클로저
    /// 밖에서 일어나 코디네이터로 감쌀 수 없기 때문이다.
    private static func generateConvertedPDFForDocx(for document: SourceDocument, context: ModelContext) async {
        guard (document.convertedPDFs ?? []).isEmpty else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            // 북마크 대신 resolveOriginalFileURL(기기 간 이식).
            let sourceURL = try resolveOriginalFileURL(for: document, context: context)
            let docxData = try readSecurityScopedData(from: sourceURL)
            try DocxToPDFConverter.convert(docxData: docxData, outputURL: tempURL)

            guard let containerURL = FileManager.default.url(
                forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
            ) else {
                print("[DocumentUploadService] docx → PDF 변환은 성공했지만 iCloud 컨테이너를 쓸 수 없어 저장하지 못함: \(document.originalFilename)")
                return
            }

            let subfolder = "연구 문서"
            let folderURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // hwp 쪽과 같은 규칙 — 원본과 같은 기본 파일명에 확장자만 .pdf로 바꾼다.
            let baseName = (document.originalFilename as NSString).deletingPathExtension
            let destinationURL = uniqueDestinationURL(in: folderURL, filename: baseName + ".pdf")

            var coordinatorError: NSError?
            var moveError: Error?
            NSFileCoordinator().coordinate(
                writingItemAt: destinationURL, options: [], error: &coordinatorError
            ) { writeURL in
                do {
                    try FileManager.default.moveItem(at: tempURL, to: writeURL)
                } catch {
                    moveError = error
                }
            }
            if let coordinatorError { throw coordinatorError }
            if let moveError { throw moveError }

            let relativePath = "\(subfolder)/\(destinationURL.lastPathComponent)"
            let pageCount = PDFDocument(url: destinationURL)?.pageCount ?? 0

            let converted = ConvertedPDF(
                pdfPath: relativePath,
                pageCount: pageCount,
                converterUsed: .docxidePdf,
                sourceDocument: document
            )
            context.insert(converted)
            try context.save()
        } catch {
            print("[DocumentUploadService] docx → PDF 사전 변환 실패(\(document.originalFilename)): \(error)")
        }
    }
    #endif

    /// security-scoped URL에서 파일 바이트를 읽는다. `DocumentViewerViewModel.readSecurityScopedData`와
    /// 같은 패턴이지만 레이어가 달라 공유 유틸로 뽑지 않고 각자 둔다.
    private static func readSecurityScopedData(from url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    // MARK: - iCloud Drive 저장 (2026-08-11 신설, 2026-08-15 비공개로 되돌림)
    //
    // 이 앱의 iCloud 컨테이너(CloudKit과 같은 식별자 `BibleResearchSchema.defaultCloudKitContainerIdentifier`)의
    // 표준 "Documents" 폴더 아래 "<subfolder>"로 원본을 복사한다.
    //
    // ⚠️ 컨테이너가 이미 앱 전용이므로 그 안에 "JBCH 성경 연구" 세그먼트를 두지 않는다("Documents/연구 문서",
    // "Documents/OCR 이미지"). 예전 경로("Documents/JBCH 성경 연구/…")의 기존 문서는 fileBookmark가 실제
    // 위치를 가리켜 계속 열리지만 옮겨주지는 않는다(필요하면 별도 마이그레이션).
    //
    // ⚠️ 컨테이너는 의도적으로 비공개(private scope)다(Info.plist 상단 주석 참고) — Finder에서 파일을 지우거나
    // 옮기면 `SourceDocument.fileBookmark`가 깨질 수 있어서다. 기기 간 iCloud 동기화는 그대로 된다.
    //
    // NSFileCoordinator로 감싸는 것은 iCloud 동기화 위치에 쓸 때의 Apple 권장 방식이다(동기화 데몬과 충돌 방지).
    private static func copyIntoICloudDocuments(sourceURL: URL, subfolder: String) throws -> URL {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
        ) else {
            throw DocumentUploadError.iCloudContainerUnavailable
        }

        let folderURL = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // 같은 폴더에 같은 이름이 실제로 있을 때만 "파일명 2.pdf" 식으로 구분하고, 그 외에는 원본 파일명을 그대로 쓴다.
        let destinationURL = uniqueDestinationURL(in: folderURL, filename: sourceURL.lastPathComponent)

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { sourceURL.stopAccessingSecurityScopedResource() } }

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: sourceURL, options: [],
            writingItemAt: destinationURL, options: [],
            error: &coordinatorError
        ) { readURL, writeURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: writeURL)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        return destinationURL
    }

    /// `filename`이 `folderURL`에 이미 있으면 "파일명 2.pdf", "파일명 3.pdf" ... 순으로 비어 있는 이름을 찾는다.
    /// 겹치지 않으면 원본 파일명을 그대로 돌려준다.
    private static func uniqueDestinationURL(in folderURL: URL, filename: String) -> URL {
        let candidate = folderURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var index = 2
        while true {
            let newName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let newCandidate = folderURL.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: newCandidate.path) {
                return newCandidate
            }
            index += 1
        }
    }

    // MARK: - 이미지 문서 쪽 (여러 장 = 한 문서)

    /// 이미지 파일 한 장을 "OCR 이미지" 폴더로 복사하고 쪽 행(`DocumentImagePage`)에 담을 위치를 돌려준다.
    /// iCloud 복사에 실패하면 `createSourceDocument`와 같은 원칙으로 원본 위치 참조(bookmark)로 폴백하며,
    /// 이때 `relativePath`는 빈 문자열이다.
    static func storeImagePageFile(from url: URL) throws -> (relativePath: String, bookmark: Data?) {
        do {
            let storedURL = try copyIntoICloudDocuments(sourceURL: url, subfolder: "OCR 이미지")
            lastICloudCopyFailureReason = nil
            return ("OCR 이미지/\(storedURL.lastPathComponent)", try? makeSecurityScopedBookmark(for: storedURL))
        } catch {
            lastICloudCopyFailureReason = describe(error)
            return ("", try makeSecurityScopedBookmark(for: url))
        }
    }

    /// 이미지 여러 장을 한 `SourceDocument`(이미지 모음)로 만든다. 첫 장이 문서의 원본 파일이 되고
    /// (`createSourceDocument`), 모든 장(첫 장 포함)에 쪽 행이 만들어진다. 첫 장 처리에 실패하면 던지고,
    /// 둘째 장부터 실패한 파일은 건너뛴 채 이름을 `failedFilenames`로 돌려준다(호출부가 사용자에게 알린다).
    /// `urls`는 이미지 확장자 파일만, 1장 이상이어야 한다. 텍스트 추출(쪽별 OCR)은 호출부 책임이다.
    static func createImageDocument(
        from urls: [URL], context: ModelContext, relatedChapterRef: BibleChapterRef? = nil, category: ImageCategory? = nil
    ) throws -> (document: SourceDocument, failedFilenames: [String]) {
        guard let first = urls.first else { throw DocumentUploadError.unsupportedFormat("") }
        let document = try createSourceDocument(
            from: first, context: context, relatedChapterRef: relatedChapterRef, category: category
        )
        // 첫 장은 문서 원본과 같은 파일이라 위치 정보를 그대로 가져온다.
        context.insert(DocumentImagePage(
            pageNumber: 0,
            imageFilePath: document.originalFilePath ?? "",
            fileBookmark: document.fileBookmark,
            sourceDocument: document
        ))

        var failedFilenames: [String] = []
        var nextPageNumber = 1
        for url in urls.dropFirst() {
            do {
                let stored = try storeImagePageFile(from: url)
                context.insert(DocumentImagePage(
                    pageNumber: nextPageNumber,
                    imageFilePath: stored.relativePath,
                    fileBookmark: stored.bookmark,
                    sourceDocument: document
                ))
                nextPageNumber += 1
            } catch {
                failedFilenames.append(url.lastPathComponent)
            }
        }

        // 실제로 장이 더해졌을 때만 "첫 파일명 외 N장"으로 이름을 바꾼다(확장자는 유지).
        if nextPageNumber > 1 {
            let base = (first.lastPathComponent as NSString).deletingPathExtension
            let ext = (first.lastPathComponent as NSString).pathExtension
            let suffix = " 외 \(nextPageNumber - 1)장"
            document.originalFilename = ext.isEmpty ? base + suffix : base + suffix + "." + ext
        }
        try context.save()
        return (document, failedFilenames)
    }

    /// 이미지 문서의 모든 쪽 파일을 지운다(문서 삭제 시). `deleteStoredFile`이 문서 원본(= 현재 첫 쪽)을
    /// 지우므로 그 파일은 겹쳐 지워질 수 있으나, 이미 없는 파일은 조용히 넘어가 문제 없다.
    /// iCloud 컨테이너에 복사한 파일만 지운다(경로가 비어 있는 폴백 쪽은 사용자 원본이라 건드리지 않는다).
    static func deleteImagePageFiles(for document: SourceDocument) {
        for page in document.imagePages ?? [] {
            deleteContainerFile(relativePath: page.imageFilePath)
        }
    }

    /// 컨테이너 "Documents/" 기준 상대 경로의 파일 하나를 지운다. 빈 경로/컨테이너 없음/이미 없는 파일은 조용히 넘어간다.
    static func deleteContainerFile(relativePath: String) {
        guard !relativePath.isEmpty,
              let containerURL = FileManager.default.url(
                  forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
              ) else { return }
        let fileURL = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: false)
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL, options: .forDeleting, error: &coordinatorError
        ) { writeURL in
            do {
                try FileManager.default.removeItem(at: writeURL)
            } catch let removeError as NSError where removeError.code == NSFileNoSuchFileError {
                // 이미 없는 파일 — 문제 아님.
            } catch {
                print("[DocumentUploadService] 이미지 쪽 파일 삭제 실패(\(relativePath)): \(error.localizedDescription)")
            }
        }
        if let coordinatorError {
            print("[DocumentUploadService] 이미지 쪽 파일 삭제 조정 실패(\(relativePath)): \(coordinatorError.localizedDescription)")
        }
    }

    // MARK: - Security-scoped bookmark

    private static func makeSecurityScopedBookmark(for url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            #if os(macOS)
            return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
        } catch {
            throw DocumentUploadError.bookmarkCreationFailed(error.localizedDescription)
        }
    }

    /// 문서 삭제 시 파일 정리 함수들. `deleteStoredFile`은 `storageLocationKind == .icloudDrive`인 문서만 지운다 —
    /// 앱이 만든 복사본이기 때문이며, `.userFolder`/`.appManagedFallback`는 사용자의 원본을 가리키므로 지우지 않는다.
    /// 파일 삭제가 실패해도 DB 레코드 삭제를 막지 않도록 throw 없이 로그만 남긴다.
    /// `deleteConvertedPDFFiles`는 `generateConvertedPDF`가 만든 사전 변환 PDF를 지운다(고아 파일 방지).
    /// `convertedPDFs`가 배열이라 `deleteStoredFile`과 별도 함수로 뽑았다.
    static func deleteConvertedPDFFiles(for document: SourceDocument) {
        let convertedPDFs = document.convertedPDFs ?? []
        guard !convertedPDFs.isEmpty else { return }
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
        ) else { return }

        for converted in convertedPDFs {
            let pdfURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(converted.pdfPath, isDirectory: false)
            var coordinatorError: NSError?
            NSFileCoordinator().coordinate(
                writingItemAt: pdfURL, options: .forDeleting, error: &coordinatorError
            ) { writeURL in
                do {
                    try FileManager.default.removeItem(at: writeURL)
                } catch let removeError as NSError where removeError.code == NSFileNoSuchFileError {
                    // 이미 없는 파일 — 문제 아님.
                } catch {
                    print("[DocumentUploadService] 사전 변환 PDF 삭제 실패(\(converted.pdfPath)): \(error.localizedDescription)")
                }
            }
            if let coordinatorError {
                print("[DocumentUploadService] 사전 변환 PDF 삭제 조정 실패(\(converted.pdfPath)): \(coordinatorError.localizedDescription)")
            }
        }
    }

    static func deleteStoredFile(for document: SourceDocument) {
        guard document.storageLocationKind == .icloudDrive else { return }
        // originalFilePath가 있으면 그것으로 URL을 직접 계산한다 — 삭제는 되돌릴 수 없어 이 기기 북마크가
        // 이식 불가라서 실패하면 안 된다. 곧 지워질 문서라 백필은 하지 않고 ModelContext 없이 쓰는 인라인 버전을 쓴다.
        let resolvedURL: URL?
        if let relativePath = document.originalFilePath,
           let containerURL = FileManager.default.url(
               forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
           ) {
            resolvedURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false)
        } else if let bookmark = document.fileBookmark {
            resolvedURL = try? resolveURL(from: bookmark)
        } else {
            resolvedURL = nil
        }
        guard let resolvedURL else { return }
        // do/catch를 두지 않는다 — 던지는 코드가 없다(`resolveURL` 실패는 위에서 `try?`로 nil 처리돼 guard에서 반환된다).
        let url = resolvedURL
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinatorError
        ) { writeURL in
            do {
                try FileManager.default.removeItem(at: writeURL)
            } catch let removeError as NSError where removeError.code == NSFileNoSuchFileError {
                // 이미 없는 파일 — 문제 아님(예: 사용자가 다른 경로로 이미 지움).
            } catch {
                print("[DocumentUploadService] 파일 삭제 실패(\(url.lastPathComponent)): \(error.localizedDescription)")
            }
        }
        if let coordinatorError {
            print("[DocumentUploadService] 파일 삭제 조정 실패(\(url.lastPathComponent)): \(coordinatorError.localizedDescription)")
        }
    }

    /// 저장된 북마크를 실제 URL로 되돌린다. 뷰어(S6)/재추출 시 호출.
    static func resolveURL(from bookmark: Data) throws -> URL {
        var isStale = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        // ⚠️ isStale이어도 북마크를 갱신하지 않는다(Apple 권장은 재생성 후 SourceDocument.fileBookmark 갱신).
        return url
    }

    /// 원본 파일 URL을 구하는 창구 — 원본을 여는 모든 곳이 `resolveURL(from:)` 대신 이 함수를 쓴다.
    /// icloudDrive이고 `originalFilePath`가 있으면 컨테이너 상대경로로 URL을 계산하므로 북마크가 필요 없다(기기 간 이식 가능).
    /// `originalFilePath`가 없는 기존 문서는 `fileBookmark`로 폴백하고, 성공하면 그 자리에서 `originalFilePath`를
    /// 소급 저장해 CloudKit 동기화로 다른 기기에서도 상대경로로 열리게 한다. icloudDrive가 아니면(앱 소유 파일이
    /// 아님) 상대경로 계산이 불가능하므로 북마크만 쓴다.
    static func resolveOriginalFileURL(for document: SourceDocument, context: ModelContext) throws -> URL {
        if document.storageLocationKind == .icloudDrive,
           let relativePath = document.originalFilePath,
           let containerURL = FileManager.default.url(
               forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
           ) {
            return containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false)
        }

        guard let bookmark = document.fileBookmark else {
            throw DocumentUploadError.securityScopedAccessFailed
        }
        let url = try resolveURL(from: bookmark)

        // 마이그레이션 — icloudDrive인데 originalFilePath가 없는 기존 문서: URL이 컨테이너 "Documents/" 아래면
        // 상대경로를 역산해 채운다.
        if document.storageLocationKind == .icloudDrive,
           document.originalFilePath == nil,
           let containerURL = FileManager.default.url(
               forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
           ) {
            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            let containerPath = documentsURL.standardizedFileURL.path
            let resolvedPath = url.standardizedFileURL.path
            if resolvedPath.hasPrefix(containerPath + "/") {
                document.originalFilePath = String(resolvedPath.dropFirst(containerPath.count + 1))
                try? context.save()
            }
        }

        return url
    }

    // MARK: - 저장 위치 추정(휴리스틱, ⚠️ 검증 필요)

    private static func inferStorageLocationKind(for url: URL) -> StorageLocationKind {
        let path = url.path
        if path.contains("Mobile Documents/com~apple~CloudDocs") {
            return .icloudDrive
        }
        // `homeDirectoryForCurrentUser`는 iOS에서 쓸 수 없어 macOS에서만 홈 경로와 대조하고, 그 외 플랫폼은
        // 아래 고정 접두사 검사로만 판단한다.
        #if os(macOS)
        if path.contains(FileManager.default.homeDirectoryForCurrentUser.path) {
            return .userFolder
        }
        #endif
        if path.hasPrefix("/Users/") || path.hasPrefix("/var/mobile/") {
            return .userFolder
        }
        return .appManagedFallback
    }
}
