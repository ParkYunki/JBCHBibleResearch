//
//  DocumentViewerView.swift
//  JBCHBibleResearch
//
//  S6(연구문서 원문 뷰어). screens.md 3장 S5/S6/S7 절 — "원본 hwp 뷰어(S6)는
//  WKWebView + rhwp-studio 새 창/시트로" + "⚠️ S6에 '추출 텍스트' 패널 필요".
//
//  [2026-08-15 교체] 사용자 요청 — "hwp관련 뷰어를 구현하고자 함." 처음엔
//  rhwp(https://github.com/edwardkim/rhwp, Rust+WebAssembly, MIT)를
//  WKWebView에 번들해 페이지별 SVG를 그리는 방식으로 구현했다.
//
//  [2026-08-16 전면 교체] 그런데 실기기 검증 내내(HWPWebViewSupport.swift·
//  HWPTextExtractor.swift 옛 버전 상단 주석에 그 과정이 남아 있었다) WKWebView
//  WebContent 프로세스가 App Sandbox 안에서 계속 실패했다 — network.client
//  entitlement 누락, JS 모듈/WASM fetch 실패, off-screen WKWebView가 RunningBoard
//  foreground assertion을 못 얻는 문제 등. 디버그 채널까지 추가해도 근본 원인이
//  샌드박스/프로세스 provisioning 레벨이라 코드로 계속 우회하기 어려웠다.
//
//  사용자가 대안으로 제시한 hwp-swift(https://github.com/sboh1214/hwp-swift,
//  LGPL-2.1)로 전면 교체했다 — 순수 네이티브 Swift 패키지(WKWebView/WASM 전혀
//  없음)라 위 문제 전체가 구조적으로 사라진다. `HwpKit`이 제공하는
//  `HwpDocumentLoader`(비동기 로더) + `HwpDocumentView`(SwiftUI 렌더러) +
//  `HwpSearchController`/`HwpSearchBar`(문서 내 검색)를 그대로 쓴다.
//
//  [2026-08-16 PDF 변환 탭 추가] 위에서 "다음 라운드에 추가"라던 PDF 변환을
//  이번에 붙였다 — 처음엔 `HwpKit.HwpPDFExporter`를 쓸 생각이었는데, 실제
//  조사해 보니 그 타입의 소스 파일을 찾을 수 없었다(hwp-swift의
//  `HwpKitCore/AGENTS.md`엔 "공개 표면은 HwpKit.HwpPDFExporter"라고 적혀
//  있지만, GitHub API로 여러 경로를 시도해도 실제 파일이 안 잡혔다 — 이 저장소
//  API 조회가 이번 세션 내내 종종 실패했던 것과 같은 증상). 대신 소스로 직접
//  확인된 `HwpKitNative.HwpPDFRenderer`(순수 CoreGraphics PDF 렌더러)를
//  곧바로 썼었다.
//
//  [2026-08-16 PDF 탭 재구현] 그런데 사용자가 이 첫 버전을 거부했다 — "현재
//  pdf는 네이티브 뷰어와 동일하므로 존재 이유가 없음"(`HwpKitNative.
//  HwpPDFRenderer`가 `HWPViewerPane`과 똑같은 `HwpDocument` paint list를
//  그대로 PDF로 뽑는 것뿐이라, 두 탭의 렌더링 결과가 사실상 같았다). 대신
//  처음에 검토만 하고 채택하지 않았던 postmelee/alhangeul-macos 방식(rhwp의
//  `renderPageSvg` → 오프스크린 WKWebView → `WKWebView.createPDF`)을 "WKWebView
//  취약점 범주가 그대로 재발할 수 있는 접근이라 해도 한번 구현테스트를 확인할
//  수 있도록" 해 달라는 명시적 요청을 받아 `RhwpPDFExportService`
//  (Services/Documents/RhwpPDFExportService.swift)로 새로 구현했다. 이제
//  네이티브 탭(hwp-swift paint list)과 렌더링 파이프라인이 완전히 다른
//  결과물이라 별도 탭으로서 존재 이유가 생긴다. 자세한 경위는
//  `HWPToPDFPane`(DocumentViewerView.swift 하단) 상단 주석과
//  `RhwpPDFExportService.swift` 상단 주석 참고. `HwpKitNative`는 더 이상 쓰지
//  않는다.
//
//  Xcode에서 File > Add Package Dependencies로
//  https://github.com/sboh1214/hwp-swift.git (branch: main)를 추가하고
//  `HwpKit` 프로덕트를 이 타깃에 링크해야 빌드된다(SPM 원격 의존성은 Xcode
//  GUI에서 추가하기로 결정 — project.pbxproj 직접 편집보다 안전).
//
//  PDF는 여전히 PDFKit이 이미 검증된 Apple 프레임워크라 그대로 구현했다(신뢰도 높음).
//

import SwiftUI
import SwiftData
import PDFKit
import HwpKit
import HwpKitCore
import BibleResearchModels

// MARK: - 별도 창(S6) 진입점 — PersistentIdentifier → SourceDocument 되찾기

/// [2026-08-07 추가] `WindowGroup(id: "document-viewer", for: PersistentIdentifier.self)`
/// (JBCHBibleResearchApp.swift 참고)가 넘겨주는 `PersistentIdentifier?`를 실제
/// `SourceDocument` 인스턴스로 되찾아 `DocumentViewerView`에 넘기는 얇은 래퍼.
/// `nil`이거나(창을 값 없이 열었을 때) 해당 ID의 모델을 못 찾으면(문서가 그 사이
/// 삭제된 경우 등) 안내 문구만 보여준다.
struct DocumentViewerWindowContent: View {
    /// [2026-08-15 수정, 크래시 fix] 사용자 보고 — `SourceDocument.originalFilename.getter`
    /// fatal error(`DocumentViewerView.body.getter`에서 `.navigationTitle(document.
    /// originalFilename)` 호출 중 발생). 원인 — 예전엔 `modelContext.model(for:)`로
    /// 딱 한 번만 객체를 찾아 `DocumentViewerView`에 그대로 넘겼다. macOS는 이
    /// S6 창을 열어 둔 채로 다른 창(문서 목록, 설정 개발자 탭의 "연구문서 전체
    /// 삭제")에서 같은 `SourceDocument`를 지울 수 있는데, 그러면 이 창이 들고
    /// 있던 참조가 SwiftData 쪽에서 이미 소멸된 객체를 가리키게 되고, 다음
    /// 재렌더링(`body` 재계산)에서 그 객체의 아무 프로퍼티나 읽으려는 순간
    /// 크래시한다 — `DocumentsHomeView`가 겪었던 것과 완전히 같은 종류의 버그
    /// (그때는 `@Query`로 고쳤다, DocumentsViewModel.swift 상단 주석 참고).
    /// 여기도 같은 처방 — `@Query`는 SwiftData 변경(삭제 포함)에 자동으로
    /// 반응해 다시 계산되므로, 문서가 지워지면 `documents.first(where:)`가
    /// 자연스럽게 nil이 되어 `documentNotFoundMessage()`로 넘어간다(크래시 대신
    /// "문서를 찾을 수 없습니다" 안내) — `DocumentViewerView`가 죽은 참조를
    /// 다시 렌더링할 기회 자체가 없어진다.
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

/// [2026-08-11 신설] `WindowGroup(id: "document-search", for: DocumentSearchRequest.self)`
/// (JBCHBibleResearchApp.swift 참고) 전용 — "관련 내용"에서 문서를 골랐을 때, 그
/// 문서를 열면서 동시에 검색어(성경 구절 원문 표현)로 찾아 이동한다. 위
/// `DocumentViewerWindowContent`와 거의 같지만 `initialSearchText`를 하나 더
/// `DocumentViewerView`에 전달한다는 점만 다르다 — 별도 타입으로 둔 이유는 위
/// `DocumentSearchRequest.swift` 상단 주석 참고.
struct DocumentSearchWindowContent: View {
    /// [2026-08-15 수정] 위 `DocumentViewerWindowContent`와 같은 크래시 fix —
    /// 같은 이유로 `@Query`로 바꿨다.
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
    let document: SourceDocument
    /// [2026-08-11 추가] "관련 내용"에서 넘어온 검색어 — 있으면 열자마자 그 텍스트를
    /// 찾아 이동한다("연구 문서는 pdf로 띄워 검색할 것", 사용자 요청). PDF 원본이
    /// 있으면 PDFKit 검색+이동, 없으면(hwp/이미지 등) 추출된 텍스트 화면에서 그
    /// 줄로 스크롤+강조하는 것으로 대신한다(2026-08-15 — 수동 탭 전환 UI는
    /// 삭제되고 이제 자동으로 판단된다, `shouldShowExtractedText` 참고).
    var initialSearchText: String? = nil

