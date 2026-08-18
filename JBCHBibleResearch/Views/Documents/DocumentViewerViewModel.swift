//
//  DocumentViewerViewModel.swift
//  JBCHBibleResearch
//
//  S6(연구문서 원문 뷰어) 상태/데이터 접근. "원본 보기"(네이티브 렌더링) / "추출
//  텍스트"(선택 가능한 순수 텍스트) 두 모드 전환은 screens.md 3장의 "⚠️ S6에
//  '추출 텍스트' 패널 필요(신규 발견)" 항목을 그대로 반영한 것이다 — hwp 뷰어가
//  WKWebView 시각적 렌더링이라 텍스트를 드래그 선택하기 어렵다는 문제의 해결책.
//

import Foundation
import SwiftData
import Observation
import PDFKit
import BibleResearchModels

@MainActor
@Observable
final class DocumentViewerViewModel {
    let document: SourceDocument
    private(set) var resolvedURL: URL?
    private(set) var textLines: [DocumentText] = []
    /// [2026-08-15 추가, 깜박임 수정] 사용자 보고 — "원본보기 pdf 내용이
    /// 깜박거리는 현상." 원인 — `DocumentViewerView.originalPane`이 SwiftUI
    /// 바디를 다시 계산할 때마다(꼭 문서 내용이 바뀌어서가 아니라, 이 창의 다른
    /// 상태가 조금만 바뀌어도) `PDFDocument(url:)`을 매번 디스크에서 새로
    /// 읽어 만들고, 그 새 인스턴스를 `PDFView.document`에 다시 대입하고
    /// 있었다 — `PDFView`는 `.document`가 바뀌면 스크롤/확대 위치를 포함해
    /// 통째로 다시 그리므로, 매 재계산마다 화면이 순간적으로 깜박였다. 여기서
    /// 이 문서를 딱 한 번만(`onAppear`) 읽어 캐싱해 두고, 뷰는 이 안정적인
    /// 참조만 계속 재사용하게 한다(`DocumentViewerView.originalPane`,
    /// `PDFKitRepresentable.updateNSView`의 동일성 검사와 짝을 이룬다).
    private(set) var pdfDocument: PDFDocument?

    /// [2026-08-15 추가, 2026-08-16 갱신] 사용자 요청 — "hwp관련 뷰어를
    /// 구현하고자 함." `HWPViewerPane`(DocumentViewerView.swift)이
    /// `HwpDocumentLoader().load(from:)`에 넘길 원본 바이트 — hwp-swift 전면
    /// 교체 이후로도 이 캐싱 원칙은 그대로 유지된다. 위 `pdfDocument`와 같은
    /// 이유로(재계산마다 디스크를 다시 읽으면 매번 문서를 새로 열게 돼
    /// 깜박임/재파싱 낭비가 생긴다) `onAppear`에서 한 번만 읽어 캐싱한다.
    private(set) var hwpFileData: Data?

    /// [2026-08-16 추가] 사용자 요청 — "hwp 업로드할 때 pdf를 생성하고 pdf
    /// 파일을 열수 있도록." 업로드 시 `DocumentUploadService.
    /// generateConvertedPDF`가 미리 만들어 둔 `ConvertedPDF`가 있으면 그
    /// 파일을 여기서 읽어 둔다 — `HWPToPDFPane`(DocumentViewerView.swift)이
    /// 이 값이 있으면 열 때마다 다시 변환하지 않고 곧바로 보여준다. 레코드가
    /// 없는(이 기능 이전에 업로드된) 문서는 nil로 남고, 그 경우
    /// `HWPToPDFPane`이 예전처럼 여는 즉시 변환하는 경로로 자동 대체된다 —
    /// "기존 데이터는 변환하지 않아도 됨" 요청 그대로.
    private(set) var convertedPDFDocument: PDFDocument?

    private let modelContext: ModelContext

    init(document: SourceDocument, modelContext: ModelContext) {
        self.document = document
        self.modelContext = modelContext
    }

