//
//  OutlineTreeView.swift
//  JBCHBibleResearch
//
//  폴더 구조 개요 화면. 구약/신약 → 책 → 장 3단 트리(왼쪽, iPhone은 전체 화면)와
//  편집기(`OutlineBookBulkEditView`, 오른쪽 또는 iPhone push)로 구성된다.
//  - `List`를 직접 만들지 않고 펼침 상태에 따라 보여야 할 행을 평면 배열(`rows`)로 계산해 그린다.
//    `DisclosureGroup`은 행 전체 탭이 펼침/접힘에 쓰여 "책 이름 탭 = 책 선택"과 충돌하므로
//    화살표 버튼과 이름 탭 영역을 분리했다.
//  - 펼침 상태는 `UserSettingsStore`(UserDefaults)에 저장돼 앱을 다시 켜도 유지된다.
//  - 책 선택은 `focusedChapter: nil`(일괄 편집), 장 선택은 `focusedChapter: 그 장`을 넘긴다.
//  ⚠️ 옛 `OutlineView`의 AI 초안 제안과 `BookOutline` 충돌 배너는 이 화면에 포함되어 있지 않다.

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

/// 트리에서 지금 선택된 대상 — 책 전체(일괄 편집) 또는 특정 장(그 장만 포커스).
enum OutlineTreeSelection: Hashable {
    case book(Int)
    case chapter(Int, Int)
}

/// 트리를 평면 배열로 펼쳐 그리기 위한 행 하나.
/// 펼쳐진 책 하나당 장 번호 칩 그리드 행 하나(`.chapterGrid`)만 만들어, 장이 많은 책도 스크롤이 길어지지 않게 한다.
private enum OutlineTreeRow: Identifiable {
    case testamentHeader(Book.Testament)
    case book(Book)
    case chapterGrid(Book)

    var id: String {
        switch self {
        case .testamentHeader(let testament): return "testament-\(testament.rawValue)"
        case .book(let book): return "book-\(book.bookId)"
        case .chapterGrid(let book): return "chapters-\(book.bookId)"
        }
    }
}

struct OutlineTreeView: View {
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// 아이폰 전용 내비게이션 경로. 장 칩 여러 개가 `List` 행 하나 안에 있으면 `NavigationLink`가
    /// 탭된 칩을 구분하지 못해 잘못된 장으로 이동하므로, 칩을 `Button`으로 두고 이 배열에 직접 append한다.
    /// 아이패드/맥은 `selection`으로 오른쪽 패널을 바꾸므로 사용하지 않는다.
    @State private var path: [OutlineTreeSelection] = []

    /// `.fullScreenCover`로 띄울 때 전달하는 닫기 동작(스와이프로 닫을 수 없음).
    /// 값이 있을 때만 아이폰 분기 툴바에 닫기 버튼을 추가한다.
    var onRequestDismiss: (() -> Void)? = nil

    var body: some View {
        if isPhone {
            NavigationStack(path: $path) {
                OutlineTreeList(isPhoneLayout: true, selection: nil, path: $path)
                    .toolbar {
                        if let onRequestDismiss {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("닫기", action: onRequestDismiss)
                            }
                        }
                    }
            }
            // 통합 검색 등에서 요청된 책/장 선택을 아이폰 분기에서도 반영한다.
            // 연속 요청 시 뒤로가기 스택이 엉키지 않도록 append 대신 `path`를 교체한다.
            .onChange(of: OutlineNavigationRequest.shared.requestedSelection) { _, newValue in
                guard let newValue else { return }
                path = [newValue]
                let bookId: Int
                switch newValue {
                case .book(let id): bookId = id
                case .chapter(let id, _): bookId = id
                }
                if let book = BooksProvider.shared.book(id: bookId) {
                    var expandedTestaments = Set(UserSettingsStore.shared.outlineExpandedTestaments)
                    expandedTestaments.insert(book.testament.rawValue)
                    UserSettingsStore.shared.outlineExpandedTestaments = Array(expandedTestaments)

                    var expandedBooks = Set(UserSettingsStore.shared.outlineExpandedBookIds)
                    expandedBooks.insert(bookId)
                    UserSettingsStore.shared.outlineExpandedBookIds = Array(expandedBooks)
                }
                OutlineNavigationRequest.shared.clear()
            }
        } else {
            OutlineTreeSplitContent()
        }
    }
}

