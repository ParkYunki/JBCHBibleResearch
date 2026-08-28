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

    /// [2026-08-26 추가] 사용자 요청 — "iCloud 상에는 있지만 현재 기기에 아직
    /// 다운로드상태가 아닌 파일을 뷰어로 열면 다운로드가 이루어져서 뷰어로 볼 수
    /// 있게 할것. 다운로드 중이면 다운로드 진행률이 나타날 수 있도록." 위
    /// `resolvedURL`이 가리키는 원본 파일의 iCloud 다운로드 상태 —
    /// `UbiquitousFileDownloadMonitor` 참고. `DocumentViewerView`가 이 값을
    /// 보고 다운로드 중이면 진행률 UI를, 실패하면 에러 메시지를 보여준다.
    private(set) var downloadStatus: UbiquitousFileDownloadMonitor.Status = .ready
    private var downloadMonitor: UbiquitousFileDownloadMonitor?

    /// 위와 같은 이유, `convertedPDFDocument`(hwp/hwpx/docx의 "PDF 변환" 탭
    /// 전용 사전 변환 PDF)가 가리키는 별도 파일용 — 원본과는 독립적인 다른
    /// 파일이라 다운로드 상태도 따로일 수 있다(예: 원본은 이미 받아졌는데
    /// 변환 PDF는 아직 안 받아진 경우, 혹은 그 반대).
    private(set) var convertedPDFDownloadStatus: UbiquitousFileDownloadMonitor.Status = .ready
    private var convertedPDFDownloadMonitor: UbiquitousFileDownloadMonitor?

    private let modelContext: ModelContext

    init(document: SourceDocument, modelContext: ModelContext) {
        self.document = document
        self.modelContext = modelContext
    }

    func onAppear() {
        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼 —
        // originalFilePath가 있으면 그걸로(다른 기기에서도 항상 성공), 없으면
        // (구버전 문서) 북마크로 폴백하고 성공 시 소급 채워 넣는다.
        //
        // [2026-08-26 수정, 사용자 보고 fix] "iCloud 문서를 열어도 다운로드
        // 진행 없이 바로 'PDF를 열 수 없습니다'만 뜬다" — 원인을 좁혀 보니
        // `resolveOriginalFileURL` 자체가 던지는 에러(컨테이너를 못 찾음,
        // 북마크가 이 기기에서 무효함 등)를 `try?`로 조용히 삼켜 `resolvedURL`
        // 이 nil이 되고, 그러면 아래에서 다운로드 모니터 자체가 시작되지 않아
        // (다운로드할 URL이 없으니 당연하다) 계속 `.ready` 상태로 남아 아무
        // 진단 정보 없는 기존 폴백 메시지만 보이는 경로가 있었다. 이제 그
        // 에러를 잡아 `downloadStatus`에 실제 사유로 담아 화면에 그대로
        // 보여준다 — 이게 진짜 원인(컨테이너 미해결/북마크 무효 등)을 바로
        // 알 수 있게 해 준다.
        do {
            resolvedURL = try DocumentUploadService.resolveOriginalFileURL(for: document, context: modelContext)
        } catch {
            resolvedURL = nil
            let message = "원본 파일 위치를 확인하지 못했습니다: \(error)"
            downloadStatus = .failed(message)
            // [2026-08-26 추가] 사용자 요청 — "상세한 오류메세지는 앱 내
            // 저장공간에 따로 로그 파일을 남겨둘것." 화면 메시지는 이 창을
            // 닫으면 사라지므로, 나중에 다시 들여다볼 수 있게 파일에도 남긴다.
            DocumentViewerErrorLog.log(context: document.originalFilename, message: message)
        }

        // [2026-08-26 수정] 사용자 요청 — 위 `downloadStatus` 프로퍼티 주석
        // 참고. 예전엔 이 아래에서 곧바로 `PDFDocument(url:)`/`Data(contentsOf:)`
        // 를 읽었는데, iCloud에는 있지만 이 기기엔 아직 다운로드 안 된 파일이면
        // 조용히 실패했다. `UbiquitousFileDownloadMonitor`가 먼저 다운로드
        // 상태를 확인해(이미 로컬에 있으면 즉시, 아니면 다운로드를 요청하고
        // 진행률을 관찰하며) `.ready`가 된 시점에만 실제 파일 읽기
        // (`loadPrimaryFileContent`)를 수행한다.
        // [2026-08-26 추가] `.doc`는 이 값을 절대 화면에 쓰지 않는다 —
        // `supportsNativePreview`가 `.doc`에 대해 항상 false라 `content(viewModel:)`
        // 가 언제나 `extractedTextPane`(SwiftData에 이미 저장된 추출 텍스트)만
        // 보여주고, `originalPane`의 `.doc, .docx, .pages` 케이스는 위 파일 상단
        // 주석대로 죽은 코드다. 그런 문서까지 다운로드를 트리거하면 사용자가 볼
        // 일 없는 원본 파일을 몰래 iCloud에서 받아오는 부작용만 생기므로 제외한다.
        if document.originalFormat == .doc {
            downloadStatus = .ready
        } else if let resolvedURL {
            let monitor = UbiquitousFileDownloadMonitor { [weak self] status in
                guard let self else { return }
                self.downloadStatus = status
                switch status {
                case .ready:
                    self.loadPrimaryFileContent(from: resolvedURL)
                case .failed(let message):
                    // [2026-08-26 추가] 위 catch 블록과 같은 이유.
                    DocumentViewerErrorLog.log(context: self.document.originalFilename, message: message)
                case .downloading:
                    break
                }
            }
            downloadMonitor = monitor
            monitor.beginMonitoring(url: resolvedURL)
        }
        // resolvedURL이 nil인 경우(위 catch에서 이미 처리) 여기서 `.ready`로
        // 덮어쓰지 않는다 — 그러면 방금 담아 둔 실제 실패 사유가 지워지고
        // 예전처럼 진단 정보 없는 상태로 되돌아간다.

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

            // [2026-08-26 수정] 원본 파일과 같은 이유 — 이 PDF도 같은 iCloud
            // 컨테이너 안 별도 파일이라 독립적으로 다운로드 상태를 확인한다.
            let monitor = UbiquitousFileDownloadMonitor { [weak self] status in
                guard let self else { return }
                self.convertedPDFDownloadStatus = status
                switch status {
                case .ready:
                    self.convertedPDFDocument = PDFDocument(url: pdfURL)
                case .failed(let message):
                    // [2026-08-26 추가] 위 catch 블록과 같은 이유. 원본 파일과
                    // 구분되도록 컨텍스트에 "(PDF 변환)"을 덧붙인다.
                    DocumentViewerErrorLog.log(context: "\(self.document.originalFilename) (PDF 변환)", message: message)
                case .downloading:
                    break
                }
            }
            convertedPDFDownloadMonitor = monitor
            monitor.beginMonitoring(url: pdfURL)
        }
        loadTextLines()
    }

    /// 위 `downloadStatus`가 `.ready`가 된 시점(이미 로컬에 있었거나, 방금
    /// 다운로드가 끝났거나)에 실제로 원본 파일 바이트를 읽어 캐싱한다 — 예전
    /// `onAppear()` 안에 곧바로 있던 로직을 그대로 옮긴 것뿐, 조건/동작은
    /// 바뀌지 않았다.
    ///
    /// [2026-08-26 수정] 사용자 보고 — "연구문서 hwp 파일 클릭(탭) - iOS
    /// 경우 다운로드 진행하다 앱이 튕기는 경우가 생김." 실기기 크래시 로그가
    /// 없어 확정 원인은 아니지만(사용자 확인 — 크래시 로그 없이 코드 리뷰로
    /// 가능성만 점검하기로 함), 코드상 명백한 위험 하나를 발견해 방어적으로
    /// 고친다: 이 함수는 `@MainActor` 뷰모델의 메서드라 메인 스레드에서
    /// 실행되는데, hwp/hwpx 분기의 `readSecurityScopedData`는 (연구문서로
    /// 올라오는 hwp가 스캔된 강의안처럼 수십MB 이상일 수 있어) 파일 전체를
    /// 동기적으로 디스크에서 읽는다 — 이 코드는 정확히 "iCloud 다운로드가
    /// 막 끝난 직후"에 자동으로 호출되므로(`onAppear()`의 `UbiquitousFileDownloadMonitor`
    /// `.ready` 콜백), 다운로드 직후 큰 파일을 메인 스레드에서 바로 읽는
    /// 시점이 사용자가 "다운로드 진행하다 튕긴다"고 느낄 수 있는 타이밍과
    /// 정확히 겹친다 — 메인 스레드가 충분히 오래 막히면 iOS가 워치독으로
    /// 앱을 강제 종료하는(사용자에게는 "크래시"로 보이는) 잘 알려진 패턴이다.
    /// 실제 파일 읽기를 `Task.detached`(메인 액터 밖)로 옮기고, 다 읽은 뒤
    /// 결과만 메인 액터로 돌아와 대입한다 — 최종적으로 `hwpFileData`에 들어가는
    /// 값과 그 값이 쓰이는 시점(화면이 `@Observable` 변화를 관찰) 자체는
    /// 전혀 바뀌지 않고, "어느 스레드에서 읽느냐"만 바뀐다. `.pdf` 분기는
    /// 이번 사용자 보고 범위(hwp) 밖이라 손대지 않았다 — 근거 없이 관련 없는
    /// 코드까지 바꾸지 않기 위함.
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
    }

    /// security-scoped URL에서 파일 바이트를 읽는다 — 접근 권한을 열고
    /// 닫는 절차가 `DocumentUploadService`/`DocumentTextExtractionService`의
    /// 다른 파일 읽기 지점들과 동일하다(`startAccessingSecurityScopedResource`
    /// / `defer { stopAccessing... }` 짝).
    ///
    /// [2026-08-26 추가] `nonisolated` — 이 타입 자체가 `@MainActor`라 기본적으론
    /// 이 정적 메서드도 메인 액터에 격리된다. 위 `loadPrimaryFileContent`가
    /// `Task.detached`(메인 액터 밖) 안에서 이 함수를 불러 실제 디스크 읽기를
    /// 메인 스레드 밖에서 하려는 것인데, `nonisolated`가 없으면 `Task.detached`
    /// 안에서도 이 호출이 다시 메인 액터로 홉(hop)해 버려 정작 무거운
    /// `Data(contentsOf:)`가 메인 스레드에서 실행되는 건 똑같아진다 — 그러면
    /// 옮긴 의미가 없다. 이 함수는 `self`(액터 격리 상태)를 전혀 건드리지 않는
    /// 순수 파일 I/O라 `nonisolated`로 표시해도 안전하다.
    private nonisolated static func readSecurityScopedData(from url: URL) throws -> Data {
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
