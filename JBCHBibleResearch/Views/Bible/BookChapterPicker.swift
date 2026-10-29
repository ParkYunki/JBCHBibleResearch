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
    /// `unifiedBarBody`/`compactBarBody` 전용. false면 책 버튼(표준 막대 "📖 고전 3장", 캡슐 막대 책 아이콘과 뒤 구분선)을 그리지 않는다 —
    /// 아이패드 두 줄 배치처럼 상단바 제목(`BibleTopBar.bookChapterTitleButton`)이 같은 책/장 그리드 팝오버를 맡을 때 쓴다. 기본값 true.
    /// `standardBody`(다른 화면)에는 영향이 없다.
    var showsBookButton: Bool = true
    /// `unifiedBarBody` 전용. true면 검색창이 남는 폭을 채운다(최소 폭은 그대로, 측정용 이상 폭 = 상한 값).
    /// false(기본값)면 최소~상한 사이(기본 120~190pt).
    var searchFieldFillsWidth: Bool = false
    /// `unifiedBarBody` 전용. true면 검색창 최소/상한 폭을 기본(120/190pt)의 4/5인 96/152pt로 줄인다(2026-10-29, 아이패드 두 줄 배치).
    /// 맥OS·아이폰 표준 막대·아이패드 한 줄 배치는 기본값 false라 그대로다.
    var usesNarrowSearchField: Bool = false
    /// `unifiedBarBody` 전용. 책 버튼·검색창·이동 버튼 사이 간격. 기본 10pt. 아이패드 "아이콘 아래줄" 배치는 6pt(2026-10-29).
    var unifiedBarSpacing: CGFloat = 10
    var onSelect: (Book, Int) -> Void

    @State private var isGridPresented = false
    @State private var freeText: String = ""
    @State private var parseErrorMessage: String?
    // 키보드 액세서리의 "완료" 버튼과 `submitFreeText()` 성공 시 키보드를 내리는 데 쓴다.
    @FocusState private var isFreeTextFocused: Bool
    /// `unifiedBarBody`의 크기(맥 32pt / 아이패드 40pt) — 부모가 `\.bibleBarSizing`으로 정한다.
    @Environment(\.bibleBarSizing) private var sizing
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
                Label("\(selectedBook.displayShortName) \(selectedChapter)장", systemImage: "book")
            }
            .popover(isPresented: $isGridPresented) {
                // 현재 책의 장 그리드로 바로 시작한다. "책 목록" 버튼(ChapterGrid.onBack)으로 다른 책 선택도 가능.
                BookGridPicker(books: books, initialBook: selectedBook, currentBook: selectedBook, currentChapter: selectedChapter) { book, chapter in
                    onSelect(book, chapter)
                    isGridPresented = false
                }
                .modifier(PickerPopoverSizing())
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
        HStack(spacing: unifiedBarSpacing) {
            if showsBookButton {
                Button {
                    isGridPresented = true
                } label: {
                    Label("\(selectedBook.displayShortName) \(selectedChapter)장", systemImage: "book")
                        .font(.system(size: sizing.fontSize, weight: .bold))
                }
                .buttonStyle(BibleBarButtonStyle(height: sizing.height, cornerRadius: sizing.radius, fontSize: sizing.fontSize))
                .help("책과 장 고르기")
                .popover(isPresented: $isGridPresented) {
                    BookGridPicker(books: books, initialBook: selectedBook, currentBook: selectedBook, currentChapter: selectedChapter) { book, chapter in
                        onSelect(book, chapter)
                        isGridPresented = false
                    }
                    .modifier(PickerPopoverSizing())
                }
            }

            if showsFreeTextSearch {
                let textColor = settings.bibleTextColor ?? Color.primary
                // 좁은 칸(`usesNarrowSearchField`, 아이패드 두 줄 배치)은 짧은 예시를 보인다(2026-10-29). 기준은 실제 칸 폭이 아니라
                // 배치(호출부가 정한 값)다 — 폭을 재서 바꾸면 placeholder가 `TextField`의 이상 폭을 바꾸고, 그것이 다시 `ViewThatFits`
                // 측정(표준 ↔ 캡슐)에 들어가 배치가 오갈 수 있다. 제목 키(접근성 라벨)는 기존 문구 그대로 둔다.
                let promptText: Text = usesNarrowSearchField ? Text("예: 요3:16") : Text("예: 창세기1, 요3:16")
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.62))
                    TextField(
                        "예: 창세기1, 요3:16",
                        text: $freeText,
                        prompt: promptText.foregroundStyle(textColor.opacity(0.62))
                    )
                    .font(.system(size: sizing.fieldFontSize))
                    .lineLimit(1)
                    .textFieldStyle(.plain)
                    .foregroundStyle(textColor)
                    .onSubmit(submitFreeText)
                    .focused($isFreeTextFocused)
                    // 아이패드 화상 키보드 위 "완료" 줄 — 다른 입력창(`standardBody`/`compactBarBody`)과 같다. `.keyboard` 배치는 iOS 전용.
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
                .padding(.horizontal, 10)
                .frame(height: sizing.height)
                .background(
                    RoundedRectangle(cornerRadius: sizing.radius, style: .continuous)
                        .fill(textColor.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: sizing.radius, style: .continuous)
                        .strokeBorder(textColor.opacity(isFreeTextFocused ? 0.5 : BibleBarMetrics.lineOpacity), lineWidth: 1)
                )
                // 채움 모드의 `idealWidth`(= 상한 값)는 `ViewThatFits`가 이상 크기(제안 nil)로 잴 때 쓰이는 값이다 — 상한과 같게 두어
                // 배치 선택 기준이 `TextField`의 이상 폭에 좌우되지 않게 한다. 실제 배치(구체적 제안)에서는 남는 폭을 채운다.
                .frame(
                    minWidth: searchFieldMinWidth,
                    idealWidth: searchFieldFillsWidth ? searchFieldCapWidth : nil,
                    maxWidth: searchFieldFillsWidth ? CGFloat.infinity : searchFieldCapWidth
                )

                Button(action: submitFreeText) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: sizing.iconSize, weight: .semibold))
                }
                .buttonStyle(BibleBarButtonStyle(kind: .primary, isSquare: true, height: sizing.height, cornerRadius: sizing.radius, fontSize: sizing.fontSize))
                .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("이동")
                .accessibilityLabel("이동")
            }
        }
    }

    /// `unifiedBarBody` 검색창 최소 폭 — 기본 120pt, `usesNarrowSearchField`면 4/5인 96pt.
    private var searchFieldMinWidth: CGFloat { usesNarrowSearchField ? 96 : 120 }
    /// `unifiedBarBody` 검색창 상한(채움 모드에서는 이상) 폭 — 기본 190pt, `usesNarrowSearchField`면 4/5인 152pt.
    private var searchFieldCapWidth: CGFloat { usesNarrowSearchField ? 152 : 190 }

    /// 아이폰/아이패드 공용 "이어진 막대" 레이아웃(책 아이콘·검색창·이동 아이콘).
    /// `BibleReadingView.JoinedNavBadgeModifier`를 재사용해 상단 막대의 나머지 아이콘과 모양을 맞춘다.
    private var compactBarBody: some View {
        HStack(spacing: 0) {
            if showsBookButton {
                Button {
                    isGridPresented = true
                } label: {
                    Image(systemName: "book")
                }
                .buttonStyle(BibleCapsuleItemStyle())
                .accessibilityLabel("책과 장 고르기")
                .popover(isPresented: $isGridPresented) {
                    BookGridPicker(books: books, initialBook: selectedBook, currentBook: selectedBook, currentChapter: selectedChapter) { book, chapter in
                        onSelect(book, chapter)
                        isGridPresented = false
                    }
                    .modifier(PickerPopoverSizing())
                }

                // 버튼 사이 구분선(2026-10-02) — 책 | 검색 칸 | 이동. 책 버튼이 없으면 바깥 막대의 앞 구분선이 검색 칸 앞을 맡는다.
                BibleCapsuleDivider()
            }

            // 이 검색창은 "현재 위치 표시"와 "직접 검색 입력"을 겸한다. 포커스가 없을 때는
            // `syncFreeTextToCurrentPositionIfNeeded()`가 현재 책/장 약어로 채우고, 타이핑 중에는 건드리지 않는다.
            // "장"은 `freeText`에 넣지 않고 옆의 고정 `Text("장")`으로 분리했다. 포커스 중에는
            // "요3:16" 같은 입력도 있어 이 라벨을 숨긴다.
            HStack(spacing: 0) {
                // 자간(예전 2pt)을 없애고 가운데 정렬한다(2026-10-02). "장" 라벨은 입력칸 바로 오른쪽에 붙는다.
                TextField("예:창세기1, 요3, 요3:16", text: $freeText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
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

                // [2026-10-29 booklabel1] "장" 라벨은 한국어 앱에서만 붙인다. 다른 언어는 "Gen 1", "创世纪1"처럼 책+숫자만으로
                // 참조가 되고, 번역 라벨("Ch."/"Cap."/"Гл." 등)은 숫자 뒤에 오면 어순이 어색하며 칸 폭(아래 frame)도 30~56pt 더 든다.
                if AppLanguage.isKorean && !isFreeTextFocused && !freeText.isEmpty {
                    Text("장")
                        .font(.title3)
                        // TextField와 같은 이유로 테마 글자색 우선, 없으면 `.secondary`.
                        .foregroundStyle(settings.bibleTextColor ?? .secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            // 구분선과 텍스트 사이 여백(예전 8pt → 4pt).
            .padding(.horizontal, 4)
            // `maxWidth: .infinity`를 쓰면 이 영역이 바깥 `.frame(maxWidth: .infinity)` 안에서 남는 폭을 모두
            // 흡수해 캡슐 전체가 화면 폭만큼 늘어난다. 고정 상한(90)은 최대 6자 안팎의 약어("삼상18", "요3:16")가
            // `.title3`에서도 잘리지 않는 값이다(자간 2pt를 뺐고 좌우 여백도 줄어 이전보다 여유가 있다).
            // [2026-10-29 booklabel1] 한국어가 아닌 앱은 상한 104 — 캡슐 자연 폭(버튼 6×40 + 구분선 6 + 좌우 8 = 254 + 이 칸)이
            // `BibleReadingView.chapterNavigationControls` 주석의 아이폰 세로 폭 358pt를 넘지 않는 최대값. 영어·스페인어·독일어·
            // 이탈리아어·일본어 약칭 + 마지막 장("2 Crón 36", "2Thess 3", "Ⅱサム24")이 들어간다. 더 좁은 기기에서는 최소 50까지 줄어든다.
            // 한국어는 90 그대로(표시 문구도 그대로).
            .frame(minWidth: 50, maxWidth: AppLanguage.isKorean ? 90 : 104, minHeight: 44)

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
        // "장"은 별도 고정 라벨이 맡으므로 책/장 약어만 넣는다. 앱 언어 약칭을 쓴다(한국어는 기존 "창1" 그대로) —
        // 이 문구는 이동 버튼을 누르면 그대로 `matchBookPrefix`에 들어가므로, 그 함수가 앱 언어 이름표를 인식해야 한다.
        freeText = selectedBook.displayShortReference(chapter: selectedChapter)
    }

    private func submitFreeText() {
        let trimmed = freeText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let match = BooksProvider.shared.matchBookPrefix(in: trimmed) else {
            parseErrorMessage = String(localized: "\"\(trimmed)\"에서 책 이름을 찾지 못했습니다.")
            return
        }
        // [booklabel1] 장·절 파싱 직전에 전각 숫자(０-９)와 전각 콜론(：)을 반각으로 바꾼다(일본어·중국어 IME 입력).
        // 반각만 쓰는 기존 입력은 결과가 같다.
        let remainder = Self.normalizedFullwidthDigits(match.remainder.trimmingCharacters(in: .whitespaces))
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
            freeText = match.book.displayShortReference(chapter: max(1, chapter))
        } else {
            freeText = ""
        }
        // 이동에 성공하면 키보드를 내린다. 실패 경로(위 두 `guard`)는 여기 도달하지 않아 포커스가 유지된다.
        isFreeTextFocused = false
    }

    /// 전각 숫자 ０-９(U+FF10…U+FF19)를 0-9로, 전각 콜론 ：(U+FF1A)를 ":"로 바꾼다. 다른 글자는 그대로 둔다.
    private static func normalizedFullwidthDigits(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:
                result.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0xFF1A:
                result.append(":")
            default:
                result.append(scalar)
            }
        }
        return String(result)
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


/// 책/장 선택 팝오버 크기. 맥은 최소 360×460을 보장한다(3열 이상 격자와 장 그리드가 잘리지 않도록). 아이패드는 최소 폭 360만 여기서 걸고,
/// 높이는 책 목록/장 그리드 쪽(`PickerContentHeight`)이 한 번만 정한다.
/// 아이폰은 팝오버가 화면 크기의 시트로 바뀌므로 고정 최소 높이를 주지 않는다 — 가로 모드(화면 높이 약 390pt)에서
/// 최소 높이 460이 시트보다 커져 위쪽이 잘리고 스크롤도 안 되던 문제(2026-10-02)를 막기 위해서다.
///
/// [2026-10-29 bookgrid1] 아이패드에서 `frame(minHeight:)`를 뺐다. SwiftUI `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`
/// 문서의 크기 규칙상 최소값은 부모(팝오버)가 그보다 작은 높이를 줘도 뷰를 최소값으로 키운다. 그래서 팝오버가 요청보다 작게 잡히면 내용이
/// 위아래로 넘쳐 머리(`PickerHeaderBar`, [‹ 책 목록])가 잘렸다. 대신 `IdealHeightFloorLayout`이 이상 크기를 잴 때(제안 높이 nil)만
/// max(자식의 이상 높이, 최소값)을 보고한다 — 이전 `minHeight`가 nil 제안에서 내던 값과 같으므로 공간이 넉넉하면 팝오버 요청 높이는 이전과 같다.
/// 구체적 높이를 받으면 자식이 그 높이를 그대로 따르므로 머리는 남고 아래 `ScrollView`만 줄어든다.
/// (`frame(idealHeight: X)`는 nil 제안에서 자식의 이상 높이와 관계없이 X를 내므로 이전 값을 재현하지 못해 쓰지 않는다.)
/// 맥과 아이폰은 이전 그대로다.
private struct PickerPopoverSizing: ViewModifier {
    /// 아이패드 팝오버 높이의 하한(이상 크기 측정 때만) — 이전 최소 높이(460)와 같은 값.
    static let padMinimumIdealHeight: CGFloat = 460

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            content
        } else {
            content.frame(minWidth: 360)
        }
        #else
        content.frame(minWidth: 360, minHeight: 460)
        #endif
    }
}

/// [2026-10-29 bookgrid1] 책 목록/장 그리드의 높이. 아이패드(아이폰이 아닌 iOS)는 `padMinimumIdealHeight`를 이상 크기 측정 때의 하한으로만 쓰고
/// (`IdealHeightFloorLayout`, `PickerPopoverSizing` 주석), 맥·아이폰은 `otherMinHeight`를 이전처럼 최소 높이로 건다(nil이면 아무것도 걸지 않는다 —
/// 이전에 높이 지정이 없던 책 목록).
private struct PickerContentHeight: ViewModifier {
    let padMinimumIdealHeight: CGFloat
    let otherMinHeight: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom != .phone {
            IdealHeightFloorLayout(minimumIdealHeight: padMinimumIdealHeight) {
                content
            }
        } else {
            otherPlatformBody(content)
        }
        #else
        otherPlatformBody(content)
        #endif
    }

    @ViewBuilder
    private func otherPlatformBody(_ content: Content) -> some View {
        if let otherMinHeight {
            content.frame(minHeight: otherMinHeight)
        } else {
            content
        }
    }
}