private struct OutlineTreeSplitContent: View {
    @State private var selection: OutlineTreeSelection?
    /// 오른쪽 빈 상태 패널의 테마 배경색용.
    @State private var settings = UserSettingsStore.shared

    var body: some View {
        HStack(spacing: 0) {
            // 목록 영역 폭을 375pt 근처로 좁혀, 스플릿 경계를 드래그해도 크게 벗어나지 않게 한다.
            OutlineTreeList(isPhoneLayout: false, selection: $selection)
                .frame(minWidth: 360, idealWidth: 375, maxWidth: 390)

            Divider()

            Group {
                if let selection {
                    destinationView(for: selection)
                        .id(selection)
                } else {
                    VStack {
                        Spacer()
                        Text("책이나 장을 선택하세요")
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 왼쪽 트리와 같은 테마 배경을 적용한다.
                    .background(settings.bibleBackgroundColor ?? Color.clear)
                }
            }
        }
        // `ChapterRelatedContentPanel`의 "개요 화면 열기" 요청을 받아 해당 책/장을 선택하고,
        // 왼쪽 트리에서도 그 구약/신약과 책을 펼쳐 둔다.
        .onChange(of: OutlineNavigationRequest.shared.requestedSelection) { _, newValue in
            guard let newValue else { return }
            selection = newValue
            let bookId: Int
            switch newValue {
            case .book(let id): bookId = id
            case .chapter(let id, _): bookId = id
            }
            if let book = BooksProvider.shared.book(id: bookId) {
                var expandedTestaments = Set(UserSettingsStore.shared.outlineExpandedTestaments)
                expandedTestaments.insert(book.testament.rawValue)
                UserSettingsStore.shared.outlineExpandedTestaments = Array(expandedTestaments)

                var expandedBooks = Set(UserSettingsStore.shared.outlineExpandedBookIds)
                expandedBooks.insert(bookId)
                UserSettingsStore.shared.outlineExpandedBookIds = Array(expandedBooks)
            }
            OutlineNavigationRequest.shared.clear()
        }
        // iOS: 첫 선택 시 왼쪽 사이드바를 숨기고, 선택이 풀리거나 화면을 떠나면 복원한다(`SidebarVisibilityRequest`).
        #if os(iOS)
        .onChange(of: selection) { oldValue, newValue in
            if newValue != nil && oldValue == nil {
                SidebarVisibilityRequest.shared.requestHide()
            } else if newValue == nil && oldValue != nil {
                SidebarVisibilityRequest.shared.requestRestore()
            }
        }
        .onDisappear {
            guard selection != nil else { return }
            SidebarVisibilityRequest.shared.requestRestore()
        }
        #endif
    }
}

@ViewBuilder
private func destinationView(for selection: OutlineTreeSelection) -> some View {
    switch selection {
    case .book(let bookId):
        if let book = BooksProvider.shared.book(id: bookId) {
            OutlineBookBulkEditView(book: book)
        }
    case .chapter(let bookId, let chapter):
        if let book = BooksProvider.shared.book(id: bookId) {
            OutlineBookBulkEditView(book: book, focusedChapter: chapter)
        }
    }
}

private struct OutlineTreeList: View {
    let isPhoneLayout: Bool
    var selection: Binding<OutlineTreeSelection?>?
    /// 아이폰 전용. 장 칩 탭 시 이 배열에 append해 이동한다(`OutlineTreeView.path` 참고). 아이패드/맥에서는 nil.
    var path: Binding<[OutlineTreeSelection]>? = nil

    @State private var settings = UserSettingsStore.shared
    @State private var searchQuery = ""

