import Foundation
import SwiftData

// 연구문서 파이프라인 모델(업로드된 원본, 추출 텍스트, 변환 PDF, OCR 결과, 마크다운,
// 문서 앵커)과 OCR 이미지 분류.

/// 사진(OCR 대상) 분류. "이건 설교자료다" 같은 사진 자체의 속성이라
/// `SourceDocument`에 부착한다(`OCRResult`가 아님 — 재-OCR해도 바뀌지 않으므로).
@Model
public final class ImageCategory {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date.now

    // ⚠️ to-many @Relationship은 타입 자체가 Optional이어야 CloudKit이 받아들인다
    // (Tags.swift 상단 주석 참고).
    @Relationship(deleteRule: .nullify, inverse: \SourceDocument.category)
    public var sourceDocuments: [SourceDocument]? = []

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// 지원하는 업로드 원본 형식. `.doc`(구 바이너리 워드)은 macOS에서만
/// `NSAttributedString(.docFormat)`로 추출할 수 있고, `.docx`/`.pages`는
/// SwiftText 패키지(SwiftTextDOCX/SwiftTextPages)로 iOS/macOS 모두 추출한다
/// (DocumentTextExtractionService.swift의 `extractDocx`/`extractPages` 참고).
public enum OriginalFormat: String, Codable, Sendable, CaseIterable {
    case hwp, hwpx, doc, docx, pages, pdf, image
}

public enum StorageLocationKind: String, Codable, Sendable, CaseIterable {
    case userFolder = "user_folder"
    case icloudDrive = "icloud_drive"
    case appManagedFallback = "app_managed_fallback"
}

public enum ConversionStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case convertingNative = "converting_native"
    case converted
    case failedNeedsManual = "failed_needs_manual"
}

public enum IndexStatus: String, Codable, Sendable, CaseIterable {
    case notIndexed = "not_indexed"
    case indexing
    case indexed
}

public enum ConverterUsed: String, Codable, Sendable, CaseIterable {
    /// 사용하지 않는 레거시 값(하위 호환용으로만 유지). rhwp에 Swift에서 직접 링크할
    /// 수 있는 C ABI가 없어 네이티브 FFI 브리징은 쓰지 않았고, hwp/hwpx 처리는
    /// `rhwpWasm`(WKWebView + WASM) 계열로 구현했다.
    case rhwpNativeFfi = "rhwp_native_ffi"
    case userPreconverted = "user_preconverted"
    /// PDFKit 네이티브 추출 경로(pdf 업로드).
    case pdfkitNative = "pdfkit_native"
    /// 폐기된 레거시 값. 예전 hwp/hwpx 텍스트 추출(`HWPTextExtractor`, WKWebView 안의
    /// rhwp WASM)이 App Sandbox에서 WebContent 프로세스 실패를 반복해 `hwpSwiftNative`로
    /// 대체됐다. 과거에 이 값으로 저장된 레코드의 하위 호환을 위해서만 남겨 둔다.
    case rhwpWasm = "rhwp_wasm"
    /// hwp-swift(LGPL-2.1)의 `HwpKit.HwpDocumentLoader` — 순수 네이티브 Swift 파서.
    /// `DocumentTextExtractionService.extractHWP`가 페이지별 블록의
    /// `attributedString.string`을 이어 붙여 텍스트를 뽑는다.
    case hwpSwiftNative = "hwp_swift_native"
    /// 업로드 시점에 `RhwpPDFExportService`(rhwp `renderPageSvg` → 오프스크린
    /// WKWebView → `createPDF`)로 미리 만들어 둔 `ConvertedPDF`에 쓴다.
    /// `SourceDocument.converterUsed`가 아니라 `ConvertedPDF.converterUsed`에만 쓰인다.
    case rhwpWebViewPDFExport = "rhwp_webview_pdf_export"
    /// `hwpSwiftNative`가 실패하는 문서(hwp-swift의 `HwpIdMappings` 버전별 필드
    /// 파싱 불일치로 조사됨, 상류에 알려진 수정 없음)에 대한 폴백.
    /// `DocumentTextExtractionService.extractHWPViaRhwp`가
    /// `RhwpPDFExportService.extractPlainText`(rhwp WASM `getPageText`)로 페이지별
    /// 텍스트를 뽑는다. 폐기된 `rhwpWasm`과는 다른 코드 경로다.
    case rhwpWebViewTextFallback = "rhwp_webview_text_fallback"
    /// `.docx`를 `SwiftTextDOCX`(SwiftText, MIT, 크로스플랫폼)로 추출.
    /// `.doc`의 `userPreconverted`(macOS 전용 NSAttributedString 경로)와 구분한다.
    case swiftTextDocx = "swift_text_docx"
    /// `.pages`를 `SwiftTextPages`(Snappy 해제 + protobuf 디코딩을 순수 Swift로 구현,
    /// macOS/iOS 모두 동작)로 추출.
    case swiftTextPages = "swift_text_pages"
    /// docxide-pdf(Rust, native/docxide-pdf-ffi로 감쌈)로 `.docx`를 미리 PDF로 변환한
    /// `ConvertedPDF`에 쓴다(`SourceDocument.converterUsed`가 아니라
    /// `ConvertedPDF.converterUsed`에만 쓰임). macOS 전용 — iOS는 폰트 처리 한계로
    /// 제외(`DocxToPDFConverter.swift` 참고).
    case docxidePdf = "docxide_pdf"
    case none
}

