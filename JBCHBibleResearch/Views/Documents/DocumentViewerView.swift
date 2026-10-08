//
//  DocumentViewerView.swift
//  JBCHBibleResearch
//
//  S6(연구문서 원문 뷰어) — 연구문서 원본을 형식별로 보여주는 화면.
//  - hwp/hwpx: hwp-swift(네이티브) / rhwp 웹 뷰어 / PDF 변환 세 뷰어를 탭으로 전환한다.
//  - PDF: PDFKit + 검색 바. docx: QuickLook 미리보기 / 변환 PDF. pages: QuickLook / 추출 텍스트.
//  - 이미지: 핀치 줌 + OCR 텍스트 레이어. 원본 미리보기가 없는 형식(.doc)은 추출 텍스트로 대체한다.
//  - hwp-swift(`HwpKit`)는 Xcode에서 SPM 의존성으로 추가해 이 타깃에 링크해야 빌드된다
//    (https://github.com/sboh1214/hwp-swift.git, branch: main).
//

import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif
import HwpKit
import HwpKitCore
import BibleResearchModels
// `PDFSearchController`가 `NSRegularExpression`을 쓰기 위한 명시적 import.
import Foundation

// MARK: - 별도 창(S6) 진입점 — PersistentIdentifier → SourceDocument 되찾기

/// `WindowGroup(id: "document-viewer", for: PersistentIdentifier.self)`가 넘겨주는 ID로
/// `SourceDocument`를 되찾아 `DocumentViewerView`에 넘기는 래퍼. ID가 nil이거나 문서가
/// 삭제돼 못 찾으면 안내 문구만 보여준다.
struct DocumentViewerWindowContent: View {
    /// `modelContext.model(for:)`로 한 번만 찾아 넘기면, 창을 열어 둔 채 다른 창에서 같은 문서를
    /// 지웠을 때 소멸된 SwiftData 객체의 프로퍼티를 읽다가 크래시한다. `@Query`는 삭제에도
    /// 다시 계산되므로 문서가 지워지면 자연히 nil이 되어 "찾을 수 없음" 안내로 넘어간다.
    @Query private var documents: [SourceDocument]
    let documentID: PersistentIdentifier?

    var body: some View {
        if let documentID, let document = documents.first(where: { $0.persistentModelID == documentID }) {
            DocumentViewerView(document: document)
        } else {
            documentNotFoundMessage()
        }
    }
}

/// `WindowGroup(id: "document-search", for: DocumentSearchRequest.self)` 전용 — 문서를 열면서
/// 검색어로 찾아 이동한다. `DocumentViewerWindowContent`와 같지만 `initialSearchText`를
/// 추가로 전달한다.
struct DocumentSearchWindowContent: View {
    /// `DocumentViewerWindowContent`와 같은 이유로 `@Query`를 쓴다(삭제된 문서 참조 크래시 방지).
    @Query private var documents: [SourceDocument]
    let request: DocumentSearchRequest?

    var body: some View {
        if let request, let document = documents.first(where: { $0.persistentModelID == request.documentID }) {
            DocumentViewerView(document: document, initialSearchText: request.searchText)
        } else {
            documentNotFoundMessage()
        }
    }
}