    @State private var viewModel: DocumentViewerViewModel?
    /// [2026-08-15 추가] 사용자 요청 — "pdf 창에 단어 검색기능 + 검색된 단어수 +
    /// 검색이동 기능 추가." `PDFView`(AppKit/UIKit)를 직접 조작해야 하는 검색
    /// 상태라 `PDFKitRepresentable`과 공유하는 별도 컨트롤러로 분리했다 — 아래
    /// `PDFSearchController` 상단 주석 참고. `initialSearchText`가 있으면
    /// `setUpIfNeeded`에서 이 컨트롤러의 검색어로 그대로 채워 넣는다(예전
    /// `PDFSearchCoordinator`의 "1회성 자동 이동"을 이 검색창이 그대로 대신한다
    /// — 검색창에 검색어가 미리 채워진 채로 열려서, 사용자가 곧바로 다음/이전으로
    /// 더 살펴볼 수 있다).
    @State private var pdfSearchController = PDFSearchController()
    /// [2026-08-16 추가] `.docx`(docxide-pdf로 변환된 PDF)용 — 위
    /// `pdfSearchController`(원본 `.pdf` 문서)와 서로 다른 `PDFDocument`를
    /// 검색하므로 공유하면 안 된다(`HWPToPDFPane`이 원본 `.pdf` 탭과 별개
    /// 컨트롤러를 쓰는 것과 같은 이유 — 그 struct 상단 주석 참고).
    @State private var docxSearchController = PDFSearchController()
    /// [2026-08-16 추가] 사용자 요청 — hwp-swift 네이티브 뷰어의 렌더링이 rhwp
    /// 만큼 완전하지 않다는 지적을 받아, rhwp 웹 뷰어(RhwpWebViewerPane.swift)를
    /// "교체"가 아니라 "추가"로 되살렸다. 같은 문서를 두 뷰어로 각각 열어 렌더링
    /// 완전성을 직접 비교해 보고 더 나은 쪽을 고를 수 있게, `.hwp`/`.hwpx` 문서를
    /// 열 때만 이 상태로 두 뷰어를 전환한다(다른 형식엔 영향 없음).
    @State private var hwpViewerMode: HWPViewerMode = .hwpSwiftNative
    /// [2026-08-16 추가] 사용자 지적 — 특정 문서에서 "hwp-swift (네이티브)" 탭만
    /// 파서 한계("Presentation build failed: Bytes are not EOF..." 등)로 못 여는
    /// 사례가 실기기에서 확인됐다. 세 탭 각각이 이 문서를 실제로 열 수 있는지
    /// 로드가 끝나는 대로 보고받아 여기 채운다(`reportViewerAvailability` 참고) —
    /// `nil`(아직 모름)/`true`(열림)/`false`(못 엶). `hwpViewerModeToggle`이 이
    /// 값을 보고 못 여는 탭을 세그먼트에서 아예 숨긴다.
    @State private var viewerAvailability: [HWPViewerMode: Bool] = [:]
    /// [2026-08-16 신설] `.pages` 전용 — 위 `PagesViewerMode` 참고. hwp의
    /// `hwpViewerMode`와 같은 역할, 별개 상태로 둔 이유도 같다(형식마다 독립적인
    /// 선택 상태).
    @State private var pagesViewerMode: PagesViewerMode = .quickLook
    /// [2026-08-16 신설] `.docx` 전용 — 위 `DocxViewerMode` 참고. 초기값은
    /// "미리보기"(추출 텍스트, 크로스플랫폼 항상 가능)로 두고, `docxContent`의
    /// `onAppear`에서 PDF 변환본이 있으면(macOS) "PDF 변환"으로 올려 준다.
    @State private var docxViewerMode: DocxViewerMode = .preview

    /// [2026-08-16 신설] 사용자 요청 — "각 뷰어에 tag를 추가할 수 있도록 하단에
    /// 태그 추가/수정 라인 삽입." `MemoDetailView.tagSection`(Views/Memo/
    /// MemoDetailView.swift)과 완전히 같은 패턴을 문서 쪽 조인 모델(`DocumentTag`,
    /// Tags.swift 2026-08-16 신설)에 맞춰 그대로 옮겼다 — 아래 `documentTagSection`
    /// 참고. 형식(pdf/hwp/doc/docx/image)마다 따로 두지 않고 `mainContent`
    /// 최하단에 한 번만 둔다 — 사용자 문구 "각 뷰어에... 하단에"를 "뷰어가
    /// 무엇으로 바뀌든 화면 맨 아래에 항상 보인다"로 해석했다(포맷별로 4~5번
    /// 중복 구현하는 것보다 한 곳에서 관리하는 편이 실수 여지가 적다).
    @State private var documentTags: [Tag] = []
    @State private var tagInput: String = ""
    @State private var tagSuggestions: [Tag] = []
    @State private var drilldownTag: Tag?

    var body: some View {
        // [2026-08-15 추가, 크래시 fix — DocumentsHomeView.DocumentRowView와 같은
        // 이유] 위 `DocumentViewerWindowContent`/`DocumentSearchWindowContent`를
        // `@Query`로 바꿔 대부분의 경우를 막았지만, 그 wrapper가 매번 이 뷰의
        // body 재계산과 정확히 같은 프레임에 반응한다는 보장까지는 없다 — 한
        // 프레임짜리 경쟁 상태를 완전히 배제할 수 없으므로, 여기서도 같은
        // `modelContext == nil` 사전 검사를 한 번 더 둔다(DocumentRowView.body
        // 상단 주석에 이 API가 왜 안전한지 자세히 적어 뒀다).
        if document.modelContext == nil {
            documentNotFoundMessage()
        } else {
            mainContent
        }
    }

    // ⚠️ 이 프로퍼티를 일부러 `content`가 아니라 `mainContent`로 이름 지었다 —
    // 아래 `private func content(viewModel:)`와 이름이 겹치면 Swift 문법상으로는
    // (프로퍼티 vs 인자 레이블 있는 함수라) 컴파일은 되지만, 읽는 사람이 헷갈리기
    // 쉬워 피했다.
    @ViewBuilder
    private var mainContent: some View {
        // [2026-08-16 수정] 태그 행을 넣기 위해 `Group`을 `VStack(spacing: 0)`으로
        // 바꿨다 — 위 뷰어 콘텐츠(`content(viewModel:)`)는 기존처럼
        // `.frame(maxHeight: .infinity)`로 남은 공간을 다 채우고, `documentTagSection`은
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
        .navigationTitle(document.originalFilename)
        .onAppear(perform: setUpIfNeeded)
        .sheet(item: $drilldownTag) { tag in
            TagDrilldownView(tag: tag)
        }
    }

