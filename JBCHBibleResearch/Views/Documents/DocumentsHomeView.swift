//
//  DocumentsHomeView.swift
//  JBCHBibleResearch
//
//  연구문서 업로드 화면(S5). 업로드 진입점(툴바 `+`, 드래그앤드롭 존, 드롭존 클릭,
//  iOS 사진 보관함)이 모두 `DocumentsViewModel.upload(urls:)` 하나를 공유한다.
//  사진 보관함 선택(`PhotosPickerItem`)은 파일 URL이 아니라서 `handlePickedPhotos`가
//  원본 데이터를 임시 파일로 써서 URL로 바꾼 뒤 `beginUpload(urls:)`에 넘긴다.
//  `PhotosPicker`(PhotosUI)는 iOS/iPadOS 전용이라 macOS는 파일 선택기만 연다.
//
//  ⚠️ 아이폰(`userInterfaceIdiom == .phone`)에서만 `supportedContentTypes(allowHWP:)`에
//  `false`를 넘겨 hwp를 막는다(RootView.swift와 같은 런타임 분기). 아이패드/맥은 hwp 선택 허용.
//
//  ⚠️ 여러 파일을 한꺼번에 드롭하면 `NSItemProvider`별 URL이 resolve되는 대로 하나씩 업로드한다
//  (일괄 처리 안 함) — 완료 콜백이 메인 액터 밖 큐에서 오는 문제(Swift 6 엄격 동시성)를 피하기
//  위한 선택이며, 모든 드롭 파일이 각자 업로드되는 최종 동작은 같다.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BibleResearchModels
#if os(iOS)
import UIKit
import PhotosUI
#endif

/// 문서 카테고리 필터. 성경 장(`relatedChapterRef`)과 커스텀 카테고리(`category`) 두 갈래를
/// 필터 하나로 묶는 화면 표시/필터링 전용 타입이다(저장은 각 필드에 따로 남는다).
private enum DocumentCategoryFilter: Hashable {
    case all
    case uncategorized
    case chapter(BibleChapterRef)
    case custom(UUID)
}

/// 시스템 내비게이션 바 배경을 테마색에 맞추는 모디파이어(테마 배경을 고르지 않았으면 아무것도 바꾸지 않는다).
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    // `Color.resolve(in:)`용 환경값. `Color(hex:)`로 만든 고정 RGB라 라이트/다크와 무관하게 같은 값이 나온다.
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        // `ToolbarPlacement.navigationBar`는 macOS에 없으므로 iOS에서만 적용한다.
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // 배경색만 바꾸면 시스템 바 아이템 색이 앱 전체 라이트/다크 모드만 따라가 어두운 테마 배경 위에서
                // 안 보일 수 있어, 배경의 WCAG 상대 휘도로 `.toolbarColorScheme`을 명시한다.
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
        } else {
            content
        }
        #elseif os(macOS)
        // macOS는 `.navigationBar` 대신 `.windowToolbar`(macOS 13+)로 창 통합 툴바 배경을 맞춘다.
        // 이 화면은 `NavigationSplitView` detail 컬럼이라 제목이 창 툴바에 그려진다.
        if let color {
            content
                .toolbarBackground(color, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .windowToolbar)
        } else {
            content
        }
        #else
        content
        #endif
    }

    private static func isDarkBackground(_ color: Color, in environment: EnvironmentValues) -> Bool {
        let resolved = color.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance < 0.5
    }
}