/// 업로드된 원본 파일 1개 = 행 1개. 원본 파일 바이트 자체는 앱 DB/CloudKit에 복제하지
/// 않고 사용자 지정 저장공간에 그대로 둔다 — `fileBookmark`는 그 위치를 가리키는
/// security-scoped bookmark(또는 경로 참조)만 저장한다(schema.md 3장).
@Model
public final class SourceDocument {
    public var id: UUID = UUID()
    public var originalFilename: String = ""
    public var originalFormat: OriginalFormat = OriginalFormat.pdf

    /// security-scoped bookmark 원시 데이터. ⚠️ 이 북마크는 생성한 기기에서만 안정적으로
    /// 해석된다(기기 간 이식 미보장) — 다른 기기에서는 파일이 iCloud로 내려받아져
    /// 있어도 열 수 없다. `storageLocationKind == .icloudDrive`는 `originalFilePath`를
    /// 우선 쓰므로, 이 필드는 `.userFolder`/`.appManagedFallback`(앱이 소유하지 않는
    /// 외부 파일)를 열 때만 필요하다.
    public var fileBookmark: Data?

    /// 이 앱 iCloud 컨테이너 "Documents/" 아래의 상대 경로(예: "연구 문서/설교문.docx").
    /// `storageLocationKind == .icloudDrive`일 때만 값이 있다. 컨테이너의 절대 경로는
    /// 기기/재설치마다 달라질 수 있어 상대 경로로 저장하고, 열 때마다
    /// `FileManager.url(forUbiquityContainerIdentifier:)`로 절대 경로를 계산한다
    /// (`DocumentUploadService.resolveOriginalFileURL(for:)`, `ConvertedPDF.pdfPath`와
    /// 같은 방식). 북마크와 달리 기기 간 동기화돼도 동일하게 계산된다. nil인 기존
    /// 문서는 원본을 성공적으로 여는 순간 소급으로 채워진다.
    public var originalFilePath: String?

    public var storageLocationKind: StorageLocationKind = StorageLocationKind.appManagedFallback
    public var conversionStatus: ConversionStatus = ConversionStatus.pending
    public var indexStatus: IndexStatus = IndexStatus.notIndexed
    public var converterUsed: ConverterUsed = ConverterUsed.none
    public var uploadedAt: Date = Date.now

    // deleteRule은 ImageCategory.sourceDocuments 쪽(inverse 선언부)에서만 지정한다 —
    // 같은 관계 양쪽에 중복 지정하지 않는다.
    public var category: ImageCategory?