/// [2026-10-29 bookgrid1] 자식 하나를 감싸, 제안 높이가 nil일 때(이상 크기 측정)만 보고 높이를 max(자식 높이, `minimumIdealHeight`)로 올린다.
/// 구체적 높이 제안에는 자식이 낸 크기를 그대로 보고하고, 자식에게는 받은 영역 크기를 그대로 제안한다(최소값으로 키우지 않는다).
private struct IdealHeightFloorLayout: Layout {
    let minimumIdealHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(proposal)
        guard proposal.height == nil else { return size }
        return CGSize(width: size.width, height: max(size.height, minimumIdealHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // `frame`의 기본 정렬(.center)과 같게 가운데에 둔다.
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(bounds.size))
    }
}

/// 책/장 선택 팝오버 글자 크기. 맥은 기본 텍스트 스타일이 작아(callout 12 / body 13) 두 단계씩 키운 고정 pt(15)를 쓰고
/// (2026-10-02 요청), 아이패드·아이폰은 기존 텍스트 스타일을 그대로 쓴다.
private enum PickerFonts {
    /// 책/장 버튼 라벨 — 굵게.
    static var cell: Font {
        #if os(macOS)
        return .system(size: 15, weight: .semibold)
        #else
        return .callout.weight(.semibold)
        #endif
    }
    /// 검색 입력창.
    static var field: Font {
        #if os(macOS)
        return .system(size: 15)
        #else
        return .body
        #endif
    }
    /// 구약/신약/"장 선택" 구역 라벨.
    static var section: Font {
        #if os(macOS)
        return .system(size: 15, weight: .semibold)
        #else
        return .system(size: 13, weight: .semibold)
        #endif
    }
    /// 머리 제목(세리프) 크기.
    static var title: CGFloat {
        #if os(macOS)
        return 20
        #else
        return 20
        #endif
    }
    /// 머리 버튼(닫기/‹ 책 목록) 글자 크기.
    static var headerButton: CGFloat {
        #if os(macOS)
        return 15
        #else
        return 15
        #endif
    }
    /// 맥 검색란 높이(글자가 커져 34 → 38).
    static var fieldHeight: CGFloat {
        #if os(macOS)
        return 38
        #else
        return 40
        #endif
    }
}

