import Foundation
import SwiftData

// 근거: bible-research-platform-schema.md 3장(연구문서 파이프라인) +
// bible-research-platform-screens.md 6.4(OCR 이미지 분류) + 6.3(linked_keyword_id →
// linked_tag_id 통일) + 14장(업로드→인덱싱 프로세스).
//
// ⚠️ converter_used에 `pdfkitNative`를 추가했다 — 14.2 표에 "converter_used enum에
// pdf 경로를 표시할 값이 없다"고 명시적으로 확인 요청이 남아있던 항목이다
// ("원본 아키텍처 수정 지점이라 확인 요청드립니다"). 이 케이스를 빼면 모델이 pdf
// 업로드 흐름을 아예 표현할 수 없어 구현이 막히므로, 이번 구현에서는 값을 추가하는
// 쪽으로 확정했다. 다른 이름(예: 별도 소스 프레임워크 필드 분리)을 원하면 이 한 곳만
// 바꾸면 된다 — 최종 명칭 확정은 여전히 사용자 확인 필요.

/// 6.4 — 사진(OCR 대상) 분류. "이건 설교자료다" 같은 사진 자체의 속성이라
/// `SourceDocument`에 부착한다(`OCRResult`가 아님 — 재-OCR해도 바뀌지 않으므로).
@Model
public final class ImageCategory {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date.now