struct DocumentsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DocumentsViewModel?

    /// 목록 렌더링용. macOS는 설정 창 등 다른 경로에서 `SourceDocument`가 삭제돼도 이 화면이 떠 있어
    /// `viewModel.documents`(fetch 캐시)가 지워진 객체를 들고 크래시할 수 있으므로, 컨텍스트 변경을
    /// 자동 구독하는 `@Query`를 쓴다.
    @Query(sort: [SortDescriptor(\SourceDocument.uploadedAt, order: .reverse)])
    private var queriedDocuments: [SourceDocument]

    /// 문서 소스의 `VerseMention`(성경구절 인덱스) — 검색어의 성경 장절을 이미 구조화된 인덱스와 비교하기 위함.
    /// `sourceTypeRaw`는 String 저장 프로퍼티라 `#Predicate` 등호 비교가 안전하다.
    @Query(filter: #Predicate<VerseMention> { $0.sourceTypeRaw == "document" })
    private var documentVerseMentions: [VerseMention]

    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    /// 사진 보관함 선택기 표시 여부와 선택 항목(iOS/iPadOS 전용, PhotosUI).
    #if os(iOS)
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotosPickerItems: [PhotosPickerItem] = []
    #endif
    /// 업로드 URL은 곧바로 올리지 않고 여기 담아 뒀다가 관련 장 확인 시트에서 고른 뒤 업로드한다.
    /// 배치 전체에 같은 장 하나만 적용한다.
    @State private var pendingUploadURLs: [URL] = []
    @State private var chapterLinkBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var chapterLinkChapter: Int = 1
    /// 업로드 시 필수 카테고리(관련 장과 달리 건너뛸 수 없음) — nil인 동안 시트의 두 버튼이 비활성화된다.
    /// 새 배치(`beginUpload`)마다 nil로 되돌려 이전 선택이 새어 들어가지 않게 한다.
    @State private var pendingUploadCategory: ImageCategory?

    /// 공백으로 나눈 단어별 OR 검색어. 파일명/카테고리/관련 장/태그/본문/성경장절을 함께 매칭한다(`searchScore(for:)`).
    @State private var searchText: String = ""
    /// 카테고리 필터(성경 장/커스텀 카테고리) — `categoryFilterMenu` 참고.
    @State private var categoryFilter: DocumentCategoryFilter = .all
    /// "카테고리 관리" 팝오버 표시 여부(맥OS·아이패드 공통 — 아이폰은 툴바 자리가 좁아 제외).
    @State private var isCategoryManagerPresented = false
    /// `categoryManagerPanel`의 "새 카테고리" 입력창.
    @State private var newCategoryName = ""
    #if os(iOS)
    /// 아이패드 순서 변경 모드 — 켜면 행마다 위/아래 버튼이 나타난다. 팝오버가 닫히면 `.onDisappear`에서 끈다.
    /// (드래그 `List.onMove`는 아이패드에서 UIKit 배치 갱신 예외(`attempt to move both item…`)로 앱이 종료돼 쓰지 않는다.)
    @State private var isReorderingCategories = false
    #endif
    /// 테마 배경/글자색 읽기용 접근.
    private var settings: UserSettingsStore { .shared }

    /// 문서함 카드 책등 강조색을 밝은/어두운 테마에 맞게 고르기 위한 환경값
    /// (`DocumentRowView.accentSpineColor`와 같은 판정 공식 — 그 struct가 private라 공식만 옮겼다).
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// 위 두 환경값으로 "지금 실제로 보이는 배경이 어두운지" 판정 — 테마
    /// 배경이 있으면 그 배경의 WCAG 상대휘도로, 없으면 시스템 라이트/다크로.
    private var isDarkBibleBackground: Bool {
        if let bg = settings.bibleBackgroundColor {
            let resolved = bg.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            return luminance < 0.5
        }
        return colorScheme == .dark
    }

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

    /// 아이폰(카드 홈 ↔ 평면 목록 전환)과 아이패드/맥(`splitMainContent` 분할)의 레이아웃 분기 기준.
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
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
        .navigationTitle("연구 문서")
        .macSerifTitle("연구 문서")
        // 타이틀을 인라인으로 표시해 툴바 아이콘 좌측 공간 낭비를 막는다.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // 시스템 내비게이션 바 배경을 테마에 맞춘다.
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        // 아이폰 다중 씬 미지원 대응 — `documentRow`의 `NavigationLink(value:)` 목적지를 이 탭의
        // NavigationStack에 등록한다. 삭제된 문서 처리는 `DocumentViewerWindowContent`가 담당한다.
        .navigationDestination(for: PersistentIdentifier.self) { documentID in
            DocumentViewerWindowContent(documentID: documentID)
        }
        .toolbar {
            #if os(iOS)
            // 아이폰 전용 — 카테고리 필터가 "전체"가 아닐 때(문서함 카드에서 들어온 상태) 카드 홈으로 돌아가는
            // '<' 버튼. 아이패드/맥은 분할 레이아웃이 폴더 목록을 항상 보여줘 필요 없다.
            if isPhone && categoryFilter != .all {
                ToolbarItem(placement: .navigation) {
                    Button {
                        categoryFilter = .all
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                // 타이틀은 세리프체(`SpecialPurposeFonts.titleSerif`)로 표시한다.
                Text("연구 문서")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            #endif
            // 카테고리 관리 팝오버 버튼(맥OS·아이패드; 아이폰은 툴바가 좁아 제외). 예전 `.inspector`(3번째 열)는 열면 본문 폭이 줄어 NavigationSplitView 사이드바가
            // 자동으로 접혔다 펴져(창 폭 약 1215pt 이하) 팝오버로 바꿨다 — 본문/사이드바 폭에 영향이 없다.
            // `.primaryAction`이라 업로드 버튼과 함께 툴바 오른쪽 끝에 놓인다.
            if !isPhone {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCategoryManagerPresented.toggle()
                    } label: {
                        Label("카테고리 관리", systemImage: "folder.badge.gearshape")
                    }
                    .help("카테고리 생성 · 이름 변경 · 삭제 · 순서")
                    .popover(isPresented: $isCategoryManagerPresented, arrowEdge: .bottom) {
                        categoryManagerPanel
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // 진입점 1: 툴바 업로드 버튼. iOS/iPadOS는 파일/사진 보관함 선택 메뉴, macOS는 파일 선택기만(`PhotosPicker` 없음).
                #if os(iOS)
                Menu {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("파일에서 선택", systemImage: "folder")
                    }
                    Button {
                        isPhotosPickerPresented = true
                    } label: {
                        Label("사진 보관함에서 선택", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Label("업로드", systemImage: "square.and.arrow.up")
                }
                #else
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("업로드", systemImage: "square.and.arrow.up")
                }
                #endif
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
        // 선택 즉시 `handlePickedPhotos`가 각 사진을 임시 파일로 내려받아 `beginUpload(urls:)`에 넘긴다.
        // 동영상은 연구문서 대상이 아니므로 `.images`만 허용한다.
        #if os(iOS)
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $selectedPhotosPickerItems,
            matching: .images
        )
        .onChange(of: selectedPhotosPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let itemsToLoad = newItems
            selectedPhotosPickerItems = []
            // `loadTransferable`은 메인 액터에 격리되지 않은 async API라, 이후 `@State`를 바꾸는 작업은
            // 명시적으로 `@MainActor`로 감싼다.
            Task { @MainActor in
                await handlePickedPhotos(itemsToLoad)
            }
        }
        #endif
        // 업로드 확인 시트 — "건너뛰기"는 관련 장 없이, "이 장으로 업로드"는 관련 장을 실어 업로드한다.
        // `pendingUploadURLs`가 비어 있지 않은 동안만 표시된다. 카테고리는 두 경로 모두 필수라
        // 시트에서 고르기 전엔 두 버튼이 비활성화된다.
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
        // 화면이 다시 보일 때마다 목록을 재fetch한다 — 다른 경로(Settings "연구문서 전체 삭제")가 같은
        // `modelContext`에서 `SourceDocument`를 지우면 캐시된 `viewModel.documents`가 무효 객체를 가리켜
        // 프로퍼티 접근 시 fatal error(잡을 수 없음)가 나기 때문이다.
        // ⚠️ macOS에서 이 화면이 떠 있는 동안 다른 창에서 삭제되는 경우는 이 fix로 못 막는다(목록 렌더링은 `@Query`가 보완).
        .onAppear {
            setUpIfNeeded()
            viewModel?.loadDocuments()
            viewModel?.loadCategories()
        }
        // File 메뉴 "연구문서 업로드... ⌘O" (AppCommands.swift).
        .focusedSceneValue(\.uploadDocumentAction) { isFileImporterPresented = true }
        .alert("오류", isPresented: Binding(
            get: { viewModel?.lastErrorDescription != nil },
            set: { if !$0 { viewModel?.lastErrorDescription = nil } }
        )) {
            Button("확인") { viewModel?.lastErrorDescription = nil }
        } message: {
            Text(viewModel?.lastErrorDescription ?? "")
        }
    }

    // MARK: - 문서함 홈(카드형, 2026-09-11 신설)

    /// 검색어가 없고 카테고리 필터가 "전체"일 때만 카드형 홈을 보여준다(그 외에는 평면 목록).
    private var isShowingShelfHome: Bool {
        categoryFilter == .all && searchText.isEmpty
    }

    private struct DocumentFolderGroup: Identifiable {
        let id: UUID
        let name: String
        let documents: [SourceDocument]
        let filter: DocumentCategoryFilter
        let spineColor: Color
    }

    /// 카테고리별 책등 강조색 — 카테고리에 색 필드가 없어 등장 순서(`loadCategories()` 정렬 기준)대로 순환 배정한다.
    private static let shelfSpineColors: [Color] = [
        JBCHCategoryPalette.gold, JBCHCategoryPalette.wood, JBCHCategoryPalette.slateTeal, JBCHCategoryPalette.wine,
    ]
    /// 위 네 색의 "밤빛 서재"(어두운 배경) 전용 변형.
    private static let shelfSpineColorsOnDark: [Color] = [
        JBCHCategoryPalette.gold, JBCHCategoryPalette.woodOnDark, JBCHCategoryPalette.slateTealOnDark, JBCHCategoryPalette.wineOnDark,
    ]
    private static let uncategorizedGroupID = UUID()

    /// 카테고리(+미분류)별로 문서를 묶는다. 문서가 없는 카테고리는 카드로 보이지 않는다.
    /// "미분류" 카드는 필터 메뉴의 `.uncategorized`(`matchesCategoryFilter`)와 같은 기준(카테고리·관련 장 모두 없음)이라
    /// 카드 개수와 탭 후 목록이 일치한다.
    /// ⚠️ 카테고리는 없고 관련 장만 있는 문서는 어느 카드에도 속하지 않는다("최근 문서"에는 나타난다).
    private func folderGroups(viewModel: DocumentsViewModel) -> [DocumentFolderGroup] {
        var groups: [DocumentFolderGroup] = []
        let onDark = isDarkBibleBackground
        for (index, category) in viewModel.categories.enumerated() {
            let documents = queriedDocuments.filter { $0.category?.id == category.id }
            guard !documents.isEmpty else { continue }
            let spineColor = (onDark ? Self.shelfSpineColorsOnDark : Self.shelfSpineColors)[index % Self.shelfSpineColors.count]
            groups.append(DocumentFolderGroup(id: category.id, name: category.name, documents: documents, filter: .custom(category.id), spineColor: spineColor))
        }
        let uncategorized = queriedDocuments.filter { $0.category == nil && $0.relatedChapterRef == nil }
        if !uncategorized.isEmpty {
            groups.append(DocumentFolderGroup(
                id: Self.uncategorizedGroupID,
                name: "분류 없음",
                documents: uncategorized,
                filter: .uncategorized,
                spineColor: onDark ? JBCHCategoryPalette.shelfSlateOnDark : JBCHCategoryPalette.shelfSlate
            ))
        }
        return groups
    }

    /// 최근 업로드 5개(`queriedDocuments`가 업로드일 역순 정렬).
    private var recentDocuments: [SourceDocument] {
        Array(queriedDocuments.prefix(5))
    }

    @ViewBuilder
    private func shelfHome(viewModel: DocumentsViewModel) -> some View {
        let groups = folderGroups(viewModel: viewModel)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("문서함")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(settings.bibleTextColor ?? .primary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                            ForEach(groups) { group in
                                folderCard(group)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                if !recentDocuments.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("최근 문서")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(settings.bibleTextColor ?? .primary)
                            .padding(.horizontal)
                        // List 밖에서 재사용돼 List의 `foregroundStyle`을 물려받지 못하고 파일명 `Text`도 자체 색이 없으므로 같은 색을 명시한다.
                        VStack(spacing: 0) {
                            ForEach(recentDocuments, id: \.id) { document in
                                DocumentRowView(
                                    document: document,
                                    highlightKeywords: [],
                                    bodyExcerpt: nil,
                                    bodyOccurrenceSum: 0,
                                    matchedTagNames: [],
                                    documentSearchText: "",
                                    viewModel: viewModel
                                )
                                if document.id != recentDocuments.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal)
                        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                    }
                }
            }
            .padding(.vertical, 14)
        }
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 문서함 카드 하나 — 탭하면 `categoryFilter`를 그 카테고리로 바꾼다(새 네비게이션 없음).
    /// `isSelected`는 분할 레이아웃(`folderSidebar`)에서 현재 보고 있는 폴더를 옅은 배경으로 표시한다.
    private func folderCard(_ group: DocumentFolderGroup, isSelected: Bool = false) -> some View {
        Button {
            categoryFilter = group.filter
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .body))
                        .foregroundStyle(settings.bibleTextColor ?? .primary)
                        .lineLimit(1)
                    Text("\(group.documents.count)개 문서")
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.4) ?? Color.secondary)
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                        ? (settings.bibleTextColor?.opacity(0.12) ?? Color.secondary.opacity(0.14))
                        : (settings.bibleTextColor?.opacity(0.05) ?? Color.secondary.opacity(0.06)))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(group.spineColor)
                    .frame(width: 4)
                    .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func content(viewModel: DocumentsViewModel) -> some View {
        VStack(spacing: 0) {
            // 아이폰은 드래그 앤 드롭을 쓸 수 없고 탭 업로드는 우측 상단 업로드 아이콘과 겹치므로 점선 박스를
            // 없애고 아이콘 하나로 통일한다. 아이패드/맥은 그대로 둔다.
            if !isPhone {
                dropZone(viewModel: viewModel)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()
            }

            searchAndFilterBar(viewModel: viewModel)

            searchContentOrnamentalDivider

            // 아이폰은 카드 홈 ↔ 평면 목록 전환(`phoneMainContent`), 아이패드/맥은 분할 레이아웃(`splitMainContent`).
            if queriedDocuments.isEmpty {
                Spacer()
                Text("업로드된 연구문서가 없습니다.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if isPhone {
                phoneMainContent(viewModel: viewModel)
            } else {
                splitMainContent(viewModel: viewModel)
            }
        }
        // 하위 `List`의 `.background()`는 리스트 프레임만 칠해 드롭존·검색+필터 줄까지 닿지 않으므로 VStack에도 같은 배경을 칠한다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 아이폰 전용 본문 — `isShowingShelfHome`으로 문서함 카드 홈 ↔ 평면 목록을 전환한다.
    @ViewBuilder
    private func phoneMainContent(viewModel: DocumentsViewModel) -> some View {
        if isShowingShelfHome {
            shelfHome(viewModel: viewModel)
        } else if filteredResults.isEmpty {
            Spacer()
            Text("검색 결과가 없습니다.")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            documentList(viewModel: viewModel)
        }
    }

    /// 아이패드/맥 분할 본문 — 왼쪽 `folderSidebar`(문서함 폴더 카드), 오른쪽 선택한 폴더(`categoryFilter`)의
    /// 문서 목록을 항상 좌우로 함께 보여준다.
    ///
    /// ⚠️ 문서를 여는 동작(행 탭 → openWindow / 아이폰 NavigationLink)은 이 분할과 무관하다. 문서 상세 정보
    /// (카테고리/관련 성경장 편집)는 `DocumentRowView`의 컨텍스트 메뉴 팝오버(`documentInfoPopover`)에서 연다.
    @ViewBuilder
    private func splitMainContent(viewModel: DocumentsViewModel) -> some View {
        HStack(spacing: 0) {
            folderSidebar(viewModel: viewModel)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            Divider()

            if filteredResults.isEmpty {
                VStack {
                    Spacer()
                    Text("검색 결과가 없습니다.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                documentList(viewModel: viewModel)
            }
        }
    }

    /// `splitMainContent`의 왼쪽 열 — `folderGroups`/`folderCard`를 재사용하되 탭하면 `categoryFilter`만 바꾼다.
    /// 이 열이 항상 보이므로 특정 폴더에서 돌아올 수 있게 "전체 문서" 카드(`allDocumentsCard`)를 둔다.
    @ViewBuilder
    private func folderSidebar(viewModel: DocumentsViewModel) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                allDocumentsCard
                ForEach(folderGroups(viewModel: viewModel)) { group in
                    folderCard(group, isSelected: categoryFilter == group.filter)
                }
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    private var allDocumentsCard: some View {
        Button {
            categoryFilter = .all
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("전체 문서")
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .body))
                        .foregroundStyle(settings.bibleTextColor ?? .primary)
                        .lineLimit(1)
                    Text("\(queriedDocuments.count)개 문서")
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(categoryFilter == .all
                        ? (settings.bibleTextColor?.opacity(0.12) ?? Color.secondary.opacity(0.14))
                        : (settings.bibleTextColor?.opacity(0.05) ?? Color.secondary.opacity(0.06)))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// `splitMainContent`/`phoneMainContent`가 공유하는 문서 목록.
    @ViewBuilder
    private func documentList(viewModel: DocumentsViewModel) -> some View {
        List(filteredResults) { result in
            DocumentRowView(
                document: result.document,
                highlightKeywords: result.score.highlightKeywords,
                bodyExcerpt: result.score.bodyExcerpt,
                bodyOccurrenceSum: result.score.bodyOccurrenceSum,
                matchedTagNames: result.score.matchedTagNames,
                documentSearchText: searchText,
                viewModel: viewModel
            )
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        // `SearchView.swift`와 같은 3종 세트(배경 숨김 + 테마 배경 + 글자색) — `.plain` 스타일이라 리스트 배경 하나만
        // 바꾸면 되고, `foregroundStyle`은 색을 지정하지 않은 `DocumentRowView` 요소가 물려받는다.
        // 않은 `Text`/`Image`가 물려받게 한다.
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
        // 어두운 배경에서 행 구분선이 거의 안 보이는 문제 대응.
        .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.3))
    }

    /// "카테고리 관리" 팝오버(맥OS·아이패드) — 툴바 버튼으로 연다. 생성 · 이름 변경 · 삭제 · 수동 순서를 지원한다.
    /// 삭제해도 소속 문서는 지워지지 않고 "분류 없음"으로 옮겨진다(`ImageCategory.sourceDocuments` deleteRule = nullify).
    ///
    /// 디자인은 이 화면의 문서함 카드(`folderCard`)·검색 영역과 같은 언어를 쓴다 — 테마 배경/글자색, 성곡 세리프 제목,
    /// 글자색 5% 채움의 둥근 카드 + 왼쪽 책등 막대(`folderGroups`와 같은 순서·색 배정), wood 톤 구분선.
    private var categoryManagerPanel: some View {
        let textColor = settings.bibleTextColor ?? Color.primary
        let secondaryTextColor = settings.bibleTextColor?.opacity(0.6) ?? Color.secondary
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // 제목과 같은 줄에 "순서 변경/완료"(아이패드)를 두고 첫 줄 기준선을 맞춘다 — 제목 아래 설명 문구와 겹치지 않는다.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("카테고리 관리")
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                        .fontWeight(.semibold)
                        .foregroundStyle(textColor)
                    #if os(iOS)
                    Spacer(minLength: 8)
                    if !(viewModel?.categories.isEmpty ?? true) {
                        Button(isReorderingCategories ? "완료" : "순서 변경") {
                            isReorderingCategories.toggle()
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(JBCHCategoryPalette.gold)
                    }
                    #endif
                }
                Text(panelSubtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            searchContentOrnamentalDivider

            if let viewModel {
                let onDark = isDarkBibleBackground
                let spineColors = onDark ? Self.shelfSpineColorsOnDark : Self.shelfSpineColors
                if viewModel.categories.isEmpty {
                    Text("아직 카테고리가 없습니다.\n아래에서 첫 카테고리를 만들어 보세요.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(secondaryTextColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 32)
                } else {
                    // 드래그 정렬(`onMove`)이 필요해 ScrollView+LazyVStack 대신 List를 쓴다.
                    List {
                        ForEach(Array(viewModel.categories.enumerated()), id: \.element.id) { index, category in
                            CategoryManagerRow(
                                category: category,
                                viewModel: viewModel,
                                spineColor: spineColors[index % spineColors.count],
                                onDelete: { deleteCategory(category, viewModel: viewModel) },
                                isReordering: isReorderingCategoriesActive,
                                canMoveUp: index > 0,
                                canMoveDown: index < viewModel.categories.count - 1,
                                onMoveUp: { viewModel.moveCategories(from: IndexSet(integer: index), to: index - 1) },
                                onMoveDown: { viewModel.moveCategories(from: IndexSet(integer: index), to: index + 2) }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            // 드래그가 어려울 때를 위한 보조 수단(정확한 한 칸 이동).
                            .contextMenu {
                                Button("위로 이동") {
                                    viewModel.moveCategories(from: IndexSet(integer: index), to: index - 1)
                                }
                                .disabled(index == 0)
                                Button("아래로 이동") {
                                    viewModel.moveCategories(from: IndexSet(integer: index), to: index + 2)
                                }
                                .disabled(index == viewModel.categories.count - 1)
                            }
                        }
                        // 드래그 정렬은 맥OS만 — 아이패드는 위/아래 버튼(`isReordering`)을 쓴다.
                        #if os(macOS)
                        .onMove { source, destination in
                            viewModel.moveCategories(from: source, to: destination)
                        }
                        #endif
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                Rectangle()
                    .fill(JBCHCategoryPalette.wood.opacity(0.3))
                    .frame(height: 1)

                HStack(spacing: 8) {
                    TextField(
                        "새 카테고리",
                        text: $newCategoryName,
                        prompt: Text("새 카테고리").foregroundStyle(textColor.opacity(0.4))
                    )
                    .textFieldStyle(.plain)
                    .foregroundStyle(textColor)
                    .onSubmit { addCategory(viewModel: viewModel) }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(settings.bibleTextColor?.opacity(0.05) ?? Color.secondary.opacity(0.06))
                    )

                    Button {
                        addCategory(viewModel: viewModel)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(JBCHCategoryPalette.gold, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .help("카테고리 추가")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Spacer()
            }
        }
        .frame(width: 340, height: 480)
        .foregroundStyle(textColor)
        #if os(iOS)
        .onDisappear { isReorderingCategories = false }
        #endif
        // 테마 배경을 칠한다. 테마를 고르지 않았으면 팝오버 기본 배경을 그대로 둔다.
        .background {
            if let background = settings.bibleBackgroundColor {
                background.ignoresSafeArea()
            }
        }
    }

    private func addCategory(viewModel: DocumentsViewModel) {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = viewModel.createCategory(named: trimmed)
        newCategoryName = ""
    }

    /// 카테고리 삭제. 지금 이 카테고리로 필터링 중이면 필터를 "전체"로 되돌린다(사라진 카테고리를 가리키지 않게).
    private func deleteCategory(_ category: ImageCategory, viewModel: DocumentsViewModel) {
        let deletedID = category.id
        if categoryFilter == .custom(deletedID) { categoryFilter = .all }
        viewModel.deleteCategory(category)
    }

    /// 순서 변경 모드 여부(맥OS는 항상 false — 드래그로 바로 옮긴다).
    private var isReorderingCategoriesActive: Bool {
        #if os(iOS)
        isReorderingCategories
        #else
        false
        #endif
    }

    /// 패널 머리 안내 문구 — 순서 변경 방법이 플랫폼마다 달라 따로 둔다.
    private var panelSubtitle: String {
        #if os(iOS)
        "이름 변경 · 삭제 · 순서는 오른쪽 위 \"순서 변경\"으로"
        #else
        "이름 변경 · 삭제 · 드래그로 순서 바꾸기"
        #endif
    }

    // MARK: - 검색 + 카테고리 필터 (2026-08-16 신설)

    /// 검색창 아래 구분선 — `SearchView.menuContentOrnamentalDivider`와 같은 시각 언어
    /// (가로선-`sparkle`-가로선, wood 톤). 그 프로퍼티가 `SearchView`의 private이라 복제했고,
    /// List 행이 아니라 VStack 안이라 `.listRowSeparator`/`.listRowBackground`는 쓰지 않는다.
    private var searchContentOrnamentalDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.45) ?? Color.secondary)
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func searchAndFilterBar(viewModel: DocumentsViewModel) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                // 돋보기 아이콘도 placeholder/테두리와 같이 테마 글자색을 따른다.
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                // `TextField(_:text:)`는 placeholder 색을 지정할 수 없어, `prompt:` 이니셜라이저로
                // 실제 보이는 placeholder에만 테마 글자색을 옅게 입힌다.
                TextField(
                    "파일명, 관련 성경 장, 카테고리, 태그, 본문, 성경장절로 검색",
                    text: $searchText,
                    prompt: Text("파일명, 관련 성경 장, 카테고리, 태그, 본문, 성경장절로 검색")
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
                )
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            // 배경 채움과 테두리 모두 테마 글자색 기반(테마 미선택 시 `Color.secondary`).
            .background(RoundedRectangle(cornerRadius: 8).fill(settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(settings.bibleTextColor?.opacity(0.2) ?? Color.secondary.opacity(0.2), lineWidth: 1))
            // 카테고리 필터 메뉴는 UI에서 제거됨 — 이 메뉴에만 있던 "관련 성경 장별" 필터(`.chapter`)는
            // 현재 UI에서 고를 방법이 없다(`categoryFilterMenu`/`chapterFilterOptions` 로직은 유지).
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// 카테고리 필터 메뉴 — 문서에 실제 쓰인 관련 성경 장 + 커스텀 카테고리(`viewModel.categories`).
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

    /// 검색어를 공백 기준 단어로 나눈다 — 단어별 OR 매칭에 쓴다.
    private var searchWords: [String] {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// 문서 하나에 대한 검색 매칭 결과 — 태그/파일명(+카테고리/관련 장)/본문 세 갈래로 나눠
    /// "몇 개의 검색단어가 그 갈래에서 일치했는지" 센다.
    ///
    /// 정렬은 세 갈래 개수를 합친 `totalMatchCount` 내림차순이지만, 갈래별 개수도 본문 스니펫/
    /// 태그·파일명 매칭 여부 판정에 계속 필요하다.
    private struct DocumentSearchScore {
        let tagCount: Int
        let filenameCount: Int
        let contentCount: Int
        /// 본문 발췌문 — 일치 단어 + 뒤 9자 조각을 " ... "로 이어붙인 70자 이하 문자열(개수 표기 없음).
        /// 본문에서 안 걸렸으면(태그/파일명 또는 성경장절 참조로만 매칭) nil.
        let bodyExcerpt: String?
        /// "(xx 회 일치)" 표시용 — 본문에서 검색단어들이 등장한 총 횟수(단어별 개수의 합).
        let bodyOccurrenceSum: Int
        /// 검색단어와 일치한 태그 이름들(중복 제거, 문서에 붙은 순서) — 뱃지 표시용. 정렬용 `tagCount`와는 별개.
        let matchedTagNames: [String]
        /// 하이라이트 대상 — 검색단어 + 이 문서에서 실제로 겹친 성경구절 원문 표현
        /// (`verseMentionSearchTexts`, 예: "창1:1~5"). 파일명/본문 발췌 강조에 쓴다.
        let highlightKeywords: [String]

        static let empty = DocumentSearchScore(
            tagCount: 0, filenameCount: 0, contentCount: 0,
            bodyExcerpt: nil, bodyOccurrenceSum: 0, matchedTagNames: [], highlightKeywords: []
        )

        var isMatch: Bool { tagCount > 0 || filenameCount > 0 || contentCount > 0 }
        /// 정렬 기준 — 갈래 구분 없이 합한 총 일치 개수. 본문 전용인 `bodyOccurrenceSum`과는 다른 값.
        var totalMatchCount: Int { tagCount + filenameCount + contentCount }
    }

    private struct DocumentSearchResult: Identifiable {
        let document: SourceDocument
        let score: DocumentSearchScore
        var id: UUID { document.id }
    }

    /// 검색 + 카테고리 필터를 통과한 문서를 `totalMatchCount` 내림차순으로 돌려준다. 동점은 `sorted`의
    /// 안정 정렬 덕에 원래 순서(최근 업로드순)가 유지된다. 검색어가 비어 있으면 정렬하지 않고
    /// `@Query` 순서(최근 업로드순)를 그대로 유지한다.
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

    /// 문서 하나의 검색 점수(단어별 OR). 성경장절 참조는 단어로 쪼개면 "창세기 1:3" 같은 표현이
    /// 깨지므로 검색어 전체를 파싱해(`verseMentionSearchTexts`) 걸린 원문 표현을 검색어에 합치고
    /// 본문 갈래로 분류한다. 카테고리 이름/관련 장 라벨은 파일명 점수에 합산한다.
    private func searchScore(for document: SourceDocument) -> DocumentSearchScore {
        let words = searchWords
        guard !words.isEmpty else { return .empty }

        let tagNames = (document.documentTags ?? []).compactMap { $0.tag?.name }
        let tagCount = words.filter { word in
            tagNames.contains { $0.localizedCaseInsensitiveContains(word) }
        }.count
        // 뱃지에 표시할 매칭 태그 이름만 순서·중복 없이 추린다(`tagCount`는 걸린 검색단어 수라 다른 값).
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

        // 타이핑한 단어 외에 이 문서에서 실제로 겹친 성경구절 원문 표현(`VerseMention.searchText`,
        // 예: "창1:1~5")도 검색/강조 대상에 합친다 — 표기가 검색어와 달라도(약어↔전체 이름, 범위)
        // 찾을 수 있다. 같은 텍스트를 두 번 세지 않도록 대소문자 무시 기준으로 중복 제거한다.
        let verseTerms = verseMentionSearchTexts(for: document)
        var seenTerms = Set<String>()
        let allTerms = (words + verseTerms).filter { seenTerms.insert($0.lowercased()).inserted }

        // 검색어별로 본문 등장 횟수와 첫 등장 위치의 "단어 + 뒤 9자" 발췌를 줄 단위로 구한다.
        // 원본 문자열에서 바로 대소문자 무시 검색한다(lowercased() 문자열의 인덱스를 재사용하지
        // 않는다 — `DocumentRowView.highlightedText`와 동일).
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
        // 본문에서 걸린 "서로 다른" 검색어 수(정렬용, 등장 횟수 아님). 성경구절 매칭은 이미 확정된
        // 사실이라 줄에서 못 찾았더라도 방어적으로 최소 1을 반영한다.
        var contentCount = occurrenceCounts.keys.count
        if !verseTerms.isEmpty && verseTerms.allSatisfy({ occurrenceCounts[$0] == nil }) {
            contentCount += 1
        }

        // "(xx 회 일치)"용 총 등장 횟수 — 정렬용 `contentCount`("서로 다른 단어" 수)와 의도적으로 다른 값.
        let bodyOccurrenceSum = occurrenceCounts.values.reduce(0, +)
        let bodyExcerpt = Self.buildContentSnippet(words: allTerms, excerpts: firstExcerpts)
        return DocumentSearchScore(
            tagCount: tagCount, filenameCount: filenameCount, contentCount: contentCount,
            bodyExcerpt: bodyExcerpt, bodyOccurrenceSum: bodyOccurrenceSum, matchedTagNames: matchedTagNames,
            highlightKeywords: allTerms
        )
    }

    /// 검색어 순서대로 "단어+뒤 9자" 발췌를 " ... "로 이어붙인다. 70자를 넘으면 70자에서 자르고
    /// 말줄임표(…)를 붙인다.
    private static func buildContentSnippet(words: [String], excerpts: [String: String]) -> String? {
        let segments = words.compactMap { excerpts[$0] }
        guard !segments.isEmpty else { return nil }
        let joined = segments.joined(separator: " ... ")
        guard joined.count > 70 else { return joined }
        let cutIndex = joined.index(joined.startIndex, offsetBy: 70)
        return String(joined[..<cutIndex]) + "…"
    }

    /// 검색어와 겹치는 이 문서의 성경구절 원문 표현(`VerseMention.searchText`, 예: "창1:1~5")을
    /// 중복 없이 돌려준다(빈 배열이면 매칭 없음). 파싱/매칭은 `BibleReferenceExtractor`가 이미 처리한다:
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

    /// `searchScore(for:)`가 문서마다 반복 호출되는 동안 같은 검색어를 매번 다시 파싱하지 않도록
    /// 한 번만 계산한다(`BibleReferenceExtractor.extract`는 정규식 컴파일은 캐싱하지만 매칭 스캔은
    /// 호출마다 돈다). 별도 캐싱 레이어는 두지 않았다.
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

    // MARK: - 드롭존(진입점 2, 3)

    private func dropZone(viewModel: DocumentsViewModel) -> some View {
        // 안내 문구 색은 `settings.bibleTextColor`를 옅게 써서 테마 배경과 항상 대비되게 하고,
        // 테마 미선택(nil)이면 원래 색(`.secondary`/`.tertiary`)을 쓴다. 마지막 캡션은 `.tertiary`가
        // `Color`가 아니라 `ShapeStyle`이라 `??`로 바로 폴백할 수 없어 `AnyShapeStyle`로 묶었다.
        VStack(spacing: 4) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 18))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
            // 진입점 3: 드롭존 클릭 — 같은 fileImporter를 그대로 연다.
            Text(allowsDragAndDrop ? "드래그해서 파일을 놓거나 클릭해서 업로드" : "탭해서 업로드")
                .font(.callout)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.85) ?? Color.secondary)
            // `.doc`/`.docx` 업로드는 막혀 있으므로(`DocumentUploadService.supportedContentTypes(allowHWP:)`
            // 참고) 안내 문구에서도 뺀다(두 분기 공통).
            Text(allowsHWP ? "hwp · hwpx · pdf · 이미지" : "pdf · 이미지 (아이폰은 hwp 업로드 미지원)")
                .font(.caption2)
                .foregroundStyle(settings.bibleTextColor.map { AnyShapeStyle($0.opacity(0.55)) } ?? AnyShapeStyle(.tertiary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                // 점선 테두리도 테마 글자색을 따른다(아이콘/문구와 동일한 폴백).
                .foregroundStyle(isDropTargeted ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.4) ?? Color.secondary.opacity(0.4)))
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
        // 이전 배치의 카테고리 선택이 이번 배치로 새지 않도록 매번 초기화 — 시트가 뜰 때마다 새로 골라야 한다.
        pendingUploadCategory = nil
        pendingUploadURLs = urls
    }

    // MARK: - 사진 앱(Photos)에서 업로드 (2026-09-17 신설)

    /// 사진 보관함 항목(`PhotosPickerItem`)은 파일 URL이 아니라 자산 식별자라, 원본 데이터를 앱 임시
    /// 폴더에 파일로 저장한 뒤 기존 `beginUpload(urls:)` 파이프라인에 태운다. `createSourceDocument`의
    /// `startAccessingSecurityScopedResource()`는 보안 스코프가 필요 없는 앱 소유 URL에서는 `false`를
    /// 돌려줄 뿐 실패하지 않아, Files 선택기·드래그앤드롭 URL과 동일하게 안전하다.
    ///
    /// 확장자는 항목의 `supportedContentTypes`(사용자가 고른 자산 자체의 타입)에서 얻고, 알 수 없으면
    /// "jpg"로 폴백한다 — `createSourceDocument`가 jpg/jpeg/png/heic/heif를 모두 `.image`로 다루므로
    /// 확장자를 못 맞혀도 업로드는 실패하지 않는다.
    ///
    /// ⚠️ 알려진 한계: 여기서 만든 임시 파일은 업로드 후에도 앱이 지우지 않는다. 공용 경로
    /// (`pendingUploadURLs`/`finishPendingUpload`)에 "앱이 만든 임시 파일" 표시를 얹으려면 세 진입점이
    /// 공유하는 상태를 건드려야 해 보류했다. iOS가 임시 폴더를 주기적으로 정리한다.
    #if os(iOS)
    @MainActor
    private func handlePickedPhotos(_ items: [PhotosPickerItem]) async {
        var savedURLs: [URL] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try data.write(to: tempURL)
                savedURLs.append(tempURL)
            } catch {
                continue
            }
        }
        guard !savedURLs.isEmpty else { return }
        beginUpload(urls: savedURLs)
    }
    #endif

    private func finishPendingUpload(relatedChapter: BibleChapterRef?) {
        let urls = pendingUploadURLs
        let category = pendingUploadCategory
        pendingUploadURLs = []
        pendingUploadCategory = nil
        viewModel?.upload(urls: urls, relatedChapter: relatedChapter, category: category)
    }
}

/// `categoryManagerPanel`(맥OS·아이패드 팝오버)의 목록 행 — 이름 인라인 편집 + 삭제 + 드래그 핸들.
/// 이름은 포커스를 잃거나 Return을 누르면 즉시 저장한다. 모양은 문서함 카드(`DocumentsHomeView.folderCard`)와 같다.
/// 삭제는 확인 대화상자 대신 행 안에서 한 번 더 묻는다(팝오버 안에서 alert가 팝오버를 닫는 일을 피하려는 것).
private struct CategoryManagerRow: View {
    let category: ImageCategory
    let viewModel: DocumentsViewModel
    /// 왼쪽 책등 막대 색 — 문서함 카드와 같은 순서·팔레트.
    let spineColor: Color
    /// 삭제 확정 시 부모가 실행한다(필터 초기화 + 모델 삭제).
    let onDelete: () -> Void
    /// 순서 변경 모드(아이패드): 켜면 이름 편집/삭제 대신 위/아래 버튼을 보인다.
    var isReordering = false
    var canMoveUp = false
    var canMoveDown = false
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    @State private var settings = UserSettingsStore.shared
    @State private var name: String = ""
    @State private var isConfirmingDelete = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let textColor = settings.bibleTextColor ?? Color.primary
        let secondaryTextColor = settings.bibleTextColor?.opacity(0.6) ?? Color.secondary
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("카테고리 이름", text: $name)
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .body))
                    .foregroundStyle(textColor)
                    .focused($isFocused)
                    .disabled(isReordering)

                if isReordering {
                    // 위/아래 한 칸 이동 — 탭 영역을 넓게 잡는다(44pt 권장).
                    Button { onMoveUp?() } label: {
                        Image(systemName: "chevron.up")
                            .font(.callout.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(JBCHCategoryPalette.gold.opacity(canMoveUp ? 1 : 0.3))
                    .disabled(!canMoveUp)
                    .accessibilityLabel("위로 이동")
                    Button { onMoveDown?() } label: {
                        Image(systemName: "chevron.down")
                            .font(.callout.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(JBCHCategoryPalette.gold.opacity(canMoveDown ? 1 : 0.3))
                    .disabled(!canMoveDown)
                    .accessibilityLabel("아래로 이동")
                } else {
                    Button {
                        isFocused = false
                        isConfirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.callout)
                            .foregroundStyle(secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                    .help("카테고리 삭제")
                }

                // 순서 변경 안내용 핸들(행 어디를 잡아 끌어도 `List.onMove`가 동작한다). 아이패드는 편집 모드에서
                // 시스템이 자체 핸들을 그리므로 중복을 피해 맥OS에서만 보인다.
                #if os(macOS)
                Image(systemName: "line.3.horizontal")
                    .font(.callout)
                    .foregroundStyle(secondaryTextColor.opacity(0.7))
                    .help("끌어서 순서 변경")
                #endif
            }

            if isConfirmingDelete && !isReordering {
                Text("삭제하면 이 카테고리의 문서는 '분류 없음'으로 옮겨집니다. 문서는 지워지지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("취소") { isConfirmingDelete = false }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                    Button("삭제") { onDelete() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JBCHCategoryPalette.wine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFocused
                    ? (settings.bibleTextColor?.opacity(0.12) ?? Color.secondary.opacity(0.14))
                    : (settings.bibleTextColor?.opacity(0.05) ?? Color.secondary.opacity(0.06)))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(spineColor)
                .frame(width: 4)
                .padding(.vertical, 6)
        }
        // 편집 중임을 금박 테두리로 알린다(시스템 포커스 링은 `focusEffectDisabled`로 껐다).
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(JBCHCategoryPalette.gold.opacity(isFocused ? 0.8 : 0), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onAppear { name = category.name }
        // 다른 곳(다른 기기 동기화 등)에서 이름이 바뀌면 편집 중이 아닐 때만 반영한다.
        .onChange(of: category.name) { _, newValue in
            if !isFocused { name = newValue }
        }
        .onSubmit { commit() }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        viewModel.renameCategory(category, to: name)
    }
}

/// 업로드 확인 시트 — 관련 성경 장을 묻는다(선택 사항이라 "건너뛰기" 가능). 카테고리는 입력이
/// 강제되어, 두 경로(건너뛰기/이 장으로 업로드) 모두 카테고리를 고르기 전에는 버튼이 비활성화된다.
private struct UploadChapterLinkSheet: View {
    @Binding var book: Book
    @Binding var chapter: Int
    let fileCount: Int
    /// 기존 카테고리 목록 — `DocumentRowView.categoryMenu`와 같은 Menu 구성(기존 분류 선택 + "새 분류…").
    let categories: [ImageCategory]
    @Binding var selectedCategory: ImageCategory?
    /// "새 분류…" 입력을 실제 `ImageCategory`로 만드는 부모 제공 클로저 — 이 시트는 `DocumentsViewModel`을 직접 모른다.
    let onCreateCategory: (String) -> ImageCategory?
    let onSkip: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isNewCategoryInputPresented = false
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            // `Form` 대신 `VStack`을 쓴다 — `Form`/`Section` 행 레이아웃이 자식 컨트롤(`BookChapterPicker`의
            // 좁은 HStack 안 검색창) 크기를 다시 계산하면서 검색창 폭이 placeholder 너비보다 줄어들어
            // placeholder가 상자 밖으로 삐져나왔다.
            VStack(alignment: .leading, spacing: 16) {
                // 이 시트에서 가장 먼저 채워야 하는 항목이라 관련 성경 장보다 위에 둔다.
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

                // 시스템 기본 폰트로 되돌린다(`RootView`의 `.appDefaultFont()` 커스텀 Paperlogy 무효화).
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
                    // 카테고리 강제를 우회하지 못하도록 "건너뛰기"도 카테고리 선택 전엔 막는다(이 버튼은 관련 성경 장만 생략).
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
            // "새 분류…" 선택 시 이름을 입력받아 `ImageCategory`를 만들고 곧바로 선택 상태로 반영한다.
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
    // 아래 `accentSpineColor`가 쓰는 테마 설정.
    private var settings: UserSettingsStore { .shared }
    let document: SourceDocument
    /// 검색 하이라이트 대상 — 타이핑한 검색어와, 부모(`searchScore`)가 `VerseMention`으로 풀어낸
    /// 문서 내 성경장절 원문("창1:1-5" 등). 빈 배열이면 하이라이트 없이 평범한 텍스트로 보인다
    /// (`highlightedText(_:keywords:)` 참고).
    let highlightKeywords: [String]
    /// 본문 일치 발췌문("태초에 하나 ... 창조하시니라" 형태, 개수 표기 없음). 본문에서 걸리지 않았으면 nil.
    let bodyExcerpt: String?
    /// "(xx 회 일치)" 접두어용 — 본문에서 검색단어들이 등장한 총 횟수(부모 `searchScore`가 계산).
    /// `bodyExcerpt`가 nil이면 쓰이지 않는다.
    let bodyOccurrenceSum: Int
    /// 검색어와 일치한 태그 이름들 — 비어 있으면 뱃지를 그리지 않는다.
    let matchedTagNames: [String]
    /// 부모(`DocumentsHomeView`)의 검색창 문자열 — 행을 눌러 뷰어를 열 때 검색어를 함께 넘겨 목록의
    /// 키워드 강조가 뷰어에서도 유지되게 한다(`SearchView.documentSearchText`와 같은 방식).
    /// `highlightKeywords`(복수)는 `DocumentSearchRequest.searchText`(단수 String)에 그대로 못 넣어
    /// 원문 문자열을 받는다. 빈 문자열이면 검색어 없이 연다("최근 문서" 목록은 검색 문맥이 아니라
    /// 빈 문자열을 넘긴다).
    let documentSearchText: String
    let viewModel: DocumentsViewModel
    @Environment(\.openWindow) private var openWindow
    // `colorScheme`은 테마 배경 미선택(nil) 시 시스템 라이트/다크 판정용, `environment`는
    // `Color.resolve(in:)`으로 테마 배경 밝기를 재는 용도(`ThemedNavigationBarBackgroundModifier.
    // isDarkBackground`와 같은 공식).
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// 실제로 보이는 배경이 어두운지 판정해 강조선 색을 고른다 — 테마 배경이 있으면 WCAG 상대휘도
    /// (`ThemedNavigationBarBackgroundModifier.isDarkBackground`와 같은 공식, 그 struct가 private라
    /// 복제했다), 없으면 시스템 라이트/다크로 판정한다.
    private var accentSpineColor: Color {
        let isDark: Bool
        if let bg = settings.bibleBackgroundColor {
            let resolved = bg.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            isDark = luminance < 0.5
        } else {
            isDark = colorScheme == .dark
        }
        return isDark ? JBCHCategoryPalette.navyOnDark : JBCHCategoryPalette.navy
    }
    @State private var isCategoryInputPresented = false
    @State private var categoryInput = ""
    /// 문서 정보 팝오버(`documentInfoPopover`) 표시 여부 — `.contextMenu`의 "문서 정보"에서 켠다.
    @State private var isInfoPopoverPresented = false
    /// 관련 성경 장 편집 시트 상태. `chapterLinkBook`은 시트를 열 때 `document.relatedChapterRef`(있으면)
    /// 또는 마지막으로 보던 성경 위치(없으면)로 채운다.
    @State private var isChapterLinkEditorPresented = false
    @State private var chapterLinkBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var chapterLinkChapter: Int = 1

    /// `UIDevice`는 iOS에서만 존재하므로 `#if os(iOS)`로 감싼다(맥 빌드 보호). 아이폰은 다중 씬을
    /// 지원하지 않아 `openWindow` 대신 `NavigationLink`로 이 탭의 NavigationStack에 밀어 넣어야 한다.
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        // 삭제된 객체 방어: 행이 트리에서 제거되기 직전 한 프레임 동안 이 뷰가 옛 `document` 참조로 다시
        // 계산되면 `@Model` 저장 프로퍼티(`conversionStatus` 등) 접근에서 fatal error가 난다(`@Query`로도
        // 막지 못하는 경쟁 상태). SwiftData가 관리하는 `modelContext`는 삭제된 객체에서 읽어도 안전하고
        // 삭제·저장 후 nil이 되므로, 다른 프로퍼티를 읽기 전에 이걸로 먼저 거른다.
        if document.modelContext == nil {
            EmptyView()
        } else {
            documentRow
        }
    }

    @ViewBuilder
    private var documentRow: some View {
        // 아이폰은 다중 씬을 지원하지 않아 `openWindow`가 새 창을 못 연다("Unable to open a window when
        // the app does not support multiple scenes") — 아이폰에서만 `NavigationLink(value:)`로 이 탭의
        // NavigationStack에 밀어 넣는다(`.navigationDestination(for: PersistentIdentifier.self)`는
        // 이 파일 하단에 등록). 그 외는 별도 창으로 연다.
        Group {
            // 검색 중일 때만(공백 제거 후 비어 있지 않을 때) 검색어를 실어 "document-search"로 열고,
            // 아니면 "document-viewer"(검색어 없음)로 연다.
            let trimmedSearchText = documentSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if isPhoneIdiom {
                if trimmedSearchText.isEmpty {
                    NavigationLink(value: document.persistentModelID) {
                        documentRowLabel
                    }
                } else {
                    // `SearchView.documentRow`의 아이폰 분기와 같은 패턴 —
                    // `.navigationDestination(for:)` 등록 없이 클로저 기반
                    // `NavigationLink`로 바로 `DocumentSearchWindowContent`를 민다.
                    NavigationLink {
                        DocumentSearchWindowContent(
                            request: DocumentSearchRequest(documentID: document.persistentModelID, searchText: trimmedSearchText)
                        )
                    } label: {
                        documentRowLabel
                    }
                }
            } else {
                Button {
                    if trimmedSearchText.isEmpty {
                        openWindow(id: "document-viewer", value: document.persistentModelID)
                    } else {
                        openWindow(
                            id: "document-search",
                            value: DocumentSearchRequest(documentID: document.persistentModelID, searchText: trimmedSearchText)
                        )
                    }
                } label: {
                    documentRowLabel
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            // 길게 프레스(아이패드)/마우스 오른쪽 버튼(맥)으로 문서 정보 팝오버를 연다 — `.contextMenu`가
            // 두 제스처를 이미 제공하므로 별도 제스처 인식기가 필요 없다.
            Button {
                isInfoPopoverPresented = true
            } label: {
                Label("문서 정보", systemImage: "info.circle")
            }
            Divider()
            if document.conversionStatus == .failedNeedsManual {
                Button {
                    viewModel.retry(document)
                } label: {
                    Label("재시도", systemImage: "arrow.clockwise")
                }
            }
            // 업로드 시 건너뛰었거나 잘못 골랐을 때의 재설정 경로.
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
            // 사이드바 "고정됨" 섹션에 넣고 빼는 토글.
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
        .popover(isPresented: $isInfoPopoverPresented) {
            documentInfoPopover
        }
    }

    /// 목록 행 라벨 — `documentRow`의 Button/NavigationLink 두 경로가 공유한다.
    private var documentRowLabel: some View {
        // 왼쪽 모서리에 3pt 세로선(책등 강조선)만 더하고 카드 배경은 시스템 기본을 유지한다.
        // `TranslationColumnView.VerseRow`의 선택 강조선과 같은 패턴.
        HStack {
                Image(systemName: formatIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    // 검색 중이 아니면(highlightKeywords 비어 있음) 일반 Text와 같다.
                    highlightedText(document.originalFilename, keywords: highlightKeywords)
                    HStack(spacing: 4) {
                        Text(document.originalFormat.rawValue.uppercased())
                        // 관련 성경 장이 설정돼 있으면 목록에서 바로 보이게 한다.
                        if let label = relatedChapterLabel {
                            Text("· \(label)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    // 레이아웃: "(N회 일치)" + (태그 일치 시) 태그 뱃지 + 발췌 본문(하이라이트).
                    // 본문 매치가 없으면(bodyExcerpt == nil) 줄 자체를 그리지 않는다 — 태그만 일치한 경우도 표시하지 않는다.
                    if let bodyExcerpt {
                        HStack(spacing: 4) {
                            Text("(\(bodyOccurrenceSum)회 일치)")
                            ForEach(matchedTagNames, id: \.self) { tagName in
                                badge(tagName, color: Self.tagBadgeBlue)
                            }
                            highlightedText(bodyExcerpt, keywords: highlightKeywords)
                                .lineLimit(2)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // 카테고리는 모든 형식에 붙일 수 있고, 관련 성경 장과는 별개 필드라 함께 지정할 수 있다.
                categoryMenu

                statusBadge
            }
        .padding(.vertical, 4)
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentSpineColor)
                .frame(width: 3)
                .padding(.vertical, 3)
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

    /// `keywords` 중 하나라도 대소문자 구분 없이 나타나는 모든 구간에 노란 배경(형광펜)을 입힌다.
    ///
    /// ⚠️ 원본 `text` 위에서 `.caseInsensitive` 옵션으로 직접 탐색한다 — `lowercased()`로 만든
    /// 별도 String의 `String.Index`는 원본과 호환된다는 보장이 없기 때문이다.
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

    // 상태 신호(대기·진행=주황, 완료=초록, 실패=빨강)의 의미는 유지하고 채도만 낮춘 톤.
    // 항목 구분용 `JBCHCategoryPalette`와 성격이 달라 여기 따로 둔다.
    private static let statusAmber = Color(hex: "#B36A2E") ?? .orange
    private static let statusGreen = Color(hex: "#5E8C5B") ?? .green
    private static let statusRed = Color(hex: "#A6483C") ?? .red

    // 태그 배지 파랑 — 상태 배지와 같은 채도 낮추기 원칙.
    // 대비(로컬 계산): 라이트 4.51~5.11:1, 다크 2.94~3.33:1.
    private static let tagBadgeBlue = Color(hex: "#4A6FA5") ?? .blue

    @ViewBuilder
    private var statusBadge: some View {
        switch document.conversionStatus {
        case .pending:
            badge("대기", color: Self.statusAmber)
        case .convertingNative:
            badge("추출 중", color: Self.statusAmber)
        case .converted:
            // 완료(정상) 상태는 뱃지를 그리지 않고, 아직 인덱싱되지 않은 예외 상황만 보여준다.
            if document.indexStatus == .indexed {
                EmptyView()
            } else {
                badge("추출 중", color: Self.statusAmber)
            }
        case .failedNeedsManual:
            badge("실패", color: Self.statusRed)
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
            // 분류가 지정된 문서만 서가 슬레이트로 칠한다. "미분류"는 색을 그대로 둬 분류 여부를 구별할 수 있게 한다.
            Group {
                if let categoryName = document.category?.name {
                    Text(categoryName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(JBCHCategoryPalette.shelfSlate, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                } else {
                    Text("분류 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

    /// 문서 정보 팝오버. 카테고리는 `categoryMenu`를, 관련 성경 장은 `presentChapterLinkEditor()`/
    /// `ChapterLinkEditorSheet`를 그대로 재사용한다(좁은 팝오버에 별도 Book/Chapter 피커를 넣지 않는다).
    private var documentInfoPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.originalFilename)
                        .font(.headline)
                        .lineLimit(2)
                    Text(document.originalFormat.rawValue.uppercased())
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                Divider()
                LabeledContent("상태") {
                    Text(infoStatusText)
                }
                LabeledContent("카테고리") {
                    categoryMenu
                }
                LabeledContent("관련 성경 장") {
                    Button(relatedChapterLabel ?? "설정 안 됨") {
                        presentChapterLinkEditor()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                if !infoTagNames.isEmpty {
                    LabeledContent("태그") {
                        Text(infoTagNames.joined(separator: ", "))
                    }
                }
                LabeledContent("업로드일") {
                    Text(document.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .padding()
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, minHeight: 200, idealHeight: 320, maxHeight: 420)
        // 팝오버 배경도 테마(`settings`)를 적용한다 — 없으면 시스템 기본(라이트: 흰색) 배경이 드러난다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
    }

    /// 태그 이름 목록(읽기전용).
    private var infoTagNames: [String] {
        (document.documentTags ?? []).compactMap { $0.tag?.name }
    }

    /// 위 `DocumentsHomeView.statusBadge`(같은 이름, 다른 struct)와 같은 판정
    /// 기준 — 다만 팝오버는 배지 스타일 없이 텍스트 한 줄로만 보여준다.
    private var infoStatusText: String {
        switch document.conversionStatus {
        case .pending: return "대기"
        case .convertingNative: return "추출 중"
        case .converted: return document.indexStatus == .indexed ? "완료" : "추출 중"
        case .failedNeedsManual: return "실패"
        }
    }
}

/// 문서 목록 행 컨텍스트 메뉴 "관련 성경 장 설정…/변경…"에서 쓰는 편집 시트. 업로드 확인 시트
/// (`UploadChapterLinkSheet`)와 달리 "건너뛰기"가 없다 — 이미 업로드된 문서 하나를 다루므로 "취소/저장"이 맞다.
private struct ChapterLinkEditorSheet: View {
    @Binding var book: Book
    @Binding var chapter: Int
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// 테마 적용용 읽기 전용 접근.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        NavigationStack {
            // `Form`/`Section` 행 레이아웃이 `BookChapterPicker`의 검색창 placeholder를 상자 밖으로 밀어내므로
            // (`UploadChapterLinkSheet`와 같은 이유) `Form` 없이 `VStack`을 쓴다.
            VStack(alignment: .center, spacing: 16) {
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
            // `.frame(maxWidth: .infinity)`로 VStack을 시트 폭까지 넓혀 뒤의 `.background()`가 전체 폭을 칠하게 한다
            // (안 그러면 시트 기본 배경이 좌우로 드러난다). 내용물은 가운데 정렬.
            // `.presentationSizing(.fitted)`로 폭을 줄이는 시도는 실기기에서 시트가 심하게 쪼그라들어 쓰지 않는다 — 폭은 시스템 기본값.
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            // `BookChapterPicker`의 "책 N장" 라벨은 자체 글자색이 없어 여기서 지정한 색을 상속한다
            // (명시적 색이 있는 요소는 그대로).
            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
            .background(settings.bibleBackgroundColor ?? Color.clear)
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
            // 시스템 내비게이션 바 배경까지 테마에 맞춘다(위 `.background()`는 콘텐츠 영역만 칠한다).
            .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 260)
        #endif
        #if os(iOS)
        // 시트 내용은 `BookChapterPicker`의 한 줄짜리 `standardBody`뿐이라 macOS와 같은 260으로 높이를 고정한다
        // (`BookmarkListPopover`와 같은 패턴).
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        // ⚠️ 가로 폭 축소는 미해결 — `.presentationCompactAdaptation(.sheet)`은 아이패드에서 효과가 없었고,
        // `.presentationSizing(.fitted)`는 시트가 조작 불가할 만큼 쪼그라들어 제거했다. 폭은 시스템 기본값(넓음).
        #endif
    }
}
