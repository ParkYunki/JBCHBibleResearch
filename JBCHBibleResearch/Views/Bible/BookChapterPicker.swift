//
//  BookChapterPicker.swift
//  JBCHBibleResearch
//
//  screens.md 3장/S1 — 책/장 선택 UI. "그리드 피커"와 "요한복음 3장" 같은 텍스트
//  자동완성 두 방식을 제공한다.
//
//  ⚠️ [단순화, 원문서와 차이] 원문서가 말하는 "자동완성"은 입력 중 후보 목록을 실시간
//  으로 보여주는 것을 뜻할 수 있으나, 이번 구현은 텍스트를 다 입력하고 이동 버튼(또는
//  엔터)을 눌렀을 때 BooksProvider.matchBookPrefix로 한 번에 해석하는 방식으로
//  단순화했다. 실시간 후보 드롭다운은 이후 필요 시 추가하면 된다.
//
//  2026-08-06: 장 개수는 더 이상 BibleReferenceStore에 매번 쿼리하지 않고
//  `Book.chapterCount`(books.json 정적 데이터)를 그대로 쓴다 — 사용자가 이전에 실제
//  배포했던 앱의 데이터를 옮겨 온 것이라 신뢰할 수 있고, DB를 열 필요도 없어졌다.
//  그리드 피커에 검색창도 추가했다(KoreanUtil 이식, Book+Search.swift 참고) — 초성
//  입력("ㅇㅎㅂㅇ")도 지원한다.
//

import SwiftUI
import BibleResearchModels

struct BookChapterPicker: View {
    let books: [Book]
    let selectedBook: Book
    let selectedChapter: Int
    /// [2026-08-12 추가] 사용자 요청 — "관주 연결시 화면 상단 중앙 성경을
    /// 타이핑해서 성경을 찾는 텍스트 공간은 필요없음." 메인 조회 화면
    /// (chapterNavigationControls)은 그대로 두고, `CrossReferenceTargetPicker`
    /// 처럼 책/장 선택 버튼만 필요한 화면에서 자유 텍스트 입력(TextField + "이동")
    /// 을 끌 수 있게 옵션으로 뺐다 — 기본값 true라 기존 호출부는 전혀 바뀌지 않는다.
    ///
    /// [2026-08-12 위치 수정] 컴파일러 경고 — "Backward matching of the
    /// unlabeled trailing closure is deprecated." 암시적 멤버와이즈 이니셜라이저는
    /// 프로퍼티 선언 순서를 그대로 따르는데, 이 프로퍼티가 `onSelect` 뒤에 있으면
    /// `onSelect`가 더 이상 "마지막 파라미터"가 아니게 되어, 호출부의 트레일링
    /// 클로저가 `onSelect`와 매칭되려면 역방향 매칭(지원 중단 예정)을 타게 된다 —
    /// `onSelect`가 항상 마지막 프로퍼티로 남도록 이 프로퍼티를 그 앞으로 옮겼다.
    var showsFreeTextSearch: Bool = true
    var onSelect: (Book, Int) -> Void

