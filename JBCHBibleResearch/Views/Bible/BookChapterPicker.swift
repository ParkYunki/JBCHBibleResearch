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
    /// [2026-08-21 추가] 사용자 요청 — "성경이동 검색 란에 절까지 포함시키면
    /// 해당 절까지 스크롤한다음 하이라이트 잠시 표시할 것(검색 결과 클릭한 것과
    /// 동일한 기능)". `submitFreeText()`가 절 번호까지 인식했을 때만 호출되고,
    /// 절이 없으면(기존 "창세기1"/"요3"처럼 장만 입력) 항상 그냥 `onSelect`로
    /// 간다 — 기본값 nil이라 이 프로퍼티를 모르는 기존 호출부(BibleReadingView
    /// 외엔 없지만)는 전혀 바뀌지 않는다. `onSelect` 바로 앞에 둔 이유는 위
    /// "onSelect가 항상 마지막 프로퍼티로 남아야" 주석과 같다 — 트레일링
    /// 클로저 매칭이 깨지지 않게.
    var onSelectVerse: ((Book, Int, Int) -> Void)? = nil
    var onSelect: (Book, Int) -> Void

    @State private var isGridPresented = false
    @State private var freeText: String = ""
    @State private var parseErrorMessage: String?
    // [2026-08-27 신설] 사용자 보고 — "상단 성경 검색영역에 포커스를 두면
    // 키보드가 올라오는데, 포커스를 해제하거나 키보드를 내릴 수 있게 해야함.
    // 키보드 때문에 다른 메뉴를 사용할 수 없음." 지금까지 이 TextField는
    // 포커스 상태를 전혀 추적하지 않아(FocusState 없음), 프로그램적으로
    // 키보드를 내릴 방법이 없었다 — 아래 키보드 액세서리 툴바의 "완료"
    // 버튼과 `submitFreeText()` 성공 시 자동 해제(두 곳 모두 이 상태를 씀)로
    // 해결한다.
    @FocusState private var isFreeTextFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isGridPresented = true
            } label: {
                // [2026-08-26 수정] 사용자 요청 — "성경 전체 이름이 아닌, 약어로
                // 줄일것(예: 베드로전서 1장 -> 벧전 1장)." `abbreviation.first`는
                // `books.json`에서 항상 공식 약어가 첫 번째로 오도록 되어 있고,
                // 이미 `VerseZoomView`/`CrossReferenceTargetPicker` 등 여러 곳에서
                // "약어로 보여줄 때" 쓰는 것과 같은 관례다(못 찾으면 전체 이름으로
                // 폴백 — books.json이 없는 이론상 경우에 대비).
                Label("\(selectedBook.abbreviation.first ?? selectedBook.nameKo) \(selectedChapter)장", systemImage: "book")
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
                // [2026-08-21 수정] 절 입력도 지원한다는 것을 알리기 위해 예시에
                // "요3:16"을 추가했다("장까지만"도 여전히 되므로 "요3" 예시는 남긴다).
                TextField("예:창세기1, 요3, 요3:16", text: $freeText)
                    .font(.body)
                    .lineLimit(1)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 140, maxWidth: 220)
                    .onSubmit(submitFreeText)
                    .focused($isFreeTextFocused)
                    // [2026-08-27 신설] 위 `isFreeTextFocused` 주석 참고 — 키보드
                    // 위 액세서리 줄에 "완료" 버튼을 달아 명시적으로 포커스를
                    // 해제(=키보드 내림)할 수 있게 한다. `.keyboard` 배치는
                    // 소프트웨어 키보드가 있는 iOS 전용 개념이라(macOS는 하드웨어
                    // 키보드뿐이라 이 액세서리 자체가 뜨지 않는다) `#if os(iOS)`로
                    // 감쌌다.
                    #if os(iOS)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("완료") {
                                isFreeTextFocused = false
                            }
                        }
                    }
                    #endif

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
        // [2026-08-21 추가] 장 숫자 뒤 나머지에서 절을 인식한다. `BibleReferenceExtractor`
        // (성경구절 자동 추출기)가 이미 검증해 둔 두 표기(콜론 "3:16", 한글 어순
        // "3장 16절")와 같은 구분자 규칙을 그대로 따른다 — 새 규칙을 임의로
        // 만들지 않고, 이 앱이 이미 쓰고 있는 절 표기 관행을 그대로 재사용한다.
        let afterChapterDigits = remainder[digits.endIndex...]
        let verse = Self.parseTrailingVerse(afterChapterDigits)
        if let onSelectVerse, let verse {
            onSelectVerse(match.book, max(1, chapter), verse)
        } else {
            onSelect(match.book, max(1, chapter))
        }
        freeText = ""
        // [2026-08-27 신설] 검색에 성공해 실제로 장(+절)을 이동시킨 뒤에는
        // 이 입력창에 계속 머물 이유가 없다 — 키보드를 자동으로 내려 사용자가
        // 곧바로 방금 이동한 화면(하단 메뉴 등)을 쓸 수 있게 한다. 입력을
        // 이해하지 못해 실패한 경로(위 두 `guard`의 `return`)는 이 줄에
        // 도달하지 않으므로, 오타를 고치려는 사용자의 포커스는 그대로
        // 유지된다.
        isFreeTextFocused = false
    }

    /// "3:16"(콜론) 또는 "3장 16절"(한글 어순) 형태의 나머지 텍스트에서 절 번호만
    /// 뽑는다. 두 구분자 모두 아니면(예: 장 번호만 입력한 기존 "창세기1"/"요3")
    /// nil을 돌려줘 `submitFreeText()`가 기존과 동일하게 `onSelect`로 가게 한다.
    private static func parseTrailingVerse<S: StringProtocol>(_ text: S) -> Int? {
        var remainder = Substring(text)
        if remainder.hasPrefix(":") {
            remainder = remainder.dropFirst()
        } else if remainder.hasPrefix("장") {
            remainder = remainder.dropFirst()
        } else {
            return nil
        }
        remainder = remainder.drop(while: { $0 == " " })
        let verseDigits = remainder.prefix(while: { $0.isNumber })
        guard !verseDigits.isEmpty else { return nil }
        return Int(verseDigits)
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

    /// [2026-08-26 추가] 사용자 요청 — "구약/신약으로 구분할것." 검색 중에도
    /// 구분을 유지한다(검색 결과가 구약/신약 어느 한쪽에만 있으면 그 섹션만
    /// 자연히 보이고, 빈 섹션은 `testamentSection`이 통째로 숨긴다).
    private func matches(_ book: Book) -> Bool {
        searchText.isEmpty || book.matches(query: searchText)
    }

    private var oldTestamentBooks: [Book] {
        books.filter { $0.testament == .old && matches($0) }
    }

    private var newTestamentBooks: [Book] {
        books.filter { $0.testament == .new && matches($0) }
    }

    /// [2026-08-26 추가] 사용자 요청 — "4단~6단 고려할 것 - 스크롤 최소화 -
    /// UI/UX 관점에서 유리한 방향으로." 팝오버 최소 폭(`BookChapterPicker`가
    /// `.frame(minWidth: 360, ...)`로 고정해 둠)을 기준으로 계산했다 — 원 지름
    /// 52~62pt + 칸 사이 10pt 간격이면 좌우 여백(padding 16*2)을 뺀 328pt 안에
    /// 대략 5~6개(원이 작을 때)에서 4개(원이 클 때) 사이로 들어와, 폭이 이보다
    /// 넓은 화면(맥OS 팝오버 등)에서도 같은 범위를 유지한다.
    private static let columns = [GridItem(.adaptive(minimum: 52, maximum: 62), spacing: 10)]

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
                    VStack(alignment: .leading, spacing: 20) {
                        testamentSection(title: "구약", books: oldTestamentBooks)
                        testamentSection(title: "신약", books: newTestamentBooks)
                    }
                    .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func testamentSection(title: String, books: [Book]) -> some View {
        // 검색 결과가 한쪽 성경(구약/신약)에 하나도 없으면 그 섹션 헤더까지
        // 통째로 숨긴다 — 빈 헤더만 남아 있으면 오히려 혼란스럽다.
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                LazyVGrid(columns: Self.columns, spacing: 10) {
                    ForEach(books) { book in
                        bookCircleButton(book)
                    }
                }
            }
        }
    }

    /// [2026-08-26 신설] 사용자 요청 — "성경이름을 약어로 줄이고, 버튼을
    /// 동그라미 버튼으로 할것." `abbreviation.first`는 이 앱 전반(예:
    /// `VerseZoomView`, `CrossReferenceTargetPicker`)이 이미 "약어 표시"에 쓰는
    /// 것과 같은 값이다 — 못 찾으면(이론상) 전체 이름으로 폴백.
    private func bookCircleButton(_ book: Book) -> some View {
        Button {
            pendingBook = book
        } label: {
            Text(book.abbreviation.first ?? book.nameKo)
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(4)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                .overlay(Circle().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
