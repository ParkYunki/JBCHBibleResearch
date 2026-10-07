//
//  WordNoteHomeView.swift
//  JBCHBibleResearch
//
//  말씀 노트 화면 — 개인 묵상(`UserMemo`)과 말씀 요약(`VerseSummary`)을 한 목록에 통합해 보여준다.
//  두 모델은 스키마가 달라(폴더/태그는 `UserMemo`에만 있음) 데이터를 합치지 않고,
//  `WordNoteItem` 열거형 래퍼로 한 목록에 섞어 보여주기만 한다. 편집은 기존
//  `MemoDetailView`/`WordSummaryEditorView`를 그대로 재사용한다.
//  아이폰은 캡슐 필터 + 목록 → 내용 2단, 아이패드·맥은 분류 트리 | 목록 | 내용 3단 구조다.
//  분류 트리는 "노트 종류"와 "성경별"(`Book.testament` 기준, 노트가 있는 책만)로 구성하며,
//  최근/즐겨찾기는 전역 사이드바(`SidebarNavigationView`)와 중복이라 넣지 않았다.
//  개인 묵상 폴더(`MemoFolder`, 플랫·단일 소속) — 분류 트리(아이패드·맥)/폴더 칩(아이폰)으로 폴더별 보기, 폴더 만들기·이름 변경·삭제,
//  행 컨텍스트 메뉴/선택 모드(여러 개)/맥·아이패드 드래그 앤 드롭으로 폴더 이동을 지원한다. 말씀 요약에는 폴더가 없다.
//  같은 이름 폴더는 `MemoFolderMaintenance.deduplicate`가 앱 시작·이 화면이 뜰 때 하나로 합친다. ⌘⇧N "새 폴더" 커맨드도 이 화면이 받는다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

/// 통합 목록의 카테고리. rawValue가 화면에 표시되는 라벨이다.
enum WordNoteCategory: String, CaseIterable, Identifiable {
    case personalMemo = "개인 묵상"
    case verseSummary = "말씀 요약"

    var id: String { rawValue }

    /// 카테고리 배지·spine(책등) 색선의 단일 출처 — `WordNoteRowView`와 분류 트리·최근 노트 카드가 같은 색을 쓴다.
    var spineColor: Color { spineColor(onDark: false) }

    /// 배지·좌표 글자·spine이 놓이는 면이 어두운지(`onDark`)에 따라 고른다. 가죽 표지 원색(#5A3826)은 어두운 배경(시스템 다크 모드 또는 어두운 테마)에서
    /// 1.4~1.6:1이라 거의 안 보여 글자용 밝은 변형(`woodTextOnDark`)을 쓴다. 금박은 어두운 배경 위에서도 4.5:1 이상이라 그대로 둔다.
    func spineColor(onDark: Bool) -> Color {
        switch self {
        case .personalMemo: return onDark ? JBCHCategoryPalette.woodTextOnDark : JBCHCategoryPalette.wood
        case .verseSummary: return JBCHCategoryPalette.gold
        }
    }
}

/// 카테고리 picker의 선택값 — "전체"를 포함해야 해서 `WordNoteCategory`를 한 단계 감쌌다.
/// `.book(bookId:)`는 아이패드·맥 분류 트리의 "성경별" 필터 전용이다(아이폰은 `.all`/`.category`만 사용).
enum WordNoteCategoryFilter: Hashable {
    case all
    case category(WordNoteCategory)
    case book(bookId: Int)
    /// 개인 묵상 폴더 필터 — 말씀 요약은 폴더가 없어 결과에 나오지 않는다.
    case folder(UUID)
    /// 폴더가 없는 개인 묵상(말씀 요약 제외).
    case unfiled
}

/// `UserMemo`/`VerseSummary` 두 모델을 한 목록에 섞어 보여주기 위한 얇은 래퍼.
/// 데이터를 복제하지 않고 원본 모델 인스턴스를 그대로 들고 있는다.
enum WordNoteItem: Identifiable {
    case memo(UserMemo)
    case summary(VerseSummary)

    var id: String {
        switch self {
        case .memo(let memo): return "memo-\(memo.id.uuidString)"
        case .summary(let summary): return "summary-\(summary.id.uuidString)"
        }
    }

    var category: WordNoteCategory {
        switch self {
        case .memo: return .personalMemo
        case .summary: return .verseSummary
        }
    }

    /// 정렬 기준 — 개인 묵상은 마지막 수정순(`updatedAt`), 말씀 요약은 쓴 순서(`createdAt`, 저널 성격).
    var sortDate: Date {
        switch self {
        case .memo(let memo): return memo.updatedAt
        case .summary(let summary): return summary.createdAt
        }
    }

    var contentText: String {
        switch self {
        case .memo(let memo): return memo.contentText
        case .summary(let summary): return summary.contentText
        }
    }

    var pendingIndexRefresh: Bool {
        switch self {
        case .memo(let memo): return memo.pendingIndexRefresh
        case .summary(let summary): return summary.pendingIndexRefresh
        }
    }

    var bookId: Int {
        switch self {
        case .memo(let memo): return memo.bookId
        case .summary(let summary): return summary.bookId
        }
    }

    var chapter: Int {
        switch self {
        case .memo(let memo): return memo.chapter
        case .summary(let summary): return summary.chapter
        }
    }

    var verse: Int? {
        switch self {
        case .memo(let memo): return memo.verse
        case .summary(let summary): return summary.verse
        }
    }

    /// 개인 묵상이 속한 폴더 id. 말씀 요약은 폴더가 없어 항상 nil.
    var folderID: UUID? {
        if case .memo(let memo) = self { return memo.folder?.id }
        return nil
    }

    var isMemo: Bool {
        if case .memo = self { return true }
        return false
    }

    var isPinned: Bool {
        switch self {
        case .memo(let memo): return memo.isPinned
        case .summary(let summary): return summary.isPinned
        }
    }

    /// 목록 행(`WordNoteRowView`)과 최근 노트 카드(`WordNoteRecentEmptyState`)가 같은 로직·값을 쓰도록 여기 모아 둔 프로퍼티들(`previewTitle` 등).
    var previewTitle: String {
        let trimmed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let emptyLabel = category == .personalMemo ? "새 메모" : "새 말씀 요약"
        guard !trimmed.isEmpty else { return emptyLabel }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return String(firstLine.prefix(40))
    }

    /// 미리보기 줄 — `previewTitle`(첫 줄)이 쓰고 남은 본문 나머지. 나머지가 없으면 nil.
    var previewSnippet: String? {
        let trimmed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "\n", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        let rest = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        return String(rest.prefix(80))
    }

