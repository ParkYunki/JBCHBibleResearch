//
//  OutlineTreeView.swift
//  JBCHBibleResearch
//
//  [2026-08-14 신설, `OutlineBookListView.swift`/`OutlineChapterListView.swift`
//  대체] 사용자 요청 — "개요: 폴더 구조로 표현할 수 있도록 — 구약 > 창세기 >
//  1장,2장 ... / 신약 > 마태복음 > 마가복음. 한번 펼친 폴더 내용은 다음에
//  개요를 눌렀을 때에도 그 상태가 유지 되도록. 성경 자체를 눌러 성경개요와
//  그 성경의 모든 장을 일괄로 편집할 수 있게 하거나 그 성경의 특정 장을
//  클릭하여 그 특정장만 수정할 수 있게 하도록. 리치 에디터화면은 폴더 구조
//  오른쪽에 나오도록."
//
//  이전 버전(66권 평면 리스트 → 장 리스트 → 편집기, 3단 push 내비게이션)을
//  완전히 대체한다. 구조:
//  - 왼쪽(또는 iPhone은 전체 화면): 구약/신약 → 책 → 장 3단 트리. `List`를
//    직접 만들지 않고, 지금 펼쳐진 상태에 따라 "보여야 할 행"을 매번
//    평면 배열로 계산해(`rows`) 그린다 — SwiftUI `DisclosureGroup`의 기본
//    "행 전체를 누르면 펼침/접힘" 동작은 "책 이름을 누르면 그 책을 선택(=
//    오른쪽에 일괄편집기 열기)"이라는 요구와 정확히 충돌해서(둘 다 "행 탭"을
//    쓰려고 하면 하나를 고를 수밖에 없다), 화살표 아이콘 전용 버튼과 이름
//    텍스트 전용 탭 영역을 분리해 직접 만들었다.
//  - 펼침 상태(구약/신약, 책)는 `UserSettingsStore.outlineExpandedTestaments`/
//    `outlineExpandedBookIds`(UserDefaults)에 저장 — 앱을 껐다 켜도 유지된다.
//  - 오른쪽(또는 iPhone은 push 이동): `OutlineBookBulkEditView` — 책을
//    선택하면 `focusedChapter: nil`(전부 접힌 채로 시작, "모두 펼치기"로 일괄
//    가능), 장을 선택하면 `focusedChapter: 그 장`(그 장만 펼쳐진 채로 시작)
//    을 넘긴다 — 같은 화면 하나가 "일괄 편집"과 "장 하나만 수정" 두 요구를
//    함께 만족한다.
//
//  ⚠️ [범위 축소, 명확히 플래그] 옛 `OutlineView`가 갖고 있던 AI 초안 제안
//  (9.9절, `ChapterOutlineDraftService`)과 `BookOutline` 충돌 배너(다른 기기가
//  같은 책 개요를 오프라인에서 따로 만든 경우)는 이번 트리 재설계에 포함하지
//  않았다 — 이번 요청 범위(폴더 트리 + 일괄/개별 편집)에 없었고, 장마다
//  접고 펼 수 있는 아코디언 구조에 두 기능을 자연스럽게 녹이려면 추가 설계가
//  필요해 별도 요청 없이 넣지 않기로 했다. 필요해지면 이후 라운드에 추가하면
//  된다.
//

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
///
/// ⚠️ [2026-08-15 재설계] 사용자 UX 피드백 — "빈 여백도 많고, 특정 장에 개요를
/// 입력하기 위해서는 클릭을 여러번 클릭해야 함." 기존엔 장마다 `.chapter(Book,
/// Int)` 행을 하나씩 만들어 시편(150장) 같은 책은 스크롤이 아주 길었다. 지금은
/// 펼쳐진 책 하나당 "장 칩 그리드" 행 하나(`.chapterGrid`)만 만들고, 그 안에서
/// `LazyVGrid`로 장 번호를 작게 줄바꿈해 늘어놓는다 — 같은 화면 안에 훨씬 많은
/// 장이 한 번에 들어와 스크롤이 크게 줄어든다.
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

    var body: some View {
        if isPhone {
            OutlineTreeList(isPhoneLayout: true, selection: nil)
        } else {
            OutlineTreeSplitContent()
        }
    }
}

private struct OutlineTreeSplitContent: View {
    @State private var selection: OutlineTreeSelection?

