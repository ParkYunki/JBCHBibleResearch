//
//  DocumentsHomeView.swift
//  JBCHBibleResearch
//
//  S5(연구문서 업로드) 화면. screens.md 3장 S5/S6/S7 절 + 14장(업로드→인덱싱
//  프로세스) 근거. 업로드 3가지 진입점(툴바 `+`, 드래그앤드롭 존, 드롭존 클릭)이
//  모두 `DocumentsViewModel.upload(urls:)` 하나를 공유한다.
//
//  ⚠️ [아이폰 hwp 차단] `UIDevice.current.userInterfaceIdiom == .phone`일 때만
//  `DocumentUploadService.supportedContentTypes(allowHWP:)`에 `false`를 넘긴다 —
//  RootView.swift와 같은 방식(별도 타겟이 아니라 런타임 분기)을 그대로 따랐다.
//  아이패드/맥은 hwp를 그대로 선택할 수 있다(4.1 "검증 후 결정" 대상 — 일단 허용).
//
//  ⚠️ [드래그앤드롭 단순화] 여러 파일을 한꺼번에 드롭하면 `NSItemProvider`별로
//  URL이 비동기·개별적으로 resolve되는데, 이 구현은 "다 모일 때까지 기다렸다 한
//  번에 처리"하지 않고 resolve되는 대로 하나씩 바로 업로드한다 — DispatchGroup 등으로
//  일괄 처리를 만들 수도 있지만, 그러면 완료 콜백이 메인 액터 밖 임의 큐에서 오는
//  문제(Swift 6 엄격 동시성)를 다시 다뤄야 해서 더 단순한 개별 처리 경로를 택했다.
//  최종 동작(모든 드롭 파일이 각자 업로드됨)은 동일하다.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

/// [2026-08-16 신설] 사용자 요청 — "카테고리는 1) 업로드할 때 지정한 성경
/// 2) 특정 성경을 선택할 수 없는 경우 기존 카테고리 선택 또는 사용자 입력."
/// 두 갈래(성경 장 / 커스텀 카테고리)를 필터 하나로 다루기 위한 타입 — 실제
/// 저장은 그대로 `SourceDocument.relatedChapterRef`/`.category` 두 필드에
/// 각자 남는다(모델 변경 없음), 이건 화면 표시/필터링 용도로만 둘을 묶는다.
private enum DocumentCategoryFilter: Hashable {
    case all
    case uncategorized
    case chapter(BibleChapterRef)
    case custom(UUID)
}