    var coordinateLabel: String {
        let bookName = BooksProvider.shared.book(id: bookId)?.nameKo ?? "\(bookId)권"
        var label = "\(bookName) \(chapter)장"
        if let verse {
            label += " \(verse)절"
        }
        return label
    }

    /// 말씀 요약은 쓴 날짜(`createdAt`), 개인 묵상은 마지막 수정일(`updatedAt`) — `sortDate`와 같은 기준.
    var dateLabel: String? {
        let date: Date
        switch self {
        case .memo(let memo): date = memo.updatedAt
        case .summary(let summary): date = summary.createdAt
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

/// 테마 배경을 고른 경우에만 시스템 내비게이션 바 배경을 테마색으로 바꾼다(고르지 않았으면 아무것도 바꾸지 않음).
/// `BibleReadingView.swift`의 같은 이름 모디파이어와 같은 패턴이다.
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    // `.toolbarColorScheme` 판정을 위해 `Color.resolve(in:)`에 넘길 현재 환경.
    // `Color(hex:)`의 고정 RGB라 라이트/다크 모드와 무관하게 같은 값이 나온다.
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        // `ToolbarPlacement.navigationBar`는 macOS에 없어 iOS 전용이고, macOS는 아래 `.windowToolbar` 분기에서 처리한다.
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // 배경 휘도로 `.toolbarColorScheme`을 명시한다. 지정하지 않으면 iOS가 앱의 라이트/다크 모드만 보고
                // 바 아이템 색을 정해, 어두운 테마 배경 위에 어두운 아이템이 남아 안 보일 수 있다.
                // 휘도가 낮으면 `.dark`(밝은 아이템), 높으면 `.light`(어두운 아이템).
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
        } else {
            content
        }
        #elseif os(macOS)
        // macOS 창 통합 툴바(`.windowToolbar`) 배경을 테마색에 맞춘다 — 연구 문서/내 설교/성경 조회와 같은 처리(2026-10-03).
        // 이전에는 이 화면만 macOS를 그대로 통과시켜, 타이틀 띠가 시스템 재질(본문보다 밝고 마우스 오버 시 색이 변함)로
        // 그려져 본문·사이드바 상단과 색이 달랐다.
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

struct WordNoteHomeView: View {
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        if isPhone {
            WordNoteListContent(isPhoneLayout: true, selectedItem: nil)
        } else {
            WordNoteSplitContent()
        }
    }
}

private struct WordNoteSplitContent: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: WordNoteItem?

    /// 빈 상세 화면의 "최근 노트" 카드용. `WordNoteListContent`의 목록 로딩과 분리해
    /// 가장 최근 항목 1개만 `fetchLimit = 1`로 조회한다.
    @State private var mostRecentItem: WordNoteItem?

    /// 상세 빈 화면에도 테마 배경을 적용하기 위한 읽기 전용 접근.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        HStack(spacing: 0) {
            // 분류 트리 열(약 200)과 목록(약 300)을 합친 폭.
            WordNoteListContent(isPhoneLayout: false, selectedItem: $selectedItem)
                .frame(minWidth: 460, idealWidth: 560, maxWidth: 720)

            // 목록/본문 구분선 — 툴바(타이틀·아이콘) 영역까지 올라가지 않도록 safe area 상단만큼 띄워 시작한다.
            #if os(macOS)
            GeometryReader { geo in
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .padding(.top, geo.safeAreaInsets.top)
            }
            .frame(width: 1)
            #else
            Divider()
            #endif

            Group {
                if let selectedItem {
                    destinationView(for: selectedItem)
                        .id(selectedItem.id)
                } else {
                    WordNoteRecentEmptyState(recentItem: mostRecentItem) { item in
                        selectedItem = item
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(settings.bibleBackgroundColor ?? Color.clear)
                }
            }
        }
        // 항목을 선택하면 왼쪽 사이드바를 숨기고, 선택 해제/화면 이탈 시 복원한다(`SidebarVisibilityRequest` 계약).
        // `WordNoteItem`은 Equatable이 아니라 `id`로 비교한다. macOS는 사이드바를 접을 필요가 없어 iOS로 제한한다.
        #if os(iOS)
        .onChange(of: selectedItem?.id) { oldValue, newValue in
            if newValue != nil && oldValue == nil {
                SidebarVisibilityRequest.shared.requestHide()
            } else if newValue == nil && oldValue != nil {
                SidebarVisibilityRequest.shared.requestRestore()
            }
        }
        .onDisappear {
            guard selectedItem != nil else { return }
            SidebarVisibilityRequest.shared.requestRestore()
        }
        #endif
        // 처음 뜰 때와 선택 해제로 빈 상태가 다시 보일 때마다 최근 항목을 새로 조회한다(macOS·iOS 공통).
        .onAppear { reloadMostRecent() }
        .onChange(of: CloudSyncMonitor.shared.remoteImportRevision) { _, _ in
            reloadMostRecent()
        }
        .onChange(of: selectedItem?.id) { _, newValue in
            if newValue == nil { reloadMostRecent() }
        }
    }

    private func reloadMostRecent() {
        var memoDescriptor = FetchDescriptor<UserMemo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        memoDescriptor.fetchLimit = 1
        var summaryDescriptor = FetchDescriptor<VerseSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        summaryDescriptor.fetchLimit = 1
        let latestMemo = (try? modelContext.fetch(memoDescriptor))?.first
        let latestSummary = (try? modelContext.fetch(summaryDescriptor))?.first
        switch (latestMemo, latestSummary) {
        case let (memo?, summary?):
            mostRecentItem = memo.updatedAt >= summary.createdAt ? .memo(memo) : .summary(summary)
        case let (memo?, nil):
            mostRecentItem = .memo(memo)
        case let (nil, summary?):
            mostRecentItem = .summary(summary)
        case (nil, nil):
            mostRecentItem = nil
        }
    }
}

/// 상세 패널이 비어 있을 때 보여주는 최근 노트 카드. 노트가 하나도 없으면(`recentItem == nil`)
/// 카드 없이 안내 문구만 보인다.
private struct WordNoteRecentEmptyState: View {
    let recentItem: WordNoteItem?
    let onSelect: (WordNoteItem) -> Void