    @State private var isGridPresented = false
    @State private var freeText: String = ""
    @State private var parseErrorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isGridPresented = true
            } label: {
                Label("\(selectedBook.nameKo) \(selectedChapter)장", systemImage: "book")
            }
            .popover(isPresented: $isGridPresented) {
                // [2026-08-08 추가] 사용자 요청 — "현재 성경에서 장만 이동하려면
                // 성경 버튼을 클릭하고 동일한 성경을 다시 클릭해야 장을 선택할 수
                // 있음". 지금 보고 있는 책(selectedBook)을 그대로 넘겨 처음부터
                // 장 그리드가 열리게 한다 — "책 목록" 버튼(ChapterGrid.onBack)으로
                // 다른 책으로 바꾸는 경로는 그대로 남겨 둔다.
                BookGridPicker(books: books, initialBook: selectedBook) { book, chapter in
                    onSelect(book, chapter)
                    isGridPresented = false
                }
                .frame(minWidth: 360, minHeight: 460)
            }

            // [2026-08-08 변경] 사용자 요청 — placeholder 예시 문구를 더 짧고
            // 실제 입력 형태에 가깝게("예:창세기1, 요3").
            // [2026-08-11 추가] 사용자 요청 — "모든 검색창의 placeholder 글꼴은
            // 기본 글꼴에 일반 사이즈로." `.appDefaultFont()`(Paperlogy)가 그대로
            // 적용되던 것을 시스템 기본 글꼴/보통 크기로 되돌린다.
            if showsFreeTextSearch {
                // [2026-08-15 추가] 사용자 보고 — "예:창세기1, 요3"가 검색창
                // 안이 아니라 옆으로 밀려나 보임(호출부 `Form`/`Section` 행이
                // 이 폭을 다시 계산하려 들면서 생긴 충돌 — 호출부인
                // `DocumentsHomeView.UploadChapterLinkSheet`/`ChapterLinkEditorSheet`
                // 쪽에서 `Form` 자체를 걷어내 근본 원인은 없앴다). 최소 폭을
                // 조금 더 넉넉하게 주고 `.lineLimit(1)`을 명시해, 혹시 다른
                // 좁은 컨테이너에 다시 놓이더라도 placeholder 전체 글자가 상자
                // 밖으로 삐져나오는 대신 상자 폭에 맞춰 잘리도록 방어했다.
                TextField("예:창세기1, 요3", text: $freeText)
                    .font(.body)
                    .lineLimit(1)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 140, maxWidth: 220)
                    .onSubmit(submitFreeText)

                Button("이동", action: submitFreeText)
                    .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert("입력을 이해하지 못했습니다", isPresented: Binding(
            get: { parseErrorMessage != nil },
            set: { if !$0 { parseErrorMessage = nil } }
        )) {
            Button("확인") { parseErrorMessage = nil }
        } message: {
            Text(parseErrorMessage ?? "")
        }
    }

    private func submitFreeText() {
        let trimmed = freeText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let match = BooksProvider.shared.matchBookPrefix(in: trimmed) else {
            parseErrorMessage = "\"\(trimmed)\"에서 책 이름을 찾지 못했습니다."
            return
        }
        let remainder = match.remainder.trimmingCharacters(in: .whitespaces)
        let digits = remainder.prefix(while: { $0.isNumber })
        let chapter = Int(digits) ?? 1
        onSelect(match.book, max(1, chapter))
        freeText = ""
    }
}

private struct BookGridPicker: View {
    let books: [Book]
    var onSelect: (Book, Int) -> Void

    @State private var pendingBook: Book?
    @State private var searchText: String = ""

    /// [2026-08-08 추가] `initialBook`을 넘기면 책 목록을 건너뛰고 곧바로 그 책의
    /// 장 그리드로 시작한다(BookChapterPicker.swift 상단 호출부 주석 참고). nil이면
    /// 기존과 동일하게 책 목록부터 보여준다.
    init(books: [Book], initialBook: Book? = nil, onSelect: @escaping (Book, Int) -> Void) {
        self.books = books
        self.onSelect = onSelect
        _pendingBook = State(initialValue: initialBook)
    }

    private var filteredBooks: [Book] {
        searchText.isEmpty ? books : books.filter { $0.matches(query: searchText) }
    }

    var body: some View {
        if let pendingBook {
            ChapterGrid(book: pendingBook) { chapter in
                onSelect(pendingBook, chapter)
            } onBack: {
                self.pendingBook = nil
            }
        } else {
            VStack(spacing: 8) {
                TextField("책 이름 검색 (예: 요한, ㅇㅎ)", text: $searchText)
                    .font(.body)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                        ForEach(filteredBooks) { book in
                            Button(book.nameKo) { pendingBook = book }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

private struct ChapterGrid: View {
    let book: Book
    var onSelect: (Int) -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Button(action: onBack) {
                Label("책 목록", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            if book.chapterCount < 1 {
                Text("\(book.nameKo)의 장 정보가 없습니다.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(1...book.chapterCount, id: \.self) { chapter in
                            Button("\(chapter)") { onSelect(chapter) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            }
        }
        .padding()
    }
}