    // ⚠️ 2026-08-06 실기기 확인: to-many @Relationship은 타입 자체가 Optional이어야
    // CloudKit이 받아들인다(Tags.swift 상단 주석 참고).
    @Relationship(deleteRule: .nullify, inverse: \SourceDocument.category)
    public var sourceDocuments: [SourceDocument]? = []

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// [2026-08-16 `docx` 추가] 사용자 요청 — "doc, docx 업로드 지원." 기존
/// `.doc`(구 바이너리 워드, macOS만 `NSAttributedString(.docFormat)`로 추출
/// 가능 — iOS엔 대응 API가 없음, DocumentTextExtractionService.swift 참고)와
/// 달리 `.docx`(Office Open XML, zip+XML 기반)는 크로스플랫폼 오픈소스
/// 파서(SwiftTextDOCX, MIT — Cocoanetics/SwiftText)로 추출한다 — iPhone에서도
/// 된다는 점이 `.doc`과의 핵심 차이. 자세한 경위는
/// DocumentTextExtractionService.swift의 `extractDocx` 상단 주석 참고.
///
/// [2026-08-16 `pages` 추가, 이전 결정 번복] 사용자 요청 — "pages 업로드 지원
/// 확인." 처음엔(같은 날 이전 조사) 신뢰할 만한 크로스플랫폼 `.pages`(iWork
/// Archive, Protobuf+Snappy, Apple 비공개 포맷) 파서가 없다고 판단해 제외를
/// 유지하기로 했었다. 그런데 사용자가 "SwiftText가 pages도 파싱할 수 있다"며
/// 재확인을 요청했고, 실제로 해당 저장소의 `Sources/SwiftTextPages/
/// PagesFile.swift`를 직접 읽어 확인한 결과 — Snappy 압축 해제와 protobuf
/// 디코딩까지 전부 그 패키지 안에서 순수 Swift로 직접 구현돼 있어(Apple
/// 프레임워크도 Pages.app도 불필요) macOS/iOS 모두 동작한다. `.docx`와 같은
/// 패키지(Cocoanetics/SwiftText)의 `SwiftTextPages` 프로덕트를 그대로 쓴다.
/// 자세한 경위는 DocumentTextExtractionService.swift의 `extractPages` 상단
/// 주석 참고.
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
    /// ⚠️ [2026-08-15 참고] 이 케이스 이름이 예고했던 "네이티브 FFI" 브리징은
    /// 결국 쓰지 않았다 — rhwp(https://github.com/edwardkim/rhwp)가 스스로
    /// "C ABI export is intentionally left for a later PR"라고 밝혀, Swift에서
    /// 직접 링크할 수 있는 인터페이스가 아직 없었기 때문이다. 실제 hwp/hwpx
    /// 뷰어·텍스트 추출은 아래 `rhwpWasm`(WKWebView + WASM)으로 구현했다 —
    /// 이 케이스는 하위 호환을 위해 남겨 두되 더 이상 새로 쓰지 않는다.
    case rhwpNativeFfi = "rhwp_native_ffi"
    case userPreconverted = "user_preconverted"
    /// 14.2에서 확인 요청된 값. PDFKit 네이티브 추출 경로(hwp FFI 불필요, 스키마 0장에서
    /// 이미 PDFKit 채택 확정)를 표시하기 위해 추가. ⚠️ 최종 명칭 확정 필요.
    case pdfkitNative = "pdfkit_native"
    /// [2026-08-15 추가, 2026-08-16 폐기] 사용자 요청 — "pdf 파일처럼 순수
    /// 텍스트를 가져와서 관련 성경구절을 추출하는 프로세스가 있어야 함."
    /// hwp/hwpx의 첫 구현체 — `HWPTextExtractor`가 rhwp WASM(`@rhwp/core`,
    /// WKWebView 안에서 실행)의 `HwpDocument.getTextFileUnicode()`로 문서
    /// 전체 텍스트를 뽑아 왔다. 실기기에서 WKWebView WebContent 프로세스가
    /// App Sandbox 안에서 계속 실패해(DocumentViewerView.swift 상단
    /// [2026-08-16 전면 교체] 참고) `hwpSwiftNative`로 대체됐다 — 이 케이스는
    /// 과거에 이 값으로 저장된 레코드의 하위 호환을 위해서만 남겨 둔다.
    case rhwpWasm = "rhwp_wasm"
    /// [2026-08-16 추가] hwp-swift(https://github.com/sboh1214/hwp-swift,
    /// LGPL-2.1)의 `HwpKit.HwpDocumentLoader` — 순수 네이티브 Swift 파서(WKWebView/
    /// WASM 없음). `DocumentTextExtractionService.extractHWP`가 페이지별
    /// 블록의 `attributedString.string`을 이어 붙여 텍스트를 뽑는다. 위
    /// `rhwpWasm`을 대체한다.
    case hwpSwiftNative = "hwp_swift_native"
    /// [2026-08-16 추가] 사용자 요청 — "hwp 업로드할 때 pdf를 생성하고 pdf
    /// 파일을 열수 있도록." 업로드 시점에 `RhwpPDFExportService`(rhwp의
    /// `renderPageSvg` → 오프스크린 WKWebView → `WKWebView.createPDF`, 자세한
    /// 경위는 그 파일 상단 주석 참고)로 미리 만들어 둔 `ConvertedPDF` 레코드에
    /// 쓴다 — `SourceDocument.converterUsed`(원문 텍스트 추출 경로)와는 별개로,
    /// `ConvertedPDF.converterUsed`에만 쓰인다.
    case rhwpWebViewPDFExport = "rhwp_webview_pdf_export"
    /// [2026-08-16 추가] 사용자 지적 — hwp-swift 네이티브 파서가 못 여는 문서가
    /// 실기기에서 확인됨("Presentation build failed: Bytes are not EOF..." —
    /// hwp-swift의 `HwpIdMappings` 버전별 필드 파싱이 이 문서의 버전 경계와
    /// 어긋나는 것으로 조사됨, 상류에 알려진 수정 없음). `hwpSwiftNative`가
    /// 실패하면 `DocumentTextExtractionService.extractHWPViaRhwp`가 이 값으로
    /// 폴백한다 — `RhwpPDFExportService.extractPlainText`(rhwp WASM,
    /// `HwpDocument.getPageText`)로 페이지별 텍스트를 뽑는다. 위 `rhwpWasm`
    /// (폐기됨, `HWPTextExtractor`라는 다른 코드 경로)과는 구현이 다르다 —
    /// 그쪽은 전면 교체됐지만 이건 명시적 "1차 실패 시 폴백"으로 살아있다.
    case rhwpWebViewTextFallback = "rhwp_webview_text_fallback"
    /// [2026-08-16 추가] 사용자 요청 — "doc, docx 업로드 지원." `.docx`(Office
    /// Open XML)는 `SwiftTextDOCX`(Cocoanetics/SwiftText, MIT, zip+XML 파싱,
    /// 크로스플랫폼)로 추출한다. `.doc`의 `userPreconverted`(근사값, macOS
    /// 전용 NSAttributedString 경로)와 구분하기 위해 새 케이스를 둔다 —
    /// DocumentTextExtractionService.swift `extractDocx` 참고.
    case swiftTextDocx = "swift_text_docx"
    /// [2026-08-16 추가, 이전 제외 결정 번복] 사용자 재확인 요청 — "SwiftText가
    /// pages도 파싱할 수 있다 하니 확인할 것." 실제로 `Sources/SwiftTextPages/
    /// PagesFile.swift`를 직접 읽어 확인됨 — Snappy 해제 + protobuf 디코딩까지
    /// 패키지 안에 순수 Swift로 구현돼 있어 macOS/iOS 모두 동작한다. `.docx`와
    /// 같은 이유로 새 케이스를 둔다 — DocumentTextExtractionService.swift
    /// `extractPages` 참고.
    case swiftTextPages = "swift_text_pages"
    /// [2026-08-16 추가] 사용자 요청 — "docxide-pdf + PDFKit로 docx를 pdf로
    /// 변환하는 것을 검토할 것" → "진행할 것." `rhwpWebViewPDFExport`와 같은
    /// 자리(`SourceDocument.converterUsed`가 아니라 `ConvertedPDF.
    /// converterUsed`에만 쓰임) — docxide-pdf(Rust, Apache-2.0, native/
    /// docxide-pdf-ffi로 감쌈)로 `.docx`를 PDF로 미리 변환해 두면, hwp의
    /// `HWPToPDFPane`처럼 `PDFKitRepresentable`+`pdfSearchBar`로 원본 보기+
    /// 검색이 된다. macOS 전용(iOS는 폰트 처리 한계로 제외 — 사용자 결정,
    /// `DocxToPDFConverter.swift` 상단 주석 참고).
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

