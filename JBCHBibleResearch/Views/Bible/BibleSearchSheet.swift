//
//  BibleSearchSheet.swift
//  JBCHBibleResearch
//
//  좁은 폭(아이패드 Split View·Slide Over 등 compact 폭)에서 성경 조회 화면을 떠나지 않고 키워드 검색을 하는 아래 시트(2026-11-11, 안2).
//
//  배경: 통합 검색 입력창은 사이드바 안에만 있고, 좁은 폭에서는 사이드바가 본문 위에 겹쳐 쌓이는 스택이라 성경 화면에서 검색하려면
//  사이드바 화면으로 갔다가 돌아와야 했다. 이 시트는 `SearchViewModel`(통합 검색과 같은 검색 엔진)을 그대로 쓰되 결과를 간단한 목록으로만 보여 준다.
//
//  결과 탭 동작
//  - 성경 구절·개요(책/장 좌표가 있음): 시트를 닫고 이 성경 화면이 그 장·절로 이동한다(`BibleReadingViewModel.selectBook` + 절 강조).
//  - 말씀 노트·설교: 이 화면에 대응하는 위치가 없어 시트를 닫고 통합 검색 화면에서 같은 검색어로 연다(`SidebarSearchRequest` + `AppNavigationRequest`).
//
//  ⚠️ `searchImmediately()`는 검색 이력에 기록하고 `SearchResultsPopRequest`를 보낸다 — 통합 검색과 같은 동작이며,
//  성경 조회 화면이 detail 스택의 루트라 경로를 비우는 것은 영향이 없다. iOS 전용.
//

#if os(iOS)
import SwiftUI
import SwiftData
import BibleResearchModels

struct BibleSearchSheet: View {
    let viewModel: BibleReadingViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchModel: SearchViewModel?
    @State private var text = ""
    @State private var filter: Filter = .all
    @State private var hasSearched = false
    @FocusState private var isFieldFocused: Bool

    private var settings: UserSettingsStore { .shared }

    private static let minimumQueryLength = 2
    /// "전체" 칩에서 범주마다 보여 주는 최대 개수 / 범주 칩에서 보여 주는 최대 개수.
    private static let perCategoryLimitInAll = 6
    private static let limitInCategory = 50