struct DocumentsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DocumentsViewModel?

    /// [2026-08-15 추가, 크래시 수정] macOS는 이 메인 창과 설정 창(`Settings { }`,
    /// `JBCHBibleResearchApp.swift` 참고)이 동시에 떠 있을 수 있다 — 설정 창의
    /// "연구문서 전체 삭제"(SettingsView.swift `deleteAllDocuments()`)처럼 이
    /// 화면을 거치지 않은 다른 코드 경로가 같은 `modelContext`에서 `SourceDocument`
    /// 를 지우면, 이 화면이 그 순간 "떠 있는 채로" 있어서(`.onAppear`가 다시 안
    /// 불림) `viewModel.documents`(한 번 fetch해서 캐시해 두는 배열)가 지워진
    /// 객체를 계속 들고 있게 되고, 다음 리드로우에서 크래시했다(아래 `.onAppear`
    /// 주석 참고 — 그 fix만으로는 "화면이 계속 떠 있던" 이 경우를 못 막는다).
    /// `@Query`는 SwiftData가 컨텍스트 변경을 직접 구독해 자동 갱신해 주므로
    /// (누가 어디서 지웠든 상관없이), 목록 렌더링만큼은 `viewModel.documents`
    /// 대신 이걸 쓴다 — 지워진 객체가 애초에 이 배열에 남아있을 수 없다.
    @Query(sort: [SortDescriptor(\SourceDocument.uploadedAt, order: .reverse)])
    private var queriedDocuments: [SourceDocument]

    /// [2026-08-17 추가] 사용자 요청 — "연구문서 검색에 성경장절도 검색할 수
    /// 있도록 할 것." 문서 본문에서 이미 성경구절을 추출해 두는
    /// `BibleReferenceIndexingService.reindexDocument`(문서 저장 직후 호출)의
    /// 결과물 `VerseMention`을 그대로 재사용한다 — 검색어를 다시 문서 전체
    /// 텍스트에서 정규식으로 훑을 필요 없이, 이미 구조화된(책ID/장/절) 인덱스와
    /// 비교하면 된다. `sourceTypeRaw`(평범한 String 저장 프로퍼티, enum이 아님)로
    /// 걸러 문서 소스만 가져온다 — `removeMentions`(BibleReferenceIndexingService.swift)가
    /// 이미 같은 방식(String 프로퍼티에 대한 #Predicate 등호 비교)을 쓰고 있어
    /// 안전하다고 확인된 패턴이다.
    @Query(filter: #Predicate<VerseMention> { $0.sourceTypeRaw == "document" })
    private var documentVerseMentions: [VerseMention]

    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    /// [2026-08-07 추가] S7 "저장 후 다음" 큐 — 검수 대기 중인 문서 목록을 탭한
    /// 문서부터 시작하도록 회전시켜 담는다. 비어 있지 않으면 시트가 떠 있다는 뜻.
    /// `OCRReviewQueueView.swift` 참고.
    @State private var ocrReviewQueue: [SourceDocument] = []

    /// [2026-08-08 추가] 사용자 요청 — "문서를 업로드할 때 관련 성경 장을 입력받을
    /// 수 있도록". 업로드 3가지 진입점(툴바/드래그앤드롭/드롭존 클릭)에서 URL을
    /// 얻으면 곧바로 업로드하지 않고 일단 여기 담아 뒀다가, 관련 장 확인 시트에서
    /// "건너뛰기" 또는 "이 장으로 업로드"를 고른 뒤에 실제로 업로드한다 — 여러
    /// 파일을 한꺼번에 올려도 이 배치 전체에 같은 장 하나만 적용한다
    /// (DocumentsViewModel.upload(urls:relatedChapter:) 상단 주석 참고).
    @State private var pendingUploadURLs: [URL] = []
    @State private var chapterLinkBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var chapterLinkChapter: Int = 1
    /// [2026-08-18 추가] 사용자 요청 — "연구문서 업로드시 반드시 카테고리 입력을
    /// 강제할 것. (선택하거나 개인이 입력하거나)." 관련 성경 장(위 두 프로퍼티,
    /// 여전히 "건너뛰기" 가능)과 달리 이 값은 업로드 확인 시트에서 nil인 동안
    /// "건너뛰기"/"이 장으로 업로드" 두 버튼을 모두 비활성화해 강제한다 —
    /// `UploadChapterLinkSheet` 참고. 새 업로드 배치가 시작될 때마다
    /// (`beginUpload`) nil로 되돌려 이전 배치에서 고른 카테고리가 실수로
    /// 새어 들어가지 않게 한다.
    @State private var pendingUploadCategory: ImageCategory?

    /// [2026-08-16 추가, 2026-08-17 갱신] 사용자 요청 — "업로드 영역과 목록
    /// 리스트 사이에 검색기능 추가할 것" → "띄어쓰기로 나누어 단어별 OR
    /// 검색." 파일명/카테고리/관련 성경 장/태그/본문/성경장절을 함께 매칭한다
    /// (`searchScore(for:)` 참고) — 예를 들어 "창세기"로 검색하면 파일명에
    /// 그 단어가 없어도 관련 장이 "창세기 1장"인 문서가 걸린다.
    @State private var searchText: String = ""
    /// [2026-08-16 추가] 사용자 요청 — "카테고리 기능 추가할 것. 검색기능에도
    /// 카테고리 필터링 기능을 넣을 것." 문서의 "카테고리"를 두 갈래로 본다는
    /// 요청대로(1: 업로드 시 지정한 성경 장, 2: 성경 장이 없을 때 쓰는 기존
    /// 카테고리/사용자 입력) `DocumentCategoryFilter`가 그 두 갈래를 필터 옵션
    /// 하나로 묶는다 — `categoryFilterMenu` 참고.
    @State private var categoryFilter: DocumentCategoryFilter = .all

    private var allowsDragAndDrop: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone
        #else
        return false
        #endif
    }

    private var allowsHWP: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("연구문서")
        // [2026-08-18 추가] 아이폰 다중 씬 미지원 fix — `documentRow`가 아이폰에서
        // `NavigationLink(value: document.persistentModelID)`로 미는 목적지를
        // 이 탭(NavigationStack)의 스코프에 등록한다. `DocumentViewerWindowContent`는
        // `WindowGroup(id: "document-viewer", ...)`(맥/아이패드용, JBCHBibleResearchApp.swift
        // 참고)가 쓰던 것과 같은 뷰 — PersistentIdentifier로부터 SourceDocument를
        // 다시 찾아오는 로직이 이미 삭제된 문서까지 안전하게 처리하므로 그대로 재사용한다.
        .navigationDestination(for: PersistentIdentifier.self) { documentID in
            DocumentViewerWindowContent(documentID: documentID)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // 진입점 1: 툴바 상시 노출 버튼(13장 "새 메모" 버튼과 동일 원칙).
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("업로드", systemImage: "square.and.arrow.up")
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: DocumentUploadService.supportedContentTypes(allowHWP: allowsHWP),
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                beginUpload(urls: urls)
            }
        }
        // [2026-08-08 추가, 2026-08-18 카테고리 강제 추가] 업로드 확인 시트 —
        // "건너뛰기"로 닫으면 관련 장 없이 업로드, "이 장으로 업로드"를 고르면
        // 관련 장을 실어서 업로드한다. `pendingUploadURLs`가 비어 있지 않은
        // 동안만 떠 있다(OCRReviewQueueView의 큐 바인딩과 같은 원칙). 카테고리는
        // 두 경로 모두 공통으로 필요 — 시트 안에서 고르기 전엔 두 버튼 다
        // 비활성화된다(`UploadChapterLinkSheet` 참고).
        .sheet(isPresented: Binding(
            get: { !pendingUploadURLs.isEmpty },
            set: { isPresented in if !isPresented { pendingUploadURLs = [] } }
        )) {
            UploadChapterLinkSheet(
                book: $chapterLinkBook,
                chapter: $chapterLinkChapter,
                fileCount: pendingUploadURLs.count,
                categories: viewModel?.categories ?? [],
                selectedCategory: $pendingUploadCategory,
                onCreateCategory: { name in viewModel?.createCategory(named: name) },
                onSkip: { finishPendingUpload(relatedChapter: nil) },
                onConfirm: {
                    finishPendingUpload(relatedChapter: BibleChapterRef(bookId: chapterLinkBook.bookId, chapter: chapterLinkChapter))
                }
            )
        }
        // [2026-08-15 수정] 크래시 리포트 — `SourceDocument.conversionStatus`
        // getter에서 `_assertionFailure`(Swift 런타임 fatal error). 원인: 이
        // 화면이 한 번 나타난 뒤(`setUpIfNeeded`) `viewModel`이 계속 살아있는
        // 채로 유지되는데(사이드바 네비게이션 구조상 뷰 자체가 재생성되지
        // 않음), `setUpIfNeeded`는 `guard viewModel == nil`이라 두 번째부터는
        // 아무 것도 하지 않아 `viewModel.documents` 배열이 그때 그대로 캐시된
        // 채 남는다. 그런데 Settings → 개발자 → "연구문서 전체 삭제"처럼 이
        // 뷰모델을 거치지 않고 다른 코드 경로가 같은 `modelContext`에서
        // `SourceDocument`를 직접 지우면(`SettingsView.swift`
        // `deleteAllDocuments()`), 이 화면이 들고 있던 배열은 이미 지워진(무효한)
        // 객체를 계속 참조하게 된다 — SwiftUI가 그 객체로 `DocumentRowView`를
        // 다시 그리려는 순간(꼭 사용자가 뭘 눌러야 일어나는 게 아니라, 다른
        // 이유로 화면이 다시 그려지기만 해도) `.conversionStatus` 같은 프로퍼티
        // 접근이 크래시한다 — 지워진 SwiftData 모델 객체의 프로퍼티 접근은
        // Swift 예외로 잡을 수 없는 런타임 fatal error다.
        //
        // 고침: 이 화면이 "다시 보일 때마다"(setUpIfNeeded로 처음 만들 때뿐
        // 아니라) 항상 최신 목록을 다시 fetch한다 — 그러면 이미 지워진 객체는
        // 배열에서 통째로 빠지고, SwiftUI는 애초에 그 객체로 행을 그리려는
        // 시도조차 하지 않는다. ⚠️ [남은 리스크] macOS는 여러 창을 동시에 열 수
        // 있어, 이 화면이 "떠 있는 동안" 다른 창(Settings)에서 삭제가 일어나는
        // 경우까지는 이 fix로 완전히 막지 못한다 — 그 경우까지 막으려면
        // `@Query`(값이 바뀔 때 자동 갱신)로 바꾸는 더 큰 리팩터링이 필요하다.
        .onAppear {
            setUpIfNeeded()
            viewModel?.loadDocuments()
            viewModel?.loadCategories()
        }
        // 11장 File 메뉴 "연구문서 업로드... ⌘O" — AppCommands.swift 참고.
        .focusedSceneValue(\.uploadDocumentAction) { isFileImporterPresented = true }
        .alert("오류", isPresented: Binding(
            get: { viewModel?.lastErrorDescription != nil },
            set: { if !$0 { viewModel?.lastErrorDescription = nil } }
        )) {
            Button("확인") { viewModel?.lastErrorDescription = nil }
        } message: {
            Text(viewModel?.lastErrorDescription ?? "")
        }
        // [2026-08-07 추가] S7(OCR 검수) — screens.md 14.3 "검수 화면 진입(대기열
        // 방식 — '저장 후 다음'으로 순차 처리)"을 이제 실제로 반영한다. 예전엔 검수
        // 대기 행을 탭하면 NavigationLink로 OCRReviewView 하나만 열고, 저장하면
        // 목록으로 돌아가 사용자가 다음 대기 행을 다시 찾아 탭해야 했다 — 여기서는
        // 탭한 문서를 큐 맨 앞으로 오도록 회전시킨 뒤 시트로 열고, 저장/폐기할
        // 때마다 큐 안에서 자동으로 다음 문서로 넘어간다(OCRReviewQueueView 참고).
        .sheet(isPresented: Binding(
            get: { !ocrReviewQueue.isEmpty },
            set: { isPresented in
                if !isPresented {
                    ocrReviewQueue = []
                    viewModel?.loadDocuments()
                }
            }
        )) {
            OCRReviewQueueView(queue: ocrReviewQueue)
        }
    }

    @ViewBuilder
    private func content(viewModel: DocumentsViewModel) -> some View {
        VStack(spacing: 0) {
            dropZone(viewModel: viewModel)
                .padding()

            Divider()

            // [2026-08-16 추가] 사용자 요청 — 업로드 영역과 목록 사이에 검색 +
            // 카테고리 필터를 둔다.
            searchAndFilterBar(viewModel: viewModel)

            Divider()

            if queriedDocuments.isEmpty {
                Spacer()
                Text("업로드된 연구문서가 없습니다.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if filteredResults.isEmpty {
                Spacer()
                Text("검색 결과가 없습니다.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filteredResults) { result in
                    DocumentRowView(
                        document: result.document,
                        highlightKeywords: result.score.highlightKeywords,
                        bodyExcerpt: result.score.bodyExcerpt,
                        bodyOccurrenceSum: result.score.bodyOccurrenceSum,
                        matchedTagNames: result.score.matchedTagNames,
                        viewModel: viewModel,
                        onOpenOCRReview: presentOCRReviewQueue
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - 검색 + 카테고리 필터 (2026-08-16 신설)

    /// 검색창(파일명/관련 성경 장/카테고리 이름 매칭) + 카테고리 필터 메뉴 한 줄.
    private func searchAndFilterBar(viewModel: DocumentsViewModel) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("파일명, 관련 성경 장, 카테고리, 태그, 본문, 성경장절로 검색", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))

            categoryFilterMenu(viewModel: viewModel)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// 문서의 "카테고리"를 두 갈래로 다룬다는 요청대로 — 업로드 시 지정한 성경
    /// 장(현재 문서들에 실제로 쓰이고 있는 것만 나열) + 기존 커스텀 카테고리
    /// (`viewModel.categories`, `categoryMenu`가 새로 만드는 것과 같은 목록).
    private func categoryFilterMenu(viewModel: DocumentsViewModel) -> some View {
        Menu {
            Button {
                categoryFilter = .all
            } label: {
                Text("전체")
            }
            Button {
                categoryFilter = .uncategorized
            } label: {
                Text("미분류")
            }
            let chapters = chapterFilterOptions
            if !chapters.isEmpty {
                Divider()
                ForEach(chapters, id: \.self) { ref in
                    Button(chapterLabel(for: ref)) { categoryFilter = .chapter(ref) }
                }
            }
            if !viewModel.categories.isEmpty {
                Divider()
                ForEach(viewModel.categories) { category in
                    Button(category.name) { categoryFilter = .custom(category.id) }
                }
            }
        } label: {
            Label(categoryFilterLabel(viewModel: viewModel), systemImage: "line.3.horizontal.decrease.circle")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// 현재 목록에 실제로 쓰이고 있는 관련 성경 장만 중복 없이, 책/장 순서로.
    private var chapterFilterOptions: [BibleChapterRef] {
        var seen = Set<BibleChapterRef>()
        var result: [BibleChapterRef] = []
        for ref in queriedDocuments.compactMap(\.relatedChapterRef) where !seen.contains(ref) {
            seen.insert(ref)
            result.append(ref)
        }
        return result.sorted { ($0.bookId, $0.chapter) < ($1.bookId, $1.chapter) }
    }

    private func chapterLabel(for ref: BibleChapterRef) -> String {
        guard let book = BooksProvider.shared.book(id: ref.bookId) else { return "\(ref.chapter)장" }
        return "\(book.nameKo) \(ref.chapter)장"
    }

    private func categoryFilterLabel(viewModel: DocumentsViewModel) -> String {
        switch categoryFilter {
        case .all: return "전체"
        case .uncategorized: return "미분류"
        case .chapter(let ref): return chapterLabel(for: ref)
        case .custom(let id):
            return viewModel.categories.first(where: { $0.id == id })?.name ?? "분류"
        }
    }

    /// [2026-08-17 확장] 사용자 요청 — "검색어 띄어쓰기 해서 검색할 때 띄어쓰기로
    /// 글자를 나누어서 각 검색단어별로 OR 검색을 하고, 검색매칭이 가장 많은
    /// 순서대로 정렬시킬 것. 1) 태그 일치 2) 파일명 일치 3) 본문 내용 일치."
    /// 예전에는 검색어 전체를 하나의 부분 문자열로 보고(AND, 전체가 그대로
    /// 포함돼야 함) 매칭했다 — 이제 공백으로 나눈 단어마다 OR로 검색하고, 그
    /// 결과를 태그>파일명>본문 우선순위 + 일치 단어 개수로 정렬한다.
    private var searchWords: [String] {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// 문서 하나에 대한 검색 매칭 결과 — 태그/파일명(+카테고리/관련 장)/본문
    /// 세 갈래로 나눠 "몇 개의 검색단어가 그 갈래에서 일치했는지" 센다.
    ///
    /// [2026-08-17 재정정] 사용자 요청 — "검색결과 정렬은 일치하는 갯수
    /// 내림차순으로 할것." 바로 앞서 구현했던 "태그 > 파일명 > 본문" 우선순위
    /// 사전식 정렬을 걷어내고, 세 갈래 개수를 그냥 합친 `totalMatchCount` 하나로
    /// 단순 내림차순 정렬한다 — 갈래별 개수는 그대로 남겨 두되(각각 어디서
    /// 걸렸는지는 여전히 계산해야 본문 스니펫/태그·파일명 매칭 여부를 알 수
    /// 있다), 정렬 기준만 사용자가 명시한 대로 "총 일치 개수" 하나로 바꿨다.
    private struct DocumentSearchScore {
        let tagCount: Int
        let filenameCount: Int
        let contentCount: Int
        /// [2026-08-17 세 번째 정정] 사용자 요청 — "각 문자열 뒤에 검색된 횟수
        /// (xx) 숫자는 지울것." `Self.buildContentSnippet`이 조각마다 붙이던
        /// "(개수)"를 없앴다 — 이제 "단어+뒤 9자 ... 단어+뒤 9자"만 이어붙인,
        /// 개수 표기가 전혀 없는 순수 발췌문이다(70자 캡은 그대로). 본문에서
        /// 전혀 안 걸렸으면(태그/파일명만으로 매칭됐거나 성경장절 참조로만
        /// 매칭됐으면) nil.
        let bodyExcerpt: String?
        /// "(xx 회 일치)"에 쓰는 숫자 — 본문에서 검색단어들이 총 몇 번 등장했는지
        /// (단어별 개수의 합). `bodyExcerpt`가 더 이상 개수를 직접 보여주지
        /// 않으므로 이 숫자를 따로 들고 있어야 화면에 표시할 수 있다.
        let bodyOccurrenceSum: Int
        /// [2026-08-17 추가] 사용자 요청 — "태그가 일치가 되면 (xx 회 일치) 뒤
        /// 본문 앞에 태그명을 뱃지형식으로 보여줄것." 검색단어와 실제로 일치한
        /// 태그의 "이름"들(중복 제거, 문서에 붙은 순서) — `tagCount`(몇 개의
        /// 검색단어가 태그에서 걸렸는지, 정렬용 숫자)와는 별개로, 뱃지에 실제
        /// 표시할 텍스트가 필요해서 태그 자체를 따로 든다.
        let matchedTagNames: [String]
        /// [2026-08-18 추가] 사용자 요청 — "성경장절 검색시 검색에 관련된
        /// 연구문서의 성경 장절은 형광펜강조(범위에 포함된 성경구절인 경우
        /// 범위 텍스트를 강조) 예) 창1:3으로 검색 -> 창1:1-5 의 텍스트 강조가
        /// 되어야 함." 검색어로 타이핑한 단어들(`searchWords`)만 하이라이트
        /// 대상으로 삼으면 "창1:3"을 검색해도 문서에 실제로 적힌 "창1:1~5"는
        /// 글자 그대로 다르니 하이라이트되지 않는다 — 이 문서에서 실제로
        /// 겹친 성경구절의 원문 표현(`verseMentionSearchTexts`)까지 합쳐서
        /// `DocumentRowView.highlightedText`에 넘긴다. 파일명/본문 발췌 둘 다
        /// 이 목록으로 강조한다(검색단어 + 이 문서에서 실제로 겹친 성경구절
        /// 표현).
        let highlightKeywords: [String]

        static let empty = DocumentSearchScore(
            tagCount: 0, filenameCount: 0, contentCount: 0,
            bodyExcerpt: nil, bodyOccurrenceSum: 0, matchedTagNames: [], highlightKeywords: []
        )

        var isMatch: Bool { tagCount > 0 || filenameCount > 0 || contentCount > 0 }
        /// 정렬 기준 — 갈래 구분 없이 그냥 다 더한 "총 일치 개수"(사용자 요청
        /// "일치하는 갯수 내림차순"). 위 `bodyOccurrenceSum`("(xx 회 일치)"
        /// 표시용, 본문만)과는 다른 숫자다 — 태그/파일명까지 섞은 정렬 전용 값.
        var totalMatchCount: Int { tagCount + filenameCount + contentCount }
    }

    private struct DocumentSearchResult: Identifiable {
        let document: SourceDocument
        let score: DocumentSearchScore
        var id: UUID { document.id }
    }

    /// [2026-08-16 신설, 2026-08-17 두 차례 정렬 로직 조정] 검색 + 카테고리
    /// 필터를 모두 통과한 문서를, 사용자 최종 요청("검색결과 정렬은 일치하는
    /// 갯수 내림차순으로 할것") 그대로 `totalMatchCount`(태그+파일명+본문 일치
    /// 개수 합) 내림차순으로 정렬해 돌려준다(직전에 구현했던 "태그>파일명>본문
    /// 우선순위" 사전식 정렬은 이 요청으로 대체됐다). 개수가 같으면 `sorted`가
    /// Swift 표준 안정 정렬이라 원래 순서(최근 업로드순)가 그대로 유지된다.
    /// 검색어가 비어 있으면(공백만 있거나 아예 없으면) 정렬을 건드리지 않고
    /// 원래 `@Query` 순서(최근 업로드순)를 그대로 유지한다.
    private var filteredResults: [DocumentSearchResult] {
        let candidates = queriedDocuments.filter { matchesCategoryFilter($0) }
        guard !searchWords.isEmpty else {
            return candidates.map { DocumentSearchResult(document: $0, score: .empty) }
        }
        let scored: [DocumentSearchResult] = candidates.compactMap { document in
            let score = searchScore(for: document)
            guard score.isMatch else { return nil }
            return DocumentSearchResult(document: document, score: score)
        }
        return scored.sorted { $0.score.totalMatchCount > $1.score.totalMatchCount }
    }

    /// [2026-08-16 확장, 2026-08-17 OR/점수 방식으로 재작성, 2026-08-18
    /// 성경구절 하이라이트 추가] 사용자 요청 — "상단 검색: 본문검색, 태그
    /// 검색 포함" 이후 "띄어쓰기로 나누어 단어별 OR 검색 + 매칭 많은 순
    /// 정렬(태그>파일명>본문)"까지 반영한다. 성경장절 참조 검색
    /// (`verseMentionSearchTexts`)은 단어 단위로 쪼개면 "창세기 1:3"
    /// 같은 표현 자체가 깨지므로(책 이름과 장:절 사이 공백이 의미가 있음)
    /// 예외적으로 검색어 전체 문자열을 그대로 써서 한 번만 확인하고, 걸리면
    /// 본문(content) 점수에 1을 더한다 — 성경구절 언급도 결국 문서 본문에서
    /// 추출된 것이라 본문 갈래로 분류했다. 카테고리 이름/관련 성경 장 라벨은
    /// 예전부터 파일명과 같은 자리(짧은 제목성 메타데이터)에 있었으므로 그대로
    /// 파일명 점수에 합산한다.
    private func searchScore(for document: SourceDocument) -> DocumentSearchScore {
        let words = searchWords
        guard !words.isEmpty else { return .empty }

        let tagNames = (document.documentTags ?? []).compactMap { $0.tag?.name }
        let tagCount = words.filter { word in
            tagNames.contains { $0.localizedCaseInsensitiveContains(word) }
        }.count
        // [2026-08-17 추가] "태그가 일치가 되면 ... 태그명을 뱃지형식으로
        // 보여줄것" — 실제로 매칭된 태그 "이름"만 순서·중복 없이 골라 둔다
        // (위 `tagCount`는 "몇 개의 검색단어가 걸렸는지"라 뱃지에 쓸 태그
        // 이름 목록과는 다른 숫자다).
        var seenTagNames = Set<String>()
        let matchedTagNames = tagNames.filter { name in
            words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
        }

        var titleFields = [document.originalFilename]
        if let category = document.category { titleFields.append(category.name) }
        if let ref = document.relatedChapterRef { titleFields.append(chapterLabel(for: ref)) }
        let filenameCount = words.filter { word in
            titleFields.contains { $0.localizedCaseInsensitiveContains(word) }
        }.count

        let lines = (document.documentTexts ?? []).sorted {
            $0.pageNumber != $1.pageNumber ? $0.pageNumber < $1.pageNumber : $0.lineIndex < $1.lineIndex
        }

        // [2026-08-18 추가] 사용자 요청 — "성경장절 검색시 ... 창1:3으로 검색
        // -> 창1:1-5 의 텍스트 강조가 되어야 함." 타이핑한 단어 그대로가
        // 아니라, 이 문서에서 실제로 겹친 성경구절의 "원문 표현"
        // (`VerseMention.searchText`, 예: "창1:1~5")도 검색/강조 대상에
        // 합친다 — 그래야 검색어와 문서 표기가 글자 그대로 다를 때도(약어↔
        // 전체이름, 범위 포함 등) 실제로 해당 텍스트를 찾아 강조할 수 있다.
        // 검색어로 타이핑한 단어(`words`)와 합쳐 아래 한 루프에서 동일하게
        // 처리한다 — 중복이 섞여 있으면 같은 텍스트를 두 번 세게 되므로
        // 대소문자 무시 기준으로 중복 제거한다.
        let verseTerms = verseMentionSearchTexts(for: document)
        var seenTerms = Set<String>()
        let allTerms = (words + verseTerms).filter { seenTerms.insert($0.lowercased()).inserted }

        // [2026-08-17 갱신] 검색단어(+성경구절 원문 표현)별로 "본문에 몇 번
        // 나오는지"(count)와 "첫 등장 위치에서 그 단어 + 뒤 9자"(excerpt,
        // "10자 미만" 요구사항 — 단어 자체 뒤에 최대 9글자만 더 붙인다)를
        // 함께 구한다. 여러 줄에 걸쳐 셀 수 있게 줄 단위로 다시 훑는다 —
        // `range(of:options:.caseInsensitive)`를 줄 하나 안에서 반복 탐색하는
        // 원리는 `DocumentRowView.highlightedText`와 동일하다(원본 문자열
        // 위에서 바로 대소문자 무시 검색 — lowercased()로 만든 별도 문자열의
        // 인덱스를 재사용하지 않는 이유도 같다).
        var occurrenceCounts: [String: Int] = [:]
        var firstExcerpts: [String: String] = [:]
        for line in lines {
            let text = line.lineText
            for term in allTerms where !term.isEmpty {
                var searchRange = text.startIndex..<text.endIndex
                while let found = text.range(of: term, options: [.caseInsensitive], range: searchRange) {
                    occurrenceCounts[term, default: 0] += 1
                    if firstExcerpts[term] == nil {
                        let tailEnd = text.index(found.upperBound, offsetBy: 9, limitedBy: text.endIndex) ?? text.endIndex
                        firstExcerpts[term] = String(text[found.lowerBound..<tailEnd])
                    }
                    searchRange = found.upperBound..<text.endIndex
                }
            }
        }
        // 몇 개의 "서로 다른" 검색어(타이핑 단어 + 성경구절 표현)가 본문에서
        // 걸렸는지(정렬용 — 개별 등장 횟수가 아니다). `verseTerms`가 실제
        // 줄에서 못 찾아졌더라도(이론상 있을 수 없지만, 방어적으로) 성경구절
        // 매칭 자체는 이미 확정된 사실이라 최소 1은 반영한다.
        var contentCount = occurrenceCounts.keys.count
        if !verseTerms.isEmpty && verseTerms.allSatisfy({ occurrenceCounts[$0] == nil }) {
            contentCount += 1
        }

        // "(xx 회 일치)"에 쓰는 숫자 — 본문에서 검색어(+성경구절 표현)들이 총
        // 몇 번 등장했는지(등장 횟수의 합). 정렬 기준인 `totalMatchCount`
        // (태그/파일명 포함, "서로 다른 단어" 개수)와는 의도적으로 다른 숫자다.
        let bodyOccurrenceSum = occurrenceCounts.values.reduce(0, +)
        let bodyExcerpt = Self.buildContentSnippet(words: allTerms, excerpts: firstExcerpts)
        return DocumentSearchScore(
            tagCount: tagCount, filenameCount: filenameCount, contentCount: contentCount,
            bodyExcerpt: bodyExcerpt, bodyOccurrenceSum: bodyOccurrenceSum, matchedTagNames: matchedTagNames,
            highlightKeywords: allTerms
        )
    }

    /// [2026-08-17 세 번째 정정] 사용자 요청 — "각 문자열 뒤에 검색된 횟수
    /// (xx) 숫자는 지울것." 조각마다 붙이던 "(개수)"를 없애고, 검색어에 등장한
    /// 순서 그대로 "단어+뒤 9자" 발췌만 " ... "로 이어붙인다. 결과가 70자를
    /// 넘으면 70자에서 잘라 말줄임표(…)를 붙인다 — "총 70자를 넘지 않도록"
    /// 요구사항을 "70자 이하"로 해석했다(잘렸다는 걸 알 수 있게 표시).
    private static func buildContentSnippet(words: [String], excerpts: [String: String]) -> String? {
        let segments = words.compactMap { excerpts[$0] }
        guard !segments.isEmpty else { return nil }
        let joined = segments.joined(separator: " ... ")
        guard joined.count > 70 else { return joined }
        let cutIndex = joined.index(joined.startIndex, offsetBy: 70)
        return String(joined[..<cutIndex]) + "…"
    }

    /// [2026-08-17 추가] 사용자 요청 4가지 조건을 모두 `BibleReferenceExtractor`
    /// 하나로 충족한다 — 그 파서가 이미 다음을 다 하고 있기 때문에 새로 구현할
    /// 필요가 없었다:
    /// - 띄어쓰기 무시: 정규식 자체가 책 이름과 장/절 사이 공백을 `\s*`로 허용.
    /// - 약어 ↔ 전체 이름 상호 검색: `Book.abbreviation + [Book.nameKo]`를 모두
    ///   같은 후보 형태(forms) 목록에 넣고 정규식 하나로 매칭하므로, 검색어를
    ///   "약어"로 쓰든 "전체 이름"으로 쓰든, 문서 본문에 어느 쪽으로 적혀 있든
    ///   같은 (bookId, chapter, verse) 좌표로 정규화된다.
    /// - 범위 포함 검색: 문서 쪽 인덱싱(`BibleReferenceIndexingService.
    ///   reindexDocument`)이 이미 "창1:1~5" 같은 범위를 절 하나하나로 펼쳐서
    ///   (`expandRange`) `VerseMention`에 저장해 두므로, 검색어가 그 범위 안의
    ///   절 하나("창세기 1:3")만 가리켜도 좌표가 정확히 일치한다. 반대로 검색어
    ///   자체가 범위여도(예: "창1:1~3") 마찬가지로 펼쳐진 뒤 겹치는 좌표가 있는지
    ///   비교한다.
    ///
    /// 좌표 비교 시 장 번호까지만 적고 절이 없는 쪽("창세기 1장")은 그 장의 어느
    /// 절과도 일치하는 것으로 본다 — `relatedChapterRef` 필터가 이미 장 단위로만
    /// 비교하는 것과 같은 원칙(더 넓은 쪽이 이긴다).
    ///
    /// [2026-08-18 확장] 사용자 요청 — "성경장절 검색시 검색에 관련된 연구문서의
    /// 성경 장절은 형광펜강조(범위에 포함된 성경구절인 경우 범위 텍스트를
    /// 강조)." 원래는 일치 여부(Bool)만 돌려줬는데, 이제 하이라이트할 실제
    /// 문서 원문 표현(`VerseMention.searchText`, 예: "창1:1~5")이 필요해져
    /// `[String]`(겹치는 멘션들의 원문 표현, 중복 제거)을 돌려주도록 확장했다
    /// — 빈 배열이면 예전의 "매칭 안 됨"과 같다. 이 문서의 좌표와 겹치는
    /// `VerseMention`을 찾는 로직 자체는 그대로다.
    private func verseMentionSearchTexts(for document: SourceDocument) -> [String] {
        let queryMatches = searchVerseQueryMatches
        guard !queryMatches.isEmpty else { return [] }
        let docId = document.id.uuidString
        var seen = Set<String>()
        return documentVerseMentions
            .filter { mention in
                guard mention.sourceId == docId else { return false }
                return queryMatches.contains { query in
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

    /// `searchScore(for:)`가 문서마다 반복 호출되는 동안 같은 검색어를 매번
    /// 다시 정규식으로 파싱하지 않도록 한 번만 계산해 둔다(`BibleReferenceExtractor.
    /// extract`는 정규식 컴파일 자체는 캐싱하지만 매칭 스캔은 호출마다 다시
    /// 돈다) — `filteredResults`가 렌더링 한 번에 이 값을 여러 번 참조해도
    /// SwiftUI가 뷰 갱신마다 새로 계산하는 건 다른 필터 조건(태그/본문 스캔)과
    /// 같은 수준이라 별도 캐싱 레이어까지는 두지 않았다.
    private var searchVerseQueryMatches: [BibleReferenceExtractor.Match] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return BibleReferenceExtractor.extract(from: trimmed)
    }

    private func matchesCategoryFilter(_ document: SourceDocument) -> Bool {
        switch categoryFilter {
        case .all:
            return true
        case .uncategorized:
            return document.relatedChapterRef == nil && document.category == nil
        case .chapter(let ref):
            return document.relatedChapterRef == ref
        case .custom(let id):
            return document.category?.id == id
        }
    }

    /// 탭한 문서를 맨 앞으로 오도록 검수 대기 문서 목록을 회전시켜 큐를 만든다 —
    /// 목록 순서 자체는 그대로 유지하되(최근 업로드순), 사용자가 탭한 문서부터
    /// 시작해서 나머지 대기 문서를 이어서 보여주는 것이 "저장 후 다음" 취지에
    /// 맞다고 판단했다.
    private func presentOCRReviewQueue(startingAt document: SourceDocument) {
        guard let viewModel else { return }
        let pending = queriedDocuments.filter { viewModel.hasPendingOCRReview($0) }
        guard let startIndex = pending.firstIndex(where: { $0.persistentModelID == document.persistentModelID }) else {
            ocrReviewQueue = [document]
            return
        }
        ocrReviewQueue = Array(pending[startIndex...]) + Array(pending[..<startIndex])
    }

    // MARK: - 드롭존(진입점 2, 3)

    private func dropZone(viewModel: DocumentsViewModel) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            // 진입점 3: 드롭존 클릭 — 같은 fileImporter를 그대로 연다.
            Text(allowsDragAndDrop ? "드래그해서 파일을 놓거나 클릭해서 업로드" : "탭해서 업로드")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(allowsHWP ? "hwp · hwpx · doc · pdf · 이미지" : "doc · pdf · 이미지 (아이폰은 hwp 업로드 미지원)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
        .contentShape(Rectangle())
        .onTapGesture { isFileImporterPresented = true }
        .modifier(DropZoneModifier(isEnabled: allowsDragAndDrop, isTargeted: $isDropTargeted) { url in
            beginUpload(urls: [url])
        })
    }

    private func setUpIfNeeded() {
        guard viewModel == nil else { return }
        let vm = DocumentsViewModel(modelContext: modelContext)
        vm.onAppear()
        viewModel = vm
    }

    // MARK: - 업로드 시 관련 성경 장 입력 (2026-08-08 추가)

    /// 업로드 3가지 진입점이 공통으로 호출 — 곧바로 업로드하지 않고 확인 시트를
    /// 띄운다. 시트의 책/장 선택 기본값은 "지금 성경 조회(S1)에서 보고 있던
    /// 위치"(`LastBiblePositionTracker`)로 맞춰 둔다 — 대부분 문서를 올릴 때
    /// 방금 읽던 본문과 관련이 있을 가능성이 높다는 가정.
    private func beginUpload(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let bookId = LastBiblePositionTracker.shared.bookId, let book = BooksProvider.shared.book(id: bookId) {
            chapterLinkBook = book
            chapterLinkChapter = LastBiblePositionTracker.shared.chapter ?? 1
        }
        // [2026-08-18 추가] 이전 업로드 배치에서 고른 카테고리가 이번 배치로
        // 새어 들어가지 않도록 매번 초기화 — 시트가 다시 뜰 때마다 새로 골라야
        // 한다(카테고리 강제 요청 취지 그대로).
        pendingUploadCategory = nil
        pendingUploadURLs = urls
    }

    private func finishPendingUpload(relatedChapter: BibleChapterRef?) {
        let urls = pendingUploadURLs
        let category = pendingUploadCategory
        pendingUploadURLs = []
        pendingUploadCategory = nil
        viewModel?.upload(urls: urls, relatedChapter: relatedChapter, category: category)
    }
}

/// [2026-08-08 추가, 2026-08-18 카테고리 강제 추가] 업로드 확인 시트 — "이
/// 문서(들)는 어느 장과 관련 있는지"를 물어본다. 관련 성경 장 자체는 여전히
/// 선택 사항이라 "건너뛰기"로 바로 업로드할 수 있다(사용자 요청 자체가 "입력받을
/// 수 있도록"이지 "반드시 입력해야"가 아니었음). 반면 카테고리는 사용자 요청 —
/// "연구문서 업로드시 반드시 카테고리 입력을 강제할 것. (선택하거나 개인이
/// 입력하거나)" — 에 따라 두 경로(건너뛰기/이 장으로 업로드) 모두 카테고리를
/// 고르기 전에는 버튼을 누를 수 없다.
private struct UploadChapterLinkSheet: View {
    @Binding var book: Book
    @Binding var chapter: Int
    let fileCount: Int
    /// [2026-08-18 추가] 기존에 만들어 둔 카테고리 목록 — `DocumentRowView.
    /// categoryMenu`와 같은 Menu 구성(기존 분류 선택 + "새 분류…")을 그대로
    /// 재사용한다.
    let categories: [ImageCategory]
    @Binding var selectedCategory: ImageCategory?
    /// [2026-08-18 추가] "새 분류…" 입력을 실제 `ImageCategory`로 만드는 동작 —
    /// 이 시트는 `DocumentsViewModel`을 직접 모르므로(부모가 옵셔널 바인딩으로만
    /// 들고 있음, 다른 화면들의 리졸버 클로저 주입 패턴과 동일) 부모가 만든
    /// 클로저를 그대로 받는다.
    let onCreateCategory: (String) -> ImageCategory?
    let onSkip: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isNewCategoryInputPresented = false
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            // [2026-08-15 2차 UI/UX 수정] 사용자 재보고 — 이전 `.formStyle(.grouped)`
            // 적용 후에도 검색어 입력창의 placeholder("예:창세기1, 요3")가 실제
            // 입력 상자 안이 아니라 옆으로 밀려나 별도 글자처럼 보였다. 근본 원인 —
            // `Form`/`Section` 행(row) 레이아웃이 자체적으로 자식 컨트롤(특히
            // `.textFieldStyle(.roundedBorder)`처럼 스타일을 직접 지정한 TextField)의
            // 크기를 다시 계산하려 들면서, 안에 있던 `BookChapterPicker`의 좁은
            // `HStack`(버튼+검색창+버튼)과 충돌해 검색창의 실제 레이아웃 폭이
            // placeholder 글자 너비보다 작게 줄어들었다 — 그래서 placeholder
            // 텍스트가 그 좁은 상자 밖으로 삐져나와 보인 것이다(SwiftUI는 기본적으로
            // 넘치는 텍스트를 잘라내지 않는다). `Form` 자체를 걷어내고 일반
            // `VStack`으로 바꿔 이 행 크기 재계산 충돌을 원천적으로 없앴다 —
            // `BookChapterPicker`가 원래 문제없이 쓰이는 다른 화면(성경 조회 상단
            // 툴바)도 전부 `Form` 밖이라는 점과 일치한다.
            VStack(alignment: .leading, spacing: 16) {
                // [2026-08-18 추가] 사용자 요청 — "연구문서 업로드시 반드시
                // 카테고리 입력을 강제할 것. (선택하거나 개인이 입력하거나)."
                // 이 시트에서 가장 먼저 채워야 하는 항목이라 관련 성경 장보다
                // 위에 둔다.
                VStack(alignment: .leading, spacing: 4) {
                    Text("카테고리").font(.body).foregroundStyle(.secondary)
                    Menu {
                        ForEach(categories) { category in
                            Button(category.name) { selectedCategory = category }
                        }
                        if !categories.isEmpty { Divider() }
                        Button("새 분류…") { isNewCategoryInputPresented = true }
                    } label: {
                        HStack {
                            Text(selectedCategory?.name ?? "카테고리를 선택하세요")
                                .foregroundStyle(selectedCategory == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.body)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    }
                    .menuStyle(.borderlessButton)
                }

                Divider()

                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: book,
                    selectedChapter: chapter
                ) { newBook, newChapter in
                    book = newBook
                    chapter = newChapter
                }

                // [2026-08-15 2차 UI/UX 수정] 사용자 요청 — "하단 설명문구 - 시스템
                // 기본 폰트, 일반 크기로." `RootView`의 `.appDefaultFont()`(커스텀
                // Paperlogy)를 명시적으로 `.font(.body)`로 되돌린다.
                Text("업로드할 파일 \(fileCount)개와 관련된 성경 장을 지정하면, 성경 조회(S1) 화면에서 이 문서를 바로 찾아볼 수 있습니다. 나중에 문서 목록에서 다시 바꾸거나 해제할 수 있습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("관련 성경 장")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // [2026-08-18 수정] 카테고리를 고르기 전엔 "건너뛰기"도 막는다
                    // — "건너뛰기"는 관련 성경 장만 생략하는 버튼이지, 카테고리
                    // 강제 자체를 우회하는 경로가 아니다.
                    Button("건너뛰기") {
                        onSkip()
                        dismiss()
                    }
                    .disabled(selectedCategory == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("이 장으로 업로드") {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(selectedCategory == nil)
                }
            }
            // [2026-08-18 추가] `DocumentRowView.categoryMenu`와 같은 패턴 —
            // "새 분류…" 선택 시 이름을 입력받아 `onCreateCategory`로 실제
            // `ImageCategory`를 만들고 곧바로 선택 상태로 반영한다.
            .alert("새 분류", isPresented: $isNewCategoryInputPresented) {
                TextField("분류 이름", text: $newCategoryName)
                Button("취소", role: .cancel) { newCategoryName = "" }
                Button("추가") {
                    if let category = onCreateCategory(newCategoryName) {
                        selectedCategory = category
                    }
                    newCategoryName = ""
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 320)
        #endif
    }
}

/// macOS/iPadOS에서만 `.onDrop`을 실제로 붙이고, 아이폰(드래그앤드롭 OS 미지원)에서는
/// 아무것도 하지 않는 조건부 modifier. `allowsDragAndDrop`으로 매번 분기 코드를
/// 반복하지 않기 위해 분리했다.
private struct DropZoneModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    let onURL: (URL) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in
                            onURL(url)
                        }
                    }
                }
                return true
            }
        } else {
            content
        }
    }
}

// MARK: - 목록 행

private struct DocumentRowView: View {
    let document: SourceDocument
    /// [2026-08-17 추가, 이후 성경장절 검색까지 포함하도록 확장] 사용자 요청
    /// — "검색결과 일치하는 텍스트는 형광펜 강조처리." + "성경장절 검색시
    /// 검색에 관련된 연구문서의 성경 장절은 형광펜강조(범위에 포함된 성경구절인
    /// 경우 범위 텍스트를 강조) 예) 창1:3으로 검색 -> 창1:1-5 의 텍스트 강조가
    /// 되어야 함." 타이핑한 검색어뿐 아니라, 부모(`searchScore`)가
    /// `VerseMention`으로 풀어낸 실제 문서 내 성경장절 원문("창1:1-5" 등)도
    /// 함께 담긴다. 검색 중이 아니면(빈 배열) 하이라이트 없이 평범한 텍스트로
    /// 보인다 — `highlightedText(_:keywords:)` 참고.
    let highlightKeywords: [String]
    /// [2026-08-17 추가, 세 차례 형식 변경] 사용자 요청 — "본문 일치는 파일명
    /// 하단에 일치하는 단어 기준 그 라인을 표시할 것" → "일치 단어 뒤 10자
    /// 미만, ...으로 구분, 70자 이내, 일치개수 표시" → "(xx 회 일치)는 조각별
    /// 개수의 합" → "각 문자열 뒤 (xx) 숫자는 지울것." 최종 형태 — 단어별
    /// 개수 표기 없는 순수 발췌문("태초에 하나 ... 창조하시니라")만 담는다.
    /// 본문에서 걸리지 않았으면 nil.
    let bodyExcerpt: String?
    /// "(xx 회 일치)" 접두어에 쓰는 숫자 — 본문에서 검색단어들이 총 몇 번
    /// 등장했는지(부모 `DocumentsHomeView.searchScore`가 계산). `bodyExcerpt`가
    /// nil이면(본문 매치 자체가 없으면) 이 값은 안 쓰인다.
    let bodyOccurrenceSum: Int
    /// [2026-08-17 추가] 사용자 요청 — "태그가 일치가 되면 (xx 회 일치) 뒤
    /// 본문 앞에 태그명을 뱃지형식으로 보여줄것." 실제로 검색어와 일치한 태그
    /// 이름들 — 비어 있으면 뱃지를 그리지 않는다.
    let matchedTagNames: [String]
    let viewModel: DocumentsViewModel
    /// [2026-08-07 추가] 검수 대기 중인 문서를 탭했을 때 부모(DocumentsHomeView)에게
    /// "이 문서부터 시작하는 검수 큐를 열어 달라"고 알린다.
    let onOpenOCRReview: (SourceDocument) -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var isCategoryInputPresented = false
    @State private var categoryInput = ""
    /// [2026-08-08 추가] 업로드 시 건너뛰었거나 나중에 바꾸고 싶을 때 쓰는 편집
    /// 시트 상태. `chapterLinkBook`은 시트를 열 때 `document.relatedChapterRef`
    /// (있으면) 또는 마지막으로 보던 성경 위치(없으면)로 채운다.
    @State private var isChapterLinkEditorPresented = false
    @State private var chapterLinkBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var chapterLinkChapter: Int = 1

    /// [2026-08-18 신설] `allowsDragAndDrop`/`allowsHWP`와 같은 패턴 —
    /// `UIDevice`는 iOS에서만 존재하므로 반드시 `#if os(iOS)`로 감싼다(맥 빌드
    /// 깨짐 방지). 아이폰만 다중 씬(멀티 윈도우)을 지원하지 않아 `openWindow`
    /// 대신 `NavigationLink`로 이 탭의 NavigationStack 안에 밀어 넣어야 한다 —
    /// 맥/아이패드는 기존 `openWindow` 그대로.
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        // [2026-08-15 추가, 크래시 fix] 사용자 보고 — `SourceDocument.conversionStatus.getter`
        // fatal error(`DocumentRowView.statusBadge.getter`에서 발생, 이 행의
        // `document`가 이미 지워진 객체를 가리키고 있었다). `List(queriedDocuments)`
        // (DocumentsHomeView 상단 `@Query` 참고)가 이미 "지워진 문서는 배열에서
        // 빠진다"를 보장하는데도 이 크래시가 남아 있었다는 건, SwiftUI가 배열
        // 변경을 반영해 이 행을 트리에서 완전히 제거하기 "직전"의 한 프레임 동안
        // 이 `DocumentRowView` 인스턴스(그리고 그 안에 값으로 박혀 있는 옛
        // `document` 참조)가 다른 이유로(예: 같은 화면의 다른 상태 변화, 다른
        // 창에서의 삭제) 한 번 더 재계산될 수 있다는 뜻이다 — `@Query`로도 완전히
        // 막지 못하는, 한 프레임짜리 경쟁 상태(race)다.
        //
        // `PersistentModel.modelContext`는 사용자가 선언한 `@Model` 저장
        // 프로퍼티(`conversionStatus` 등)와 달리 SwiftData 프레임워크가 직접
        // 관리하는 "이 객체가 지금 어떤 컨텍스트에 속해 있는지" 플래그다 — 객체가
        // 컨텍스트에서 지워지고 저장되면 nil이 된다. 이 값 자체를 읽는 것은
        // (다른 저장 프로퍼티와 달리) 지워진 객체에서도 안전하다 — 정확히 "이
        // 객체를 더 건드려도 되는지" 사전 검사 용도로 Apple이 제공하는 것이다.
        // 그래서 다른 프로퍼티(`originalFilename`, `conversionStatus` 등)를 읽기
        // 전에 이걸로 먼저 걸러낸다.
        if document.modelContext == nil {
            EmptyView()
        } else {
            documentRow
        }
    }

    @ViewBuilder
    private var documentRow: some View {
        // [2026-08-07 수정] 이전엔 NavigationLink 하나가 검수 대기/일반 문서 둘 다
        // 같은 방식(메인 창 안 푸시)으로 열었다. 이제 둘의 진입 방식 자체가
        // 다르다 — 검수 대기는 시트+큐(S7), 그 외엔 별도 창(S6, Preview.app
        // 패턴) — 그래서 NavigationLink 대신 분기하는 Button 하나로 바꿨다.
        //
        // [2026-08-18 추가, 실기기 크래시 fix] 사용자 보고 — 아이폰 실기기에서
        // "Unable to open a window when the app does not support multiple
        // scenes" 런타임 에러. 원인 — 아이패드/맥과 달리 아이폰은 다중
        // 씬(멀티 윈도우)을 지원하지 않아 `openWindow`가 새 창을 못 연다(S6
        // 도입 당시 README에 "실기기 검증 필요"로 이미 위험 표시해 둔
        // 부분). 그래서 아이폰에서만 `openWindow` 대신 이 탭의 NavigationStack
        // 안으로 `NavigationLink(value:)`로 밀어 넣는다 — `.navigationDestination
        // (for: PersistentIdentifier.self)`는 이 파일 하단에 등록.
        Group {
            if viewModel.hasPendingOCRReview(document) {
                Button {
                    onOpenOCRReview(document)
                } label: {
                    documentRowLabel
                }
            } else if isPhoneIdiom {
                NavigationLink(value: document.persistentModelID) {
                    documentRowLabel
                }
            } else {
                Button {
                    openWindow(id: "document-viewer", value: document.persistentModelID)
                } label: {
                    documentRowLabel
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if document.conversionStatus == .failedNeedsManual {
                Button {
                    viewModel.retry(document)
                } label: {
                    Label("재시도", systemImage: "arrow.clockwise")
                }
            }
            // [2026-08-08 추가] 업로드 시 건너뛰었거나 잘못 골랐을 때를 위한
            // 재설정 경로 — categoryMenu(이미지 분류)와 같은 위치 원칙.
            Button {
                presentChapterLinkEditor()
            } label: {
                Label(
                    document.relatedChapterRef == nil ? "관련 성경 장 설정…" : "관련 성경 장 변경…",
                    systemImage: "book.closed"
                )
            }
            if document.relatedChapterRef != nil {
                Button(role: .destructive) {
                    viewModel.setRelatedChapter(nil, for: document)
                } label: {
                    Label("관련 성경 장 해제", systemImage: "book.closed")
                }
            }
            // [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드 앱처럼
            // 기능을 추가할 것. 고정됨." 사이드바 "고정됨" 섹션에 넣고 뺄 수 있는
            // 토글 — `categoryMenu`/관련 성경 장 재설정과 같은 위치 원칙(컨텍스트
            // 메뉴에서 이산적 액션으로 즉시 반영).
            Button {
                viewModel.togglePin(document)
            } label: {
                Label(document.isPinned ? "고정 해제" : "고정", systemImage: document.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                viewModel.delete(document)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .sheet(isPresented: $isChapterLinkEditorPresented) {
            ChapterLinkEditorSheet(
                book: $chapterLinkBook,
                chapter: $chapterLinkChapter,
                onSave: {
                    viewModel.setRelatedChapter(BibleChapterRef(bookId: chapterLinkBook.bookId, chapter: chapterLinkChapter), for: document)
                }
            )
        }
    }

    /// [2026-08-18 신설] `documentRow`의 Button/NavigationLink 두 경로가 같은
    /// 라벨을 쓰도록 분리 — 위 iPhone 런타임 크래시 fix에서 라벨 중복을
    /// 피하려고 뺐다.
    private var documentRowLabel: some View {
        HStack {
                Image(systemName: formatIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    // [2026-08-17 수정, 2026-08-18 성경장절 강조까지 확장] 사용자
                    // 요청 — "검색결과 일치하는 텍스트는 형광펜 강조처리." 검색
                    // 중이 아니면(highlightKeywords 비어 있음) highlightedText가
                    // 그냥 평범한 Text를 돌려줘 기존과 동일하다.
                    highlightedText(document.originalFilename, keywords: highlightKeywords)
                    HStack(spacing: 4) {
                        Text(document.originalFormat.rawValue.uppercased())
                        // [2026-08-08 추가] 관련 성경 장이 설정돼 있으면 목록에서도
                        // 바로 보이게 — 안 그러면 문서가 몇 개만 있어도 어떤 게
                        // 어느 장과 연결됐는지 매번 컨텍스트 메뉴를 열어봐야 한다.
                        if let label = relatedChapterLabel {
                            Text("· \(label)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    // [2026-08-17 추가, 세 차례 형식 변경] 사용자 요청 — "본문
                    // 일치는 파일명 하단에 ... 표시" → 단어별 발췌+개수+70자
                    // 캡 → "(xx 회 일치)는 조각 개수 합" → "각 조각 뒤 (xx)는
                    // 지우고" → "태그 일치 시 (xx 회 일치) 뒤 본문 앞에 태그명
                    // 뱃지." 최종 레이아웃: "(N회 일치)" 텍스트 + (태그 일치
                    // 시) 태그 뱃지들 + 발췌 본문(하이라이트) 순서로 한 줄에
                    // 나열한다. 본문 매치가 아예 없으면(bodyExcerpt == nil)
                    // 이 줄 자체를 그리지 않는다 — 태그만 일치하고 본문은
                    // 안 걸린 경우는 뱃지를 보여줄 자리가 없어 표시하지 않는다
                    // (요청 문구가 "(xx 회 일치) 뒤 본문 앞에"라 본문 줄의
                    // 존재를 전제하고 있다고 해석했다).
                    if let bodyExcerpt {
                        HStack(spacing: 4) {
                            Text("(\(bodyOccurrenceSum)회 일치)")
                            ForEach(matchedTagNames, id: \.self) { tagName in
                                badge(tagName, color: .blue)
                            }
                            highlightedText(bodyExcerpt, keywords: highlightKeywords)
                                .lineLimit(2)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // [2026-08-16 수정] 사용자 요청 — "카테고리 기능 추가할 것."
                // 원래는 이미지(OCR 분류, 6.4)에서만 커스텀 카테고리를 붙일 수
                // 있었다 — 이제 모든 형식에 다 허용한다(관련 성경 장과는 별개
                // 필드라 둘 다 붙여도 된다 — 예: "창세기 1장" + "설교 자료").
                categoryMenu

                statusBadge
            }
    }

    /// 컨텍스트 메뉴에서 시트를 열 때 기본값을 채운다 — 이미 연결돼 있으면 그
    /// 값, 없으면 마지막으로 보던 성경 위치(업로드 시트와 같은 원칙).
    private func presentChapterLinkEditor() {
        if let ref = document.relatedChapterRef, let book = BooksProvider.shared.book(id: ref.bookId) {
            chapterLinkBook = book
            chapterLinkChapter = ref.chapter
        } else if let bookId = LastBiblePositionTracker.shared.bookId, let book = BooksProvider.shared.book(id: bookId) {
            chapterLinkBook = book
            chapterLinkChapter = LastBiblePositionTracker.shared.chapter ?? 1
        }
        isChapterLinkEditorPresented = true
    }

    private var relatedChapterLabel: String? {
        guard let ref = document.relatedChapterRef, let book = BooksProvider.shared.book(id: ref.bookId) else { return nil }
        return "\(book.nameKo) \(ref.chapter)장"
    }

    /// [2026-08-17 신설] 사용자 요청 — "검색결과 일치하는 텍스트는 형광펜
    /// 강조처리." `text` 안에서 `keywords`(검색단어들) 중 하나라도 대소문자
    /// 구분 없이 나타나는 모든 구간에 노란 배경(형광펜 느낌)을 입힌다.
    ///
    /// ⚠️ [구현 선택] `text.range(of:options:.caseInsensitive)`를 원본
    /// `text`(같은 String 인스턴스) 위에서 그대로 반복 탐색한다 — 처음엔
    /// 별도로 `text.lowercased()`를 만들어 그 위에서 찾는 방식을 생각했지만,
    /// `lowercased()`가 만든 새 String은 `String.Index`가 원본과 호환된다는
    /// 보장이 없어(글자 수가 같아 보여도 다른 String 인스턴스의 인덱스는
    /// 서로 바꿔 쓸 수 없다) 안전하지 않다. `.caseInsensitive` 옵션을 쓰면
    /// 원본 문자열 위에서 바로 대소문자 무시 검색이 되므로 이 문제 자체가
    /// 생기지 않는다.
    private func highlightedText(_ text: String, keywords: [String]) -> Text {
        let trimmedKeywords = keywords.filter { !$0.isEmpty }
        guard !trimmedKeywords.isEmpty else { return Text(text) }

        var attributed = AttributedString(text)
        for keyword in trimmedKeywords {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: keyword, options: [.caseInsensitive], range: searchRange) {
                if let attrRange = Range(found, in: attributed) {
                    attributed[attrRange].backgroundColor = .yellow.opacity(0.55)
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return Text(attributed)
    }

    private var formatIcon: String {
        switch document.originalFormat {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .hwp, .hwpx: return "doc.text"
        case .doc, .docx, .pages: return "doc" // [2026-08-16 docx/pages 추가] .doc과 같은 아이콘 재사용
        }
    }

    // MARK: - 상태 배지(14.5 시맨틱 색상: 대기/추출중=주황, 완료=초록, 실패=빨강)

    @ViewBuilder
    private var statusBadge: some View {
        if viewModel.hasPendingOCRReview(document) {
            badge("검수 대기", color: .orange)
        } else {
            switch document.conversionStatus {
            case .pending:
                badge("대기", color: .orange)
            case .convertingNative:
                badge("추출 중", color: .orange)
            case .converted:
                if document.indexStatus == .indexed {
                    badge("인덱싱 완료", color: .green)
                } else {
                    badge("추출 중", color: .orange)
                }
            case .failedNeedsManual:
                badge("실패", color: .red)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - 카테고리(원래 6.4 이미지 분류였다가, 2026-08-16 모든 형식으로 확장)

    private var categoryMenu: some View {
        Menu {
            Button("미분류") { viewModel.setCategory(nil, for: document) }
            ForEach(viewModel.categories) { category in
                Button(category.name) { viewModel.setCategory(category, for: document) }
            }
            Divider()
            Button("새 분류…") { isCategoryInputPresented = true }
        } label: {
            Text(document.category?.name ?? "분류 없음")
                .font(.caption)
        }
        .alert("새 분류", isPresented: $isCategoryInputPresented) {
            TextField("분류 이름", text: $categoryInput)
            Button("취소", role: .cancel) { categoryInput = "" }
            Button("추가") {
                if let category = viewModel.createCategory(named: categoryInput) {
                    viewModel.setCategory(category, for: document)
                }
                categoryInput = ""
            }
        }
    }
}

/// [2026-08-08 추가] 문서 목록 행 컨텍스트 메뉴 "관련 성경 장 설정…/변경…"에서
/// 쓰는 편집 시트. 업로드 확인 시트(`UploadChapterLinkSheet`)와 달리 "건너뛰기"가
/// 없다 — 이미 업로드된 문서 하나를 다루는 것이라 "취소/저장"이 더 맞는 문구다.
private struct ChapterLinkEditorSheet: View {
    @Binding var book: Book
    @Binding var chapter: Int
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // [2026-08-15 2차 UI/UX 수정] `UploadChapterLinkSheet`와 같은 이유(그
            // 파일 주석 참고) — `Form`/`Section` 행 레이아웃이 `BookChapterPicker`의
            // 검색창 placeholder를 상자 밖으로 밀어내는 문제가 있어 `Form` 자체를
            // 걷어내고 일반 `VStack`으로 바꿨다.
            VStack(alignment: .leading, spacing: 16) {
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: book,
                    selectedChapter: chapter
                ) { newBook, newChapter in
                    book = newBook
                    chapter = newChapter
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("관련 성경 장")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 260)
        #endif
    }
}