    /// 이 문서가 관련된 성경 장(업로드 시 또는 문서 목록에서 사용자가 지정). 성경
    /// 읽기 화면에서 장과 관련된 연구문서를 보여주는 데 쓴다.
    ///
    /// `DocumentAnchor.linkedVerse`(verse 필수)를 재사용하지 않는다 — 앵커는 "문서 안
    /// 특정 위치와 구절/태그의 연결"이라 "문서 전체가 이 장과 관련 있다"는 문서 레벨
    /// 메타데이터와 의미가 다르고, 없는 verse에 임의 값을 채우는 것도 피하기 위해
    /// 책+장 전용 값 타입 `BibleChapterRef`를 쓴다.
    public var relatedChapterRef: BibleChapterRef?

    @Relationship(deleteRule: .cascade, inverse: \DocumentText.sourceDocument)
    public var documentTexts: [DocumentText]? = []

    @Relationship(deleteRule: .cascade, inverse: \ConvertedPDF.sourceDocument)
    public var convertedPDFs: [ConvertedPDF]? = []

    @Relationship(deleteRule: .cascade, inverse: \OCRResult.sourceDocument)
    public var ocrResults: [OCRResult]? = []

    @Relationship(deleteRule: .cascade, inverse: \DocumentAnchor.sourceDocument)
    public var anchors: [DocumentAnchor]? = []

    @Relationship(deleteRule: .cascade, inverse: \DocumentMarkdown.sourceDocument)
    public var markdownRevisions: [DocumentMarkdown]? = []

    /// `UserMemo.memoTags`와 같이 이 쪽에는 `@Relationship`을 붙이지 않는다 — 반대편
    /// (`DocumentTag.document`, Tags.swift)이 이미 `inverse:`로 가리키고 있어, 양쪽에
    /// 붙이면 SwiftData가 같은 관계를 두 개로 오인할 수 있다(inverse는 한쪽에만 선언).
    public var documentTags: [DocumentTag]? = []

    /// 사이드바에 고정 표시. 기본값 있는 저장 프로퍼티 추가라 SwiftData 가벼운
    /// 마이그레이션이 자동 처리한다.
    public var isPinned: Bool = false

    /// `documentTexts`(페이지×줄)를 정렬·이어붙인 검색용 캐시. 검색 때마다 다시 계산하지
    /// 않도록 문서 텍스트가 바뀔 때만 계산해 저장하고, 검색은 이 필드를 읽기만 한다.
    ///
    /// ⚠️ `documentTexts`의 파생값이므로 `documentTexts`를 쓰는 모든 지점
    /// (`DocumentTextExtractionService.extract(for:context:)` 끝,
    /// `OCRReviewViewModel.save()`, 앞으로 추가될 코드 포함)이 반드시
    /// `rebuildCachedCombinedText()`를 함께 호출해야 어긋나지 않는다.
    ///
    /// 이 필드 도입 이전에 업로드된 문서는 빈 문자열이며, 백필은 호출부
    /// (`SearchViewModel.searchDocuments`)가 `documentTexts`는 있는데 캐시만 빈
    /// 경우에 한해 다시 만들어 저장한다.
    public var cachedCombinedText: String = ""

    public init(
        id: UUID = UUID(),
        originalFilename: String,
        originalFormat: OriginalFormat,
        fileBookmark: Data? = nil,
        originalFilePath: String? = nil,
        storageLocationKind: StorageLocationKind,
        conversionStatus: ConversionStatus = .pending,
        indexStatus: IndexStatus = .notIndexed,
        converterUsed: ConverterUsed = .none,
        category: ImageCategory? = nil,
        relatedChapterRef: BibleChapterRef? = nil,
        isPinned: Bool = false,
        uploadedAt: Date = .now
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.originalFormat = originalFormat
        self.fileBookmark = fileBookmark
        self.originalFilePath = originalFilePath
        self.storageLocationKind = storageLocationKind
        self.conversionStatus = conversionStatus
        self.indexStatus = indexStatus
        self.converterUsed = converterUsed
        self.category = category
        self.relatedChapterRef = relatedChapterRef
        self.isPinned = isPinned
        self.uploadedAt = uploadedAt
    }