    enum Filter: CaseIterable, Identifiable {
        case all, bible, outline, wordNote, sermon
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return String(localized: "전체")
            case .bible: return String(localized: "성경")
            case .outline: return String(localized: "개요")
            case .wordNote: return String(localized: "말씀 노트")
            case .sermon: return String(localized: "설교")
            }
        }
    }

    private enum RowAction {
        /// 이 성경 화면이 그 장(·절)로 이동한다.
        case jump(bookId: Int, chapter: Int, verse: Int?)
        /// 통합 검색 화면으로 넘긴다.
        case handoff
    }

    private struct Row: Identifiable {
        let id: String
        let category: Filter
        let label: String
        let text: String
        let keywords: [String]
        let usesSerif: Bool
        let action: RowAction
    }

    private var palette: BibleBarPalette {
        BibleBarPalette(environment: environment, colorScheme: colorScheme)
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSearch: Bool { trimmedText.count >= Self.minimumQueryLength }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            chipRow
            Divider()
            resultArea
        }
        .background(settings.bibleBackgroundColor ?? Color(uiColor: .systemBackground))
        .foregroundStyle(palette.text)
        .presentationBackground(settings.bibleBackgroundColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(BackgroundStyle()))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if searchModel == nil {
                searchModel = SearchViewModel(modelContext: modelContext)
            }
            // 시트가 올라오는 도중에 포커스를 주면 무시되는 경우가 있어 한 틱 미룬다.
            DispatchQueue.main.async { isFieldFocused = true }
        }
        .onDisappear { searchModel?.onDisappear() }
    }

    // MARK: - 입력줄

    private var searchHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.text.opacity(0.6))
                TextField(
                    "",
                    text: $text,
                    prompt: Text("성경 · 개요 · 메모 · 설교 검색 (2글자 이상)").foregroundStyle(palette.text.opacity(0.5))
                )
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($isFieldFocused)
                .onSubmit { runSearch() }
                .accessibilityLabel(String(localized: "검색어"))
                if !text.isEmpty {
                    Button {
                        text = ""
                        hasSearched = false
                        searchModel?.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.text.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "지우기"))
                }
            }
            .font(.body)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.text.opacity(BibleBarMetrics.fillOpacity)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.strong, lineWidth: 1))

            Button(String(localized: "닫기")) { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.strong)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        Text(item.title)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .foregroundStyle(filter == item ? palette.strongForeground : palette.text)
                            .background(Capsule().fill(filter == item ? palette.strong : Color.clear))
                            .overlay(Capsule().strokeBorder(filter == item ? palette.strong : palette.text.opacity(0.24), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - 결과

    @ViewBuilder
    private var resultArea: some View {
        if let searchModel, hasSearched {
            let rows = makeRows(from: searchModel)
            if searchModel.isSearching && rows.isEmpty {
                VStack { ProgressView().padding(.top, 40); Spacer(minLength: 0) }
                    .frame(maxWidth: .infinity)
            } else if rows.isEmpty {
                message(String(localized: "검색 결과가 없습니다."))
            } else {
                List {
                    ForEach(rows) { row in
                        Button { open(row) } label: { rowView(row) }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(palette.text.opacity(0.12))
                    }
                    Button {
                        handoffToIntegratedSearch()
                    } label: {
                        Label(String(localized: "통합 검색에서 모두 보기"), systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.strong)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        } else {
            message(String(localized: "검색어를 입력하고 검색을 누르세요."))
        }
    }

    private func message(_ string: String) -> some View {
        VStack {
            Text(string)
                .font(.subheadline)
                .foregroundStyle(palette.text.opacity(0.6))
                .padding(.top, 40)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.strong)
            Text(Self.highlighted(row.text, keywords: row.keywords, tint: palette.strong))
                .font(row.usesSerif ? Font.system(.subheadline, design: .serif) : Font.subheadline)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// 검색어(키워드) 위치마다 배경 강조를 칠한다. 대소문자는 구분하지 않는다.
    private static func highlighted(_ string: String, keywords: [String], tint: Color) -> AttributedString {
        var attributed = AttributedString(string)
        for keyword in keywords where !keyword.isEmpty {
            var cursor = attributed.startIndex
            while cursor < attributed.endIndex,
                  let range = attributed[cursor...].range(of: keyword, options: [.caseInsensitive]) {
                attributed[range].backgroundColor = tint.opacity(0.22)
                cursor = range.upperBound
            }
        }
        return attributed
    }

    // MARK: - 행 만들기

    private func makeRows(from model: SearchViewModel) -> [Row] {
        let inAll = filter == .all
        let limit = inAll ? Self.perCategoryLimitInAll : Self.limitInCategory
        var rows: [Row] = []

        if inAll || filter == .bible {
            // 같은 절이 번역본마다 따로 나올 수 있다 — 시트에서는 절당 한 줄만 보인다(첫 번째 = 검색이 가장 앞에 둔 번역본).
            var seen = Set<String>()
            var verseRows: [Row] = []
            for result in model.verseResults {
                let key = "\(result.bookId)-\(result.chapter)-\(result.verse)"
                guard seen.insert(key).inserted else { continue }
                let bookName = BooksProvider.shared.book(id: result.bookId)?.displayName ?? result.bookNameKo
                verseRows.append(Row(
                    id: "verse-\(result.id)",
                    category: .bible,
                    label: "\(String(localized: "성경")) · \(bookName) \(result.chapter):\(result.verse)",
                    text: result.content,
                    keywords: result.highlightKeywords,
                    usesSerif: true,
                    action: .jump(bookId: result.bookId, chapter: result.chapter, verse: result.verse)
                ))
                if verseRows.count >= limit { break }
            }
            rows += verseRows
        }

        if inAll || filter == .outline {
            for result in model.outlineResults.prefix(limit) {
                let bookName = BooksProvider.shared.book(id: result.bookId)?.displayName ?? ""
                let place = result.chapter.map { "\(bookName) \($0)" } ?? bookName
                rows.append(Row(
                    id: "outline-\(result.id)",
                    category: .outline,
                    label: "\(String(localized: "개요")) · \(place)",
                    text: result.bodyExcerpt ?? String(result.contentText.prefix(120)),
                    keywords: result.highlightKeywords,
                    usesSerif: false,
                    action: .jump(bookId: result.bookId, chapter: result.chapter ?? 1, verse: nil)
                ))
            }
        }

        if inAll || filter == .wordNote {
            var noteRows: [Row] = []
            for result in model.memoResults {
                noteRows.append(Row(
                    id: "memo-\(result.id)",
                    category: .wordNote,
                    label: "\(String(localized: "말씀 노트")) · \(String(localized: "개인 묵상"))",
                    text: result.bodyExcerpt ?? "",
                    keywords: result.highlightKeywords,
                    usesSerif: false,
                    action: .handoff
                ))
            }
            for result in model.summaryResults {
                noteRows.append(Row(
                    id: "summary-\(result.id)",
                    category: .wordNote,
                    label: "\(String(localized: "말씀 노트")) · \(String(localized: "말씀 요약"))",
                    text: result.bodyExcerpt ?? "",
                    keywords: result.highlightKeywords,
                    usesSerif: false,
                    action: .handoff
                ))
            }
            for result in model.phraseNoteResults {
                noteRows.append(Row(
                    id: "phrase-\(result.id)",
                    category: .wordNote,
                    label: "\(String(localized: "말씀 노트")) · \(String(localized: "메모"))",
                    text: result.bodyExcerpt ?? "",
                    keywords: result.highlightKeywords,
                    usesSerif: false,
                    action: .handoff
                ))
            }
            rows += noteRows.prefix(limit)
        }

        if inAll || filter == .sermon {
            for result in model.sermonResults.prefix(limit) {
                let title = result.sermon.title.isEmpty ? String(localized: "제목 없음") : result.sermon.title
                let excerpt = result.bodyExcerpt ?? ""
                rows.append(Row(
                    id: "sermon-\(result.id)",
                    category: .sermon,
                    label: "\(String(localized: "내 설교")) · \(title)",
                    text: excerpt,
                    keywords: result.highlightKeywords,
                    usesSerif: false,
                    action: .handoff
                ))
            }
        }
        return rows
    }

    // MARK: - 동작

    private func runSearch() {
        guard canSearch, let searchModel else { return }
        searchModel.query = trimmedText
        searchModel.searchImmediately()
        hasSearched = true
        isFieldFocused = false
    }

    private func open(_ row: Row) {
        switch row.action {
        case .jump(let bookId, let chapter, let verse):
            guard let book = BooksProvider.shared.book(id: bookId) else { return }
            viewModel.selectBook(book, chapter: chapter)
            if let verse { viewModel.highlightVerseTemporarily(verse) }
            dismiss()
        case .handoff:
            handoffToIntegratedSearch()
        }
    }

    /// 통합 검색 화면에서 같은 검색어로 연다(`SidebarNavigationView.submitSidebarSearch`와 같은 요청 쌍).
    private func handoffToIntegratedSearch() {
        let query = trimmedText
        guard query.count >= Self.minimumQueryLength else { return }
        SidebarSearchRequest.shared.request(query)
        AppNavigationRequest.shared.request(.search)
        dismiss()
    }
}
#endif