    private var settings: UserSettingsStore { .shared }
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    /// 카드가 놓인 배경이 어두운지 — `WordNoteListContent.isDarkTheme`/`WordNoteRowView.isDarkSurface`와 같은 공식.
    private var isDarkTheme: Bool {
        if let background = settings.bibleBackgroundColor {
            let resolved = background.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            return luminance < 0.5
        }
        return colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("아직 선택된 노트가 없습니다")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
            if let recentItem {
                Button {
                    onSelect(recentItem)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("최근 노트")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                        Text(recentItem.previewTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(settings.bibleTextColor ?? .primary)
                            .lineLimit(1)
                        Text(recentItem.coordinateLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(recentItem.category.spineColor(onDark: isDarkTheme))
                        if let dateLabel = recentItem.dateLabel {
                            Text(dateLabel)
                                .font(.caption2)
                                .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? .secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: 280, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(settings.bibleTextColor?.opacity(0.05) ?? Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(settings.bibleTextColor?.opacity(0.15) ?? Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@ViewBuilder
private func destinationView(for item: WordNoteItem) -> some View {
    switch item {
    case .memo(let memo):
        // 편집기 상단의 성경 좌표 편집 영역은 숨기고 읽기전용 좌표 라벨만 보이게 한다
        // (`MemoPresentationContext.wordNoteList`, MemoDetailView.swift 참고).
        MemoDetailView(memo: memo, presentationContext: .wordNoteList)
    case .summary(let summary):
        // `.memo` 케이스와 같은 이유로 `.wordNoteList`를 쓴다 — 기본 `.standalone`은 화면 영역이
        // 기기 가로폭보다 커져 잘린다(`WordSummaryEditorView.WordSummaryPresentationContext.wordNoteList` 참고).
        WordSummaryEditorView(summary: summary, presentationContext: .wordNoteList)
    }
}

private struct WordNoteListContent: View {
    @Environment(\.modelContext) private var modelContext

    let isPhoneLayout: Bool
    var selectedItem: Binding<WordNoteItem?>?

    @State private var allMemos: [UserMemo] = []
    @State private var allSummaries: [VerseSummary] = []
    @State private var folders: [MemoFolder] = []
    @State private var categoryFilter: WordNoteCategoryFilter = .all
    @State private var searchText: String = ""
    @State private var isNewFolderPresented = false
    @State private var newFolderName = ""
    /// 분류 트리(`categoryTreeColumn`) "성경별" 구약/신약 `DisclosureGroup` 펼침 상태. 기본은 접힘.
    @State private var expandedTestaments: Set<Book.Testament> = []
    // 폴더 관리 상태 — 이름 변경/삭제는 alert·dialog가 닫히며 바인딩이 먼저 비워질 수 있어 대상 객체를 별도 상태로 들고 있는다.
    @State private var isRenameFolderPresented = false
    @State private var folderBeingRenamed: MemoFolder?
    @State private var renameFolderName = ""
    @State private var isDeleteFolderPresented = false
    @State private var folderPendingDeletion: MemoFolder?
    @State private var folderErrorMessage: String?
    /// "새 폴더…"를 "폴더로 이동" 메뉴에서 눌렀을 때, 폴더를 만든 뒤 옮길 묵상 id들.
    @State private var pendingMoveMemoIDs: [UUID] = []
    /// 여러 개 선택 모드(폴더로 한꺼번에 이동용). 개인 묵상만 선택 대상이다.
    @State private var isSelecting = false
    @State private var selectedMemoIDs: Set<UUID> = []
    /// 드래그 앤 드롭 중 지금 올라가 있는 트리 행(강조 표시용).
    @State private var dropTargetFilter: WordNoteCategoryFilter?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    /// 테마 배경/글자색 읽기 전용 접근.
    private var settings: UserSettingsStore { .shared }

    private var mergedItems: [WordNoteItem] {
        let items: [WordNoteItem] = allMemos.map { .memo($0) } + allSummaries.map { .summary($0) }
        return items.sorted { $0.sortDate > $1.sortDate }
    }

    private var filteredItems: [WordNoteItem] {
        var result = mergedItems
        switch categoryFilter {
        case .all:
            break
        case .category(let category):
            result = result.filter { $0.category == category }
        case .book(let bookId):
            result = result.filter { $0.bookId == bookId }
        case .folder(let folderID):
            result = result.filter { $0.folderID == folderID }
        case .unfiled:
            result = result.filter { $0.isMemo && $0.folderID == nil }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter { $0.contentText.localizedCaseInsensitiveContains(trimmed) }
        }
        return result
    }

    /// 분류 트리 행의 개수 배지와 목록 헤더가 쓴다. 검색어는 제외하고 `mergedItems` 기준으로 센다
    /// (입력 중인 검색어에 따라 분류 개수가 바뀌지 않게).
    private func count(for filter: WordNoteCategoryFilter) -> Int {
        switch filter {
        case .all: return mergedItems.count
        case .category(let category): return mergedItems.filter { $0.category == category }.count
        case .book(let bookId): return mergedItems.filter { $0.bookId == bookId }.count
        case .folder(let folderID): return mergedItems.filter { $0.folderID == folderID }.count
        case .unfiled: return mergedItems.filter { $0.isMemo && $0.folderID == nil }.count
        }
    }

    /// 목록 헤더용 — 지금 선택된 분류의 제목.
    private var filterTitle: String {
        switch categoryFilter {
        case .all: return "전체"
        case .category(let category): return category.rawValue
        case .book(let bookId): return BooksProvider.shared.book(id: bookId)?.nameKo ?? "\(bookId)권"
        case .folder(let folderID): return folders.first(where: { $0.id == folderID })?.name ?? "폴더"
        case .unfiled: return "미분류"
        }
    }

    /// "성경별" 트리에 보여줄 책 — 노트가 하나라도 있는 책만 추린다(66권 전부는 대부분 0건).
    /// 구약/신약 구분은 `Book.testament`를 쓴다.
    private func booksWithNotes(in testament: Book.Testament) -> [Book] {
        let bookIdsWithNotes = Set(mergedItems.map { $0.bookId })
        return BooksProvider.shared.books.filter {
            $0.testament == testament && bookIdsWithNotes.contains($0.bookId)
        }
    }

    /// 카테고리 캡슐 버튼(아이폰). 선택 시 `AccentColor` 테두리 + 12% 틴트 + 굵은 accent 글자색,
    /// 비선택 시 테두리/글자색은 화면 테마(`settings.bibleTextColor`)를 따른다 — 퍼스널 컬러는 "선택됨" 강조에만 쓴다.
    private func categoryCapsuleButton(_ filter: WordNoteCategoryFilter, title: String) -> some View {
        let isSelected = categoryFilter == filter
        // 색 계산은 명시적 `Color` 상수로 분리했다 — 삼항/옵셔널 체이닝/`??`를 모디파이어 체인에 인라인하면
        // 타입 추론이 시간 초과된다.
        let textColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.55) ?? Color.secondary)
        let fillColor: Color = isSelected ? Color("AccentColor").opacity(0.12) : Color.clear
        let borderColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.35) ?? Color.secondary.opacity(0.35))
        return Button {
            categoryFilter = filter
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .foregroundStyle(textColor)
                .background(
                    Capsule().fill(fillColor)
                )
                .overlay(
                    Capsule().strokeBorder(borderColor, lineWidth: 1.4)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// 캡슐 아래 콘텐츠 시작부의 장식 구분선(가로선-sparkle-가로선, wood 톤).
    /// `SearchView.menuContentOrnamentalDivider`/`DocumentsHomeView.searchContentOrnamentalDivider`와
    /// 같은 모양이며 각 파일에서 private이라 옮겨 적었다. List 밖 VStack용이라 `.listRowSeparator`/`.listRowBackground`는 없다.
    private var wordNoteContentOrnamentalDivider: some View {
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

    // MARK: - 분류 트리 (아이패드·맥 전용, 2026-09-12 신설)
    //
    // 아이패드·맥은 분류 트리 | 목록 | 내용 3단이다. 아이폰(`phoneContent`)은 캡슐 필터를 쓰므로 이 트리를 쓰지 않는다.
    // "노트 종류"는 캡슐과 같은 3항목을 트리 행으로 그린 것이라 `categoryFilter` 상태·필터링 로직을 공유한다.
    // 최근/즐겨찾기는 전역 사이드바와 중복이라 넣지 않았다.

    // 분류 트리(아이패드·맥) 글꼴 — macOS는 텍스트 스타일 간 크기 차이가 작아(caption/footnote 10pt, subheadline 11pt) 한 단계 키운 값을 명시한다.
    // 섹션 제목 10→12, 행 제목 11→13, 개수/안내 10→12, 아이콘 13→15. 아이패드는 기존 스타일 그대로.
    private var treeSectionFont: Font {
        #if os(macOS)
        .system(size: 12, weight: .bold)
        #else
        .caption.weight(.bold)
        #endif
    }
    private var treeRowFont: Font {
        #if os(macOS)
        .system(size: 13, weight: .semibold)
        #else
        .subheadline.weight(.semibold)
        #endif
    }
    private var treeCountFont: Font {
        #if os(macOS)
        .system(size: 12)
        #else
        .caption
        #endif
    }
    private var treeIconSize: CGFloat {
        #if os(macOS)
        15
        #else
        13
        #endif
    }
    /// 글자가 커진 만큼 macOS 트리 열 폭도 넓힌다(200→224).
    private static var treeColumnWidth: CGFloat {
        #if os(macOS)
        224
        #else
        200
        #endif
    }

    private var categoryTreeColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("노트 종류")
                    .font(treeSectionFont)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                treeRow(.all, title: "전체", systemImage: "list.bullet", count: count(for: .all))
                ForEach(WordNoteCategory.allCases) { category in
                    treeRow(
                        .category(category), title: category.rawValue,
                        systemImage: category == .personalMemo ? "note.text" : "doc.text",
                        count: count(for: .category(category)), spine: category.spineColor(onDark: isDarkTheme)
                    )
                }

                folderTreeSection

                let oldTestamentBooks = booksWithNotes(in: .old)
                let newTestamentBooks = booksWithNotes(in: .new)
                if !oldTestamentBooks.isEmpty || !newTestamentBooks.isEmpty {
                    Divider().padding(.vertical, 8).padding(.horizontal, 14)
                    Text("성경별")
                        .font(treeSectionFont)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 2)
                    testamentDisclosure(title: "구약", testament: .old, books: oldTestamentBooks)
                    testamentDisclosure(title: "신약", testament: .new, books: newTestamentBooks)
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// 분류 트리 행 하나(노트 종류/성경별 공용). `spine`이 있으면 카테고리 색과 같은 왼쪽 색선을 그린다.
    /// 성경별 책 행은 대응되는 색이 없어 spine을 두지 않는다.
    private func treeRow(
        _ filter: WordNoteCategoryFilter, title: String, systemImage: String, count: Int, spine: Color? = nil
    ) -> some View {
        let isSelected = categoryFilter == filter
        // 색 계산을 명시적 `Color` 상수로 분리(타입 추론 시간 초과 방지, `categoryCapsuleButton` 참고).
        let textColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor ?? .primary)
        let iconColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.6) ?? .secondary)
        let fillColor: Color = isSelected ? Color("AccentColor").opacity(0.14) : Color.clear
        return Button {
            categoryFilter = filter
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: treeIconSize))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                Text(title)
                    .font(treeRowFont)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(treeCountFont)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 7)
            .padding(.trailing, 10)
            .padding(.leading, 11)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(spine ?? Color.clear)
                    .frame(width: 3)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
    }

    /// "성경별" 아래 구약/신약 한 그룹. 책이 없으면 아무것도 그리지 않는다(한쪽 구약/신약만 비었을 수 있다).
    @ViewBuilder
    private func testamentDisclosure(title: String, testament: Book.Testament, books: [Book]) -> some View {
        if !books.isEmpty {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedTestaments.contains(testament) },
                set: { isOn in
                    if isOn { expandedTestaments.insert(testament) } else { expandedTestaments.remove(testament) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(books) { book in
                        treeRow(.book(bookId: book.bookId), title: book.nameKo, systemImage: "book.closed", count: count(for: .book(bookId: book.bookId)))
                    }
                }
                .padding(.leading, 10)
            } label: {
                Text(title)
                    .font(treeRowFont)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            .padding(.horizontal, 14)
            .tint(settings.bibleTextColor?.opacity(0.6) ?? .secondary)
        }
    }

    /// 목록 열 머리글(아이패드·맥 전용) — 지금 선택된 분류 제목 + 개수.
    /// 아이폰은 캡슐 자체가 이미 선택 상태를 보여줘 따로 두지 않는다.
    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(filterTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(1)
            Spacer()
            Text("\(filteredItems.count)개의 노트")
                .font(.caption)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? .secondary)
            selectToggleButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    /// 목록(`List`) — 아이폰·아이패드·맥이 공유한다.
    private var wordNoteList: some View {
        List {
            ForEach(filteredItems) { item in
                rowContent(for: item)
            }
            .onDelete { offsets in
                guard isPhoneLayout else { return }
                deleteItems(at: offsets)
            }
        }
        .listStyle(.plain)
        // 시스템 리스트 배경을 끄고 테마 배경으로 교체한다(테마 미선택이면 clear).
        // 행마다 흰 배경이 남지 않도록 `rowContent`에서도 `.listRowBackground(Color.clear)`를 지정한다.
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // 시스템 기본 구분선은 임의의 테마 배경 위에서 거의 안 보일 수 있어 wood 톤을 옅게(0.3) 지정한다.
        .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.3))
        .searchable(text: $searchText, prompt: "검색")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting { selectionBar }
        }
    }

    /// 아이폰 전용 콘텐츠 — 캡슐 필터 + 구분선 + 목록.
    private var phoneContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                categoryCapsuleButton(.all, title: "전체")
                ForEach(WordNoteCategory.allCases) { category in
                    categoryCapsuleButton(.category(category), title: category.rawValue)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(settings.bibleTextColor?.opacity(0.1) ?? Color.secondary.opacity(0.12))
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            phoneFolderBar
                .padding(.horizontal)
                .padding(.bottom, 8)

            wordNoteContentOrnamentalDivider
            wordNoteList
        }
    }

