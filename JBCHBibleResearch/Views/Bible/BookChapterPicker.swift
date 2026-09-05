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
    /// [2026-09-04 신설, 같은 날 재설계] 사용자 요청 — "아이폰 [성경]의 상단
    /// 메뉴 - 성경 장 위치 이동관련 메뉴 - 크기 조정 필요." 첫 시도(책/장
    /// 버튼에 텍스트+캡슐 배경, 검색창만 살짝 축소)는 실기기에서 "창 2장"
    /// 텍스트가 좁은 폭에 눌려 3줄로 줄바꿈되며 찌그러지는 문제로 나타났고,
    /// 사용자가 이어서 (1) 개별 버튼 사이 공백 없이 하나의 이어진 막대로,
    /// (2) 책 아이콘은 아이콘만 남기고 "창2장" 표시는 검색창 쪽으로,
    /// (3) "이동" 텍스트를 아이콘+다른 색으로 바꿔달라고 구체적으로 요청해
    /// `compactBarBody`(아래)로 완전히 다시 짰다. true면(현재는
    /// `BibleReadingView.compactChapterNavigationBar`가 아이폰에서만 넘김)
    /// `body`가 `compactBarBody`를, false면(기본값) 기존 `standardBody`를
    /// 그대로 쓴다 — 기본값이 false라 다른 호출부(`CrossReferenceTargetPicker`,
    /// `DocumentsHomeView`, `WordNoteHomeView`, `WordSummaryEditorView`,
    /// `SearchView`)는 이 파라미터 자체를 안 넘겨 전혀 영향받지 않는다.
    /// `onSelect` 바로 앞에 둔 이유는 위 "onSelect가 항상 마지막 프로퍼티로
    /// 남아야" 주석과 같다 — 트레일링 클로저 매칭이 깨지지 않게.
    var compactTouchTargets: Bool = false
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
        Group {
            if compactTouchTargets {
                compactBarBody
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

                // [2026-09-05 수정] 사용자 보고(맥OS) — "성경 장 이동 및
                // 검색 영역 - 아이폰 디자인을 참고하여 일관성을 갖추고
                // ... 수정하라." 아래 `compactBarBody`가 이미 쓰는 "이동"
                // 아이콘 버튼(강조색 원 배경 + 흰 화살표 아이콘)과 정확히
                // 같은 모양으로 바꿔, 텍스트 버튼("이동")보다 이 그룹의
                // "주된 실행 동작"임이 더 뚜렷이 드러나게 한다(새 스타일
                // 발명 대신 같은 파일 안의 기존 패턴 재사용).
                Button(action: submitFreeText) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("이동")
            }
        }
    }

    /// [2026-09-04 신설] 위 `compactTouchTargets` 주석 참고 — 아이폰 전용
    /// "이어진 막대" 레이아웃. `BibleReadingView.compactChapterNavigationBar`가
    /// 이 3개 요소(책 아이콘·검색창·이동 아이콘)를 자신의 다른 4개 버튼과
    /// 함께 하나의 캡슐 배경 안에 넣으므로, 여기서는 개별 배경을 주지 않고
    /// spacing 0의 얇은 구분선만 둔다.
    private var compactBarBody: some View {
        HStack(spacing: 0) {
            Button {
                isGridPresented = true
            } label: {
                Image(systemName: "book")
            }
            .buttonStyle(.plain)
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
            .popover(isPresented: $isGridPresented) {
                BookGridPicker(books: books, initialBook: selectedBook) { book, chapter in
                    onSelect(book, chapter)
                    isGridPresented = false
                }
                .frame(minWidth: 360, minHeight: 460)
            }

            CompactBarDivider()

            // [2026-09-04 신설] 사용자 요청 — "책모양 아이콘의 현재 성경 장을
            // 표시하는 텍스트는 약어로 텍스트 박스에 넣도록. 직접텍스트를
            // 입력하여 나온 결과도 텍스트 박스에 그대로 남기도록." 이 검색창
            // 하나가 "현재 위치 표시"와 "직접 검색 입력"을 겸한다 — 포커스가
            // 없을 때는 아래 `syncFreeTextToCurrentPositionIfNeeded()`가 항상
            // 현재 선택된 책/장의 약어("창2" 등)로 채우고, 포커스가 있는
            // (타이핑 중인) 동안에는 건드리지 않는다.
            //
            // [2026-09-04 수정] 사용자 요청 — "'장'이라는 텍스트가 자동으로
            // 붙는데, 불편함. ... '장'이라는 텍스트를 보여주기 위해서
            // 지울 필요가 없는 텍스트로 고정할 수 있는 방법을 제안바람.
            // 대신 텍스트 입력란이 너무 좁아지면 안됨." `freeText` 자체
            // ("창2" 등, 아래 `syncFreeTextToCurrentPositionIfNeeded`/
            // `submitFreeText` 참고)에는 더 이상 "장"을 넣지 않는다 — 대신
            // 바로 옆에 편집 불가능한 고정 `Text("장")`을 따로 붙여, 다른
            // 책/장을 입력하려 할 때 의미 없는 "장" 글자부터 지울 필요가
            // 없게 했다. 포커스 중(사용자가 직접 타이핑 중, "요3:16"처럼
            // "장"이 안 맞는 입력도 나올 수 있음)에는 이 라벨을 숨긴다 —
            // 숨겨진 만큼 입력란이 넓어져 "텍스트 입력란이 좁아지면 안됨"도
            // 함께 만족한다.
            HStack(spacing: 2) {
                TextField("예:창세기1, 요3, 요3:16", text: $freeText)
                    .font(.title3)
                    .lineLimit(1)
                    .textFieldStyle(.plain)
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
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            // [2026-09-04 추가] 사용자 요청 — "이 검색창의 텍스트가 '|' 세로
            // 바와 딱 붙지 않게 왼쪽 패딩? 여백?을 줄 수 있는가?" 왼쪽
            // `CompactBarDivider()` 바로 옆에 텍스트가 밀착돼 보이는 문제라,
            // 이 HStack 전체(TextField + "장" 라벨)에 왼쪽 여백만 추가한다 —
            // 오른쪽은 원래도 붙지 않으므로(다음이 CompactBarDivider) 건드릴
            // 필요 없음.
            .padding(.leading, 8)
            .frame(minWidth: 50, maxWidth: .infinity, minHeight: 44)

            CompactBarDivider()

            // [2026-09-04 신설] 사용자 요청 — "'이동'이라는 텍스트도 관련
            // 아이콘으로 바꾸고, 색을 다르게 할 것 - 디자인 가이드에 맞춰서."
            // `ActionBarCircularIconModifier`(BibleReadingView.swift)의
            // `isProminent` 분기가 이미 쓰는 것과 같은 처리(진한 accentColor
            // 배경 + 흰 아이콘)를 그대로 재사용해, 이 버튼이 이 그룹의 "주된
            // 실행 동작"임을 시각적으로 구분한다.
            Button(action: submitFreeText) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
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
            // [2026-09-04 신설] 사용자가 검색창을 탭했다가(포커스 획득) 아무
            // 것도 제출하지 않고 다른 곳을 탭해 포커스를 잃으면(focused ==
            // false), 입력하다 만 텍스트가 "현재 위치"인 것처럼 남아있으면
            // 안 되므로 다시 현재 위치 약어로 되돌린다.
            if !focused {
                syncFreeTextToCurrentPositionIfNeeded()
            }
        }
    }

    /// [2026-09-04 신설] `compactBarBody` 전용 — 포커스가 없을 때 검색창을
    /// 항상 현재 선택된 책/장의 약어로 채운다. 포커스 중(사용자가 직접
    /// 타이핑하는 동안)에는 아무것도 하지 않아 입력을 방해하지 않는다.
    private func syncFreeTextToCurrentPositionIfNeeded() {
        guard !isFreeTextFocused else { return }
        // [2026-09-04 수정] 사용자 요청 — "장"이 검색창 텍스트 자체에 있으면
        // 매번 지우고 다시 입력해야 해 불편하다 — "장"은 이제 별도 고정
        // 라벨(위 `compactBarBody`의 `Text("장")`)이 맡고, 이 텍스트에는
        // 책/장 약어만 남긴다.
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
        // [2026-09-04 수정] 사용자 요청 — "직접텍스트를 입력하여 나온 결과도
        // 텍스트 박스에 그대로 남기도록." 컴팩트 모드(아이폰)는 이 검색창이
        // "현재 위치 표시"도 겸하므로(위 `compactBarBody`/`syncFreeTextToCurrentPositionIfNeeded`
        // 참고), 방금 이동한 결과의 약어로 즉시 채운다 — 부모의
        // selectedBook/selectedChapter가 다음 렌더에서 갱신되어 `onChange`가
        // 다시 같은 값을 채우기 전에도 화면이 비어 보이지 않는다. 기존
        // 호출부(컴팩트가 아닌 표준 모드)는 원래 동작(빈 문자열로 비우기)을
        // 그대로 유지한다.
        if compactTouchTargets {
            // [2026-09-04 수정] 위 `syncFreeTextToCurrentPositionIfNeeded`와
            // 같은 이유로 "장"을 붙이지 않는다 — 고정 라벨이 대신 보여준다.
            freeText = "\(match.book.abbreviation.first ?? match.book.nameKo)\(max(1, chapter))"
        } else {
            freeText = ""
        }
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

/// [2026-09-04 신설] `compactBarBody`(위) 전용 — 이어진 막대 안에서 요소
/// 사이를 나누는 얇은 구분선. 전체 배경(캡슐)은 `BibleReadingView.
/// compactChapterNavigationBar`가 이 뷰 바깥에서 주므로, 여기서는 세로선
/// 하나만 그린다.
private struct CompactBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
    }
}