    /// security-scoped bookmark 원시 데이터. ⚠️ addendum 3장 미검증 리스크(2026-08-18
    /// 실기기로 확인됨) — 이 북마크는 생성한 기기에서만 안정적으로 해석된다. 다른
    /// Mac에서 열면 파일이 iCloud로 이미 다 내려받아져 있어도 "다른 기기에서는 열 수
    /// 없다"고 나온다(Apple 문서에 명시된 제약 — security-scoped bookmark는 기기
    /// 간 이식을 보장하지 않는다). `storageLocationKind == .icloudDrive`(이 앱
    /// 소유의 iCloud 컨테이너 안에 원본이 복사돼 있는 경우)는 이제 `originalFilePath`
    /// (상대경로 문자열, ConvertedPDF.pdfPath와 같은 방식)를 우선 쓴다 — 이 필드는
    /// `.userFolder`/`.appManagedFallback`(사용자가 앱 바깥에서 고른, 앱이 소유하지
    /// 않는 파일)를 열 때만 여전히 필요하다.
    public var fileBookmark: Data?

    /// [2026-08-18 신설, fileBookmark 기기 간 이식 불가 문제 fix] 이 앱의 iCloud
    /// 컨테이너 "Documents/" 바로 아래부터의 상대 경로(예: "연구 문서/설교문.docx") —
    /// `ConvertedPDF.pdfPath`와 정확히 같은 원리. `storageLocationKind == .icloudDrive`일
    /// 때만 값이 있다. 절대 경로가 아니라 상대 경로인 이유도 `ConvertedPDF.pdfPath`와
    /// 같다 — 컨테이너의 실제 디스크 절대경로는 기기/재설치마다 달라질 수 있어,
    /// 열 때마다 `FileManager.url(forUbiquityContainerIdentifier:)`로 절대경로를
    /// 새로 계산한다(`DocumentUploadService.resolveOriginalFileURL(for:)` 참고).
    /// 북마크와 달리 CloudKit으로 다른 기기에 동기화돼도 항상 똑같이 계산되므로
    /// 기기 간 이식 문제가 없다. 이 필드가 nil인 기존 문서(이 필드 도입 이전 업로드)는
    /// 원본을 성공적으로 여는 순간 소급으로 채워진다(같은 함수 참고).
    public var originalFilePath: String?

    public var storageLocationKind: StorageLocationKind = StorageLocationKind.appManagedFallback
    public var conversionStatus: ConversionStatus = ConversionStatus.pending
    public var indexStatus: IndexStatus = IndexStatus.notIndexed
    public var converterUsed: ConverterUsed = ConverterUsed.none
    public var uploadedAt: Date = Date.now

    // deleteRule은 ImageCategory.sourceDocuments 쪽(inverse 선언부)에서만 지정한다 —
    // 같은 관계 양쪽에 deleteRule을 중복 지정하지 않는다(단순함 우선, 6.4).
    public var category: ImageCategory?

    /// [2026-08-08 추가] 사용자 요청 — "성경 장을 읽을 때 이 장과 관련된 연구문서가
    /// 있다는 것을 한눈에 확인"할 수 있으려면 문서가 어느 장과 관련 있는지 알아야
    /// 하는데, 그 연결을 만들 UI가 이 앱에 전혀 없었다(README "S1 관련문서 패널" 미구현
    /// 기록 참고). 이 필드가 그 연결을 담당한다 — 업로드 시(또는 나중에 문서 목록에서)
    /// 사용자가 직접 "이 문서는 OO장에 관한 것"이라고 지정한다.
    ///
    /// ⚠️ [설계 결정] `DocumentAnchor.linkedVerse`(BibleVerseRef, verse 값 필수)를
    /// 재사용하지 않고 새 필드를 추가했다 — `DocumentAnchor`는 "문서 안의 특정 위치
    /// (페이지/줄)와 성경 구절/태그의 연결"(6.3, S6 "드래그 선택 → 중요 단어 표시"용으로
    /// 남겨둔 미구현 기능)을 뜻하는 모델이라, "문서 전체가 이 장과 관련 있다"는 문서
    /// 레벨 메타데이터와 의미가 다르다. 없는 verse 값에 0 같은 임의 값을 채우는 편법
    /// 대신, 이미 존재하는 책+장 전용 값 타입(`BibleChapterRef`, `LectureNote.chapterRefs`가
    /// 쓰는 것과 동일)을 그대로 재사용해 필드 하나만 추가했다.
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

