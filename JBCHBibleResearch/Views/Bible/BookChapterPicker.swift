//
//  BookChapterPicker.swift
//  JBCHBibleResearch
//
//  책/장 선택 UI. 그리드 피커와 "요한복음 3장" 같은 텍스트 입력 두 방식을 제공한다.
//  텍스트 입력은 이동 버튼(또는 엔터) 시점에 BooksProvider.matchBookPrefix로 한 번에
//  해석한다(실시간 후보 드롭다운은 없음). 장 개수는 Book.chapterCount(books.json)를
//  쓰고, 그리드 피커 검색창은 초성 입력("ㅇㅎㅂㅇ")도 지원한다.
//

import SwiftUI
import BibleResearchModels

struct BookChapterPicker: View {
    let books: [Book]
    let selectedBook: Book
    let selectedChapter: Int
    /// false면 자유 텍스트 입력(TextField + "이동")을 숨긴다. 기본값 true.
    /// 옵션 프로퍼티는 모두 `onSelect` 앞에 둔다 — memberwise init에서 `onSelect`가
    /// 마지막 파라미터여야 트레일링 클로저 매칭이 깨지지 않는다.
    var showsFreeTextSearch: Bool = true
    /// 입력에 절 번호까지 있을 때만 호출된다(장만 입력하면 `onSelect`). 기본값 nil.
    var onSelectVerse: ((Book, Int, Int) -> Void)? = nil
    /// true면 `body`가 `compactBarBody`(이어진 막대)를, false면 `standardBody`를 쓴다. 기본값 false.
    var compactTouchTargets: Bool = false
    /// true면 `standardBody` 대신 `unifiedBarBody`(성경 조회 맥OS 상단 막대와 같은 32pt 규격, `BibleBarControls.swift`)를 쓴다.
    /// 다른 화면(교차참조/설교/메모/문서/말씀 요약)의 선택기는 기본값 false라 모양이 그대로다. `compactTouchTargets`가 true면 무시된다.
    var unifiedBarStyle: Bool = false
    var onSelect: (Book, Int) -> Void