@ViewBuilder
private func documentNotFoundMessage() -> some View {
    VStack(spacing: 8) {
        Image(systemName: "doc.questionmark")
            .font(.system(size: 32))
            .foregroundStyle(.secondary)
        Text("문서를 찾을 수 없습니다.")
            .foregroundStyle(.secondary)
        Text("원본 문서가 그 사이 삭제되었을 수 있습니다.")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

struct DocumentViewerView: View {
    @Environment(\.modelContext) private var modelContext
    /// iOS 전용 닫기 버튼(`closeWindowButton`)이 쓴다. 다중 창 미지원 기기(아이폰, Stage Manager
    /// 미사용 아이패드)에서는 `openWindow`가 현재 화면을 이 뷰로 대체하고 뒤로 갈 내비게이션이
    /// 없다. macOS는 창의 닫기 버튼이 이미 있어 쓰지 않는다.
    #if os(iOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    let document: SourceDocument
    /// "관련 내용"에서 넘어온 검색어. 있으면 열자마자 찾아 이동한다 — PDF는 PDFKit 검색+이동,
    /// 그 외 형식은 추출 텍스트 화면에서 해당 줄로 스크롤+강조(`shouldShowExtractedText` 참고).
    var initialSearchText: String? = nil

    @State private var viewModel: DocumentViewerViewModel?
    /// PDF 검색 상태(검색어·일치 개수·이동). `PDFView`를 직접 조작해야 해서
    /// `PDFKitRepresentable`과 공유하는 컨트롤러로 분리했다. `initialSearchText`는
    /// `setUpIfNeeded`에서 이 컨트롤러의 검색어로 미리 채운다.
    @State private var pdfSearchController = PDFSearchController()
    /// `.docx` 변환 PDF용. 원본 `.pdf`(`pdfSearchController`)와 다른 `PDFDocument`를 검색하므로
    /// 컨트롤러를 공유하면 안 된다.
    @State private var docxSearchController = PDFSearchController()
    /// `.hwp`/`.hwpx` 전용 뷰어 전환 상태(다른 형식엔 영향 없음). 같은 문서를 여러 뷰어로 열어
    /// 렌더링을 비교할 수 있다.
    @State private var hwpViewerMode: HWPViewerMode = .hwpSwiftNative
    /// 각 hwp 뷰어가 이 문서를 열 수 있는지 로드 완료 시 보고받아 채운다(`reportViewerAvailability`).
    /// nil=미확정, true=열림, false=못 엶 — `hwpViewerModeToggle`이 못 여는 탭을 숨긴다.
    @State private var viewerAvailability: [HWPViewerMode: Bool] = [:]
    /// `.pages` 전용 뷰어 선택 상태(`PagesViewerMode`). 형식마다 선택 상태를 독립적으로 둔다.
    @State private var pagesViewerMode: PagesViewerMode = .quickLook
    /// `.docx` 전용 뷰어 선택 상태(`DocxViewerMode`). 초기값은 "미리보기"이고, PDF 변환본이 있으면
    /// `docxContent`가 "PDF 변환"으로 올린다.
    @State private var docxViewerMode: DocxViewerMode = .preview

    /// 이미지 모음 전용 — 이미지 추가(파일 선택기/사진 보관함)와 쪽 삭제 확인 상태.
    @State private var isAddImageImporterPresented = false
    @State private var isDeleteImagePageDialogPresented = false
    /// 이미지 모음 화면 안 검색 상태(2026-10-07). 검색결과에서 열렸으면 `setUpIfNeeded`가 그 검색어로 미리 채운다.
    /// 일치 항목은 모든 쪽의 OCR 줄을 쪽 순서 → 줄 순서로 늘어놓은 목록이고, `imageCurrentMatchIndex`가 그중 지금 항목이다.
    @State private var imageSearchQuery = ""
    @State private var imageCurrentMatchIndex = 0
    /// 상단 돋보기 버튼 → `ZoomableImageView` 전달용 일회성 명령(받은 뷰가 처리 후 nil로 되돌린다).
    @State private var imageZoomCommand: ImageZoomCommand?
    #if os(iOS)
    @State private var isAddImagePhotosPickerPresented = false
    @State private var pickedImagePhotoItems: [PhotosPickerItem] = []
    #endif

    /// 문서 태그 입력 상태. `MemoDetailView.tagSection`과 같은 패턴이며(`documentTagSection` 참고),
    /// 형식별 중복을 피하려고 `mainContent` 최하단에 한 번만 둔다.
    @State private var documentTags: [Tag] = []
    @State private var tagInput: String = ""
    @State private var tagSuggestions: [Tag] = []
    @State private var drilldownTag: Tag?

    var body: some View {
        // `@Query` wrapper만으로는 body 재계산과 같은 프레임의 경쟁 상태를 완전히 배제할 수 없어,
        // 삭제된 문서 참조 크래시를 막기 위해 `modelContext == nil` 검사를 한 번 더 둔다
        // (`DocumentRowView.body` 주석 참고).
        if document.modelContext == nil {
            documentNotFoundMessage()
        } else {
            mainContent
        }
    }

    // ⚠️ 아래 `content(viewModel:)`와 혼동되지 않도록 `content`가 아닌 `mainContent`로 이름 지었다.
    @ViewBuilder
    private var mainContent: some View {
        // 뷰어 콘텐츠는 `.frame(maxHeight: .infinity)`로 남은 공간을 채우고, `documentTagSection`은
        // 그 아래 고정 높이로 붙는다.
        VStack(spacing: 0) {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            documentTagSection
        }
        .navigationTitle(document.displayTitle)
        .onAppear(perform: setUpIfNeeded)
        .sheet(item: $drilldownTag) { tag in
            TagDrilldownView(tag: tag)
        }
        #if os(iOS)
        .overlay(alignment: .topTrailing) {
            closeWindowButton
        }
        #endif
    }

    #if os(iOS)
    /// iOS 전용 닫기 버튼(`dismissWindow` 프로퍼티 참고). `NavigationStack`이 없어 `.toolbar` 대신 `.overlay`로 그린다.
    private var closeWindowButton: some View {
        Button {
            dismissWindow()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .background(Circle().fill(.background))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(12)
        .accessibilityLabel("닫기")
    }
    #endif

    // 항상 원본(네이티브 미리보기)을 먼저 보여준다. 원본 미리보기가 없는 형식(.doc)이거나, 검색어가
    // 있는데 원본 탭이 검색을 못 하는 형식일 때만 추출 텍스트로 자동 대체한다(수동 전환 UI 없음).
    private func shouldShowExtractedText(viewModel: DocumentViewerViewModel) -> Bool {
        if !viewModel.supportsNativePreview { return true }
        // hwp/hwpx는 검색어가 있어도 추출 텍스트로 대체하지 않고, 사이드바에서 그냥 열 때와 같은
        // 원본 hwp 뷰어(`originalPane`의 3-way)를 보여준다.
        if document.originalFormat == .hwp || document.originalFormat == .hwpx {
            return false
        }
        // `.image`도 hwp/hwpx처럼 제외한다 — `ZoomableImageView`가 OCR 텍스트를 이미지 위 정확한
        // 위치에 겹쳐 보여주므로, 검색어가 있어도 항상 원본 이미지를 보여준다.
        if document.originalFormat == .image {
            return false
        }
        // 검색어가 있을 때 PDF는 원본 보기(PDFKit 검색+이동)가 담당하고, PDF가 아니면 원본 탭이
        // 검색을 지원하지 않으므로 추출 텍스트(줄 단위 스크롤+강조)로 보여준다.
        if let initialSearchText, !initialSearchText.isEmpty, document.originalFormat != .pdf {
            return true
        }
        return false
    }

    @ViewBuilder
    private func content(viewModel: DocumentViewerViewModel) -> some View {
        // `.pages`/`.docx`는 각자 뷰어 전환 세그먼트를 가지므로 `shouldShowExtractedText`의
        // 이분법을 따르지 않고 별도 분기로 뺀다.
        if document.originalFormat == .pages {
            pagesContent(viewModel: viewModel)
        } else if document.originalFormat == .docx {
            docxContent(viewModel: viewModel)
        } else if shouldShowExtractedText(viewModel: viewModel) {
            extractedTextPane(viewModel: viewModel)
        } else {
            originalPane(viewModel: viewModel)
        }
    }

    // MARK: - docx 전용(미리보기 ↔ PDF 변환)

    /// docx 전용 뷰어. "미리보기"(QuickLook — 렌더링만 하고 텍스트를 앱에 돌려주지 못해 검색 불가) /
    /// "PDF 변환"(docxide-pdf로 변환된 PDF를 `PDFKitRepresentable`+검색창으로 표시, 검색 가능).
    ///
    /// ⚠️ 변환 실행(`DocxToPDFConverter`, Rust FFI)만 macOS 전용이고 결과 PDF는 iCloud로 동기화된다.
    /// 그래서 macOS에서 변환된 문서는 iOS에서도 "PDF 변환" 탭과 검색이 동작한다
    /// (`convertedPDFDocument`는 "이 기기에서 그 PDF 파일을 읽을 수 있는지"만 본다). iOS에서 새로
    /// 업로드한 docx는 그 세션에서 변환이 시도되지 않으며, macOS 앱에서 한 번 열면 이후 iOS에서도
    /// 보인다. "PDF 변환" 탭은 변환본이 있을 때만 토글에 나타난다.
    @ViewBuilder
    private func docxContent(viewModel: DocumentViewerViewModel) -> some View {
        VStack(spacing: 0) {
            docxViewerModeToggle(viewModel: viewModel)
            Divider()
            switch docxViewerMode {
            case .preview:
                if case .ready = viewModel.downloadStatus, let url = viewModel.resolvedURL {
                    QLPreviewRepresentable(url: url)
                } else {
                    fileContentUnavailableView(
                        status: viewModel.downloadStatus,
                        fallbackMessage: "docx 원본 파일을 열 수 없습니다."
                    )
                }
            case .pdfConverted:
                if let pdf = viewModel.convertedPDFDocument {
                    VStack(spacing: 0) {
                        pdfSearchBar(controller: docxSearchController)
                        Divider()
                        PDFKitRepresentable(document: pdf, searchController: docxSearchController)
                    }
                } else {
                    fileContentUnavailableView(
                        status: viewModel.convertedPDFDownloadStatus,
                        fallbackMessage: "PDF로 변환된 파일이 없습니다."
                    )
                }
            }
        }
        .onAppear {
            // PDF 변환본이 있으면 검색 가능한 "PDF 변환" 탭을 기본으로 올리고, 없으면 "미리보기"를
            // 유지한다. 검색어 채우기도 `syncDocxViewerModeIfConvertedPDFReady`가 맡는다.
            syncDocxViewerModeIfConvertedPDFReady(viewModel: viewModel)
        }
        // 변환 PDF가 iCloud 다운로드 완료 후 나중에 채워질 수 있어 `onAppear`의 1회 체크만으로는
        // 놓친다. `PDFDocument`는 `Equatable`이 아니라 `!= nil`(Bool)이 false → true로 바뀌는
        // 시점을 대신 관찰한다.
        .onChange(of: viewModel.convertedPDFDocument != nil) { _, isAvailable in
            guard isAvailable else { return }
            syncDocxViewerModeIfConvertedPDFReady(viewModel: viewModel)
        }
    }

    /// `docxContent`의 `.onAppear`/`.onChange`가 공유한다 — 변환 PDF가 있으면 "PDF 변환" 탭으로
    /// 올리고, 검색어가 있으면 그 탭의 검색창에 미리 채운다. 변환 PDF가 나중에 도착할 수 있어
    /// 1회성 체크 대신 이 함수로 합쳤다.
    private func syncDocxViewerModeIfConvertedPDFReady(viewModel: DocumentViewerViewModel) {
        guard viewModel.convertedPDFDocument != nil else { return }
        docxViewerMode = .pdfConverted
        if let initialSearchText, !initialSearchText.isEmpty {
            docxSearchController.query = initialSearchText
        }
    }

    private func docxViewerModeToggle(viewModel: DocumentViewerViewModel) -> some View {
        Picker("뷰어", selection: $docxViewerMode) {
            ForEach(DocxViewerMode.allCases.filter { $0 != .pdfConverted || viewModel.convertedPDFDocument != nil }) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(8)
    }

    // MARK: - pages 전용(QuickLook 원본 ↔ 추출 텍스트 검색)

    /// pages 전용 뷰어 — 세그먼트로 QuickLook(원본)과 추출 텍스트(검색)를 오간다.
    /// hwp의 `hwpViewerModeToggle` 구조와 같은 모양.
    @ViewBuilder
    private func pagesContent(viewModel: DocumentViewerViewModel) -> some View {
        VStack(spacing: 0) {
            pagesViewerModeToggle
            Divider()
            switch pagesViewerMode {
            case .quickLook:
                if case .ready = viewModel.downloadStatus, let url = viewModel.resolvedURL {
                    QLPreviewRepresentable(url: url)
                } else {
                    fileContentUnavailableView(
                        status: viewModel.downloadStatus,
                        fallbackMessage: "pages 원본 파일을 열 수 없습니다."
                    )
                }
            case .extractedText:
                extractedTextPane(viewModel: viewModel)
            }
        }
        .onAppear {
            // 검색어가 있으면 검색 가능한 텍스트 탭을 바로 보여준다(`shouldShowExtractedText`와 같은 이유).
            if let initialSearchText, !initialSearchText.isEmpty {
                pagesViewerMode = .extractedText
            }
        }
    }

    private var pagesViewerModeToggle: some View {
        Picker("뷰어", selection: $pagesViewerMode) {
            ForEach(PagesViewerMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(8)
    }

    // MARK: - 원본 보기

    /// 상단 돋보기 버튼(확대/축소/원본 크기)이 `ZoomableImageView`에 보내는 명령. `token`이 매번 달라 같은 명령을 연달아 보내도 변경으로 감지된다.
    private struct ImageZoomCommand: Equatable {
        enum Kind { case zoomIn, zoomOut, reset }
        let kind: Kind
        let token = UUID()
    }

    /// 이미지 뷰어(아래 `ZoomableImageView`)는 scale to fit으로 시작해 핀치로 확대/축소하고,
    /// 확대 상태에서는 드래그로 이동하며 더블탭으로 원래 크기로 되돌린다. 최소 배율은 1로 제한한다.
    ///
    /// 이미지 위 OCR 텍스트 레이어용 값 타입. `DocumentText.ocrBoundingBox`(Vision 정규화 좌표,
    /// 좌하단 원점)를 이 화면(좌상단 원점)이 쓸 수 있게 미리 담아 둔다.
    private struct OCRLineOverlayItem: Identifiable {
        let id: UUID
        let text: String
        /// Vision 원본 그대로 — 정규화(0...1) 좌표, **좌하단 원점**.
        let boundingBox: CGRect

        /// "x,y,width,height" 콤마 구분 문자열(`DocumentTextExtractionService.
        /// encodeOCRBoundingBox`가 쓴 형식)을 되돌린다. 형식이 어긋나거나
        /// nil이면(옛 OCR 문서, 위치 정보 없음) nil을 돌려줘 그 줄은 오버레이
        /// 없이 조용히 건너뛴다 — 위치를 추측해서 지어내지 않는다.
        static func decodeBoundingBox(_ raw: String?) -> CGRect? {
            guard let raw else { return nil }
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 4 else { return nil }
            return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        }
    }

    private struct ZoomableImageView: View {
        let image: PlatformImage
        /// 위치 정보가 있는 OCR 줄들(없으면 빈 배열 — 오버레이 없이 이미지만).
        var ocrLines: [OCRLineOverlayItem] = []
        /// 검색결과에서 진입했을 때의 검색어 — 일치하는 줄만 강조 박스를 얹는다.
        var searchText: String? = nil
        /// 지금 가리키는 일치 항목(검색 막대의 ︿ ﹀ 위치) — 다른 일치 줄보다 진한 주황으로 강조한다.
        var activeLineID: UUID? = nil
        /// 상단 돋보기 버튼 명령(확대/축소/원본 크기). 처리하면 nil로 되돌린다.
        @Binding var zoomCommand: ImageZoomCommand?

        @State private var scale: CGFloat = 1
        @State private var lastScale: CGFloat = 1
        @State private var offset: CGSize = .zero
        @State private var lastOffset: CGSize = .zero

        private let minScale: CGFloat = 1
        private let maxScale: CGFloat = 5

        private var trimmedSearchText: String {
            (searchText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// 이미지의 실제 픽셀 크기 — `.aspectRatio(contentMode: .fit)`이 그리는 사각형(레터박스 포함) 계산에 쓴다.
        private var imagePixelSize: CGSize {
            // `loadedImage`는 항상 `PlatformImage(data:)`로 만들어져 `scale`이 1.0이므로 `.size`가 곧
            // Vision이 `boundingBox`를 계산한 CGImage 픽셀 공간의 크기다(NSImage/UIImage 모두
            // CGSize라 플랫폼 분기가 필요 없다).
            image.size
        }

        /// `.aspectRatio(contentMode: .fit)`이 `containerSize` 안에서 실제로
        /// 이미지를 그리는 사각형(레터박스 여백 제외) — 표준 aspect-fit 계산.
        /// OCR 오버레이 박스는 이 사각형을 기준으로 위치를 잡아야 실제
        /// 이미지 위 정확한 자리에 온다(컨테이너 전체를 기준으로 하면
        /// 레터박스만큼 어긋난다).
        private func fitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
            guard imageSize.width > 0, imageSize.height > 0,
                  containerSize.width > 0, containerSize.height > 0 else {
                return CGRect(origin: .zero, size: containerSize)
            }
            let imageAspect = imageSize.width / imageSize.height
            let containerAspect = containerSize.width / containerSize.height
            if imageAspect > containerAspect {
                let width = containerSize.width
                let height = width / imageAspect
                return CGRect(x: 0, y: (containerSize.height - height) / 2, width: width, height: height)
            } else {
                let height = containerSize.height
                let width = height * imageAspect
                return CGRect(x: (containerSize.width - width) / 2, y: 0, width: width, height: height)
            }
        }

        /// Vision의 정규화 좌표(좌하단 원점)를 `rect`(화면 좌표, 좌상단 원점)
        /// 기준의 실제 화면 사각형으로 바꾼다 — Vision → UIKit/SwiftUI 좌표계
        /// 변환의 표준 공식(y축 반전)이다.
        private func screenRect(for box: CGRect, in rect: CGRect) -> CGRect {
            let x = rect.minX + box.origin.x * rect.width
            let y = rect.minY + (1 - box.origin.y - box.height) * rect.height
            return CGRect(x: x, y: y, width: box.width * rect.width, height: box.height * rect.height)
        }

        private func isSearchMatch(_ text: String) -> Bool {
            guard !trimmedSearchText.isEmpty else { return false }
            return text.range(of: trimmedSearchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        var body: some View {
            #if os(macOS)
            let baseImage = Image(nsImage: image)
            #else
            let baseImage = Image(uiImage: image)
            #endif
            GeometryReader { geometry in
                let contentRect = fitRect(imageSize: imagePixelSize, in: geometry.size)
                ZStack(alignment: .topLeading) {
                    baseImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    // OCR 텍스트 레이어 — 인식된 줄마다 Vision이 준 위치에 겹친다. 글자는 투명하게
                    // 그려 화면엔 원본 이미지만 보이되 길게 눌러 선택·복사할 수 있고(`.textSelection`),
                    // 검색어와 일치하는 줄만 반투명 강조 박스를 더한다.
                    ForEach(ocrLines) { line in
                        let box = screenRect(for: line.boundingBox, in: contentRect)
                        let matched = isSearchMatch(line.text)
                        ZStack {
                            if matched {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(line.id == activeLineID ? Color.orange.opacity(0.5) : Color.yellow.opacity(0.35))
                            }
                            // 항상 투명 — 글자 모양은 밑의 이미지가 보여주고, 일치 여부는 위 노란
                            // 박스로만 표시한다.
                            Text(line.text)
                                .font(.system(size: max(box.height * 0.75, 1)))
                                .foregroundStyle(Color.clear)
                                .lineLimit(1)
                                .minimumScaleFactor(0.1)
                                .textSelection(.enabled)
                        }
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, minScale), maxScale)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= minScale {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    scale = minScale
                                    lastScale = minScale
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > minScale else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        if scale > minScale {
                            scale = minScale
                            lastScale = minScale
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2
                            lastScale = 2
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: zoomCommand) { _, command in
                guard let command else { return }
                applyZoomCommand(command.kind)
                zoomCommand = nil
            }
        }

        /// 돋보기 버튼 동작 — 핀치와 같은 배율 범위(1~5배)를 지킨다. 한 번에 1.25배씩, 1배로 돌아오면 이동 위치도 함께 되돌린다.
        private func applyZoomCommand(_ kind: ImageZoomCommand.Kind) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                switch kind {
                case .zoomIn:
                    scale = min(scale * 1.25, maxScale)
                case .zoomOut:
                    scale = max(scale / 1.25, minScale)
                case .reset:
                    scale = minScale
                }
                lastScale = scale
                if scale <= minScale {
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
    }

    /// 이미지 문서의 `pageNumber`쪽 OCR 줄 중 위치 정보(`ocrBoundingBox`)가 있는 것만 `lineIndex` 순으로 돌려준다.
    /// 위치 정보가 없는 옛 OCR 문서는 위치를 추측하지 않고 빈 배열이 되어 오버레이 없이 동작한다.
    private func ocrOverlayLines(forPage pageNumber: Int) -> [OCRLineOverlayItem] {
        guard document.originalFormat == .image else { return [] }
        let lines = (document.documentTexts ?? [])
            .filter { $0.pageNumber == pageNumber && $0.ocrBoundingBox != nil }
            .sorted { $0.lineIndex < $1.lineIndex }
        return lines.compactMap { line in
            guard let box = OCRLineOverlayItem.decodeBoundingBox(line.ocrBoundingBox) else { return nil }
            return OCRLineOverlayItem(id: line.id, text: line.lineText, boundingBox: box)
        }
    }

    @ViewBuilder
    private func originalPane(viewModel: DocumentViewerViewModel) -> some View {
        switch document.originalFormat {
        case .pdf:
            // `viewModel.onAppear()`에서 한 번 읽어 캐싱한 인스턴스를 쓴다 — 재계산마다
            // `PDFDocument(url:)`를 새로 만들면 깜박인다(`DocumentViewerViewModel.pdfDocument` 참고).
            if let pdf = viewModel.pdfDocument {
                VStack(spacing: 0) {
                    pdfSearchBar
                    Divider()
                    PDFKitRepresentable(document: pdf, searchController: pdfSearchController)
                }
            } else {
                fileContentUnavailableView(status: viewModel.downloadStatus, fallbackMessage: "PDF를 열 수 없습니다.")
            }
        case .image:
            // 쪽 넘김 + 썸네일 줄 + 이미지 추가/쪽 삭제(`imagePane`). 1장짜리 기존 문서도 같은 화면이다.
            imagePane(viewModel: viewModel)
        case .hwp, .hwpx:
            if let hwpFileData = viewModel.hwpFileData {
                VStack(spacing: 0) {
                    hwpViewerModeToggle
                    Divider()
                    // 셋 다 항상 뷰 계층에 두고 안 보이는 것은 `opacity(0)` + `allowsHitTesting(false)`로
                    // 숨긴다. `switch`로 하나만 두면 탭 전환마다 뷰가 파괴돼 각 Pane의 `@State`(파싱된
                    // 문서, WKWebView 등)가 사라지고 `.task(id:)`가 다시 실행된다. 뷰 정체성이 유지되면
                    // 같은 문서인 한 한 번만 로드하고 전환은 즉시 된다.
                    ZStack {
                        HWPViewerPane(
                            documentData: hwpFileData,
                            initialSearchText: initialSearchText,
                            additionalSearchTerms: verseSearchLiteralTerms(for:),
                            onAvailabilityChange: { reportViewerAvailability($0, for: .hwpSwiftNative) }
                        )
                            .opacity(hwpViewerMode == .hwpSwiftNative ? 1 : 0)
                            .allowsHitTesting(hwpViewerMode == .hwpSwiftNative)
                            .accessibilityHidden(hwpViewerMode != .hwpSwiftNative)
                        RhwpWebViewerPane(
                            documentData: hwpFileData,
                            initialSearchText: initialSearchText,
                            additionalSearchTerms: verseSearchLiteralTerms(for:),
                            onAvailabilityChange: { reportViewerAvailability($0, for: .rhwpWeb) }
                        )
                            .opacity(hwpViewerMode == .rhwpWeb ? 1 : 0)
                            .allowsHitTesting(hwpViewerMode == .rhwpWeb)
                            .accessibilityHidden(hwpViewerMode != .rhwpWeb)
                        HWPToPDFPane(
                            documentData: hwpFileData,
                            preConvertedDocument: viewModel.convertedPDFDocument,
                            additionalSearchTerms: verseSearchLiteralTerms(for:),
                            initialSearchText: initialSearchText,
                            onAvailabilityChange: { reportViewerAvailability($0, for: .pdfConverted) }
                        )
                            .opacity(hwpViewerMode == .pdfConverted ? 1 : 0)
                            .allowsHitTesting(hwpViewerMode == .pdfConverted)
                            .accessibilityHidden(hwpViewerMode != .pdfConverted)
                    }
                }
            } else {
                fileContentUnavailableView(status: viewModel.downloadStatus, fallbackMessage: "hwp 원본 파일을 열 수 없습니다.")
            }
        case .doc, .docx, .pages:
            // `.doc`는 `supportsNativePreview == false`라 `shouldShowExtractedText`가 항상 true이고,
            // `.docx`/`.pages`는 `content(viewModel:)`이 먼저 가로채므로 이 분기는 실제로 그려지지
            // 않는다. switch exhaustive 요구 때문에 남겨 둔 자리다.
            unavailableMessage("이 형식은 원본 미리보기를 지원하지 않습니다. 추출된 텍스트를 대신 보여드립니다.")
        }
    }

    // MARK: - 이미지 모음(여러 장 = 한 문서)

    /// 이미지 문서 뷰어 — 위쪽 검색·돋보기 막대(검색칸 · 일치 항목 이동 · 확대/축소/원본 크기 · ⋯ 메뉴[이미지 추가 · 이 페이지 삭제]),
    /// 가운데 확대 가능한 이미지(+ OCR 글자 레이어, 좌우 가장자리 쪽 이동 버튼, 아래 가운데 쪽 번호),
    /// 아래쪽 썸네일 줄(2장 이상일 때). 파일은 `viewModel.openImagePage`가 쪽 단위로 내려받아 `loadedImage`에 담는다.
    @ViewBuilder
    private func imagePane(viewModel: DocumentViewerViewModel) -> some View {
        VStack(spacing: 0) {
            imageToolBar(viewModel: viewModel)
            Divider()
            if case .ready = viewModel.downloadStatus {
                if let image = viewModel.loadedImage {
                    // `ocrOverlayLines`와 검색어를 함께 넘겨 OCR 텍스트 레이어를 겹친다(지금 보는 쪽의 글자만).
                    // `.id`로 쪽이 바뀔 때 확대/이동 상태를 초기화한다.
                    ZoomableImageView(
                        image: image,
                        ocrLines: ocrOverlayLines(forPage: viewModel.currentImagePageNumber),
                        searchText: imageSearchQuery,
                        activeLineID: activeImageMatchLineID(viewModel: viewModel),
                        zoomCommand: $imageZoomCommand
                    )
                    .id(viewModel.currentImagePageNumber)
                    // 쪽 이동(2026-10-07 목업 A안) — 위쪽 막대에서 옮겨 이미지 좌우 가장자리 세로 중앙의 원형 버튼과
                    // 아래 가운데 쪽 번호 알약으로 둔다. 이미지 위 오버레이라 확대·이동 제스처 영역을 줄이지 않는다.
                    .overlay { imagePageEdgeButtons(viewModel: viewModel) }
                    .overlay(alignment: .bottom) { imagePageIndicator(viewModel: viewModel) }
                } else {
                    ProgressView("이미지를 불러오는 중…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                fileContentUnavailableView(status: viewModel.downloadStatus, fallbackMessage: "이미지를 열 수 없습니다.")
            }
            if viewModel.imagePageCount > 1 {
                Divider()
                imageThumbnailStrip(viewModel: viewModel)
            }
        }
        // 검색어가 바뀌면 첫 일치 항목으로 돌아가 그 쪽을 연다.
        .onChange(of: imageSearchQuery) { _, _ in
            imageCurrentMatchIndex = 0
            showCurrentImageMatchPage(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $isAddImageImporterPresented,
            allowedContentTypes: [.jpeg, .png, .heic],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.appendImages(urls: urls)
            }
        }
        #if os(iOS)
        .photosPicker(isPresented: $isAddImagePhotosPickerPresented, selection: $pickedImagePhotoItems, matching: .images)
        .onChange(of: pickedImagePhotoItems) { _, items in
            guard !items.isEmpty else { return }
            let itemsToLoad = items
            pickedImagePhotoItems = []
            Task { @MainActor in
                await appendPickedPhotos(itemsToLoad, viewModel: viewModel)
            }
        }
        #endif
        .confirmationDialog(
            "\(viewModel.currentImagePageIndex + 1)쪽을 삭제할까요?",
            isPresented: $isDeleteImagePageDialogPresented,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) { viewModel.deleteCurrentImagePage() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이미지와 인식된 글자가 함께 삭제됩니다.")
        }
        .alert("이미지 모음", isPresented: Binding(
            get: { viewModel.imagePageMessage != nil },
            set: { if !$0 { viewModel.imagePageMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.imagePageMessage ?? "")
        }
    }

    // MARK: 이미지 모음 — 검색·돋보기 막대와 쪽 이동 (2026-10-07)

    /// 검색어가 들어간 OCR 줄 전부 — 쪽 순서(`imagePageNumbers`) → 줄 순서(`lineIndex`). 검색어가 비면 빈 배열.
    /// `imageMatchCounts`(썸네일 점)와 같은 일치 규칙(대소문자·발음 기호 무시 부분 문자열)을 쓴다.
    private func imageSearchMatches(viewModel: DocumentViewerViewModel) -> [DocumentText] {
        let trimmed = imageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var pageOrder: [Int: Int] = [:]
        for (index, pageNumber) in viewModel.imagePageNumbers.enumerated() where pageOrder[pageNumber] == nil {
            pageOrder[pageNumber] = index
        }
        let matched = viewModel.textLines.filter { line in
            pageOrder[line.pageNumber] != nil
                && line.lineText.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return matched.sorted { (lhs: DocumentText, rhs: DocumentText) -> Bool in
            let lhsOrder = pageOrder[lhs.pageNumber] ?? 0
            let rhsOrder = pageOrder[rhs.pageNumber] ?? 0
            return lhsOrder != rhsOrder ? lhsOrder < rhsOrder : lhs.lineIndex < rhs.lineIndex
        }
    }

    /// 지금 가리키는 일치 줄의 id(없으면 nil). 목록이 줄어 인덱스가 넘치면 마지막 항목으로 맞춘다.
    private func activeImageMatchLineID(viewModel: DocumentViewerViewModel) -> UUID? {
        let matches = imageSearchMatches(viewModel: viewModel)
        guard !matches.isEmpty else { return nil }
        return matches[min(imageCurrentMatchIndex, matches.count - 1)].id
    }

    /// ︿ ﹀ / 엔터 — 일치 항목을 앞뒤로 옮긴다(처음↔끝은 이어진다). 다른 쪽에 있으면 그 쪽을 연다.
    private func moveImageMatch(by delta: Int, viewModel: DocumentViewerViewModel) {
        let matches = imageSearchMatches(viewModel: viewModel)
        guard !matches.isEmpty else { return }
        let current = min(imageCurrentMatchIndex, matches.count - 1)
        imageCurrentMatchIndex = ((current + delta) % matches.count + matches.count) % matches.count
        showCurrentImageMatchPage(viewModel: viewModel)
    }

    /// 지금 일치 항목이 있는 쪽을 연다. 이미 그 쪽이면 아무것도 하지 않는다(확대 상태 유지).
    private func showCurrentImageMatchPage(viewModel: DocumentViewerViewModel) {
        let matches = imageSearchMatches(viewModel: viewModel)
        guard !matches.isEmpty else { return }
        let match = matches[min(imageCurrentMatchIndex, matches.count - 1)]
        guard let index = viewModel.imagePageNumbers.firstIndex(of: match.pageNumber),
              index != viewModel.currentImagePageIndex else { return }
        viewModel.openImagePage(at: index)
    }

    /// 위쪽 막대 — PDF 뷰어(`pdfSearchBar`)와 같은 구성: 검색칸 · 일치 항목 이동 · 돋보기 3버튼(강조색 12% 원형, 28pt) + ⋯ 메뉴.
    private func imageToolBar(viewModel: DocumentViewerViewModel) -> some View {
        let trimmedQuery = imageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchCount = imageSearchMatches(viewModel: viewModel).count
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("검색", text: $imageSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { moveImageMatch(by: 1, viewModel: viewModel) }
                if !trimmedQuery.isEmpty {
                    Text(matchCount == 0 ? "0건" : "\(min(imageCurrentMatchIndex, matchCount - 1) + 1)/\(matchCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button {
                        moveImageMatch(by: -1, viewModel: viewModel)
                    } label: {
                        Image(systemName: "chevron.up")
                            .foregroundStyle(Color("AccentColor"))
                    }
                    .buttonStyle(.plain)
                    .disabled(matchCount == 0)
                    .help("이전 일치 항목")
                    Button {
                        moveImageMatch(by: 1, viewModel: viewModel)
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(Color("AccentColor"))
                    }
                    .buttonStyle(.plain)
                    .disabled(matchCount == 0)
                    .help("다음 일치 항목")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

            imageToolCircleButton(systemImage: "plus.magnifyingglass", help: "확대") {
                imageZoomCommand = ImageZoomCommand(kind: .zoomIn)
            }
            imageToolCircleButton(systemImage: "minus.magnifyingglass", help: "축소") {
                imageZoomCommand = ImageZoomCommand(kind: .zoomOut)
            }
            imageToolCircleButton(systemImage: "arrow.up.left.and.down.right.magnifyingglass", help: "원본 크기") {
                imageZoomCommand = ImageZoomCommand(kind: .reset)
            }

            if viewModel.isModifyingImagePages {
                ProgressView().controlSize(.small)
            }
            Menu {
                Button("파일에서 이미지 추가…") { isAddImageImporterPresented = true }
                #if os(iOS)
                Button("사진 보관함에서 추가…") { isAddImagePhotosPickerPresented = true }
                #endif
                if viewModel.imagePageCount > 1 {
                    Divider()
                    Button(role: .destructive) {
                        isDeleteImagePageDialogPresented = true
                    } label: {
                        Label("이 페이지 삭제", systemImage: "trash")
                    }
                }
            } label: {
                imageToolCircleLabel(systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("이미지 추가·삭제")
        }
        .disabled(viewModel.isModifyingImagePages)
        .padding(.vertical, 8)
        .padding(.leading, 12)
        // iOS는 오른쪽 위에 `closeWindowButton`이 떠 있어 `pdfSearchBar`와 같은 이유로 오른쪽 여백을 더 둔다.
        #if os(iOS)
        .padding(.trailing, 44)
        #else
        .padding(.trailing, 12)
        #endif
    }

    private func imageToolCircleLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color("AccentColor"))
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color("AccentColor").opacity(0.12)))
            .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
    }

    private func imageToolCircleButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            imageToolCircleLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// 이미지 좌우 가장자리 세로 중앙의 쪽 이동 원형 버튼(48pt, 탭 영역 44pt 이상). 쪽이 2장 이상일 때만 보이고,
    /// 첫 쪽의 이전/끝 쪽의 다음은 흐려지며 눌리지 않는다.
    @ViewBuilder
    private func imagePageEdgeButtons(viewModel: DocumentViewerViewModel) -> some View {
        if viewModel.imagePageCount > 1 {
            HStack {
                imageEdgeButton(
                    systemImage: "chevron.left", label: "이전 쪽",
                    isEnabled: viewModel.currentImagePageIndex > 0 && !viewModel.isModifyingImagePages
                ) { viewModel.showPreviousImagePage() }
                Spacer()
                imageEdgeButton(
                    systemImage: "chevron.right", label: "다음 쪽",
                    isEnabled: viewModel.currentImagePageIndex < viewModel.imagePageCount - 1 && !viewModel.isModifyingImagePages
                ) { viewModel.showNextImagePage() }
            }
            .padding(.horizontal, 10)
        }
    }

    private func imageEdgeButton(systemImage: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.18), radius: 4, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
        .accessibilityLabel(label)
    }

    /// 아래 가운데 쪽 번호 알약 — "3 / 7". 누르는 대상이 아니라 표시일 뿐이라 터치는 아래 이미지로 통과시킨다.
    @ViewBuilder
    private func imagePageIndicator(viewModel: DocumentViewerViewModel) -> some View {
        if viewModel.imagePageCount > 1 {
            Text("\(viewModel.currentImagePageIndex + 1) / \(viewModel.imagePageCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7), in: Capsule())
                .padding(.bottom, 10)
                .allowsHitTesting(false)
        }
    }

    /// 쪽 썸네일 줄 — 누르면 그 쪽으로 이동, 지금 쪽은 테두리, 검색어와 일치하는 글자가 있는 쪽은 노란 점(일치 줄 수)이 붙는다.
    private func imageThumbnailStrip(viewModel: DocumentViewerViewModel) -> some View {
        let matchCounts = viewModel.imageMatchCounts(for: imageSearchQuery)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.imagePageNumbers.enumerated()), id: \.element) { index, pageNumber in
                        imageThumbnailCell(
                            viewModel: viewModel, index: index, pageNumber: pageNumber,
                            matchCount: matchCounts[pageNumber] ?? 0
                        )
                        .id(pageNumber)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.currentImagePageIndex) { _, _ in
                withAnimation { proxy.scrollTo(viewModel.currentImagePageNumber, anchor: .center) }
            }
        }
        .frame(height: 90)
    }

    private func imageThumbnailCell(
        viewModel: DocumentViewerViewModel, index: Int, pageNumber: Int, matchCount: Int
    ) -> some View {
        let isCurrent = index == viewModel.currentImagePageIndex
        return Button {
            viewModel.openImagePage(at: index)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail = viewModel.imageThumbnails[pageNumber] {
                        #if os(macOS)
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                        #else
                        Image(uiImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                        #endif
                    } else {
                        Rectangle().fill(Color.secondary.opacity(0.15))
                    }
                }
                .frame(width: 54, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomLeading) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 4)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? Color("AccentColor") : Color.secondary.opacity(0.3), lineWidth: isCurrent ? 2.5 : 1)
                )
                if matchCount > 0 {
                    Text("\(matchCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.yellow, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(index + 1)쪽")
    }

    #if os(iOS)
    /// 사진 보관함에서 고른 항목을 임시 파일로 내려받아 이 문서 맨 끝에 더한다(`DocumentsHomeView.handlePickedPhotos`와 같은 방식).
    @MainActor
    private func appendPickedPhotos(_ items: [PhotosPickerItem], viewModel: DocumentViewerViewModel) async {
        var savedURLs: [URL] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            if (try? data.write(to: tempURL)) != nil {
                savedURLs.append(tempURL)
            }
        }
        guard !savedURLs.isEmpty else { return }
        viewModel.appendImages(urls: savedURLs)
    }
    #endif

    // MARK: - hwp 뷰어 전환(네이티브 hwp-swift ↔ rhwp 웹 뷰어)

    /// `.hwp`/`.hwpx` 전용 세그먼트 컨트롤 — hwp-swift(HWPViewerPane, 네이티브), rhwp(RhwpWebViewerPane,
    /// WKWebView + WASM), PDF 변환 뷰어 중 선택한다.
    ///
    /// hwp-swift 파서 한계로 특정 문서가 네이티브 탭에서만 안 열릴 수 있다("Presentation build
    /// failed: Bytes are not EOF..." — `HwpIdMappings.swift`가 문서 버전별로 필드 개수를 다르게
    /// 읽는 경계에서 어긋나는 것으로 보이며, 현재 hwp-swift에 알려진 수정은 없다).
    /// `viewerAvailability`가 `false`로 확정한 탭은 세그먼트에서 숨긴다.
    private var hwpViewerModeToggle: some View {
        Picker("뷰어", selection: $hwpViewerMode) {
            ForEach(HWPViewerMode.allCases.filter { viewerAvailability[$0] != false }) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(8)
    }

    /// 위 `viewerAvailability`에 한 뷰어의 로드 결과를 채운다. 지금 선택된 탭이
    /// 방금 "못 엶"으로 확정됐으면, 이미 "열림"으로 확정된 다른 탭이 있는 경우
    /// 그쪽으로 자동 전환한다 — 사용자가 빈 에러 화면을 계속 보고 있지 않게.
    private func reportViewerAvailability(_ isAvailable: Bool, for mode: HWPViewerMode) {
        viewerAvailability[mode] = isAvailable
        // 성공 보고 때도 "현재 선택된 탭이 이미 실패로 확정돼 있으면" 성공한 탭으로 전환한다.
        // 네이티브(동기 파싱)가 rhwp(WKWebView+WASM 초기화)보다 먼저 실패를 보고하는 게 보통이라,
        // 실패 시점엔 폴백 후보가 없어 실패한 탭에 머문다 — 그 탭은 토글에서 숨겨진 채 실패 화면만
        // 남는다.
        if isAvailable {
            if viewerAvailability[hwpViewerMode] == false {
                hwpViewerMode = mode
            }
            return
        }
        guard hwpViewerMode == mode else { return }
        if let fallback = HWPViewerMode.allCases.first(where: { viewerAvailability[$0] == true }) {
            hwpViewerMode = fallback
        }
    }

    // MARK: - PDF 검색 바(단어 검색 + 일치 개수 + 다음/이전 이동)

    /// `OutlineQuickViewWindowContent.header`와 같은 모양의 검색창(검색어 입력 + "N/M" 일치 개수 +
    /// 다음/이전). `@Observable` 컨트롤러의 `query`에 양방향으로 쓰려면 `@Bindable` 로컬 바인딩이
    /// 필요하다.
    private var pdfSearchBar: some View {
        pdfSearchBar(controller: pdfSearchController)
    }

    /// 컨트롤러를 파라미터로 받는다 — `.docx` 변환 PDF는 원본과 다른 `PDFDocument`라 별도 컨트롤러가
    /// 필요하다(`docxSearchController`). 위 `pdfSearchBar`는 `.pdf` 케이스용 얇은 래퍼.
    private func pdfSearchBar(controller: PDFSearchController) -> some View {
        @Bindable var searchController = controller
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("검색", text: $searchController.query)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit { controller.goToNext() }

            if !controller.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(controller.matchCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    controller.goToPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
                .disabled(controller.matches.isEmpty)
                .help("이전 일치 항목")

                Button {
                    controller.goToNext()
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
                .disabled(controller.matches.isEmpty)
                .help("다음 일치 항목")
            }

            Spacer(minLength: 8)

            // 돋보기 3버튼 — 다른 뷰어(`OutlineQuickViewWindowContent`/`RhwpWebViewerPane`/`HWPViewerPane`)와
            // 같은 디자인(강조색 12% 원형 배경 + 35% 테두리, 28pt). 실제 확대/축소는
            // `PDFSearchController`가 `pdfView.scaleFactor`를 직접 읽고 써서 처리한다.
            Button {
                controller.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("확대")

            Button {
                controller.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("축소")

            Button {
                controller.resetZoom()
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("원본 크기 (\(Int((controller.zoomScale * 100).rounded()))%)")
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        // iOS에서는 `mainContent`의 `closeWindowButton`이 오른쪽 위 모서리에 떠 있어 "원본 크기"
        // 버튼과 겹치므로, 검색 바(및 `pdfConvertedSearchBar`)의 오른쪽 여백만 늘려 왼쪽으로 민다.
        // `closeWindowButton`은 다른 형식 뷰어와 공유하므로 옮기지 않는다. macOS는 이 버튼이 없어
        // 기존 여백(8)을 유지한다.
        #if os(iOS)
        .padding(.trailing, 44)
        #else
        .padding(.trailing, 8)
        #endif
    }

    // MARK: - 추출 텍스트(선택 가능한 순수 텍스트 + 검색)

    /// 추출 텍스트(PDF 외 형식) 화면의 검색 상태. PDFKit 대신 메모리의 `viewModel.textLines`를
    /// 필터링하므로 별도 컨트롤러 없이 `@State`만으로 충분하다.
    @State private var extractedTextSearchQuery: String = ""
    @State private var extractedTextCurrentMatchIndex: Int = 0

    /// 검색어를 `BibleReferenceExtractor`로 파싱해 (책ID, 장, 절)로 정규화한 뒤, 이 문서에
    /// 색인된 `VerseMention` 중 좌표가 겹치는 것의 `searchText`(문서 원문 표기, 예: "창1:1~5")를
    /// 돌려준다. 띄어쓰기/약어/전체이름은 파서가 흡수하고, 범위 표기는 색인 시 절 단위로
    /// 펼쳐져 있어 범위 안의 한 절만 검색해도 겹친다(`DocumentsHomeView.matchesVerseReference`와
    /// 같은 원리). 이 리터럴을 `extractedTextMatches`와 `PDFSearchController`의 추가 검색어로 쓴다.
    private func verseSearchLiteralTerms(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let queryMatches = BibleReferenceExtractor.extract(from: trimmed)
        guard !queryMatches.isEmpty else { return [] }

        let docId = document.id.uuidString
        // `sourceId`는 String 저장 프로퍼티라 #Predicate 등호 비교가 안전하다. enum rawValue인
        // `sourceType`은 프로젝트에서 predicate를 피하므로 아래에서 Swift 쪽으로 확인한다.
        let predicate = #Predicate<VerseMention> { $0.sourceId == docId }
        guard let mentions = try? modelContext.fetch(FetchDescriptor<VerseMention>(predicate: predicate)) else {
            return []
        }

        var seen = Set<String>()
        return mentions
            .filter { mention in
                mention.sourceType == .document
                    && queryMatches.contains { query in
                        query.bookId == mention.bookId
                            && query.chapter == mention.chapter
                            // 장만 가리키는 mention(`mention.verse == nil`)은 어떤 절 검색에도 걸리지 않게 한다(혼란 방지).
                            // 검색어 자체가 장만 가리키면(`query.verse == nil`) 그 장의 모든 mention과 매칭한다.
                            && (query.verse == nil || query.verse == mention.verse)
                    }
            }
            .map(\.searchText)
            // 범위 표현("창1:1~5")은 절 개수만큼 VerseMention으로 펼쳐져 있어
            // 같은 searchText가 여러 번 나올 수 있다 — 중복 제거.
            .filter { seen.insert($0).inserted }
    }

    /// 검색어와 일치하는 줄들의 id 목록(검색어가 비면 빈 배열). 리터럴 부분 문자열 일치에
    /// 더해 성경 장절 참조로 해석되는 검색어(`verseSearchLiteralTerms`)와 겹치는 줄도 찾는다.
    private func extractedTextMatches(viewModel: DocumentViewerViewModel) -> [UUID] {
        let trimmed = extractedTextSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let verseTerms = verseSearchLiteralTerms(for: trimmed)
        return viewModel.textLines
            .filter { line in
                line.lineText.localizedCaseInsensitiveContains(trimmed)
                    || verseTerms.contains { line.lineText.localizedCaseInsensitiveContains($0) }
            }
            .map(\.id)
    }

    private func goToNextExtractedTextMatch(viewModel: DocumentViewerViewModel) {
        let count = extractedTextMatches(viewModel: viewModel).count
        guard count > 0 else { return }
        extractedTextCurrentMatchIndex = (extractedTextCurrentMatchIndex + 1) % count
    }

    private func goToPreviousExtractedTextMatch(viewModel: DocumentViewerViewModel) {
        let count = extractedTextMatches(viewModel: viewModel).count
        guard count > 0 else { return }
        extractedTextCurrentMatchIndex = (extractedTextCurrentMatchIndex - 1 + count) % count
    }

    /// 추출 텍스트 화면. 강조 대상은 검색창 입력 중이면 현재 검색 일치 줄, 빈 검색어면
    /// [관련 내용]에서 넘어온 1회성 매치 줄(`initialSearchText`).
    private func extractedTextPane(viewModel: DocumentViewerViewModel) -> some View {
        Group {
            if viewModel.textLines.isEmpty {
                unavailableMessage(
                    document.conversionStatus == .failedNeedsManual
                        ? "이 문서는 자동 추출에 실패했습니다. 원본은 열람할 수 있지만 텍스트 검색은 지원되지 않습니다."
                        : "추출된 텍스트가 없습니다."
                )
            } else {
                VStack(spacing: 0) {
                    extractedTextSearchBar(viewModel: viewModel)
                    Divider()
                    extractedTextScrollView(viewModel: viewModel)
                }
            }
        }
    }

    private func extractedTextSearchBar(viewModel: DocumentViewerViewModel) -> some View {
        let matches = extractedTextMatches(viewModel: viewModel)
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("검색", text: $extractedTextSearchQuery)
                .textFieldStyle(.plain)
                .font(.body)
                .onChange(of: extractedTextSearchQuery) { _, _ in
                    extractedTextCurrentMatchIndex = 0
                }
                .onSubmit { goToNextExtractedTextMatch(viewModel: viewModel) }

            if !extractedTextSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(matches.isEmpty ? "0/0" : "\(extractedTextCurrentMatchIndex + 1)/\(matches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    goToPreviousExtractedTextMatch(viewModel: viewModel)
                } label: {
                    Image(systemName: "chevron.up")
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
                .disabled(matches.isEmpty)
                .help("이전 일치 항목")

                Button {
                    goToNextExtractedTextMatch(viewModel: viewModel)
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
                .disabled(matches.isEmpty)
                .help("다음 일치 항목")
            }
        }
        .padding(8)
    }

    private func extractedTextScrollView(viewModel: DocumentViewerViewModel) -> some View {
        let matches = extractedTextMatches(viewModel: viewModel)
        let currentMatchID = matches.isEmpty ? nil : matches[min(extractedTextCurrentMatchIndex, matches.count - 1)]
        // 검색창이 비어 있으면 "관련 내용"에서 넘어온 1회성 매치를 강조한다. `initialSearchText`는
        // 정규화된 표기("창세기 1:3")라 문서 원문("창1:3")과 리터럴로는 안 맞을 수 있어,
        // `verseSearchLiteralTerms`로 같은 해석을 적용한다.
        let fallbackMatchID: UUID? = {
            guard currentMatchID == nil, let initialSearchText, !initialSearchText.isEmpty else { return nil }
            let verseTerms = verseSearchLiteralTerms(for: initialSearchText)
            return viewModel.textLines.first { line in
                line.lineText.localizedCaseInsensitiveContains(initialSearchText)
                    || verseTerms.contains { term in line.lineText.localizedCaseInsensitiveContains(term) }
            }?.id
        }()
        let highlightedID = currentMatchID ?? fallbackMatchID

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.textLines, id: \.id) { line in
                        Text(line.lineText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .background(
                                line.id == highlightedID
                                    ? Color.yellow.opacity(0.35) : Color.clear
                            )
                            .id(line.id)
                    }
                }
                .padding()
            }
            .onAppear {
                guard let highlightedID else { return }
                // 레이아웃이 자리 잡기 전에 스크롤하면 위치가 어긋날 수 있어
                // 한 프레임 정도 늦춘다.
                DispatchQueue.main.async {
                    proxy.scrollTo(highlightedID, anchor: .center)
                }
            }
            .onChange(of: currentMatchID) { _, newValue in
                guard let newValue else { return }
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func unavailableMessage(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// iCloud에만 있고 아직 내려받지 않은 파일의 안내 화면. `.downloading`이면 진행률,
    /// `.failed`면 원인, `.ready`(받았는데도 못 연 경우)면 기존 폴백 메시지를 보여준다.
    @ViewBuilder
    private func fileContentUnavailableView(
        status: UbiquitousFileDownloadMonitor.Status,
        fallbackMessage: String
    ) -> some View {
        switch status {
        case .downloading(let progress):
            downloadingMessage(progress: progress)
        case .failed(let reason):
            unavailableMessage("iCloud에서 파일을 다운로드하지 못했습니다.\n\(reason)")
        case .ready:
            unavailableMessage(fallbackMessage)
        }
    }

    /// `fileContentUnavailableView`의 `.downloading` 케이스 — `ProgressView(value:)`로 다운로드 진행률을 보여준다.
    private func downloadingMessage(progress: Double) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .frame(maxWidth: 240)
            Text("iCloud에서 다운로드하는 중… \(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setUpIfNeeded() {
        guard viewModel == nil else { return }
        let vm = DocumentViewerViewModel(document: document, modelContext: modelContext)
        vm.onAppear(initialSearchText: initialSearchText)
        viewModel = vm
        // PDFKit 검색 컨트롤러 둘(`.pdf` 원본, `.docx` PDF 변환)은 같은 `document`를 대상으로 하므로
        // 같은 리졸버를 연결한다. `HWPToPDFPane`은 `document`에 접근할 수 없어 `originalPane`에서
        // 이 함수를 파라미터로 넘겨 연결한다.
        pdfSearchController.additionalSearchTerms = verseSearchLiteralTerms(for:)
        docxSearchController.additionalSearchTerms = verseSearchLiteralTerms(for:)
        // 초기 검색어는 새 검색창(`pdfSearchController.query`)으로 전달한다.
        if let initialSearchText, document.originalFormat == .pdf {
            pdfSearchController.query = initialSearchText
        }
        // 이미지 모음도 같은 방식 — 검색결과에서 열렸으면 화면 안 검색칸을 그 검색어로 채운다.
        if let initialSearchText, document.originalFormat == .image {
            imageSearchQuery = initialSearchText
        }
        // `.docx`의 변환 PDF는 iCloud 다운로드 완료 후 늦게 채워질 수 있어, 그 검색어 연결은
        // 여기서 한 번만 하지 않고 `docxContent`의 `syncDocxViewerModeIfConvertedPDFReady`에서 처리한다.
        documentTags = (document.documentTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
    }

    // MARK: - 태그 (MemoDetailView.tagSection과 같은 패턴, DocumentTag 조인 사용)

    private var documentTagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 라벨과 태그 칩을 같은 `HStack`에 두어 칩이 라벨 오른쪽에 붙게 한다. 칩이 줄바꿈되어도
            // 라벨이 같이 밀리지 않도록 `alignment: .top`.
            HStack(alignment: .top, spacing: 8) {
                Text("태그")

                FlowLayoutHStack {
                    ForEach(documentTags) { tag in
                        HStack(spacing: 4) {
                            Text(tag.name)
                                .onTapGesture { drilldownTag = tag }
                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color("AccentColor").opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }

            HStack {
                TextField("태그 입력 후 Enter", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit { commitTagInput() }
                    .onChange(of: tagInput) { _, newValue in
                        updateTagSuggestions(for: newValue)
                    }
                if !tagSuggestions.isEmpty {
                    Menu {
                        ForEach(tagSuggestions) { suggestion in
                            Button(suggestion.name) { addTag(suggestion) }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                }
            }
            .frame(maxWidth: 280)
        }
        .padding(12)
    }

    private func updateTagSuggestions(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            tagSuggestions = []
            return
        }
        do {
            let all = try modelContext.fetch(FetchDescriptor<Tag>(
                predicate: #Predicate<Tag> { $0.mergedIntoId == nil }
            ))
            tagSuggestions = Array(
                all
                    .filter { $0.normalizedForm.contains(trimmed) }
                    .filter { candidate in !documentTags.contains { $0.id == candidate.id } }
                    .sorted {
                        let lhsCount = $0.documentTags?.count ?? 0
                        let rhsCount = $1.documentTags?.count ?? 0
                        if lhsCount != rhsCount { return lhsCount > rhsCount }
                        return $0.name < $1.name
                    }
                    .prefix(8)
            )
        } catch {
            tagSuggestions = []
        }
    }

    private func commitTagInput() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let tag = try TagDeduplication.findOrCreateTag(named: trimmed, context: modelContext)
            addTag(tag)
        } catch {
            print("[DocumentViewerView] 태그 생성 실패: \(error)")
        }
        tagInput = ""
        tagSuggestions = []
    }

    private func addTag(_ tag: Tag) {
        guard !documentTags.contains(where: { $0.id == tag.id }) else { return }
        let join = DocumentTag(document: document, tag: tag)
        modelContext.insert(join)
        documentTags.append(tag)
        tagInput = ""
        tagSuggestions = []
        try? modelContext.save()
    }

    private func removeTag(_ tag: Tag) {
        if let join = (document.documentTags ?? []).first(where: { $0.tag?.id == tag.id }) {
            modelContext.delete(join)
        }
        documentTags.removeAll { $0.id == tag.id }
        try? modelContext.save()
    }
}

// MARK: - PDFKit 네이티브 뷰(높은 신뢰도 — schema.md 0장에서 이미 채택 확정)

#if os(macOS)
private struct PDFKitRepresentable: NSViewRepresentable {
    let document: PDFDocument
    /// 생성된 `PDFView`를 `searchController`에 연결하는 것이 이 표현형의 유일한 역할이다.
    /// 검색/이동은 컨트롤러가 그 `PDFView`에 직접 명령한다.
    let searchController: PDFSearchController

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        searchController.pdfView = view
        return view
    }
    func updateNSView(_ nsView: PDFView, context: Context) {
        // SwiftUI가 재계산할 때마다 `.document`에 무조건 대입하면 같은 내용이라도 `PDFView`가
        // 다시 그려져 스크롤/확대 위치가 흔들릴 수 있어, 참조가 바뀐 경우에만(`!==`) 대입한다.
        if nsView.document !== document {
            nsView.document = document
        }
        if searchController.pdfView !== nsView {
            searchController.pdfView = nsView
        }
    }
}
#else
private struct PDFKitRepresentable: UIViewRepresentable {
    let document: PDFDocument
    let searchController: PDFSearchController

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        searchController.pdfView = view
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        // 위 macOS `updateNSView`와 같은 이유 — 동일성 검사로 불필요한 재대입을
        // 막는다.
        if uiView.document !== document {
            uiView.document = document
        }
        if searchController.pdfView !== uiView {
            searchController.pdfView = uiView
        }
    }
}
#endif

/// `PDFView`에 대한 참조를 직접 들고 검색창의 입력/버튼에 바로 명령을 내리는 명령형
/// 컨트롤러. "다음/이전"처럼 매번 다른 동작은 `updateNSView`의 선언적 diff로 표현하기
/// 어려워 이 패턴을 쓴다(AppKit/UIKit 상호운용의 일반적 방식).
@MainActor
@Observable
final class PDFSearchController {
    /// `PDFKitRepresentable`이 실제 `PDFView`가 만들어지는 대로 연결해 준다. `PDFView`는
    /// SwiftUI 뷰 계층이 소유하므로 순환 참조 방지를 위해 `weak`로 둔다.
    weak var pdfView: PDFView? {
        didSet {
            guard pdfView != nil, !query.isEmpty else { return }
            performSearch()
        }
    }

    var query: String = "" {
        didSet {
            guard oldValue != query else { return }
            performSearch()
        }
    }

    private(set) var matches: [PDFSelection] = []
    private(set) var currentIndex: Int = 0

    /// 타이핑된 검색어가 성경 참조("창세기 1:3")일 때 문서에 실제로 적힌 다른 표현("창1:1~5")도
    /// 찾도록, `DocumentViewerView`가 `verseSearchLiteralTerms(for:)`를 연결하는 주입 지점.
    /// `PDFDocument.findString`이 리터럴 부분 문자열만 찾기 때문이며, 이 컨트롤러가
    /// `SourceDocument`/`VerseMention`을 몰라도 되도록 의존성을 역전시켰다.
    var additionalSearchTerms: (String) -> [String] = { _ in [] }

    var matchCountText: String {
        matches.isEmpty ? "0/0" : "\(currentIndex + 1)/\(matches.count)"
    }

    // MARK: - 확대/축소 (2026-09-05 추가)

    /// 확대/축소 범위와 단위(앱의 다른 뷰어와 동일). `pdfView.scaleFactor`를 그대로 읽고 써서
    /// 트랙패드 핀치줌과 버튼이 항상 같은 값을 공유한다(별도 SwiftUI 상태를 두면 핀치 결과를
    /// 되돌리는 충돌이 생긴다).
    ///
    /// ⚠️ [알려진 한계] `zoomScale`은 그때그때 읽는 계산 프로퍼티라, 핀치줌 직후에는 `.help()`
    /// 툴팁의 퍼센트가 즉시 갱신되지 않을 수 있다(버튼을 누르면 정확해진다). 갱신하려면
    /// `.PDFViewScaleChanged` 구독이 필요한데 툴팁 하나를 위해 추가하지 않았다. 실제
    /// 확대/축소 동작은 영향받지 않는다.
    static let minZoom: CGFloat = 0.5
    static let maxZoom: CGFloat = 3.0
    static let zoomStep: CGFloat = 0.1

    var zoomScale: CGFloat { pdfView?.scaleFactor ?? 1.0 }

    func zoomIn() {
        guard let pdfView else { return }
        pdfView.scaleFactor = min(Self.maxZoom, pdfView.scaleFactor + Self.zoomStep)
    }

    func zoomOut() {
        guard let pdfView else { return }
        pdfView.scaleFactor = max(Self.minZoom, pdfView.scaleFactor - Self.zoomStep)
    }

    func resetZoom() {
        pdfView?.scaleFactor = 1.0
    }

    /// ⚠️ [알려진 한계] `PDFDocument.findString`은 문서 전체를 동기적으로 훑고 타이핑마다
    /// 다시 검색하므로, 매우 긴 PDF(수백 페이지)에서는 검색창 반응이 잠깐 끊길 수 있다
    /// (디바운스/비동기화 미적용). 성경 참조로 풀린 리터럴 표현마다 검색이 한 번씩 더 일어난다.
    func performSearch() {
        currentIndex = 0
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pdfView, let document = pdfView.document, !trimmed.isEmpty else {
            matches = []
            return
        }
        // `additionalSearchTerms`가 결과를 돌려주면(참조로 인식되어 이 문서에 색인된 표현이 있으면)
        // 그것만 신뢰하고, 원문은 결과가 비었을 때만 폴백으로 쓴다. 원문("창1:1")을 항상 같이 찾으면
        // "창1:14" 같은 접두사 오탐이 생기기 때문이다(`RhwpWebViewerPane`/`HWPViewerPane`의
        // `additionalSearchTerms(initialSearchText).first ?? initialSearchText`와 같은 원칙).
        let resolvedTerms = additionalSearchTerms(trimmed)
        let terms = resolvedTerms.isEmpty ? [trimmed] : resolvedTerms
        var seenTerms = Set<String>()
        let uniqueTerms = terms.filter { seenTerms.insert($0.lowercased()).inserted }

        // `findString`은 리터럴 부분 문자열 검색이라 "1:1"이 "1:14"/"1:11"(접두사)이나 "21:1"(접미사)에도
        // 걸리고, `.regularExpression` 옵션은 PDFKit이 지원하지 않는다(지원 옵션은 대소문자/리터럴/
        // 역방향뿐). 그래서 `matchesWithDigitBoundary`가 페이지 원문에 직접 `NSRegularExpression`을
        // 돌려 앞뒤에 숫자가 없을 때만 매치시키고, 문자 인덱스 범위를
        // `PDFDocument.selection(from:atCharacterIndex:to:atCharacterIndex:)`로 `PDFSelection`으로 바꾼다.
        let found = uniqueTerms.flatMap { matchesWithDigitBoundary(for: $0, in: document) }
        // 여러 검색어를 따로 찾아 이어붙인 결과라 문서 순서가 뒤섞여 있다 —
        // "다음/이전"이 위→아래로 자연스럽게 움직이도록 페이지·페이지 안
        // 세로 위치(위에서 아래) 기준으로 다시 정렬한다.
        matches = found.sorted { lhs, rhs in
            guard let lhsPage = lhs.pages.first, let rhsPage = rhs.pages.first else { return false }
            let lhsIndex = document.index(for: lhsPage)
            let rhsIndex = document.index(for: rhsPage)
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            let lhsBounds = lhs.bounds(for: lhsPage)
            let rhsBounds = rhs.bounds(for: rhsPage)
            // PDF 좌표계는 y가 아래→위로 증가하므로, "위에서 아래로 읽는 순서"는
            // y값이 큰(위쪽) 쪽이 먼저다.
            if abs(lhsBounds.minY - rhsBounds.minY) > 1 { return lhsBounds.minY > rhsBounds.minY }
            return lhsBounds.minX < rhsBounds.minX
        }
        highlightCurrent()
    }

    /// `findString` 대신 페이지 원문에 `NSRegularExpression`을 돌려, 검색어 앞뒤에 숫자가 붙은
    /// 오탐("1:1" ↔ "1:14"/"21:1")을 막는다. `term`은 `escapedPattern(for:)`로 이스케이프하고
    /// `(?<!\d)`/`(?!\d)`를 붙이므로, 숫자로 시작/끝나지 않는 `term`은 기존 결과와 같다.
    private func matchesWithDigitBoundary(for term: String, in document: PDFDocument) -> [PDFSelection] {
        guard !term.isEmpty else { return [] }
        let pattern = "(?<!\\d)" + NSRegularExpression.escapedPattern(for: term) + "(?!\\d)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        var selections: [PDFSelection] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let text = page.string else { continue }
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            for result in regex.matches(in: text, range: fullRange) {
                guard result.range.length > 0 else { continue }
                let startIndex = result.range.location
                let endIndex = result.range.location + result.range.length - 1
                if let selection = document.selection(
                    from: page, atCharacterIndex: startIndex,
                    to: page, atCharacterIndex: endIndex
                ) {
                    selections.append(selection)
                }
            }
        }
        return selections
    }

    func goToNext() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        highlightCurrent()
    }

    func goToPrevious() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        highlightCurrent()
    }

    private func highlightCurrent() {
        guard let pdfView, matches.indices.contains(currentIndex) else { return }
        let selection = matches[currentIndex]
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
    }
}

// MARK: - hwp 뷰어 종류(2026-08-16 재도입 — hwpViewerModeToggle 참고)

/// `.hwp`/`.hwpx` 문서를 열 때 고를 수 있는 뷰어들. `HWPViewerPane`(hwp-swift 네이티브),
/// `RhwpWebViewerPane`(rhwp WKWebView 웹 뷰어), `HWPToPDFPane`(rhwp SVG를 오프스크린
/// WKWebView의 `createPDF`로 PDF화)가 같은 `Data`를 받아 각자 렌더링한다. rhwp.js(WASM)
/// 자체에는 PDF 기능이 없어 PDF 탭은 `RhwpPDFExportService`가 담당한다.
private enum HWPViewerMode: String, CaseIterable, Identifiable {
    case hwpSwiftNative
    case rhwpWeb
    case pdfConverted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hwpSwiftNative: return "hwp-swift (네이티브)"
        case .rhwpWeb: return "rhwp (웹)"
        case .pdfConverted: return "PDF 변환"
        }
    }
}

/// pages 뷰어 모드. QuickLook은 순수 렌더링 API라 텍스트를 앱으로 돌려주지 않아 그 안에서
/// 검색할 수 없으므로, "원본(QuickLook, 시각적으로 정확·검색 불가)"과
/// "텍스트(SwiftTextPages로 추출, 검색 가능)"를 세그먼트로 오가게 한다.
private enum PagesViewerMode: String, CaseIterable, Identifiable {
    case quickLook
    case extractedText

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quickLook: return "원본(Quick Look)"
        case .extractedText: return "텍스트(검색)"
        }
    }
}

/// docx 뷰어 모드. `HWPViewerMode`/`PagesViewerMode`와 같은 패턴으로 사용자가 세그먼트로 직접
/// 오간다. "PDF 변환"은 `HWPViewerMode.pdfConverted`와 같은 개념(업로드 시 미리 변환해 둔 PDF).
private enum DocxViewerMode: String, CaseIterable, Identifiable {
    case preview
    case pdfConverted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview: return "미리보기"
        case .pdfConverted: return "PDF 변환"
        }
    }
}

// MARK: - hwp 뷰어(hwp-swift/HwpKit 네이티브 렌더러 기반, 위 파일 상단 [2026-08-16 전면 교체] 참고)

/// 원본 보기에서 hwp 문서 바이트가 준비됐을 때 그리는 네이티브 뷰어.
/// `HwpKit`의 `HwpDocumentView`/`HwpSearchController`/`HwpSearchBar`를 쓰는 순수 SwiftUI 구성이며,
/// 상단은 검색창 + 돋보기 아이콘 버튼 3개(`searchAndZoomBar`)로 pdf 뷰어(`pdfSearchBar`)와 같은 모양이다.
private struct HWPViewerPane: View {
    let documentData: Data
    /// 관련 연구문서에서 넘어온 검색어 — `load()` 완료 직후 `search.search(text:)`로 흘려보낸다.
    /// 지오메트리가 아직 없으면 `HwpSearchController`가 질의만 저장해 두고, `HwpDocumentView`가 나중에
    /// `attach(to:)`할 때 저장된 질의로 다시 스캔하므로 호출 순서는 상관없다.
    var initialSearchText: String? = nil
    /// `HwpSearchController.search(text:)`는 검색어 하나만 받으므로, 부모가 돌려준 리터럴 표현이 있으면
    /// 그중 첫 번째(문서에 실제로 적힌 표기)를, 없으면 원래 입력을 쓴다 — `load()` 참고.
    var additionalSearchTerms: (String) -> [String] = { _ in [] }
    /// 로드 성공/실패를 상위(`DocumentViewerView.reportViewerAvailability`)에 보고한다.
    var onAvailabilityChange: ((Bool) -> Void)? = nil
    @State private var document: HwpDocument?
    @State private var errorMessage: String?
    @State private var currentPage: Int = 1
    @State private var zoomScale: CGFloat = 1.0
    /// 문서 내 검색 세션 — `HwpDocumentView`와 `HwpSearchBar`에 같은 인스턴스를 넘기면
    /// 하이라이트·매치 이동이 라이브러리 안에서 자동 연결된다.
    @State private var search = HwpSearchController()
    @FocusState private var searchFieldFocused: Bool

    /// 앱 전체의 돋보기 아이콘 3개(확대/축소/원본크기) 패턴과 같은 줌 범위.
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 3.0
    private static let zoomStep: CGFloat = 0.1

    var body: some View {
        Group {
            if let document {
                VStack(spacing: 0) {
                    searchAndZoomBar
                    Divider()
                    HwpDocumentView(
                        document: document,
                        zoomScale: $zoomScale,
                        currentPage: $currentPage,
                        searchController: search,
                        onHyperlinkTapped: { url in
                            print("[HWPViewerPane] hyperlink tapped: \(url)")
                        },
                        onUnsupportedElement: { element in
                            print("[HWPViewerPane] unsupported element: \(element)")
                        }
                    )
                }
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("hwp 문서를 열지 못했습니다.")
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("문서를 여는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // documentData가 바뀌면 재로딩한다(값 비교라 같은 파일 재진입은 다시 파싱하지 않음).
        .task(id: documentData) {
            await load()
        }
    }

    /// 검색창 + 돋보기 버튼 3개를 한 줄로 배치한다. 페이지 이동은 `HwpDocumentView`의 스크롤/제스처로 대신한다.
    private var searchAndZoomBar: some View {
        HStack(spacing: 8) {
            HwpSearchBar(controller: search, isFocused: $searchFieldFocused)

            Spacer(minLength: 8)

            // `OutlineQuickViewWindowContent.header`와 같은 스타일(강조색 12% 원형 배경 + 35% 테두리, 28pt).
            Button {
                zoomScale = min(Self.maxZoom, zoomScale + Self.zoomStep)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("확대")

            Button {
                zoomScale = max(Self.minZoom, zoomScale - Self.zoomStep)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("축소")

            Button {
                zoomScale = 1.0
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("원본 크기 (\(Int((zoomScale * 100).rounded()))%)")
        }
        .padding(8)
    }

    private func load() async {
        document = nil
        errorMessage = nil
        do {
            document = try await HwpDocumentLoader().load(from: documentData)
            onAvailabilityChange?(true)
            if let initialSearchText, !initialSearchText.isEmpty {
                let resolvedTerm = additionalSearchTerms(initialSearchText).first ?? initialSearchText
                search.search(text: resolvedTerm)
            }
        } catch {
            errorMessage = "\(error)"
            onAvailabilityChange?(false)
        }
    }
}

// MARK: - hwp → PDF 변환 탭(2026-08-16 신설, 위 HWPViewerMode 주석 참고)

/// hwp를 PDF로 변환해 보여주는 탭.
/// rhwp 엔진 자체에는 PDF 내보내기가 없어(`exportHwp*` 계열은 HWP/HWPX/HML 포맷 내보내기),
/// `RhwpPDFExportService`가 rhwp.js의 `renderPageSvg` → 오프스크린 `WKWebView` →
/// `WKWebView.createPDF` → PDFKit 이어붙이기로 변환한다. 렌더링 파이프라인이 네이티브 탭
/// (`HWPViewerPane`)과 달라 별도 탭으로 둔다. ⚠️ 알려진 위험은 `RhwpPDFExportService.swift` 상단 주석 참고.
/// 업로드 시 `DocumentUploadService.generateConvertedPDF`가 미리 만든 PDF(`preConvertedDocument`)가 있으면
/// 그대로 보여주고, 없는 기존 문서는 탭을 열 때 즉석 변환한다.
private struct HWPToPDFPane: View {
    let documentData: Data
    /// `DocumentViewerViewModel.convertedPDFDocument` — 업로드 시 미리 변환해 둔 결과(있을 때만 채워짐).
    let preConvertedDocument: PDFDocument?
    /// 부모(`DocumentViewerView.verseSearchLiteralTerms(for:)`)가 넘겨주는 성경 장절 검색 리졸버.
    /// 이 struct는 `SourceDocument`에 접근하지 못해 클로저로 받는다.
    var additionalSearchTerms: (String) -> [String] = { _ in [] }
    /// 검색어 자동 하이라이트용 초기 검색어. 네이티브 뷰어 로드 실패 시 이 탭으로 자동 전환되므로
    /// 이 탭에서도 `pdfSearchController.query`로 똑같이 흘려보낸다.
    var initialSearchText: String? = nil
    /// 로드 성공/실패를 상위에 보고한다(`HWPViewerPane.onAvailabilityChange`와 동일).
    var onAvailabilityChange: ((Bool) -> Void)? = nil
    @State private var pdfDocument: PDFDocument?
    @State private var errorMessage: String?
    @State private var conversionProgress: (pageIndex: Int, pageCount: Int)?
    @State private var exportService = RhwpPDFExportService()
    /// 원본 `.pdf` 탭의 `pdfSearchController`와는 별개 인스턴스 — 서로 다른 문서를 검색하므로 공유하면 안 된다.
    @State private var pdfSearchController = PDFSearchController()

    var body: some View {
        Group {
            if let pdfDocument {
                VStack(spacing: 0) {
                    pdfConvertedSearchBar
                    Divider()
                    PDFKitRepresentable(document: pdfDocument, searchController: pdfSearchController)
                }
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("PDF로 변환하지 못했습니다.")
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let conversionProgress {
                VStack(spacing: 8) {
                    ProgressView(
                        value: conversionProgress.pageCount > 0
                            ? Double(conversionProgress.pageIndex) / Double(conversionProgress.pageCount)
                            : 0
                    )
                    .frame(maxWidth: 200)
                    Text("PDF로 변환하는 중… (\(conversionProgress.pageIndex + 1)/\(conversionProgress.pageCount)쪽)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("PDF로 변환하는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // documentData가 바뀌면 다시 변환한다(`HWPViewerPane.load()`와 같은 패턴).
        .task(id: documentData) {
            await convert()
        }
        // 부모가 넘긴 성경 장절 검색 리졸버를 이 탭의 `pdfSearchController`에 연결한다.
        .onAppear {
            pdfSearchController.additionalSearchTerms = additionalSearchTerms
        }
        // `preConvertedDocument`는 탭이 떠 있는 도중(원본은 받아졌고 변환 PDF는 아직 다운로드 중이던 경우)
        // nil에서 채워질 수 있다. 놓치면 이미 시작된 즉석 변환본이 계속 남으므로, `PDFDocument`가
        // Equatable이 아니라 `!= nil`(Bool)의 false → true 전환을 관찰해 그 시점의 값을 채택한다.
        .onChange(of: preConvertedDocument != nil) { _, isAvailable in
            guard isAvailable, let preConvertedDocument else { return }
            pdfDocument = preConvertedDocument
            seedInitialSearchTextIfNeeded()
            onAvailabilityChange?(true)
        }
    }

    /// 원본 `.pdf` 탭의 `pdfSearchBar`와 같은 모양의 검색창 + 돋보기 버튼 3개.
    private var pdfConvertedSearchBar: some View {
        @Bindable var searchController = pdfSearchController
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("검색", text: $searchController.query)
                .textFieldStyle(.plain)
                .onSubmit { pdfSearchController.goToNext() }

            if !pdfSearchController.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(pdfSearchController.matchCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    pdfSearchController.goToPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
                .disabled(pdfSearchController.matches.isEmpty)
                .help("이전 일치 항목")

                Button {
                    pdfSearchController.goToNext()
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
                .disabled(pdfSearchController.matches.isEmpty)
                .help("다음 일치 항목")
            }

            Spacer(minLength: 8)

            // 원본 `.pdf` 탭과 같은 디자인·같은 `PDFSearchController.zoomIn/zoomOut/resetZoom` API를 쓴다
            // (`pdfView.scaleFactor`를 직접 읽고 써서 트랙패드 핀치줌과 같은 값을 공유).
            Button {
                pdfSearchController.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("확대")

            Button {
                pdfSearchController.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("축소")

            Button {
                pdfSearchController.resetZoom()
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("원본 크기 (\(Int((pdfSearchController.zoomScale * 100).rounded()))%)")
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        // `pdfSearchBar(controller:)`와 같은 이유로 iOS에서는 오른쪽 끝 버튼이 겹치지 않게 trailing 여백을 더 둔다.
        #if os(iOS)
        .padding(.trailing, 44)
        #else
        .padding(.trailing, 8)
        #endif
    }

    /// 사전 변환본(`preConvertedDocument`)이 있으면 그대로 쓰고, 없을 때만 `RhwpPDFExportService`로 즉석 변환한다.
    private func convert() async {
        pdfDocument = nil
        errorMessage = nil
        conversionProgress = nil

        if let preConvertedDocument {
            pdfDocument = preConvertedDocument
            seedInitialSearchTextIfNeeded()
            onAvailabilityChange?(true)
            return
        }

        do {
            let data = try await exportService.exportPDF(documentData: documentData) { pageIndex, pageCount in
                conversionProgress = (pageIndex, pageCount)
            }
            guard let pdf = PDFDocument(data: data) else {
                errorMessage = "PDF 데이터를 만들었지만 열 수 없습니다."
                onAvailabilityChange?(false)
                return
            }
            pdfDocument = pdf
            seedInitialSearchTextIfNeeded()
            onAvailabilityChange?(true)
        } catch {
            errorMessage = "\(error)"
            onAvailabilityChange?(false)
        }
    }

    /// `pdfDocument`가 채워진 두 지점(사전 변환본 재사용/즉석 변환 성공)에서 초기 검색어를 적용한다.
    private func seedInitialSearchTextIfNeeded() {
        guard let initialSearchText, !initialSearchText.isEmpty else { return }
        pdfSearchController.query = initialSearchText
    }
}
