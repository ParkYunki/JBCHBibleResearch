//
//  SearchView.swift
//  JBCHBibleResearch
//
//  S11(통합 검색) 화면. 검색어 입력 + 성경구절/개요/연구문서/메모/개인 묵상/
//  말씀 요약 분류별 결과.
//  키워드 검색 결과는 `DocumentsHomeView` 검색 결과와 같은 표현(일치 횟수 접두어 +
//  태그 뱃지 + 형광펜 강조 발췌)을 쓴다. `highlightedText`/`badge`는 세 번째
//  사용처가 생기기 전까지 공통 헬퍼로 추출하지 않고 이 파일에 따로 둔다.
//  툴바의 질문형 검색 토글(`questionToggleButton`)은 질의 의도 카드(관계/인물/주제/예언)를
//  결과 목록 위에 보여준다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// 참조 일치·태그 배지 색. `DocumentsHomeView`의 statusGreen/tagBadgeBlue와 같은
// 값으로 "일치/성공"·"태그" 의미를 앱 전체에서 통일한다.
fileprivate let referenceMatchGreen = Color(hex: "#5E8C5B") ?? .green
fileprivate let tagBadgeBlue = Color(hex: "#4A6FA5") ?? .blue

/// 통합 검색 화면의 시스템 내비게이션 바 배경을 테마 색에 맞추는 모디파이어.
/// `BibleReadingView`/`WordNoteHomeView`의 동명 모디파이어와 같은 패턴이다.
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    // `Color.resolve(in:)`에 넘길 현재 환경. 고정 RGB 색이라 라이트/다크 모드와
    // 무관하게 항상 같은 값이 나온다.
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        // `ToolbarPlacement.navigationBar`는 macOS에 없는 심볼이라 iOS에서만 적용하고,
        // macOS는 항상 그대로 통과시킨다.
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // 배경 휘도로 `.toolbarColorScheme`을 명시한다. 지정하지 않으면 iOS는 앱 전체의
                // 라이트/다크 모드만 보고 바 아이템 색을 정해, 라이트 모드에서 어두운 테마를
                // 고르면 아이템이 거의 안 보일 수 있다. 어두우면 `.dark`(밝은 아이템).
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
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

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SearchViewModel?
    /// `SearchContentView`와 같은 읽기 전용 접근 패턴 — 내비게이션 바 배경 테마에 쓴다.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        Group {
            if let viewModel {
                SearchContentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .onAppear {
                        let vm = SearchViewModel(modelContext: modelContext)
                        // 사이드바 검색창이 넘긴 검색어(SidebarSearchRequest)가 있으면 화면 생성
                        // 시점에 곧바로 반영한다. 아래 `.onChange`는 화면이 이미 떠 있을 때의 재검색용.
                        if let pending = SidebarSearchRequest.shared.pendingQuery {
                            vm.query = pending
                            // `query` didSet은 자동 검색하지 않으므로(타이핑 프리징 방지)
                            // 제출된 검색어는 명시적으로 즉시 검색한다.
                            vm.searchImmediately()
                            SidebarSearchRequest.shared.clear()
                        }
                        viewModel = vm
                    }
            }
        }
        .navigationTitle("통합 검색")
        // 아이콘 좌측 공간 낭비를 막기 위해 인라인 타이틀을 쓴다(`WordNoteHomeView`와 동일).
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // 시스템 내비게이션 바 배경을 테마에 맞춘다.
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        #if os(iOS)
        // 타이틀을 테마 글자색으로 표시한다(`WordNoteHomeView`/`DocumentsHomeView`와 동일).
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("통합 검색")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
        }
        #endif
        // 평범한 Equatable(String?) 싱글턴 프로퍼티라 안전하게 관찰할 수 있다
        // (`SidebarNavigationView`의 requestedSection 관찰과 같은 패턴).
        .onChange(of: SidebarSearchRequest.shared.pendingQuery) { _, newValue in
            guard let newValue, let viewModel else { return }
            viewModel.query = newValue
            viewModel.searchImmediately()
            SidebarSearchRequest.shared.clear()
        }
    }
}

/// 아이폰에서만 `.navigationDestination(for: BibleVerseDestination.self)` 등록을 끄기
/// 위한 조건부 modifier (`SearchContentView`의 등록 위치 주석 참고).
private struct BibleVerseDestinationRegistration: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationDestination(for: BibleVerseDestination.self) { destination in
                BibleReadingView(
                    initialBook: BooksProvider.shared.book(id: destination.bookId),
                    initialChapter: destination.chapter,
                    initialVerse: destination.verse
                )
            }
        } else {
            content
        }
    }
}

// 인물/주제/관계 상세(`PersonDetailView`/`ThemeDetailView`/`RelationDetailView`)는
// push하지 않고 `SearchContentView`가 `List` 안에서 `viewModel.aiCardSelectedIndex`
// 상태로 직접 전환한다.

/// `BibleReadingView`의 동명 타입과 같은 얇은 `Identifiable` 래퍼. 공통 타입 추출은
/// 세 번째 사용처가 생기기 전까지 하지 않으므로 이 파일 전용으로 둔다. 한자 주석
/// 필드는 `VerseTextSelectionPopover.hanjaWords` 기본값 `[]`으로 충분해 생략했다.
private struct PartialTextSelectionTarget: Identifiable {
    let id = UUID()
    let verseNumber: Int
    let translationDisplayName: String
    let text: String
}

private struct SearchContentView: View {
    let viewModel: SearchViewModel
    // 검색결과의 문서 진입점은 별도 창(document-viewer WindowGroup)으로 연다.
    @Environment(\.openWindow) private var openWindow
    // 검색 제출 시(`.onSubmit(of: .search)`) 검색 활성 상태를 종료해, 성경구절 탭 후
    // 이동할 때 빈 통합검색 화면이 끼어드는 것을 막는다.
    @Environment(\.dismissSearch) private var dismissSearch

    /// "선택" 버튼(`verseRowActionButtons`)이 채우는 팝오버 대상.
    @State private var partialTextSelectionTarget: PartialTextSelectionTarget?
    /// 복사 버튼을 눌렀을 때 화면 아래에 잠깐 띄우는 토스트 문구(`BibleReadingView.showToast`와 같은 방식).
    @State private var toastMessage: String?
    /// 연달아 복사할 때 먼저 예약된 타이머가 새 토스트를 조기에 지우지 않도록 이전 예약을 취소하기 위한 작업 핸들.
    @State private var toastDismissWorkItem: DispatchWorkItem?

    /// 검색어가 비어 있는 채로 화면이 새로 나타나면 검색창에 자동 포커스를 줘 최근
    /// 검색어(`.searchSuggestions`)가 바로 보이게 한다. macOS/iPadOS 사이드바는 섹션
    /// 전환 시 `SearchView`를 매번 새로 만들어 검색어/결과가 사라지기 때문이다
    /// (아이폰은 탭이 유지돼 상태를 잃지 않는다).
    @FocusState private var isSearchFieldFocused: Bool
    /// 테마 배경/글자색용 읽기 전용 접근.
    private var settings: UserSettingsStore { .shared }

    /// 검색 결과 분류 탭. 중첩 `TabView`는 macOS에서 렌더링되지 않아 `SettingsView`처럼
    /// 세그먼트 `Picker` + `@State` 선택값 패턴을 쓴다. "메모/말씀노트" 탭은 메모
    /// (`VersePhraseNote`)·개인 묵상(`UserMemo`)·말씀 요약(`VerseSummary`)을 각자의
    /// 표시 로직 그대로 묶은 것이다.
    private enum SearchResultTab: String, CaseIterable, Identifiable {
        case verse, outline, notes, document, sermon
        var id: Self { self }
        var title: String {
            switch self {
            case .verse: return "성경구절"
            case .outline: return "개요"
            case .notes: return "메모/말씀노트"
            case .document: return "연구 문서"
            case .sermon: return "내 설교"
            }
        }

        /// 각 탭 아이콘은 `sectionHeader`가 같은 분류에 쓰는 아이콘과 맞췄다.
        /// "메모/말씀노트"는 하단 탭바 "말씀 노트" 탭의 "note.text"를 재사용한다.
        var icon: String {
            switch self {
            case .verse: return "book.closed.fill"
            case .outline: return "list.bullet.rectangle.fill"
            case .notes: return "note.text"
            case .document: return "doc.text.fill"
            case .sermon: return "mic.fill"
            }
        }

        // 탭별 고정 구분색은 두지 않는다. 일부 읽기 테마 프리셋 배경과 같은 값이 되면 선택된
        // 탭이 배경에 묻히므로, `mainResultTabButton`이 캡슐과 같은 색(선택 시 accent,
        // 평소엔 테마 글자색)을 쓴다.
    }

    @State private var selectedResultTab: SearchResultTab = .verse

    /// [성경구절] 탭 안에서 보고 있는 번역본 코드. 활성 번역본 목록
    /// (`viewModel.activeTranslations`, 최대 3개)은 검색마다 다시 계산되므로, 여기 저장한
    /// 값이 목록에 없으면 `resultsSection`에서 첫 번째 활성 번역본으로 대체한다.
    /// 그래서 옵셔널로 두고 사용자가 마지막으로 고른 값만 기억한다.
    @State private var selectedVerseTranslationCode: String?

