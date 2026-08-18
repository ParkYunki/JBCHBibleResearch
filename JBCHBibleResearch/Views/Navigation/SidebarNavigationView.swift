//
//  SidebarNavigationView.swift
//  JBCHBibleResearch
//
//  screens.md 9.1 — macOS/iPadOS 메인 창: 왼쪽 사이드바(폭 200~280) + 오른쪽 본문.
//  최소 창 크기(1000×700)는 Scene 선언부(.defaultSize/.windowResizability)에서 다뤄야
//  하는 부분이라 여기가 아니라 JBCHBibleResearchApp.swift에서 처리한다.
//
//  2026-08-06: 8.1 "시작 시 마지막으로 보던 화면 열기" + 11장 View 메뉴(화면 전환
//  ⌘1-5, 사이드바 토글 ⌥⌘S)를 연결했다. 메뉴 커맨드는 `.focusedSceneValue`로
//  이 화면의 로컬 상태를 노출받아 조작한다 — 전역 싱글턴을 안 쓴 이유는
//  AppFocusedValues.swift 상단 주석 참고(멀티윈도우에서 창끼리 선택 상태가
//  잘못 공유되는 걸 피하기 위함).
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
    @State private var selection: AppSection? = SidebarNavigationView.initialSelection()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isSettingsPresented = false
    /// [2026-08-18 추가] 사용자 요청 — "왼쪽 사이드바 맨 위 상단 검색기능: 버튼이
    /// 아니라 검색 텍스트박스+버튼으로 배치: 두글자이상 입력후 검색 버튼을
    /// 누르면(또는 엔터키) 오른쪽 메인영역에 검색결과가 나타날 수 있도록."
    /// `sidebarSearchBar`/`submitSidebarSearch()` 참고.
    @State private var sidebarSearchText: String = ""

    /// [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드 앱처럼 기능을
    /// 추가할 것. 고정됨 / (일주일 이내 날짜)/이전 -> 작성/수정한 연구문서/개인
    /// 묵상/말씀 요약 리스트를 보여줄 것." `@Query`라 SwiftData 변경(고정 토글,
    /// 새 업로드/새 메모 등)이 생기면 이 목록들이 자동으로 갱신된다.
    @Query(sort: \SourceDocument.uploadedAt, order: .reverse) private var sidebarDocuments: [SourceDocument]
    @Query(sort: \UserMemo.updatedAt, order: .reverse) private var sidebarMemos: [UserMemo]
    @Query(sort: \VerseSummary.createdAt, order: .reverse) private var sidebarSummaries: [VerseSummary]

    /// screens.md 8장/11장 — macOS는 환경설정을 앱 메뉴(⌘,)로만 노출한다("사이드바에
    /// 두지 않는다"). 하지만 iPadOS엔 그 메뉴 자체가 없어, 이 화면(사이드바 툴바)에
    /// 톱니바퀴 버튼을 하나 둔다 — 스펙이 명시하지 않은 iPad 전용 보완이다.
    private var showsSettingsToolbarButton: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        false
        #endif
    }

    /// [2026-08-18 추가] "두글자이상 입력후" 요청 그대로 — 공백을 뺀 길이가
    /// 2 미만이면 검색 버튼을 누를 수 없다(엔터키도 `submitSidebarSearch()`
    /// 안에서 같은 기준으로 한 번 더 막는다).
    private var canSubmitSidebarSearch: Bool {
        sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("검색 (2글자 이상)", text: $sidebarSearchText)
                .textFieldStyle(.plain)
                .onSubmit { submitSidebarSearch() }
            if !sidebarSearchText.isEmpty {
                Button {
                    sidebarSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                submitSidebarSearch()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitSidebarSearch)
        }
        .font(.body)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// `SidebarSearchRequest`(그 파일 상단 주석 참고)로 검색어를 전달하고, 이
    /// 화면이 이미 들고 있는 `selection`을 곧바로 `.search`로 바꿔 "오른쪽
    /// 메인영역에 검색결과가 나타나도록" 한다.
    private func submitSidebarSearch() {
        let trimmed = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        SidebarSearchRequest.shared.request(trimmed)
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

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // ⚠️ [주의] `List(AppSection.allCases, selection:)`처럼 컬렉션을 첫 인자로
            // 넘기는 초기화 구문은 selection의 타입을 `AppSection.ID?`(=String?)로
            // 강제한다(Data.Element: Identifiable 기반 오버로드) — `.tag(_:)`로 요소
            // 자체를 선택값으로 쓰는 것과는 다른 API다. 여기서는 `.tag(section)`으로
            // `AppSection?` 그대로 선택하고 싶으므로, 데이터 없이 `List(selection:content:)`
            // + `ForEach` 조합을 쓴다.
            List(selection: $selection) {
                // [2026-08-18 변경] 사용자 요청 — "'태그 관계' 메뉴 삭제 - 기능
                // 삭제는 추후 보류." `AppSection.sidebarMenuCases`(그 파일 상단
                // 주석 참고)가 `.tagRelations`만 뺀 목록을 준다 — 이 화면 안의
                // `.tagRelations` 분기(별도 창 열기)는 그대로 둬도 무해하다(이제
                // 이 목록에 그 case가 안 나오니 실행될 일이 없을 뿐).
                ForEach(AppSection.sidebarMenuCases) { section in
                    if section.opensSeparateWindow {
                        // 별도 창으로 여는 항목은 선택 상태를 바꾸지 않고 그냥 새 창을 연다
                        // (.tag를 붙이지 않아 List의 selection 대상에서 제외된다).
                        Button {
                            openWindow(id: "tag-relations")
                        } label: {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }

                // [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드
                // 앱처럼 기능을 추가할 것. 고정됨 / (일주일 이내 날짜)/이전 ->
                // 작성/수정한 연구문서/개인 묵상/말씀 요약 리스트를 보여줄 것."
                // 이 세 Section의 행들은 `.tag(_:)`를 붙이지 않는다 — 위 태그
                // 관계 행과 같은 이유로, `selection`(AppSection 전용) 대상에서
                // 빠져야 하기 때문이다(탭하면 직접 `openQuickItem(_:)`으로
                // 새 창을 열거나 다른 섹션으로 전환한다).
                if !pinnedQuickItems.isEmpty {
                    Section("고정됨") {
                        ForEach(pinnedQuickItems) { item in
                            quickItemRow(item)
                        }
                    }
                }
                if !thisWeekQuickItems.isEmpty {
                    Section("이번 주") {
                        ForEach(thisWeekQuickItems) { item in
                            quickItemRow(item)
                        }
                    }
                }
                if !olderQuickItems.isEmpty {
                    Section("이전") {
                        ForEach(olderQuickItems) { item in
                            quickItemRow(item)
                        }
                    }
                }
            }
            // [2026-08-18 추가] 검색 텍스트박스+버튼을 목록 "맨 위"에 고정한다 —
            // 목록 안 첫 행으로 넣으면 `List(selection:)`의 선택/포커스 처리에
            // 섞여 들어가(예: 방향키 이동, 파란 선택 배경) 검색창처럼 보이지 않을
            // 위험이 있어, `.safeAreaInset`으로 목록 바깥 위쪽에 별도로 붙인다.
            .safeAreaInset(edge: .top) {
                sidebarSearchBar
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            .navigationTitle("JBCH Bible Research")
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
            NavigationStack {
                // [2026-08-08 추가] 사용자 보고 — "왼쪽 사이드바 버튼을 클릭해서
                // 사이드바를 닫아 화면을 확장한 후, 다시 사이드바를 볼 수 있도록
                // 아이콘 추가해야 함". 사이드바 쪽 툴바(바로 위 List에 붙은
                // `.toolbar`)에 토글 버튼을 두면, 정작 사이드바가 닫혀 있을 때는
                // 그 사이드바 자체가 화면에서 사라져 버튼도 같이 사라진다 —
                // "닫은 뒤엔 다시 열 방법이 없다"는 증상과 정확히 들어맞는다.
                // 그래서 사이드바 열림/닫힘과 무관하게 항상 화면에 남아 있는
                // detail 쪽 툴바에 이 버튼을 둔다. macOS는 사이드바가 있는 창에
                // 시스템이 자동으로 툴바 토글 버튼을 제공하는 것으로 알려져 있고
                // 사용자가 macOS에서는 이 문제를 보고하지 않았으므로, 기존 동작을
                // 건드리지 않기 위해 iOS(아이패드)에만 적용한다.
                //
                // [2026-08-08 추가 수정] 사용자 보고 — "왼쪽 사이드바 바로 오른쪽에
                // 왼쪽 사이드바 아이콘이 또 있음". 사이드바가 열려 있을 때는
                // 아이패드가 사이드바 자체(또는 그 근처)에 이미 기본 접기 동작을
                // 제공하고 있어, 사이드바가 열려 있는 동안은 이 버튼이 중복으로
                // 보였다 — 이 버튼은 "닫았을 때 다시 여는" 용도로만 만든 것이므로,
                // 사이드바가 실제로 닫혀 있을 때(`columnVisibility == .detailOnly`)만
                // 보이게 한다.
                //
                // [2026-08-08 재수정, 근본 원인 발견] 사용자가 스크린샷으로 확인해준
                // 결과 — 이 `.toolbar`를 (아래처럼 content 안이 아니라) NavigationStack
                // "컨테이너" 자체에 형제 modifier로 붙였더니, "성경 조회" 타이틀은 물론
                // BibleReadingContentView가 선언한 관련 콘텐츠/조회 이력 트레일링
                // 아이콘까지 전부 사라졌다(스크린샷 상단이 완전히 빈 채로 나옴 — 아이콘이
                // 더 보기 메뉴에 접힌 게 아니라 애초에 툴바 자체가 비어 있었다). 이전
                // 라운드에 `.primaryAction`→`.topBarTrailing`로 배치를 바꿔도 전혀
                // 효과가 없었던 이유가 바로 이것 — 문제는 배치가 아니라, NavigationStack
                // 컨테이너 바로 바깥에 붙인 이 `.toolbar`가 (조건이 false라 빈 내용을
                // 반환할 때조차) 내부 콘텐츠(detailView가 렌더링하는 BibleReadingView →
                // BibleReadingContentView)가 선언한 타이틀/툴바 전체를 밀어내고 있었다.
                // 해결책은 이 `.toolbar`를 NavigationStack "컨테이너"가 아니라 그 안의
                // 루트 콘텐츠(`detailView(for:)`가 반환하는 뷰)에 붙이는 것 — 이러면
                // 이 버튼과 BibleReadingContentView 안쪽 깊이 있는 `.navigationTitle`/
                // `.toolbar`가 같은 콘텐츠 트리 안에서 정상적으로 합쳐진다.
                detailView(for: selection ?? .bibleReading)
                    #if os(iOS)
                    .toolbar {
                        if columnVisibility == .detailOnly {
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
        // [2026-08-08 추가] S1(성경 조회) 관련 콘텐츠 시트의 "개요 화면 열기"가
        // 쓰는 경로 — `AppNavigationRequest.swift` 상단 주석 참고. 이 값은 평범한
        // `AppSection?`(Equatable)이라 `@FocusedValue`의 클로저 게시 문제(툴바를
        // 가진 뷰에서 읽으면 실기기 크래시)가 없다.
        .onChange(of: AppNavigationRequest.shared.requestedSection) { _, newValue in
            guard let newValue, !newValue.opensSeparateWindow else { return }
            selection = newValue
            AppNavigationRequest.shared.clear()
        }
        // [2026-08-12 추가] 말씀 요약 편집기 열기/닫기 — `SidebarVisibilityRequest.swift`
        // 상단 주석 참고. `AppNavigationRequest`와 같은 이유로 `@FocusedValue`
        // 대신 plain-Equatable 싱글턴 + `.onChange`를 쓴다.
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
        .sheet(isPresented: $isSettingsPresented) {
            SettingsHostView()
        }
    }

    // MARK: - "고정됨"/"최근" (2026-08-18 신설)

    /// `WordNoteItem`(WordNoteHomeView.swift)과 같은 원칙 — 데이터 자체를 합치지
    /// 않고, 사이드바에 한 목록으로 섞어 보여주기 위한 얇은 열거형 래퍼.
    /// 사용자 요청이 명시한 세 종류(연구문서/개인 묵상/말씀 요약)만 다룬다 —
    /// 메모(VersePhraseNote)/개요는 이 섹션 범위 밖("작성/수정한 연구문서/개인
    /// 묵상/말씀 요약 리스트를 보여줄 것" 문구 그대로).
    private enum SidebarQuickItemKind {
        case document(SourceDocument)
        case memo(UserMemo)
        case summary(VerseSummary)
    }

    private struct SidebarQuickItem: Identifiable {
        let kind: SidebarQuickItemKind

        var id: String {
            switch kind {
            case .document(let document): return "quick-doc-\(document.id.uuidString)"
            case .memo(let memo): return "quick-memo-\(memo.id.uuidString)"
            case .summary(let summary): return "quick-summary-\(summary.id.uuidString)"
            }
        }
        var title: String {
            switch kind {
            case .document(let document): return document.originalFilename
            case .memo(let memo):
                let bookName = BooksProvider.shared.book(id: memo.bookId)?.nameKo ?? "성경"
                return "\(bookName) \(memo.chapter)장 메모"
            case .summary(let summary):
                let bookName = BooksProvider.shared.book(id: summary.bookId)?.nameKo ?? "성경"
                return "\(bookName) \(summary.chapter)장 말씀 요약"
            }
        }
        var systemImage: String {
            switch kind {
            case .document: return "doc.text"
            case .memo: return "note.text"
            case .summary: return "text.quote"
            }
        }
        var isPinned: Bool {
            switch kind {
            case .document(let document): return document.isPinned
            case .memo(let memo): return memo.isPinned
            case .summary(let summary): return summary.isPinned
            }
        }
        /// "작성/수정한" 기준 — 연구문서는 업로드 시각, 개인 묵상은 마지막 수정
        /// 시각(WordNoteHomeView와 같은 원칙), 말씀 요약은 쓴 시각(같은 이유로
        /// "쓴 순서"가 그 모델의 저널 성격에 맞다 — `WordNoteItem.sortDate` 상단
        /// 주석 참고).
        var sortDate: Date {
            switch kind {
            case .document(let document): return document.uploadedAt
            case .memo(let memo): return memo.updatedAt
            case .summary(let summary): return summary.createdAt
            }
        }
    }

    private var allQuickItems: [SidebarQuickItem] {
        sidebarDocuments.map { SidebarQuickItem(kind: .document($0)) }
            + sidebarMemos.map { SidebarQuickItem(kind: .memo($0)) }
            + sidebarSummaries.map { SidebarQuickItem(kind: .summary($0)) }
    }

    private var pinnedQuickItems: [SidebarQuickItem] {
        allQuickItems.filter(\.isPinned).sorted { $0.sortDate > $1.sortDate }
    }

    /// 고정된 항목은 "고정됨" 섹션에 이미 나오므로 "최근" 쪽에서는 뺀다(중복
    /// 노출 방지, Claude 앱과 같은 방식). 항목이 아주 많아지면 사이드바가
    /// 무한정 길어지는 걸 막기 위해 최근 30개로 캡을 둔다 — 스펙에 명시된
    /// 숫자는 없지만("이번 주"/"이전" 두 구간만 명시), 개인용 앱 규모를
    /// 고려한 실용적 상한이다.
    private var recentQuickItems: [SidebarQuickItem] {
        Array(allQuickItems.filter { !$0.isPinned }.sorted { $0.sortDate > $1.sortDate }.prefix(30))
    }

    private var weekAgoDate: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    }

    private var thisWeekQuickItems: [SidebarQuickItem] {
        recentQuickItems.filter { $0.sortDate >= weekAgoDate }
    }

    private var olderQuickItems: [SidebarQuickItem] {
        recentQuickItems.filter { $0.sortDate < weekAgoDate }
    }

    private func quickItemRow(_ item: SidebarQuickItem) -> some View {
        Button {
            openQuickItem(item)
        } label: {
            Label(item.title, systemImage: item.systemImage)
                .lineLimit(1)
        }
        // "태그 관계" 행과 같은 이유로 `.plain` — 이 Button들은 `selection`
        // 대상이 아니라 List 기본 버튼 틴트가 어울리지 않는다.
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                togglePinQuickItem(item)
            } label: {
                Label(item.isPinned ? "고정 해제" : "고정", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
        }
    }

    /// 연구문서는 기존 검색결과와 같은 방식(새 창), 개인 묵상/말씀 요약은
    /// "말씀 노트" 섹션으로 전환하면서 그 항목이 바로 선택되도록
    /// `WordNoteSelectionRequest`(그 파일 상단 주석 참고)로 알린다.
    ///
    /// ⚠️ [2026-08-18 검토, 아이폰 크래시 fix 관련] `openWindow`가 아이폰에서
    /// 런타임 에러를 내는 문제(DocumentsHomeView/SearchView/TagDrilldownView/
    /// ChapterRelatedContentPanel 동일 fix 참고)가 이 함수에도 있어 보이지만,
    /// `SidebarNavigationView` 자체가 macOS/iPadOS 전용이다(RootView.swift —
    /// `UIDevice.current.userInterfaceIdiom == .phone`이면 이 뷰 대신
    /// `PhoneTabView`를 쓴다). 즉 이 함수는 아이폰에서 아예 호출될 수 없어
    /// 실제로는 안전하다 — 다른 4곳과 달리 이 함수 자체는 여러 View 중
    /// 하나를 고르는 `@ViewBuilder` 컨텍스트가 아니라 명령형 함수라, 같은
    /// `if isPhoneIdiom { NavigationLink … }` 패턴을 그대로 적용할 수도 없다
    /// (NavigationLink는 View이지 명령형으로 "누르는" 액션이 아니다). 만약
    /// 나중에 이 뷰가 아이패드 멀티태스킹 축소 등으로 아이폰에서도 쓰이게
    /// 된다면, `NavigationSplitView`의 detail 쪽에 `NavigationPath` 바인딩을
    /// 새로 도입해 `path.append(document.persistentModelID)`로 바꿔야 한다.
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
        }
    }

    /// `DocumentsViewModel.togglePin`/`WordNoteListContent.togglePin`과 같은
    /// 원칙(이산적 액션, 즉시 저장) — 이 화면은 뷰모델이 따로 없어 여기서 직접
    /// `modelContext`에 저장한다.
    private func togglePinQuickItem(_ item: SidebarQuickItem) {
        switch item.kind {
        case .document(let document): document.isPinned.toggle()
        case .memo(let memo): memo.isPinned.toggle()
        case .summary(let summary): summary.isPinned.toggle()
        }
        try? modelContext.save()
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .bibleReading: BibleReadingView()
        case .wordNote: WordNoteHomeView()
        case .documents: DocumentsHomeView()
        // [2026-08-14 변경] 사용자 요청 — "개요: 구약/신약 > 책 > 장 폴더 구조로."
        // 66권 평면 리스트(`OutlineBookListView`, 삭제됨)를 트리(`OutlineTreeView`)로
        // 교체 — `WindowGroup(id: "outline")`(성경 조회 사이드바의 "개요 화면
        // 열기" 별도 창)은 이 경로를 타지 않으므로 영향 없다(JBCHBibleResearchApp.swift 참고).
        case .outline: OutlineTreeView()
        case .search: SearchView()
        case .tagRelations: EmptyView() // 별도 창으로만 열리므로 본문에는 그려지지 않는다.
        }
    }
}