    /// 책/장에 내용이 있는지만 알면 되므로 RTF 원문 대신 평문 캐시 `contentText`의 공백 제거 후 빈 여부만 본다.
    /// `@Query`가 변경을 구독하므로 에디터에서 돌아오면 점 표시가 바로 갱신된다.
    @Query private var bookOutlines: [BookOutline]
    @Query private var chapterSummaries: [ChapterSummary]

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchingBooks: [Book] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return BooksProvider.shared.books.filter { book in
            book.nameKo.localizedCaseInsensitiveContains(query)
                || book.nameOriginal.localizedCaseInsensitiveContains(query)
                || book.abbreviation.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var oldTestamentBooks: [Book] {
        BooksProvider.shared.books.filter { $0.testament == .old }
    }
    private var newTestamentBooks: [Book] {
        BooksProvider.shared.books.filter { $0.testament == .new }
    }

    /// 책 개요 또는 그 책 어느 장이든 내용이 있으면 그 책의 `bookId`가 들어간다.
    /// 책 행 옆 점 표시(제안 화면의 "룻기" 점) 용도.
    private var booksWithContent: Set<Int> {
        var ids = Set(bookOutlines.compactMap { hasContent($0.contentText) ? $0.bookId : nil })
        ids.formUnion(chapterSummaries.compactMap { hasContent($0.contentText) ? $0.bookId : nil })
        return ids
    }

    /// 장 칩 색칠 용도 — `bookId * 1000 + chapter`로 인코딩(66권 중 최대 장 수인
    /// 시편도 150장이라 1000 미만이라 충돌 없음).
    private var chaptersWithContent: Set<Int> {
        Set(chapterSummaries.compactMap { hasContent($0.contentText) ? $0.bookId * 1000 + $0.chapter : nil })
    }

    private func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rows: [OutlineTreeRow] {
        if isSearching {
            var result: [OutlineTreeRow] = []
            for book in matchingBooks {
                result.append(.book(book))
                result.append(.chapterGrid(book))
            }
            return result
        }
        var result: [OutlineTreeRow] = []
        for testament in [Book.Testament.old, .new] {
            result.append(.testamentHeader(testament))
            guard isTestamentExpanded(testament) else { continue }
            let books = testament == .old ? oldTestamentBooks : newTestamentBooks
            for book in books {
                result.append(.book(book))
                guard isBookExpanded(book.bookId) else { continue }
                result.append(.chapterGrid(book))
            }
        }
        return result
    }

    var body: some View {
        // 계산 프로퍼티를 행/칩마다 접근하면 `bookOutlines`/`chapterSummaries`를 그만큼 반복 스캔하므로,
        // 렌더당 한 번만 계산해 아래로 넘긴다.
        let booksWithContent = self.booksWithContent
        let chaptersWithContent = self.chaptersWithContent
        VStack(spacing: 0) {
            searchField
            Divider()
            List(rows) { row in
                rowView(row, booksWithContent: booksWithContent, chaptersWithContent: chaptersWithContent)
                    // `.scrollContentBackground(.hidden)`은 컨테이너 배경만 바꾸므로, 행 셀의 기본 배경은
                    // `.listRowBackground(Color.clear)`로 지워야 List 배경(테마색)이 비친다.
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            // 다른 화면과 같은 테마 배경/글자색을 적용한다. 아이폰과 아이패드/맥이 이 뷰를 공유하므로 양쪽에 반영된다.
            .scrollContentBackground(.hidden)
            .background(settings.bibleBackgroundColor ?? Color.clear)
            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
            .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.3))
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .navigationTitle("개요")
        // 다른 화면과 같이 `.principal` 툴바 타이틀(성곡 세리프체 + 테마 글자색)을 쓴다.
        // `.inline`을 함께 지정하지 않으면 시스템의 큰 왼쪽 정렬 타이틀이 별도 줄로 겹쳐 보인다.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .principal) {
                Text("개요")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            #endif
        }
        // `path`에 담긴 값과 `bookLabel`의 `NavigationLink(value:)`가 쓰는 목적지.
        // 아이패드/맥은 링크를 만들지 않으므로 이 등록이 사용되지 않는다.
        .navigationDestination(for: OutlineTreeSelection.self) { selection in
            destinationView(for: selection)
        }
    }