/// 책/장 선택 팝오버 공용 헤더(제목 + 닫기 버튼). `onBack`을 넘기면(장 그리드 단계) 뒤로가기 셰브런도 보인다.
private struct PickerHeaderBar: View {
    let title: String
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        headerBody
    }

    /// 플랫폼별 규격 — 맥은 성경 조회 막대 규격(32pt), 아이패드·아이폰은 터치용(40pt). 제목·버튼 글자는 `PickerFonts` 참고.
    private var headerButtonStyle: BibleBarButtonStyle {
        #if os(iOS)
        return BibleBarButtonStyle(height: 40, cornerRadius: 10, fontSize: 15)
        #else
        return BibleBarButtonStyle(fontSize: PickerFonts.headerButton)
        #endif
    }

    private static var titleSize: CGFloat { PickerFonts.title }

    /// 구절 레이어(`VerseZoomView`/`OriginalTextInfoView`)와 같은 머리 부품을 쓴다(2026-10-02 구절 레이어 통일안).
    /// 책 선택 단계는 [닫기], 장 선택 단계는 [‹ 책 목록]이 왼쪽 버튼이다. 아래에 글자색 14% 선.
    private var headerBody: some View {
        let textColor = UserSettingsStore.shared.bibleTextColor ?? Color.primary
        return VerseLayerHeader(title: title, titleSize: Self.titleSize) {
            if let onBack {
                Button(action: onBack) {
                    Label("책 목록", systemImage: "chevron.left")
                }
                .buttonStyle(headerButtonStyle)
                .accessibilityLabel("책 목록으로 돌아가기")
            } else {
                Button("닫기") { dismiss() }
                    .buttonStyle(headerButtonStyle)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(textColor.opacity(0.14)).frame(height: 1)
        }
    }
}