    @State private var isGridPresented = false
    @State private var freeText: String = ""
    @State private var parseErrorMessage: String?
    // 키보드 액세서리의 "완료" 버튼과 `submitFreeText()` 성공 시 키보드를 내리는 데 쓴다.
    @FocusState private var isFreeTextFocused: Bool
    /// 테마 글자색 읽기 전용 접근 — 투명 배경 검색창이 상단 바 테마색에 맞춰야 한다.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        Group {
            if compactTouchTargets {
                compactBarBody
            } else if unifiedBarStyle {
                unifiedBarBody
            } else {
                standardBody
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

    private var standardBody: some View {
        HStack(spacing: 8) {
            Button {
                isGridPresented = true
            } label: {
                // 약어 표시(`abbreviation.first`는 공식 약어). 없으면 전체 이름으로 폴백.
                Label("\(selectedBook.abbreviation.first ?? selectedBook.nameKo) \(selectedChapter)장", systemImage: "book")
            }
            .popover(isPresented: $isGridPresented) {
                // 현재 책의 장 그리드로 바로 시작한다. "책 목록" 버튼(ChapterGrid.onBack)으로 다른 책 선택도 가능.
                BookGridPicker(books: books, initialBook: selectedBook) { book, chapter in
                    onSelect(book, chapter)
                    isGridPresented = false
                }
                .frame(minWidth: 360, minHeight: 460)
            }

            if showsFreeTextSearch {
                // 테마 글자색이 없으면(macOS 툴바 등) `Color.secondary`로 폴백한다.
                // 좁은 컨테이너에서도 placeholder가 상자 밖으로 삐져나오지 않도록 `.lineLimit(1)`.
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    TextField(
                        "예:창세기1, 요3, 요3:16",
                        text: $freeText,
                        prompt: Text("예:창세기1, 요3, 요3:16")
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
                    )
                        .font(.body)
                        .lineLimit(1)
                        .textFieldStyle(.plain)
                        .onSubmit(submitFreeText)
                        .focused($isFreeTextFocused)
                        // 키보드 위 액세서리 줄의 "완료" 버튼으로 포커스를 해제한다. `.keyboard` 배치는 iOS 전용.
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
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(settings.bibleTextColor?.opacity(0.2) ?? Color.secondary.opacity(0.2), lineWidth: 1))
                // 폭 제한은 안쪽 `TextField`가 아니라 아이콘/패딩을 포함한 바깥 `HStack`에 둔다.
                .frame(minWidth: 105, maxWidth: 165)

                // `compactBarBody`의 "이동" 아이콘 버튼과 같은 모양(강조색 원 + 흰 화살표).
                Button(action: submitFreeText) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color("AccentColor")))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("이동")
            }
        }
    }

    /// 성경 조회 맥OS 상단 막대용 — 책 버튼, 검색창, 이동 버튼을 `BibleBarControls.swift`의 32pt 규격으로 그린다.
    /// 동작(그리드 팝오버, 자유 텍스트 해석, 오류 알림)은 `standardBody`와 같은 상태·함수를 쓴다.
    private var unifiedBarBody: some View {
        HStack(spacing: 10) {
            Button {
                isGridPresented = true
            } label: {
                Label("\(selectedBook.abbreviation.first ?? selectedBook.nameKo) \(selectedChapter)장", systemImage: "book")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(BibleBarButtonStyle())
            .help("책과 장 고르기")
            .popover(isPresented: $isGridPresented) {
                BookGridPicker(books: books, initialBook: selectedBook) { book, chapter in
                    onSelect(book, chapter)
                    isGridPresented = false
                }
                .frame(minWidth: 360, minHeight: 460)
            }

            if showsFreeTextSearch {
                let textColor = settings.bibleTextColor ?? Color.primary
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.62))
                    TextField(
                        "예: 창세기1, 요3:16",
                        text: $freeText,
                        prompt: Text("예: 창세기1, 요3:16").foregroundStyle(textColor.opacity(0.62))
                    )
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .textFieldStyle(.plain)
                    .foregroundStyle(textColor)
                    .onSubmit(submitFreeText)
                    .focused($isFreeTextFocused)
                }
                .padding(.horizontal, 10)
                .frame(height: BibleBarMetrics.height)
                .background(
                    RoundedRectangle(cornerRadius: BibleBarMetrics.radius, style: .continuous)
                        .fill(textColor.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BibleBarMetrics.radius, style: .continuous)
                        .strokeBorder(textColor.opacity(isFreeTextFocused ? 0.5 : BibleBarMetrics.lineOpacity), lineWidth: 1)
                )
                .frame(minWidth: 120, maxWidth: 190)

                Button(action: submitFreeText) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(BibleBarButtonStyle(kind: .primary, isSquare: true))
                .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("이동")
                .accessibilityLabel("이동")
            }
        }
    }

    /// 아이폰/아이패드 공용 "이어진 막대" 레이아웃(책 아이콘·검색창·이동 아이콘).
    /// `BibleReadingView.JoinedNavBadgeModifier`를 재사용해 상단 막대의 나머지 아이콘과 모양을 맞춘다.
    private var compactBarBody: some View {
        HStack(spacing: 0) {
            Button {
                isGridPresented = true
            } label: {
                Image(systemName: "book")
            }
            .buttonStyle(BibleCapsuleItemStyle())
            .accessibilityLabel("책과 장 고르기")
            .popover(isPresented: $isGridPresented) {
                BookGridPicker(books: books, initialBook: selectedBook) { book, chapter in
                    onSelect(book, chapter)
                    isGridPresented = false
                }
                .frame(minWidth: 360, minHeight: 460)
            }

            // 버튼 사이 구분선(2026-10-02) — 책 | 검색 칸 | 이동.
            BibleCapsuleDivider()

            // 이 검색창은 "현재 위치 표시"와 "직접 검색 입력"을 겸한다. 포커스가 없을 때는
            // `syncFreeTextToCurrentPositionIfNeeded()`가 현재 책/장 약어로 채우고, 타이핑 중에는 건드리지 않는다.
            // "장"은 `freeText`에 넣지 않고 옆의 고정 `Text("장")`으로 분리했다. 포커스 중에는
            // "요3:16" 같은 입력도 있어 이 라벨을 숨긴다.
            HStack(spacing: 2) {
                // 짧은 약어 입력이 성글게 보이도록 자간 2pt.
                TextField("예:창세기1, 요3, 요3:16", text: $freeText)
                    .font(.title3)
                    .tracking(2)
                    .lineLimit(1)
                    .textFieldStyle(.plain)
                    // `.plain` 스타일은 배경이 없어 상단 바 배경(테마색일 수 있음)이 비친다 — 글자색도 테마색 우선.
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .onSubmit(submitFreeText)
                    .focused($isFreeTextFocused)
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

                if !isFreeTextFocused && !freeText.isEmpty {
                    Text("장")
                        .font(.title3)
                        // TextField와 같은 이유로 테마 글자색 우선, 없으면 `.secondary`.
                        .foregroundStyle(settings.bibleTextColor ?? .secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            // 구분선과 텍스트 사이 여백.
            .padding(.horizontal, 8)
            // `maxWidth: .infinity`를 쓰면 이 영역이 바깥 `.frame(maxWidth: .infinity)` 안에서 남는 폭을 모두
            // 흡수해 캡슐 전체가 화면 폭만큼 늘어난다. 고정 상한(90)은 최대 6자 안팎의 약어("삼상18", "요3:16")가
            // `.title3` + `tracking(2)`에서도 잘리지 않는 값이다.
            .frame(minWidth: 50, maxWidth: 90, minHeight: 44)

            BibleCapsuleDivider()

            // 강조 채움 원으로 "주된 실행 동작"임을 구분한다(밝은 테마 금갈색, 어두운 테마 밝은 금색).
            Button(action: submitFreeText) {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(BibleCapsuleGoStyle())
            .accessibilityLabel("이동")
            .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear {
            syncFreeTextToCurrentPositionIfNeeded()
        }
        .onChange(of: selectedBook) { _, _ in
            syncFreeTextToCurrentPositionIfNeeded()
        }
        .onChange(of: selectedChapter) { _, _ in
            syncFreeTextToCurrentPositionIfNeeded()
        }
        .onChange(of: isFreeTextFocused) { _, focused in
            // 제출 없이 포커스를 잃으면 입력하다 만 텍스트를 현재 위치 약어로 되돌린다.
            if !focused {
                syncFreeTextToCurrentPositionIfNeeded()
            }
        }
    }

    /// `compactBarBody` 전용 — 포커스가 없을 때 검색창을 현재 책/장 약어로 채운다. 타이핑 중에는 건드리지 않는다.
    private func syncFreeTextToCurrentPositionIfNeeded() {
        guard !isFreeTextFocused else { return }
        // "장"은 별도 고정 라벨이 맡으므로 책/장 약어만 넣는다.
        freeText = "\(selectedBook.abbreviation.first ?? selectedBook.nameKo)\(selectedChapter)"
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
        // 장 숫자 뒤 나머지에서 절을 인식한다(콜론 "3:16", 한글 어순 "3장 16절" — `BibleReferenceExtractor`와 같은 규칙).
        let afterChapterDigits = remainder[digits.endIndex...]
        let verse = Self.parseTrailingVerse(afterChapterDigits)
        if let onSelectVerse, let verse {
            onSelectVerse(match.book, max(1, chapter), verse)
        } else {
            onSelect(match.book, max(1, chapter))
        }
        // 컴팩트 모드는 검색창이 "현재 위치 표시"를 겸하므로, 부모의 selectedBook/selectedChapter가
        // 갱신되기 전에도 비어 보이지 않게 이동한 결과의 약어로 즉시 채운다. 표준 모드는 비운다.
        if compactTouchTargets {
            // "장"은 고정 라벨이 보여주므로 붙이지 않는다.
            freeText = "\(match.book.abbreviation.first ?? match.book.nameKo)\(max(1, chapter))"
        } else {
            freeText = ""
        }
        // 이동에 성공하면 키보드를 내린다. 실패 경로(위 두 `guard`)는 여기 도달하지 않아 포커스가 유지된다.
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


/// 책/장 선택 팝오버 공용 헤더(제목 + 닫기 버튼). `onBack`을 넘기면(장 그리드 단계) 뒤로가기 셰브런도 보인다.
private struct PickerHeaderBar: View {
    let title: String
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                // 아이콘 크기는 그대로 두고 보이는 클릭 영역을 키운다(macOS는 조준해서 클릭하므로 투명
                // 탭 영역만으론 부족). `bookCircleButton`/`chapterButton`과 같은 강조색 12% 배경 + 35% 테두리,
                // 탭 영역은 HIG 최소치 44×44pt.
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                        .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("뒤로")
            }
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            // 탭 영역만 44×44pt로 넓힌다(뒤로가기 버튼과 동일).
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 10)
        // 위쪽 여백을 더 준다(아래는 `Divider()`가 바로 이어짐). 좌우는 44pt 탭 영역만큼 버튼이 안쪽으로 들어와 보이지 않게 10.
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

private struct BookGridPicker: View {
    let books: [Book]
    var onSelect: (Book, Int) -> Void

    /// 테마 배경/글자색 읽기 전용 접근 — `body` 끝의 `.background()`/`.foregroundStyle()`에서 쓴다.
    private var settings: UserSettingsStore { .shared }

    @State private var pendingBook: Book?
    @State private var searchText: String = ""

    /// `initialBook`을 넘기면 책 목록을 건너뛰고 그 책의 장 그리드로 바로 시작한다. nil이면 책 목록부터.
    init(books: [Book], initialBook: Book? = nil, onSelect: @escaping (Book, Int) -> Void) {
        self.books = books
        self.onSelect = onSelect
        _pendingBook = State(initialValue: initialBook)
    }

    /// 검색 중에도 구약/신약 구분을 유지한다. 빈 섹션은 `testamentSection`이 숨긴다.
    private func matches(_ book: Book) -> Bool {
        searchText.isEmpty || book.matches(query: searchText)
    }

    private var oldTestamentBooks: [Book] {
        books.filter { $0.testament == .old && matches($0) }
    }

    private var newTestamentBooks: [Book] {
        books.filter { $0.testament == .new && matches($0) }
    }

    /// 팝오버 최소 폭 360 기준: 원 지름 52~62pt + 간격 10pt로, 좌우 패딩 32를 뺀 328pt 안에 4~6개가 들어간다.
    private static let columns = [GridItem(.adaptive(minimum: 52, maximum: 62), spacing: 10)]

    var body: some View {
        // 두 분기(장 그리드 / 책 목록)를 `Group`으로 감싸 테마 배경/글자색을 한 번만 적용한다
        // (배경을 지정하지 않으면 시스템 기본 배경이 드러난다).
        Group {
            if let pendingBook {
                ChapterGrid(book: pendingBook) { chapter in
                    onSelect(pendingBook, chapter)
                } onBack: {
                    self.pendingBook = nil
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                PickerHeaderBar(title: "책 선택")
                Divider()
                VStack(spacing: 8) {
                    // 연구문서 검색란(`DocumentsHomeView.searchAndFilterBar`)과 같은 모양(돋보기 + `.plain` TextField + 지우기 버튼 + 옅은 채움/테두리).
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("책 이름 검색 (예: 요한, ㅇㅎ)", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.body)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
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
        }
        // 테마가 없으면 시스템 기본과 동일하게 동작하도록 폴백한다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
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

    /// 약어 원형 버튼. 텍스트는 강조색 굵게로 원 배경/테두리와 한 벌로 보이게 한다(`ChapterGrid.chapterButton`도 동일).
    private func bookCircleButton(_ book: Book) -> some View {
        Button {
            pendingBook = book
        } label: {
            // 2글자 약어도 `minimumScaleFactor`로 원(52pt) 안에 들어간다.
            Text(book.abbreviation.first ?? book.nameKo)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color("AccentColor"))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(4)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct ChapterGrid: View {
    let book: Book
    var onSelect: (Int) -> Void
    var onBack: () -> Void

    /// 고정 크기 라운드 사각형(52×44pt, 44는 HIG 최소 탭 영역) — 3자리 장 번호(시편)가 줄바꿈되지 않도록
    /// 크기와 `.lineLimit(1)`을 고정한다. 원형은 3자리를 담으려면 지름을 키워야 해 쓰지 않는다.
    private static let columns = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 10)]

    /// 팝오버 높이 추정치. 장이 많은 책(창세기 50장 등)은 호출부의 고정 minHeight 460으로 부족해
    /// 5열 기준 필요 높이를 계산해 `.frame(minHeight:)`로 얹는다(상한 560, 그 이상은 스크롤). 460과는 큰 쪽이 적용된다.
    private var estimatedGridHeight: CGFloat {
        let headerHeight: CGFloat = 54
        let dividerHeight: CGFloat = 1
        let rowHeight: CGFloat = 54
        let outerPadding: CGFloat = 32
        // 열 개수는 팝오버 최소 폭 360 기준(`BookGridPicker.columns`와 같은 계산)으로 5열 추정. 더 넓게 뜨면
        // 실제 줄 수는 줄어 추정치가 여유 쪽으로만 어긋난다.
        let columnsEstimate = 5
        let rows = Int(ceil(Double(book.chapterCount) / Double(columnsEstimate)))
        let gridHeight = min(CGFloat(rows) * rowHeight + outerPadding, 560)
        return headerHeight + dividerHeight + gridHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PickerHeaderBar(title: "\(book.abbreviation.first ?? book.nameKo) — 장 선택", onBack: onBack)
            Divider()

            if book.chapterCount < 1 {
                Text("\(book.nameKo)의 장 정보가 없습니다.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 10) {
                        ForEach(1...book.chapterCount, id: \.self) { chapter in
                            chapterButton(chapter)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minHeight: estimatedGridHeight)
    }

    /// 고정 크기 라운드 사각형 버튼. `bookCircleButton`과 같은 색 언어(강조색 12% 배경 + 35% 테두리).
    private func chapterButton(_ chapter: Int) -> some View {
        Button {
            onSelect(chapter)
        } label: {
            Text("\(chapter)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color("AccentColor"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 52, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color("AccentColor").opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
