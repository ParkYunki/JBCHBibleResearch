//
//  WordNoteHomeView.swift
//  JBCHBibleResearch
//
//  [2026-08-13 신설] 사용자 요청 — "왼쪽 사이드바 [개인 묵상], [말씀 요약] 통합할 것 :
//  메뉴명 - [말씀 노트] / 카테고리로 분류할 것 : [개인 묵상], [말씀 요약] / 말씀 노트
//  메뉴 탭하면 리스트에서 리스트 항목 앞에 카테고리를 표시할 것 / 리스트 위에 검색창
//  옆에 카테고리 picker를 주어 선택된 카테고리 별로 조회할 수 있도록 할것."
//
//  기존 `MemoHomeView.swift`(개인 묵상, `UserMemo` 기반)와 `WordSummaryHomeView.swift`
//  (말씀 요약, `VerseSummary` 기반)를 이 화면 하나로 대체한다 — 두 파일은 삭제했다.
//  두 모델은 스키마가 다르므로(폴더/태그는 `UserMemo`에만 있음) 데이터 자체를 합치지
//  않고, `WordNoteItem`(이 파일 하단)이라는 얇은 열거형 래퍼로 둘을 한 목록에 섞어
//  보여주기만 한다 — 실제 편집은 기존 `MemoDetailView`/`WordSummaryEditorView`를
//  그대로 재사용한다(두 화면 모두 성경 조회 화면의 확대보기 액션바에서 "contextual"로
//  여는 경로가 그대로 남아 있어, 이 화면과 무관하게 계속 동작한다).
//
//  ⚠️ [범위 축소, 명확히 플래그] 기존 `MemoHomeView`엔 폴더별 목록 필터 메뉴가
//  있었지만, 이번 요청은 "검색창 옆 카테고리 picker" 하나만 명시했다 — 폴더 필터
//  UI는 이 통합 목록에서 뺐다(오버엔지니어링 방지). 폴더 배정 자체는 여전히
//  `MemoDetailView`의 폴더 메뉴에서 가능하고, ⌘⇧N "새 폴더" 메뉴 커맨드도 이 화면이
//  그대로 이어받아 동작한다(알림창만 남기고 필터 메뉴 UI는 없앤 것).
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

/// 통합 목록의 카테고리 — 사용자 요청 문구를 그대로 라벨로 쓴다.
enum WordNoteCategory: String, CaseIterable, Identifiable {
    case personalMemo = "개인 묵상"
    case verseSummary = "말씀 요약"

    var id: String { rawValue }
}

/// 검색창 옆 카테고리 picker의 선택값 — "전체"까지 포함해야 해서 `WordNoteCategory`
/// 자체가 아니라 한 단계 감싼 별도 enum을 쓴다.
enum WordNoteCategoryFilter: Hashable {
    case all
    case category(WordNoteCategory)
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

    /// 목록 정렬 기준 — 기존 각 화면의 정렬 원칙을 그대로 유지한다: 개인 묵상은
    /// "마지막 수정순"(`updatedAt`), 말씀 요약은 "쓴 순서"(`createdAt`, 저널 성격 —
    /// `WordSummaryHomeView.swift` 옛 상단 주석 참고).
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