    /// 아이패드·맥 전용 콘텐츠 — 분류 트리 | 목록. 상세(내용) 열은 이 view
    /// 바깥, `WordNoteSplitContent`가 그 옆에 나란히 그린다.
    private var splitTreeContent: some View {
        HStack(spacing: 0) {
            categoryTreeColumn
                .frame(width: Self.treeColumnWidth)

            Divider()

            VStack(spacing: 0) {
                listHeader
                wordNoteContentOrnamentalDivider
                wordNoteList
            }
        }
    }

    var body: some View {
        // 아이폰은 캡슐 필터+목록(`phoneContent`), 아이패드·맥은 분류 트리가 추가된 `splitTreeContent`.
        // `Group`으로 감싸 아래 화면 전체 모디파이어는 분기와 무관하게 한 번만 적용된다.
        Group {
            if isPhoneLayout {
                phoneContent
            } else {
                splitTreeContent
            }
        }
        // 검색창+필터 줄은 `List` 바깥이라 `List`의 `.background()`가 닿지 않아, 전체에도 테마 배경을 칠한다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .navigationTitle("말씀 노트")
        .macSerifTitle("말씀 노트")
        // 탭 최상위 화면이라 뒤로가기가 없어, automatic이면 큰 제목이 별도 줄로 그려져 툴바 아이콘 왼쪽이 낭비된다.
        // inline으로 제목과 아이콘을 한 줄에 합친다(macOS엔 이 모디파이어가 없어 iOS로 제한).
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // 시스템 내비게이션 바 배경을 테마에 맞춘다(`ThemedNavigationBarBackgroundModifier`).
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        .onAppear {
            // 동기화로 도착한 같은 이름 폴더를 먼저 하나로 합친 뒤 목록을 읽는다.
            MemoFolderMaintenance.deduplicate(in: modelContext)
            reload()
            // 사이드바 "고정됨"/"최근"에서 진입했을 수 있다(`WordNoteSelectionRequest.swift` 참고).
            // `reload()`로 `allMemos`/`allSummaries`가 채워진 뒤라야 대상 UUID를 찾을 수 있어 이 순서로 둔다.
            applyPendingSelectionRequest()
        }
        // 이미 떠 있는 상태에서 사이드바가 다른 항목을 요청한 경우용(첫 진입은 위 `.onAppear`가 처리).
        .onChange(of: CloudSyncMonitor.shared.remoteImportRevision) { _, _ in
            reload()
        }
        .onChange(of: WordNoteSelectionRequest.shared.requestedTarget) { _, _ in
            applyPendingSelectionRequest()
        }
        .toolbar {
            #if os(iOS)
            // 시스템 기본 타이틀 색은 앱이 입힌 테마 배경을 몰라 어두운 테마에서도 검정으로 남는다.
            // 색을 직접 지정한 `Text`로 `.principal`을 덮어쓴다(`.navigationTitle`은 시스템 내부용으로 유지).
            ToolbarItem(placement: .principal) {
                // 성곡 세리프체(CC BY-ND, 설정 > 라이센스 고지 참고). Regular 한 굵기뿐이라 `.semibold`는 화면에서만
                // 합성 볼드로 그려지며 폰트 파일 자체는 변경하지 않는다.
                Text("말씀 노트")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { createNewMemo() } label: { Text("개인 묵상 추가").font(.body) }
                    Button { createNewSummary() } label: { Text("말씀 요약 추가").font(.body) }
                } label: {
                    // 서재 금박(`JBCHCategoryPalette.gold`) 채움 원형 배경 — 이 화면의 핵심 동작(메모 추가)에 배정한 색(흰 아이콘 대비 7.32:1).
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(JBCHCategoryPalette.gold, in: Circle())
                }
                .help("새 항목")
            }
        }
        .alert("새 폴더", isPresented: $isNewFolderPresented) {
            TextField("폴더 이름", text: $newFolderName)
            Button("취소", role: .cancel) {
                newFolderName = ""
                pendingMoveMemoIDs = []
            }
            Button("만들기") { createFolder() }
        } message: {
            Text(pendingMoveMemoIDs.isEmpty ? "개인 묵상을 묶어 둘 폴더 이름을 입력하세요." : "폴더를 만들고 선택한 묵상을 옮깁니다.")
        }
        .alert("폴더 이름 변경", isPresented: $isRenameFolderPresented) {
            TextField("폴더 이름", text: $renameFolderName)
            Button("취소", role: .cancel) { folderBeingRenamed = nil }
            Button("변경") { commitRenameFolder() }
        }
        .confirmationDialog(
            "폴더 삭제", isPresented: $isDeleteFolderPresented, titleVisibility: .visible, presenting: folderPendingDeletion
        ) { folder in
            Button("'\(folder.name)' 삭제", role: .destructive) { deleteFolder(folder) }
            Button("취소", role: .cancel) {}
        } message: { folder in
            Text("이 폴더의 개인 묵상 \(count(for: .folder(folder.id)))개는 삭제되지 않고 '미분류'로 이동합니다.")
        }
        .alert("폴더", isPresented: Binding(
            get: { folderErrorMessage != nil },
            set: { if !$0 { folderErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(folderErrorMessage ?? "")
        }
        // File 메뉴 "새 메모 ⌘N" / "새 폴더 ⇧⌘N" — AppCommands.swift 참고. "새 메모"는 개인 묵상을 새로 만든다.
        .focusedSceneValue(\.newMemoAction) { createNewMemo() }
        .focusedSceneValue(\.newFolderAction) { beginNewFolder() }
    }

    @ViewBuilder
    private func rowContent(for item: WordNoteItem) -> some View {
        if isSelecting {
            selectionRow(for: item)
        } else if isPhoneLayout {
            NavigationLink {
                destinationView(for: item)
            } label: {
                WordNoteRowView(item: item)
            }
            // 이 행 셀 배경을 명시적으로 지워야 List 배경(테마색)이 비친다.
            // `.scrollContentBackground(.hidden)`은 컨테이너 배경만 바꾸고 각 행 셀 배경은 투명하게 하지 않는다.
            .listRowBackground(Color.clear)
            .contextMenu { rowContextMenu(for: item) }
        } else {
            dragSource(
                WordNoteRowView(item: item)
                    .contentShape(Rectangle())
                    .listRowBackground(
                        selectedItem?.wrappedValue?.id == item.id
                            ? Color("AccentColor").opacity(0.15) : Color.clear
                    )
                    .onTapGesture {
                        selectedItem?.wrappedValue = item
                    }
                    .contextMenu { rowContextMenu(for: item) },
                item: item
            )
        }
    }

    /// 행 컨텍스트 메뉴(길게 누르기/우클릭) — 고정, 폴더로 이동(개인 묵상만), 삭제.
    @ViewBuilder
    private func rowContextMenu(for item: WordNoteItem) -> some View {
        Button {
            togglePin(item)
        } label: {
            Label(item.isPinned ? "고정 해제" : "고정", systemImage: item.isPinned ? "pin.slash" : "pin")
        }
        if case .memo(let memo) = item {
            Menu {
                moveMenuContent(for: [memo.id])
            } label: {
                Label("폴더로 이동", systemImage: "folder")
            }
        }
        Button(role: .destructive) {
            delete(item)
        } label: {
            Label("삭제", systemImage: "trash")
        }
    }

    /// 선택 모드의 행 — 개인 묵상만 체크할 수 있고(말씀 요약은 폴더가 없다), 탭하면 열지 않고 선택만 토글한다.
    private func selectionRow(for item: WordNoteItem) -> some View {
        var isChecked = false
        if case .memo(let memo) = item { isChecked = selectedMemoIDs.contains(memo.id) }
        let checkColor: Color = isChecked ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.4) ?? Color.secondary)
        let symbol = item.isMemo ? (isChecked ? "checkmark.circle.fill" : "circle") : "minus.circle"
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(checkColor)
            WordNoteRowView(item: item)
        }
        .opacity(item.isMemo ? 1 : 0.4)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .onTapGesture { toggleSelection(item) }
    }

    /// 아이패드·맥 — 개인 묵상 행을 분류 트리의 폴더로 끌어다 놓아 옮길 수 있게 한다(말씀 요약은 끌 수 없다).
    @ViewBuilder
    private func dragSource<V: View>(_ content: V, item: WordNoteItem) -> some View {
        if case .memo(let memo) = item {
            content.draggable("memo:\(memo.id.uuidString)")
        } else {
            content
        }
    }

    // MARK: - 폴더 (분류 트리 섹션 / 폴더 칩 / 관리 / 이동)

    /// 지금 보이는 배경이 어두운지 — 폴더 책등 색 변형 선택용(`DocumentsHomeView.isDarkBibleBackground`와 같은 공식).
    private var isDarkTheme: Bool {
        if let background = settings.bibleBackgroundColor {
            let resolved = background.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            return luminance < 0.5
        }
        return colorScheme == .dark
    }

    /// 폴더 책등 색 — 연구 문서 문서함 카드와 같은 4색을 순서대로 순환한다(폴더에 색 필드가 없다).
    private func folderSpineColor(_ index: Int) -> Color {
        let onLight: [Color] = [JBCHCategoryPalette.gold, JBCHCategoryPalette.wood, JBCHCategoryPalette.slateTeal, JBCHCategoryPalette.wine]
        let onDark: [Color] = [JBCHCategoryPalette.gold, JBCHCategoryPalette.woodOnDark, JBCHCategoryPalette.slateTealOnDark, JBCHCategoryPalette.wineOnDark]
        let palette = isDarkTheme ? onDark : onLight
        return palette[index % palette.count]
    }

    private var unfiledSpineColor: Color {
        isDarkTheme ? JBCHCategoryPalette.shelfSlateOnDark : JBCHCategoryPalette.shelfSlate
    }

    /// 분류 트리의 "폴더" 섹션(아이패드·맥) — 폴더가 없어도 "+"가 보이도록 항상 그린다.
    private var folderTreeSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.vertical, 8).padding(.horizontal, 14)
            HStack {
                Text("폴더")
                    .font(treeSectionFont)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                Spacer()
                Button {
                    beginNewFolder()
                } label: {
                    Image(systemName: "plus")
                        .font(treeSectionFont)
                        .foregroundStyle(JBCHCategoryPalette.gold)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("새 폴더")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 2)

            ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                let filter = WordNoteCategoryFilter.folder(folder.id)
                memoDropTarget(
                    treeRow(filter, title: folder.name, systemImage: "folder", count: count(for: filter), spine: folderSpineColor(index))
                        .contextMenu {
                            Button { beginRenameFolder(folder) } label: { Label("이름 변경", systemImage: "pencil") }
                            Button(role: .destructive) { requestDeleteFolder(folder) } label: { Label("폴더 삭제", systemImage: "trash") }
                        },
                    filter: filter, folder: folder
                )
            }
            memoDropTarget(
                treeRow(.unfiled, title: "미분류", systemImage: "tray", count: count(for: .unfiled), spine: unfiledSpineColor),
                filter: .unfiled, folder: nil
            )
            if folders.isEmpty {
                Text("폴더를 만들어 개인 묵상을 묶어 보세요. 묵상을 끌어다 놓거나 행을 길게 눌러(우클릭) 옮길 수 있습니다.")
                    .font(treeCountFont)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? .secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }
        }
    }

    /// 트리 행을 개인 묵상 드롭 대상으로 만든다. `folder == nil`이면 "미분류"로 옮긴다.
    private func memoDropTarget<V: View>(_ content: V, filter: WordNoteCategoryFilter, folder: MemoFolder?) -> some View {
        content
            .overlay {
                if dropTargetFilter == filter {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(JBCHCategoryPalette.gold, lineWidth: 1.5)
                        .padding(.horizontal, 6)
                }
            }
            .dropDestination(for: String.self) { payloads, _ in
                handleMemoDrop(payloads, into: folder)
            } isTargeted: { isTargeted in
                if isTargeted {
                    dropTargetFilter = filter
                } else if dropTargetFilter == filter {
                    dropTargetFilter = nil
                }
            }
    }

    private func handleMemoDrop(_ payloads: [String], into folder: MemoFolder?) -> Bool {
        var ids: [UUID] = []
        for payload in payloads where payload.hasPrefix("memo:") {
            ids += payload.dropFirst("memo:".count).split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        }
        guard !ids.isEmpty else { return false }
        moveMemos(ids, to: folder)
        return true
    }

    /// 아이폰 — 캡슐 아래 한 줄: 폴더 필터/관리 메뉴 + 선택 모드 토글.
    private var phoneFolderBar: some View {
        var isActive = false
        var title = "폴더"
        switch categoryFilter {
        case .folder(let folderID):
            isActive = true
            title = folders.first(where: { $0.id == folderID })?.name ?? "폴더"
        case .unfiled:
            isActive = true
            title = "미분류"
        default:
            break
        }
        let textColor: Color = isActive ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
        let fillColor: Color = isActive ? Color("AccentColor").opacity(0.12) : Color.clear
        let borderColor: Color = isActive ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.35) ?? Color.secondary.opacity(0.35))
        return HStack(spacing: 8) {
            Menu {
                phoneFolderMenuContent
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.caption)
                    Text(title)
                        .font(.subheadline.weight(isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(textColor)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(Capsule().fill(fillColor))
                .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1.2))
            }
            Spacer()
            selectToggleButton
        }
    }

    @ViewBuilder
    private var phoneFolderMenuContent: some View {
        Button {
            categoryFilter = .all
        } label: {
            Label("폴더 필터 해제", systemImage: "line.3.horizontal.decrease.circle")
        }
        if !folders.isEmpty { Divider() }
        ForEach(folders) { folder in
            Button {
                categoryFilter = .folder(folder.id)
            } label: {
                Text("\(folder.name) (\(count(for: .folder(folder.id))))")
            }
        }
        Button {
            categoryFilter = .unfiled
        } label: {
            Text("미분류 (\(count(for: .unfiled)))")
        }
        Divider()
        Button {
            beginNewFolder()
        } label: {
            Label("새 폴더…", systemImage: "folder.badge.plus")
        }
        if !folders.isEmpty {
            Menu("이름 변경") {
                ForEach(folders) { folder in
                    Button(folder.name) { beginRenameFolder(folder) }
                }
            }
            Menu("폴더 삭제") {
                ForEach(folders) { folder in
                    Button(folder.name, role: .destructive) { requestDeleteFolder(folder) }
                }
            }
        }
    }

    /// "폴더로 이동" 메뉴 항목들(행 컨텍스트 메뉴·선택 모드 바 공용).
    @ViewBuilder
    private func moveMenuContent(for ids: [UUID]) -> some View {
        Button {
            moveMemos(ids, to: nil)
        } label: {
            Label("미분류", systemImage: "tray")
        }
        if !folders.isEmpty { Divider() }
        ForEach(folders) { folder in
            Button {
                moveMemos(ids, to: folder)
            } label: {
                Label(folder.name, systemImage: "folder")
            }
        }
        Divider()
        Button {
            beginNewFolder(thenMove: ids)
        } label: {
            Label("새 폴더…", systemImage: "folder.badge.plus")
        }
    }

    // MARK: 선택 모드

    private var selectToggleButton: some View {
        let textColor: Color = isSelecting ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
        let borderColor: Color = isSelecting ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.35) ?? Color.secondary.opacity(0.35))
        return Button {
            isSelecting.toggle()
            if !isSelecting { selectedMemoIDs = [] }
        } label: {
            Text(isSelecting ? "완료" : "선택")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("여러 묵상을 선택해 폴더로 이동")
    }

    /// 지금 목록에 보이는(필터·검색 통과) 선택 항목만 — 필터를 바꿔 가려진 묵상이 모르는 사이 같이 옮겨지지 않게 한다.
    private var visibleSelectedMemoIDs: [UUID] {
        filteredItems.compactMap { item -> UUID? in
            if case .memo(let memo) = item, selectedMemoIDs.contains(memo.id) { return memo.id }
            return nil
        }
    }

    private var selectionBar: some View {
        let ids = visibleSelectedMemoIDs
        return VStack(spacing: 0) {
            Divider()
            HStack {
                Text(ids.isEmpty ? "묵상을 선택하세요" : "\(ids.count)개 선택")
                    .font(.subheadline)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Spacer()
                Menu {
                    moveMenuContent(for: ids)
                } label: {
                    Label("폴더로 이동", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(JBCHCategoryPalette.gold, in: Capsule())
                }
                .disabled(ids.isEmpty)
                .opacity(ids.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background {
            if let background = settings.bibleBackgroundColor {
                background
            } else {
                Rectangle().fill(.bar)
            }
        }
    }

    private func toggleSelection(_ item: WordNoteItem) {
        guard case .memo(let memo) = item else { return }
        if selectedMemoIDs.contains(memo.id) {
            selectedMemoIDs.remove(memo.id)
        } else {
            selectedMemoIDs.insert(memo.id)
        }
    }

    // MARK: 폴더 생성/이름 변경/삭제/이동

    private func beginNewFolder(thenMove ids: [UUID] = []) {
        pendingMoveMemoIDs = ids
        newFolderName = ""
        isNewFolderPresented = true
    }

    /// 같은 이름(공백·대소문자·전각 무시)의 폴더가 이미 있으면 새로 만들지 않고 그 폴더를 쓴다(중복 방지).
    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let moveIDs = pendingMoveMemoIDs
        pendingMoveMemoIDs = []
        newFolderName = ""
        guard !trimmed.isEmpty else { return }
        reload()
        let key = MemoFolderMaintenance.normalizedKey(trimmed)
        let folder: MemoFolder
        if let existing = folders.first(where: { MemoFolderMaintenance.normalizedKey($0.name) == key }) {
            folder = existing
        } else {
            folder = MemoFolder(name: trimmed)
            modelContext.insert(folder)
            try? modelContext.save()
            reload()
        }
        if moveIDs.isEmpty {
            categoryFilter = .folder(folder.id)
        } else {
            moveMemos(moveIDs, to: folder)
        }
    }

    private func beginRenameFolder(_ folder: MemoFolder) {
        folderBeingRenamed = folder
        renameFolderName = folder.name
        isRenameFolderPresented = true
    }

    private func commitRenameFolder() {
        defer { folderBeingRenamed = nil }
        guard let folder = folderBeingRenamed else { return }
        let trimmed = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        let key = MemoFolderMaintenance.normalizedKey(trimmed)
        if folders.contains(where: { $0.id != folder.id && MemoFolderMaintenance.normalizedKey($0.name) == key }) {
            folderErrorMessage = "같은 이름의 폴더가 이미 있습니다."
            return
        }
        folder.name = trimmed
        try? modelContext.save()
        reload()
    }

    private func requestDeleteFolder(_ folder: MemoFolder) {
        folderPendingDeletion = folder
        isDeleteFolderPresented = true
    }

    /// 폴더만 지운다 — 안의 묵상은 삭제하지 않고 폴더 없음("미분류")으로 돌린다(`MemoFolder.memos` 삭제 규칙 nullify와 같은 결과를 명시).
    private func deleteFolder(_ folder: MemoFolder) {
        let folderID = folder.id
        for memo in Array(folder.memos ?? []) {
            memo.folder = nil
        }
        modelContext.delete(folder)
        try? modelContext.save()
        if categoryFilter == .folder(folderID) { categoryFilter = .all }
        folderPendingDeletion = nil
        reload()
    }

    /// 개인 묵상을 폴더로 옮긴다(`folder == nil`이면 미분류). 수정일(`updatedAt`)은 건드리지 않아 목록 순서가 바뀌지 않는다.
    private func moveMemos(_ ids: [UUID], to folder: MemoFolder?) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        for memo in allMemos where idSet.contains(memo.id) && memo.folder?.id != folder?.id {
            memo.folder = folder
        }
        try? modelContext.save()
        selectedMemoIDs = []
        isSelecting = false
        reload()
    }

    private func reload() {
        do {
            allMemos = try modelContext.fetch(
                FetchDescriptor<UserMemo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            )
            // 같은 id의 말씀 요약이 둘 이상이면(동기화 중복) 목록 id(`summary-<id>`)가 겹쳐 SwiftUI가 undefined 동작을 하므로 하나만 남긴다.
            allSummaries = VerseSummaryDeduplication.uniqueById(try modelContext.fetch(
                FetchDescriptor<VerseSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            ))
            folders = try modelContext.fetch(
                FetchDescriptor<MemoFolder>(sortBy: [SortDescriptor(\.name)])
            )
        } catch {
            print("[WordNoteListContent] 목록 로드 실패: \(error)")
        }
    }

    /// 사이드바 "고정됨"/"최근"에서 넘어온 선택 요청을 실제 항목으로 바꿔 `selectedItem`에 반영한다.
    /// 폰 레이아웃(`selectedItem` 바인딩이 nil)에서는 아무 것도 하지 않는다.
    private func applyPendingSelectionRequest() {
        guard let target = WordNoteSelectionRequest.shared.requestedTarget else { return }
        let resolved: WordNoteItem?
        switch target {
        case .memo(let id):
            resolved = allMemos.first(where: { $0.id == id }).map { .memo($0) }
        case .summary(let id):
            resolved = allSummaries.first(where: { $0.id == id }).map { .summary($0) }
        }
        guard let resolved else { return }
        selectedItem?.wrappedValue = resolved
        WordNoteSelectionRequest.shared.clear()
    }

    /// `MemoHomeView.createNewMemo()`와 같은 기본 좌표 규칙(이번 세션 마지막 위치 →
    /// 없으면 창세기 1장).
    private func createNewMemo() {
        let bookId = LastBiblePositionTracker.shared.bookId ?? 1
        let chapter = LastBiblePositionTracker.shared.chapter ?? 1
        let memo = UserMemo(bookId: bookId, chapter: chapter)
        modelContext.insert(memo)
        try? modelContext.save()
        BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
        reload()
        selectedItem?.wrappedValue = .memo(memo)
    }

    /// `WordSummaryHomeView.createNewSummary()`와 같은 규칙 — `verse`는 항상 nil로
    /// 시작한다(사이드바 진입점이라 특정 절이 정해져 있지 않음).
    private func createNewSummary() {
        let bookId = LastBiblePositionTracker.shared.bookId ?? 1
        let chapter = LastBiblePositionTracker.shared.chapter ?? 1
        let summary = VerseSummary(bookId: bookId, chapter: chapter)
        modelContext.insert(summary)
        try? modelContext.save()
        BibleReferenceIndexingService.reindexWordSummary(summary, context: modelContext)
        reload()
        selectedItem?.wrappedValue = .summary(summary)
    }

    /// 이산적 액션이므로 즉시 저장한다(`DocumentsViewModel.togglePin`과 같은 원칙).
    private func togglePin(_ item: WordNoteItem) {
        switch item {
        case .memo(let memo): memo.isPinned.toggle()
        case .summary(let summary): summary.isPinned.toggle()
        }
        try? modelContext.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            delete(filteredItems[index], skipReload: true)
        }
        try? modelContext.save()
        reload()
    }

    private func delete(_ item: WordNoteItem, skipReload: Bool = false) {
        if selectedItem?.wrappedValue?.id == item.id {
            selectedItem?.wrappedValue = nil
        }
        switch item {
        case .memo(let memo):
            BibleReferenceIndexingService.removeMentions(
                sourceType: .memo, sourceId: memo.id.uuidString, context: modelContext
            )
            modelContext.delete(memo)
        case .summary(let summary):
            BibleReferenceIndexingService.removeMentions(
                sourceType: .wordSummary, sourceId: summary.id.uuidString, context: modelContext
            )
            modelContext.delete(summary)
        }
        guard !skipReload else { return }
        try? modelContext.save()
        reload()
    }
}

