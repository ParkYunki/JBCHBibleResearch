//
//  SidebarNavigationView.swift
//  JBCHBibleResearch
//
//  macOS/iPadOS 메인 창: 왼쪽 사이드바(폭 200~280) + 오른쪽 본문.
//  최소 창 크기(1000×700)는 Scene 선언부(JBCHBibleResearchApp.swift)에서 처리한다.
//  시작 시 마지막 화면 복원과 View 메뉴(화면 전환 ⌘1-5, 사이드바 토글 ⌥⌘S)는
//  `.focusedSceneValue`로 이 화면의 로컬 상태를 노출받아 조작한다. 전역 싱글턴을
//  쓰지 않는 이유는 AppFocusedValues.swift 상단 주석 참고(멀티윈도우에서 창끼리
//  선택 상태가 공유되는 것을 피하기 위함).
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

struct SidebarNavigationView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    /// 테마 색상 설정(`bibleBackgroundColor`/`bibleTextColor`) 접근자.
    /// 사이드바도 오른쪽 콘텐츠와 같은 테마 색상을 따르게 한다.
    private var settings: UserSettingsStore { .shared }
    @State private var selection: AppSection? = SidebarNavigationView.initialSelection()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isSettingsPresented = false
    /// 사이드바 상단 검색 텍스트박스 입력값. `sidebarSearchBar`/`submitSidebarSearch()` 참고.
    @State private var sidebarSearchText: String = ""

    /// 검색결과에서 성경 조회로 push된 상태에서 다시 검색하면 검색결과로 돌아오게 하는
    /// detail 컬럼의 내비게이션 경로. push는 `selection`과 별개인 detail 스택 상태라
    /// `selection = .search`만으로는 pop되지 않는다.
    /// `NavigationPath`를 비우면 값 기반/목적지-클로저 `NavigationLink` push가 모두 pop되고,
    /// 스택과 루트 `SearchView`(viewModel 상태)는 유지된다. `.id(_:)`로 스택을 통째로
    /// 재생성하면 detail 컬럼 재연결과 충돌해 흰 화면이 뜨므로 쓰지 않는다.
    @State private var detailNavigationPath = NavigationPath()

    /// 사이드바 "고정됨/최근" 목록의 원본. `@Query`라 SwiftData 변경 시 자동 갱신된다.
    @Query(sort: \SourceDocument.uploadedAt, order: .reverse) private var sidebarDocuments: [SourceDocument]
    @Query(sort: \UserMemo.updatedAt, order: .reverse) private var sidebarMemos: [UserMemo]
    @Query(sort: \VerseSummary.createdAt, order: .reverse) private var sidebarSummaries: [VerseSummary]
    /// 성경 본문에 직접 붙는 주석 작업(형광펜 `VerseHighlight`, 메모 `VersePhraseNote`,
    /// 관주 `VerseCrossReference`)의 이력용 쿼리. 개인 주석(`UserMemo`)은 `sidebarMemos`가 담당한다.
    @Query(sort: \VerseHighlight.createdAt, order: .reverse) private var sidebarHighlights: [VerseHighlight]
    @Query(sort: \VersePhraseNote.updatedAt, order: .reverse) private var sidebarPhraseNotes: [VersePhraseNote]
    @Query(sort: \VerseCrossReference.updatedAt, order: .reverse) private var sidebarCrossReferences: [VerseCrossReference]

    /// macOS는 환경설정을 앱 메뉴(⌘,)로만 노출하지만 iPadOS엔 그 메뉴가 없어,
    /// 사이드바 툴바에 톱니바퀴 버튼을 둔다.
    private var showsSettingsToolbarButton: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        false
        #endif
    }

    /// 사이드바/인스펙터 동시 노출 방지 조율(`IPadSidebarInspectorCoordination.swift`)은
    /// 아이패드 전용이다. 판정 로직은 `showsSettingsToolbarButton`과 같지만 목적이 달라
    /// 별도 프로퍼티로 둔다.
    private var isIPadIdiom: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        false
        #endif
    }

    /// 공백을 뺀 길이가 2 미만이면 검색할 수 없다(엔터키도 `submitSidebarSearch()`에서
    /// 같은 기준으로 막는다).
    private var canSubmitSidebarSearch: Bool {
        sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: 6) {
            // 아이콘·placeholder·상자 배경을 고정 `.secondary`가 아니라 테마 글자색 기반으로 그린다.
            Image(systemName: "magnifyingglass")
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            TextField(
                "검색 (2글자 이상)",
                text: $sidebarSearchText,
                prompt: Text("검색 (2글자 이상)")
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
            )
                .textFieldStyle(.plain)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .onSubmit { submitSidebarSearch() }
            if !sidebarSearchText.isEmpty {
                Button {
                    sidebarSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                submitSidebarSearch()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitSidebarSearch)
        }
        .font(.body)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(settings.bibleTextColor?.opacity(0.2) ?? Color.clear, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// `SidebarSearchRequest`(그 파일 상단 주석 참고)로 검색어를 전달하고,
    /// `selection`을 `.search`로 바꿔 오른쪽 메인영역에 검색결과를 보여준다.
    private func submitSidebarSearch() {
        let trimmed = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        SidebarSearchRequest.shared.request(trimmed)
        // push된 성경 조회 화면이 있었다면 전부 pop해 검색 결과로 돌아간다(`detailNavigationPath` 참고).
        detailNavigationPath = NavigationPath()
        selection = .search
    }

    private static func initialSelection() -> AppSection {
        let settings = UserSettingsStore.shared
        guard settings.openLastScreenOnLaunch,
              let raw = settings.lastSelectedSectionRawValue,
              let section = AppSection(rawValue: raw),
              !section.opensSeparateWindow else {
            return .bibleReading
        }
        return section
    }

    /// 검색창을 스크롤 영역 밖의 형제 뷰로 두기 위해 `body`에서 분리한
    /// 사이드바 메뉴/고정됨/최근 목록.
    private var sidebarMenuList: some View {
        List(selection: $selection) {
            // `AppSection.sidebarMenuCases`는 `.tagRelations`를 뺀 목록이라, 아래 `.tagRelations`
            // 분기(별도 창 열기)는 이 목록에서는 실행되지 않는다.
            ForEach(AppSection.sidebarMenuCases) { section in
                if section.opensSeparateWindow {
                    // 별도 창으로 여는 항목은 선택 상태를 바꾸지 않고 그냥 새 창을 연다
                    // (.tag를 붙이지 않아 List의 selection 대상에서 제외된다).
                    Button {
                        openWindow(id: "tag-relations")
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .foregroundStyle(settings.bibleTextColor ?? .primary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label(section.title, systemImage: section.systemImage)
                        .foregroundStyle(settings.bibleTextColor ?? .primary)
                        .tag(section)
                }
            }

            // 고정됨/최근 Section의 행들은 `.tag(_:)`를 붙이지 않는다 — `selection`(AppSection 전용)
            // 대상에서 빠져야 하기 때문이다(탭하면 `openQuickItem(_:)`이 새 창을 열거나 다른 섹션으로 전환한다).
            // 위 메뉴와 아래 목록 사이 구분선이며, 모두 비어 있으면 표시하지 않는다.
            // 날짜 그룹(오늘/어제/그저께/이번 주/이전)은 `quickItemDateBucket(for:)`가 각 항목을
            // 정확히 한 버킷에만 넣는다.
            if !pinnedQuickItems.isEmpty || !todayQuickItems.isEmpty || !yesterdayQuickItems.isEmpty
                || !dayBeforeYesterdayQuickItems.isEmpty || !thisWeekQuickItems.isEmpty || !olderQuickItems.isEmpty {
                Divider()
            }
            if !pinnedQuickItems.isEmpty {
                Section {
                    ForEach(pinnedQuickItems) { item in
                        quickItemRow(item)
                    }
                } header: {
                    // 고정됨/날짜 헤더는 메뉴보다 옅게 표시한다.
                    Text("고정됨").foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
            }
            if !todayQuickItems.isEmpty {
                Section {
                    ForEach(todayQuickItems) { item in
                        quickItemRow(item)
                    }
                } header: {
                    Text("오늘").foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
            }
            if !yesterdayQuickItems.isEmpty {
                Section {
                    ForEach(yesterdayQuickItems) { item in
                        quickItemRow(item)
                    }
                } header: {
                    Text("어제").foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
            }
            if !dayBeforeYesterdayQuickItems.isEmpty {
                Section {
                    ForEach(dayBeforeYesterdayQuickItems) { item in
                        quickItemRow(item)
                    }
                } header: {
                    Text(dayBeforeYesterdayHeaderLabel).foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
            }
            if !thisWeekQuickItems.isEmpty {
                Section {
                    ForEach(thisWeekQuickItems) { item in
                        quickItemRow(item)
                    }
                } header: {
                    Text("이번 주").foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
            }
            if !olderQuickItems.isEmpty {
                Section {
                    ForEach(olderQuickItems) { item in
                        quickItemRow(item)
                    }
                } header: {
                    Text("이전").foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
            }
        }
        // 이 목록은 `.listStyle(.sidebar)`라 macOS가 선택 행 배경을 `AccentColor`(#B8863C)로
        // 채우는데, 큰 면적에서는 탁한 갈색으로 보인다. 앱 전체 `AccentColor`를 바꾸면 영향이
        // 크므로, 이 목록의 선택 배경에만 같은 색상(H)의 밝은 금색(#D1A35E)을 `.tint`로 덧씌운다.
        .tint(Color(hex: "#D1A35E") ?? Color("AccentColor"))
        // `List` 기본 시스템 배경을 `.scrollContentBackground(.hidden)`으로 먼저 꺼야
        // `.background(...)`의 테마 색이 보인다.
        .scrollContentBackground(.hidden)
        // 아이패드에서는 본문과 구분되도록 옅은 톤을 얹는다(`IPadPaneSeparation.swift`; 맥/아이폰은 테마색 그대로).
        .themedPaneBackground(tinted: true)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // ⚠️ [주의] `List(AppSection.allCases, selection:)`처럼 컬렉션을 첫 인자로
            // 넘기는 초기화 구문은 selection의 타입을 `AppSection.ID?`(=String?)로
            // 강제한다(Data.Element: Identifiable 기반 오버로드) — `.tag(_:)`로 요소
            // 자체를 선택값으로 쓰는 것과는 다른 API다. 여기서는 `.tag(section)`으로
            // `AppSection?` 그대로 선택하고 싶으므로, 데이터 없이 `List(selection:content:)`
            // + `ForEach` 조합을 쓴다.
            // 검색창을 `List`의 `.safeAreaInset`이 아니라 형제 뷰(`VStack`)로 둔다: macOS
            // `.listStyle(.sidebar)` List에서는 스크롤 행이 safeAreaInset 위로 비쳐 올라올 수 있다
            // (같은 스크롤 좌표계 공유). `.navigationSplitViewColumnWidth`/`.navigationTitle`/`.toolbar`는
            // 사이드바 컬럼 전체에 적용돼야 하므로 이 `VStack`에 건다.
            VStack(spacing: 0) {
                sidebarSearchBar
                sidebarMenuList
            }
            // 검색창 주변 여백까지 테마색으로 채우기 위해 `List` 밖의 `VStack`에도 배경을 준다.
            .themedPaneBackground(tinted: true)
            // 아이패드: 본문과 맞닿는 오른쪽 가장자리에 헤어라인(맥/아이폰은 동작 안 함).
            .iPadPaneSeparator(.trailing)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            // macOS: 사이드바 상단(신호등 버튼 줄)도 본문 컬럼의 창 툴바와 같은 테마색으로 맞춘다(2026-10-03).
            // 테마를 고르지 않았으면(nil) 아무것도 바꾸지 않는다.
            #if os(macOS)
            .sidebarWindowToolbarThemed(settings.bibleBackgroundColor)
            #endif
            // 아이패드에서는 사이드바 위의 큰 인라인 제목으로 보이므로 macOS 전용으로만 둔다
            // (이 뷰는 애초에 아이폰에서 쓰이지 않는다).
            #if os(macOS)
            .navigationTitle("JBCH Bible Research")
            #endif
            .toolbar {
                if showsSettingsToolbarButton {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            isSettingsPresented = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .help("설정")
                    }
                }
            }
        } detail: {
            // `NavigationStack`은 `path:` 바인딩을 쓴다(`detailNavigationPath` 참고). 기존
            // 목적지-클로저 `NavigationLink { Destination() }`도 그대로 동작하고, 경로를 비우면 전부 pop된다.
            NavigationStack(path: $detailNavigationPath) {
                detailView(for: selection ?? .bibleReading)
                    #if os(iOS)
                    .toolbar {
                        // 성경조회 화면은 전용 "사이드바 열기" 아이콘이 있어(`BibleReadingView.swift`
                        // `toolbarContent`, `IPadSidebarInspectorCoordination.swift` 참고), 아이패드에서 이
                        // `.navigation` 아이콘이 트레일링 그룹에 중복으로 붙지 않도록 그 화면에서는 뺀다.
                        // 다른 화면은 대체 아이콘이 없어 이 버튼으로 사이드바를 다시 연다.
                        if columnVisibility == .detailOnly && (selection ?? .bibleReading) != .bibleReading {
                            ToolbarItem(placement: .navigation) {
                                Button {
                                    columnVisibility = .all
                                } label: {
                                    Image(systemName: "sidebar.leading")
                                }
                                .help("사이드바 보이기")
                            }
                        }
                    }
                    #endif
            }
        }
        // 아이패드는 안쪽 `List`의 `.tint()`만으로는 선택 강조색이 시스템 파란색으로 남는다
        // (macOS는 AppKit, 아이패드는 UIKit `UISplitViewController` 브리징이라 색 해석이 다르다).
        // 그래서 `NavigationSplitView` 자체에도 같은 색을 건다.
        .tint(Color(hex: "#D1A35E") ?? Color("AccentColor"))
        .focusedSceneValue(\.selectSection) { section in
            if section.opensSeparateWindow {
                openWindow(id: "tag-relations")
            } else {
                selection = section
            }
        }
        .focusedSceneValue(\.toggleSidebar) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue, !newValue.opensSeparateWindow else { return }
            UserSettingsStore.shared.lastSelectedSectionRawValue = newValue.rawValue
        }
        // S1(성경 조회) 관련 콘텐츠 시트의 "개요 화면 열기" 경로(`AppNavigationRequest.swift` 참고).
        // 평범한 `AppSection?`(Equatable)이라 `@FocusedValue`의 클로저 게시 문제(툴바를 가진 뷰에서
        // 읽으면 실기기 크래시)가 없다.
        .onChange(of: AppNavigationRequest.shared.requestedSection) { _, newValue in
            guard let newValue, !newValue.opensSeparateWindow else { return }
            selection = newValue
            AppNavigationRequest.shared.clear()
        }
        // `SearchResultsPopRequest.swift` 참고 — `SearchViewModel.searchImmediately()`가 검색을
        // 시작할 때마다 보내는 신호를 받아 `detailNavigationPath`를 비운다. 진입점(사이드바 검색창/
        // `SearchView`의 `.searchable`)과 무관하게 성경 조회가 push된 상태에서 다시 검색하면
        // 검색결과 화면으로 돌아온다. `token`은 매번 증가하는 카운터라 `clear()`가 필요 없다.
        .onChange(of: SearchResultsPopRequest.shared.token) { _, _ in
            detailNavigationPath = NavigationPath()
        }
        // 말씀 요약 편집기 열기/닫기(`SidebarVisibilityRequest.swift` 참고). `AppNavigationRequest`와
        // 같은 이유로 `@FocusedValue` 대신 plain-Equatable 싱글턴 + `.onChange`를 쓴다.
        .onChange(of: SidebarVisibilityRequest.shared.pendingRequest) { _, newValue in
            guard let newValue else { return }
            switch newValue {
            case .hide:
                SidebarVisibilityRequest.shared.recordVisibilityBeforeHide(columnVisibility != .detailOnly)
                columnVisibility = .detailOnly
            case .restore:
                columnVisibility = SidebarVisibilityRequest.shared.wasVisibleBeforeHide ? .all : .detailOnly
            }
            SidebarVisibilityRequest.shared.clear()
        }
        // 아이패드에서 인스펙터와 사이드바가 동시에 나타나지 않게 조율한다
        // (`IPadSidebarInspectorCoordination.swift` 참고). 아이패드 전용이며 macOS/아이폰에서는
        // 싱글턴 값을 바꾸는 쪽이 없어 실질적으로 비활성이다.
        //
        // ① `columnVisibility`가 바뀔 때마다(경로 무관) 최신 표시 상태를 싱글턴에 보고한다.
        .onChange(of: columnVisibility) { _, newValue in
            guard isIPadIdiom else { return }
            IPadSidebarInspectorCoordination.shared.reportSidebarVisibility(newValue != .detailOnly)
        }
        // ② 트레일링 아이콘 그룹의 "사이드바 열기" 버튼(`BibleReadingView.swift`)은 사이드바를
        // 소유하지 않아 명령만 보낸다(매번 증가하는 카운터). 그 신호를 받아 실제로 사이드바를 연다.
        .onChange(of: IPadSidebarInspectorCoordination.shared.showSidebarRequestToken) { _, newValue in
            guard isIPadIdiom, newValue > 0 else { return }
            columnVisibility = .all
        }
        // ③ 관련 콘텐츠 인스펙터가 열리는 순간을 관찰해, 이 화면이 자기 로컬 상태로 사이드바를 접는다.
        .onChange(of: IPadSidebarInspectorCoordination.shared.isInspectorVisible) { _, newValue in
            guard isIPadIdiom, newValue, columnVisibility != .detailOnly else { return }
            columnVisibility = .detailOnly
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsHostView()
        }
    }

    // MARK: - "고정됨"/"최근" (2026-08-18 신설)

    /// `WordNoteItem`(WordNoteHomeView.swift)과 같은 원칙 — 데이터를 합치지 않고
    /// 사이드바에 한 목록으로 섞어 보여주기 위한 얇은 열거형 래퍼.
    /// 형광펜/메모/관주는 `isPinned` 필드가 없어 항상 고정 불가(`isPinnable == false`)이며
    /// "고정됨" 섹션에는 나오지 않는다.
    private enum SidebarQuickItemKind {
        case document(SourceDocument)
        case memo(UserMemo)
        case summary(VerseSummary)
        case highlight(VerseHighlight)
        case phraseNote(VersePhraseNote)
        case crossReference(VerseCrossReference)
    }

    private struct SidebarQuickItem: Identifiable {
        let kind: SidebarQuickItemKind

        var id: String {
            switch kind {
            case .document(let document): return "quick-doc-\(document.id.uuidString)"
            case .memo(let memo): return "quick-memo-\(memo.id.uuidString)"
            case .summary(let summary): return "quick-summary-\(summary.id.uuidString)"
            case .highlight(let highlight): return "quick-highlight-\(highlight.id.uuidString)"
            case .phraseNote(let note): return "quick-phrasenote-\(note.id.uuidString)"
            case .crossReference(let reference): return "quick-xref-\(reference.id.uuidString)"
            }
        }
        var title: String {
            switch kind {
            case .document(let document): return document.displayTitle
            case .memo(let memo):
                let bookName = BooksProvider.shared.book(id: memo.bookId)?.nameKo ?? "성경"
                // 절 단위 메모(`UserMemo.verse`)는 아래 다른 케이스와 같은 "장:절" 표기를 쓴다.
                if let verse = memo.verse {
                    return "\(bookName) \(memo.chapter):\(verse) 메모"
                }
                return "\(bookName) \(memo.chapter)장 메모"
            case .summary(let summary):
                let bookName = BooksProvider.shared.book(id: summary.bookId)?.nameKo ?? "성경"
                return "\(bookName) \(summary.chapter)장 말씀 요약"
            case .highlight(let highlight):
                let bookName = BooksProvider.shared.book(id: highlight.bookId)?.nameKo ?? "성경"
                return "\(bookName) \(highlight.chapter):\(highlight.verse) 형광펜"
            case .phraseNote(let note):
                let bookName = BooksProvider.shared.book(id: note.bookId)?.nameKo ?? "성경"
                return "\(bookName) \(note.chapter):\(note.verse) 메모"
            case .crossReference(let reference):
                let bookName = BooksProvider.shared.book(id: reference.bookId)?.nameKo ?? "성경"
                return "\(bookName) \(reference.chapter):\(reference.verse) 관주"
            }
        }
        var systemImage: String {
            switch kind {
            case .document: return "doc.text"
            case .memo: return "note.text"
            case .summary: return "text.quote"
            case .highlight: return "highlighter"
            case .phraseNote: return "note.text"
            // `VerseZoomView`의 관주 버튼과 같은 아이콘.
            case .crossReference: return "link"
            }
        }
        var isPinned: Bool {
            switch kind {
            case .document(let document): return document.isPinned
            case .memo(let memo): return memo.isPinned
            case .summary(let summary): return summary.isPinned
            case .highlight, .phraseNote, .crossReference: return false
            }
        }
        /// 형광펜/메모/관주는 고정 기능이 없다.
        var isPinnable: Bool {
            switch kind {
            case .document, .memo, .summary: return true
            case .highlight, .phraseNote, .crossReference: return false
            }
        }
        /// "작성/수정한" 기준 시각 — 연구문서는 업로드 시각, 개인 묵상은 마지막 수정 시각,
        /// 말씀 요약은 쓴 시각(저널 성격). 형광펜은 수정 개념이 없어 `createdAt`, 메모/관주는
        /// 내용을 고칠 수 있어 `updatedAt`을 쓴다.
        var sortDate: Date {
            switch kind {
            case .document(let document): return document.uploadedAt
            case .memo(let memo): return memo.updatedAt
            case .summary(let summary): return summary.createdAt
            case .highlight(let highlight): return highlight.createdAt
            case .phraseNote(let note): return note.updatedAt
            // `VerseCrossReference.updatedAt`은 옵셔널이므로, 한 번도 편집되지 않은 관주(`nil`)는
            // `createdAt`으로 대체한다.
            case .crossReference(let reference): return reference.updatedAt ?? reference.createdAt
            }
        }
    }

    private var allQuickItems: [SidebarQuickItem] {
        sidebarDocuments.map { SidebarQuickItem(kind: .document($0)) }
            + sidebarMemos.map { SidebarQuickItem(kind: .memo($0)) }
            + sidebarSummaries.map { SidebarQuickItem(kind: .summary($0)) }
            + sidebarHighlights.map { SidebarQuickItem(kind: .highlight($0)) }
            + sidebarPhraseNotes.map { SidebarQuickItem(kind: .phraseNote($0)) }
            + sidebarCrossReferences.map { SidebarQuickItem(kind: .crossReference($0)) }
    }

    private var pinnedQuickItems: [SidebarQuickItem] {
        allQuickItems.filter(\.isPinned).sorted { $0.sortDate > $1.sortDate }
    }

    /// 고정된 항목은 "고정됨" 섹션에 이미 나오므로 뺀다(중복 노출 방지). 사이드바가
    /// 무한정 길어지지 않도록 최근 30개로 제한한다(스펙에 없는 실용적 상한).
    private var recentQuickItems: [SidebarQuickItem] {
        Array(allQuickItems.filter { !$0.isPinned }.sorted { $0.sortDate > $1.sortDate }.prefix(30))
    }

    private var weekAgoDate: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    }

    /// 항목 하나가 정확히 한 버킷(오늘/어제/그저께/이번 주/이전)에만 들어가도록 판정을
    /// `quickItemDateBucket(for:)` 한 곳에 모은다. 프로퍼티마다 따로 필터링하면 경계에서
    /// 기준이 어긋나 중복/누락이 생길 수 있다.
    private enum SidebarQuickItemDateBucket {
        case today, yesterday, dayBeforeYesterday, thisWeek, older
    }

    private func quickItemDateBucket(for date: Date) -> SidebarQuickItemDateBucket {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        if let dayBeforeYesterday = calendar.date(byAdding: .day, value: -2, to: .now),
           calendar.isDate(date, inSameDayAs: dayBeforeYesterday) {
            return .dayBeforeYesterday
        }
        return date >= weekAgoDate ? .thisWeek : .older
    }

    private var todayQuickItems: [SidebarQuickItem] {
        recentQuickItems.filter { quickItemDateBucket(for: $0.sortDate) == .today }
    }

    private var yesterdayQuickItems: [SidebarQuickItem] {
        recentQuickItems.filter { quickItemDateBucket(for: $0.sortDate) == .yesterday }
    }

    private var dayBeforeYesterdayQuickItems: [SidebarQuickItem] {
        recentQuickItems.filter { quickItemDateBucket(for: $0.sortDate) == .dayBeforeYesterday }
    }

    private var thisWeekQuickItems: [SidebarQuickItem] {
        recentQuickItems.filter { quickItemDateBucket(for: $0.sortDate) == .thisWeek }
    }

    private var olderQuickItems: [SidebarQuickItem] {
        recentQuickItems.filter { quickItemDateBucket(for: $0.sortDate) == .older }
    }

    /// "그저께(날짜)" 헤더 문구 — 실제 날짜(예: "8월 24일")를 괄호 안에 보여준다.
    private static let dayBeforeYesterdayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    private var dayBeforeYesterdayHeaderLabel: String {
        guard let date = Calendar.current.date(byAdding: .day, value: -2, to: .now) else { return "그저께" }
        return "그저께(\(Self.dayBeforeYesterdayDateFormatter.string(from: date)))"
    }

    @ViewBuilder
    private func quickItemRow(_ item: SidebarQuickItem) -> some View {
        let row = Button {
            openQuickItem(item)
        } label: {
            Label(item.title, systemImage: item.systemImage)
                .lineLimit(1)
                // 보조 목록은 메뉴보다 옅은 테마 글자색으로 표시해 위계를 구분한다.
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
        }
        // "태그 관계" 행과 같은 이유로 `.plain` — 이 Button들은 `selection`
        // 대상이 아니라 List 기본 버튼 틴트가 어울리지 않는다.
        .buttonStyle(.plain)

        // 형광펜/메모/관주는 고정 기능이 없어(`isPinnable`), 빈 컨텍스트 메뉴가 뜨지 않도록
        // 그 셋에는 `.contextMenu`를 붙이지 않는다.
        if item.isPinnable {
            row.contextMenu {
                Button {
                    togglePinQuickItem(item)
                } label: {
                    Label(item.isPinned ? "고정 해제" : "고정", systemImage: item.isPinned ? "pin.slash" : "pin")
                }
            }
        } else {
            row
        }
    }

    /// 연구문서는 새 창으로 열고, 개인 묵상/말씀 요약은 "말씀 노트" 섹션으로 전환하면서
    /// `WordNoteSelectionRequest`(그 파일 상단 주석 참고)로 선택할 항목을 알린다.
    ///
    /// ⚠️ `openWindow`는 아이폰에서 런타임 에러를 내지만, 이 뷰는 macOS/iPadOS 전용이라
    /// (RootView.swift는 아이폰에서 `PhoneTabView`를 쓴다) 여기서는 호출될 수 없다.
    /// 이 뷰가 아이폰에서도 쓰이게 되면 detail 쪽에 `NavigationPath` 바인딩을 도입해
    /// `path.append(document.persistentModelID)`로 바꿔야 한다.
    private func openQuickItem(_ item: SidebarQuickItem) {
        switch item.kind {
        case .document(let document):
            openWindow(id: "document-viewer", value: document.persistentModelID)
        case .memo(let memo):
            WordNoteSelectionRequest.shared.request(.memo(memo.id))
            selection = .wordNote
        case .summary(let summary):
            WordNoteSelectionRequest.shared.request(.summary(summary.id))
            selection = .wordNote
        // 형광펜/메모/관주는 별도 목록 화면이 없고 성경 조회 화면에 있으므로 해당 절로 바로
        // 이동한다(`BibleVerseNavigationRequest.swift` 참고).
        case .highlight(let highlight):
            navigateToBibleVerse(bookId: highlight.bookId, chapter: highlight.chapter, verse: highlight.verse)
        case .phraseNote(let note):
            navigateToBibleVerse(bookId: note.bookId, chapter: note.chapter, verse: note.verse)
        case .crossReference(let reference):
            navigateToBibleVerse(bookId: reference.bookId, chapter: reference.chapter, verse: reference.verse)
        }
    }

    /// 성경 조회 섹션으로 전환하고 `BibleVerseNavigationRequest`로 목표 좌표를 넘긴다.
    /// `BibleReadingView`가 이미 떠 있든(`.onChange`) 새로 만들어지든(`.onAppear`) 처리된다.
    private func navigateToBibleVerse(bookId: Int, chapter: Int, verse: Int) {
        BibleVerseNavigationRequest.shared.request(bookId: bookId, chapter: chapter, verse: verse)
        selection = .bibleReading
    }

    /// `DocumentsViewModel.togglePin`/`WordNoteListContent.togglePin`과 같은 원칙(이산적 액션,
    /// 즉시 저장). 뷰모델이 없어 여기서 직접 `modelContext`에 저장한다. 고정 불가 케이스는
    /// `switch` 총망라를 위해 아무 것도 하지 않는다.
    private func togglePinQuickItem(_ item: SidebarQuickItem) {
        switch item.kind {
        case .document(let document): document.isPinned.toggle()
        case .memo(let memo): memo.isPinned.toggle()
        case .summary(let summary): summary.isPinned.toggle()
        case .highlight, .phraseNote, .crossReference: return
        }
        try? modelContext.save()
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .bibleReading: BibleReadingView()
        case .wordNote: WordNoteHomeView()
        case .documents: DocumentsHomeView()
        // "내 설교" — `SermonHomeView`는 iPhone/Mac·iPad 양쪽에서 재사용된다
        // (`SermonHomeView.swift` 참고).
        case .sermons: SermonHomeView()
        // 개요: 구약/신약 > 책 > 장 트리. 별도 창 `WindowGroup(id: "outline")`은 이 경로를 타지 않는다.
        case .outline: OutlineTreeView()
        // 다시 검색할 때 push된 화면에 갇히는 문제는 `NavigationStack(path:)`와
        // `submitSidebarSearch()`의 경로 초기화가 처리한다.
        case .search: SearchView()
        case .tagRelations: EmptyView() // 별도 창으로만 열리므로 본문에는 그려지지 않는다.
        }
    }
}

// MARK: - macOS 세리프 타이틀 수정자
//
// macOS 주요 화면(성경 조회·말씀 노트·연구 문서·내 설교·개요)의 상단 타이틀을 아이패드와 같은 성곡 세리프체로 보이게 한다.
// macOS 윈도우 타이틀은 시스템이 그려 글꼴을 바꿀 수 없어 `.navigationTitle`은 그대로 두고 `.toolbar(removing: .title)`로 시각적
// 타이틀만 숨긴 뒤 같은 자리에 세리프체 `Text`를 놓는다. 다른 플랫폼은 무동작이다.
// 글꼴: 국민대학교 성곡 세리프체(`SpecialPurposeFonts.titleSerif`, CC BY-ND — 설정 > 라이센스 탭 고지).

struct MacSerifTitleModifier: ViewModifier {
    let title: String
    @State private var settings = UserSettingsStore.shared

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .toolbar(removing: .title)
            .toolbar {
                // 제목은 툴바 맨 왼쪽(`.navigation`)에 둔다(2026-10-01 요청: `.principal`은 제목이 가운데로 간다).
                // 오른쪽 아이콘 묶음은 각 화면이 `.primaryAction`으로 두어 오른쪽 끝에 놓이게 한다.
                ToolbarItem(placement: .navigation) {
                    Text(title)
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                        .fontWeight(.semibold)
                        .foregroundStyle(settings.bibleTextColor ?? .primary)
                        .lineLimit(1)
                        // 툴바 폭이 모자라도 제목이 "…"로 잘리지 않게 본래 폭을 요구한다.
                        .fixedSize(horizontal: true, vertical: false)
                }
                .sharedBackgroundVisibility(.hidden)   // macOS 26 유리 캡슐 배경 제거(제목은 버튼이 아니다)
                // 보이지 않는 빈 `.principal` 항목 — 실기기 확인(2026-10-01): `.principal` 항목이 하나라도 있어야 시스템이 툴바를
                // [왼쪽 그룹 | 가운데 | 오른쪽 그룹]으로 나눠 배치해 `.primaryAction` 아이콘이 오른쪽 끝으로 간다. 없으면 제목(`.navigation`)
                // 바로 옆에 붙는다. `ToolbarSpacer`(.navigation/.primaryAction)와 제목 `.frame(maxWidth: .infinity)`는 효과가 없었다.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        #else
        content
        #endif
    }
}

extension View {
    /// macOS에서만 상단 타이틀을 성곡 세리프체로 보여준다(다른 플랫폼은 무동작).
    func macSerifTitle(_ title: String) -> some View {
        modifier(MacSerifTitleModifier(title: title))
    }
}

#if os(macOS)
extension View {
    /// 사이드바 컬럼의 창 툴바 배경을 테마색으로 칠한다(테마 미선택이면 무동작).
    @ViewBuilder
    func sidebarWindowToolbarThemed(_ color: Color?) -> some View {
        if let color {
            self
                .toolbarBackground(color, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        } else {
            self
        }
    }
}
#endif