    /// `documentTexts`를 `pageNumber`/`lineIndex` 오름차순으로 정렬해 이어붙여
    /// `cachedCombinedText`에 저장한다. 저장(`context.save()`)은 호출부 책임이다
    /// (이 메서드는 SwiftData 컨텍스트를 모르므로).
    public func rebuildCachedCombinedText() {
        let lines = (documentTexts ?? []).sorted {
            $0.pageNumber != $1.pageNumber ? $0.pageNumber < $1.pageNumber : $0.lineIndex < $1.lineIndex
        }
        cachedCombinedText = lines.map(\.lineText).joined(separator: "\n")
    }
}

/// 순수 텍스트는 파일과 분리되어 앱 자체 DB에 저장된다(schema.md 3장). 줄 단위.
@Model
public final class DocumentText {
    public var id: UUID = UUID()
    public var pageNumber: Int = 0
    public var lineIndex: Int = 0
    public var lineText: String = ""
    public var createdAt: Date = Date.now

    /// 이미지 OCR 줄의 이미지 내 위치(Vision `VNRecognizedTextObservation.boundingBox`).
    /// `DocumentTextExtractionService.extractImageOCR`가 채우며, "x,y,width,height"
    /// 콤마 구분 문자열로 인코딩한다(`DocumentAnchor.bboxOrOffset`과 같은 관례).
    /// 값은 Vision 그대로 정규화 좌표(0...1)이고 **좌하단 원점**이라, UIKit/SwiftUI
    /// 좌상단 원점으로 그릴 때는 y축을 뒤집어야 한다. OCR이 아닌 형식이나 이 필드
    /// 추가 이전의 OCR 레코드는 nil이며, 그 경우 위치 오버레이 없이 텍스트만 취급한다.
    public var ocrBoundingBox: String?

    public var sourceDocument: SourceDocument?

    public init(
        id: UUID = UUID(),
        pageNumber: Int,
        lineIndex: Int,
        lineText: String,
        ocrBoundingBox: String? = nil,
        sourceDocument: SourceDocument? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.pageNumber = pageNumber
        self.lineIndex = lineIndex
        self.lineText = lineText
        self.ocrBoundingBox = ocrBoundingBox
        self.sourceDocument = sourceDocument
        self.createdAt = createdAt
    }
}

/// 업로드 시 `DocumentUploadService.generateConvertedPDF(for:context:)`가 미리 만들어
/// 둔 변환 PDF(선택 기능). "PDF 변환" 탭(`HWPToPDFPane`)이 열 때마다 다시 변환하지
/// 않고 이 파일을 연다. `pdfPath`는 이 앱 iCloud 컨테이너 "Documents/" 아래의 상대
/// 경로(예: "연구 문서/이사야 1장.pdf")다 — 컨테이너의 절대 경로는 기기/재설치마다
/// 달라질 수 있어 절대 경로로 저장하면 나중에 열 수 없다. 이 레코드가 없는 문서는
/// 소급 변환하지 않으며, `HWPToPDFPane`이 여는 즉시 변환하는 경로로 대체한다.
@Model
public final class ConvertedPDF {
    public var id: UUID = UUID()
    public var pdfPath: String = ""
    public var pageCount: Int = 0
    public var converterUsed: ConverterUsed = ConverterUsed.none
    public var convertedAt: Date = Date.now

    public var sourceDocument: SourceDocument?

    public init(
        id: UUID = UUID(),
        pdfPath: String,
        pageCount: Int,
        converterUsed: ConverterUsed,
        sourceDocument: SourceDocument? = nil,
        convertedAt: Date = .now
    ) {
        self.id = id
        self.pdfPath = pdfPath
        self.pageCount = pageCount
        self.converterUsed = converterUsed
        self.sourceDocument = sourceDocument
        self.convertedAt = convertedAt
    }
}

public enum OCRStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case userReviewed = "user_reviewed"
    case aiRefined = "ai_refined"
    case final
}

