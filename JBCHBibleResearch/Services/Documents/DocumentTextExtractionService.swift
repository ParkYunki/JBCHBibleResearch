//
//  DocumentTextExtractionService.swift
//  JBCHBibleResearch
//
//  screens.md 14.2 — 형식별 텍스트 추출. 신뢰도가 형식마다 크게 다르다는 걸 스펙
//  원문 자체가 표로 명시했다 — 이 파일의 각 분기도 그 신뢰도 순서를 그대로 따른다.
//
//  | 형식 | 이 구현의 처리 | 신뢰도 |
//  |---|---|---|
//  | pdf | PDFKit(`PDFDocument`/`PDFPage.string`) | 높음 — 검증된 Apple 프레임워크 |
//  | image | Vision(`VNRecognizeTextRequest`) → OCRResult(draft), S7 검수 대기 | 높음(API 자체) — 단 결과 텍스트 정확도는 문서 화질에 따라 다름 |
//  | doc | macOS만 `NSAttributedString(url:options:[.documentType: .docFormat])` | ⚠️ 스펙 원문이 "iOS 지원 여부 확인 안 됨"이라 명시 — iOS/iPadOS/아이폰에서는 시도하지 않고 바로 실패 처리 |
//  | docx | [2026-08-16 추가] `SwiftTextDOCX`(Cocoanetics/SwiftText, MIT, zip+XML) — macOS/iOS 모두 지원(`.doc`과 핵심 차이) | 높음 — 표준 OOXML 파싱, 단 문단 서식/표는 평문으로 단순화됨 |
//  | pages | [2026-08-16 추가, 이전 "파서 없음" 판단 번복] `SwiftTextPages`(Cocoanetics/SwiftText, MIT, 자체 Snappy+protobuf 구현) — macOS/iOS 모두 지원. `extractPages` 상단 주석에 재확인 경위 | 높음 — 실제 소스(PagesFile.swift)까지 직접 읽어 검증, 단 iWork '09 이전 초구형 문서는 별도 레거시 경로(패키지 자체 지원) |
//  | hwp/hwpx | [2026-08-16 3단계 폴백 체인 추가] 1차 `HwpKit`(hwp-swift, https://github.com/sboh1214/hwp-swift, LGPL-2.1, 순수 네이티브 Swift) → 실패 시 2차 rhwp(WASM, WKWebView, `getPageText`) → 그마저 실패 시 3차 업로드 시 사전 생성해 둔 PDF(rhwp SVG → WKWebView.createPDF)의 PDFKit 텍스트 레이어. `extractHWP` 참고 | 1차가 신뢰도 가장 높음(화면 렌더링과 같은 파싱 결과). 일부 문서는 hwp-swift의 `HwpIdMappings` 버전별 필드 파싱 한계("Bytes are not EOF" 등, 상류에 알려진 수정 없음, 실기기로 확인)로 1차가 실패하는데, 이때 2차·3차가 서로 다른 파서 구현이라 우회 가능성이 있다. 2차·3차 모두 실패하면 정직하게 "실패, 수동 필요"로 떨어뜨린다. |
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
// [2026-08-16 추가] 사용자 요청 — "doc, docx 업로드 지원." SPM 원격 의존성 —
// https://github.com/Cocoanetics/SwiftText.git (MIT, Cocoanetics/SwiftText).
// ⚠️ Xcode의 Package Dependencies GUI에서 직접 추가해야 한다(HwpKit/HwpKitNative
// 때와 같은 프로젝트 관례 — project.pbxproj 손 편집 금지). 패키지 추가 후
// `SwiftTextDOCX`/`SwiftTextPages` 프로덕트를 앱 타깃에 링크할 것.
//
// ⚠️⚠️ [2026-08-16 추가, 실기기 확인된 의존성 해석 오류] 반드시 "Branch: main"
// 규칙으로 추가해야 한다 — "Up to Next Major Version" 같은 버전 기반 규칙으로
// 추가하면 아래 오류로 해석이 실패한다(사용자가 실제로 겪음):
//   Failed to resolve dependencies ... 'swifttext' is required using a
//   stable-version but 'swifttext' depends on an unstable-version package
//   'zipfoundation'.
// 원인 — SwiftText 저장소 자신의 Package.swift가 ZIPFoundation을 정식 버전
// 태그가 아니라 특정 커밋(revision)에 고정해 두고 있다(Windows/Android용
// import 수정이 아직 정식 릴리스에 없어서 — SwiftText 쪽 주석에 명시됨).
// SwiftPM은 "버전 규칙으로 추가한 패키지가 자기 자신은 버전이 아닌(브랜치/
// revision) 의존성을 갖는" 조합을 거부한다 — 우리 쪽도 버전이 아니라
// branch/revision으로 추가해야 이 제약을 피할 수 있다(hwp-swift를 이미
// "branch: main"으로 추가한 것과 같은 이유·같은 해법). Xcode에서: 기존
// SwiftText 항목을 지우고 다시 추가할 때 "Dependency Rule"을 "Version"이
// 아니라 "Branch"로 바꾸고 `main`을 입력할 것.
import SwiftTextDOCX
// [2026-08-16 추가, pages 지원 확정] 같은 패키지(Cocoanetics/SwiftText)의
// `SwiftTextPages` 프로덕트도 함께 링크해야 한다(위 "Branch: main" 안내 참고 —
// 별도 트레잇 설정은 필요 없다, `SwiftText`의 기본 trait 세트 자체가 CLI→DOCX/
// PAGES/EPUB/HTML을 이미 포함해 켜져 있음). 처음엔 pages를 신뢰할 만한
// 크로스플랫폼 파서가 없다고 판단해 제외했었는데, 사용자가 이 패키지가
// pages도 지원한다고 재확인을 요청해 소스(`Sources/SwiftTextPages/
// PagesFile.swift`)를 직접 읽어 확인했다 — Snappy 압축 해제와 protobuf
// 디코딩까지 패키지 안에서 순수 Swift로 구현돼 있어 macOS/iOS 모두 동작한다.
// 아래 `extractPages` 참고.
import SwiftTextPages
#if os(macOS)
import AppKit
#endif