    var body: some View {
        HStack(spacing: 0) {
            // [2026-08-15 4차 변경] 사용자 요청 — "성경 리스트 영역(왼쪽 사이드바와
            // 오른쪽 리치텍스트 에디터 영역 사이 중간영역) 사이즈 크기를 375px
            // 정도로 할 것." min/max를 375 근처로 좁혀 사용자가 스플릿 경계를
            // 드래그해도 크게 벗어나지 않게 했다(완전 고정폭 대신 약간의 여유를
            // 둔 이유 — "375px 정도로"라는 표현이 정확히 고정값을 요구한 것은
            // 아니라고 판단).
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
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // [2026-08-15 추가] `ChapterRelatedContentPanel`의 "개요 화면 열기" 버튼
        // — `OutlineNavigationRequest.swift` 상단 주석 참고. 요청받은 책/장을
        // 그대로 선택해 오른쪽에 `OutlineBookBulkEditView`(기본 편집 가능)가
        // 바로 뜨게 하고, 왼쪽 트리도 그 구약/신약과 책을 펼쳐 시각적으로
        // 맞춰 둔다(펼침 상태는 `UserSettingsStore`에 영구 저장되는 값이라,
        // `OutlineTreeList.isTestamentExpanded`/`isBookExpanded`가 자동으로
        // 다시 읽어 반영한다).
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
        // [2026-08-21 추가] 사용자 요청("아이패드 수정사항") — "개요 리스트에
        // 항목 탭시 - 왼쪽 사이드바 자동 숨김기능." `WordNoteHomeView.
        // WordNoteSplitContent`(같은 날 추가)와 완전히 같은 계약 —
        // `SidebarVisibilityRequest`(Services/SidebarVisibilityRequest.swift)로
        // 첫 선택 시 hide, 선택이 풀리거나 화면을 떠나면 restore. 이 화면의
        // `OutlineTreeSelection`은 이미 `Hashable`(= Equatable)이라
        // `WordNoteItem`과 달리 `.id` 우회 없이 값 자체로 비교한다. macOS는
        // 이 항목에 "(맥OS, iOS 공통)" 표기가 없어(성경 조회 세로보기 등 다른
        // 아이패드 전용 항목들과 같은 취급) iOS로만 제한한다.
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

    @State private var settings = UserSettingsStore.shared
    @State private var searchQuery = ""

    /// [2026-08-15 추가] 사용자 UX 피드백 — "빈 여백도 많고 ... 책 이름을 검색해
    /// 바로 찾을 수 있게." 책/장 콘텐츠(RTF 원문)는 절대 읽지 않고, "이 책/장에
    /// 뭔가 쓰여 있는가"만 알면 되므로 `contentText`(RTF에서 뽑아둔 평문 캐시,
    /// `RichTextEditor.swift` 참고)의 공백 제거 후 빈 문자열 여부만 본다.
    /// `@Query`는 SwiftData 변경을 자동 구독하므로 에디터에서 방금 글을 쓰고
    /// 돌아와도 점 표시가 바로 갱신된다.
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
        VStack(spacing: 0) {
            searchField
            Divider()
            List(rows) { row in
                rowView(row)
            }
            .listStyle(.plain)
        }
        .navigationTitle("개요")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("책 이름 검색", text: $searchQuery)
                .textFieldStyle(.plain)
                // [2026-08-15 4차 변경] 사용자 요청 — "검색 창 placeholder 텍스트는
                // 시스템 기본폰트, 일반 크기로." `RootView`가 `.appDefaultFont()`
                // (커스텀 Paperlogy 폰트)를 최상단 환경에 걸어 자식 뷰가 전부
                // 물려받으므로, 명시적으로 `.font(.body)`를 줘서 이 필드(placeholder
                // 포함 — SwiftUI에서 placeholder는 입력 텍스트와 같은 폰트를 쓴다)만
                // 시스템 기본 폰트로 되돌린다.
                .font(.body)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func rowView(_ row: OutlineTreeRow) -> some View {
        switch row {
        case .testamentHeader(let testament):
            HStack(spacing: 6) {
                Image(systemName: isTestamentExpanded(testament) ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .frame(width: 14)
                Text(testament == .old ? "구약" : "신약")
                    .font(.headline)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleTestament(testament) }
            // [2026-08-15 4차 변경] 사용자 요청 — "리스트의 항목간 간격을 조금 더
            // 여유롭게 둘것." 세 종류 행(구약/신약, 책, 장 칩 그리드) 모두 상하
            // 여백을 늘려 전체적으로 더 널널하게 보이도록 했다.
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
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }

                Text("\(book.chapterCount)장")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 16)
            .padding(.vertical, 6)

        case .chapterGrid(let book):
            chapterChipGrid(book)
                .padding(.leading, 34)
                .padding(.vertical, 8)
        }
    }

    /// [2026-08-15 신설] 장 하나당 행 하나이던 목록을 대체 — 작은 칩을 폭에 맞춰
    /// 줄바꿈해 늘어놓는다. `Layout` 프로토콜로 직접 흐름 레이아웃을 만드는 대신
    /// `LazyVGrid(.adaptive(...))`를 쓴 이유: 칩 크기가 고정(30pt)이라 adaptive
    /// 컬럼이 흐름 레이아웃과 시각적으로 동일하게 줄바꿈되면서, 커스텀 `Layout`
    /// 구현 없이 훨씬 적은 코드로 같은 결과를 낸다.
    private func chapterChipGrid(_ book: Book) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 32, maximum: 32), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(1...max(book.chapterCount, 1), id: \.self) { chapter in
                chapterChip(book: book, chapter: chapter)
            }
        }
    }

    @ViewBuilder
    private func chapterChip(book: Book, chapter: Int) -> some View {
        let hasContent = chaptersWithContent.contains(book.bookId * 1000 + chapter)
        if isPhoneLayout {
            NavigationLink {
                OutlineBookBulkEditView(book: book, focusedChapter: chapter)
            } label: {
                chapterChipLabel(chapter: chapter, hasContent: hasContent)
            }
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
            .foregroundStyle(hasContent ? Color.accentColor : Color.secondary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hasContent ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasContent ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private func bookLabel(_ book: Book) -> some View {
        if isPhoneLayout {
            NavigationLink {
                OutlineBookBulkEditView(book: book)
            } label: {
                Text(book.nameKo).font(.body)
            }
        } else {
            Text(book.nameKo)
                .font(.body)
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