    func onAppear() {
        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼 —
        // originalFilePath가 있으면 그걸로(다른 기기에서도 항상 성공), 없으면
        // (구버전 문서) 북마크로 폴백하고 성공 시 소급 채워 넣는다.
        resolvedURL = try? DocumentUploadService.resolveOriginalFileURL(for: document, context: modelContext)
        if document.originalFormat == .pdf, let resolvedURL {
            pdfDocument = PDFDocument(url: resolvedURL)
        }
        if (document.originalFormat == .hwp || document.originalFormat == .hwpx), let resolvedURL {
            hwpFileData = try? Self.readSecurityScopedData(from: resolvedURL)
        }
        // [2026-08-16 docx 추가] 사용자 요청 — "docxide-pdf + PDFKit로 docx를
        // pdf로 변환하는 것을 검토할 것" → "진행할 것." hwp와 같은 `ConvertedPDF`
        // 모델·같은 로딩 경로를 그대로 재사용한다.
        //
        // ⚠️ [2026-08-16 정정] 처음엔 "변환 자체가 macOS 전용이니 iOS에서는
        // `convertedPDFs`가 항상 비어 있다"고 잘못 적었었다 — 사용자 지적대로
        // 그렇지 않다. `generateConvertedPDFForDocx`(변환 실행)만 macOS
        // 전용이지, 그 결과물(`ConvertedPDF` 레코드 + iCloud Documents
        // 컨테이너의 실제 PDF 파일)은 CloudKit/iCloud Drive로 다른 기기에도
        // 동기화된다. 즉 **macOS에서 업로드/변환된 문서를 iOS에서 열면**
        // 이 코드(순수 PDFKit 읽기, 플랫폼 제한 전혀 없음)가 정상적으로 그
        // PDF를 읽어 `convertedPDFDocument`를 채우고, 검색(`PDFKitRepresentable`
        // 도 이미 macOS/iOS 양쪽 구현이 있음)도 그대로 된다. 진짜 제약은 더
        // 좁다 — "iOS 기기에서 '직접' 새로 업로드한 docx"는 그 업로드 세션
        // 자체가 iOS에서 일어나 변환이 시도조차 안 되므로 PDF가 없다. 그
        // 문서를 나중에 macOS 앱에서 한 번 열어 재시도(`DocumentsViewModel.
        // retry`)하면 그때 변환되고, 그 뒤로는 iOS에서도 정상적으로 보인다.
        if (document.originalFormat == .hwp || document.originalFormat == .hwpx || document.originalFormat == .docx),
           let convertedPDF = (document.convertedPDFs ?? []).first,
           let containerURL = FileManager.default.url(
               forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
           ) {
            // `ConvertedPDF.pdfPath`는 컨테이너의 "Documents/" 바로 아래부터의
            // 상대 경로다(절대 경로가 아닌 이유는 그 모델 상단 주석 참고).
            let pdfURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(convertedPDF.pdfPath, isDirectory: false)
            convertedPDFDocument = PDFDocument(url: pdfURL)
        }
        loadTextLines()
    }

    /// security-scoped URL에서 파일 바이트를 읽는다 — 접근 권한을 열고
    /// 닫는 절차가 `DocumentUploadService`/`DocumentTextExtractionService`의
    /// 다른 파일 읽기 지점들과 동일하다(`startAccessingSecurityScopedResource`
    /// / `defer { stopAccessing... }` 짝).
    private static func readSecurityScopedData(from url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// 2026-08-06: `#Predicate`로 `sourceDocument?.id == ...`처럼 옵셔널 관계를 비교하는
    /// 문법은 SwiftData 버전별 지원 범위가 불확실하다는 게 이미 이 프로젝트에서
    /// 여러 번 플래그된 항목(addendum 6장)이라, 여기서는 아예 그 경로를 쓰지 않고
    /// `SourceDocument.documentTexts`(이미 존재하는 역관계, Documents.swift) 배열을
    /// 그대로 정렬해 쓴다 — 더 단순하고 컴파일 불확실성도 없다.
    private func loadTextLines() {
        textLines = (document.documentTexts ?? []).sorted {
            ($0.pageNumber, $0.lineIndex) < ($1.pageNumber, $1.lineIndex)
        }
    }

    /// 원본 렌더링(네이티브 뷰어)이 이 형식에서 의미가 있는지. doc(구 워드)는
    /// 이번 구현에 전용 렌더러가 없어(위 파일 상단 참고), "추출 텍스트" 탭만 쓸모
    /// 있다고 판단해 원본 탭을 숨긴다.
    ///
    /// [2026-08-16 docx 수정, 같은 날 재수정] 사용자 요청 — "docxide-pdf +
    /// PDFKit로 docx를 pdf로 변환하는 것을 검토할 것" → "진행할 것" → "docx는
    /// hwp뷰어처럼, 상단 탭을 줄것(미리보기, pdf변환)." `.docx`는 더 이상 이
    /// 값 하나로 원본/추출 텍스트를 자동 결정하지 않는다 — `DocumentViewerView.
    /// docxContent`가 세그먼트 토글로 "미리보기"/"PDF 변환"을 사용자가 직접
    /// 고르게 한다(hwp/pages와 같은 패턴). 이 프로퍼티는 `.docx`에 대해서는
    /// 이제 어디서도 안 쓰이지만(`content(viewModel:)`이 `docxContent`로
    /// 먼저 가로챔), `convertedPDFDocument` 유무를 그대로 반영하는 값이
    /// 실제 상황과 맞아 굳이 지우지 않고 남겨 뒀다.
    var supportsNativePreview: Bool {
        switch document.originalFormat {
        case .pdf, .image, .hwp, .hwpx: return true
        case .docx: return convertedPDFDocument != nil
        case .doc, .pages: return false // [2026-08-16 pages 추가] .doc과 동일 — 추출된 텍스트 뷰로 폴백
        }
    }
}