@MainActor
enum DocumentTextExtractionService {
    /// S5 업로드 직후 또는 "재시도" 액션에서 호출. 형식에 따라 갈라진다(14.2).
    /// 이미지(OCR)는 이 함수가 `OCRResult`(draft)까지만 만들고 끝난다 — 실제
    /// `DocumentText` 반영과 `index_status = indexed`는 S7 검수 화면에서 사용자가
    /// "저장 후 다음"을 눌러야 일어난다(14.3, ChapterSummaryDeduplication과 같은
    /// "사용자 확정 전엔 반영 안 함" 원칙).
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

        // [2026-09-05 추가] 사용자 요청 — "연구문서 combinedText 반복 재생성
        // 문제를 캐싱 필드로 해결." 위 분기가 무엇이었든(이미지 OCR은 여기서
        // `documentTexts`를 아직 안 채운다 — 클래스 상단 주석 참고, 그 경우엔
        // 그냥 빈 문자열로 정확히 반영된다) `documentTexts`가 이 호출로 확정된
        // 뒤 캐시를 한 번만 다시 만들어 저장한다. 각 개별 분기(`extractPDF`
        // 등) 안에서 이미 여러 차례 `context.save()`가 일어나지만, 캐시
        // 필드는 여기 한 곳에서만 갱신·저장하면 모든 형식을 다 커버한다 —
        // 형식별 함수 6개를 각각 건드릴 필요가 없다.
        document.rebuildCachedCombinedText()
        // [2026-09-05 추가] 사용자 요청 — "개요/메모/개인 묵상/말씀 요약/
        // 연구문서 5개 카테고리 전체스캔 최적화 → FTS5 보조 인덱스(unicode61)."
        // 캐시 필드를 다시 만든 바로 이 시점에 인덱스도 함께 최신화한다 —
        // `cachedCombinedText`를 갱신하는 지점과 어긋나면 인덱스가 옛 본문을
        // 가리키게 된다. 실패해도 무시(`UserContentSearchIndexLocation.upsert`
        // 선언부 주석 참고).
        UserContentSearchIndexLocation.upsert(
            category: .document, sourceId: document.id.uuidString, content: document.cachedCombinedText
        )
        try? context.save()
    }

    // MARK: - PDF (높은 신뢰도)

    private static func extractPDF(_ document: SourceDocument, context: ModelContext) async {
        document.conversionStatus = .convertingNative
        try? context.save()

        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼 —
        // originalFilePath가 있으면 그걸로, 없으면(구버전 문서) 북마크로 폴백.
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
            // 페이지는 있으나 텍스트 레이어가 없는 스캔 PDF일 수 있다 — OCR 재시도가
            // 아니라 "실패, 수동 필요"로 정직하게 표시한다(이 v1 범위는 PDF 내부
            // 이미지에 대한 자동 OCR 폴백까지는 포함하지 않는다).
            document.conversionStatus = .failedNeedsManual
        }
        try? context.save()
        // [2026-08-11 추가] 사용자 요청 — "연구문서를 등록할 때마다 관련 성경구절
        // 인덱스 재계산." 이 문서가 방금 `indexed`가 됐을 때만(`anyPageExtracted`)
        // 실제로 추출한다 — 실패 케이스는 `reindexDocument` 내부에서
        // `indexStatus != .indexed`로 스스로 걸러진다.
        BibleReferenceIndexingService.reindexDocument(document, context: context)
    }

    // MARK: - 이미지 OCR (14.3, 검수 필수)

    private static func extractImageOCR(_ document: SourceDocument, context: ModelContext) async {
        document.indexStatus = .indexing
        try? context.save()

        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼 —
        // originalFilePath가 있으면 그걸로, 없으면(구버전 문서) 북마크로 폴백.
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
            let lines = observations.compactMap { $0.topCandidates(1).first }
            let rawText = lines.map(\.string).joined(separator: "\n")
            let averageConfidence = lines.isEmpty ? 0 : Double(lines.map(\.confidence).reduce(0, +)) / Double(lines.count)

            let result = OCRResult(
                rawText: rawText,
                engine: "Vision(VNRecognizeTextRequest)",
                confidence: averageConfidence,
                status: .draft,
                sourceDocument: document
            )
            context.insert(result)
            // 14.3 — draft인 동안은 index_status가 indexed로 넘어가지 않는다. S7에서
            // 사용자가 확정해야 비로소 indexed가 된다(OCRReviewViewModel 참고).
            document.indexStatus = .notIndexed
            document.conversionStatus = .converted // "추출(=OCR 실행) 자체"는 끝났다는 의미.
            try? context.save()
        } catch {
            document.conversionStatus = .failedNeedsManual
            document.indexStatus = .notIndexed
            try? context.save()
        }
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

        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼 —
        // originalFilePath가 있으면 그걸로, 없으면(구버전 문서) 북마크로 폴백.
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
            // 전용 값이 없다 — pdfkitNative를 추가했던 것과 같은 사유로 이 시점엔
            // 새 케이스를 또 추가하지 않고 가장 가까운 기존 값(userPreconverted)으로
            // 근사했다. 정확한 명칭이 필요하면 pdfkitNative처럼 케이스를 하나 더
            // 추가하는 편이 맞다 — 제품 결정 필요.
            document.conversionStatus = .converted
            document.indexStatus = .indexed
            try? context.save()
            // [2026-08-11 추가] 위 PDF 분기와 같은 이유.
            BibleReferenceIndexingService.reindexDocument(document, context: context)
        } catch {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
        }
        #else
        // iOS/iPadOS — NSAttributedString.DocumentType.docFormat는 AppKit(macOS)
        // 전용이라 iOS엔 대응 API가 없다(스펙 14.2가 "확인 안 됨"으로 남긴 항목을
        // 실제 확인해 보니 iOS에는 이 상수 자체가 없었다). 추측성 시도 대신 바로
        // 실패 처리한다 — 원본 파일은 그대로 열람 가능(14.5).
        document.conversionStatus = .failedNeedsManual
        try? context.save()
        #endif
    }

    // MARK: - docx(Office Open XML) — SwiftTextDOCX(크로스플랫폼, .doc과 달리 iOS도 지원)

    /// [2026-08-16 추가] 사용자 요청 — "doc, docx 업로드 지원." `.doc`과 달리
    /// `SwiftTextDOCX`(zip+XML 파서, NSAttributedString 미사용)는 macOS/iOS
    /// 모두 동작해 `#if os(macOS)` 분기가 필요 없다. DOCX엔 PDF/hwp처럼
    /// "쪽(page)" 개념이 없어(문단만 있음) `insertLines`엔 항상 `pageNumber: 0`
    /// 하나로 전체 본문을 넘긴다 — 검색/미리보기 쪽에서 페이지 단위 이동을
    /// 기대하지 않는 한 문제 없다(hwp/pdf처럼 페이지별 뷰어가 애초에 없음).
    private static func extractDocx(_ document: SourceDocument, context: ModelContext) {
        document.conversionStatus = .convertingNative
        try? context.save()

        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼 —
        // originalFilePath가 있으면 그걸로, 없으면(구버전 문서) 북마크로 폴백.
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
            // [2026-08-11 추가한 PDF/doc 분기와 같은 이유] 추출 직후 성경구절 인덱싱.
            BibleReferenceIndexingService.reindexDocument(document, context: context)
        } catch {
            document.conversionStatus = .failedNeedsManual
            try? context.save()
        }
    }

    // MARK: - pages(iWork) — SwiftTextPages(크로스플랫폼, 자체 Snappy+protobuf 구현)

    /// [2026-08-16 추가, 이전 제외 결정 번복] 사용자 재확인 요청 — "SwiftText가
    /// pages도 파싱할 수 있다 하니 확인할 것." 처음엔 `.pages`(iWork Archive,
    /// Protobuf+Snappy, Apple 비공개 포맷)를 읽을 크로스플랫폼 Swift 파서가
    /// 없다고 판단했었다. 그런데 `SwiftTextPages`(`.docx`에 이미 쓴 SwiftText
    /// 패키지의 다른 모듈)의 실제 소스(`PagesFile.swift`)를 직접 읽어 보니
    /// Snappy 블록 해제 + protobuf 와이어 디코딩까지 패키지 안에서 순수 Swift로
    /// 구현돼 있었다(Apple 프레임워크·Pages.app 불필요, README 주장을 소스로
    /// 직접 검증) — `.docx`와 완전히 같은 방식(`extractDocx` 바로 위 참고)으로
    /// 붙인다. DOCX와 마찬가지로 "쪽(page)" 개념이 없어 문단을 한 번에
    /// `pageNumber: 0`으로 넘긴다.
    private static func extractPages(_ document: SourceDocument, context: ModelContext) {
        document.conversionStatus = .convertingNative
        try? context.save()

        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼 —
        // originalFilePath가 있으면 그걸로, 없으면(구버전 문서) 북마크로 폴백.
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

    /// [2026-08-16 폴백 체인 추가] 사용자가 실기기에서 hwp-swift 네이티브
    /// 파서가 특정 문서를 못 여는 사례를 보고했다 — "hwp 문서를 열지
    /// 못했습니다. Presentation build failed: Bytes are not EOF : 4 bytes
    /// remain in HwpIdMappings." hwp-swift 저장소를 직접 조사한 결과(GitHub
    /// 이슈 #83, `HwpIdMappings.swift` 소스 확인): 이 모델은 문서 버전에 따라
    /// `memoShapeCount`/`changeTraceCount`/`changeTraceUserCount` 필드를
    /// 조건부로 읽고, 다 읽은 뒤 `!reader.isEOF`면 곧바로 예외를 던지는 엄격한
    /// 검증을 한다 — 이 문서는 그 버전 경계에서 실제 필드 구성과 어긋나는
    /// 것으로 보인다. 현재(2026-08-16) hwp-swift에 이 케이스를 위한 알려진
    /// 수정은 없다(관련 이슈는 이 EOF 강제 자체를 다루는 리팩터링 이슈뿐,
    /// 버전 경계 완화는 아니다) — 즉 우리 쪽에서 코드로 "고칠 수 있는" 버그가
    /// 아니라 제3자 라이브러리의 현재 한계다.
    ///
    /// 대신 사용자 질문("네이티브에서만 텍스트추출이 실패한 것으로 보이는데,
    /// rhwp에서 추출을 진행할 수 있는가? PDF 변환 파일에서 추출을 하는 것으로
    /// 할 수 있는가?")에 따라 3단계 폴백 체인을 둔다:
    /// 1) `extractHWPNative` — hwp-swift(기존 경로, 가장 신뢰도 높음)
    /// 2) `extractHWPViaRhwp` — 네이티브가 실패하면 rhwp(WKWebView, WASM)로
    ///    같은 문서를 다시 열어 `getPageText`로 재시도. 서로 다른 파서 구현이라
    ///    한쪽 한계를 다른 쪽이 우회할 수 있다.
    /// 3) `extractHWPFromConvertedPDF` — 그마저 실패하면, 업로드 시 미리
    ///    만들어 둔 `ConvertedPDF`(rhwp SVG → WKWebView.createPDF)가 있을 때
    ///    PDFKit의 `PDFPage.string`으로 마지막 시도. `DocumentsViewModel.upload`
    ///    가 PDF 사전 생성을 텍스트 추출보다 먼저 호출하도록 순서를 바꿔서, 이
    ///    시점엔 이미 `ConvertedPDF`가 있을 수 있다.
    private static func extractHWP(_ document: SourceDocument, context: ModelContext) async {
        document.conversionStatus = .convertingNative
        try? context.save()

        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼 —
        // originalFilePath가 있으면 그걸로, 없으면(구버전 문서) 북마크로 폴백.
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

        // [2026-09-02 추가] 이 함수 자체가 "재시도" 액션으로 다시 호출될 수
        // 있다(`extract(for:context:)` doc 주석 참고) — 이전 시도(성공이든
        // 실패든)가 남긴 `DocumentText`가 있으면 이번 추출분과 중복 저장되므로,
        // 1차 시도 전에 먼저 지운다.
        clearDocumentTexts(for: document, context: context)

        var extracted = false
        do {
            extracted = try await extractHWPNative(data: data, document: document, context: context)
        } catch {
            print("[DocumentTextExtractionService] hwp 네이티브(hwp-swift) 추출 실패, rhwp 폴백 시도: \(error)")
        }

        if !extracted {
            // [2026-09-02 추가] 사용자 보고 — "같은 절 언급이 한 문서에서 5개나
            // 중복으로 뜸." 원인: `extractHWPNative`는 페이지마다 성공하는 대로
            // `insertLines`로 즉시 저장하는데, 일부 페이지까지만 성공하고 그
            // 다음 페이지에서 파싱 에러(예: `HwpIdMappings` 버전 경계 문제)로
            // throw하면, 이미 저장된 앞쪽 페이지들의 `DocumentText`는 지워지지
            // 않은 채 그대로 남는다. 그 상태에서 rhwp 폴백이 (보통 전체 페이지를)
            // 다시 추출해 또 `insertLines`하면, 앞쪽 페이지 구간이 두 번
            // 저장돼 — 그 구간에 있는 성경 장절 언급이 재인덱싱 시 문자 그대로
            // 중복으로 걸린다("본문에서 언급됨"에 똑같은 행이 여러 번 뜨는 원인).
            // 폴백을 시도하기 전에 방금 실패한 시도가 남긴 부분 결과부터 지운다.
            clearDocumentTexts(for: document, context: context)
            do {
                extracted = try await extractHWPViaRhwp(data: data, document: document, context: context)
            } catch {
                print("[DocumentTextExtractionService] hwp rhwp(WKWebView) 폴백도 실패, PDF 텍스트 레이어 폴백 시도: \(error)")
            }
        }

        if !extracted {
            // 위와 같은 이유 — rhwp 폴백이 일부만 성공하고 실패했을 가능성에
            // 대비해 PDF 텍스트 레이어 폴백 전에도 한 번 더 지운다.
            clearDocumentTexts(for: document, context: context)
            extracted = extractHWPFromConvertedPDF(document: document, context: context)
        }

        if extracted {
            document.conversionStatus = .converted
            document.indexStatus = .indexed
        } else {
            // 세 경로 모두 텍스트를 못 뽑은 경우(진짜 빈 문서, 이미지만 있는
            // 문서, 세 파서 모두의 한계에 걸리는 문서 등) — PDF 분기의 "텍스트
            // 레이어 없는 스캔 PDF" 처리와 같은 원칙으로 "실패, 수동 필요"로
            // 정직하게 떨어뜨린다. 원본은 DocumentViewerView.swift의 뷰어로
            // (안 열리는 탭은 자동으로 숨겨지고) 계속 열람할 수 있다.
            document.conversionStatus = .failedNeedsManual
        }
        try? context.save()
        // [2026-08-11 추가 원칙 유지] 위 PDF/doc 분기와 같은 이유 — 방금
        // `indexed`가 됐을 때만 실제로 재인덱싱한다(실패 케이스는
        // `reindexDocument` 내부에서 스스로 걸러진다).
        BibleReferenceIndexingService.reindexDocument(document, context: context)
    }

    /// 1차 — hwp-swift(HwpKit) 네이티브 파서. 페이지별로 블록(`.text`/`.table`/
    /// `.textbox`/`.footnote` 등)의 `attributedString.string`을 이어 붙인다 —
    /// PDF 분기(`PDFPage.string`)와 같은 "페이지 단위 순수 텍스트" 모양을
    /// 맞춰 `insertLines`가 페이지 번호(0-based)를 그대로 쓸 수 있게 한다.
    /// 파싱 자체가 실패하면(예: HwpIdMappings 버전 경계 문제) throw한다 — 파싱은
    /// 됐지만 뽑힌 텍스트가 없는 경우(빈 문서 등)는 throw하지 않고 `false`만
    /// 돌려준다(둘 다 상위에서 다음 폴백으로 넘어가는 신호이므로 구분할 필요는
    /// 없지만, 로그 메시지가 더 정확해진다).
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

    /// 2차 — hwp-swift 네이티브 파서가 이 문서를 못 열 때의 폴백. 렌더링에 이미
    /// 쓰고 있는 rhwp(WASM, WKWebView)로 같은 문서를 다시 열어
    /// `HwpDocument.getPageText(page_index)`(웹한글컨트롤 GetPageText와 같은
    /// API)로 쪽별 순수 텍스트를 뽑는다. `RhwpPDFExportService.
    /// extractPlainText`가 이미 검증된 "오프스크린 숨김 윈도우에 WKWebView를
    /// 붙여서 문서를 로드"하는 인프라를 그대로 재사용한다 — PDF 변환(`createPDF`
    /// 호출 포함)과 달리 이 경로는 JS 실행/파싱만 필요하고 화면 합성
    /// (compositing) 스냅샷이 필요 없어서, 실기기에서 확인된 RunningBoard
    /// 문제(`createPDF` 근처에서 발생)에 걸릴 가능성이 상대적으로 낮다.
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

    /// 3차(마지막) — 네이티브·rhwp 둘 다 실패했을 때, 업로드 시 미리 만들어
    /// 둔 `ConvertedPDF`(rhwp SVG → `WKWebView.createPDF`,
    /// `DocumentUploadService.generateConvertedPDF` 참고)가 있으면 PDFKit의
    /// `PDFPage.string`으로 텍스트를 뽑아 본다. rhwp가 SVG `<text>` 요소로
    /// 글자를 그리면(래스터 이미지가 아니라) WKWebView의 PDF 내보내기가 그
    /// 텍스트를 실제 선택 가능한 텍스트 레이어로 보존할 가능성이 있다 — 다만
    /// 이건 확실히 검증된 동작은 아니라 "밑져야 본전" 수준의 마지막 시도다.
    /// 레코드가 아직 없으면(예: PDF 사전 생성도 실패했거나, 애초에 hwp/hwpx가
    /// 아니어서 시도조차 안 했으면) 조용히 false를 돌려준다.
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

    /// [2026-09-02 추가] hwp 3단계 폴백 체인이 중간 tier에서 부분적으로
    /// `insertLines`한 뒤 다음 tier로 넘어갈 때, 그리고 `extract(for:context:)`
    /// 자체가 "재시도" 액션으로 다시 호출될 때(위 doc 주석 참고) 이전에 이미
    /// 저장된 `DocumentText`가 남아 있으면 재추출분과 중복 저장된다 — 두
    /// 경우 모두 다음 추출을 시작하기 전에 기존 레코드를 지워 정리한다.
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

    /// [2026-09-02 추가, 미확인/방어적 조치] 사용자 보고 — "성경조회 인스펙터의
    /// 관련연구문서 목록에 줄바꿈 기호(\r\n)가 그대로 보임." `components(separatedBy:
    /// .newlines)`는 실제 개행 제어문자(LF/CR/CRLF 등)는 이미 줄 단위로 나눠
    /// 처리하므로, 화면에 "\r\n"이라는 4글자가 문자 그대로 보인다면 원본
    /// 추출 텍스트 자체에 이스케이프된 백슬래시-r-백슬래시-n 문자열이 들어있는
    /// 경우로 추정된다(예: 2차 rhwp(WKWebView/WASM) 폴백의 `getPageText`
    /// 반환값). 실제 사용자 데이터를 확인할 방법이 없어 확정 원인은 아니지만,
    /// 이 리터럴 이스케이프 시퀀스를 공백으로 치환해 두면 어느 추출 경로에서
    /// 나오든 방어적으로 화면에 노출되지 않는다.
    private static func sanitizeLineText(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\\r\\n", with: " ")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
    }
}
