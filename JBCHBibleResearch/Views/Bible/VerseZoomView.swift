//
//  VerseZoomView.swift
//  JBCHBibleResearch
//
//  "구절 확대보기"(메모하기) 화면 — 구간 주석(형광펜/메모/관주)의 선택 UX.
//  평소 읽기 화면의 "절 전체 탭 → 선택"(복사)은 그대로 두고, 하단 액션바 버튼으로 이 화면을 연다.
//  주석은 번역본 하나에 종속되므로(같은 절도 번역본마다 단어가 다르다) 여러 번역본이 떠 있으면 상단에서 대상 번역본을 고른다.
//  "표시 모드"(`AnnotatedVerseFlowView`, 순수 SwiftUI)와 "선택 모드"(`SelectableVerseTextView`, 드래그로 새 구간을 고를 때만)를 분리했다.
//  형광펜/메모 버튼으로 선택 모드에 들어가 범위를 고르고 색/스타일을 적용하면 표시 모드로 돌아온다
//  (배경은 `VerseAnnotationRenderer.swift`/`SelectableVerseTextView.swift` 상단 주석 참고).
//  관주가 걸린 표현에는 주황 밑줄이 자동으로 붙는다(수동 밑줄 버튼은 없다).
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct VerseZoomView: View {
    let verseNumber: Int
    let columns: [BibleReadingViewModel.ColumnState]
    let viewModel: BibleReadingViewModel
    /// 구간 메모 생성 직후와 기존 구간 메모 아이콘 선택 시 모두 "이 메모를 편집기 시트로 열어라"는 같은 의미라
    /// 콜백 하나로 겸한다. 호출부(BibleReadingView)가 "메모 작성" 시트 흐름(`memoBeingCreated`)에 연결한다.
    var onOpenPhraseMemo: (UserMemo) -> Void
    /// 기존 관주 목록에서 대상을 골랐을 때 그 책/장으로 이동한다(`TranslationColumnView.onSelectCrossReferenceTarget`와 동일).
    var onJumpToCrossReference: (BibleVerseRef) -> Void
    /// "관련 내용" 목록에서 하나를 고르면 호출된다 — 호출부가 메모는 편집기 시트로, 연구문서는 PDF 검색+이동 창으로 연다.
    var onSelectVerseMention: (VerseMention) -> Void
    /// "원문 정보로 전환" 콜백. 호출부가 이 시트를 닫고 원문 정보 시트를 여는 순서를 책임진다
    /// (한 화면이 시트 두 개를 동시에 띄울 수 없다).
    var onSwitchToOriginalTextInfo: () -> Void
    /// 이전/다음 구절 이동. 이동 자체(장/책 경계 넘기, 선택 절 갱신)는 뷰모델 책임이고 이 화면은
    /// 버튼 활성 여부와 탭 콜백만 받는다. 기본값은 값을 안 넘기는 호출부용 — 그 경우 화살표는 항상 비활성.
    var onNavigateToPreviousVerse: () -> Void = {}
    var onNavigateToNextVerse: () -> Void = {}
    var canGoToPreviousVerse: Bool = false
    var canGoToNextVerse: Bool = false
    /// true로 열면 화면이 뜬 직후(`onAppear`) `beginComposingPersonalNote()`를 자동 호출해, 안쪽 "개인 묵상" 버튼을
    /// 누른 것과 같은 상태(목록 맨 위에 새 항목 입력칸)를 만든다.
    /// `let`으로 한 번만 받으면 `.sheet` 콘텐츠 클로저 평가 시점과 `onAppear` 시점이 어긋날 수 있어
    /// `@Binding`으로 받아 `onAppear`에서 "그 순간의" 최신 값을 읽는다(`PhraseNoteEditorPopover`와 같은 이유).
    @Binding var autoPresentPersonalNoteEditor: Bool

    @Environment(\.dismiss) private var dismiss
    private var settings: UserSettingsStore { .shared }
    @State private var selectedColumnID: UUID
    @State private var selectedRange = NSRange(location: 0, length: 0)
    /// 표시 모드(false)/선택 모드(true) 전환. 형광펜/메모 버튼이 true로 바꾸고, 스타일 적용 또는 취소 시 false로 돌아간다.
    @State private var isSelecting = false
    @State private var isCrossReferencePickerPresented = false
    @State private var isVerseMentionPopoverPresented = false
    /// "메모"(드래그 표현 부연설명) 편집 팝오버 표시 여부 — 새로 만들기/수정 구분은 `editingPhraseNote`(nil이면 새로 만들기).
    @State private var isPhraseNoteEditorPresented = false
    /// 개인 묵상 인라인 입력칸 — 켜지면 `personalNoteList` 맨 위에 입력칸 카드를 그린다.
    /// 항상 "새 항목 만들기" 전용(수정 미지원, 자동저장 없음). 텍스트는 `newPersonalNoteText`에만 담겨 있다가
    /// "등록" 버튼을 눌러야 `BibleReadingViewModel.createPersonalNote`로 저장된다.
    @State private var isComposingPersonalNote = false
    @State private var newPersonalNoteText = ""
    /// 입력칸이 열린 뒤 포커스를 잃으면(`body`의 `.onChange`) 아직 등록되지 않은 입력칸은 초안을 버리고 닫는다(저장 안 됨).
    /// "등록" 버튼은 먼저 `isComposingPersonalNote`를 false로 만들어 두므로(`commitNewPersonalNote()`) 포커스 상실과 겹쳐도 중복 저장되지 않는다.
    @FocusState private var isNewPersonalNoteFieldFocused: Bool
    @State private var editingPhraseNote: VersePhraseNote?
    /// 메모 팝오버를 "열기로 결정하는 순간"의 선택 범위/텍스트 스냅샷. 팝오버가 뜨며 텍스트뷰가 first responder를 잃으면
    /// 선택이 해제되어 `selectedRange`가 (0, 0)으로 리셋될 수 있다(델리게이트 콜백이 비동기라 팝오버가 열린 뒤에 일어남).
    /// 그래서 팝오버의 표시(anchorText)와 저장(addPhraseNote)은 이 스냅샷만 쓴다.
    @State private var editingAnchorRange = NSRange(location: 0, length: 0)
    @State private var editingAnchorText: String = ""
    /// 표시 영역의 실제 폭 — 줄바꿈 계산(`VerseAnnotationRenderer.lineRanges`)과 선택 모드 텍스트뷰 폭에 쓴다.
    /// `GeometryReader`로 콘텐츠를 감싸면 높이가 화면 전체로 늘어나므로, `onGeometryChange`(iOS 17+/macOS 14+)로 크기만 관찰한다.
    @State private var scrollWidth: CGFloat = 320
    /// 표시 영역의 실제 높이 — `scrollWidth`와 함께 "폭 > 높이면 가로"로 방향을 판정한다
    /// (`UIDevice.orientation` 대신; 이 화면은 거의 전체 화면 시트라 화면 방향과 사실상 일치).
    @State private var scrollHeight: CGFloat = 480

    init(
        verseNumber: Int, columns: [BibleReadingViewModel.ColumnState], viewModel: BibleReadingViewModel,
        onOpenPhraseMemo: @escaping (UserMemo) -> Void,
        onJumpToCrossReference: @escaping (BibleVerseRef) -> Void,
        onSelectVerseMention: @escaping (VerseMention) -> Void,
        onSwitchToOriginalTextInfo: @escaping () -> Void,
        onNavigateToPreviousVerse: @escaping () -> Void = {},
        onNavigateToNextVerse: @escaping () -> Void = {},
        canGoToPreviousVerse: Bool = false,
        canGoToNextVerse: Bool = false,
        autoPresentPersonalNoteEditor: Binding<Bool> = .constant(false)
    ) {
        self.verseNumber = verseNumber
        self.columns = columns
        self.viewModel = viewModel
        self.onOpenPhraseMemo = onOpenPhraseMemo
        self.onJumpToCrossReference = onJumpToCrossReference
        self.onSelectVerseMention = onSelectVerseMention
        self.onSwitchToOriginalTextInfo = onSwitchToOriginalTextInfo
        self.onNavigateToPreviousVerse = onNavigateToPreviousVerse
        self.onNavigateToNextVerse = onNavigateToNextVerse
        self.canGoToPreviousVerse = canGoToPreviousVerse
        self.canGoToNextVerse = canGoToNextVerse
        self._autoPresentPersonalNoteEditor = autoPresentPersonalNoteEditor
        _selectedColumnID = State(initialValue: columns.first?.id ?? UUID())
    }

    private var currentColumn: BibleReadingViewModel.ColumnState? {
        columns.first { $0.id == selectedColumnID }
    }

    private var verseText: String {
        currentColumn?.verses.first { $0.verse == verseNumber }?.content ?? ""
    }

    private var hasSelection: Bool { selectedRange.length > 0 }

    /// 글꼴 "종류"는 환경설정의 `UserSettingsStore.bibleFontName`을 따르되, 크기는 `bibleBodyFontSize`를 추종하지 않고 고정값을 쓴다 —
    /// 본문 크기 설정에 따라 줄바꿈·메모 박스 배치 계산이 흔들리는 것을 막기 위함.
    private var bibleFont: PlatformFont {
        let settings = UserSettingsStore.shared
        // 고정 크기. `targetCharsPerLine`/`effectiveTextWidth`는 글자 수/실측 폭 기준이라 폰트 크기와 별개로 유지된다.
        let size: CGFloat = 19
        guard settings.bibleFontName != "System" else { return .systemFont(ofSize: size) }
        BundledFontRegistrar.ensureAvailable(settings.bibleFontName)
        return PlatformFont(name: settings.bibleFontName, size: size) ?? .systemFont(ofSize: size)
    }

    /// 스크롤 영역의 실제 콘텐츠 폭(패딩 32pt + 여백 20pt 제외). 메모 박스가 화면 안에서 밀릴 수 있는 실제 한계이며,
    /// 성경 본문 줄바꿈 목표 폭(`effectiveTextWidth`)과는 별개로 계산된다(`AnnotatedVerseFlowView.availableWidth` 참고).
    private var availableContentWidth: CGFloat {
        max(scrollWidth - 52, 0)
    }

    private var effectiveTextWidth: CGFloat {
        let sample = "가" as NSString
        let charWidth = sample.size(withAttributes: [.font: bibleFont]).width
        // 성경 본문 줄바꿈 목표 폭 — "가" 23자 폭으로 제한해 읽기 좋은 줄 길이를 유지한다. 한글 절은 글자 수 기준이라 폭과 무관하고,
        // 라틴/혼합 절은 `VerseAnnotationRenderer.measuredLineRanges`가 이 폭으로 TextKit 측정한다(선택 모드도 같은 폭).
        // 23은 `targetCharsPerLine`과 연동되지 않는 독립 고정값이다.
        let idealWidth = charWidth * 23
        return idealWidth > 0 ? min(availableContentWidth, idealWidth) : availableContentWidth
    }

    /// 세로/가로 모드별 줄바꿈 글자 수 구분용 판정 — 아이폰만 대상(`userInterfaceIdiom == .phone`).
    private var isPhonePortrait: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && scrollHeight > scrollWidth
        #else
        false
        #endif
    }

    /// 줄바꿈 목표 글자 수 — 아이폰 세로 18자, 그 외 20자. 그 지점 이후 첫 띄어쓰기에서 줄바꿈하며,
    /// 알고리즘은 `VerseAnnotationRenderer.koreanLineRanges`(`firstSpaceIndex`)를 재사용한다. 메모 박스 폭 계산(`effectiveTextWidth`)과는 무관.
    private var targetCharsPerLine: Int {
        isPhonePortrait ? 18 : 20
    }

    private var labelColor: PlatformColor {
        #if os(iOS)
        .label
        #else
        .labelColor
        #endif
    }

    /// 읽기 테마 글자색(`settings.bibleTextColor`) 폴백 체인. 커스텀 텍스트 렌더러는 SwiftUI `Color`가 아닌 `PlatformColor`를 받으므로
    /// `PlatformColor(color)`로 변환한다.
    private var effectiveTextColor: PlatformColor {
        settings.bibleTextColor.map { PlatformColor($0) } ?? labelColor
    }

    private var highlights: [VerseHighlight] {
        guard let column = currentColumn else { return [] }
        return viewModel.highlights(translationCode: column.registry.code, verse: verseNumber)
    }

    private var crossReferences: [VerseCrossReference] {
        guard let column = currentColumn else { return [] }
        return viewModel.crossReferences(translationCode: column.registry.code, verse: verseNumber)
    }

    /// 한자 단어 뜻풀이(훈음). 메인 읽기 화면에는 뜻이 나오지 않아 확대보기에서만 볼 수 있다.
    private var hanjaWords: [HanjaWordAnnotation] {
        guard let column = currentColumn else { return [] }
        return viewModel.hanjaWords(translationCode: column.registry.code, verse: verseNumber)
    }

    private var phraseMemos: [UserMemo] {
        guard let column = currentColumn else { return [] }
        return viewModel.phraseMemos(translationCode: column.registry.code, verse: verseNumber)
    }

    /// "메모"(드래그 표현 부연설명) — 특정 번역본의 특정 표현에 종속된다.
    private var phraseNotes: [VersePhraseNote] {
        guard let column = currentColumn else { return [] }
        return viewModel.phraseNotes(translationCode: column.registry.code, verse: verseNumber)
    }

    /// "관련 내용" — 번역본과 무관하게 이 절을 언급하는 메모/연구문서.
    private var verseMentions: [VerseMention] {
        viewModel.verseMentions(verse: verseNumber)
    }

    /// 레이어 머리 제목 — "책이름 장번호장 절번호절"(`navigationTitle`과 같은 계산식).
    private var layerTitle: String {
        "\(currentColumn?.localizedBookChapterLabel ?? "")장 \(verseNumber)절"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 아이패드·아이폰: 시스템 내비게이션 바 대신 시트 안에 직접 그린 머리(닫기 · 세리프 제목) + 조작줄(‹ n절 › · 원문 정보 · 펜/눈)
                // — 2026-10-02 "구절 레이어 통일안". 맥은 아래 하단 버튼줄(`VerseSheetFooter`)을 그대로 쓴다.
                #if os(iOS)
                VerseLayerHeader(title: layerTitle) {
                    Button("닫기") { dismiss() }
                        .buttonStyle(BibleBarButtonStyle(height: 40, cornerRadius: 10, fontSize: 15))
                }
                VerseLayerStrip(
                    verseLabel: "\(verseNumber)절",
                    canGoPrevious: canGoToPreviousVerse, canGoNext: canGoToNextVerse,
                    onPrevious: onNavigateToPreviousVerse, onNext: onNavigateToNextVerse
                ) {
                    Button(action: onSwitchToOriginalTextInfo) {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                    .buttonStyle(BibleBarButtonStyle(kind: .primary, height: 40, cornerRadius: 10, fontSize: 15))
                    .accessibilityLabel("원문 정보로 전환")
                    // 펜/눈동자 토글 — 표시 모드에선 펜(선택 모드 진입), 선택 모드에선 눈동자(표시 모드 복귀 + 선택 해제).
                    // 2026-10-07: 아이콘만이던 토글에 글자를 더했다 — 펜 "편집"(선택 모드 진입) ↔ 눈 "뷰어"(표시 모드 복귀). 글자는 누르면 가는 쪽 모드 이름.
                    Button {
                        isSelecting.toggle()
                        selectedRange = NSRange(location: 0, length: 0)
                    } label: {
                        Label(isSelecting ? "뷰어" : "편집", systemImage: isSelecting ? "eye" : "pencil")
                    }
                    .buttonStyle(BibleBarButtonStyle(kind: isSelecting ? .primary : .secondary, height: 40, cornerRadius: 10, fontSize: 15))
                    .accessibilityLabel(isSelecting ? "글자 선택 끝내기" : "글자 선택 모드")
                }
                #endif
                if columns.count > 1 {
                    translationSwitcher
                    Divider()
                }

                // 말씀구절 + 한자 뜻풀이 + 관주/메모 줄을 하나의 ScrollView 안에 둔다(2026-10-07 아이패드 수정).
                // 예전에는 구절 ScrollView만 늘고 줄어 하단 고정 영역(한자 뜻풀이 등)이 커지면 구절이 한 줄만 남고 구절 안에서만 스크롤됐다.
                // 이제 시트 전체가 함께 스크롤된다. 도구줄(`actionBar`)도 이 안(구절 바로 아래)에 있어 함께 스크롤된다(2026-10-07 목업).
                ScrollView {
                    VStack(spacing: 0) {
                        Group {
                            if isSelecting {
                                // 선택 모드 — 새 구간을 드래그로 고르는 동안만 표시. 표시 모드와 같은 `highlights`/`phraseNotes`를 넘겨
                                // 어느 표현에 무엇이 붙어 있는지는 보이게 한다(메모 박스/화살표는 그리지 않음).
                                // `UITextView`/`NSTextView`는 폭 기준 자동 줄바꿈을 하므로 `.frame(width:)`로 좁혀도 잘리지 않는다.
                                // 표시 모드와 같은 `effectiveTextWidth`를 `containerWidth`로 넘겨야 두 모드의 줄 경계가 일치한다.
                                SelectableVerseTextView(
                                    text: verseText, font: bibleFont, textColor: effectiveTextColor,
                                    containerWidth: effectiveTextWidth, targetCharsPerLine: targetCharsPerLine,
                                    highlights: highlights, phraseNotes: phraseNotes, crossReferences: crossReferences,
                                    hanjaWords: hanjaWords,
                                    selectedRange: $selectedRange
                                )
                                .frame(width: effectiveTextWidth, alignment: .leading)
                            } else {
                                // 표시 모드(평소) — 순수 SwiftUI 렌더링. 형광펜 취소/메모 수정·삭제는 이 뷰의 `.contextMenu`(길게 누르기/우클릭)로 처리된다.
                                // ⚠️ `.frame(width:)`를 씌우지 않는다 — `containerWidth`는 줄 나눔의 "목표"일 뿐이고 한글 절은 글자 수 기준이라
                                // 실제 폭이 이보다 넓거나 좁을 수 있다. 각 줄은 자체 줄바꿈하지 않는 `HStack(spacing: 0)`이라 좁은 frame을 씌우면 잘려 보인다.
                                AnnotatedVerseFlowView(
                                    text: verseText, highlights: highlights, phraseNotes: phraseNotes,
                                    crossReferences: crossReferences, hanjaWords: hanjaWords,
                                    font: bibleFont, textColor: effectiveTextColor, containerWidth: effectiveTextWidth,
                                    availableWidth: availableContentWidth, targetCharsPerLine: targetCharsPerLine,
                                    onRequestRemoveHighlight: { highlight in
                                        viewModel.deleteHighlight(highlight)
                                    },
                                    onRequestEditPhraseNote: { note in
                                        editingPhraseNote = note
                                        presentPhraseNoteEditor()
                                    },
                                    onRequestDeletePhraseNote: { note in
                                        viewModel.deletePhraseNote(note)
                                    }
                                )
                            }
                        }
                        .padding()
                        // 화면이 `effectiveTextWidth`보다 넓으면 남는 공간은 오른쪽에 두고 텍스트 블록은 왼쪽에 붙인다.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 도구줄(형광펜·메모·개인 묵상·관주) — 2026-10-07 목업 결정: 말씀구절 → 도구줄 → 한자 뜻풀이 → 관주 칩 순서.
                        // 예전에는 시트 맨 아래에 고정이었으나 구절에서 멀어, 구절 바로 아래로 올려 시트와 함께 스크롤되게 했다(모든 기기).
                        #if os(macOS)
                        Divider()
                        #endif
                        actionBar
                        // 평소 읽기 화면(`TranslationColumnView.VerseRow`)과 같은 아이콘 + 팝오버/메뉴 조합을 재사용한다(탭 동작도 동일).
                        // 한자 뜻풀이가 있으면 관주/메모 상태줄보다 위에 먼저 그린다.
                        // 개인 묵상/한자/관주/관련 내용이 하나도 없어도 입력칸이 열려 있으면(`isComposingPersonalNote`) 그 입력칸을 보여줄
                        // 섹션이 그려져야 하므로 아래 조건들에 모두 포함한다.
                        if !hanjaWords.isEmpty || !crossReferences.isEmpty || !phraseMemos.isEmpty || !verseMentions.isEmpty || isComposingPersonalNote {
                            Divider()
                            if !hanjaWords.isEmpty {
                                hanjaGlossSection
                                if !crossReferences.isEmpty || !phraseMemos.isEmpty || !verseMentions.isEmpty || isComposingPersonalNote {
                                    Divider()
                                }
                            }
                            if !crossReferences.isEmpty || !phraseMemos.isEmpty || !verseMentions.isEmpty || isComposingPersonalNote {
                                annotationStatusBar
                            }
                        }
                    }
                }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
                    scrollWidth = newSize.width
                    scrollHeight = newSize.height
                }

                // macOS `.sheet`의 `.confirmationAction`/`.cancellationAction` 자리는 버튼 하나만 그려져, 두 번째 버튼을 얹으면
                // (`ToolbarItem`/`ToolbarItemGroup` 모두) 조용히 사라진다(실측). 그래서 macOS만 하단 버튼줄(닫기/원문 정보/펜·눈동자)을
                // 본문에 직접 그린다. iOS/iPadOS 내비게이션 바는 이 제약이 없어 아래 `.toolbar`를 그대로 쓴다.
                // 버튼 규격은 성경 조회 막대와 같은 `BibleBarButtonStyle`(32pt), 줄 바탕·위쪽 선은 `VerseSheetFooter`(VerseSheetChrome.swift).
                // 펜/눈동자 토글은 선택 모드가 켜지면(눈동자) 강조 채움으로 바뀌어 현재 상태가 보인다.
                #if os(macOS)
                VerseSheetFooter {
                    Button("닫기") { dismiss() }
                        .buttonStyle(BibleBarButtonStyle())
                    Spacer(minLength: 0)
                    Button(action: onSwitchToOriginalTextInfo) {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                    .buttonStyle(BibleBarButtonStyle())
                    .help("원문 정보로 전환")
                    Button {
                        isSelecting.toggle()
                        selectedRange = NSRange(location: 0, length: 0)
                    } label: {
                        Label(isSelecting ? "뷰어" : "편집", systemImage: isSelecting ? "eye" : "pencil")
                    }
                    .buttonStyle(BibleBarButtonStyle(kind: isSelecting ? .primary : .secondary))
                    .help(isSelecting ? "글자 선택 끝내기(표시 모드)" : "글자 선택 모드")
                }
                #endif
            }
            // 읽기 테마 배경(테마가 없으면 시스템 기본 배경).
            .background(settings.bibleBackgroundColor ?? Color.clear)
            // "장"을 직접 붙여 "책이름 장번호장 절번호절"로 표시한다(`localizedBookChapterLabel`은 "책이름 장번호"까지만 담는다 —
            // `BibleReadingViewModel.reloadVerses` 참고).
            .navigationTitle("\(currentColumn?.localizedBookChapterLabel ?? "")장 \(verseNumber)절")
            // 아이패드·아이폰은 머리를 본문 안에 직접 그리므로(위 `VerseLayerHeader`) 시스템 내비게이션 바는 숨긴다.
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onChange(of: selectedColumnID) { _, _ in
                selectedRange = NSRange(location: 0, length: 0)
                isSelecting = false
            }
            // 메모하기 레이어가 열린 동안에도 부분 메모·개인 묵상·형광펜을 다시 조회한다.
            // 입력 중인 초안과 선택 범위는 유지한다.
            .onChange(of: CloudSyncMonitor.shared.remoteImportRevision) { _, _ in
                viewModel.refreshAfterRemoteImport()
            }
            .sheet(isPresented: $isCrossReferencePickerPresented) {
                // `CrossReferenceTargetPicker.onSave`는 절 목록(DB 저장용)과 항목별 라벨/개수(표시용, 정제된 문구)를 함께 넘기고,
                // 시트의 "등록된 관주" 섹션(`existingDisplayEntries`)이 그 라벨을 그대로 보여준다.
                // 선택 범위가 있으면 그 텍스트(`anchorText`)와 겹치는 기존 관주(`overlappingCrossReferences`)를, 없으면
                // 이 절에 걸린 관주 전부(절 전체 관주 포함)를 넘긴다. 삭제는 `onDeleteExisting`이 `viewModel.removeCrossReferenceGroup`으로 처리한다.
                CrossReferenceTargetPicker(
                    sourceLabel: crossReferenceSourceLabel,
                    anchorText: hasSelection ? anchorText : nil,
                    existingReferences: hasSelection ? overlappingCrossReferences(for: selectedRange) : crossReferences,
                    onDeleteExisting: { reference, verses in
                        viewModel.removeCrossReferenceGroup(verses, from: reference)
                    }
                ) { targets, entryLabels, entryVerseCounts in
                    guard let column = currentColumn else { return }
                    viewModel.addCrossReference(
                        translationCode: column.registry.code,
                        verse: verseNumber,
                        range: hasSelection ? selectedRange : nil,
                        anchorText: hasSelection ? anchorText : nil,
                        targets: targets,
                        entryLabels: entryLabels,
                        entryVerseCounts: entryVerseCounts
                    )
                    selectedRange = NSRange(location: 0, length: 0)
                    isSelecting = false
                }
            }
            // "메모" 편집 팝오버 — `editingPhraseNote`가 nil이면 새로 만들기, 있으면 수정(표시 모드 박스 탭/컨텍스트 메뉴 "메모 수정").
            // `anchorText`/`isEditing`을 `let` 생성자 인자로 넘기면 같은 값도 성공/실패가 갈려, `$editingPhraseNote`/`$editingAnchorText`를
            // `@Binding`으로 넘겨 `body`가 그릴 때마다 최신 값을 읽게 한다(`PhraseNoteEditorPopover.swift` 상단 주석 참고). `.id(...)`는 만약을 위해 유지.
            .popover(isPresented: $isPhraseNoteEditorPresented) {
                PhraseNoteEditorPopover(
                    editingPhraseNote: $editingPhraseNote,
                    pendingAnchorText: $editingAnchorText,
                    onSave: { text in
                        if let editing = editingPhraseNote {
                            viewModel.updatePhraseNote(editing, noteText: text)
                        } else if let column = currentColumn, editingAnchorRange.length > 0 {
                            viewModel.addPhraseNote(
                                translationCode: column.registry.code, verse: verseNumber,
                                range: editingAnchorRange, anchorText: editingAnchorText, noteText: text
                            )
                        }
                        selectedRange = NSRange(location: 0, length: 0)
                        isSelecting = false
                    },
                    onDelete: { note in viewModel.deletePhraseNote(note) }
                )
                .id(editingPhraseNote?.id.uuidString ?? "new")
            }
            // 개인 묵상은 팝오버 없이 `personalNoteList`가 `isComposingPersonalNote`를 보고 입력칸을 직접 그린다.
            // 바깥 "개인 묵상" 버튼으로 열렸을 때만 화면이 뜨자마자 입력칸을 자동으로 연다(`autoPresentPersonalNoteEditor` 참고).
            .onAppear {
                if autoPresentPersonalNoteEditor {
                    beginComposingPersonalNote()
                }
            }
        }
        #if os(macOS)
        // 본문 글자·목표 줄폭에 맞춰 잡은 창 최소 폭(`bibleFont`/`targetCharsPerLine` 참고).
        .frame(minWidth: 525, minHeight: 420)
        #endif
        // 이전/다음 구절 이동 화살표 — `VerseNavArrowsModifier` 선언부 주석 참고. 맥만 본문 양옆에 띄우고,
        // 아이패드·아이폰은 본문을 가리지 않도록 위쪽 조작줄의 [‹ n절 ›] 묶음으로 옮겼다(2026-10-02).
        #if os(macOS)
        .modifier(VerseNavArrowsModifier(
            canGoPrevious: canGoToPreviousVerse,
            canGoNext: canGoToNextVerse,
            onPrevious: onNavigateToPreviousVerse,
            onNext: onNavigateToNextVerse
        ))
        #endif
    }

    // 앱의 다른 곳(`TranslationPickerPopover.chip(for:)`, `BookChapterPicker`)과 같은 "강조색 배경 15% + 테두리 획" 캡슐 스타일을
    // 재사용한다. 여기는 화면에 떠 있는 번역본 중 하나만 고르므로 다중 선택용 순서 배지 등은 없다.
    private var translationSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(columns) { column in
                    let isSelected = column.id == selectedColumnID
                    // 세 색상을 미리 계산해 둔다 — modifier 체인 안에 삼항연산자+`??`가 여러 번 겹치면 타입 추론이 시간 초과로 컴파일에 실패한다.
                    let labelColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor ?? Color.primary)
                    let fillColor: Color = isSelected ? Color("AccentColor").opacity(0.15) : (settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.12))
                    let strokeColor: Color = isSelected ? Color("AccentColor").opacity(0.5) : (settings.bibleTextColor?.opacity(0.3) ?? Color.secondary.opacity(0.4))
                    Button {
                        selectedColumnID = column.id
                    } label: {
                        Text(column.registry.displayName)
                            .font(isSelected ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(labelColor)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(fillColor))
                            .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(column.registry.displayName)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .accessibilityLabel("번역본")
    }

    // 네 버튼(형광펜/메모/개인 묵상/관주)이 `isSelecting` 기준으로 함께 흐려진다. 개인 묵상/관주도 이에 포함되어
    // 선택 모드 전용이 된다(원래는 드래그 선택과 무관하게 절 전체에 걸 수 있던 기능).
    // 수동 밑줄 버튼(`.mark`)은 없앴다 — 그 주황 밑줄은 관주가 걸린 표현에 자동으로 붙는다(`VerseAnnotationRenderer.buildLines`의 `hasCrossReference`).
    // `VerseHighlightStyle.mark` 케이스와 렌더링 분기는 기존 레거시 데이터 표시용으로 남겼고 새로 만드는 진입점은 없다.
    #if os(macOS)
    /// macOS 하단 도구 줄 — 형광펜 색 점 상자 + 메모/개인 묵상/관주 72×56 타일(목업 결정, `VerseSheetChrome.swift`).
    /// 선택 모드가 꺼지면 모든 도구를 38%로 흐리게 하고 누를 수 없게 둔다(예전 35%와 같은 의도).
    private var actionBar: some View {
        let textColor: Color = settings.bibleTextColor ?? Color.primary
        return HStack(spacing: 8) {
            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    ForEach(HighlightColorTag.allCases) { tag in
                        Button {
                            handleHighlightTap(tag)
                        } label: {
                            Circle()
                                .fill(tag.swiftUIColor)
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(textColor.opacity(0.38), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    }
                }
                Text("형광펜")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, 12)
            .modifier(VerseToolBoxChrome())
            .opacity(isSelecting ? 1 : BibleBarMetrics.disabledOpacity)

            Rectangle()
                .fill(textColor.opacity(0.22))
                .frame(width: 1, height: 32)

            toolTile(title: "메모", systemImage: "text.bubble") {
                beginPhraseNoteFromSelection()
            }
            toolTile(title: "개인 묵상", systemImage: "note.text") {
                beginComposingPersonalNote()
            }
            // 관주 버튼은 항상 새로 만들기 시트(`CrossReferenceTargetPicker`)를 열고, 겹치는 기존 관주는 `existingReferences`로
            // 시트에 넘겨 그 안에서 보여준다(아래 `.sheet` 참고).
            toolTile(title: "관주", systemImage: "link") {
                isCrossReferencePickerPresented = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .disabled(!isSelecting)
    }

    private func toolTile(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 19))
                Text(title)
            }
        }
        .buttonStyle(VerseToolTileStyle())
    }
    #endif

    /// 형광펜 색 점을 눌렀을 때 — 선택 범위가 있으면 그 색으로 칠하고, 없으면 선택 모드로 들어간다(기존 동작 그대로).
    private func handleHighlightTap(_ tag: HighlightColorTag) {
        if hasSelection {
            applyHighlight(colorTag: tag)
        } else {
            isSelecting = true
        }
    }

    /// 메모 버튼 동작(기존 클로저 본문을 그대로 옮김). 선택 범위와 겹치는 기존 메모가 있으면(`existingPhraseNote(overlapping:)`) 중복 등록하지 않고
    /// 그 메모를 편집 모드로 연다. 팝오버를 열기로 결정하는 이 순간 `selectedRange`/`anchorText`를 `editingAnchorRange`/`editingAnchorText`에
    /// 스냅샷으로 떠 둔다(상태 선언부 주석 참고). 앞뒤 공백은 `trimmedRange`로 뺀다.
    private func beginPhraseNoteFromSelection() {
        let trimmed = trimmedRange(selectedRange, in: verseText)
        guard trimmed.length > 0 else {
            isSelecting = true
            return
        }
        let trimmedText = (verseText as NSString).substring(with: trimmed)
        let existing = existingPhraseNote(overlapping: trimmed)
        editingPhraseNote = existing
        editingAnchorRange = trimmed
        editingAnchorText = trimmedText
        presentPhraseNoteEditor()
    }

    #if os(iOS)
    /// 아이패드·아이폰 하단 도구 줄 — 형광펜 색 점 상자 + 메모/개인 묵상/관주 44pt 상자, 이름은 상자 바깥 아래(2026-10-02 목업).
    /// 색 점마다 글자색 38% 외곽선을 둬 연한 색이 배경에 묻히지 않게 한다. 선택 모드가 꺼지면 전체를 흐리게(45%) 하고 누를 수 없게 둔다.
    private var actionBar: some View {
        let textColor: Color = settings.bibleTextColor ?? Color.primary
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let dotSize: CGFloat = isPhone ? 21 : 24
        return VerseLayerFooter {
            VerseLayerToolCaption(title: "형광펜") {
                HStack(spacing: isPhone ? 6 : 8) {
                    ForEach(HighlightColorTag.allCases) { tag in
                        Button {
                            handleHighlightTap(tag)
                        } label: {
                            Circle()
                                .fill(tag.swiftUIColor)
                                .frame(width: dotSize, height: dotSize)
                                .overlay(Circle().strokeBorder(textColor.opacity(0.38), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, isPhone ? 8 : 10)
                .verseLayerBox()
            }

            // 선택 범위와 겹치는 기존 메모가 있으면(`existingPhraseNote(overlapping:)`) 중복 등록하지 않고 그 메모를 편집 모드로 연다.
            // 팝오버를 열기로 결정하는 이 순간 `selectedRange`/`anchorText`를 `editingAnchorRange`/`editingAnchorText`에 스냅샷으로 떠 둔다
            // (상태 선언부 주석 참고). 앞뒤 공백은 `trimmedRange`로 뺀다.
            VerseLayerToolCaption(title: "메모") {
                Button {
                    beginPhraseNoteFromSelection()
                } label: {
                    Image(systemName: "text.bubble")
                }
                .buttonStyle(VerseLayerToolButtonStyle())
                .accessibilityLabel("메모")
            }

            VerseLayerToolCaption(title: "개인 묵상") {
                Button {
                    beginComposingPersonalNote()
                } label: {
                    Image(systemName: "note.text")
                }
                .buttonStyle(VerseLayerToolButtonStyle())
                .accessibilityLabel("개인 묵상")
            }

            // 관주 버튼은 항상 새로 만들기 시트(`CrossReferenceTargetPicker`)를 열고, 겹치는 기존 관주는 `existingReferences`로
            // 시트에 넘겨 그 안에서 보여준다(아래 `.sheet` 참고).
            VerseLayerToolCaption(title: "관주") {
                Button {
                    isCrossReferencePickerPresented = true
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(VerseLayerToolButtonStyle())
                .accessibilityLabel("관주")
            }
        }
        .disabled(!isSelecting)
        .opacity(isSelecting ? 1 : 0.45)
    }
    #endif

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 18))
                Text(title).font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(settings.bibleTextColor ?? .primary)
    }

    private var anchorText: String {
        (verseText as NSString).substring(with: selectedRange)
    }

    /// 저장되는 메모 앵커가 앞뒤 공백(스페이스·탭·줄바꿈)을 뺀 알맹이 텍스트와 일치하도록 범위의 시작/끝만 안쪽으로 옮긴다
    /// (길이만 줄어들어 인덱스가 어긋나지 않는다).
    private func trimmedRange(_ range: NSRange, in text: String) -> NSRange {
        let ns = text as NSString
        guard range.length > 0, range.location >= 0, range.location + range.length <= ns.length else {
            return range
        }
        let substring = ns.substring(with: range) as NSString
        var start = 0
        var end = substring.length
        while start < end, let scalar = Unicode.Scalar(substring.character(at: start)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            start += 1
        }
        while end > start, let scalar = Unicode.Scalar(substring.character(at: end - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            end -= 1
        }
        guard start < end else { return NSRange(location: range.location, length: 0) }
        return NSRange(location: range.location + start, length: end - start)
    }

    /// `isPhraseNoteEditorPresented = true`를 데이터 상태 변경과 같은 트랜잭션에서 설정하면, 새 `.id(...)`가
    /// 세션에서 처음 등장할 때 `PhraseNoteEditorPopover.init`이 빈 값/`isEditing: false`를 받는 현상이 로그로
    /// 확인됐다(`.popover`가 첫 표시 프레임에서 커밋 전 스냅샷으로 콘텐츠를 평가하는 것으로 보인다).
    /// 그래서 팝오버 표시만 다음 런루프 틱으로 미뤄, 데이터 상태가 커밋된 뒤 프레젠테이션이 시작되게 한다.
    private func presentPhraseNoteEditor() {
        DispatchQueue.main.async {
            isPhraseNoteEditorPresented = true
        }
    }

    private func existingPhraseNote(overlapping range: NSRange) -> VersePhraseNote? {
        guard range.length > 0 else { return nil }
        let full = verseText as NSString
        return phraseNotes.first { note in
            guard let noteRange = VerseAnnotationRenderer.resolvedRange(
                start: note.rangeStart, end: note.rangeEnd, anchorText: note.anchorText, in: full
            ) else { return false }
            return NSIntersectionRange(noteRange, range).length > 0
        }
    }

    private var crossReferenceSourceLabel: String {
        "\(currentColumn?.localizedBookChapterLabel ?? "")장 \(verseNumber)절"
    }

    private func applyHighlight(colorTag: HighlightColorTag) {
        guard let column = currentColumn, hasSelection else { return }
        viewModel.addHighlight(
            translationCode: column.registry.code, verse: verseNumber, range: selectedRange,
            anchorText: anchorText, style: .highlight, colorTag: colorTag.rawValue
        )
        selectedRange = NSRange(location: 0, length: 0)
        isSelecting = false
    }

    /// 선택 범위와 겹치는 기존 관주를 모두 골라 `CrossReferenceTargetPicker`에 넘긴다. 절 전체 관주(구간 없음)는
    /// 제외하며, `VerseAnnotationRenderer.resolvedRange`의 자가 치유 앵커링으로 저장 오프셋이 본문과 어긋나도
    /// `anchorText`로 다시 찾아 겹침을 판정한다.
    private func overlappingCrossReferences(for range: NSRange) -> [VerseCrossReference] {
        guard range.length > 0 else { return [] }
        let full = verseText as NSString
        return crossReferences.filter { reference in
            guard let start = reference.rangeStart, let end = reference.rangeEnd,
                  let anchor = reference.anchorText,
                  let resolved = VerseAnnotationRenderer.resolvedRange(start: start, end: end, anchorText: anchor, in: full)
            else { return false }
            return NSIntersectionRange(resolved, range).length > 0
        }
    }

    /// "+ 개인 묵상"은 기존 메모를 재사용하지 않고 매번 빈 입력칸을 연다(한 구절에 여러 묵상 가능).
    /// 실제 레코드는 `commitNewPersonalNote()`에서 "등록"을 눌렀을 때만 만든다.
    private func beginComposingPersonalNote() {
        newPersonalNoteText = ""
        isComposingPersonalNote = true
    }

    /// "등록" 버튼 — 눌러야만 저장된다(자동저장 없음, 그 전 입력은 화면 로컬 상태). 수정 API는 없고
    /// 삭제 후 재등록만 지원한다.
    private func commitNewPersonalNote() {
        let trimmed = newPersonalNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.createPersonalNote(verse: verseNumber, contentText: trimmed)
        isComposingPersonalNote = false
        newPersonalNoteText = ""
    }

    /// 입력칸을 저장 없이 닫는다. 포커스 이탈(`body`의 `.onChange(of: isNewPersonalNoteFieldFocused)`)과
    /// "취소" 버튼이 함께 호출하며, `commitNewPersonalNote()`로 이미 닫힌 경우엔 `guard`에서 무시된다.
    private func discardComposingPersonalNote() {
        guard isComposingPersonalNote else { return }
        isComposingPersonalNote = false
        newPersonalNoteText = ""
    }

    // MARK: - 기존 주석 표시 (2026-08-08 추가)

    /// 한자 뜻풀이 영역 — 중복 제거한 단어(`uniqueHanjaWords`)를 2열로 배치하고 글자별 훈음은
    /// `HanjaDictionaryProvider`로 찾는다. `Grid`의 `Divider()`는 행마다 끊겨 연속된 세로선을 만들 수 없어,
    /// `VStack`+`HStack` 위에 `overlay`로 폭 1pt `Rectangle` 하나를 얹어 전체 높이를 관통하게 했다.
    private var hanjaGlossSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 보조 텍스트·구분선은 테마 글자색(`bibleTextColor`) 기반이며, 없으면 시스템 보조색으로 폴백한다.
            Text("한자 뜻풀이")
                .font(.caption2)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            VStack(spacing: 0) {
                ForEach(Array(hanjaGlossRowPairs.enumerated()), id: \.offset) { rowIndex, pair in
                    HStack(spacing: 0) {
                        hanjaGlossCell(pair.0)
                            .frame(maxWidth: .infinity)
                            .padding(.trailing, 8)
                        if let second = pair.1 {
                            hanjaGlossCell(second)
                                .frame(maxWidth: .infinity)
                                .padding(.leading, 8)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .padding(.leading, 8)
                        }
                    }
                    if rowIndex < hanjaGlossRowPairs.count - 1 {
                        // 시스템 `Divider()`는 색을 지정할 수 없어 테마 글자색 기반 `Rectangle`을 쓴다.
                        Rectangle()
                            .fill(settings.bibleTextColor?.opacity(0.3) ?? Color.secondary.opacity(0.3))
                            .frame(height: 1)
                    }
                }
            }
            .overlay {
                // 가로 구분선과 같은 값의 테마 글자색 기반 세로 구분선.
                Rectangle()
                    .fill(settings.bibleTextColor?.opacity(0.3) ?? Color.secondary.opacity(0.3))
                    .frame(width: 1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 중복 제거된 단어를 2개씩 (왼쪽, 오른쪽) 쌍으로 묶는다. 개수가 홀수면 마지막 쌍의 오른쪽은 nil(빈 칸).
    private var hanjaGlossRowPairs: [(HanjaWordAnnotation, HanjaWordAnnotation?)] {
        let words = uniqueHanjaWords
        var rows: [(HanjaWordAnnotation, HanjaWordAnnotation?)] = []
        var index = 0
        while index < words.count {
            let second = index + 1 < words.count ? words[index + 1] : nil
            rows.append((words[index], second))
            index += 2
        }
        return rows
    }

    /// 뜻풀이 칸 하나(중앙 정렬). 한자 옆에 네이버 한자사전 링크 아이콘을 붙인다.
    private func hanjaGlossCell(_ word: HanjaWordAnnotation) -> some View {
        VStack(alignment: .center, spacing: 2) {
            HStack(spacing: 4) {
                // 한글과 한자를 서로 다른 폰트로 한 줄에 잇기 위해 `AttributedString` 구간별 `.font`를 쓴다
                // (`Text + Text`는 macOS 26에서 deprecated, 문자열 보간은 폰트 하나만 적용돼 대안이 안 된다).
                {
                    var koText = AttributedString("\(word.ko) ")
                    koText.font = bibleSwiftUIFont
                    var hanjaText = AttributedString(word.hanja)
                    hanjaText.font = hanjaSwiftUIFont
                    return Text(koText + hanjaText)
                }()
                    // 본문과 같은 테마 글자색 폴백.
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                if let url = naverHanjaDictionaryURL(for: word.hanja) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption2)
                    }
                }
            }
            let infos = HanjaDictionaryProvider.shared.infoList(for: word.hanja)
            if !infos.isEmpty {
                // 음훈은 성경 구절 크기(17pt)보다 작은 16pt.
                Text(infos.map { "\($0.hun)" }.joined(separator: " · "))
                    .font(.system(size: 16))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    /// 네이버 한자사전 검색 URL. `#` 뒤가 클라이언트 라우팅 경로라 `URLComponents.queryItems`를 쓰면 `?`가
    /// 해시 앞으로 조립되므로, 리터럴 문자열에 한자만 퍼센트 인코딩해 끼워 넣는다.
    private func naverHanjaDictionaryURL(for hanja: String) -> URL? {
        guard let encoded = hanja.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://hanja.dict.naver.com/#/search?query=\(encoded)")
    }

    /// 같은 (한글, 한자) 조합이 한 절에 반복되면 오프셋이 달라도 뜻풀이 목적으론 같은 항목이라 첫 등장만 남긴다.
    private var uniqueHanjaWords: [HanjaWordAnnotation] {
        var seen = Set<String>()
        var result: [HanjaWordAnnotation] = []
        for word in hanjaWords where seen.insert("\(word.ko)|\(word.hanja)").inserted {
            result.append(word)
        }
        return result
    }

    /// 확대보기 성경 구절 글꼴(`bibleFont`와 같은 이름, 17pt 고정)의 SwiftUI `Font` 버전.
    private var bibleSwiftUIFont: Font {
        let settings = UserSettingsStore.shared
        guard settings.bibleFontName != "System" else { return .system(size: 17) }
        BundledFontRegistrar.ensureAvailable(settings.bibleFontName)
        return .custom(settings.bibleFontName, size: 17)
    }

    /// 한자 전용 글꼴 — 이름은 `UserSettingsStore.hanjaFontName`을 따르며, 한글(17pt)보다 돋보이도록
    /// 26pt bold를 쓴다.
    private var hanjaSwiftUIFont: Font {
        UserSettingsStore.shared.hanjaFont(size: 26).weight(.bold)
    }

    private var annotationStatusBar: some View {
        // 관주 구절 목록은 길어질 수 있어 줄바꿈을 허용하도록 별도 줄(VStack)로 둔다.
        VStack(alignment: .leading, spacing: 6) {
            // 병합된 구절 구간(`crossReferenceInlineSegments`)마다 독립된 칩 버튼으로 그려 탭하면 해당 구절로 이동한다.
            // 구간이 많으면 자동 줄바꿈되도록 `FlowLayout`을 쓴다. 관주 삭제는 관주 연결 시트의 "등록된 관주" 목록에서 한다.
            if !crossReferences.isEmpty {
                // 부모 `.font(.caption)` 아래지만 관주 칩은 `.body`로 키웠다(다른 자식 라벨은 caption 유지).
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "link.circle.fill")
                        .font(.body)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(crossReferenceInlineSegments.enumerated()), id: \.offset) { _, segment in
                            Button {
                                if let first = segment.verses.first {
                                    onJumpToCrossReference(first)
                                }
                                dismiss()
                            } label: {
                                // 칩 모양 — 모든 플랫폼 테마 강조색 칩(`VerseLinkChipModifier`), 맥만 밑줄 유지.
                                Text(segment.label)
                                    .font(.body)
                                    #if os(macOS)
                                    .underline()
                                    #endif
                                    .modifier(VerseLinkChipModifier())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }

            // 이 절의 개인 묵상 전부를 카드 목록으로 항상 펼쳐 보여준다(`personalNoteList`).
            if !phraseMemos.isEmpty || isComposingPersonalNote {
                personalNoteList
            }

            if !verseMentions.isEmpty {
                HStack(spacing: 16) {
                    Button {
                        isVerseMentionPopoverPresented = true
                    } label: {
                        Label("관련 내용 \(verseMentions.count)개", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isVerseMentionPopoverPresented) {
                        VerseMentionListView(mentions: verseMentions) { mention in
                            isVerseMentionPopoverPresented = false
                            onSelectVerseMention(mention)
                            dismiss()
                        }
                    }

                    Spacer()
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `annotationStatusBar`의 "개인 묵상" 섹션. 카드마다 마지막 수정일과 본문 앞부분(최대 2줄)을 보여준다.
    /// `phraseMemos`는 절 전체 메모와 이 번역본의 표현별 메모를 합친 목록이라 여러 개일 수 있다.
    /// 목록 맨 위에 새 항목 입력칸(`composingPersonalNoteCard`)을 직접 그린다.
    private var personalNoteList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("개인 묵상 \(phraseMemos.count)개", systemImage: "note.text")
            VStack(alignment: .leading, spacing: 6) {
                if isComposingPersonalNote {
                    composingPersonalNoteCard
                }

                ForEach(phraseMemos) { memo in
                    // 목록엔 두 종류가 섞여 있다 — 절 전체 메모(`rangeStart == nil`, 수정 미지원·삭제 후 재등록)와
                    // 표현별 메모(`rangeStart != nil`, 탭하면 `onOpenPhraseMemo`로 편집). 그래서 탭 가능 여부를
                    // `rangeStart` 유무로 가르고, 삭제 버튼은 두 종류 모두에 둔다.
                    HStack(alignment: .top, spacing: 8) {
                        if memo.rangeStart != nil {
                            Button {
                                onOpenPhraseMemo(memo)
                                dismiss()
                            } label: {
                                personalNoteCardBody(memo)
                            }
                            .buttonStyle(.plain)
                        } else {
                            personalNoteCardBody(memo)
                        }

                        Button(role: .destructive) {
                            viewModel.deletePersonalNote(memo)
                        } label: {
                            Image(systemName: "trash")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .modifier(VerseNoteCardModifier())
                }
            }
        }
    }

    /// `personalNoteList` 카드 한 장의 본문(날짜 + 미리보기). 탭 가능한 표현별 메모와 탭 불가능한 절 전체 메모가
    /// 같은 모양을 공유하도록 분리했다.
    private func personalNoteCardBody(_ memo: UserMemo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(memo.updatedAt, format: .dateTime.year().month().day())
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(phraseMemoLabel(memo))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "+ 개인 묵상"을 누르면 `personalNoteList` 맨 위에 뜨는 입력칸. "등록"을 눌러야만
    /// `commitNewPersonalNote()`가 저장하고, "취소"나 포커스 이탈은 `discardComposingPersonalNote()`로
    /// 저장 없이 닫는다.
    private var composingPersonalNoteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $newPersonalNoteText)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 160)
                .focused($isNewPersonalNoteFieldFocused)
                .onChange(of: newPersonalNoteText) { _, newValue in
                    // `UserMemo.contentText`의 저장 규칙과 같은 글자수 제한(`MemoTextLimit`).
                    if newValue.count > MemoTextLimit.maxCharacters {
                        newPersonalNoteText = String(newValue.prefix(MemoTextLimit.maxCharacters))
                    }
                }

            HStack {
                Text("\(newPersonalNoteText.count)/\(MemoTextLimit.maxCharacters)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("취소") {
                    discardComposingPersonalNote()
                }
                Button("등록") {
                    commitNewPersonalNote()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPersonalNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .modifier(VerseNoteCardModifier())
        .onAppear {
            // 새로 뜬 입력칸에 바로 타이핑할 수 있도록 포커스를 준다.
            isNewPersonalNoteFieldFocused = true
        }
        .onChange(of: isNewPersonalNoteFieldFocused) { _, focused in
            if !focused {
                discardComposingPersonalNote()
            }
        }
    }

    /// 이 절의 `VerseCrossReference` 전부에서 대상 구절(`targets`)만 모아 중복을 없앤다.
    private var allCrossReferenceVerses: [BibleVerseRef] {
        Array(Set(crossReferences.flatMap(\.targets)))
    }

    /// 관주 대상 구절을 정경 순서(책 orderIndex → 장 → 절)로 정렬하고, 같은 책·장에서 절 번호가 1씩 연속이면
    /// "장:시작-끝" 구간으로 합친다(고후1:1, 고후1:2 → 고후1:1-2). 호출부가 구간마다 탭 가능한 칩으로
    /// 그릴 수 있도록 (라벨, 구간의 절들)을 구간별로 반환한다.
    private var crossReferenceInlineSegments: [(label: String, verses: [BibleVerseRef])] {
        let sorted = allCrossReferenceVerses.sorted { lhs, rhs in
            let lo = BooksProvider.shared.book(id: lhs.bookId)?.orderIndex ?? lhs.bookId
            let ro = BooksProvider.shared.book(id: rhs.bookId)?.orderIndex ?? rhs.bookId
            if lo != ro { return lo < ro }
            if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
            return lhs.verse < rhs.verse
        }
        var segments: [(label: String, verses: [BibleVerseRef])] = []
        var index = 0
        while index < sorted.count {
            let start = sorted[index]
            var end = start
            var next = index + 1
            while next < sorted.count,
                  sorted[next].bookId == start.bookId,
                  sorted[next].chapter == start.chapter,
                  sorted[next].verse == end.verse + 1 {
                end = sorted[next]
                next += 1
            }
            let abbreviation = BooksProvider.shared.book(id: start.bookId)?.abbreviation.first ?? "?"
            let verses = sorted[index..<next]
            let label = end.verse == start.verse
                ? "\(abbreviation)\(start.chapter):\(start.verse)"
                : "\(abbreviation)\(start.chapter):\(start.verse)-\(end.verse)"
            segments.append((label: label, verses: Array(verses)))
            index = next
        }
        return segments
    }

    private func phraseMemoLabel(_ memo: UserMemo) -> String {
        let trimmed = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(내용 없음)" : trimmed
    }
}

/// 칩이 한 줄에 다 안 들어가면 자동으로 줄바꿈되는 가로 나열 레이아웃(`HStack`은 줄바꿈을 지원하지 않는다).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