/// `status = draft`인 동안은 검색 대상이 아니다(사용자 확인을 거쳐 저장).
/// `[저장 후 다음]`으로 `user_reviewed`가 되어야 `DocumentText` 동급 레코드로 반영된다.
@Model
public final class OCRResult {
    public var id: UUID = UUID()
    public var rawText: String = ""
    public var engine: String = ""
    public var confidence: Double = 0
    public var status: OCRStatus = OCRStatus.draft

    public var sourceDocument: SourceDocument?

    public init(
        id: UUID = UUID(),
        rawText: String,
        engine: String,
        confidence: Double,
        status: OCRStatus = .draft,
        sourceDocument: SourceDocument? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.engine = engine
        self.confidence = confidence
        self.status = status
        self.sourceDocument = sourceDocument
    }
}

/// 문서 파이프라인 산출용 마크다운. 리치텍스트 통일(content_html/content_text) 대상은
/// UserMemo/BookOutline/ChapterSummary뿐이라, 여기는 `content_md`를 그대로 유지한다.
@Model
public final class DocumentMarkdown {
    public var id: UUID = UUID()
    public var contentMd: String = ""
    public var version: Int = 1
    public var editedBy: String = ""
    public var createdAt: Date = Date.now

    public var sourceDocument: SourceDocument?

    public init(
        id: UUID = UUID(),
        contentMd: String,
        version: Int = 1,
        editedBy: String,
        sourceDocument: SourceDocument? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.contentMd = contentMd
        self.version = version
        self.editedBy = editedBy
        self.sourceDocument = sourceDocument
        self.createdAt = createdAt
    }
}

public enum DocumentAnchorSourceKind: String, Codable, Sendable, CaseIterable {
    case hwpNativeText = "hwp_native_text"
    case hwpNativeRenderTree = "hwp_native_render_tree"
    case ocrPdf = "ocr_pdf"
}

public enum DocumentAnchorType: String, Codable, Sendable, CaseIterable {
    case verseRef = "verse_ref"
    case keyword
    case phrase
}

/// 문서/OCR 이미지 내 특정 위치와 (성경 구절 | 태그 | 임의 구절) 사이의 연결.
/// 키워드 연결은 `linkedTag`로 통일했다. OCR 이미지는 검수 확정된 텍스트가
/// `DocumentText` 동급으로 취급되므로 같은 메커니즘을 공유한다.
@Model
public final class DocumentAnchor {
    public var id: UUID = UUID()
    public var pageNumber: Int = 0
    public var lineIndex: Int?
    public var sourceKind: DocumentAnchorSourceKind = DocumentAnchorSourceKind.hwpNativeText
    public var bboxOrOffset: String = ""
    public var anchorType: DocumentAnchorType = DocumentAnchorType.phrase
    public var anchorValue: String = ""

    /// `anchorType == .verseRef`일 때만 사용. BibleVerses는 이 레이어 밖에 있으므로
    /// 관계가 아니라 값으로 저장(BibleCoordinates.swift 상단 원칙 참고).
    public var linkedVerse: BibleVerseRef?

    /// `anchorType == .keyword`일 때만 사용.
    public var linkedTag: Tag?

    public var sourceDocument: SourceDocument?

    public init(
        id: UUID = UUID(),
        pageNumber: Int,
        lineIndex: Int? = nil,
        sourceKind: DocumentAnchorSourceKind,
        bboxOrOffset: String,
        anchorType: DocumentAnchorType,
        anchorValue: String,
        linkedVerse: BibleVerseRef? = nil,
        linkedTag: Tag? = nil,
        sourceDocument: SourceDocument? = nil
    ) {
        self.id = id
        self.pageNumber = pageNumber
        self.lineIndex = lineIndex
        self.sourceKind = sourceKind
        self.bboxOrOffset = bboxOrOffset
        self.anchorType = anchorType
        self.anchorValue = anchorValue
        self.linkedVerse = linkedVerse
        self.linkedTag = linkedTag
        self.sourceDocument = sourceDocument
    }
}
