//
//  DocumentsViewModel.swift
//  JBCHBibleResearch
//
//  S5(연구문서 업로드) 화면의 상태와 데이터 접근. screens.md 14장 전체 프로세스 —
//  업로드 접수(14.1, DocumentUploadService) → 형식별 추출(14.2,
//  DocumentTextExtractionService) → 상태 갱신(14.5)까지 이 뷰모델이 오케스트레이션한다.
//

import Foundation
import SwiftData
import Observation
import BibleResearchModels

@MainActor
@Observable
final class DocumentsViewModel {
    /// ⚠️ [2026-08-15 참고, 크래시 수정] `DocumentsHomeView`는 이제 이 배열이
    /// 아니라 자체 `@Query`(`queriedDocuments`)로 목록을 그린다 — 다른 화면
    /// (Settings 개발자 탭의 "연구문서 전체 삭제" 등)이 이 뷰모델을 거치지 않고
    /// 같은 `modelContext`에서 `SourceDocument`를 지웠을 때, 이 화면이 계속
    /// 떠 있는 상태(macOS는 메인 창/설정 창이 동시에 뜬다)면 이 캐시 배열이
    /// 지워진 객체를 계속 들고 있다가 다음 리드로우에서 크래시했기 때문이다
    /// (`DocumentsHomeView.swift` 상단 `@Query` 주석 참고). 화면 렌더링에는 더
    /// 안 쓰이지만, `upload(urls:)`가 낙관적 갱신(업로드 직후 바로 맨 앞에
    /// insert)에 여전히 이 배열을 쓰고 있어 완전히 제거하지는 않았다 — 필요
    /// 없어진 다른 프로퍼티(`hasPendingOCRReview` 등)는 `document` 하나를 받는
    /// 형태라 이 배열과 무관하게 계속 동작한다.
    private(set) var documents: [SourceDocument] = []
    private(set) var categories: [ImageCategory] = []
    var lastErrorDescription: String?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func onAppear() {
        loadDocuments()
        loadCategories()
    }

