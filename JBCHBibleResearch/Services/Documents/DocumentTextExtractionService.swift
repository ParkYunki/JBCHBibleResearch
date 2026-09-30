//
//  DocumentTextExtractionService.swift
//  JBCHBibleResearch
//
//  형식별 텍스트 추출. 형식마다 신뢰도가 달라 각 분기가 그 순서를 따른다.
//  - pdf: PDFKit. 텍스트 레이어가 없는 스캔 PDF는 "실패, 수동 필요"로 처리한다.
//  - image: Vision OCR 결과를 그대로 `DocumentText`로 반영한다(정확도는 화질에 따름).
//  - doc: macOS만 `NSAttributedString` docFormat 사용. iOS에는 대응 API가 없어 바로 실패 처리한다.
//  - docx/pages: SwiftText(SwiftTextDOCX/SwiftTextPages, MIT)로 macOS/iOS 지원. 서식/표는 평문으로 단순화된다.
//  - hwp/hwpx: 3단계 폴백 — HwpKit(hwp-swift) → rhwp(WKWebView) → 업로드 시 만든 PDF의 텍스트 레이어.
//    hwp-swift는 `HwpIdMappings` 버전별 파싱 한계로 일부 문서에서 실패하므로 다른 파서로 우회한다.
//

import Foundation
import PDFKit
import Vision
import ImageIO
import CoreGraphics
import SwiftData
import BibleResearchModels
import HwpKit
import HwpKitCore
// SwiftText(https://github.com/Cocoanetics/SwiftText.git, MIT)는 Xcode Package Dependencies에서
// 직접 추가하고(project.pbxproj 손 편집 금지) `SwiftTextDOCX`/`SwiftTextPages`를 앱 타깃에 링크한다.
// ⚠️ Dependency Rule은 반드시 "Branch: main"이어야 한다. SwiftText의 Package.swift가 ZIPFoundation을
// 버전이 아닌 특정 revision에 고정해, 버전 규칙으로 추가하면 SwiftPM이 의존성 해석을 거부한다
// (hwp-swift를 branch: main으로 추가한 것과 같은 이유).
import SwiftTextDOCX
// `SwiftTextPages`는 같은 SwiftText 패키지의 프로덕트로, 위 "Branch: main" 안내가 그대로 적용된다.
import SwiftTextPages
#if os(macOS)
import AppKit
#endif

@MainActor
enum DocumentTextExtractionService {
    /// 업로드 직후 또는 "재시도" 액션에서 호출한다. 형식에 따라 추출 분기를 나눈다.
    static func extract(for document: SourceDocument, context: ModelContext) async {
        switch document.originalFormat {
        case .pdf:
            await extractPDF(document, context: context)
        case .image:
            await extractImageOCR(document, context: context)
        case .doc:
            extractDoc(document, context: context)
        case .docx:
            extractDocx(document, context: context)
        case .pages:
            extractPages(document, context: context)
        case .hwp, .hwpx:
            await extractHWP(document, context: context)
        }

        // 어느 분기든 `documentTexts`가 확정된 뒤 캐시(`cachedCombinedText`)를 여기서 한 번만 다시
        // 만든다 — 형식별 함수마다 갱신할 필요가 없다.
        document.rebuildCachedCombinedText()
        // FTS5 보조 인덱스도 캐시 갱신 직후 함께 갱신한다(어긋나면 인덱스가 옛 본문을 가리킨다).
        // 실패는 무시한다(`UserContentSearchIndexLocation.upsert` 선언부 참고).
        UserContentSearchIndexLocation.upsert(
            category: .document, sourceId: document.id.uuidString, content: document.cachedCombinedText
        )
        try? context.save()
    }

    // MARK: - PDF (높은 신뢰도)

    private static func extractPDF(_ document: SourceDocument, context: ModelContext) async {
        document.conversionStatus = .convertingNative
        try? context.save()

        // originalFilePath가 있으면 그것으로, 없으면(구버전 문서) 북마크로 폴백하는 공용 헬퍼.
        guard let url = try? DocumentUploadService.resolveOriginalFileURL(for: document, context: context) else {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let pdf = PDFDocument(url: url) else {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
            return
        }

        var anyPageExtracted = false
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex), let text = page.string, !text.isEmpty else { continue }
            insertLines(from: text, pageNumber: pageIndex, sourceDocument: document, context: context)
            anyPageExtracted = true
        }