/// [2026-09-04 신설] 사용자 요청 — "다른 서브기능(책갈피 리스트, 히스토리,
/// 번역본선택...)의 레이아웃(버튼 배치, 리스트 유형, 색상)도 디자인이
/// 전체적으로 통일 될 수 있도록 검토할 것." 이 파일의 책/장 선택 팝오버만
/// 지금까지 제목·닫기 버튼이 아예 없었다(검색창/그리드가 바로 시작) —
/// `BookmarkListPopover.header`/`TranslationPickerPopover.header`와 정확히
/// 같은 모양(제목 `.headline` + 우측 상단 원형 `xmark.circle.fill` 닫기
/// 버튼, 같은 패딩 14/10)으로 맞춘 공용 헤더다. `onBack`을 넘기면(장 그리드
/// 단계) 제목 왼쪽에 뒤로가기 셰브런도 함께 보여준다 — `BibleReadingHistorySheet`
/// 처럼 이 팝오버 전체를 `NavigationStack`으로 바꾸지는 않았다(그 파일은
/// `.sheet`로 뜨는 전체화면 시트라 네이티브 `.navigationTitle`+툴바가 맞는
/// 반면, 이건 계속 `.popover`로 뜨는 작은 팝업이라 기존 `pendingBook` 토글
/// 구조를 그대로 두고 헤더만 공용 컴포넌트로 뺀 것 — 근거 없는 구조 변경
/// 방지).
private struct PickerHeaderBar: View {
    let title: String
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                // [2026-09-04 수정] 사용자 보고 — "'<' 성경을 선택하는
                // 아이콘이 작아서 터치하기가 어려움." 아이콘 자체(`.body`
                // 크기)만큼만 탭 영역이 잡혀 있었다 — `JoinedNavIconButtonModifier`
                // (BibleReadingView.swift, 아이폰 상단 이동 막대의 아이콘
                // 버튼들과 같은 원칙)처럼 아이콘은 그대로 두고 보이지 않는
                // 탭 영역만 HIG 최소치(44×44pt)로 넓힌다 — 시각적 위치/
                // 크기는 그대로다.
                // [2026-09-05 수정] 사용자 보고(맥OS) — "'<' 성경을
                // 선택하는 아이콘이 작아서 터치하기가 어려움"(위 44×44 안 보이는
                // 탭 영역만으로는 부족했다는 재보고). 마우스로 클릭하는
                // macOS에서는 트랙패드/터치와 달리 목표를 "보고" 조준하므로,
                // 탭 영역만 넓혀서는 클릭하기 쉬워 보이지 않는다 — 이 팝오버가
                // 이미 쓰는 `bookCircleButton`/`chapterButton`(아래)과 같은
                // "강조색 12% 원 배경 + 35% 테두리" 언어를 그대로 재사용해,
                // 실제로 보이는 클릭 영역 자체를 키운다(새 스타일 발명 대신
                // 기존 패턴 재사용 — 근거 없는 리팩토링 방지).
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.accentColor.opacity(0.12)))
                        .overlay(Circle().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
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
            // [2026-09-04 수정] 사용자 보고 — "닫기버튼도 작아서 터치가
            // 어려움." 위 뒤로가기 버튼과 같은 이유로 탭 영역만 44×44pt로
            // 넓힌다.
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
        // [2026-09-04 수정] 사용자 보고 — "상단에 여백을 조금 주어서 위에
        // 딱 붙어있는 느낌이 없도록 수정할 것." 기존엔 위아래 같은 값
        // (`.padding(.vertical, 10)`)이라 팝오버 맨 위 모서리와 버튼 사이에
        // 여유가 거의 없었다 — 위쪽만 더 띄운다(아래는 `Divider()`가 바로
        // 이어지므로 그대로 둔다). 좌우 패딩은 44pt 탭 영역을 더한 만큼
        // 버튼이 시각적으로 더 안쪽으로 들어와 보이지 않도록 14→10으로
        // 살짝 줄였다(버튼 자체의 보이는 아이콘 위치는 그대로, 탭 영역만
        // 늘어난 것과 맞춘 조정).
        .padding(.top, 16)
        .padding(.bottom, 10)
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
            // [2026-09-04 신설] 사용자 요청 — "화면 레이아웃도 디자인 가이드를
            // 충분히 참고하여 수정할 것." 위 `PickerHeaderBar` 참고 — 이
            // 팝오버도 다른 두 팝오버(책갈피/번역본 선택)와 같은 제목+닫기
            // 버튼 헤더를 갖춘다.
            VStack(alignment: .leading, spacing: 0) {
                PickerHeaderBar(title: "책 선택")
                Divider()
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
    ///
    /// [2026-09-04 수정] 사용자 요청 — "동그란 버튼안의 텍스트가 좀더
    /// 선명하게 눈에 잘 띌 수 있도록 수정할 것." 텍스트가 색 지정 없이
    /// 기본(`.primary`)으로만 그려지고 있어, 연한 액센트 틴트(0.12) 원 배경
    /// 위에서 뚜렷한 색 대비 없이 흐릿해 보였다 — 굵게(`.semibold`) + 이
    /// 버튼 자체의 강조색(`Color.accentColor`)으로 텍스트 색을 명시해, 원
    /// 배경·테두리와 한 벌로 보이는 또렷한 "강조색 텍스트" 버튼으로
    /// 바꿨다(아래 `ChapterGrid.chapterButton`도 같은 처리로 통일).
    private func bookCircleButton(_ book: Book) -> some View {
        Button {
            pendingBook = book
        } label: {
            // [2026-09-05 수정] 사용자 보고(맥OS) — "'책 선택' 기능에서 각
            // 성경별 약어 버튼의 텍스트를 조금 더 크고 명확하게 표현하라."
            // `.callout`(16pt)에서 `.title3`(20pt)로 올리고 굵기도
            // `.bold`로 강화한다 — 원 지름(52pt)/`minimumScaleFactor`는
            // 그대로 둬 "삼상"처럼 2글자 약어도 필요시 자동 축소로 안전하게
            // 들어간다.
            Text(book.abbreviation.first ?? book.nameKo)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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

    /// [2026-09-04 수정] 사용자 보고 — "책모양아이콘 탭 -> 장 목록: 현재
    /// 2자리 숫자까지는 원활하게 표시되나 3자리 숫자는 3번째 숫자가 자동
    /// 줄바꿈되는 상황, 시편 같은 경우 3자리 장 숫자가 있음." 원인: 예전
    /// `Button("\(chapter)").buttonStyle(.bordered)`는 크기를 직접 정하지
    /// 않고 `LazyVGrid`가 계산한 셀 폭에 맞춰 자동으로 잡히는데, 그 폭이
    /// "150" 같은 3자리 숫자가 한 줄에 들어가기엔 좁을 수 있었고
    /// `.lineLimit`/`.fixedSize` 보호도 없어 줄바꿈됐다 — 아래
    /// `chapterButton`처럼 `bookCircleButton`과 같은 원칙(고정 크기 도형 +
    /// `.lineLimit(1)`)으로 바꿔 원천적으로 줄바꿈될 수 없게 했다. 다만
    /// 사용자 제안대로("꼭 원 아이콘이 아니어도 됨 — 라운드 사각형도
    /// 고려") 원은 유지하지 않았다 — 3자리 숫자를 원 안에 넣으려면 지름을
    /// 키워야 하는데, 그러면 1~2자리 장이 대부분인 다른 책들에서 불필요하게
    /// 커 보인다. 라운드 사각형은 폭만 살짝 넓혀(52pt) 3자리를 여유 있게
    /// 담고, 높이는 그대로(44pt, HIG 최소 탭 영역) 둘 수 있다.
    private static let columns = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 10)]

    var body: some View {
        // [2026-09-04 신설] 사용자 요청 — "다른 서브기능의 레이아웃도
        // 디자인이 통일되도록 검토할 것." 기존 "책 목록" 텍스트 백 버튼을
        // 위 `PickerHeaderBar`(제목 + 뒤로가기 셰브런 + 닫기 버튼)로 바꿔,
        // `BookGridPicker`의 새 헤더와 같은 모양으로 맞췄다.
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
    }

    /// [2026-09-04 신설] 위 `body`/`columns` 상단 주석 참고 — 고정 크기
    /// 라운드 사각형 버튼. `bookCircleButton`과 같은 색 언어(강조색 12%
    /// 배경 + 35% 테두리 + 강조색 굵은 텍스트)를 그대로 재사용해 이 팝오버
    /// 안에서 "책 선택"과 "장 선택" 두 단계가 하나의 일관된 스타일로
    /// 보이게 한다.
    private func chapterButton(_ chapter: Int) -> some View {
        Button {
            onSelect(chapter)
        } label: {
            Text("\(chapter)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 52, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