    // [2026-08-15 수정] 사용자 요청 — "텍스트 탭 삭제." "원본 보기"/"추출 텍스트"를
    // 수동으로 오가던 세그먼트 피커를 없애고, 항상 원본(네이티브 미리보기)을
    // 먼저 보여준다 — "추출 텍스트"는 원본 미리보기 자체가 없는 형식(.doc)이나
    // 검색어를 들고 들어왔는데 PDFKit 검색이 안 되는 형식(비-PDF)일 때만 내부
    // 판단으로 자동 대체된다. 사용자가 직접 탭을 눌러 전환할 방법은 이제 없다.
    private func shouldShowExtractedText(viewModel: DocumentViewerViewModel) -> Bool {
        if !viewModel.supportsNativePreview { return true }
        // [2026-08-11 추가 원칙 유지] 검색어를 갖고 열렸을 때(관련 내용에서 진입)
        // — PDF는 원본 보기(PDFKit 검색+이동)가 그대로 담당하고, PDF가 아니면
        // 원본 탭이 검색을 지원하지 않으므로 추출 텍스트(줄 단위 스크롤+강조)로.
        if let initialSearchText, !initialSearchText.isEmpty, document.originalFormat != .pdf {
            return true
        }
        return false
    }

    @ViewBuilder
    private func content(viewModel: DocumentViewerViewModel) -> some View {
        // [2026-08-16 추가] `.pages`/`.docx`는 위 `shouldShowExtractedText`의
        // "원본 지원 없으면 무조건 추출 텍스트" 이분법을 안 따른다 — 둘 다
        // "원본(또는 변환본)"과 "검색 가능한 추출 텍스트"를 세그먼트로 함께
        // 제공하기로 했으므로, 아예 별도 분기(`pagesContent`/`docxContent`)로
        // 뺀다.
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

    /// [2026-08-16 신설, 같은 날 재수정] 사용자 요청 — "docx는 hwp뷰어처럼,
    /// 상단 탭을 줄것(미리보기, pdf변환)." → "미리보기는 맥 파인더에서
    /// 스페이스바 누르면 보이는 퀵뷰를 말하는 것임." 처음엔 "미리보기"를
    /// `extractedTextPane`(추출 텍스트)로 잘못 구현했었다 — 사용자가 명확히
    /// "Finder 스페이스바 퀵룩"이라고 정정해서, `.pages`의 QuickLook 탭과 같은
    /// `QLPreviewRepresentable`로 바꿨다. 세그먼트: "미리보기"(QuickLook,
    /// 시각적 렌더링만 — 검색 불가) / "PDF 변환"(docxide-pdf로 변환된 PDF,
    /// `.pdf` 원본 탭과 같은 `PDFKitRepresentable`+검색창 — 검색 가능).
    ///
    /// ⚠️ 이 변경으로 "미리보기" 탭에선 더 이상 검색이 안 된다 — QuickLook은
    /// 순수 렌더링 API라 텍스트를 앱에 못 돌려준다는 게 이미 pages 때 확인된
    /// 사실(대화 참고)이라, docx도 같은 제약을 그대로 받는다. 검색은 "PDF
    /// 변환" 탭에서만 가능.
    ///
    /// ⚠️⚠️ [2026-08-16 정정, 사용자 지적] "PDF 변환 탭·검색이 iOS에서 항상
    /// 안 된다"고 처음에 잘못 설명했었다 — 변환 실행(`DocxToPDFConverter`,
    /// Rust FFI)만 macOS 전용이지, 변환 결과물은 iCloud로 동기화되고 그걸
    /// 읽는 `PDFDocument(url:)`/`PDFKitRepresentable`/검색은 전부 플랫폼
    /// 제한이 없다. 그래서 **macOS에서 이미 변환된 문서를 iOS에서 열면 "PDF
    /// 변환" 탭도 보이고 검색도 정상 동작**한다(아래 필터가 참조하는
    /// `viewModel.convertedPDFDocument`는 그 문서가 어느 기기에서
    /// 변환됐는지와 무관하게, "지금 이 기기에서 그 PDF 파일을 읽을 수
    /// 있는지"만 본다 — `DocumentViewerViewModel.swift`의 관련 주석 정정
    /// 참고). 진짜 제약은 "iOS에서 직접 새로 업로드한 docx는 그 세션에서
    /// 변환이 시도조차 안 된다"는 것뿐 — macOS 앱에서 한 번 열어(재시도) 주면
    /// 그 뒤로는 iOS에서도 보인다.
    ///
    /// "PDF 변환" 탭은 변환본이 실제로 있을 때만 보이게 아래 토글에서 걸러낸다
    /// (`viewerAvailability`로 안 열리는 hwp 탭을 숨기는 것과 같은 원칙 —
    /// 다만 docx는 비동기 로드 실패가 아니라 "그 문서가 아직 어느 기기에서도
    /// 변환된 적이 없다"는 훨씬 단순한 조건이라 별도 상태 없이 그냥
    /// `viewModel.convertedPDFDocument`를 직접 확인한다).
    @ViewBuilder
    private func docxContent(viewModel: DocumentViewerViewModel) -> some View {
        VStack(spacing: 0) {
            docxViewerModeToggle(viewModel: viewModel)
            Divider()
            switch docxViewerMode {
            case .preview:
                if let url = viewModel.resolvedURL {
                    QLPreviewRepresentable(url: url)
                } else {
                    unavailableMessage("docx 원본 파일을 열 수 없습니다.")
                }
            case .pdfConverted:
                if let pdf = viewModel.convertedPDFDocument {
                    VStack(spacing: 0) {
                        pdfSearchBar(controller: docxSearchController)
                        Divider()
                        PDFKitRepresentable(document: pdf, searchController: docxSearchController)
                    }
                } else {
                    unavailableMessage("PDF로 변환된 파일이 없습니다.")
                }
            }
        }
        .onAppear {
            // PDF 변환본이 있으면(macOS) 검색까지 되는 "PDF 변환" 탭을
            // 기본값으로 올려 준다 — 없으면(iOS 등) "미리보기"(QuickLook,
            // 초기값)를 그대로 유지. 검색어를 들고 들어온 경우의 실제 검색어
            // 채우기는
            // `setUpIfNeeded`에서 `docxSearchController.query`에 미리 넣어
            // 둔다(원본 `.pdf` 탭이 `pdfSearchController.query`를 채우는 것과
            // 같은 패턴) — 여기서는 그 값이 보이는 탭("PDF 변환")으로만
            // 전환한다.
            if viewModel.convertedPDFDocument != nil {
                docxViewerMode = .pdfConverted
            }
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

    /// [2026-08-16 신설] 사용자 요청 — "pages 뷰어는 QLPreviewController로
    /// 보여지게 하되, 검색기능을 검토할 것." hwp의 `originalPane`
    /// `.hwp, .hwpx` 분기(`hwpViewerModeToggle` + 두 뷰어 ZStack 캐싱)와 같은
    /// 모양으로 만들었다 — 세그먼트로 QuickLook(원본)과 추출 텍스트(검색)를
    /// 오간다.
    @ViewBuilder
    private func pagesContent(viewModel: DocumentViewerViewModel) -> some View {
        VStack(spacing: 0) {
            pagesViewerModeToggle
            Divider()
            switch pagesViewerMode {
            case .quickLook:
                if let url = viewModel.resolvedURL {
                    QLPreviewRepresentable(url: url)
                } else {
                    unavailableMessage("pages 원본 파일을 열 수 없습니다.")
                }
            case .extractedText:
                extractedTextPane(viewModel: viewModel)
            }
        }
        .onAppear {
            // "관련 내용"에서 검색어를 들고 들어왔으면 QuickLook이 아니라 검색이
            // 가능한 텍스트 탭이 곧바로 보여야 자연스럽다 — hwp/PDF의
            // `shouldShowExtractedText` 원칙(2026-08-11)과 같은 이유.
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

    @ViewBuilder
    private func originalPane(viewModel: DocumentViewerViewModel) -> some View {
        switch document.originalFormat {
        case .pdf:
            // [2026-08-15 수정, 깜박임 fix] 매 재계산마다 `PDFDocument(url:)`를
            // 새로 만들지 않고, `viewModel.onAppear()`에서 한 번만 읽어 캐싱해 둔
            // 안정적인 인스턴스를 그대로 쓴다 — `DocumentViewerViewModel.
            // pdfDocument` 상단 주석 참고.
            if let pdf = viewModel.pdfDocument {
                VStack(spacing: 0) {
                    pdfSearchBar
                    Divider()
                    PDFKitRepresentable(document: pdf, searchController: pdfSearchController)
                }
            } else {
                unavailableMessage("PDF를 열 수 없습니다.")
            }
        case .image:
            if let url = viewModel.resolvedURL, let image = PlatformImage(contentsOfFile: url.path) {
                #if os(macOS)
                ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
                #else
                ScrollView([.horizontal, .vertical]) { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) }
                #endif
            } else {
                unavailableMessage("이미지를 열 수 없습니다.")
            }
        case .hwp, .hwpx:
            if let hwpFileData = viewModel.hwpFileData {
                VStack(spacing: 0) {
                    hwpViewerModeToggle
                    Divider()
                    // [2026-08-16 수정] 사용자 지적 — "탭을 바꿀때마다 파일을
                    // 읽는 것 같음... 탭을 바꿔도 바로바로 전환되는 것이
                    // 가능해보임." 원래는 `switch`로 셋 중 하나만 뷰 계층에
                    // 존재했다 — SwiftUI는 `switch`/`if`로 조건부로 나타나는
                    // 뷰를 다른 케이스로 바뀔 때 완전히 파괴하고 새로 만든다,
                    // 그래서 각 Pane의 `@State`(파싱된 문서, WKWebView 등)가
                    // 매번 사라지고 `.task(id:)`가 처음부터 다시 실행됐다 —
                    // 이게 "탭 바꿀 때마다 다시 읽는" 것처럼 보인 이유다.
                    //
                    // 셋 다 항상 뷰 계층에 남겨 두고(`ZStack`) 안 보이는 것만
                    // `opacity(0)` + `allowsHitTesting(false)`로 숨기면, 뷰
                    // 정체성이 안 바뀌어 `@State`가 그대로 유지된다 — 각 Pane은
                    // 이미 `.task(id: documentData)`라 `documentData`가 안
                    // 바뀌는 한(같은 문서를 계속 보는 한) 딱 한 번만 로드하고,
                    // 그 다음부터 탭 전환은 단순히 보이기/숨기기라 즉시
                    // 전환된다.
                    ZStack {
                        HWPViewerPane(
                            documentData: hwpFileData,
                            onAvailabilityChange: { reportViewerAvailability($0, for: .hwpSwiftNative) }
                        )
                            .opacity(hwpViewerMode == .hwpSwiftNative ? 1 : 0)
                            .allowsHitTesting(hwpViewerMode == .hwpSwiftNative)
                            .accessibilityHidden(hwpViewerMode != .hwpSwiftNative)
                        RhwpWebViewerPane(
                            documentData: hwpFileData,
                            onAvailabilityChange: { reportViewerAvailability($0, for: .rhwpWeb) }
                        )
                            .opacity(hwpViewerMode == .rhwpWeb ? 1 : 0)
                            .allowsHitTesting(hwpViewerMode == .rhwpWeb)
                            .accessibilityHidden(hwpViewerMode != .rhwpWeb)
                        HWPToPDFPane(
                            documentData: hwpFileData,
                            preConvertedDocument: viewModel.convertedPDFDocument,
                            additionalSearchTerms: verseSearchLiteralTerms(for:),
                            onAvailabilityChange: { reportViewerAvailability($0, for: .pdfConverted) }
                        )
                            .opacity(hwpViewerMode == .pdfConverted ? 1 : 0)
                            .allowsHitTesting(hwpViewerMode == .pdfConverted)
                            .accessibilityHidden(hwpViewerMode != .pdfConverted)
                    }
                }
            } else {
                unavailableMessage("hwp 원본 파일을 열 수 없습니다.")
            }
        case .doc, .docx, .pages:
            // [2026-08-15 참고, 2026-08-16 docx/pages 재분리] `.doc`는
            // `supportsNativePreview == false`라 `shouldShowExtractedText`가
            // 항상 true를 돌려줘 이 분기가 실제로는 그려지지 않는다(스위치
            // 전체 케이스를 다뤄야 하는 Swift 문법상 남겨둔 자리). `.docx`/
            // `.pages`도 이 스위치엔 여전히 있어야 하지만(exhaustive 요구),
            // 실제로는 `content(viewModel:)`이 이 둘을 `originalPane` 자체에
            // 도달하기 전에 각각 `docxContent`(미리보기 ↔ PDF 변환 세그먼트)/
            // `pagesContent`(QuickLook ↔ 추출 텍스트 세그먼트)로 먼저
            // 가로채므로 이 케이스들도 마찬가지로 그려지지 않는다.
            unavailableMessage("이 형식은 원본 미리보기를 지원하지 않습니다. 추출된 텍스트를 대신 보여드립니다.")
        }
    }

    // MARK: - hwp 뷰어 전환(네이티브 hwp-swift ↔ rhwp 웹 뷰어)

    /// [2026-08-16 추가] `.hwp`/`.hwpx` 문서를 열 때만 보이는 세그먼트 컨트롤.
    /// hwp-swift(HWPViewerPane, 순수 네이티브)와 rhwp(RhwpWebViewerPane,
    /// WKWebView + WASM) 중 하나를 골라 같은 문서를 열어 렌더링을 비교해 볼 수
    /// 있다 — RhwpWebViewerPane.swift 상단 주석 참고.
    ///
    /// [2026-08-16 수정] 사용자 지적 — 특정 문서가 hwp-swift 파서 한계로 "네이티브"
    /// 탭에서만 안 열리는 사례가 실기기에서 확인됐다("hwp 문서를 열지 못했습니다.
    /// Presentation build failed: Bytes are not EOF..." — hwp-swift 저장소를
    /// 직접 조사해 보니 `HwpIdMappings.swift`가 문서 버전에 따라 필드 개수를
    /// 다르게 읽는데, 이 문서는 그 버전 경계에서 어긋나는 것으로 보인다. 현재
    /// hwp-swift에 이 케이스에 대한 알려진 수정은 없다). `viewerAvailability`가
    /// `false`로 확정한 탭은 세그먼트에서 아예 숨긴다 — 안 열리는 탭을 굳이
    /// 보여주고 에러 화면을 또 띄우기보다, 되는 탭만 고를 수 있게 한다.
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
        guard !isAvailable, hwpViewerMode == mode else { return }
        if let fallback = HWPViewerMode.allCases.first(where: { viewerAvailability[$0] == true }) {
            hwpViewerMode = fallback
        }
    }

    // MARK: - PDF 검색 바(단어 검색 + 일치 개수 + 다음/이전 이동)

    /// [2026-08-15 신설] `OutlineQuickViewWindowContent.header`의 검색창과 같은
    /// 모양(돋보기 아이콘 + 검색어 입력 + "N/M" 일치 개수 + 다음/이전 버튼)으로
    /// 통일했다. `@Observable` 컨트롤러의 `query`에 양방향으로 쓰려면 `@Bindable`
    /// 로컬 바인딩이 필요하다 — SwiftUI가 공식적으로 지원하는 패턴(`@Bindable var
    /// x = x`로 `@State` 참조 타입을 셰도잉해 `$x.프로퍼티` 바인딩을 얻는다).
    private var pdfSearchBar: some View {
        pdfSearchBar(controller: pdfSearchController)
    }

    /// [2026-08-16 리팩터] 사용자 요청 — "docxide-pdf + PDFKit로 docx를 pdf로
    /// 변환하는 것을 검토할 것" → "진행할 것." 원래 `pdfSearchController` 하나에
    /// 고정돼 있던 걸 파라미터로 뺐다 — `.docx`가 원본(`.pdf`)과는 다른
    /// `PDFDocument`(변환된 결과물)를 검색해야 해서 별도 컨트롤러 인스턴스가
    /// 필요하기 때문(아래 `docxSearchController` 참고, `HWPToPDFPane`이 원본
    /// `.pdf` 탭과 별개 컨트롤러를 쓰는 것과 같은 이유). 위 `pdfSearchBar`는
    /// 기존 호출부(`.pdf` 케이스)가 그대로 쓸 수 있게 남겨 둔 얇은 래퍼.
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
                }
                .buttonStyle(.plain)
                .disabled(controller.matches.isEmpty)
                .help("이전 일치 항목")

                Button {
                    controller.goToNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(controller.matches.isEmpty)
                .help("다음 일치 항목")
            }
        }
        .padding(8)
    }