    /// 책 이름 검색 입력란. 연구문서 검색란(`DocumentsHomeView.searchAndFilterBar`)과 같은 테마색 스타일.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            TextField(
                "책 이름 검색",
                text: $searchQuery,
                // `.appDefaultFont()`가 환경에서 상속되므로, placeholder를 포함한 이 필드만
                // `.font(.body)`로 시스템 기본 폰트로 되돌린다.
                prompt: Text("책 이름 검색")
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
            )
                .textFieldStyle(.plain)
                .font(.body)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(settings.bibleTextColor?.opacity(0.2) ?? Color.secondary.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func rowView(_ row: OutlineTreeRow, booksWithContent: Set<Int>, chaptersWithContent: Set<Int>) -> some View {
        switch row {
        case .testamentHeader(let testament):
            HStack(spacing: 6) {
                Image(systemName: isTestamentExpanded(testament) ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .frame(width: 14)
                // 성곡 세리프체는 Regular뿐이라 `.fontWeight(.semibold)`로 합성 볼드를 주고,
                // Dynamic Type 배율 유지를 위해 `relativeTo: .headline`을 쓴다.
                Text(testament == .old ? "구약" : "신약")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .headline))
                    .fontWeight(.semibold)
                Spacer()
                // 해당 성경의 책 권수 배지.
                Text("\(testament == .old ? oldTestamentBooks.count : newTestamentBooks.count)\u{AD8C}")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(JBCHCategoryPalette.shelfSlate, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleTestament(testament) }
            .padding(.vertical, 8)

        case .book(let book):
            HStack(spacing: 6) {
                Button {
                    toggleBook(book.bookId)
                } label: {
                    Image(systemName: (isSearching || isBookExpanded(book.bookId)) ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .disabled(isSearching)

                bookLabel(book)

                Spacer()

                if booksWithContent.contains(book.bookId) {
                    Circle()
                        .fill(Color("AccentColor"))
                        .frame(width: 6, height: 6)
                }

                Text("\(book.chapterCount)장")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 16)
            .padding(.vertical, 6)

        case .chapterGrid(let book):
            chapterChipGrid(book, chaptersWithContent: chaptersWithContent)
                .padding(.leading, 34)
                .padding(.vertical, 8)
        }
    }

    /// 장 칩을 폭에 맞춰 줄바꿈해 늘어놓는다. 칩 크기가 고정(30pt)이라 커스텀 `Layout` 없이 `LazyVGrid(.adaptive)`로 충분하다.
    private func chapterChipGrid(_ book: Book, chaptersWithContent: Set<Int>) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 32, maximum: 32), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(1...max(book.chapterCount, 1), id: \.self) { chapter in
                chapterChip(book: book, chapter: chapter, chaptersWithContent: chaptersWithContent)
            }
        }
    }

    @ViewBuilder
    private func chapterChip(book: Book, chapter: Int, chaptersWithContent: Set<Int>) -> some View {
        let hasContent = chaptersWithContent.contains(book.bookId * 1000 + chapter)
        if isPhoneLayout {
            // `NavigationLink` 대신 `Button`을 쓴다. 어느 칩이 눌렸는지는 클로저가 캡처한 값으로 결정되며,
            // 이동은 `OutlineTreeView.path`에 직접 append해 처리한다.
            Button {
                path?.wrappedValue.append(.chapter(book.bookId, chapter))
            } label: {
                chapterChipLabel(chapter: chapter, hasContent: hasContent)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selection?.wrappedValue = .chapter(book.bookId, chapter)
            } label: {
                chapterChipLabel(chapter: chapter, hasContent: hasContent)
            }
            .buttonStyle(.plain)
        }
    }

    private func chapterChipLabel(chapter: Int, hasContent: Bool) -> some View {
        Text("\(chapter)")
            .font(.system(size: 12, weight: hasContent ? .semibold : .regular))
            .foregroundStyle(hasContent ? Color("AccentColor") : Color.secondary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hasContent ? Color("AccentColor").opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasContent ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private func bookLabel(_ book: Book) -> some View {
        if isPhoneLayout {
            // 이 행도 같은 `List` 행 안에 펼침 토글 버튼과 함께 있어 값 기반 `NavigationLink(value:)`를 쓴다.
            // 성곡 세리프체 17pt(`.body`)는 Regular라 굵기 보정이 필요 없다.
            NavigationLink(value: OutlineTreeSelection.book(book.bookId)) {
                Text(book.nameKo)
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .body))
            }
        } else {
            Text(book.nameKo)
                .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .body))
                .contentShape(Rectangle())
                .onTapGesture { selection?.wrappedValue = .book(book.bookId) }
        }
    }

    // MARK: - 펼침 상태 (영구 저장)

    private func isTestamentExpanded(_ testament: Book.Testament) -> Bool {
        settings.outlineExpandedTestaments.contains(testament.rawValue)
    }

    private func toggleTestament(_ testament: Book.Testament) {
        var set = Set(settings.outlineExpandedTestaments)
        if set.contains(testament.rawValue) {
            set.remove(testament.rawValue)
        } else {
            set.insert(testament.rawValue)
        }
        settings.outlineExpandedTestaments = Array(set)
    }

    private func isBookExpanded(_ bookId: Int) -> Bool {
        settings.outlineExpandedBookIds.contains(bookId)
    }

    private func toggleBook(_ bookId: Int) {
        var set = Set(settings.outlineExpandedBookIds)
        if set.contains(bookId) {
            set.remove(bookId)
        } else {
            set.insert(bookId)
        }
        settings.outlineExpandedBookIds = Array(set)
    }
}
