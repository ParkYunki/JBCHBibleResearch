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

    /// [2026-08-27 신설] 사용자 재보고 — "장 버튼을 누르면 무조건 마지막
    /// 장으로 이동, 뒤로가기가 이전 화면이 아니라 이전 장으로 감." 8/26에
    /// "값 기반 `NavigationLink(value:)` + 화면당 단 하나의
    /// `.navigationDestination(for:)`"로 고쳤다고 기록돼 있었지만, 실제로는
    /// 그 조합으로도 문제가 재현됐다 — 근본 원인은 그게 아니라, 장 칩
    /// 여러 개가 `List`의 행(row) 하나(`LazyVGrid`) 안에 몰려 있는 구조
    /// 자체였다: `NavigationLink`가 몇 개든, 그게 암묵적(각자 알아서 push하는)
    /// 내비게이션 스택에 얹혀 있는 한, `List`/`NavigationStack`이 "한 행 안의
    /// 여러 링크 중 실제로 탭된 게 어느 것인지"를 안정적으로 구분하지
    /// 못했다. 해법은 그 자체를 없애는 것 — 칩을 `NavigationLink`가 아니라
    /// 평범한 `Button`으로 바꾸고(어느 클로저가 눌렸는지는 Swift 클로저
    /// 캡처만으로 100% 명확하다, `List`/링크 식별에 기댈 필요가 없다), 이동은
    /// `NavigationStack(path:)`에 명시적으로 바인딩된 배열에 값을 직접
    /// append하는 방식으로 프로그램적으로 처리한다. 이 `path`는 아이폰
    /// 분기 전용이다 — 아이패드/맥(`OutlineTreeSplitContent`)은 원래부터
    /// `NavigationLink`/`NavigationStack`을 전혀 안 쓰고 `@State selection`
    /// 하나로 오른쪽 패널을 직접 바꿔치기하는 완전히 다른 구조라 이 변경과
    /// 무관하다.
    @State private var path: [OutlineTreeSelection] = []

    /// [2026-08-27 신설, 사용자 결정 — "개요→더보기, 검색→탭바"] 아이폰
    /// 탭바에서 개요를 빼고 "더보기" 메뉴 안 `.fullScreenCover`로 옮기면서
    /// (`PlaceholderScreens.swift`/`PhoneTabView.swift` 참고) 생긴 매개변수다.
    /// `.fullScreenCover`는(`.sheet`와 달리) 아래로 스와이프해 닫을 수 없어
    /// 명시적 닫기 버튼이 필요한데, 기존 호출부(탭바에서 직접 쓰는 경우,
    /// 매개변수 없음)는 탭 전환만으로 나가면 되므로 닫기 버튼이 필요 없다 —
    /// 기본값 `nil`로 기존 동작을 그대로 유지하고, 이 값이 있을 때만 아이폰
    /// 분기의 `NavigationStack` 툴바에 닫기 버튼을 추가한다.
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
            // [2026-09-05 신설] 사용자 신고 — "개요 기능까지는 이동이 됨.
            // 사용자가 마태복음 3장 개요을 탭하면 마태복음 3장의 개요가
            // 나와야 하는데 개요까지만 나옴." 원인: `OutlineNavigationRequest.
            // shared.requestedSelection`을 실제로 소비해 화면을 전환하는
            // `.onChange` 핸들러가 지금까지 `OutlineTreeSplitContent`(맥OS/
            // 아이패드 전용, 아래)에만 있었다 — 아이폰 분기(`isPhone`, 이 위)는
            // `OutlineTreeList(..., selection: nil, path: $path)`만 그릴 뿐
            // 이 요청을 전혀 관찰하지 않았다. 그래서 통합 검색의 "개요" 결과를
            // 탭하면 `AppNavigationRequest.shared.request(.outline)`이
            // `PhoneTabView`의 `.fullScreenCover`를 열어 이 화면 자체는 뜨지만
            // (=사용자가 본 "개요 기능까지는 이동이 됨"), 정작 요청받은 책/장
            // 선택은 아무도 반영하지 않아 트리 최상위 화면만 보였다. 아이패드/
            // 맥(`OutlineTreeSplitContent`)의 같은 핸들러를 그대로 옮겨 쓰되,
            // 그쪽은 `selection`(같은 화면 안에서 오른쪽 패널만 바꿔치기)을
            // 쓰는 반면 이 화면은 `NavigationStack(path:)`으로 화면을 push하는
            // 구조라(위 `path` 선언부 주석 — 장 칩 여러 개가 `List` 행 하나에
            // 몰려 있던 문제 때문에 이 방식으로 바꿨다) `path`에 값을 담는다.
            // 검색 결과를 연달아 다른 책/장으로 탭하는 경우를 고려해
            // append 대신 교체(`= [newValue]`)한다 — 매번 새 목적지로 바로
            // 이동해야지, 이전에 우연히 쌓인 push 위에 계속 얹으면 뒤로가기
            // 스택이 뒤엉킨다.
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
    /// [2026-08-27 신설] 위 `OutlineTreeView` 주석 참고 — 아이폰 전용,
    /// `chapterChip`이 장 칩을 눌렀을 때 이 배열에 직접 append해 이동한다.
    /// 아이패드/맥 쪽(`OutlineTreeSplitContent`가 만드는 인스턴스)은 이 값을
    /// 넘기지 않아 nil로 남고, `chapterChip`의 `isPhoneLayout == false`
    /// 분기는 애초에 이 값을 쓰지 않는다.
    var path: Binding<[OutlineTreeSelection]>? = nil

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
        // [2026-08-29 성능 수정] 사용자 보고 — "개요 등록 수가 많아 지면
        // 많아질수록 느려짐." 원인: 바로 아래 `booksWithContent`/
        // `chaptersWithContent`는 계산 프로퍼티인데, 지금까지 책 행마다
        // (`rowView`의 `.book` 케이스)·장 칩마다(`chapterChip`) 각각 따로
        // 접근해 왔다 — 즉 화면에 펼쳐진 책 수·장 칩 수만큼
        // `bookOutlines`/`chapterSummaries` 전체를 매번 처음부터 다시
        // 스캔한 것이다(예: 66권을 다 펼치면 장 칩 약 1,189개 × 매번
        // 최대 1,189개 스캔 = 렌더 한 번에 백만 단위 연산). 계산 로직
        // 자체(두 프로퍼티의 정의)는 전혀 바꾸지 않고, 이 화면을 그리는
        // 동안 딱 한 번만 계산해 아래로 넘겨 재사용하도록 "계산 시점"만
        // 바꾼다.
        let booksWithContent = self.booksWithContent
        let chaptersWithContent = self.chaptersWithContent
        VStack(spacing: 0) {
            searchField
            Divider()
            List(rows) { row in
                rowView(row, booksWithContent: booksWithContent, chaptersWithContent: chaptersWithContent)
            }
            .listStyle(.plain)
        }
        .navigationTitle("개요")
        // [2026-08-26 추가, 사용자 보고 fix] "아이폰 개요 — 장 버튼을 누르면
        // 무조건 마지막 장으로 이동, 뒤로가기(<)를 누르면 이전 장으로 이동
        // (원래는 이전 화면으로 가야 함)." 원인 — `chapterChip`/`bookLabel`이
        // (아이폰 전용 분기) 지금까지 클로저 기반 `NavigationLink { Destination()
        // } label: { ... }`을 칩/책마다 하나씩 만들어 왔는데, 한 책을 펼치면
        // 그 책의 모든 장 칩이 `chapterChipGrid` 하나 — 즉 `List`의 행(row)
        // *하나*(`.chapterGrid` 케이스) 안에 통째로 들어간다(2026-08-15 스크롤
        // 최소화 재설계, 파일 상단 주석 참고). `List`/`NavigationStack`은 한
        // 행 안에 클로저 기반 `NavigationLink`가 여러 개 있는 구성을 안정적으로
        // 구분하도록 설계돼 있지 않아 — 실제로 어느 칩을 탭했는지와 무관하게
        // 그 행에 등록된 링크 중 하나(주로 마지막 것)로만 이동하는 것으로
        // 보인다. 탭할 때마다 그 잘못된 목적지가 스택에 새로 push되니, "<"를
        // 누르면 (사용자가 기대하는 "이전 화면"이 아니라) 그 직전에 잘못
        // push됐던 다른 장 화면이 나와 "이전 장으로 이동"처럼 보인다 —
        // `BibleVerseDestination.swift`가 이미 겪고 고친 것과 근본적으로
        // 같은 종류의 문제(그 파일 상단 주석 참고)라, 같은 해법(값 기반
        // `NavigationLink(value:)` + 화면 전체에 딱 하나뿐인
        // `.navigationDestination(for:)`)을 그대로 적용한다 — 이러면 목적지
        // 해석이 탭 위치가 아니라 실제로 전달된 값 하나로만 결정되어, 여러
        // 링크가 한 행에 있어도 더 이상 서로 뒤섞이지 않는다.
        //
        // `destinationView(for:)`는 `OutlineTreeSplitContent`(맥OS/아이패드)가
        // 이미 쓰고 있던 것을 그대로 재사용한다(같은 파일의 최상위 함수).
        // 맥OS/아이패드 쪽(`isPhoneLayout == false`)은 `NavigationLink(value:)`를
        // 전혀 만들지 않으므로 이 등록은 그쪽에선 그냥 쓰이지 않을 뿐 해가 없다.
        .navigationDestination(for: OutlineTreeSelection.self) { selection in
            destinationView(for: selection)
        }
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
    private func rowView(_ row: OutlineTreeRow, booksWithContent: Set<Int>, chaptersWithContent: Set<Int>) -> some View {
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
            chapterChipGrid(book, chaptersWithContent: chaptersWithContent)
                .padding(.leading, 34)
                .padding(.vertical, 8)
        }
    }

    /// [2026-08-15 신설] 장 하나당 행 하나이던 목록을 대체 — 작은 칩을 폭에 맞춰
    /// 줄바꿈해 늘어놓는다. `Layout` 프로토콜로 직접 흐름 레이아웃을 만드는 대신
    /// `LazyVGrid(.adaptive(...))`를 쓴 이유: 칩 크기가 고정(30pt)이라 adaptive
    /// 컬럼이 흐름 레이아웃과 시각적으로 동일하게 줄바꿈되면서, 커스텀 `Layout`
    /// 구현 없이 훨씬 적은 코드로 같은 결과를 낸다.
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
            // [2026-08-26 시도, 2026-08-27 재시도 끝에 최종 구조로 교체]
            // 처음엔 클로저 기반 `NavigationLink`, 그다음 값 기반
            // `NavigationLink(value:)`, 그다음 그걸 `.background`에 숨기는
            // 시도까지 — 셋 다 "장 칩 여러 개가 `List` 행 하나에 몰려
            // 있다"는 근본 구조를 그대로 둔 채였고, 그래서 셋 다 결국
            // "탭한 칩과 무관하게 마지막 장으로 이동, 뒤로가기가 이전
            // 화면이 아니라 이전 장으로 감" 버그를 재현했다(위
            // `OutlineTreeView.path` 주석 참고). 이번엔 `NavigationLink`
            // 자체를 버리고 평범한 `Button`으로 바꿨다 — 어느 칩이 눌렸는지는
            // 이 클로저가 캡처한 `chapter`/`book.bookId` 값만으로 결정되므로
            // `List`나 내비게이션 링크의 행-단위 식별에 전혀 기대지 않는다.
            // 이동은 `OutlineTreeView`가 소유한 `path` 배열에 직접 append해
            // `NavigationStack(path:)`가 그대로 push하게 한다. 부수 효과로
            // `Button`은 `List`가 자동으로 붙이는 화살표(disclosure indicator)
            // 대상이 아니므로, 지난번 겪었던 꺽쇠 겹침 문제도 이 구조에서는
            // 애초에 생기지 않는다.
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
            // [2026-08-26 수정] 위 `chapterChip`과 같은 이유 — 이 행도 같은
            // `List` 행 하나(`.book` 케이스) 안에 다른 버튼(펼침 토글)과 함께
            // 있어 잠재적으로 같은 문제의 소지가 있으므로 일관되게 값 기반으로
            // 바꿔 둔다.
            NavigationLink(value: OutlineTreeSelection.book(book.bookId)) {
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