    // MARK: - 추출 텍스트(선택 가능한 순수 텍스트 + 검색)

    /// [2026-08-16 추가] 사용자 요청 — "미리보기에 검색기능 추가할 것." PDF가
    /// 아닌 형식(hwp/doc/docx/pages/이미지 OCR)의 "추출 텍스트" 화면엔 지금까지
    /// `initialSearchText`(관련 내용에서 넘어온 1회성 자동 이동)만 있었고,
    /// 사용자가 직접 입력해 찾는 검색창은 없었다. `pdfSearchBar`/
    /// `PDFSearchController`(원본 `.pdf` 탭)와 같은 모양(돋보기+검색어+N/M+
    /// 다음/이전)으로 통일했지만, PDFKit 대신 이미 메모리에 있는
    /// `viewModel.textLines`(줄 단위 배열)를 그냥 필터링하면 되므로 별도
    /// `@Observable` 컨트롤러 없이 이 뷰의 `@State` 두 개로 충분하다.
    @State private var extractedTextSearchQuery: String = ""
    @State private var extractedTextCurrentMatchIndex: Int = 0

    /// [2026-08-18 추가] 사용자 요청 — "모든 뷰어창 검색기능에 연구문서 검색과
    /// 동일하게 성경 장절을 검색할 수 있도록 할 것" — 4가지 조건(띄어쓰기 무시,
    /// 약어↔전체이름 상호 검색, 범위 포함 검색) 전부 `DocumentsHomeView.
    /// matchesVerseReference`가 이미 구현한 것과 완전히 같은 원리로 푼다 —
    /// 검색어를 `BibleReferenceExtractor`로 파싱해 (책ID, 장, 절) 좌표로
    /// 정규화하면, 그 파서 자체가 이미 띄어쓰기/약어/전체이름을 다 흡수한다
    /// (DocumentsHomeView.swift의 `matchesVerseReference` 상단 주석 참고).
    ///
    /// 이 문서에 이미 색인된 `VerseMention`(`BibleReferenceIndexingService`가
    /// 문서 저장 직후 만들어 둠) 중 그 좌표와 겹치는 것들의 `searchText`(문서
    /// 원문에 실제로 적힌 표현 그대로, 예: "창1:1~5")를 돌려준다 — 이
    /// 리터럴 문자열들을 아래 `extractedTextMatches`(줄 단위 `contains`)와
    /// `PDFSearchController.performSearch`(PDFKit `findString`) 양쪽에 "추가
    /// 검색어"로 먹이면, 사용자가 "창세기 1:3"이라고 입력해도 문서에 적힌
    /// "창1:1~5" 같은 다른 표현을 실제로 찾아 강조할 수 있다. 범위 포함
    /// 검색도 같은 방식으로 저절로 된다 — `BibleReferenceIndexingService.
    /// reindexDocument`가 이미 범위를 절 단위로 펼쳐 색인해 뒀으므로("창1:1~5"
    /// → 1,2,3,4,5절 각각의 `VerseMention`), 검색어가 그 범위 안의 절 하나만
    /// 가리켜도 좌표가 겹친다.
    private func verseSearchLiteralTerms(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let queryMatches = BibleReferenceExtractor.extract(from: trimmed)
        guard !queryMatches.isEmpty else { return [] }

        let docId = document.id.uuidString
        // `VerseMention.sourceId`는 평범한 String 저장 프로퍼티라 #Predicate
        // 등호 비교가 안전하다(`sourceType`처럼 enum rawValue인 경우만 이
        // 프로젝트가 회피해 온 패턴 — BibleReferenceIndexingService.
        // removeMentions 상단 주석 참고). `sourceType`은 여기서 Swift 쪽에서
        // 한 번 더 확인한다.
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
                            && (query.verse == nil || mention.verse == nil || query.verse == mention.verse)
                    }
            }
            .map(\.searchText)
            // 범위 표현("창1:1~5")은 절 개수만큼 VerseMention으로 펼쳐져 있어
            // 같은 searchText가 여러 번 나올 수 있다 — 중복 제거.
            .filter { seen.insert($0).inserted }
    }

    /// 검색어와 일치하는 줄들의 id 목록 — 검색어가 비어 있으면 빈 배열(검색
    /// 바가 "N/M"을 안 보여줌). [2026-08-18 확장] 리터럴 부분 문자열 일치에
    /// 더해, 성경 장절 참조로 해석되는 검색어(`verseSearchLiteralTerms`)와
    /// 겹치는 줄도 함께 찾는다.
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

    /// [2026-08-11 신설] 사용자 요청 — "[관련 내용]에서 문서를 고르면 그 성경구절
    /// 표현이 있는 위치로 바로 이동." + [2026-08-16 검색기능과 통합] 이전엔
    /// `initialSearchText`가 있을 때만 줄 단위로 쪼개 스크롤+강조했고, 없으면
    /// 그냥 전체를 이어붙인 `Text` 하나였다(검색 이동이 아예 불가능한 모양).
    /// 이제 검색창이 생겼으니 두 경로를 하나로 합친다 — 강조 대상은
    /// "검색창에 입력 중이면 현재 검색 일치 줄, 아니면(빈 검색어) 관련 내용에서
    /// 넘어온 1회성 매치 줄".
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
                }
                .buttonStyle(.plain)
                .disabled(matches.isEmpty)
                .help("이전 일치 항목")

                Button {
                    goToNextExtractedTextMatch(viewModel: viewModel)
                } label: {
                    Image(systemName: "chevron.down")
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
        // 검색창이 비어 있을 때는(검색 안 하는 중) 기존처럼 "관련 내용"에서 넘어온
        // 1회성 자동 이동 매치를 강조 대상으로 쓴다.
        let fallbackMatchID: UUID? = {
            guard currentMatchID == nil, let initialSearchText, !initialSearchText.isEmpty else { return nil }
            return viewModel.textLines.first {
                $0.lineText.localizedCaseInsensitiveContains(initialSearchText)
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

    private func setUpIfNeeded() {
        guard viewModel == nil else { return }
        let vm = DocumentViewerViewModel(document: document, modelContext: modelContext)
        vm.onAppear()
        viewModel = vm
        // [2026-08-18 추가] 사용자 요청 — "모든 뷰어창 검색기능에 연구문서
        // 검색과 동일하게 성경 장절을 검색할 수 있도록 할 것." 이 창에서 쓰는
        // PDFKit 기반 검색 컨트롤러 둘 다(`.pdf` 원본, `.docx` PDF 변환) 같은
        // 문서(`document`)를 대상으로 하므로 같은 리졸버를 그대로 연결한다 —
        // `HWPToPDFPane`(별도 struct, `document`에 직접 접근 못 함)의
        // 내부 컨트롤러는 `originalPane`에서 이 함수를 파라미터로 넘겨 연결한다.
        pdfSearchController.additionalSearchTerms = verseSearchLiteralTerms(for:)
        docxSearchController.additionalSearchTerms = verseSearchLiteralTerms(for:)
        // 옛 `PDFSearchCoordinator`의 "1회성 자동 이동"을 새 검색창이 대신한다 —
        // 위 `pdfSearchController` 프로퍼티 주석 참고.
        if let initialSearchText, document.originalFormat == .pdf {
            pdfSearchController.query = initialSearchText
        }
        // [2026-08-16 추가] 위와 같은 이유, `.docx`용 — `docxContent`의
        // "PDF 변환" 탭(macOS, 변환본 있을 때만)에서만 실제 검색이 가능하므로
        // `vm.onAppear()`가 이미 채워 둔 `convertedPDFDocument`를 확인한 뒤에만
        // 채운다.
        if let initialSearchText, document.originalFormat == .docx, vm.convertedPDFDocument != nil {
            docxSearchController.query = initialSearchText
        }
        documentTags = (document.documentTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
    }

    // MARK: - 태그 (MemoDetailView.tagSection과 같은 패턴, DocumentTag 조인 사용)

    private var documentTagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // [2026-08-16 수정] 사용자 요청 — "'태그' 타이틀 일반사이즈로. 입력된
            // 태그는 '태그' 타이틀 하단이 아니라 우측 옆으로 추가되게 할 것."
            // 이전엔 `.caption` 크기 라벨을 위 줄에 혼자 두고, 그 아래 줄에
            // `FlowLayoutHStack`(태그 칩들)을 별도로 배치했다 — 이제 라벨과 칩을
            // 같은 `HStack`에 넣어 라벨 오른쪽에 칩이 붙게 한다. 칩이 많아 줄바꿈
            // 되더라도 라벨이 아래로 같이 밀리지 않도록 `alignment: .top`.
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
                        .background(Color.accentColor.opacity(0.15))
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
    /// [2026-08-15 변경] 예전엔 이 뷰가 자체 `PDFSearchCoordinator`로 "1회성
    /// 검색+이동"만 했다 — 이제 `DocumentViewerView.pdfSearchController`
    /// (양방향 검색창)가 검색 전체를 담당하므로, 이 표현형(representable)의
    /// 유일한 역할은 실제로 만들어진 `PDFView`를 그 컨트롤러에 연결해 주는
    /// 것뿐이다(컨트롤러가 이후 검색/이동을 직접 그 `PDFView`에 명령한다).
    let searchController: PDFSearchController

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        searchController.pdfView = view
        return view
    }
    func updateNSView(_ nsView: PDFView, context: Context) {
        // [2026-08-15 추가, 깜박임 fix] `document`가 캐싱된 뒤에도(위 originalPane
        // 수정 참고) SwiftUI는 이 뷰가 재계산될 때마다 `updateNSView`를 부를 수
        // 있다 — 매번 무조건 `.document`에 대입하면 같은 내용이라도 `PDFView`가
        // 다시 그리며 스크롤/확대 위치가 흔들릴 수 있어, 참조가 실제로 바뀐
        // 경우에만(`!==`, 클래스 타입 동일성) 대입한다.
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

/// [2026-08-15 신설] 사용자 요청 — "pdf 창에 단어 검색기능 + 검색된 단어수 +
/// 검색이동 기능 추가." `PDFView`(AppKit/UIKit `NSViewRepresentable`/
/// `UIViewRepresentable` 안쪽에 있는 실제 뷰)를 SwiftUI 검색창에서 직접
/// 조작해야 해서, `updateNSView`의 선언적 diff 타이밍에 기대는 대신(이전
/// `PDFSearchCoordinator`가 쓰던 방식 — 검색어 하나가 바뀔 때만 반응하는 "1회성"
/// 용도에는 맞았지만, "다음/이전" 같은 매번 다른 동작을 표현하기 어렵다) 이
/// 컨트롤러가 `PDFView`에 대한 참조를 직접 들고 있다가 검색창의 버튼/타이핑에
/// 바로 명령을 내리는 명령형(imperative) 패턴을 썼다 — AppKit/UIKit 상호운용에서
/// 흔히 쓰는 방식이다.
@MainActor
@Observable
final class PDFSearchController {
    /// `PDFKitRepresentable.makeNSView`/`updateNSView`가 실제 `PDFView`가
    /// 만들어지는 대로 연결해 준다. `PDFView`는 이미 SwiftUI 뷰 계층(그 안의
    /// `NSViewRepresentable`)이 소유하고 있으므로, 이 컨트롤러 쪽에서는 강한
    /// 참조를 잡을 필요가 없어 `weak`로 둔다(순환 참조 방지).
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

    /// [2026-08-18 추가] 사용자 요청 — "모든 뷰어창 검색기능에 연구문서 검색과
    /// 동일하게 성경 장절을 검색할 수 있도록 할 것." `PDFDocument.findString`은
    /// 리터럴 부분 문자열만 찾으므로, 타이핑된 검색어가 성경 참조("창세기
    /// 1:3")면 문서에 실제로 적힌 다른 표현("창1:1~5")을 그대로 못 찾는다.
    /// `DocumentViewerView`가 이 클로저에 `verseSearchLiteralTerms(for:)`를
    /// 연결해 두면, `performSearch()`가 타이핑된 검색어 그대로에 더해 이
    /// 클로저가 돌려주는 리터럴 표현들도 함께 찾아 하나의 결과로 합친다 —
    /// 이 컨트롤러 자체는 "누가 이 결과를 채워 주는지" 몰라도 되게 의존성을
    /// 역전시켰다(`PDFSearchController`는 `SourceDocument`/`VerseMention`을
    /// 전혀 몰라도 된다 — 이 파일 최상단이 SwiftData 모델을 import하는 이유가
    /// 이 컨트롤러 때문이 되지 않게 하려는 의도).
    var additionalSearchTerms: (String) -> [String] = { _ in [] }

    var matchCountText: String {
        matches.isEmpty ? "0/0" : "\(currentIndex + 1)/\(matches.count)"
    }

    /// ⚠️ [알려진 한계] `PDFDocument.findString`은 문서 전체를 동기적으로 훑는다
    /// — 타이핑할 때마다 즉시 다시 검색하므로, 아주 긴 PDF(수백 페이지)에서는
    /// 검색창 반응이 잠깐 끊길 수 있다. 이번 요청 범위(단어 검색+개수+이동)엔
    /// 없던 요구라 디바운스/비동기화는 넣지 않았다 — 실제로 느리게 느껴지면
    /// 다음 라운드에서 추가하면 된다. [2026-08-18 추가] 이제 검색어 하나당
    /// `findString` 호출이 여러 번(타이핑된 검색어 + 성경 참조로 풀린 리터럴
    /// 표현마다 한 번씩) 일어날 수 있어 이 비용이 조금 더 커졌다 — 리터럴
    /// 표현 개수는 보통 한 자릿수라 실사용에서 체감될 정도는 아닐 것으로
    /// 본다.
    func performSearch() {
        currentIndex = 0
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pdfView, let document = pdfView.document, !trimmed.isEmpty else {
            matches = []
            return
        }
        var terms = [trimmed]
        terms.append(contentsOf: additionalSearchTerms(trimmed))
        var seenTerms = Set<String>()
        let uniqueTerms = terms.filter { seenTerms.insert($0.lowercased()).inserted }

        let found = uniqueTerms.flatMap { document.findString($0, withOptions: .caseInsensitive) }
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

/// `.hwp`/`.hwpx` 문서를 열 때 고를 수 있는 뷰어들. `HWPViewerPane`(hwp-swift
/// 네이티브)과 `RhwpWebViewerPane`(rhwp WKWebView 웹 뷰어, 별도 파일
/// RhwpWebViewerPane.swift)이 같은 `Data`를 받아 각자 렌더링한다.
///
/// [2026-08-16 정리] rhwp 웹 뷰어가 계속 실패하던 문제를 진단용 임시 탭
/// 3단계(단순 WKWebView → 커스텀 스킴 핸들러만 → rhwp.js import/wasm init
/// 단독 실행)로 근본 원인 두 가지를 확정하고 고쳤다 — (1) `HWPViewerSchemeHandler`
/// 가 wasm 응답에 진짜 HTTP `Content-Type` 헤더를 안 채워서
/// `WebAssembly.instantiateStreaming`이 실패하던 것(수정: `HTTPURLResponse
/// (headerFields:)`), (2) `didFinish`가 `hwp_viewer.js` 모듈 실행 완료보다
/// 먼저 와서 `window.rhwpLoadDocument`가 아직 정의 전이던 레이스 컨디션(수정:
/// JS가 명시적으로 보내는 `hwpViewerReady` 신호를 기다리도록 변경) — 자세한
/// 내용은 RhwpWebViewerPane.swift 상단 주석 참고. 진단용 탭/리소스는 문제
/// 해결 확인 후 모두 제거했다.
/// [2026-08-16 추가] 사용자 요청 — "rhwp 엔진중에 pdf 변환기능이 있던지
/// 확인해서 업로드할 때 pdf 변환해서 보여주는 것을 네이티브, 웹, pdf 별도
/// 탭에 구현할 것." 조사 결과(HWPToPDFPane 상단 주석에 자세히 정리) rhwp.js
/// (WASM)엔 PDF 관련 기능이 전혀 없었다 — 처음엔 hwp-swift(HwpKit) 쪽
/// `HwpKitNative.HwpPDFRenderer`(WebView 없는 순수 CoreGraphics 렌더러)로
/// 세 번째 탭을 구현했다.
///
/// [2026-08-16 PDF 탭 재구현] 그 첫 버전을 사용자가 거부했다 — 네이티브 탭
/// (`HWPViewerPane`)과 똑같은 `HwpDocument` paint list를 그대로 PDF로 뽑을
/// 뿐이라 렌더링 결과가 사실상 같아서 "존재 이유가 없음." 대신 참고로 든
/// https://github.com/postmelee/alhangeul-macos 가 실제로 쓰는 방식(rhwp
/// 자체 PDF 기능이 아니라 `renderPageSvg` → 오프스크린 WKWebView →
/// `WKWebView.createPDF`)을 "WKWebView 취약점 범주가 그대로 재발할 수 있는
/// 접근이라 해도 한번 구현테스트를 확인할 수 있도록" 해 달라는 명시적 요청을
/// 받아 `RhwpPDFExportService`로 새로 구현했다 — 자세한 내용은
/// `RhwpPDFExportService.swift`와 `HWPToPDFPane` 상단 주석 참고.
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

/// [2026-08-16 신설] 사용자 요청 — "pages 뷰어는 QLPreviewController로 보여지게
/// 하되, 검색기능을 검토할 것." 검토 결과 — QuickLook은 순수 렌더링 API라
/// 텍스트를 앱으로 못 돌려주므로 그 안에서 검색을 구현할 수 없다(대화에서 이미
/// 확인). 그래서 `.hwp`/`.hwpx`의 `HWPViewerMode`(네이티브 ↔ 웹)와 같은 방식으로
/// "원본(QuickLook, 시각적으로 정확·검색 불가)"과 "텍스트(SwiftTextPages로 추출,
/// 검색 가능)"를 세그먼트로 오가게 한다 — 한쪽에 다 몰아넣지 않고 사용자가
/// 목적에 맞게 고르게 했다.
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

/// [2026-08-16 신설] 사용자 요청 — "docx는 hwp뷰어처럼, 상단 탭을 줄것(미리보기,
/// pdf변환)." hwp의 `HWPViewerMode`/pages의 `PagesViewerMode`와 같은 패턴 —
/// 자동으로 하나를 골라 보여주는 대신, 사용자가 세그먼트로 직접 오갈 수 있게
/// 한다. "PDF 변환" 탭 이름은 `HWPViewerMode.pdfConverted`의 라벨과 그대로
/// 맞췄다(같은 개념 — 업로드 시 미리 변환해 둔 PDF).
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

/// 페이지(원본 보기)에서 문서 바이트가 준비돼 있을 때 그리는 실제 뷰어 화면.
/// `HwpKit`의 네이티브 SwiftUI 컴포넌트(`HwpDocumentView`/`HwpSearchController`/
/// `HwpSearchBar`)를 그대로 쓴다 — hwp-swift 저장소의
/// `Sample/HwpSwiftSample/ContentView.swift` 실제 배선 예시를 그대로 따랐다.
/// WKWebView/WASM이 없어 `pdfSearchBar` + `PDFKitRepresentable` 쌍과 마찬가지로
/// 순수 SwiftUI/네이티브 뷰 조합이다.
///
/// [2026-08-16 수정] 사용자 요청으로 상단 툴바를 pdf 뷰어(`pdfSearchBar`)와 같은
/// 모양으로 통일했다 — 이제 `HwpDocumentToolbar`/`HwpPageNavigator`/
/// `HwpZoomControls`(HwpKit이 기본 제공하는 페이지 이동 버튼 툴바)는 쓰지 않고,
/// 검색창 + 자체 구현한 돋보기 아이콘 버튼 3개(`searchAndZoomBar`)로 대신한다.
private struct HWPViewerPane: View {
    let documentData: Data
    /// [2026-08-16 추가] `hwpViewerModeToggle` 상단 주석 참고 — 로드 성공/실패를
    /// 상위(`DocumentViewerView.reportViewerAvailability`)에 보고한다.
    var onAvailabilityChange: ((Bool) -> Void)? = nil
    @State private var document: HwpDocument?
    @State private var errorMessage: String?
    @State private var currentPage: Int = 1
    @State private var zoomScale: CGFloat = 1.0
    /// 문서 내 검색 세션 — `HwpDocumentView(searchController:)`와
    /// `HwpSearchBar(controller:)`에 같은 인스턴스를 넘기면 하이라이트·매치
    /// 이동이 라이브러리 안에서 자동으로 배선된다(hwp-swift Sample README 참고).
    @State private var search = HwpSearchController()
    @FocusState private var searchFieldFocused: Bool

    /// [2026-08-16 추가] `pdfSearchBar`/`OutlineQuickViewWindowContent.header`와
    /// 같은 줌 범위 — 앱 전체에서 "돋보기 아이콘 3개(확대/축소/원본크기)" 패턴을
    /// 통일하기 위해 값도 그대로 맞췄다.
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
        // `.task(id:)`로 documentData가 바뀌면(다른 문서를 같은 뷰에서 다시
        // 열게 되는 경우) 재로딩한다 — 값 비교이므로 같은 파일 재진입은
        // 다시 파싱하지 않는다.
        .task(id: documentData) {
            await load()
        }
    }

    /// [2026-08-16 교체] 사용자 요청 — "hwp 뷰어를 pdf뷰어와 UI를 비슷하게 맞출것
    /// (page 이동버튼 삭제, 검색기능 옆에 줌기능 버튼 세개(개요처럼))." 예전엔
    /// `HwpDocumentToolbar { HwpPageNavigator; Spacer; HwpZoomControls }` +
    /// 별도 줄의 `HwpSearchBar` 두 줄이었다 — `HwpPageNavigator`(페이지 이동
    /// 버튼)를 없애고, `pdfSearchBar`/`OutlineQuickViewWindowContent.header`와
    /// 똑같은 모양(검색창 + 돋보기 아이콘 버튼 3개)으로 한 줄에 합쳤다. 페이지
    /// 이동은 `HwpDocumentView`의 자체 스크롤/제스처로 대신한다(PDFKitRepresentable도
    /// 마찬가지로 별도 페이지 버튼 없이 스크롤로만 넘긴다).
    private var searchAndZoomBar: some View {
        HStack(spacing: 8) {
            HwpSearchBar(controller: search, isFocused: $searchFieldFocused)

            Spacer(minLength: 8)

            Button {
                zoomScale = min(Self.maxZoom, zoomScale + Self.zoomStep)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("확대")

            Button {
                zoomScale = max(Self.minZoom, zoomScale - Self.zoomStep)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("축소")

            Button {
                zoomScale = 1.0
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.plain)
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
        } catch {
            errorMessage = "\(error)"
            onAvailabilityChange?(false)
        }
    }
}

// MARK: - hwp → PDF 변환 탭(2026-08-16 신설, 위 HWPViewerMode 주석 참고)

/// [2026-08-16 신설] 사용자 요청 — "rhwp 엔진중에 pdf 변환기능이 있던지
/// 확인해서... pdf 별도 탭에 구현할 것." 조사 경과:
///
/// 1) 번들된 `Resources/rhwp.js`(WASM) 전체(HwpDocument 메서드 약 300개 +
/// `DocumentExport` 결과 컨테이너)를 다 뒤져도 "pdf"라는 문자열 자체가 단 한
/// 군데도 없다 — `exportHwp`/`exportHwpx`/`exportHml` 계열은 전부 HWP/HWPX/
/// HML 포맷 내보내기지 PDF가 아니다. edwardkim/rhwp 상류 README의 로드맵도
/// "다양한 출력 포맷(PDF, DOCX 등)"을 아직 시작 안 한 v2.0.0 항목으로 못박아
/// 둬서(현재 배포 버전은 v0.7.15), 이 엔진 자체엔 PDF 변환 기능이 없다는 게
/// 번들/상류 양쪽에서 다 확인된다.
///
/// 2) [2026-08-16 첫 버전, 이후 교체됨] 참고로 든
/// https://github.com/postmelee/alhangeul-macos 를 실제로 조사해 보니
/// (`Sources/HostApp/Services/RhwpStudioPagePDFRenderer.swift`/
/// `RhwpStudioPDFExportController.swift`, MIT), 그 앱의 PDF 내보내기는
/// rhwp-studio가 페이지별 SVG를 만들면 → 그 SVG를 오프스크린 `WKWebView`로
/// 다시 열어 → `WKWebView.createPDF(configuration:)`로 한 쪽씩 PDF로 변환한
/// 뒤 → PDFKit으로 이어붙이는 방식이었다. 처음엔 이번 세션 내내 겪은
/// WKWebView 취약점 범주(App Sandbox/커스텀 스킴/타이밍)가 그대로 재발할 수
/// 있다는 우려로 이 방식 대신 hwp-swift(HwpKit)의 `HwpKitNative.
/// HwpPDFRenderer`(WebView 없는 순수 CoreGraphics 렌더러)를 채택했었다.
///
/// 3) [2026-08-16 재구현] 그런데 그 첫 버전은 `HWPViewerPane`(네이티브 탭)과
/// 정확히 같은 `HwpDocument` paint list를 그대로 PDF로 뽑는 것뿐이라
/// 렌더링이 사실상 동일했고, 사용자가 "네이티브 뷰어와 동일하므로 존재
/// 이유가 없음"이라고 명확히 지적했다. 그리고 "WKWebView 취약점 범주가
/// 그대로 재발할 수 있는 접근이라 해도 한번 구현테스트를 확인할 수 있도록"
/// 위 2)의 alhangeul-macos 방식을 실제로 구현해 보라는 명시적 요청을 받아,
/// `RhwpPDFExportService`(Services/Documents/RhwpPDFExportService.swift)로
/// 다시 만들었다 — rhwp.js의 `renderPageSvg(page_num)` → 이 프로젝트가 이미
/// 검증한 `hwpviewer://` 스킴/준비-신호 인프라를 재사용하는 오프스크린
/// `WKWebView` → `WKWebView.createPDF` → PDFKit 이어붙이기. 이제 렌더링
/// 파이프라인이 네이티브 탭과 완전히 달라(hwp-swift paint list가 아니라
/// rhwp WASM의 SVG 렌더러) 별도 탭으로서 존재 이유가 생긴다. ⚠️ 알려진
/// 위험은 `RhwpPDFExportService.swift` 상단 주석 참고 — 실기기 테스트 필요.
///
/// 4) [2026-08-16 사전 변환 연동] 사용자 지적 — "탭을 바꿀때마다 파일을 읽는
/// 것 같음"과 "hwp 업로드할 때 pdf를 생성하고 pdf 파일을 열수 있도록"이 같은
/// 라운드에 함께 들어와서, 이 탭이 열릴 때마다(또는 문서를 새로 열 때마다)
/// `RhwpPDFExportService`로 즉석 변환하던 걸 업로드 시점에 딱 한 번만 변환해
/// 두는 쪽으로 옮겼다 — `DocumentUploadService.generateConvertedPDF`가
/// 만들어 둔 파일을 `preConvertedDocument`로 받으면 그걸 그대로 보여주고,
/// 없으면(이 기능 이전에 업로드된 "기존 데이터") 예전처럼 이 탭을 열 때
/// 즉석 변환하는 경로로 자동 대체된다 — "기존 데이터는 변환하지 않아도 됨."
private struct HWPToPDFPane: View {
    let documentData: Data
    /// `DocumentViewerViewModel.convertedPDFDocument` — 업로드 시 미리 변환해
    /// 둔 결과가 있으면 이 값이 채워져 있다(위 4) 참고).
    let preConvertedDocument: PDFDocument?
    /// [2026-08-18 추가] 사용자 요청 — "모든 뷰어창 검색기능에 연구문서 검색과
    /// 동일하게 성경 장절을 검색할 수 있도록 할 것." 이 struct는 `document:
    /// SourceDocument`에 직접 접근하지 못해(`documentData: Data`만 받음)
    /// `DocumentViewerView.verseSearchLiteralTerms(for:)`를 부모가 클로저로
    /// 대신 넘겨준다 — `DocumentViewerView.originalPane`의 `.hwp, .hwpx`
    /// 케이스에서 이 값을 채워 전달한다.
    var additionalSearchTerms: (String) -> [String] = { _ in [] }
    /// [2026-08-16 추가] `HWPViewerPane.onAvailabilityChange`와 같은 목적 —
    /// `hwpViewerModeToggle` 상단 주석 참고.
    var onAvailabilityChange: ((Bool) -> Void)? = nil
    @State private var pdfDocument: PDFDocument?
    @State private var errorMessage: String?
    @State private var conversionProgress: (pageIndex: Int, pageCount: Int)?
    @State private var exportService = RhwpPDFExportService()
    /// 원본 `.pdf` 문서 탭(`DocumentViewerView.pdfSearchController`)과는 별개의
    /// 인스턴스 — 이 탭이 보여주는 `PDFDocument`는 매번 새로 변환한 결과라
    /// 서로 다른 문서를 검색하게 되므로 공유하면 안 된다.
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
        // `HWPViewerPane.load()`와 같은 패턴 — documentData가 바뀌면(다른
        // 문서를 같은 뷰에서 다시 열게 되는 경우) 다시 변환한다.
        .task(id: documentData) {
            await convert()
        }
        // [2026-08-18 추가] 부모가 넘겨준 성경 장절 검색 리졸버를 이 탭 전용
        // `pdfSearchController`에 연결한다 — `additionalSearchTerms` 프로퍼티
        // 주석 참고.
        .onAppear {
            pdfSearchController.additionalSearchTerms = additionalSearchTerms
        }
    }

    /// `pdfSearchBar`(원본 `.pdf` 문서 탭)와 똑같은 모양 — 결과물이 결국
    /// `PDFDocument`라 별도 줌 버튼 없이(PDFView가 이미 확대/축소 제스처를
    /// 지원한다) 검색창만 둔다.
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
                }
                .buttonStyle(.plain)
                .disabled(pdfSearchController.matches.isEmpty)
                .help("이전 일치 항목")

                Button {
                    pdfSearchController.goToNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(pdfSearchController.matches.isEmpty)
                .help("다음 일치 항목")
            }
        }
        .padding(8)
    }

    /// [2026-08-16 사전 변환 연동] `preConvertedDocument`(업로드 시 미리 만들어
    /// 둔 결과)가 있으면 그걸 그대로 쓰고 끝낸다 — 없을 때만(위 4) 참고,
    /// "기존 데이터") `RhwpPDFExportService`(오프스크린 WKWebView + rhwp의
    /// `renderPageSvg` → `WKWebView.createPDF`)로 즉석 변환한다. 자세한 경위는
    /// 이 struct와 `RhwpPDFExportService.swift` 상단 주석 참고.
    private func convert() async {
        pdfDocument = nil
        errorMessage = nil
        conversionProgress = nil

        if let preConvertedDocument {
            pdfDocument = preConvertedDocument
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
            onAvailabilityChange?(true)
        } catch {
            errorMessage = "\(error)"
            onAvailabilityChange?(false)
        }
    }
}