    /// [2026-08-16 신설] 사용자 요청 — "각 뷰어에 tag를 추가할 수 있도록 하단에
    /// 태그 추가/수정 라인 삽입." `UserMemo.memoTags`와 같은 이유로 관계 자체엔
    /// `@Relationship`을 안 붙인다 — 반대편(`DocumentTag.document`, Tags.swift)에서
    /// 이미 `inverse:`로 이 프로퍼티를 가리키고 있어, 양쪽에 동시에 붙이면
    /// SwiftData가 같은 관계를 두 개로 오인할 수 있다(관계 하나엔 inverse
    /// 선언을 한쪽에만 두는 이 프로젝트 전체 관례, 위 `category` 필드 주석 참고).
    public var documentTags: [DocumentTag]? = []

    /// [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드 앱처럼 기능을
    /// 추가할 것. 고정됨." `UserMemo.isPinned`/`VerseSummary.isPinned`와 같은
    /// 패턴 — 기본값 있는 저장 프로퍼티 추가만으로 SwiftData가 가벼운 마이그레이션을
    /// 자동 처리한다(이 파일의 다른 필드들처럼).
    public var isPinned: Bool = false

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
}

/// 순수 텍스트는 파일과 분리되어 앱 자체 DB에 저장된다(schema.md 3장). 줄 단위.
@Model
public final class DocumentText {
    public var id: UUID = UUID()
    public var pageNumber: Int = 0
    public var lineIndex: Int = 0
    public var lineText: String = ""
    public var createdAt: Date = Date.now

    public var sourceDocument: SourceDocument?

    public init(
        id: UUID = UUID(),
        pageNumber: Int,
        lineIndex: Int,
        lineText: String,
        sourceDocument: SourceDocument? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.pageNumber = pageNumber
        self.lineIndex = lineIndex
        self.lineText = lineText
        self.sourceDocument = sourceDocument
        self.createdAt = createdAt
    }
}

/// 선택 기능 — 필수 아님(schema.md 3장).
///
/// [2026-08-16 실사용 시작] hwp/hwpx 업로드 시 `DocumentUploadService.
/// generateConvertedPDF(for:context:)`가 이 모델을 실제로 채우기 시작했다 —
/// "PDF 변환" 탭(`HWPToPDFPane`, DocumentViewerView.swift)을 열 때마다 매번
/// 다시 변환하지 않고, 업로드 시 미리 만들어 둔 파일을 그대로 열기 위해서다.
/// `pdfPath`는 절대 경로가 아니라 이 앱 iCloud 컨테이너의 "Documents/" 바로
/// 아래부터의 상대 경로(예: "연구 문서/이사야 1장.pdf")다 — 기기/재설치마다
/// 컨테이너의 실제 절대 디스크 경로가 달라질 수 있어(`FileManager.url(
/// forUbiquityContainerIdentifier:)`가 매번 새로 알려준다), 절대 경로를 그대로
/// 저장해 두면 나중에 못 여는 문제가 생긴다. 이 레코드가 없는(이 기능 이전에
/// 업로드된) 문서는 그대로 두고 소급 변환하지 않는다 — `HWPToPDFPane`이 그
/// 경우엔 예전처럼 여는 즉시 변환하는 경로로 자동 대체된다.
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

/// `status = draft`인 동안은 검색 대상이 아니다(14.3 — "사용자 확인을 거쳐서 저장").
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

/// 원본 schema.md 3장 그대로 — 문서 파이프라인 산출용 마크다운. 6장 리치텍스트 통일
/// (content_html/content_text)은 UserMemo/BookOutline/ChapterSummary 세 곳만 대상이라고
/// 명시했으므로(6.6 참고), 여기는 근거 없이 바꾸지 않고 원본 그대로 `content_md`를 유지한다.
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
/// 6.3: 원본의 `linked_keyword_id` → `linkedTag`로 통일. OCR 이미지는 검수 확정된
/// 텍스트가 `DocumentText` 동급으로 취급되므로 별도 처리 없이 같은 메커니즘을 공유한다.
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
