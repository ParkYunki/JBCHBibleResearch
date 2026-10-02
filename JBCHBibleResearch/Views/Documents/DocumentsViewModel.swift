//
//  DocumentsViewModel.swift
//  JBCHBibleResearch
//
//  S5(연구문서 업로드) 화면의 상태와 데이터 접근. 업로드 접수(DocumentUploadService) →
//  형식별 추출(DocumentTextExtractionService) → 상태 갱신까지 이 뷰모델이 오케스트레이션한다.
//

import Foundation
import SwiftData
import Observation
import BibleResearchModels

@MainActor
@Observable
final class DocumentsViewModel {
    /// ⚠️ 화면 렌더링에는 쓰지 않는다 — `DocumentsHomeView`는 자체 `@Query`로 목록을 그린다(다른 화면이
    /// 이 뷰모델을 거치지 않고 `SourceDocument`를 지우면 이 캐시 배열이 삭제된 객체를 들고 있다 크래시하기
    /// 때문). `upload(urls:)`의 낙관적 갱신(맨 앞 insert)에만 남아 있다.
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
        categories = (try? modelContext.fetch(FetchDescriptor<ImageCategory>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))) ?? []
    }

    /// 같은 파일 경로로 짧은 시간 안에 들어온 중복 업로드 요청을 무시하기 위한 기록. 드래그 앤 드롭
    /// 완료 콜백이 두 번 불릴 가능성(AppKit "재진입 드래그 메시지" 로그를 확인한 적 있음)을 방어한다 —
    /// 근본 원인은 확정하지 못했다.
    private var recentlyUploadedPaths: [String: Date] = [:]
    private static let duplicateUploadGuardWindow: TimeInterval = 3

    /// 업로드 3가지 진입점(툴바 버튼/드래그앤드롭/드롭존 클릭)이 모두 이 함수 하나를 호출한다.
    /// `relatedChapter`는 배치 전체(멀티 선택/드롭)에 같은 장을 적용한다.
    /// `category`는 UI가 선택을 강제하므로 실제로는 non-nil이지만, UI 강제와 데이터 계층 제약을
    /// 분리하려고 옵셔널로 둔다.
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
                // iCloud Drive 복사 실패 시 원본 위치를 참조하는 폴백으로 업로드는 성공하므로,
                // 동기화 폴더에 복사되지 않았다는 사실과 이유를 알림으로 보여준다.
                if document.storageLocationKind != .icloudDrive {
                    let reason = DocumentUploadService.lastICloudCopyFailureReason ?? "알 수 없는 이유"
                    lastErrorDescription = "\(url.lastPathComponent)을(를) iCloud Drive 동기화 폴더에 복사하지 못해 원래 위치를 그대로 참조합니다 (\(reason)). 원본 파일을 옮기거나 지우면 이 문서를 열지 못할 수 있습니다."
                }
                Task {
                    // `generateConvertedPDF`가 텍스트 추출보다 먼저 끝나야 세 번째 폴백(`extractHWPFromConvertedPDF`)이
                    // `ConvertedPDF` 레코드를 쓸 수 있다. hwp/hwpx가 아니면 즉시 반환하므로 다른 형식에도 안전하다.
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
    /// 업로드 때와 같은 순서 — PDF 사전 생성이 없었거나 실패했을 수 있어 먼저 다시 시도한다
    /// (`generateConvertedPDF`는 이미 `ConvertedPDF`가 있으면 멱등하게 건너뛴다).
    func retry(_ document: SourceDocument) {
        Task {
            await DocumentUploadService.generateConvertedPDF(for: document, context: modelContext)
            await DocumentTextExtractionService.extract(for: document, context: modelContext)
            loadDocuments()
        }
    }

    func delete(_ document: SourceDocument) {
        // 삭제한 문서의 관련 멘션도 함께 삭제한다.
        BibleReferenceIndexingService.removeMentions(
            sourceType: .document, sourceId: document.id.uuidString, context: modelContext
        )
        // 레코드가 사라지면 어떤 파일을 가리켰는지 알 수 없으므로 DB 삭제 전에 파일을 먼저 지운다.
        // 앱이 iCloud 컨테이너에 복사한 파일만 지우고 사용자의 원래 위치 원본은 건드리지 않는다.
        DocumentUploadService.deleteStoredFile(for: document)
        // hwp 업로드 시 미리 만들어 둔 PDF도 함께 지운다.
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

    /// 문서 고정 토글. 이산적 액션이라 `setCategory`와 같은 원칙(즉시 저장).
    func togglePin(_ document: SourceDocument) {
        document.isPinned.toggle()
        try? modelContext.save()
    }

    func createCategory(named rawName: String) -> ImageCategory? {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let existing = categories.first(where: { $0.name == name }) { return existing }
        // 새 카테고리는 맨 뒤에 둔다(수동 순서 `sortOrder`의 최댓값 + 1).
        let category = ImageCategory(name: name, sortOrder: (categories.map(\.sortOrder).max() ?? -1) + 1)
        modelContext.insert(category)
        try? modelContext.save()
        categories.append(category)
        return category
    }

    /// 카테고리 이름 변경. `createCategory`처럼 트리밍하고, 같은 이름의 다른 카테고리가 이미 있으면
    /// 아무 것도 하지 않는다(이름으로 구분하는 `categoryMenu`/`folderGroups`와의 일관성).
    func renameCategory(_ category: ImageCategory, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != category.name else { return }
        guard !categories.contains(where: { $0.id != category.id && $0.name == name }) else { return }
        category.name = name
        try? modelContext.save()
        loadCategories()
    }


    /// 카테고리 삭제. 소속 문서는 지워지지 않는다 — `ImageCategory.sourceDocuments`의 deleteRule이 `.nullify`라
    /// 문서의 `category`만 비워져 "분류 없음"으로 보인다.
    func deleteCategory(_ category: ImageCategory) {
        modelContext.delete(category)
        try? modelContext.save()
        loadCategories()
    }

    /// 수동 순서 변경(`List.onMove`/위·아래 이동 공용). 변경 후 전체를 0...n-1로 다시 매겨
    /// 기존 카테고리의 동률(모두 0)이나 동기화로 생긴 값 겹침도 이 시점에 정리한다.
    func moveCategories(from source: IndexSet, to destination: Int) {
        // SwiftUI의 `move(fromOffsets:toOffset:)`와 같은 의미를 직접 구현(이 파일은 SwiftUI를 import하지 않는다).
        var reordered = categories
        let moving = source.sorted().compactMap { reordered.indices.contains($0) ? reordered[$0] : nil }
        guard !moving.isEmpty else { return }
        let insertionIndex = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where reordered.indices.contains(index) { reordered.remove(at: index) }
        reordered.insert(contentsOf: moving, at: max(0, min(insertionIndex, reordered.count)))
        for (index, category) in reordered.enumerated() where category.sortOrder != index {
            category.sortOrder = index
        }
        try? modelContext.save()
        categories = reordered
    }
}