private struct BookGridPicker: View {
    let books: [Book]
    var onSelect: (Book, Int) -> Void

    /// 테마 배경/글자색 읽기 전용 접근 — `body` 끝의 `.background()`/`.foregroundStyle()`에서 쓴다.
    private var settings: UserSettingsStore { .shared }

    @State private var pendingBook: Book?
    @State private var searchText: String = ""
    private static var searchFieldHeight: CGFloat { PickerFonts.fieldHeight }
    /// 지금 화면에 켜 둔 책/장 — 책·장 버튼 중 현재 위치를 강조색으로 채워 보여 준다.
    private let currentBook: Book?
    private let currentChapter: Int?

    /// `initialBook`을 넘기면 책 목록을 건너뛰고 그 책의 장 그리드로 바로 시작한다. nil이면 책 목록부터.
    init(books: [Book], initialBook: Book? = nil, currentBook: Book? = nil, currentChapter: Int? = nil,
         onSelect: @escaping (Book, Int) -> Void) {
        self.books = books
        self.currentBook = currentBook
        self.currentChapter = currentChapter
        self.onSelect = onSelect
        _pendingBook = State(initialValue: initialBook)
    }

    /// 검색 중에도 구약/신약 구분을 유지한다. 빈 섹션은 `testamentSection`이 숨긴다.
    /// [2026-10-29 bookgrid1] 한국어가 아닌 앱은 앱 언어 책 이름/약칭도 찾는다(`Book.matchesGridSearch`). 한국어 검색(초성 포함)은 이전과 같다.
    private func matches(_ book: Book) -> Bool {
        searchText.isEmpty || book.matchesGridSearch(query: searchText)
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
                ChapterGrid(
                    book: pendingBook,
                    currentChapter: pendingBook.id == currentBook?.id ? currentChapter : nil
                ) { chapter in
                    onSelect(pendingBook, chapter)
                } onBack: {
                    self.pendingBook = nil
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                PickerHeaderBar(title: String(localized: "책 선택"))
                VStack(spacing: 8) {
                    // 연구문서 검색란(`DocumentsHomeView.searchAndFilterBar`)과 같은 모양(돋보기 + `.plain` TextField + 지우기 버튼 + 옅은 채움/테두리).
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("책 이름 검색 (예: 요한, ㅇㅎ)", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(PickerFonts.field)
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
                    // 입력창: 높이 iOS 40 / 맥 34, 모서리 10, 글자색 5% 채움 + 24% 테두리(구절 레이어 통일안, 맥 포함).
                    .padding(.horizontal, 12)
                    .frame(height: Self.searchFieldHeight)
                    .background(RoundedRectangle(cornerRadius: 10).fill((settings.bibleTextColor ?? Color.primary).opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke((settings.bibleTextColor ?? Color.primary).opacity(0.24), lineWidth: 1))
                    .padding(.horizontal)
                    .padding(.top, 12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            testamentSection(title: String(localized: "구약"), books: oldTestamentBooks)
                            testamentSection(title: String(localized: "신약"), books: newTestamentBooks)
                        }
                        .padding()
                    }
                }
                }
                // 아이패드만 이상 높이 하한 460(이전 `PickerPopoverSizing`의 최소 높이를 이 단계에서 재현). 맥·아이폰은 지정 없음(이전 그대로).
                .modifier(PickerContentHeight(padMinimumIdealHeight: PickerPopoverSizing.padMinimumIdealHeight, otherMinHeight: nil))
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
                PickerSectionLabel(title: title)
                LazyVGrid(columns: Self.columns, spacing: 10) {
                    ForEach(books) { book in
                        bookCircleButton(book)
                    }
                }
            }
        }
    }

    /// 약어 버튼. 맥은 강조색 원형(기존 그대로), iOS는 52×44 라운드 사각형 — 글자색 라벨, 현재 책은 강조색으로 채운다.
    /// (`ChapterGrid.chapterButton`도 같은 색 언어.)
    @ViewBuilder
    private func bookCircleButton(_ book: Book) -> some View {
        let isCurrent = book.id == currentBook?.id
        Button {
            pendingBook = book
        } label: {
            // 2글자 약어도 `minimumScaleFactor`로 52pt 안에 들어간다.
            Text(book.displayShortName)
                .font(PickerFonts.cell)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 4)
                .frame(width: 52, height: 44)
                .modifier(PickerCellStyle(isCurrent: isCurrent))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isCurrent ? String(localized: "\(book.displayName), 현재 책") : book.displayName)
    }
}

