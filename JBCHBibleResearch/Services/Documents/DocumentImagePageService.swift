//
//  DocumentImagePageService.swift
//  JBCHBibleResearch
//
//  이미지 문서의 "쪽" 관리 — 여러 장을 한 문서(이미지 모음)로 다루기 위한 쪽 목록 조회, 쪽 파일 위치 해석,
//  이미지 추가(맨 끝에), 쪽 삭제를 맡는다. 모델은 `DocumentImagePage`(Documents.swift).
//
//  규칙
//  - 쪽 번호(`pageNumber`)는 0부터이며 OCR 줄(`DocumentText.pageNumber`)·앵커(`DocumentAnchor.pageNumber`)와 같은 값이다.
//  - 쪽 행이 하나도 없는 이미지 문서는 "원본 파일 1장짜리"(기존 문서)로 본다 — 변환 작업 없이 그대로 열린다.
//    처음 장을 더하는 순간에만 0쪽 행이 만들어진다(`appendImages`).
//  - 문서의 원본 위치(`originalFilePath`/`fileBookmark`)는 항상 현재 첫 쪽 파일을 가리킨다(첫 쪽을 지우면 `deletePage`가 옮긴다).
//

import Foundation
import SwiftData
import BibleResearchModels

enum DocumentImagePageError: Error, LocalizedError {
    case notImageDocument
    case lastPage
    case pageNotFound

    var errorDescription: String? {
        switch self {
        case .notImageDocument: return "이미지 문서가 아닙니다."
        case .lastPage: return "마지막 한 장은 삭제할 수 없습니다. 문서를 삭제해 주세요."
        case .pageNotFound: return "해당 쪽을 찾을 수 없습니다."
        }
    }
}

@MainActor
enum DocumentImagePageService {
    /// `appendImages` 결과 — 새로 더해진 쪽 번호와, 파일 복사에 실패해 건너뛴 파일 이름.
    struct AppendResult {
        var addedPageNumbers: [Int] = []
        var failedFilenames: [String] = []
    }

    /// 쪽 행을 쪽 번호 순으로 돌려준다(없으면 빈 배열 = 원본 1장짜리).
    static func sortedPages(for document: SourceDocument) -> [DocumentImagePage] {
        (document.imagePages ?? []).sorted { $0.pageNumber < $1.pageNumber }
    }

    /// 이 문서의 쪽 번호 목록. 쪽 행이 없으면 원본 1장(0쪽)이다.
    static func pageNumbers(for document: SourceDocument) -> [Int] {
        let pages = sortedPages(for: document)
        return pages.isEmpty ? [0] : pages.map(\.pageNumber)
    }

    /// 쪽 이미지 파일의 URL. 쪽 행의 컨테이너 상대 경로 → 위치 북마크 순으로 시도하고, 0쪽이면 문서 원본으로 폴백한다.
    /// 원본 열기와 같은 이유로 `DocumentUploadService.resolveOriginalFileURL`을 그대로 쓴다(기기 간 이식).
    static func resolveURL(pageNumber: Int, for document: SourceDocument, context: ModelContext) throws -> URL {
        if let page = (document.imagePages ?? []).first(where: { $0.pageNumber == pageNumber }) {
            if !page.imageFilePath.isEmpty,
               let containerURL = FileManager.default.url(
                   forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
               ) {
                return containerURL
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent(page.imageFilePath, isDirectory: false)
            }
            if let bookmark = page.fileBookmark {
                return try DocumentUploadService.resolveURL(from: bookmark)
            }
        }
        if pageNumber == 0 {
            return try DocumentUploadService.resolveOriginalFileURL(for: document, context: context)
        }
        throw DocumentImagePageError.pageNotFound
    }

    // MARK: - 이미지 추가 (맨 끝에)