        if anyPageExtracted {
            document.converterUsed = .pdfkitNative
            document.conversionStatus = .converted
            document.indexStatus = .indexed
        } else {
            // 페이지는 있으나 텍스트 레이어가 없는 스캔 PDF일 수 있다 — PDF 내부 이미지 OCR 폴백은
            // 범위 밖이라 "실패, 수동 필요"로 표시한다.
            document.conversionStatus = .failedNeedsManual
        }
        try? context.save()
        // 관련 성경구절 인덱스 재계산 — 실패 케이스는 `reindexDocument`가 `indexStatus != .indexed`로 거른다.
        BibleReferenceIndexingService.reindexDocument(document, context: context)
    }

    // MARK: - 이미지 OCR (14.3 원문은 "검수 필수"였으나, [2026-09-27 수정]
    // 검수(S7) 단계를 없앴다) — Vision 인식 결과를 그대로 `DocumentText`로 반영하고 즉시
    // `indexStatus = .indexed`로 만든다. `OCRResult`는 인식 결과 기록(재-OCR 비교/디버깅 근거)으로
    // 남기되 `status`는 처음부터 `.userReviewed`로 저장한다.

    private static func extractImageOCR(_ document: SourceDocument, context: ModelContext) async {
        document.indexStatus = .indexing
        try? context.save()

        guard let url = try? DocumentUploadService.resolveOriginalFileURL(for: document, context: context) else {
            document.conversionStatus = .failedNeedsManual
            document.indexStatus = .notIndexed
            try? context.save()
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let cgImage = loadCGImage(from: url) else {
            document.conversionStatus = .failedNeedsManual
            document.indexStatus = .notIndexed
            try? context.save()
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // 한국어 문서(설교노트 등)가 주 대상이므로 한국어를 우선 언어로 지정한다.
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            // 각 관측치의 `boundingBox`(Vision 정규화 좌표, 좌하단 원점)도 함께 챙긴다 — request 결과는
            // 이 함수를 벗어나면 사라진다. `DocumentText.ocrBoundingBox` 선언부 참고.
            let recognizedLines: [(text: String, confidence: Double, boundingBox: CGRect)] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return (candidate.string, Double(candidate.confidence), observation.boundingBox)
            }
            let rawText = recognizedLines.map(\.text).joined(separator: "\n")
            let averageConfidence = recognizedLines.isEmpty ? 0 : recognizedLines.map(\.confidence).reduce(0, +) / Double(recognizedLines.count)

            let result = OCRResult(
                rawText: rawText,
                engine: "Vision(VNRecognizeTextRequest)",
                confidence: averageConfidence,
                status: .userReviewed,
                sourceDocument: document
            )
            context.insert(result)

            // 재시도(`retry()`)로 이 함수가 다시 호출될 수 있으므로 이전 시도가 남긴 레코드를 먼저
            // 지운다(`extractHWP`와 같은 원칙).
            clearDocumentTexts(for: document, context: context)
            var anyLineInserted = false
            for (index, line) in recognizedLines.enumerated() {
                let trimmed = sanitizeLineText(line.text)
                guard !trimmed.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let record = DocumentText(
                    pageNumber: 0,
                    lineIndex: index,
                    lineText: trimmed,
                    ocrBoundingBox: encodeOCRBoundingBox(line.boundingBox),
                    sourceDocument: document
                )
                context.insert(record)
                anyLineInserted = true
            }

            document.conversionStatus = .converted
            document.indexStatus = anyLineInserted ? .indexed : .notIndexed
            try? context.save()
        } catch {
            document.conversionStatus = .failedNeedsManual
            document.indexStatus = .notIndexed
            try? context.save()
        }
        // 추출 직후 성경구절 인덱싱(PDF 분기와 같은 이유).
        BibleReferenceIndexingService.reindexDocument(document, context: context)
    }

    /// `DocumentText.ocrBoundingBox`용 "x,y,width,height" 콤마 구분 문자열. Vision 정규화 좌표
    /// (0...1, 좌하단 원점)를 변환 없이 소수점 6자리로 인코딩한다.
    private static func encodeOCRBoundingBox(_ box: CGRect) -> String {
        String(format: "%.6f,%.6f,%.6f,%.6f", box.origin.x, box.origin.y, box.width, box.height)
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - doc(구 워드) — macOS만, ⚠️ iOS 지원 여부 미확인(스펙 원문 그대로)

    private static func extractDoc(_ document: SourceDocument, context: ModelContext) {
        #if os(macOS)
        document.conversionStatus = .convertingNative
        try? context.save()

        guard let url = try? DocumentUploadService.resolveOriginalFileURL(for: document, context: context) else {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
            return
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.docFormat],
                documentAttributes: nil
            )
            insertLines(from: attributed.string, pageNumber: 0, sourceDocument: document, context: context)
            document.converterUsed = .userPreconverted // ⚠️ ConverterUsed에 "docFormat 네이티브"
            // 전용 값이 없어 가장 가까운 기존 값(userPreconverted)으로 근사했다 — 정확한 명칭이 필요하면
            // pdfkitNative처럼 케이스를 추가할 것(제품 결정 필요).
            document.conversionStatus = .converted
            document.indexStatus = .indexed
            try? context.save()
            BibleReferenceIndexingService.reindexDocument(document, context: context)
        } catch {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
        }
        #else
        // iOS/iPadOS — `NSAttributedString.DocumentType.docFormat`은 AppKit 전용이라 대응 API가 없다.
        // 추측성 시도 없이 바로 실패 처리한다(원본 파일은 그대로 열람 가능).
        document.conversionStatus = .failedNeedsManual
        try? context.save()
        #endif
    }

    // MARK: - docx(Office Open XML) — SwiftTextDOCX(크로스플랫폼, .doc과 달리 iOS도 지원)

    /// `SwiftTextDOCX`(zip+XML 파서)는 macOS/iOS 모두 동작해 플랫폼 분기가 없다. DOCX에는 쪽(page)
    /// 개념이 없어 전체 본문을 `pageNumber: 0`으로 넘긴다.
    private static func extractDocx(_ document: SourceDocument, context: ModelContext) {
        document.conversionStatus = .convertingNative
        try? context.save()

        guard let url = try? DocumentUploadService.resolveOriginalFileURL(for: document, context: context) else {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
            return
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let docx = try DocxFile(url: url)
            let text = docx.plainTextParagraphs().joined(separator: "\n")
            insertLines(from: text, pageNumber: 0, sourceDocument: document, context: context)
            document.converterUsed = .swiftTextDocx
            document.conversionStatus = .converted
            document.indexStatus = .indexed
            try? context.save()
            BibleReferenceIndexingService.reindexDocument(document, context: context)
        } catch {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
        }
    }

    // MARK: - pages(iWork) — SwiftTextPages(크로스플랫폼, 자체 Snappy+protobuf 구현)

    /// `SwiftTextPages`로 `.pages`를 읽는다 — Snappy 해제·protobuf 디코딩이 패키지 안에서 순수
    /// Swift로 구현돼 macOS/iOS 모두 동작한다. DOCX처럼 쪽 개념이 없어 `pageNumber: 0`으로 넘긴다.
    private static func extractPages(_ document: SourceDocument, context: ModelContext) {
        document.conversionStatus = .convertingNative
        try? context.save()

        guard let url = try? DocumentUploadService.resolveOriginalFileURL(for: document, context: context) else {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
            return
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let pages = try PagesFile(url: url)
            let text = pages.plainTextParagraphs().joined(separator: "\n")
            insertLines(from: text, pageNumber: 0, sourceDocument: document, context: context)
            document.converterUsed = .swiftTextPages
            document.conversionStatus = .converted
            document.indexStatus = .indexed
            try? context.save()
            BibleReferenceIndexingService.reindexDocument(document, context: context)
        } catch {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
        }
    }

    // MARK: - hwp/hwpx (위 파일 상단 [2026-08-16 전면 교체] 참고 — hwp-swift/HwpKit)

    /// hwp/hwpx는 3단계 폴백 체인으로 추출한다 — 서로 다른 파서 구현이라 한쪽의 한계를 다른 쪽이
    /// 우회할 수 있다.
    /// 1) `extractHWPNative` — hwp-swift(가장 신뢰도 높음). 문서 버전 경계에서 `HwpIdMappings`의
    ///    엄격한 EOF 검증에 걸려 일부 문서가 실패하며, 이는 제3자 라이브러리의 현재 한계다.
    /// 2) `extractHWPViaRhwp` — rhwp(WKWebView, WASM)로 같은 문서를 다시 열어 `getPageText`로 재시도.
    /// 3) `extractHWPFromConvertedPDF` — 업로드 시 미리 만든 `ConvertedPDF`의 PDFKit 텍스트 레이어.
    ///    `DocumentsViewModel.upload`가 PDF 사전 생성을 텍스트 추출보다 먼저 호출한다.
    private static func extractHWP(_ document: SourceDocument, context: ModelContext) async {
        document.conversionStatus = .convertingNative
        try? context.save()

        guard let url = try? DocumentUploadService.resolveOriginalFileURL(for: document, context: context) else {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
            return
        }

        // 재시도 액션으로 다시 호출될 수 있으므로, 이전 시도가 남긴 `DocumentText`가 중복 저장되지
        // 않게 먼저 지운다.
        clearDocumentTexts(for: document, context: context)

        var extracted = false
        do {
            extracted = try await extractHWPNative(data: data, document: document, context: context)
        } catch {
            print("[DocumentTextExtractionService] hwp 네이티브(hwp-swift) 추출 실패, rhwp 폴백 시도: \(error)")
        }

        if !extracted {
            // 네이티브가 일부 페이지만 저장하고 throw하면 그 결과가 남아, 폴백이 다시 추출할 때 같은 구간이
            // 중복 저장되고 성경 장절 언급이 재인덱싱 시 중복으로 걸린다 — 폴백 전에 부분 결과를 지운다.
            clearDocumentTexts(for: document, context: context)
            do {
                extracted = try await extractHWPViaRhwp(data: data, document: document, context: context)
            } catch {
                print("[DocumentTextExtractionService] hwp rhwp(WKWebView) 폴백도 실패, PDF 텍스트 레이어 폴백 시도: \(error)")
            }
        }

        if !extracted {
            // 위와 같은 이유로 rhwp의 부분 결과도 지운다.
            clearDocumentTexts(for: document, context: context)
            extracted = extractHWPFromConvertedPDF(document: document, context: context)
        }

        if extracted {
            document.conversionStatus = .converted
            document.indexStatus = .indexed
        } else {
            // 세 경로 모두 텍스트를 못 뽑은 경우(빈 문서, 이미지만 있는 문서 등) "실패, 수동 필요"로
            // 처리한다. 원본은 뷰어로 계속 열람할 수 있다.
            document.conversionStatus = .failedNeedsManual
        }
        try? context.save()
        // 방금 `indexed`가 됐을 때만 재인덱싱한다(실패 케이스는 `reindexDocument`가 거른다).
        BibleReferenceIndexingService.reindexDocument(document, context: context)
    }

    /// 1차 — hwp-swift(HwpKit) 네이티브 파서. 페이지별 블록의 `attributedString.string`을 이어 붙여
    /// PDF 분기와 같은 페이지 단위(0-based) 텍스트로 만든다. 파싱 실패는 throw, 추출된 텍스트가
    /// 없으면 throw 없이 `false`를 돌려준다.
    private static func extractHWPNative(data: Data, document: SourceDocument, context: ModelContext) async throws -> Bool {
        let hwpDocument = try await HwpDocumentLoader().load(from: data)
        var anyTextExtracted = false
        for (pageIndex, page) in hwpDocument.pages.enumerated() {
            let pageText = page.blocks
                .compactMap(\.attributedString?.string)
                .joined(separator: "\n")
            guard !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            insertLines(from: pageText, pageNumber: pageIndex, sourceDocument: document, context: context)
            anyTextExtracted = true
        }
        if anyTextExtracted {
            document.converterUsed = .hwpSwiftNative
        }
        return anyTextExtracted
    }

    /// 2차 — 렌더링에 이미 쓰는 rhwp(WASM, WKWebView)로 문서를 다시 열어 `getPageText`로 쪽별
    /// 텍스트를 뽑는다. `RhwpPDFExportService.extractPlainText`의 오프스크린 WKWebView 인프라를
    /// 재사용하며, `createPDF`와 달리 화면 합성 스냅샷이 필요 없어 그 근처에서 확인된 RunningBoard
    /// 문제에 걸릴 가능성이 상대적으로 낮다.
    private static func extractHWPViaRhwp(data: Data, document: SourceDocument, context: ModelContext) async throws -> Bool {
        let pages = try await RhwpPDFExportService().extractPlainText(documentData: data)
        var anyTextExtracted = false
        for (pageIndex, pageText) in pages.enumerated() {
            guard !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            insertLines(from: pageText, pageNumber: pageIndex, sourceDocument: document, context: context)
            anyTextExtracted = true
        }
        if anyTextExtracted {
            document.converterUsed = .rhwpWebViewTextFallback
        }
        return anyTextExtracted
    }

    /// 3차(마지막) — 업로드 시 미리 만든 `ConvertedPDF`(rhwp SVG → `WKWebView.createPDF`)가 있으면
    /// PDFKit `PDFPage.string`으로 텍스트를 뽑는다. SVG `<text>`가 텍스트 레이어로 보존될 가능성에
    /// 기대는, 검증되지 않은 마지막 시도다. 레코드가 없으면 조용히 `false`를 돌려준다.
    private static func extractHWPFromConvertedPDF(document: SourceDocument, context: ModelContext) -> Bool {
        guard let convertedPDF = (document.convertedPDFs ?? []).first,
              let containerURL = FileManager.default.url(
                  forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
              ) else { return false }
        let pdfURL = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(convertedPDF.pdfPath, isDirectory: false)
        guard let pdf = PDFDocument(url: pdfURL) else { return false }

        var anyTextExtracted = false
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex), let text = page.string, !text.isEmpty else { continue }
            insertLines(from: text, pageNumber: pageIndex, sourceDocument: document, context: context)
            anyTextExtracted = true
        }
        if anyTextExtracted {
            document.converterUsed = .pdfkitNative
        }
        return anyTextExtracted
    }

    // MARK: - 공통: 텍스트 → DocumentText 줄 단위 저장

    /// hwp 폴백 체인이 부분 저장한 뒤 다음 tier로 넘어갈 때와 "재시도"로 재호출될 때, 기존
    /// `DocumentText`가 재추출분과 중복 저장되지 않도록 먼저 지운다.
    private static func clearDocumentTexts(for document: SourceDocument, context: ModelContext) {
        for text in document.documentTexts ?? [] {
            context.delete(text)
        }
    }

    private static func insertLines(from text: String, pageNumber: Int, sourceDocument: SourceDocument, context: ModelContext) {
        let lines = text.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let line = sanitizeLineText(rawLine)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let record = DocumentText(
                pageNumber: pageNumber,
                lineIndex: index,
                lineText: line,
                sourceDocument: sourceDocument
            )
            context.insert(record)
        }
    }

    /// 리터럴 이스케이프 시퀀스(백슬래시-r-백슬래시-n 등)를 공백으로 치환하는 방어적 조치.
    /// 원본 추출 텍스트(예: rhwp `getPageText` 반환값)에 이스케이프 문자열이 그대로 들어 있으면
    /// 화면에 "\r\n"이 노출되는 것으로 추정되나, 확정된 원인은 아니다.
    private static func sanitizeLineText(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\\r\\n", with: " ")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
    }
}