    func loadDocuments() {
        do {
            documents = try modelContext.fetch(FetchDescriptor<SourceDocument>(sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)]))
        } catch {
            lastErrorDescription = "문서 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func loadCategories() {
        categories = (try? modelContext.fetch(FetchDescriptor<ImageCategory>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    /// 업로드 3가지 진입점(툴바 버튼/드래그앤드롭/드롭존 클릭)이 모두 이 함수 하나를
    /// 호출한다(14장 "같은 함수 호출, 중복 구현 방지").
    ///
    /// [2026-08-08 추가] `relatedChapter` — 사용자 요청("문서를 업로드할 때 관련
    /// 성경 장을 입력받을 수 있도록")에 따라 DocumentsHomeView가 업로드 확인
    /// 시트에서 고른 책/장을 넘긴다. 한 번에 여러 파일을 올려도(드롭/멀티 선택)
    /// 이 배치 전체에 같은 장을 적용한다 — 파일마다 다른 장을 고르게 하면 매 파일
    /// 확인창이 떠 흐름이 번거로워지므로, "건너뛰기"로 아예 비워두거나 나중에
    /// 문서 목록에서 개별 재설정(`setRelatedChapter`)하는 쪽을 택했다.
    /// [2026-08-15 추가] 사용자 보고 — "혹시 파일이 두 개 생성되는지 확인." 원인
    /// 후보 — 드래그 앤 드롭 경로(`DropZoneModifier`가 `NSItemProvider.
    /// loadObject(ofClass:completionHandler:)`를 씀)는 실기기 콘솔에서 실제로
    /// AppKit의 "재진입 드래그 메시지"(`Reentrant message: kDragIPCWithinWindow`)
    /// 가 찍히는 걸 확인한 적이 있다 — 같은 드롭 한 번에 완료 콜백이 두 번
    /// 불려 `upload`가 같은 파일로 두 번 호출될 가능성을 배제할 수 없다(정확한
    /// AppKit 내부 동작까지는 이 세션에서 실기기로 재현/디버깅할 수 없어 단정할
    /// 수는 없다). 근본 원인을 확정하지 못했더라도, 아주 짧은 시간 안에 같은
    /// 파일 경로로 또 업로드 요청이 들어오면 무시하는 방어 로직을 걸어 두면
    /// 어느 경로로 이중 호출이 나든 결과적으로 중복 생성은 막을 수 있다.
    private var recentlyUploadedPaths: [String: Date] = [:]
    private static let duplicateUploadGuardWindow: TimeInterval = 3

    /// [2026-08-18 추가] `category` — 사용자 요청 "연구문서 업로드시 반드시
    /// 카테고리 입력을 강제할 것." 호출부(DocumentsHomeView의 업로드 확인
    /// 시트)가 카테고리를 고르기 전엔 업로드 자체를 못 누르게 막으므로, 실제로는
    /// 이 함수가 항상 non-nil 카테고리를 받는다 — 그래도 파라미터 타입 자체는
    /// 옵셔널로 둔다(`DocumentUploadService.createSourceDocument` 상단 주석과
    /// 같은 이유 — UI 강제와 데이터 계층 제약을 분리).
    func upload(urls: [URL], relatedChapter: BibleChapterRef? = nil, category: ImageCategory? = nil) {
        let now = Date.now
        for url in urls {
            let path = url.path
            if let lastUploaded = recentlyUploadedPaths[path],
               now.timeIntervalSince(lastUploaded) < Self.duplicateUploadGuardWindow {
                continue
            }
            recentlyUploadedPaths[path] = now

            do {
                let document = try DocumentUploadService.createSourceDocument(
                    from: url, context: modelContext, relatedChapterRef: relatedChapter, category: category
                )
                documents.insert(document, at: 0)
                // [2026-08-16 추가] 사용자 질문 — "HWP 파일만 동기화 폴더에
                // 저장되지 않는 이유는?" iCloud Drive 복사가 실패하면 지금까지
                // 아무 표시 없이 원본 위치를 그대로 참조하는 방식으로 조용히
                // 폴백했다(DocumentUploadService.swift `lastICloudCopyFailureReason`
                // 상단 주석 참고) — 업로드 자체(문서 생성)는 계속 성공하지만,
                // "동기화 폴더에는 실제로 복사되지 않았다"는 사실과 이유를
                // 이제 사용자에게 알림으로 보여준다.
                if document.storageLocationKind != .icloudDrive {
                    let reason = DocumentUploadService.lastICloudCopyFailureReason ?? "알 수 없는 이유"
                    lastErrorDescription = "\(url.lastPathComponent)을(를) iCloud Drive 동기화 폴더에 복사하지 못해 원래 위치를 그대로 참조합니다 (\(reason)). 원본 파일을 옮기거나 지우면 이 문서를 열지 못할 수 있습니다."
                }
                Task {
                    // [2026-08-16 순서 변경] 사용자 질문 — "텍스트 추출이
                    // 네이티브에서만 진행되고 있는데, 실패하면 rhwp에서 추출을
                    // 진행할 수 있는가? PDF 변환된 파일에서 추출을 하는 것으로
                    // 할 수 있는가?" — 세 번째 폴백(`DocumentTextExtractionService.
                    // extractHWPFromConvertedPDF`)이 `ConvertedPDF` 레코드를
                    // 쓰려면 이 시점에 이미 존재해야 한다. 원래는 텍스트 추출을
                    // 먼저 부르고 PDF 생성을 나중에 불렀는데, 그러면 그 폴백이
                    // 항상 허탕이었다 — 순서를 바꿔 PDF 사전 생성을 먼저 끝낸다.
                    // (이 함수는 hwp/hwpx가 아니면 즉시 아무것도 안 하고
                    // 돌아오므로, 다른 형식에도 그냥 항상 불러도 안전하다.)
                    await DocumentUploadService.generateConvertedPDF(for: document, context: modelContext)
                    await DocumentTextExtractionService.extract(for: document, context: modelContext)
                    loadDocuments()
                }
            } catch {
                lastErrorDescription = "\(url.lastPathComponent) 업로드 실패: \(error.localizedDescription)"
            }
        }
    }

    /// 업로드 시 건너뛰었거나 잘못 지정한 "관련 성경 장"을 나중에 문서 목록에서
    /// 고치거나(값을 넘김) 해제(nil)할 수 있게 한다 — `setCategory`와 같은 원칙
    /// (이산적 액션, 즉시 저장).
    func setRelatedChapter(_ chapterRef: BibleChapterRef?, for document: SourceDocument) {
        document.relatedChapterRef = chapterRef
        try? modelContext.save()
    }

    /// 14.5 — 실패(`failed_needs_manual`) 문서에 대한 재시도.
    ///
    /// [2026-08-16 수정] `upload(urls:)`와 같은 이유로 순서를 맞췄다 — 이
    /// 문서가 처음 업로드됐을 때 PDF 사전 생성이 아직 없었거나 실패했을 수
    /// 있으므로, 재시도 때도 먼저 PDF 생성을 한 번 더 시도해 세 번째 폴백
    /// (`extractHWPFromConvertedPDF`)이 쓸 수 있는 최신 상태로 만들어 둔다.
    /// `generateConvertedPDF`는 이미 `ConvertedPDF`가 있으면 멱등하게
    /// 건너뛴다.
    func retry(_ document: SourceDocument) {
        Task {
            await DocumentUploadService.generateConvertedPDF(for: document, context: modelContext)
            await DocumentTextExtractionService.extract(for: document, context: modelContext)
            loadDocuments()
        }
    }

    func delete(_ document: SourceDocument) {
        // [2026-08-11 추가] 사용자 요청 — "삭제했을 때는 그 관련내용도 다 삭제."
        BibleReferenceIndexingService.removeMentions(
            sourceType: .document, sourceId: document.id.uuidString, context: modelContext
        )
        // [2026-08-15 추가] 사용자 요청 — "연구문서를 앱에서 삭제하면 파일도
        // 삭제할 것." DB 레코드를 지우기 전에 먼저(레코드가 사라지면 이 문서가
        // 어떤 파일을 가리켰는지 알 수 없으므로) 실제 파일을 지운다 —
        // DocumentUploadService.deleteStoredFile 참고(우리가 iCloud 컨테이너
        // 안에 직접 복사해 둔 파일만 지우고, 사용자의 원래 위치 원본은 건드리지
        // 않는다).
        DocumentUploadService.deleteStoredFile(for: document)
        // [2026-08-16 추가] hwp 업로드 시 미리 만들어 둔 PDF(있다면)도 원본과
        // 같은 이유로 함께 지운다 — DocumentUploadService.deleteConvertedPDFFiles
        // 상단 주석 참고.
        DocumentUploadService.deleteConvertedPDFFiles(for: document)
        modelContext.delete(document)
        try? modelContext.save()
        loadDocuments()
    }

    /// 6.4 — 이미지 원본 분류. 이산적 액션이라 즉시 저장한다(디바운스 불필요,
    /// 13.3과 같은 원칙).
    func setCategory(_ category: ImageCategory?, for document: SourceDocument) {
        document.category = category
        try? modelContext.save()
    }

    /// [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드 앱처럼 기능을
    /// 추가할 것. 고정됨." 이산적 액션이라 `setCategory`와 같은 원칙(즉시 저장).
    func togglePin(_ document: SourceDocument) {
        document.isPinned.toggle()
        try? modelContext.save()
    }

    func createCategory(named rawName: String) -> ImageCategory? {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let existing = categories.first(where: { $0.name == name }) { return existing }
        let category = ImageCategory(name: name)
        modelContext.insert(category)
        try? modelContext.save()
        categories.append(category)
        return category
    }

    /// 이 문서가 OCR 검수 대기 중인지(draft 상태 OCRResult가 있는지) — 목록 행에서
    /// "검수 대기" 배지를 따로 보여주고, 탭하면 S7로 바로 연결하기 위해 쓴다.
    func hasPendingOCRReview(_ document: SourceDocument) -> Bool {
        (document.ocrResults ?? []).contains { $0.status == .draft }
    }
}