    /// 기존 이미지 문서 맨 끝에 이미지들을 더하고 새 쪽만 OCR한다. 쪽 행이 없던 문서(원본 1장짜리)는 먼저 0쪽 행을 만든다.
    /// 복사에 실패한 파일은 건너뛰고 이름을 결과에 담는다. 더해진 쪽이 하나도 없으면 문서는 바뀌지 않는다.
    static func appendImages(urls: [URL], to document: SourceDocument, context: ModelContext) async throws -> AppendResult {
        guard document.originalFormat == .image else { throw DocumentImagePageError.notImageDocument }

        let existing = document.imagePages ?? []
        var createdFirstRow: DocumentImagePage?
        var nextPageNumber: Int
        if existing.isEmpty {
            // 기존 1장짜리 문서 — 원본 위치를 그대로 0쪽 행에 옮겨 담는다.
            let row = DocumentImagePage(
                pageNumber: 0,
                imageFilePath: document.originalFilePath ?? "",
                fileBookmark: document.fileBookmark,
                sourceDocument: document
            )
            context.insert(row)
            createdFirstRow = row
            nextPageNumber = 1
        } else {
            nextPageNumber = (existing.map(\.pageNumber).max() ?? -1) + 1
        }

        var result = AppendResult()
        for url in urls {
            do {
                let stored = try DocumentUploadService.storeImagePageFile(from: url)
                context.insert(DocumentImagePage(
                    pageNumber: nextPageNumber,
                    imageFilePath: stored.relativePath,
                    fileBookmark: stored.bookmark,
                    sourceDocument: document
                ))
                result.addedPageNumbers.append(nextPageNumber)
                nextPageNumber += 1
            } catch {
                result.failedFilenames.append(url.lastPathComponent)
            }
        }

        if result.addedPageNumbers.isEmpty {
            // 더해진 게 없으면 방금 만든 0쪽 행도 되돌려 문서를 원래 상태로 둔다.
            if let createdFirstRow { context.delete(createdFirstRow) }
            try? context.save()
            return result
        }

        try context.save()
        await DocumentTextExtractionService.extractImagePages(result.addedPageNumbers, for: document, context: context)
        return result
    }

    // MARK: - 쪽 삭제

    /// 한 쪽을 지운다 — 쪽 행, 이미지 파일, 그 쪽의 OCR 글자·앵커를 지우고 뒤쪽 번호를 하나씩 당긴다. 검색 캐시(`cachedCombinedText`)와
    /// FTS 색인, 성경구절 색인도 다시 만든다. 마지막 한 장은 지울 수 없다(`DocumentImagePageError.lastPage`).
    static func deletePage(pageNumber: Int, from document: SourceDocument, context: ModelContext) throws {
        guard document.originalFormat == .image else { throw DocumentImagePageError.notImageDocument }
        let pages = sortedPages(for: document)
        guard pages.count > 1 else { throw DocumentImagePageError.lastPage }
        guard let target = pages.first(where: { $0.pageNumber == pageNumber }) else {
            throw DocumentImagePageError.pageNotFound
        }

        // 현재 첫 쪽을 지우면 문서 원본 위치를 다음 쪽 파일로 옮긴다(원본 파일이 사라져도 문서가 열리도록).
        if target.pageNumber == pages[0].pageNumber {
            let successor = pages[1]
            document.originalFilePath = successor.imageFilePath.isEmpty ? nil : successor.imageFilePath
            document.fileBookmark = successor.fileBookmark
            if !successor.imageFilePath.isEmpty {
                document.storageLocationKind = .icloudDrive
            }
        }

        for text in document.documentTexts ?? [] {
            if text.pageNumber == pageNumber {
                context.delete(text)
            } else if text.pageNumber > pageNumber {
                text.pageNumber -= 1
            }
        }
        for anchor in document.anchors ?? [] {
            if anchor.pageNumber == pageNumber {
                context.delete(anchor)
            } else if anchor.pageNumber > pageNumber {
                anchor.pageNumber -= 1
            }
        }
        for page in pages where page.pageNumber > pageNumber {
            page.pageNumber -= 1
        }

        let removedPath = target.imageFilePath
        context.delete(target)
        try context.save()

        // 삭제 반영 후 파생 데이터를 다시 만든다(저장 전에는 관계 배열에 지워진 객체가 남아 있을 수 있어 저장 뒤에 한다).
        document.rebuildCachedCombinedText()
        UserContentSearchIndexLocation.upsert(
            category: .document, sourceId: document.id.uuidString, content: document.cachedCombinedText
        )
        try? context.save()
        BibleReferenceIndexingService.reindexDocument(document, context: context)

        // DB 삭제가 성공한 뒤에만 파일을 지운다(되돌릴 수 없는 작업을 마지막에).
        DocumentUploadService.deleteContainerFile(relativePath: removedPath)
    }
}