/// 개인 묵상 폴더(`MemoFolder`) 유지보수 — 같은 이름 폴더 병합.
/// CloudKit은 `@Attribute(.unique)`를 지원하지 않아, 여러 기기가 같은 이름의 폴더를 각각 만들면 동기화 후 이름이 같은 행이 둘 이상 남는다
/// (`SermonGatheringSeeder.deduplicate`와 같은 유형의 문제).
enum MemoFolderMaintenance {
    /// 이름 비교용 키 — 공백, 대소문자, 전각/반각 차이를 무시한다.
    static func normalizedKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    /// 가장 먼저 만든 폴더를 남기고, 중복 폴더의 묵상은 남긴 폴더로 옮긴 뒤 중복 폴더를 지운다. 이름이 빈 폴더는 건드리지 않는다.
    /// 변경이 없으면 저장하지 않는다(여러 번 불러도 안전 — 멱등).
    static func deduplicate(in context: ModelContext) {
        do {
            let all = try context.fetch(FetchDescriptor<MemoFolder>(sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
            var survivors: [String: MemoFolder] = [:]
            var didChange = false
            for folder in all {
                let key = normalizedKey(folder.name)
                guard !key.isEmpty else { continue }
                if let survivor = survivors[key] {
                    // 관계를 바꾸면 `folder.memos`가 함께 변하므로 복사본을 돈다.
                    for memo in Array(folder.memos ?? []) {
                        memo.folder = survivor
                    }
                    context.delete(folder)
                    didChange = true
                } else {
                    survivors[key] = folder
                }
            }
            if didChange { try context.save() }
        } catch {
            print("[MemoFolderMaintenance] 중복 폴더 정리 실패: \(error)")
        }
    }
}