    /// [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드 앱처럼 기능을
    /// 추가할 것. 고정됨."
    var isPinned: Bool {
        switch self {
        case .memo(let memo): return memo.isPinned
        case .summary(let summary): return summary.isPinned
        }
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
    @State private var selectedItem: WordNoteItem?

    var body: some View {
        HStack(spacing: 0) {
            WordNoteListContent(isPhoneLayout: false, selectedItem: $selectedItem)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            Divider()

            Group {
                if let selectedItem {
                    destinationView(for: selectedItem)
                        .id(selectedItem.id)
                } else {
                    VStack {
                        Spacer()
                        Text("항목을 선택하세요")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // [2026-08-21 추가] 사용자 요청("아이패드 수정사항") — "말씀노트 리스트에
        // 항목 탭시 - 왼쪽 사이드바 자동 숨김기능." `SidebarVisibilityRequest`
        // (Services/SidebarVisibilityRequest.swift)는 `BibleReadingContentView`가
        // "말씀 요약" 편집기를 열 때 이미 쓰던 것과 같은 싱글턴이다 — 여기서도
        // 같은 계약(열 때 hide, 닫을 때/화면을 떠날 때 restore)을 그대로
        // 재사용한다. `WordNoteItem`은 `Equatable`을 선언하지 않아
        // `.onChange(of: selectedItem)`을 바로 못 쓰므로, 이미 있는 `id: String`
        // (Equatable)로 비교한다 — 타입에 새 프로토콜 준수를 추가하는 대신
        // 가장 적은 변경으로 끝낸다. macOS는 사이드바를 접을 만큼 화면이 좁지
        // 않고(이 항목만 "(맥OS, iOS 공통)" 표기가 없다 — 사용자가 이 화면 하단
        // "성경 매칭 수정 영역 삭제"는 명시적으로 공통 표기했다는 점과 대비된다),
        // 기존 macOS 동작을 건드리지 않기 위해 iOS(아이폰/아이패드)로만 제한한다.
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
    }
}

@ViewBuilder
private func destinationView(for item: WordNoteItem) -> some View {
    switch item {
    case .memo(let memo):
        // [2026-08-21 수정] 사용자 요청("아이패드 수정사항", 맥OS·iOS 공통) —
        // "말씀노트 리스트에 항목 탭 - 에디터 화면의 상단 성경 매칭수정 영역은
        // 삭제할 것." 예전엔 기본값 `.standalone`이 그대로 쓰여 좌표 편집
        // 헤더(BookChapterPicker+절 Stepper)가 보였다 —
        // `MemoPresentationContext.wordNoteList`(MemoDetailView.swift 참고)로
        // 바꿔 읽기전용 좌표 라벨만 보이게 한다.
        MemoDetailView(memo: memo, presentationContext: .wordNoteList)
    case .summary(let summary):
        WordSummaryEditorView(summary: summary, presentationContext: .standalone)
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

    private var mergedItems: [WordNoteItem] {
        let items: [WordNoteItem] = allMemos.map { .memo($0) } + allSummaries.map { .summary($0) }
        return items.sorted { $0.sortDate > $1.sortDate }
    }

    private var filteredItems: [WordNoteItem] {
        var result = mergedItems
        if case .category(let category) = categoryFilter {
            result = result.filter { $0.category == category }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter { $0.contentText.localizedCaseInsensitiveContains(trimmed) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // 사용자 요청 — "리스트 위에 검색 창 옆에 카테고리 picker를 주어."
            HStack(spacing: 8) {
                TextField("검색", text: $searchText)
                    .font(.body)
                    .textFieldStyle(.roundedBorder)

                Picker("카테고리", selection: $categoryFilter) {
                    Text("전체").tag(WordNoteCategoryFilter.all)
                    ForEach(WordNoteCategory.allCases) { category in
                        Text(category.rawValue).tag(WordNoteCategoryFilter.category(category))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                // [2026-08-14 추가] 사용자 요청 — "[공통] 앱의 메뉴명이나, 기능관련
                // 소개, 그 외 텍스트는 시스템 기본 글꼴로 표현할 것 ... Picker
                // 타이틀 '카테고리'의 스타일도 시스템 기본 글꼴로 변경." 이 화면
                // 바깥의 `RootView`가 앱 전역에 `.appDefaultFont()`(내장 Paperlogy)를
                // 적용하고 있어, 명시적으로 `.font(.body)`(시스템 기본, 보통 크기)로
                // 덮어써야 한다 — SettingsView가 이미 같은 이유로 쓰는 방식과 동일.
                .font(.body)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

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
        }
        .navigationTitle("말씀 노트")
        .onAppear {
            reload()
            // [2026-08-18 추가] 사이드바 "고정됨"/"최근" 섹션에서 이 항목을 골라
            // 들어왔을 수 있다 — `WordNoteSelectionRequest.swift` 상단 주석 참고.
            // `reload()`가 방금 끝나 `allMemos`/`allSummaries`가 채워진 뒤라야
            // 대상 UUID를 실제 항목으로 찾을 수 있어 이 순서로 둔다.
            applyPendingSelectionRequest()
        }
        // 이 화면이 이미 떠 있는 채로 사이드바에서 다시 다른 항목을 골랐을 때만
        // 쓰인다(처음 여는 경우는 위 `.onAppear`가 이미 처리).
        .onChange(of: WordNoteSelectionRequest.shared.requestedTarget) { _, _ in
            applyPendingSelectionRequest()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { createNewMemo() } label: { Text("개인 묵상 추가").font(.body) }
                    Button { createNewSummary() } label: { Text("말씀 요약 추가").font(.body) }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .tint(.accentColor)
                .help("새 항목")
            }
        }
        .alert("새 폴더", isPresented: $isNewFolderPresented) {
            TextField("폴더 이름", text: $newFolderName)
            Button("취소", role: .cancel) { newFolderName = "" }
            Button("만들기") { createFolder() }
        }
        // 11장 File 메뉴 "새 메모 ⌘N" / "새 폴더 ⇧⌘N" — AppCommands.swift 참고.
        // 기존 MemoHomeView가 발행하던 것과 같은 키를 그대로 이어받는다("새 메모"는
        // 개인 묵상 하나를 새로 만든다 — 통합 목록에서 "새로 만들기" 메뉴의 첫 항목과
        // 같은 동작).
        .focusedSceneValue(\.newMemoAction) { createNewMemo() }
        .focusedSceneValue(\.newFolderAction) { isNewFolderPresented = true }
    }

    @ViewBuilder
    private func rowContent(for item: WordNoteItem) -> some View {
        if isPhoneLayout {
            NavigationLink {
                destinationView(for: item)
            } label: {
                WordNoteRowView(item: item)
            }
        } else {
            WordNoteRowView(item: item)
                .contentShape(Rectangle())
                .listRowBackground(
                    selectedItem?.wrappedValue?.id == item.id
                        ? Color.accentColor.opacity(0.15) : Color.clear
                )
                .onTapGesture {
                    selectedItem?.wrappedValue = item
                }
                .contextMenu {
                    // [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드
                    // 앱처럼 기능을 추가할 것. 고정됨." `DocumentRowView`의
                    // 컨텍스트 메뉴 고정 토글과 같은 위치 원칙.
                    Button {
                        togglePin(item)
                    } label: {
                        Label(item.isPinned ? "고정 해제" : "고정", systemImage: item.isPinned ? "pin.slash" : "pin")
                    }
                    Button(role: .destructive) {
                        delete(item)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
        }
    }

    private func reload() {
        do {
            allMemos = try modelContext.fetch(
                FetchDescriptor<UserMemo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            )
            allSummaries = try modelContext.fetch(
                FetchDescriptor<VerseSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            )
            folders = try modelContext.fetch(
                FetchDescriptor<MemoFolder>(sortBy: [SortDescriptor(\.name)])
            )
        } catch {
            print("[WordNoteListContent] 목록 로드 실패: \(error)")
        }
    }

    /// [2026-08-18 추가] `WordNoteSelectionRequest.swift` 상단 주석 참고 —
    /// 사이드바 "고정됨"/"최근" 섹션에서 특정 개인 묵상/말씀 요약을 골라 들어온
    /// 요청을 실제 항목으로 바꿔 `selectedItem`에 반영한다. 폰 레이아웃(`selectedItem`
    /// 바인딩이 nil)에서는 조용히 아무 것도 안 한다 — `SidebarNavigationView`
    /// 자체가 iPhone에서는 안 쓰이므로(그 화면 상단 주석 — macOS/iPadOS 전용,
    /// 아이폰은 `PhoneTabView`) 실제로는 이 경로를 안 탄다.
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

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = MemoFolder(name: trimmed)
        modelContext.insert(folder)
        try? modelContext.save()
        newFolderName = ""
        reload()
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

    /// [2026-08-18 추가] `DocumentsViewModel.togglePin`과 같은 원칙(이산적 액션,
    /// 즉시 저장).
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