    /// 아이폰은 다중 씬을 지원하지 않아 `openWindow`가 런타임 에러를 내므로 구분한다
    /// (`DocumentsHomeView.isPhoneIdiom`과 같은 패턴). `UIDevice`는 iOS 전용이다.
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// 성경 조회 이동 행. 아이폰에서는 이 화면에서 직접 push하지 않는다 — 검색이 활성인
    /// 채로 같은 화면에서 `BibleVerseDestination`을 push하는 조합이 구조적으로 깨지기
    /// 때문이다(전환 충돌, 검색 활성 경고, 엉뚱한 탭 이동). 대신 "성경" 탭으로 전환
    /// (`AppNavigationRequest`)하고 떠 있는 `BibleReadingView`에 목표 좌표를
    /// 전달(`BibleVerseNavigationRequest`)한다. 이 화면은 `TabView`가 계속 살려 두므로
    /// 상태를 잃지 않는다.
    ///
    /// macOS/iPadOS는 그대로 `NavigationLink(value:)`를 쓴다. `Button`은 List 행에서
    /// 디스클로저 화살표를 자동으로 그리지 않으므로 같은 모양의 화살표를 직접 그린다.
    @ViewBuilder
    private func bibleVerseRow<RowLabel: View>(
        _ destination: BibleVerseDestination,
        @ViewBuilder label: () -> RowLabel
    ) -> some View {
        if isPhoneIdiom {
            Button {
                AppNavigationRequest.shared.request(.bibleReading)
                // 메모(VersePhraseNote) 결과처럼 절이 없으면(`verse == nil`) 그 장의 1절로 대체한다
                // (`BibleVerseNavigationTarget.verse`는 옵셔널이 아니다).
                BibleVerseNavigationRequest.shared.request(
                    bookId: destination.bookId,
                    chapter: destination.chapter,
                    verse: destination.verse ?? 1
                )
            } label: {
                HStack(spacing: 8) {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: destination) {
                label()
            }
        }
    }

    var body: some View {
        Group {
            // 맥/아이패드에서 항목이 여러 개인 카드가 뜬 경우에만 결과 목록 + 상세 두 칼럼으로
            // 바꾼다. 그 외(아이폰, 항목 0/1개, 카드 없는 일반 검색)는 단일 목록(`mainResultsList`).
            if !isPhoneIdiom, let multi = multiItemInlineCard {
                macSplitCardLayout(intent: multi.intent, kind: multi.kind)
            } else {
                mainResultsList
            }
        }
        // 테마 배경/글자색 모디파이어 다섯 개(`.listStyle`/`.scrollContentBackground`/
        // `.background`/`.foregroundStyle`/`.listRowSeparatorTint`)는 `Group`이 아니라
        // `mainResultsList`와 `macSplitCardLayout`의 각 `List`가 직접 들고 있다. 중복이지만
        // 어느 레이아웃에서도 테마가 유지되고 칼럼별로 따로 바꿀 수 있게 하려는 의도다.
        // 아래 `.searchable` 등은 레이아웃과 무관하게 하나면 되므로 `Group`에 둔다.
        .searchable(text: Binding(
            get: { viewModel.query },
            set: { viewModel.query = $0 }
        ), prompt: "검색어 입력")
        .searchFocused($isSearchFieldFocused)
        // macOS/iPadOS에서 섹션 전환 후 화면이 새로 만들어질 때(검색어가 빈 첫 등장) 검색창에
        // 자동 포커스를 줘 최근 검색 제안이 바로 보이게 한다. 아이폰은 탭을 열 때마다 키보드가
        // 올라오므로 `!isPhoneIdiom`으로 제외한다.
        .onAppear {
            if !isPhoneIdiom, viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                isSearchFieldFocused = true
            }
        }
        // 검색창 아래 최근 검색 제안. `.searchable`을 세 플랫폼이 공유하므로 이 한 곳으로
        // 모두 같은 동작이 나온다. 검색어가 비어 있을 때만 보이며, 항목을 탭하면 그 검색어로
        // 즉시 검색하고 검색을 종료한다(`dismissSearch`, `.onSubmit`과 같은 이유).
        .searchSuggestions {
            // 아이폰은 `recentSearchesSection`(포커스와 무관하게 항상 보임)이 이 역할을 하므로
            // 제외한다. 안 그러면 검색창 포커스 중 같은 목록이 두 번 겹쳐 보인다.
            if !isPhoneIdiom, viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                let recentSearches = viewModel.recentSearchHistory()
                if !recentSearches.isEmpty {
                    Section("최근 검색") {
                        ForEach(recentSearches) { entry in
                            Button {
                                viewModel.query = entry.query
                                viewModel.searchImmediately()
                                dismissSearch()
                            } label: {
                                Label(entry.query, systemImage: "clock")
                            }
                        }
                    }
                }
            }
        }
        // 엔터(또는 iOS 키보드 검색 버튼)를 누르면 디바운스(350ms) 대기 없이 바로 검색한다.
        .onSubmit(of: .search) {
            viewModel.searchImmediately()
            // `dismissSearch` 선언부 참고. 결과 표시 조건(`resultsSection`)은 `viewModel.query`에만
            // 달려 있어 검색 활성 상태를 종료해도 결과 표시엔 영향이 없다.
            dismissSearch()
        }
        // `BibleVerseDestination`의 `.navigationDestination` 등록. 같은 스택에 이 타입의 등록이
        // 둘이면 루트에 더 가까운 쪽만 쓰이고 나머지는 조용히 무시된다. `.searchable`이 활성인
        // 이 화면은 iOS가 검색 결과를 별도로 호스팅하면서 modifier 체인이 스택 안에 두 번
        // 나타나는 것으로 보이며, 이 증상은 아이폰에서만 재현됐다. 아이폰은 `bibleVerseRow`가
        // push 없이 탭 전환 방식을 쓰므로 등록이 필요 없고, macOS/iPadOS
        // (`SidebarNavigationView`)만 이 화면 자신의 등록을 쓴다.
        .modifier(BibleVerseDestinationRegistration(isEnabled: !isPhoneIdiom))
        .overlay(alignment: .bottom) { searchToastOverlay }
        .toolbar {
            // 질문형 검색 토글은 배포판을 포함한 모든 빌드에서 노출한다. `viewModel.isQuestionSearchEnabled`는 이 버튼으로만
            // 켤 수 있고 영구 저장하지 않으며 기본은 꺼짐이다.
            ToolbarItem(placement: .primaryAction) {
                questionToggleButton
            }
        }
        .onDisappear { viewModel.onDisappear() }
        // 이스터 에그(`ChurchYouthEasterEgg.swift`) — 의미검색 상태에서 특정 검색어를 검색하면 전체 화면 오버레이.
        .modifier(ChurchYouthEasterEggPresenter(isPresented: Binding(
            get: { viewModel.isEasterEggPresented },
            set: { viewModel.isEasterEggPresented = $0 }
        )))
        // "선택" 버튼용 `VerseTextSelectionPopover`(성경조회 화면과 동일).
        .popover(item: $partialTextSelectionTarget) { target in
            VerseTextSelectionPopover(
                verseNumber: target.verseNumber,
                translationDisplayName: target.translationDisplayName,
                text: target.text,
                onCopy: { text in
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #else
                    UIPasteboard.general.string = text
                    #endif
                }
            )
        }
        // 두 단어 이상 검색 시 더보기를 누르면 검색 1회당 최초 1번만 뜨는 안내창
        // (`SearchViewModel.confirmMoreResultsNotice()` 참고). `.alert(item:)`은 deprecated라
        // `.alert(_:isPresented:presenting:actions:message:)`를 쓴다.
        .alert(
            "추가 검색결과 안내",
            isPresented: Binding(
                get: { viewModel.pendingMoreResultsNotice != nil },
                set: { if !$0 { viewModel.dismissMoreResultsNotice() } }
            ),
            presenting: viewModel.pendingMoreResultsNotice
        ) { _ in
            Button("확인") {
                viewModel.confirmMoreResultsNotice()
            }
        } message: { notice in
            Text("구약·신약 성경책 \(notice.additionalBookCount)권에 걸쳐 추가 검색결과가 반영되었습니다. 확인해보세요.")
        }
    }

    /// 검색창 왼쪽에 놓이는 질문형 검색 토글. `.searchable` 시스템 검색창이 툴바 맨 끝(trailing)에
    /// 붙으므로 이 항목을 먼저 선언한다.
    private var questionToggleButton: some View {
        Toggle(isOn: Binding(
            get: { viewModel.isQuestionSearchEnabled },
            set: { viewModel.isQuestionSearchEnabled = $0 }
        )) {
            Label("질문형 검색", systemImage: "questionmark.bubble")
        }
        .toggleStyle(.button)
        .help("켜면 ‘다윗의 아들은 누구인가’처럼 물었을 때 인물·관계·주제 정보를 카드로 먼저 보여줍니다.")
    }

    // 질의 의도 카드가 통합검색 화면 자체를 대체할 때의 카드 종류. 단일 항목이면 바로 상세로,
    // 여러 항목이면 행 목록에서 선택해 상세로 간다. 예언/서사는 데이터가 없어 항상
    // `.notReady`이므로(`QueryIntentHandler.swift` 참고) 포함하지 않는다.
    private enum InlineCardKind {
        case relation([RelationDisplayItem])
        case person([PersonEntity])
        /// 장소가 걸린 질의 — 인물이 함께 있으면 같은 목록에 섞여 있다(`ProfileItem`).
        case entity([ProfileItem])
        case theme([ThemeRecord])

        var count: Int {
            switch self {
            case .relation(let items): return items.count
            case .person(let items): return items.count
            case .entity(let items): return items.count
            case .theme(let items): return items.count
            }
        }
    }

    private func inlineCardKind(for content: QueryIntentCard.Content) -> InlineCardKind? {
        switch content {
        case .relation(let items): return .relation(items)
        case .personProfile(let persons): return .person(persons)
        case .entityProfile(let items): return .entity(items)
        case .theme(let themes): return .theme(themes)
        case .prophecy, .narrative: return nil
        }
    }

    /// 질의 의도 카드가 통합검색 페이지 자체를 대체하는 중인지 — 참이면 `resultsSection`
    /// (성경구절/개요/메모·말씀노트/연구문서 4개 탭)을 그리지 않는다. `body`와
    /// `intentCardSection` 양쪽에서 쓴다.
    private var isInlineCardDisplayActive: Bool {
        guard let card = viewModel.intentCard, case .found(let content) = card.status else { return false }
        return inlineCardKind(for: content) != nil
    }

    /// 맥/아이패드에서 결과 목록과 상세를 나란히(split) 보여줘야 하는 경우만
    /// 값을 준다 — 항목이 1개뿐이면 나열할 목록 자체가 의미 없어 split 없이
    /// (아이폰과 동일하게) 상세를 바로 보여주면 되므로 여기 포함하지 않는다
    /// (`body`의 분기 참고).
    private var multiItemInlineCard: (intent: QueryIntentClassifier.Intent, kind: InlineCardKind)? {
        guard let card = viewModel.intentCard, case .found(let content) = card.status,
              let kind = inlineCardKind(for: content), kind.count > 1 else { return nil }
        return (card.intent, kind)
    }

    @ViewBuilder
    private func inlineCardRow(_ kind: InlineCardKind, index: Int, onSelect: @escaping () -> Void) -> some View {
        switch kind {
        case .relation(let items):
            inlineSelectableRow(onSelect: onSelect) { relationLabel(items[index]) }
        case .person(let items):
            inlineSelectableRow(onSelect: onSelect) { personOrPlaceLabel(items[index]) }
        case .entity(let items):
            inlineSelectableRow(onSelect: onSelect) { entityLabel(items[index]) }
        case .theme(let items):
            inlineSelectableRow(onSelect: onSelect) { themeLabel(items[index]) }
        }
    }

    @ViewBuilder
    private func inlineCardDetail(_ kind: InlineCardKind, index: Int) -> some View {
        switch kind {
        case .relation(let items):
            // 관계 행은 그 행의 "답 인물"(예: "갓은 야곱의 아들" → 갓)의 인물 상세를 연다. 인물로 특정되지 않으면
            // (Persons에 없는 이름, 동명이인, 장소 등) 기존처럼 관계 상세로 폴백한다.
            if !items[index].answerWord.isEmpty,
               let person = PersonDetailView.resolvePerson(named: items[index].answerWord, idx: items[index].answerIdx) {
                PersonDetailView(person: person)
            } else {
                RelationDetailView(item: items[index])
            }
        case .person(let items): PersonDetailView(person: items[index])
        case .entity(let items):
            switch items[index] {
            case .person(let person): PersonDetailView(person: person)
            case .place(let place): PlaceDetailView(place: place)
            }
        case .theme(let items): ThemeDetailView(theme: items[index])
        }
    }

    /// 목록 행 하나 — 탭하면 `onSelect()`로 이 화면 안의 상태만 바꿔 상세를
    /// 연다(push 없음). `bibleVerseRow`의 아이폰 분기와 같은 이유로 오른쪽에
    /// 디스클로저 화살표를 직접 그린다 — `NavigationLink`처럼 보이되 실제로는
    /// `NavigationLink`가 아니다.
    private func inlineSelectableRow<RowLabel: View>(
        onSelect: @escaping () -> Void,
        @ViewBuilder label: () -> RowLabel
    ) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                label()
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `intentCardSection`/`macSplitCardLayout` 양쪽이 쓰는 공통 `Section`
    /// 뼈대(헤더 + `.listRowBackground(Color.clear)`) — 내용만 다르다.
    @ViewBuilder
    private func cardSectionWrapper<Content: View>(
        _ meta: (title: String, icon: String, color: Color),
        count: Int,
        // 항목이 여러 개라 "목록"을 보여줄 때만 헤더(아이콘+제목+건수 배지)를 표시한다.
        // 항목 1개짜리 상세(`intentCardSection`의 `kind.count == 1` 분기)에서는 헤더를 없애되
        // `Section`은 유지해 리스트 행 스타일(배경 등)을 그대로 받는다.
        showHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if showHeader {
            Section {
                content()
            } header: {
                sectionHeader(meta.title, icon: meta.icon, color: meta.color, count: count)
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                content()
            }
            .listRowBackground(Color.clear)
        }
    }

    /// 통합검색의 기본 `List` — 카드가 없거나, 카드 항목이 1개뿐이거나, 아이폰인 경우 항상
    /// 이걸 쓴다. 맥/아이패드에서 카드 항목이 여러 개일 때만 `body`가 `macSplitCardLayout`
    /// 으로 갈라진다.
    private var mainResultsList: some View {
        List {
            Section {
                if viewModel.isSearching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("검색 중...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if let errorDescription = viewModel.errorDescription {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorDescription)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 2)
                }

            }
            .padding(.vertical, 4)
            // `.scrollContentBackground(.hidden)`와 `List`의 `.background()`는
            // 컨테이너 배경만 바꾸고 각 행/Section 셀의 자체 배경은 투명하게 만들지 않는다. 그래서 Section 단위로
            // `.listRowBackground(Color.clear)`를 적용한다(여러 행을 만드는 컨테이너에 적용하면 안의
            // 모든 행에 전파된다).
            .listRowBackground(Color.clear)

            // 일반 검색 결과보다 먼저 보여준다(정답에 더 가까운 안내). `viewModel.intentCard`가 nil이면
            // Section 자체가 그려지지 않으며, 질문형 검색 토글이 꺼져 있을 때도 항상 nil이다
            // (`SearchViewModel.performSearch`가 카드를 계산하지 않는다).
            if let intentCard = viewModel.intentCard {
                intentCardSection(intentCard)
            }

            if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                // 아이폰만 List 본문에 최근 검색을 직접 넣는다 — `.searchSuggestions`는 검색창이
                // 포커스를 받아야만 보이는데, 탭 진입 직후에도 바로 보이게 하려는 것. 그래서 아래
                // `.searchSuggestions`는 아이폰일 때 끈다(안 그러면 포커스 중 목록이 두 번 겹쳐 보인다).
                if isPhoneIdiom {
                    recentSearchesSection
                }
            } else if !isInlineCardDisplayActive {
                resultsSection
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
        .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.3))
    }

    /// 맥/아이패드 전용 — 질의 의도 카드가 항목을 여러 개 찾았을 때 왼쪽에 목록, 오른쪽에 선택된 항목의 상세를 나란히 보여준다. 선택
    /// 전에는 오른쪽에 안내 문구만 보이며 첫 항목을 자동 선택하지 않는다. 검색창/질문형 검색 토글 등 공통 모디파이어는 `body`에 남아
    /// 있어 여기서는 결과 콘텐츠만 그린다.
    @ViewBuilder
    private func macSplitCardLayout(intent: QueryIntentClassifier.Intent, kind: InlineCardKind) -> some View {
        let meta = intentSectionMeta(intent)
        HStack(spacing: 0) {
            List {
                cardSectionWrapper(meta, count: kind.count) {
                    ForEach(0..<kind.count, id: \.self) { index in
                        inlineCardRow(kind, index: index) {
                            viewModel.aiCardSelectedIndex = index
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(settings.bibleBackgroundColor ?? Color.clear)
            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
            .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.3))
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)

            Divider()

            Group {
                if let selected = viewModel.aiCardSelectedIndex, selected < kind.count {
                    List {
                        inlineCardDetail(kind, index: selected)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(settings.bibleBackgroundColor ?? Color.clear)
                    .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                    .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.3))
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: meta.icon)
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("왼쪽 목록에서 항목을 선택하세요")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - 질의 의도 카드 (관계/인물·지명 정보/예언/주제·속성/서사, 2026-08-20 신설)
    // `QueryIntentClassifier`+`QueryIntentHandler` 결과를 `resultsSection` 위에 별도
    // Section으로 보여준다. 데이터가 없으면 안내 문구만 뜨고 일반 검색은 항상 그대로 나오므로, 카드가 오분류되거나 데이터가
    // 없어도 검색이 막히지 않는다.
    // 관계/인물/주제(`InlineCardKind`)는 카드가 뜨면 일반 검색을 함께 보여주지
    // 않는다(`isInlineCardDisplayActive`). 항목이 1개면 바로 상세, 여러 개면 목록(탭하면 상세로 전환)이다.
    // 맥/아이패드에서 여러 개면 `body`가 `macSplitCardLayout`으로 대체하므로 이 함수는 호출되지 않는다.

    @ViewBuilder
    private func intentCardSection(_ card: QueryIntentCard) -> some View {
        let meta = intentSectionMeta(card.intent)
        switch card.status {
        case .notReady(let message):
            cardSectionWrapper(meta, count: card.foundCount) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(message)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        case .found(let content):
            if let kind = inlineCardKind(for: content) {
                if kind.count == 1 {
                    cardSectionWrapper(meta, count: 1, showHeader: false) {
                        inlineCardDetail(kind, index: 0)
                    }
                } else if let selected = viewModel.aiCardSelectedIndex, selected < kind.count {
                    cardSectionWrapper(meta, count: kind.count, showHeader: false) {
                        Button {
                            viewModel.aiCardSelectedIndex = nil
                        } label: {
                            Label("목록으로", systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(settings.bibleTextColor ?? .primary)
                        .padding(.vertical, 2)

                        inlineCardDetail(kind, index: selected)
                    }
                } else {
                    cardSectionWrapper(meta, count: kind.count) {
                        ForEach(0..<kind.count, id: \.self) { index in
                            inlineCardRow(kind, index: index) {
                                viewModel.aiCardSelectedIndex = index
                            }
                        }
                    }
                }
            } else {
                cardSectionWrapper(meta, count: card.foundCount) {
                    intentContentRows(content)
                }
            }
        }
    }

    // 아이콘 색은 고정 시스템 색 대신 커스텀 읽기 테마 글자색(`settings.bibleTextColor`)을 따른다(고정 색은
    // 특정 테마 배경에서 대비가 낮아진다). 카테고리 구분은 아이콘 모양과 섹션 제목이 맡고, 테마 미선택 시 `.primary`.
    private func intentSectionMeta(_ intent: QueryIntentClassifier.Intent) -> (title: String, icon: String, color: Color) {
        let themeColor = settings.bibleTextColor ?? .primary
        switch intent {
        case .relation: return ("관계 정보", "person.2.fill", themeColor)
        case .personProfile: return ("인물 정보", "person.crop.circle.fill", themeColor)  // [2026-09-15] personOrPlaceInfo 대체, 장소 미포함
        case .placeProfile: return ("인물·장소 정보", "mappin.and.ellipse", themeColor)  // [2026-10-01] 장소(PlaceSeed.json) 신설
        case .prophecy: return ("예언", "scroll.fill", themeColor)
        case .themeOrAttribute: return ("주제·속성", "lightbulb.fill", themeColor)
        case .narrative: return ("서사·흐름", "list.number", themeColor)
        case .general: return ("", "questionmark", themeColor)  // QueryIntentHandler.handle이 .general이면 nil을 돌려줘서 실제로는 안 쓰인다.
        }
    }

    // 관계/인물/주제는 `intentCardSection`이 `inlineCardKind` 경로로 먼저 처리해 여기까지 오지 않는다.
    // `Content` 열거형이라 switch는 전부 다뤄야 하며, 예언/서사는 데이터가 없어 항상
    // `.notReady`(`QueryIntentHandler.swift` 상단 주석)라 현재는 실행되지 않는다 — 데이터가 채워지면
    // 그대로 동작한다.
    @ViewBuilder
    private func intentContentRows(_ content: QueryIntentCard.Content) -> some View {
        switch content {
        case .relation, .personProfile, .entityProfile, .theme:
            EmptyView()
        case .prophecy(let prophecies):
            ForEach(Array(prophecies.enumerated()), id: \.offset) { _, prophecy in
                prophecyRow(prophecy)
            }
        case .narrative(let groups):
            ForEach(groups) { group in
                narrativeGroupRows(group)
            }
        }
    }

    // MARK: - 관계 행

    /// 관계 행. 탭하면 push하지 않고 `viewModel.aiCardSelectedIndex`로 이 화면 안에서
    /// 행의 답 인물 상세(`PersonDetailView`)로 전환한다. 인물로 특정되지 않으면 `RelationDetailView`
    /// (문장 + 관련 성경구절 칩)로 폴백한다(`inlineCardDetail` 참고).
    private func relationLabel(_ item: RelationDisplayItem) -> some View {
        rowLabel(
            icon: "person.2.fill", iconColor: settings.bibleTextColor ?? .primary,
            title: PersonRelationLabeling.sentence(for: item.relation),
            excerptText: PersonRelationLabeling.displayRawSentence(item.relation.rawSentence)
        )
    }

    // MARK: - 인물·지명 정보 행

    // `PersonEntity`(보강 컬럼 + 관계 리스트)를 받으며 항상 인물이라 아이콘을 고정한다(장소 미노출). 탭하면
    // `viewModel.aiCardSelectedIndex`로 화면 안 상세로
    // 전환하고(`intentCardSection`/`inlineCardRow` 참고), 성경 구절 이동은 상세의 "관련 성경구절" 칩이
    // 맡는다.
    private func personOrPlaceLabel(_ entity: PersonEntity) -> some View {
        rowLabel(
            icon: "person.crop.circle.fill",
            iconColor: settings.bibleTextColor ?? .primary,
            title: entity.word,
            excerptText: entity.entityRemark
        )
    }

    // MARK: - 인물·장소 혼합 행

    /// 인물은 인물 아이콘, 장소는 핀 아이콘. 같은 이름의 지명은 `remark`("1. …", "2. …")가 요약 줄에 나와 구분된다.
    private func entityLabel(_ item: ProfileItem) -> some View {
        switch item {
        case .person(let person):
            return rowLabel(
                icon: "person.crop.circle.fill", iconColor: settings.bibleTextColor ?? .primary,
                title: person.word, excerptText: person.entityRemark
            )
        case .place(let place):
            return rowLabel(
                icon: "mappin.circle.fill", iconColor: settings.bibleTextColor ?? .primary,
                title: place.word, excerptText: place.remark
            )
        }
    }

    // MARK: - 예언 행

    private func prophecyRow(_ prophecy: ProphecyRecord) -> some View {
        Group {
            if let first = prophecy.prophecyRefs.first {
                bibleVerseRow(BibleVerseDestination(
                    bookId: first.bookId, chapter: first.chapter, verse: first.verse
                )) {
                    prophecyLabel(prophecy)
                }
            } else {
                prophecyLabel(prophecy)
            }
        }
    }

    private func prophecyLabel(_ prophecy: ProphecyRecord) -> some View {
        var tags = [prophecy.category]
        if let period = prophecy.timelinePeriod, !period.isEmpty { tags.append(period) }
        return rowLabel(
            icon: "scroll.fill", iconColor: settings.bibleTextColor ?? .primary,
            title: prophecy.title,
            tagNames: tags.filter { !$0.isEmpty },
            excerptText: prophecy.prophecyDescription
        )
    }

    // MARK: - 주제·속성 행

    // 위 `personOrPlaceLabel`과 같이 탭하면 화면 안 상태 전환으로 `ThemeDetailView`를 보여준다.
    private func themeLabel(_ theme: ThemeRecord) -> some View {
        rowLabel(
            icon: "lightbulb.fill", iconColor: settings.bibleTextColor ?? .primary,
            title: theme.title,
            tagNames: [theme.category].filter { !$0.isEmpty },
            excerptText: theme.themeDescription
        )
    }

    // MARK: - 서사 행

    @ViewBuilder
    private func narrativeGroupRows(_ group: NarrativeGroup) -> some View {
        ForEach(Array(group.events.enumerated()), id: \.offset) { _, event in
            narrativeEventRow(group: group, event: event)
        }
    }

    private func narrativeEventRow(group: NarrativeGroup, event: TimelineEventRecord) -> some View {
        Group {
            if let first = event.verseRefs.first {
                bibleVerseRow(BibleVerseDestination(
                    bookId: first.bookId, chapter: first.chapter, verse: first.verse
                )) {
                    narrativeEventLabel(group: group, event: event)
                }
            } else {
                narrativeEventLabel(group: group, event: event)
            }
        }
    }

    private func narrativeEventLabel(group: NarrativeGroup, event: TimelineEventRecord) -> some View {
        rowLabel(
            icon: "list.number", iconColor: settings.bibleTextColor ?? .primary,
            title: "\(group.narrativeTitle) — \(event.eventTitle)",
            excerptText: event.eventDescription
        )
    }

    // MARK: - 최근 검색 (2026-09-04 신설, 아이폰 전용)

    /// 아이폰이고 검색어가 비어 있을 때만 보이는 최근 검색 Section(포커스 여부와 무관). 항목을 탭하면 그 검색어로 즉시
    /// 검색한다 — `.searchSuggestions`의 탭 동작과 같다.
    /// 같다.
    private var recentSearchesSection: some View {
        let recentSearches = viewModel.recentSearchHistory()
        return Group {
            if !recentSearches.isEmpty {
                Section("최근 검색") {
                    ForEach(recentSearches) { entry in
                        Button {
                            viewModel.query = entry.query
                            viewModel.searchImmediately()
                            dismissSearch()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                Text(entry.query)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - 결과

    // 커스텀 섹션 헤더(아이콘 + 굵은 제목 + 캡슐형 개수 배지)를 쓴다 — `Section("문자열")`의 기본 헤더는 작은 대문자
    // 스타일이라 아이콘을 넣을 자리가 없다.
    @ViewBuilder
    private var resultsSection: some View {
        // 상위 탭은 네이티브 `.pickerStyle(.segmented)` 대신 커스텀 `HStack`+`Button`으로 그린다
        // — macOS `NSSegmentedControl`은 세그먼트 아이콘을 단색 템플릿으로 그리고 선택 내용색을 시스템
        // 강조색으로 덮어써, 세그먼트별 커스텀 색이 반영되지 않을 위험이 있다.
        HStack(spacing: 8) {
            ForEach(SearchResultTab.allCases) { tab in
                mainResultTabButton(tab)
            }
        }
        .listRowSeparator(.hidden)
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)

        // 메뉴(위 탭들, 번역본 하위 탭 포함)와 콘텐츠(검색 결과)의 경계 한 곳에만 장식 구분선을 넣는다.
        menuContentOrnamentalDivider

        switch selectedResultTab {
        case .verse:
        // 활성 번역본별 하위 탭(최대 3개, `SearchViewModel.resolveActiveTranslations`에서
        // 캡). 번역본이 1개뿐이면 하위 탭이 불필요하므로 2개 이상일 때만 노출한다.
        let activeVerseTranslations = viewModel.activeTranslations
        let showsVerseTranslationTabs = activeVerseTranslations.count > 1
        let selectedVerseTranslation: String? = {
            guard showsVerseTranslationTabs else { return nil }
            if let selectedVerseTranslationCode,
               activeVerseTranslations.contains(where: { $0.code == selectedVerseTranslationCode }) {
                return selectedVerseTranslationCode
            }
            return activeVerseTranslations.first?.code
        }()
        // 성경구절 결과는 책 단위 접이식 목록으로 보여준다(2026-10-02 목업 채택). 책 묶음·정렬·펼침·더보기 상태는 모두
        // `SearchViewModel`(`verseBookGroups` 등)이 갖고, 랭킹(`searchVerses`: 매칭 단어 수 → 성경순)은 건드리지 않는다.
        // 번역본 하위 탭이 선택돼 있으면 그 번역본 결과만 묶고, 더보기·펼친 절 수는 번역본별로 독립이다.
        let verseBookGroups = viewModel.verseBookGroups(translationCode: selectedVerseTranslation)
        let verseTranslationKey = selectedVerseTranslation ?? "all"

        // 하위 탭임이 디자인에서 드러나도록 왼쪽에 `arrow.turn.down.right` 아이콘을 두고
        // `.padding(.leading, 16)`으로 들여쓴다.
        if showsVerseTranslationTabs {
            // 번역본 캡슐은
            // `mainResultTabButton`/`WordNoteHomeView.categoryCapsuleButton`과
            // 같은 규칙(선택 시 accent 테두리+틴트, 평소엔 테마 글자색)을 따른다 — 네이티브 세그먼트는 macOS에서
            // 커스텀 색이 반영되지 않을 위험이 있다.
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
                Text("번역본")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.8) ?? Color.secondary)
                    .fixedSize()
                ForEach(activeVerseTranslations, id: \.code) { translation in
                    translationCapsuleButton(translation, isSelected: translation.code == selectedVerseTranslation)
                }
            }
            .padding(.leading, 16)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if !verseBookGroups.isEmpty {
            verseBookControlsRow(bookIds: verseBookGroups.map(\.bookId))
        }

        Section {
            if verseBookGroups.isEmpty {
                emptyRow()
            } else {
                verseBookRows(verseBookGroups, translationKey: verseTranslationKey)
            }
        }
        .listRowBackground(Color.clear)

        case .outline:
        Section {
            if viewModel.outlineResults.isEmpty { emptyRow() }
            // `outlineResults`(순서/필터링)는 그대로 두고 표시만
            // `SearchViewModel.groupedOutlineResults`로 책 단위 그룹을 만든다(성경구절의 장 단위
            // 그룹핑과 같은 방식).
            ForEach(viewModel.groupedOutlineResults) { group in
                groupCardBorder {
                    VStack(alignment: .leading, spacing: 0) {
                        outlineGroupHeader(group)
                            .padding(.bottom, 6)
                        ForEach(Array(group.items.enumerated()), id: \.offset) { index, result in
                            if index > 0 {
                                // 위 `verseChapterCard` 구분선과 같은 이유.
                                Rectangle()
                                    .fill(JBCHCategoryPalette.wood.opacity(0.3))
                                    .frame(height: 0.5)
                            }
                            groupedOutlineRow(result)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.clear)

        case .notes:
        Section {
            if viewModel.phraseNoteResults.isEmpty { emptyRow() }
            ForEach(viewModel.phraseNoteResults) { result in
                phraseNoteRow(result)
            }
        } header: {
            sectionHeader("메모", icon: "note.text", color: settings.bibleTextColor ?? .primary, count: viewModel.phraseNoteResults.count)
        }
        .listRowBackground(Color.clear)

        Section {
            if viewModel.memoResults.isEmpty { emptyRow() }
            ForEach(viewModel.memoResults) { result in
                memoRow(result)
            }
        } header: {
            sectionHeader("개인 묵상", icon: "heart.text.square.fill", color: settings.bibleTextColor ?? .primary, count: viewModel.memoResults.count)
        }
        .listRowBackground(Color.clear)

        Section {
            if viewModel.summaryResults.isEmpty { emptyRow() }
            ForEach(viewModel.summaryResults) { result in
                summaryRow(result)
            }
        } header: {
            sectionHeader("말씀 요약", icon: "text.quote", color: settings.bibleTextColor ?? .primary, count: viewModel.summaryResults.count)
        }
        .listRowBackground(Color.clear)

        case .document:
        Section {
            if viewModel.documentResults.isEmpty { emptyRow() }
            ForEach(viewModel.documentResults) { result in
                documentRow(result)
            }
        }
        .listRowBackground(Color.clear)

        case .sermon:
        Section {
            if viewModel.sermonResults.isEmpty { emptyRow() }
            ForEach(viewModel.sermonResults) { result in
                sermonRow(result)
            }
        }
        .listRowBackground(Color.clear)
        }
    }

    /// 메뉴와 콘텐츠 경계에 넣는 장식 구분선(가로선-`sparkle`-가로선). 선·장식 색은 `groupCardBorder` 테두리와
    /// 같은 테마 글자색 30% 톤이다.
    private var menuContentOrnamentalDivider: some View {
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
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// 커스텀 섹션 헤더 — 아이콘 + 굵은 제목 + 캡슐형 개수 배지. `.textCase(nil)`로
    /// List 섹션 헤더 기본값(작은 대문자)을 끄지 않으면 우리가 지정한 `.headline`
    /// 스타일이 시스템 스타일에 덮인다.
    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    /// `resultsSection` 상위 탭 버튼 하나. 선택 여부에 따라 꽉 찬/옅은 배경으로 눌림 상태를 분명히 하고,
    /// 아이콘+제목을 세로로 쌓는다.
    private func mainResultTabButton(_ tab: SearchResultTab) -> some View {
        let isSelected = selectedResultTab == tab
        // 삼항 연산자 + 옵셔널 체이닝을 인라인하면 "The compiler is unable to type-check this
        // expression in reasonable time" 빌드 에러가 나므로 명시적 타입의 `let`으로
        // 뽑는다(`WordNoteHomeView.categoryCapsuleButton`과 동일).
        let textColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.65) ?? Color.secondary)
        let fillColor: Color = isSelected ? Color("AccentColor").opacity(0.12) : Color.clear
        let borderColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.35) ?? Color.secondary.opacity(0.35))
        let count = tabResultCount(tab)
        return Button {
            selectedResultTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(tab.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if count > 0 {
                    // 총 일치 개수는 탭 버튼 안에 표시한다. "메모/말씀노트" 탭은 세 분류
                    // 합계(`tabResultCount` 참고).
                    Text("\(count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(textColor)
            // 이 화면의 다른 카드들과 같은 계열의 `RoundedRectangle`(12pt) — 세로로 아이콘+제목+개수를
            // 담는 큰 박스라 12pt로 했다.
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(borderColor, lineWidth: 1.4))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// 탭별 총 일치 개수. 번역본 하위 탭 선택과 무관하게 항상 카테고리 전체 기준이다 — [성경구절] 탭은 선택된 번역본만이 아니라
    /// 활성 번역본 전체 합계(`allVerseResults`)이고, "메모/말씀노트" 탭은 세 모델 합계다.
    private func tabResultCount(_ tab: SearchResultTab) -> Int {
        switch tab {
        case .verse: return viewModel.allVerseResults.count
        case .outline: return viewModel.outlineResults.count
        case .notes: return viewModel.phraseNoteResults.count + viewModel.memoResults.count + viewModel.summaryResults.count
        case .document: return viewModel.documentResults.count
        case .sermon: return viewModel.sermonResults.count
        }
    }

    /// 번역본 하나의 캡슐 버튼 — `mainResultTabButton`과 같은 규칙(선택 시 accent 테두리+틴트, 평소엔 테마
    /// 글자색).
    private func translationCapsuleButton(_ translation: TranslationRegistry, isSelected: Bool) -> some View {
        let textColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.55) ?? Color.secondary)
        let fillColor: Color = isSelected ? Color("AccentColor").opacity(0.12) : Color.clear
        let borderColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.35) ?? Color.secondary.opacity(0.35))
        return Button {
            selectedVerseTranslationCode = translation.code
        } label: {
            Text(translation.displayName)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(textColor)
                .background(Capsule().fill(fillColor))
                .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func emptyRow(_ text: String = "결과 없음") -> some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .foregroundStyle(.tertiary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.body)
        .padding(.vertical, 6)
    }

    /// 6개 분류 행이 공유하는 뼈대(아이콘 배지 + 제목(+참조 배지) + 태그 배지 + 본문 발췌)를 한 곳에 모았다.
    /// `matchedWordCount`가 nil이면(성경구절 본문 미리보기처럼 "몇 번 일치"가 무의미한 경우) 칩 없이 발췌 텍스트만
    /// 보여준다.
    @ViewBuilder
    private func rowLabel(
        icon: String,
        iconColor: Color,
        title: String,
        isReferenceMatch: Bool = false,
        tagNames: [String] = [],
        // 중복 제거된 매칭 검색어 수(성경구절 탭과 통일).
        matchedWordCount: Int? = nil,
        excerptText: String? = nil,
        excerptKeywords: [String] = []
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            categoryIcon(icon, color: iconColor)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if isReferenceMatch {
                        badge("참조 일치", color: referenceMatchGreen, systemImage: "checkmark.seal.fill")
                    }
                    Spacer(minLength: 4)
                }
                if !tagNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tagNames, id: \.self) { name in
                            badge(name, color: tagBadgeBlue, systemImage: "tag.fill")
                        }
                    }
                }
                if let excerptText {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let matchedWordCount, matchedWordCount > 0 {
                            verseMatchCountBadge(matchedWordCount)
                        }
                        // `.foregroundStyle(.secondary)`를 뷰 모디파이어로 직접 지정하면 조상의
                        // 테마 `.foregroundStyle`을 덮어쓰므로 테마 글자색을
                        // 명시한다(`rowLabel`을 공유하는 모든 행의 발췌 본문에 해당).
                        highlightedText(excerptText, keywords: excerptKeywords)
                            .font(.body)
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? Color.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// 메모/말씀노트/연구문서 결과 행 전용 라벨. 성경구절/개요 행과 같은 크기를 쓴다
    /// (아이콘 18pt 폭 프레임, 제목 `.headline`, 발췌 15pt, 세로 여백 2).
    /// `rowLabel`은 관계/인물·지명/예언/주제·속성/서사 카테고리와 공유하므로 건드리지 않는다.
    private func compactItemLabel(
        icon: String,
        iconColor: Color,
        title: String,
        isReferenceMatch: Bool = false,
        tagNames: [String] = [],
        matchedWordCount: Int? = nil,
        excerptText: String? = nil,
        excerptKeywords: [String] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if isReferenceMatch {
                    badge("참조 일치", color: referenceMatchGreen, systemImage: "checkmark.seal.fill")
                }
                Spacer(minLength: 4)
            }
            if !tagNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tagNames, id: \.self) { name in
                        badge(name, color: tagBadgeBlue, systemImage: "tag.fill")
                    }
                }
            }
            if let excerptText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let matchedWordCount, matchedWordCount > 0 {
                        verseMatchCountBadge(matchedWordCount)
                    }
                    highlightedText(excerptText, keywords: excerptKeywords)
                        .font(.system(size: 15))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? Color.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 분류별 색상 원형 아이콘 배지.
    private func categoryIcon(_ systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 성경구절

    /// 결과 단위(성경구절 장 그룹, 개요 책 그룹, 메모·개인 묵상·말씀 요약·연구문서 각 항목)를
    /// 감싸는 라운드 테두리. 배경은 채우지 않고 `bibleTextColor` 30% 톤의 스트로크만 그린다
    /// (`.listRowSeparatorTint`와 같은 값).
    private func groupCardBorder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 25)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(JBCHCategoryPalette.wood.opacity(0.3), lineWidth: 1)
            )
            // 카드와 카드 사이의 바깥 세로 간격.
            .padding(.vertical, 5)
            // List 기본 행 인셋(위/아래)이 위 padding에 얹히지 않도록 0으로 두어 카드 간 세로
            // 간격을 위 padding 하나가 전담하게 한다. 좌우는 List 기본값(16)을 유지한다.
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
    }

    // MARK: - 성경구절: 책 단위 접기

    /// 정렬 선택 캡슐 + 모두 펼치기/접기. 번역본 하위 탭 줄과 같은 들여쓰기·캡슐 규칙을 쓴다.
    private func verseBookControlsRow(bookIds: [Int]) -> some View {
        let anyExpanded = !viewModel.expandedVerseBookIds.isEmpty
        return HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
            Text("정렬")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.8) ?? Color.secondary)
                .fixedSize()
            ForEach(viewModel.availableVerseBookSorts) { sort in
                bookCapsuleButton(title: sort.title, isSelected: sort == viewModel.verseBookSort) {
                    viewModel.setVerseBookSort(sort)
                }
            }
            Spacer(minLength: 4)
            Button(anyExpanded ? "모두 접기" : "모두 펼치기") {
                if anyExpanded {
                    viewModel.collapseAllVerseBooks()
                } else {
                    viewModel.expandAllVerseBooks(bookIds)
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? Color.secondary)
        }
        .padding(.leading, 16)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// `translationCapsuleButton`과 같은 모양의 범용 캡슐(정렬 선택용).
    private func bookCapsuleButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let textColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.55) ?? Color.secondary)
        let fillColor: Color = isSelected ? Color("AccentColor").opacity(0.12) : Color.clear
        let borderColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.35) ?? Color.secondary.opacity(0.35))
        return Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(textColor)
                .background(Capsule().fill(fillColor))
                .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// 정렬에 따른 책 목록. 성경순은 구약/신약 머리줄로 나누고(각각 접기·더보기 독립), 관련도순·많은 순은 한 줄 목록이다 —
    /// 관련도순에 구약/신약 구획을 두면 신약의 높은 매칭 수 결과가 구약 아래로 밀려 정렬 규칙이 깨지므로 구획을 쓰지 않는다.
    @ViewBuilder
    private func verseBookRows(_ groups: [SearchViewModel.VerseBookGroup], translationKey: String) -> some View {
        switch viewModel.verseBookSort {
        case .canon:
            verseTestamentRows(title: "구약", key: "old", groups: groups.filter(\.isOldTestament), translationKey: translationKey)
            verseTestamentRows(title: "신약", key: "new", groups: groups.filter { !$0.isOldTestament }, translationKey: translationKey)
        case .relevance, .count:
            verseBookList(groups, limitKey: "\(translationKey)|flat", translationKey: translationKey)
        }
    }

    @ViewBuilder
    private func verseTestamentRows(title: String, key: String, groups: [SearchViewModel.VerseBookGroup], translationKey: String) -> some View {
        if !groups.isEmpty {
            let collapsed = viewModel.isTestamentCollapsed(key)
            let total = groups.reduce(0) { $0 + $1.verses.count }
            Button {
                viewModel.toggleTestament(key)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 14)
                    Text(title)
                        .font(.title3.weight(.bold))
                    Text("\(groups.count)권 · \(total)개 절")
                        .font(.footnote)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    Spacer()
                }
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityValue(collapsed ? "접힘" : "펼침")

            if !collapsed {
                verseBookList(groups, limitKey: "\(translationKey)|\(key)", translationKey: translationKey)
            }
        }
    }

    @ViewBuilder
    private func verseBookList(_ groups: [SearchViewModel.VerseBookGroup], limitKey: String, translationKey: String) -> some View {
        let visibleCount = viewModel.visibleBookCount(limitKey: limitKey)
        ForEach(groups.prefix(visibleCount)) { group in
            verseBookBlock(group, translationKey: translationKey)
        }
        if groups.count > visibleCount {
            let remaining = groups.count - visibleCount
            HStack(spacing: 12) {
                Spacer()
                Button {
                    viewModel.requestMoreBooks(limitKey: limitKey, remainingBooks: remaining, showAll: false)
                } label: {
                    Label("책 더보기 (\(remaining)권 남음)", systemImage: "chevron.down.circle")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                Button("모두 펼치기") {
                    viewModel.requestMoreBooks(limitKey: limitKey, remainingBooks: remaining, showAll: true)
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? Color.secondary)
                Spacer()
            }
            // 아이콘/글자 색은 테마 글자색 — `JBCHCategoryPalette.navy`는 "밤빛 서재" 테마 배경과 같은 색이라 그 테마에서 거의 안 보인다.
            .foregroundStyle(settings.bibleTextColor ?? .primary)
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    /// 책 머리줄 한 행 + (펼쳤을 때) 장 카드 행들 + "이 책 더보기".
    @ViewBuilder
    private func verseBookBlock(_ group: SearchViewModel.VerseBookGroup, translationKey: String) -> some View {
        let expanded = viewModel.isVerseBookExpanded(group.bookId)
        groupCardBorder {
            Button {
                viewModel.toggleVerseBook(group.bookId)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 14)
                    Text(group.bookNameKo)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text("\(group.verses.count)개 절")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "펼침" : "접힘")
        }
        if expanded {
            let page = viewModel.visibleChapterGroups(for: group, translationKey: translationKey)
            ForEach(page.groups) { chapterGroup in
                verseChapterCard(chapterGroup)
                    .padding(.leading, 14)
            }
            if page.remainingVerses > 0 {
                HStack {
                    Spacer()
                    Button {
                        viewModel.loadMoreVersesInBook(bookId: group.bookId, translationKey: translationKey)
                    } label: {
                        Label("\(group.bookNameKo) 더보기 (\(page.remainingVerses)개 남음)", systemImage: "chevron.down.circle")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    Spacer()
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    /// 장 단위 카드(기존 장 그룹 카드 그대로 — 헤더 + 절 행들).
    private func verseChapterCard(_ group: SearchViewModel.VerseSearchResultGroup) -> some View {
        groupCardBorder {
            VStack(alignment: .leading, spacing: 0) {
                verseChapterGroupHeader(group)
                    .padding(.bottom, 6)
                ForEach(Array(group.verses.enumerated()), id: \.offset) { index, result in
                    if index > 0 {
                        // List 구분선/카드 테두리(`groupCardBorder`)와 같은 wood 톤으로 통일한다.
                        Rectangle()
                            .fill(JBCHCategoryPalette.wood.opacity(0.3))
                            .frame(height: 0.5)
                    }
                    groupedVerseRow(result)
                }
            }
        }
    }

    /// 성경구절 결과의 장 단위 그룹 헤더(책 + 장, 절 개수).
    /// `groupCardBorder` 내부 요소라 `.listRowSeparator`는 두지 않는다.
    private func verseChapterGroupHeader(_ group: SearchViewModel.VerseSearchResultGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .frame(width: 18)
            Text("\(group.bookNameKo) \(group.chapter)장")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Text("\(group.verses.count)절")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    /// 장 헤더 아래에 "N절) 본문" 형태로 표시하는 절 행. 책/장은 헤더가 이미 보여준다.
    private func groupedVerseRow(_ result: VerseSearchResult) -> some View {
        // 본문 `Text`만 독립된 `Button`으로 감싸 해당 절로 이동한다. 한 행 안에 여러
        // 암묵적 NavigationLink가 섞이면 탭 대상이 불안정해지는 문제(`OutlineTreeView.swift`
        // 상단 주석)가 있어, 행 전체를 링크로 감싸지 않고 선택/복사 Button과 나란히 둔다.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // 접두어와 본문을 별도 `Text`로 나란히 두어 본문이 줄바꿈돼도 접두어 폭만큼
            // 들여쓰기가 유지된다(`PersonDetailView.verseReferenceRow`와 같은 방식).
            HStack(alignment: .top, spacing: 0) {
                Text(versePrefixAttributedString(result))
                    .fixedSize()
                Text(verseBodyAttributedString(result))
            }
            .lineLimit(2)
            if result.isReferenceMatch {
                badge("참조 일치", color: referenceMatchGreen, systemImage: "checkmark.seal.fill")
            }
            Spacer(minLength: 8)
            verseRowActionButtons(result)
            // 참조 매치는 `matchCount`가 항상 0이라 배지를 숨긴다.
            if result.matchCount > 0 {
                verseMatchCountBadge(result.matchCount)
            }
        }
        .padding(.vertical, 5.2)
        // 본문 글자뿐 아니라 행 어디를 눌러도(빈 공간 포함) 그 절로 이동한다. 안쪽 선택/복사 `Button`은 자기 클릭을 먼저 처리하므로
        // 이 탭 제스처는 실행되지 않는다. `Button`이 아니라 `contentShape` + `onTapGesture`인 이유: 행 전체를 Button으로 감싸면
        // 안쪽 버튼들과 중첩돼 macOS에서 클릭 대상이 불안정해진다(위 주석의 같은 문제).
        .contentShape(Rectangle())
        .onTapGesture { openVerseInBibleReading(result) }
        .accessibilityAddTraits(.isButton)
    }

    /// 절 행 탭 — "성경 조회" 섹션으로 전환하고 목표 절을 넘긴다. 성경 조회 화면이 새로 만들어지면 `.onAppear`, 이미 떠 있으면
    /// `.onChange`가 그 절로 자동 스크롤하고 잠시 강조한다(`BibleReadingView`/`TranslationColumnView`의 `highlightedVerse` 경로).
    private func openVerseInBibleReading(_ result: VerseSearchResult) {
        AppNavigationRequest.shared.request(.bibleReading)
        BibleVerseNavigationRequest.shared.request(
            bookId: result.bookId, chapter: result.chapter, verse: result.verse
        )
    }

    /// 절 행 오른쪽의 선택/복사 버튼. 이동은 본문 `Button`이 담당한다.
    /// - 선택: `VerseTextSelectionPopover`를 띄운다(한자 주석은 기본값 `[]`이라 생략).
    /// - 복사: `BibleVerseCopyFormatter.format`에 이 절의 번역본 하나만 넘긴다
    ///   (`BibleReadingView.copySingleTranslation`과 같은 패턴).
    private func verseRowActionButtons(_ result: VerseSearchResult) -> some View {
        HStack(spacing: 14) {
            Button {
                partialTextSelectionTarget = PartialTextSelectionTarget(
                    verseNumber: result.verse,
                    translationDisplayName: result.translationDisplayName,
                    text: result.content
                )
            } label: {
                Image(systemName: "character.cursor.ibeam")
            }
            .help("선택")

            Button {
                copySearchResult(result)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("복사")
        }
        .buttonStyle(.plain)
        // 아이콘 색은 테마 글자색을 따르고, 테마를 고르지 않았으면 `.secondary`.
        .foregroundStyle(settings.bibleTextColor ?? Color.secondary)
        .font(.system(size: 16))
    }

    /// 검색된 번역본 하나만 담아 포맷해 클립보드에 복사한다.
    private func copySearchResult(_ result: VerseSearchResult) {
        guard let book = BooksProvider.shared.book(id: result.bookId) else { return }
        let verse = BibleVerse(
            uid: 0, versionCode: result.translationCode, bookId: result.bookId,
            chapter: result.chapter, verse: result.verse, content: result.content, paragraph: nil
        )
        guard let text = BibleVerseCopyFormatter.format(
            book: book, chapter: result.chapter, selectedVerses: [result.verse],
            translations: [BibleVerseCopyFormatter.TranslationSnapshot(
                displayName: result.translationDisplayName, verses: [verse]
            )]
        ) else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        showToast("복사되었습니다.")
    }

    /// 토스트를 띄우고 1.6초 뒤 스스로 지운다. 연달아 부르면 이전 예약을 취소하고 새로 예약한다(`BibleReadingView.showToast`와 동일).
    private func showToast(_ message: String) {
        toastDismissWorkItem?.cancel()
        withAnimation {
            toastMessage = message
        }
        let workItem = DispatchWorkItem {
            withAnimation {
                toastMessage = nil
            }
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    @ViewBuilder
    private var searchToastOverlay: some View {
        if let toastMessage {
            Text(toastMessage)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.8), in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    /// "N절) " 접두어 `AttributedString`(굵게, 테마 글자색). `Text + Text`는 macOS 26에서
    /// deprecated라 `AttributedString`을 쓴다.
    private func versePrefixAttributedString(_ result: VerseSearchResult) -> AttributedString {
        var prefix = AttributedString("\(result.verse)절) ")
        prefix.font = .system(size: 15, weight: .semibold)
        // `AttributedString`에 직접 지정한 `.primary`/`.secondary`는 조상의
        // `.foregroundStyle(bibleTextColor)`보다 우선해 다크 모드에서 밝은 테마 배경 위에도
        // 흰색으로 남으므로, 테마 글자색을 명시한다.
        prefix.foregroundColor = settings.bibleTextColor ?? .primary
        return prefix
    }

    private func verseBodyAttributedString(_ result: VerseSearchResult) -> AttributedString {
        var body = highlightedAttributedString(result.content, keywords: result.highlightKeywords)
        body.font = .system(size: 15)
        body.foregroundColor = settings.bibleTextColor?.opacity(0.75) ?? .secondary
        return body
    }

    /// 일치한 서로 다른 검색어 수(`matchCount`)를 "N단어" 캡슐로 표시하는 오른쪽 끝 배지.
    private func verseMatchCountBadge(_ count: Int) -> some View {
        let color = verseMatchCountBadgeColor(count)
        return Text("\(count)단어")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .fixedSize()
    }

    /// 일치 단어 수별 배지 색 (1 회색, 2 초록, 3 파랑, 4 금색, 5 주황, 6 이상 빨강).
    private func verseMatchCountBadgeColor(_ count: Int) -> Color {
        switch count {
        case 1: return .gray
        case 2: return .green
        case 3: return .blue
        case 4: return JBCHCategoryPalette.gold   // [2026-09-11 수정] 근사 RGB 대신 이미 있는 팔레트 금색을 재사용
        case 5: return .orange
        default: return .red   // 6 이상 (0 이하는 호출부가 `matchCount > 0`일 때만 부르므로 실질적으로 발생하지 않음)
        }
    }

    // MARK: - 개요(BookOutline/ChapterSummary)

    /// 개요 결과의 책 단위 그룹 헤더(책 이름, 개수). `groupCardBorder` 내부 요소다.
    private func outlineGroupHeader(_ group: SearchViewModel.OutlineSearchResultGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .frame(width: 18)
            Text(group.bookNameKo)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Text("\(group.items.count)개")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    /// 개요 결과 행. 아이콘은 책 헤더(`outlineGroupHeader`)에만 두고, 이 행은 "개요) " 또는
    /// "N장) " 접두어 + 본문 한 줄과 오른쪽 끝 "N단어" 배지로 그린다.
    private func groupedOutlineRow(_ result: OutlineSearchResult) -> some View {
        Button {
            AppNavigationRequest.shared.request(.outline)
            if let chapter = result.chapter {
                OutlineNavigationRequest.shared.request(bookId: result.bookId, chapter: chapter)
            } else {
                OutlineNavigationRequest.shared.requestBook(bookId: result.bookId)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(outlineExcerptAttributedString(result))
                    .lineLimit(2)
                if result.isReferenceMatch {
                    badge("참조 일치", color: referenceMatchGreen, systemImage: "checkmark.seal.fill")
                }
                Spacer(minLength: 8)
                // 본문 매칭이 없는 참조 일치(`matchedWordCount == 0`)는 배지를 숨긴다.
                // `verseMatchCountBadgeColor`는 1 이상만 전제한다.
                if let bodyExcerpt = result.bodyExcerpt, !bodyExcerpt.isEmpty, result.matchedWordCount > 0 {
                    verseMatchCountBadge(result.matchedWordCount)
                }
            }
            .padding(.vertical, 5.2)
            .contentShape(Rectangle())
        }
        // 새 화면으로 전환하는 Button이 List 안에서 NavigationLink 행과 같은 텍스트 색이
        // 되도록 `.plain`을 쓴다.
        .buttonStyle(.plain)
    }

    /// "N장)"/"개요)" 접두어(굵게, 테마 글자색)와 하이라이트된 발췌 본문을 하나의
    /// `AttributedString`으로 이어 붙인다. 책 전체 개요는 장 번호가 없어 "개요)"를 쓴다.
    private func outlineExcerptAttributedString(_ result: OutlineSearchResult) -> AttributedString {
        let prefixText = result.chapter.map { "\($0)장) " } ?? "개요) "
        var prefix = AttributedString(prefixText)
        prefix.font = .system(size: 15, weight: .semibold)
        // 접두어 색을 테마 글자색으로 명시하는 이유는 `versePrefixAttributedString`과 같다.
        prefix.foregroundColor = settings.bibleTextColor ?? .primary
        var body = highlightedAttributedString(result.bodyExcerpt ?? "", keywords: result.highlightKeywords)
        body.font = .system(size: 15)
        body.foregroundColor = settings.bibleTextColor?.opacity(0.75) ?? .secondary
        return prefix + body
    }

    // MARK: - 메모(VersePhraseNote)

    private func phraseNoteRow(_ result: PhraseNoteSearchResult) -> some View {
        groupCardBorder {
            bibleVerseRow(BibleVerseDestination(
                bookId: result.note.bookId, chapter: result.note.chapter, verse: nil
            )) {
                compactItemLabel(
                    icon: "note.text", iconColor: settings.bibleTextColor ?? .primary,
                    title: phraseNoteTitle(result.note),
                    isReferenceMatch: result.isReferenceMatch,
                    matchedWordCount: result.bodyExcerpt != nil ? result.matchedWordCount : nil,
                    excerptText: result.bodyExcerpt ?? result.note.noteText, excerptKeywords: result.highlightKeywords
                )
            }
        }
    }

    private func phraseNoteTitle(_ note: VersePhraseNote) -> String {
        let bookName = BooksProvider.shared.book(id: note.bookId)?.nameKo ?? "성경"
        return "\(bookName) \(note.chapter):\(note.verse) 메모"
    }

    // MARK: - 개인 묵상(UserMemo)

    private func memoRow(_ result: MemoSearchResult) -> some View {
        groupCardBorder {
            NavigationLink {
                MemoDetailView(memo: result.memo)
            } label: {
                compactItemLabel(
                    icon: "heart.text.square.fill", iconColor: settings.bibleTextColor ?? .primary,
                    title: memoTitle(result.memo),
                    tagNames: result.matchedTagNames,
                    matchedWordCount: result.bodyExcerpt != nil ? result.matchedWordCount : nil,
                    excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
                )
            }
        }
    }

    private func memoTitle(_ memo: UserMemo) -> String {
        let bookName = BooksProvider.shared.book(id: memo.bookId)?.nameKo ?? "성경"
        return "\(bookName) \(memo.chapter)장 메모"
    }

    // MARK: - 말씀 요약(VerseSummary)

    private func summaryRow(_ result: SummarySearchResult) -> some View {
        groupCardBorder {
            NavigationLink {
                // `.standalone` 헤더가 아이폰 가로폭을 넘겨 잘리므로 `WordNoteHomeView`와
                // 같이 `.wordNoteList`를 쓴다.
                WordSummaryEditorView(summary: result.summary, presentationContext: .wordNoteList)
            } label: {
                compactItemLabel(
                    icon: "text.quote", iconColor: settings.bibleTextColor ?? .primary,
                    title: summaryTitle(result.summary),
                    tagNames: result.matchedTagNames,
                    matchedWordCount: result.bodyExcerpt != nil ? result.matchedWordCount : nil,
                    excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
                )
            }
        }
    }

    private func summaryTitle(_ summary: VerseSummary) -> String {
        let bookName = BooksProvider.shared.book(id: summary.bookId)?.nameKo ?? "성경"
        return "\(bookName) \(summary.chapter)장 말씀 요약"
    }

    // MARK: - 연구문서(SourceDocument)

    /// `DocumentSearchRequest.searchText`(단수 String)에 넘길 검색어. 결과별
    /// `highlightKeywords`는 복수라 그대로 넣을 수 없어 사용자가 입력한 검색창
    /// 문자열(`viewModel.query`)을 쓴다.
    private var documentSearchText: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func documentRow(_ result: DocumentSearchResult) -> some View {
        // 아이폰은 다중 씬을 지원하지 않아 `openWindow`가 런타임 에러를 내므로
        // (`isPhoneIdiom` 참고) 이 화면의 NavigationStack 안으로 직접 이동한다.
        // 두 분기 모두 `groupCardBorder`로 감싼다.
        if isPhoneIdiom {
            groupCardBorder {
                NavigationLink {
                    DocumentSearchWindowContent(
                        request: DocumentSearchRequest(documentID: result.document.persistentModelID, searchText: documentSearchText)
                    )
                } label: {
                    compactItemLabel(
                        icon: "doc.text.fill", iconColor: settings.bibleTextColor ?? .primary,
                        title: documentTitle(result),
                        tagNames: result.matchedTagNames,
                        matchedWordCount: result.bodyExcerpt != nil ? result.matchedWordCount : nil,
                        excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
                    )
                }
            }
        } else {
            groupCardBorder {
                Button {
                    openWindow(
                        id: "document-search",
                        value: DocumentSearchRequest(documentID: result.document.persistentModelID, searchText: documentSearchText)
                    )
                } label: {
                    compactItemLabel(
                        icon: "doc.text.fill", iconColor: settings.bibleTextColor ?? .primary,
                        title: documentTitle(result),
                        tagNames: result.matchedTagNames,
                        matchedWordCount: result.bodyExcerpt != nil ? result.matchedWordCount : nil,
                        excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
                    )
                }
                // 새 창을 여는 Button이 List 안에서 NavigationLink 행과 같은 텍스트 색이
                // 되도록 `.plain`을 쓴다(기본 버튼 스타일은 강조색 틴트를 입힌다).
                .buttonStyle(.plain)
            }
        }
    }

    private func documentTitle(_ result: DocumentSearchResult) -> String {
        if let page = result.pageNumber {
            return "\(result.document.originalFilename) p.\(page + 1)"
        }
        return result.document.originalFilename
    }

    // MARK: - 내 설교(Sermon)

    /// 내 설교 결과 행. `documentRow`와 같은 분기 구조다: 아이폰은 `SermonViewerView`를
    /// NavigationStack 안으로 밀어 넣고(`isPhoneIdiom` 참고), 그 외는 `sermon-viewer` 창을 연다.
    @ViewBuilder
    private func sermonRow(_ result: SermonSearchResult) -> some View {
        if isPhoneIdiom {
            groupCardBorder {
                NavigationLink {
                    SermonViewerView(subject: .sermon(result.sermon))
                } label: {
                    compactItemLabel(
                        icon: "mic.fill", iconColor: settings.bibleTextColor ?? .primary,
                        title: sermonTitle(result),
                        tagNames: result.matchedTagNames,
                        matchedWordCount: result.bodyExcerpt != nil ? result.matchedWordCount : nil,
                        excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
                    )
                }
            }
        } else {
            groupCardBorder {
                Button {
                    openWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(result.sermon))
                } label: {
                    compactItemLabel(
                        icon: "mic.fill", iconColor: settings.bibleTextColor ?? .primary,
                        title: sermonTitle(result),
                        tagNames: result.matchedTagNames,
                        matchedWordCount: result.bodyExcerpt != nil ? result.matchedWordCount : nil,
                        excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
                    )
                }
                // documentRow와 같은 이유 — 새 창을 여는 Button이 List 안에서
                // 기존 NavigationLink 행과 같은 텍스트 색으로 보이도록 `.plain`.
                .buttonStyle(.plain)
            }
        }
    }

    private func sermonTitle(_ result: SermonSearchResult) -> String {
        result.sermon.title.isEmpty ? "제목 없음" : result.sermon.title
    }

    // MARK: - 형광펜 강조 / 태그 뱃지 (DocumentsHomeView.DocumentRowView와 같은 원리)

    /// `DocumentsHomeView.DocumentRowView.highlightedText`와 완전히 같은 구현 —
    /// 원본 문자열 위에서 바로 대소문자 무시 검색해 겹치는 범위에 배경색을 입힌다
    /// (lowercased()로 만든 별도 문자열의 인덱스를 재사용하지 않는 이유도 같다).
    private func highlightedText(_ text: String, keywords: [String]) -> Text {
        Text(highlightedAttributedString(text, keywords: keywords))
    }

    /// `highlightedText`의 하이라이트 계산을 `AttributedString`으로 반환하도록 분리한 것.
    /// 접두어와 이어 붙여 단일 `Text(_:)`로 그리려면 `Text`가 아닌 `AttributedString`이
    /// 필요하다(`Text + Text`는 deprecated).
    private func highlightedAttributedString(_ text: String, keywords: [String]) -> AttributedString {
        let trimmedKeywords = keywords.filter { !$0.isEmpty }
        var attributed = AttributedString(text)
        guard !trimmedKeywords.isEmpty else { return attributed }

        for keyword in trimmedKeywords {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: keyword, options: [.caseInsensitive], range: searchRange) {
                if let attrRange = Range(found, in: attributed) {
                    attributed[attrRange].backgroundColor = .yellow.opacity(0.5)
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return attributed
    }

    /// 캡슐 배지. `systemImage`를 주면 아이콘이 앞에 붙는다("참조 일치"는 체크마크, 태그는 태그 아이콘).
    private func badge(_ text: String, color: Color, systemImage: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
            }
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }

}