/// 책/장 버튼 공통 모양. 일반: 글자색 라벨 + 글자색 5% 채움 + 24% 테두리 / 현재: 강조색 채움 + 배경색 라벨.
private struct PickerCellStyle: ViewModifier {
    let isCurrent: Bool

    /// 테마 배경이 없을 때 현재 항목 라벨(강조색 위 글자)에 쓸 시스템 배경색.
    private static var fallbackBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    func body(content: Content) -> some View {
        let settings = UserSettingsStore.shared
        let textColor = settings.bibleTextColor ?? Color.primary
        let onAccent = settings.bibleBackgroundColor ?? Self.fallbackBackground
        content
            .foregroundStyle(isCurrent ? onAccent : textColor)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCurrent ? Color("AccentColor") : textColor.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isCurrent ? Color("AccentColor") : textColor.opacity(0.24), lineWidth: 1)
            )
    }
}

/// 구약/신약/장 선택 같은 구역 라벨— 글자색 60%의 작은 굵은 글씨.
private struct PickerSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PickerFonts.section)
            .foregroundStyle((UserSettingsStore.shared.bibleTextColor ?? Color.primary).opacity(0.6))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ChapterGrid: View {
    let book: Book
    /// 현재 보고 있는 장(같은 책일 때만 전달). 강조색으로 채워 보여 준다.
    var currentChapter: Int? = nil
    var onSelect: (Int) -> Void
    var onBack: () -> Void

    /// 고정 크기 라운드 사각형(52×44pt, 44는 HIG 최소 탭 영역) — 3자리 장 번호(시편)가 줄바꿈되지 않도록
    /// 크기와 `.lineLimit(1)`을 고정한다. 원형은 3자리를 담으려면 지름을 키워야 해 쓰지 않는다.
    private static let columns = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 10)]

    /// 팝오버 높이 추정치. 장이 많은 책(창세기 50장 등)은 호출부의 고정 minHeight 460으로 부족해
    /// 5열 기준 필요 높이를 계산해 얹는다 — 맥은 `.frame(minHeight:)`, 아이패드는 이상 크기 측정 때의 하한(`PickerContentHeight`)(상한 560, 그 이상은 스크롤). 460과는 큰 쪽이 적용된다.
    private var estimatedGridHeight: CGFloat {
        // 아이폰은 시트 높이를 따르므로(가로 모드에서 화면보다 커지면 잘림) 최소 높이를 주지 않는다. 장이 많으면 `ScrollView`가 맡는다.
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone { return 0 }
        #endif
        // 머리(14 + 40 + 8 + 4) + 선 1 + 구역 라벨 줄(약 28).
        let headerHeight: CGFloat = 66
        let dividerHeight: CGFloat = 1
        let rowHeight: CGFloat = 54
        let outerPadding: CGFloat = 32 + 28
        // 열 개수는 팝오버 최소 폭 360 기준(`BookGridPicker.columns`와 같은 계산)으로 5열 추정. 더 넓게 뜨면
        // 실제 줄 수는 줄어 추정치가 여유 쪽으로만 어긋난다.
        let columnsEstimate = 5
        let rows = Int(ceil(Double(book.chapterCount) / Double(columnsEstimate)))
        let gridHeight = min(CGFloat(rows) * rowHeight + outerPadding, 560)
        return headerHeight + dividerHeight + gridHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // iOS: 제목은 책 이름, "장 선택"은 아래 구역 라벨로 나눈다(구절 레이어 통일안). 머리 자체가 아래 선을 그린다.
            PickerHeaderBar(title: book.displayName, onBack: onBack)

            if book.chapterCount < 1 {
                Text("\(book.displayName)의 장 정보가 없습니다.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        PickerSectionLabel(title: String(localized: "장 선택"))
                        LazyVGrid(columns: Self.columns, spacing: 10) {
                            ForEach(1...book.chapterCount, id: \.self) { chapter in
                                chapterButton(chapter)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        // [2026-10-29 bookgrid1] 아이패드는 max(추정치, 460)을 이상 크기 측정 때의 하한으로만 쓴다 — 이전 유효 요청값 max(자식 이상 높이, 추정치, 460)과 같고,
        // 가용 높이가 모자라면 팝오버가 받은 높이를 따라 머리(`PickerHeaderBar`)는 남고 아래 `ScrollView`만 줄어든다(`PickerPopoverSizing` 주석).
        // 맥·아이폰은 이전처럼 최소 높이(아이폰은 0).
        .modifier(PickerContentHeight(
            padMinimumIdealHeight: max(estimatedGridHeight, PickerPopoverSizing.padMinimumIdealHeight),
            otherMinHeight: estimatedGridHeight
        ))
    }

    /// 고정 크기 라운드 사각형 버튼. 맥은 강조색 12% 배경 + 35% 테두리(기존 그대로),
    /// iOS는 글자색 라벨 + 현재 장 강조색 채움(`PickerCellStyle`).
    @ViewBuilder
    private func chapterButton(_ chapter: Int) -> some View {
        let isCurrent = chapter == currentChapter
        Button {
            onSelect(chapter)
        } label: {
            Text("\(chapter)")
                .font(PickerFonts.cell)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 52, height: 44)
                .modifier(PickerCellStyle(isCurrent: isCurrent))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isCurrent ? String(localized: "\(chapter)장, 현재 장") : String(localized: "\(chapter)장"))
    }
}

/// 성경 조회 상단바(`BibleTopBar`)의 제목 탭이 여는 책/장 그리드 팝오버 내용 (2026-10-21).
/// `BookGridPicker`/`PickerPopoverSizing`이 이 파일 전용(private)이라 같은 파일에서 얇게 감싸 내보낸다.
/// 현재 책의 장 그리드로 바로 시작하고 "책 목록"으로 다른 책을 고를 수 있다 — 장 이동 막대의 책 버튼 팝오버와 같은 내용.
struct BookChapterGridPopover: View {
    let books: [Book]
    let selectedBook: Book
    let selectedChapter: Int
    var onSelect: (Book, Int) -> Void

    var body: some View {
        BookGridPicker(books: books, initialBook: selectedBook, currentBook: selectedBook, currentChapter: selectedChapter, onSelect: onSelect)
            .modifier(PickerPopoverSizing())
    }
}
