//
//  VerseZoomView.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설] "구절 확대보기" — 구간 주석(형광펜/메모/관주) 기능의
//  선택 UX. README "이어서 16" 설계 논의에서 사용자가 직접 제안한 방식을 그대로
//  구현한다: 평소 읽기 화면의 "절 전체 탭 → 선택"(복사 기능)은 그대로 두고,
//  하단 액션바의 "구절 확대보기" 버튼으로 이 화면을 연다.
//
//  여러 번역본이 동시에 표시 중일 수 있어(최대 3열), 상단에 번역본 전환 메뉴를
//  둔다 — 주석은 구조적으로 번역본 하나에 종속되므로(같은 절이라도 번역본마다
//  단어가 다르다), "어느 번역본의 어느 표현에 붙일지"를 명시적으로 고르게 한다.
//
//  [2026-08-11 8차 수정, 확대보기 전면 재설계] 사용자가 제공한 설계 문서
//  ("SwiftUI 성경 본문 주석 UI 명세")를 그대로 채택해, 이 화면을 "표시 모드"
//  (`AnnotatedVerseFlowView`, 순수 SwiftUI)와 "선택 모드"(`SelectableVerseTextView`,
//  드래그로 새 구간을 고를 때만) 두 가지로 분리했다 — 자세한 배경은
//  `VerseAnnotationRenderer.swift`와 `SelectableVerseTextView.swift` 상단
//  [2026-08-11 8차 수정] 주석 참고. 평소엔 표시 모드만 보인다 — 형광펜/메모
//  버튼을 누르면 선택 모드로 전환되어 드래그로 범위를 고를 수 있고, 그
//  상태에서 색/스타일을 고르면 바로 적용되며 다시 표시 모드로 돌아간다.
//  "개인 주석"과 "관주(절 전체)"는 선택과 무관하게 항상 동작하므로 표시
//  모드에서도 그대로 쓸 수 있다.
//
//  [2026-08-12 변경] 사용자 요청 — "사용자가 직접 밑줄표시를 하는 기능은
//  없앨것. 관주가 있는 텍스트에 밑줄처럼 표시할 것." 액션바의 "표시"(수동
//  밑줄, `.mark`) 버튼을 없앴다 — 그 주황 밑줄 스타일은 이제 관주가 걸린
//  표현에 자동으로 붙는다(표시 모드/선택 모드 둘 다). 관주 버튼도 선택
//  범위가 기존 관주와 겹치면 새로 만들기 대신 그 관주를 보여주도록 바뀌었다
//  — 자세한 내용은 아래 `actionBar`/`overlappingCrossReference` 주석 참고.
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
    /// 구간 메모를 만들거나(생성 직후) 기존 구간 메모 아이콘에서 하나를 골랐을
    /// 때(열람) — 두 경우 다 "이 메모를 편집기 시트로 열어라"라는 같은 의미라
    /// 콜백 하나로 겸한다. 호출부(BibleReadingView)가 기존 "메모 작성" 시트
    /// 흐름(`memoBeingCreated`)에 이어서 연결한다.
    var onOpenPhraseMemo: (UserMemo) -> Void
    /// [2026-08-08 추가] 사용자 요청 — "확대된 텍스트에도 ... 관주 여부가 동일하게
    /// 표시되도록". 기존 관주 목록에서 대상을 골랐을 때 — `TranslationColumnView.
    /// onSelectCrossReferenceTarget`와 똑같이 그 책/장으로 이동한다.
    var onJumpToCrossReference: (BibleVerseRef) -> Void
    /// [2026-08-11 추가] 사용자 요청 — "성경 본문 하단 관주, 메모정보가 있는
    /// 라인에 [관련 내용] 추가 — 팝업으로 띄워 해당 성경장절이 검색어로 검색되어
    /// 해당 구절로 바로 이동." 목록에서 하나를 고르면 호출부(BibleReadingView)가
    /// 메모는 편집기 시트로, 연구문서는 PDF 검색+이동 창으로 연다.
    var onSelectVerseMention: (VerseMention) -> Void
    /// [2026-08-28 신설] 사용자 요청 — "[메모하기]-[원문정보] 각 레이어창 마다
    /// 쉽게 오갈 수 있도록 화살표라든지 기능을 추가할 것." 이 화면(메모하기,
    /// 구 확대보기)의 툴바에 "원문 정보로 전환" 버튼을 추가하기 위한 콜백 —
    /// 호출부(BibleReadingView)가 이 시트를 닫고 원문 정보 시트를 여는 순서를
    /// 책임진다(같은 화면이 시트 두 개를 동시에 띄울 수 없는 기존 제약,
    /// `pendingPhraseMemo`와 같은 이유).
    var onSwitchToOriginalTextInfo: () -> Void
    /// [2026-09-02 신설] 사용자 요청 — "메모하기 버튼 옆 '개인 묵상' 버튼을
    /// 클릭할 때 동작 = 메모하기 내 '개인 묵상' 버튼 클릭할 때와 동일하게."
    /// 바깥 하단 액션바의 "개인 묵상" 버튼(`BibleReadingView.
    /// openPersonalNoteDirectly()`)이 이 값을 `true`로 넘겨 이 화면을 열면,
    /// 화면이 뜨자마자(`onAppear`) 아래 `beginComposingPersonalNote()`를 자동
    /// 호출해 안(내부) 버튼을 누른 것과 완전히 같은 결과(말씀구절/한자/관주/
    /// 개인묵상 목록이 다 보이는 채로, 그 목록 맨 위에 새 항목 입력칸이 열림)를
    /// 만든다.
    /// [2026-09-02 변경] 사용자 요청 — "개인 묵상의 텍스트를 꼭 팝오버에서
    /// 작성을 해야하는가? ... 리스트 항목에 직접 작성을 해서 등록하는 UI"로
    /// 전환하면서, 이 값이 트리거하는 것도 팝오버가 아니라 아래
    /// `isComposingPersonalNote` 기반 인라인 입력칸이 됐다.
    ///
    /// [2026-09-02 버그 수정, 2차] 사용자 보고 — "다른 기능에서 성경 조회로
    /// 넘어온 뒤 처음 개인 묵상 버튼을 누르면 입력칸이 안 뜨고, 팝업을 닫고
    /// 다시 누르면 뜬다." 1차 시도(`BibleReadingView.openPersonalNoteDirectly()`
    /// 에서 시트를 여는 시점만 다음 런루프 틱으로 미루는 것)로는 해결되지
    /// 않았다 — 이 파일 위쪽 `PhraseNoteEditorPopover.swift`의 2026-08-11
    /// 15차 수정 주석이 이미 실측으로 확인해 둔 것과 정확히 같은 근본 원인일
    /// 가능성이 높다: 문제는 "언제 스냅샷을 뜨느냐"가 아니라 "생성자 인자로
    /// 값을 한 번만(`let`) 받는 것 자체"다 — `.sheet`의 콘텐츠 클로저가 이
    /// 화면을 처음 준비하는 시점에 `shouldAutoPresentPersonalNoteEditor`를
    /// 읽어 `VerseZoomView.init`에 `let`으로 얼려서 넘기면, 그 시점이 실제로
    /// 이 뷰가 화면에 붙어 `onAppear`가 도는 시점보다 이를 수 있어 값이
    /// 어긋날 수 있다(런루프 틱을 미루는 정도로는 이 어긋남 자체가 없어지지
    /// 않는다는 게 15차 수정에서 이미 확인된 바). `PhraseNoteEditorPopover`가
    /// `editingPhraseNote`/`pendingAnchorText`를 `@Binding`으로 바꿔 해결한
    /// 것과 동일하게, 이 값도 `@Binding`으로 바꿔 `onAppear`가 뷰가 실제로
    /// 화면에 붙은 뒤 "그 순간의" 최신 값을 다시 읽게 한다.
    @Binding var autoPresentPersonalNoteEditor: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedColumnID: UUID
    @State private var selectedRange = NSRange(location: 0, length: 0)
    /// [2026-08-11 8차 수정] 표시 모드/선택 모드 전환 — 위 파일 상단 주석 참고.
    /// 형광펜/메모 버튼이 이 값을 `true`로 바꿔 선택 모드로 들어가고,
    /// 실제로 스타일을 적용하고 나면(또는 취소하면) 다시 `false`로 돌아간다.
    @State private var isSelecting = false
    @State private var isCrossReferencePickerPresented = false
    @State private var isVerseMentionPopoverPresented = false
    /// [2026-08-11 추가] "메모"(드래그 표현 부연설명) 편집 팝오버 — nil이면 새로
    /// 만들기(현재 `selectedRange`/`anchorText` 기준), 값이 있으면 그 메모 수정.
    @State private var isPhraseNoteEditorPresented = false
    /// [2026-09-02 변경] 사용자 요청 — "개인 묵상의 텍스트를 꼭 팝오버에서
    /// 작성을 해야하는가? ... 리스트 항목에 직접 작성을 해서 등록하는 UI는
    /// 불가능한지 검토하라." 확인 결과(1) 팝오버를 완전히 없애고 리스트
    /// 카드 자체를 편집(작성) 모드로 바꾸는 방향으로 진행하기로 함 — 그래서
    /// `PersonalNoteEditorPopover`/`isPersonalNoteEditorPresented` 팝오버
    /// 상태는 지우고, 아래 `personalNoteList`가 이 값이 켜져 있을 때 목록
    /// 맨 위에 입력칸(카드)을 직접 그린다.
    /// 사용자 확인(2) — "수정은 지원하지 않는다. 삭제하고 다시 등록하는
    /// 프로세스이다. 자동저장은 하지 않는다." 그래서 이 입력칸은 항상 "새
    /// 항목 만들기" 전용이고(기존 항목을 다시 여는 편집 모드는 없음), 텍스트는
    /// `newPersonalNoteText`에만 임시로 담겨 있다가 "등록" 버튼을 눌러야
    /// `BibleReadingViewModel.createPersonalNote`로 실제 저장된다.
    @State private var isComposingPersonalNote = false
    @State private var newPersonalNoteText = ""
    /// 사용자 확인 — "'+ 개인 묵상'을 눌러 입력칸이 열린 뒤, 아무것도 쓰지
    /// 않고 다른 곳을 탭하면 그냥 닫히고 저장 안 됨." 포커스를 잃는 순간이
    /// "다른 곳을 탭함"의 신호 — 아래 `body`의 `.onChange(of:
    /// isNewPersonalNoteFieldFocused)`가 이 값이 `false`로 바뀔 때 아직
    /// 등록되지 않은 입력칸이면(=`isComposingPersonalNote`가 여전히 `true`)
    /// 초안을 버리고 입력칸을 닫는다. "등록" 버튼 자체를 눌렀을 때는 그
    /// 버튼의 동작이 먼저 `isComposingPersonalNote`를 `false`로 만들어 두므로
    /// (아래 `commitNewPersonalNote()`) 이 포커스-상실 처리와 겹쳐도 중복
    /// 저장되지 않는다.
    @FocusState private var isNewPersonalNoteFieldFocused: Bool
    @State private var editingPhraseNote: VersePhraseNote?
    /// [2026-08-11 12차 수정] 사용자 보고 — "선택모드 - 처음 텍스트 선택 -
    /// 처음 메모 클릭: 메모 팝업 상단에 선택된 텍스트 정보가 나타나지 않음.
    /// 다시 메모 클릭하면 나타남." 원인으로 가장 유력한 것은 — 팝오버가 뜨는
    /// 순간 `SelectableVerseTextView`의 `UITextView`/`NSTextView`가 first
    /// responder를 잃으면서(팝오버가 포커스를 가져가므로) iOS/macOS가
    /// 드래그 선택을 자동으로 해제하고, 그 델리게이트 콜백
    /// (`Coordinator.textViewDidChangeSelection`)이 `DispatchQueue.main.async`
    /// 로 미뤄져 있어 팝오버가 이미 열린 "이후"에 `selectedRange`를
    /// `(0, 0)`으로 되돌려 버리는 것 — 팝오버 상단의 `anchorText`(선택된
    /// 텍스트 인용)가 `selectedRange`를 실시간으로 읽는 계산 프로퍼티라서,
    /// 이 리셋이 팝오버가 열린 "직후"에 일어나면 방금까지 있던 텍스트
    /// 정보가 사라져 보인다(두 번째 시도가 성공하는 것도 이 설명과 들어맞는다
    /// — 이미 한 번 리셋된 뒤라 그 이후엔 별다른 변화가 없다).
    ///
    /// 근본 대책 — 팝오버를 "열기로 결정하는 바로 그 순간"에 선택 범위와
    /// 그 표현 텍스트를 스냅샷으로 떠 둔다. 팝오버의 표시(anchorText)와
    /// 저장(addPhraseNote) 둘 다 이 스냅샷만 쓰고, 그 이후 `selectedRange`가
    /// 어떻게 바뀌든 전혀 영향받지 않는다.
    @State private var editingAnchorRange = NSRange(location: 0, length: 0)
    @State private var editingAnchorText: String = ""
    /// [2026-08-11 8차 수정] 표시 영역의 실제 화면 폭 — `AnnotatedVerseFlowView`
    /// 의 줄바꿈 계산(`VerseAnnotationRenderer.lineRanges`)과 선택 모드 텍스트뷰
    /// 폭에 둘 다 쓴다. `GeometryReader`로 콘텐츠 자체를 감싸면(전형적인 실수)
    /// 그 콘텐츠의 높이까지 강제로 화면 전체로 늘어나 버리므로, 대신
    /// `onGeometryChange`(iOS 17+/macOS 14+)로 "내 크기를 옆에서 관찰만" 한다 —
    /// 레이아웃에 영향을 주지 않아 콘텐츠는 원래대로 내용에 맞는 높이를 갖는다.
    @State private var scrollWidth: CGFloat = 320
    /// [2026-08-12 추가] 사용자 요청 — "가로모드와 세로모드 각각 줄넘김에 대한
    /// 글자수 차이둘것"(아이폰). 세로/가로를 판정하려고 `UIDevice.orientation`
    /// 같은 별도 API 대신, 이미 관찰 중이던 `scrollWidth`와 같은 방식으로 실제
    /// 렌더링 높이도 함께 관찰해 "폭 > 높이면 가로, 아니면 세로"로 판정한다 —
    /// 이 화면이 거의 전체 화면을 덮는 시트라 화면 방향과 사실상 일치한다.
    @State private var scrollHeight: CGFloat = 480

    init(
        verseNumber: Int, columns: [BibleReadingViewModel.ColumnState], viewModel: BibleReadingViewModel,
        onOpenPhraseMemo: @escaping (UserMemo) -> Void,
        onJumpToCrossReference: @escaping (BibleVerseRef) -> Void,
        onSelectVerseMention: @escaping (VerseMention) -> Void,
        onSwitchToOriginalTextInfo: @escaping () -> Void,
        autoPresentPersonalNoteEditor: Binding<Bool> = .constant(false)
    ) {
        self.verseNumber = verseNumber
        self.columns = columns
        self.viewModel = viewModel
        self.onOpenPhraseMemo = onOpenPhraseMemo
        self.onJumpToCrossReference = onJumpToCrossReference
        self.onSelectVerseMention = onSelectVerseMention
        self.onSwitchToOriginalTextInfo = onSwitchToOriginalTextInfo
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

    /// [2026-08-11 수정] 사용자 요청 — "성경 구절은 메인창의 성경 글꼴과 동일하도록."
    /// 환경설정(모양 탭)의 "S1 표시 폰트"(`TranslationColumnView.VerseRow`가 쓰는
    /// `UserSettingsStore.bibleFontName`)를 그대로 재사용한다.
    /// [2026-08-12 변경] 사용자 요청 — "글꼴은 설정값을 유지하되, 글꼴크기는
    /// 보통크기로." 글꼴 "종류"(`bibleFontName`)는 계속 설정값을 따르지만,
    /// 크기는 `bibleBodyFontSize`(모양 탭에서 12~32pt로 조절 가능한 값)를
    /// 따라가지 않고 고정 크기를 쓴다 — 사용자가 메인 화면 본문 크기를
    /// 크게/작게 키워도 확대보기 안에서 줄바꿈·메모 박스 배치 계산이 그 값에
    /// 흔들리지 않게 하기 위함이다(설정값을 직접 반영하는 방안은 2026-08-21에
    /// 다시 검토했으나, 그 흔들림 버그가 재발할 위험이 있어 여전히 피했다 —
    /// 대신 아래처럼 고정값 자체를 조금 키웠다).
    /// [2026-08-21 변경] 사용자 요청 — "확대보기 폰트크기를 20pt로." 위 이유로
    /// 여전히 고정값이지만(설정 추종 아님), 17 → 20으로 올렸다 — 아래
    /// `targetCharsPerLine`/`effectiveTextWidth`도 커진 글자 폭에 맞춰 함께
    /// 조정했다.
    private var bibleFont: PlatformFont {
        let settings = UserSettingsStore.shared
        // [2026-08-26 변경] 사용자 요청 — "확대보기 - 영역수정: 성경구절
        // 1pt 줄이고." 위 [2026-08-21 변경] 주석이 20으로 올린 이후 처음
        // 받은 축소 요청이라 그 값에서 그대로 1만 뺀다 — `targetCharsPerLine`/
        // `effectiveTextWidth`(아래)는 고정 글자 수/화면 실측 폭 기준이라
        // 폰트가 1pt 작아진다고 별도로 다시 맞출 근거값이 없다(글자 수 기준
        // 줄바꿈은 폰트 크기와 무관하게 그대로 유지되는 게 맞다).
        let size: CGFloat = 19
        guard settings.bibleFontName != "System" else { return .systemFont(ofSize: size) }
        BundledFontRegistrar.ensureAvailable(settings.bibleFontName)
        return PlatformFont(name: settings.bibleFontName, size: size) ?? .systemFont(ofSize: size)
    }

    /// [2026-08-11 추가, 2026-08-11 8차 수정] 사용자 요청 — "한 줄에 17~25자
    /// 정도로... 왼쪽 정렬." 화면이 넓어도(아이패드 가로 등) 성경 본문 한
    /// 줄이 너무 길어지지 않도록 읽기 좋은 폭으로 제한한다. 한글 절은 이
    /// 값과 무관하게 23자 최근접 띄어쓰기로 줄이 정확히 나뉘지만(폭이 아니라
    /// 글자 수 기준), 라틴/혼합 절은 `VerseAnnotationRenderer.measuredLineRanges`
    /// 가 이 폭을 그대로 기준 삼아 TextKit으로 측정한다 — 선택 모드
    /// (`SelectableVerseTextView`)도 시각적 일관성을 위해 같은 폭을 쓴다.
    /// [2026-08-12 신설, `effectiveTextWidth`에서 분리] 스크롤 영역의 실제
    /// 콘텐츠 폭(패딩 32pt 제외) — 성경 본문 줄바꿈 목표 폭(`effectiveTextWidth`,
    /// 훨씬 좁게 제한됨)과 달리, 메모 박스가 실제로 화면 안에서 밀릴 수 있는
    /// 진짜 한계는 이 값이다(`AnnotatedVerseFlowView.availableWidth` 참고).
    /// [2026-08-21 변경] 사용자 요청 — "확대보기 - 메모 가로 크기를 현 최대
    /// 사이즈에서 20px을 줄여줄것." 기존엔 패딩(32pt)만 뺐는데, 메모 박스가
    /// 닿을 수 있는 최대 폭 자체를 20px 더 줄이기 위해 빼는 값을 32 → 52로
    /// 늘렸다(패딩 32 + 요청한 20). 성경 본문 줄바꿈 폭(`effectiveTextWidth`)은
    /// 이 값과 별개 계산이라 영향받지 않는다.
    private var availableContentWidth: CGFloat {
        max(scrollWidth - 52, 0)
    }

    private var effectiveTextWidth: CGFloat {
        let sample = "가" as NSString
        let charWidth = sample.size(withAttributes: [.font: bibleFont]).width
        // [2026-08-21 변경] 사용자 요청 — "확대보기 창을 가로로 조금 더 늘리고
        // 20pt로." 이 23은 그 때 `targetCharsPerLine`(당시 25)보다 항상 2 작게
        // 유지해 온 값이었다(라틴/혼합 문자가 한글 "가"보다 평균적으로 조금 더
        // 넓어서 그만큼 여유를 둔 것으로 보인다).
        // [2026-09-01 변경] 사용자 결정 — "확대보기 줄바꿈 글자수(세로모드
        // 아이폰 18자 유지 / 그 외 25→20자)를 바꾸되, 메모 박스 폭 계산은
        // 그대로 둘 것." 이제 이 23은 `targetCharsPerLine`과 연동되지 않는
        // 독립적인 고정값이다 — 아래 `targetCharsPerLine`이 20/18로 바뀌어도
        // 이 값은 그대로 23을 쓴다.
        let idealWidth = charWidth * 23
        return idealWidth > 0 ? min(availableContentWidth, idealWidth) : availableContentWidth
    }

    /// [2026-08-12 신설] 사용자 요청 — "가로모드와 세로모드 각각 줄넘김에 대한
    /// 글자수 차이둘것 ... 아이폰에서." 아이패드/맥은 대상이 아니므로
    /// `UIDevice.userInterfaceIdiom == .phone`으로 제한한다.
    private var isPhonePortrait: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && scrollHeight > scrollWidth
        #else
        false
        #endif
    }

    /// 가로모드(아이패드/맥/아이폰 가로모드) - 20자. 세로모드(아이폰) - 18자
    /// 기준으로 그 지점 이후 나타나는 첫 띄어쓰기에서 줄바꿈(사용자 요청) —
    /// 실제 알고리즘은 `VerseAnnotationRenderer.koreanLineRanges`(아래
    /// `firstSpaceIndex` 참고)가 그대로 재사용하고, 목표 글자수만 이 값으로
    /// 바꿔 넘긴다.
    /// [2026-08-21 변경] 사용자 요청 — "확대보기 창을 가로로 조금 더 늘리고
    /// 20pt로." 23 → 25로 올렸었다 — 2026-08-11 8차 수정이 정한 원래 허용
    /// 범위("한 줄에 17~25자 정도로")의 상한 그대로라 그 결정을 벗어나지
    /// 않았다. 아이폰 세로모드(18자)는 그 요청 범위 밖이라 그대로 뒀다.
    /// [2026-09-01 변경] 사용자 요청 — "한라인에서 20글자(공백포함) 이후
    /// 나타나는 첫 공백에서 줄바꿈으로 바꿀 것." 세로모드 아이폰은 그대로
    /// 18자를 유지하고, 그 외(가로모드 아이폰/아이패드/맥)는 25 → 20으로
    /// 내렸다(사용자가 명시적으로 확인한 값 — `effectiveTextWidth`의 메모
    /// 박스 폭 계산은 이 변경과 별개로 그대로 둔다, 위 주석 참고).
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

    // [2026-08-09 수정, 빌드 에러] 이전엔 지역 변수였다 — 형광펜/밑줄 취소
    // 기능 이후 여러 곳에서 필요해져 저장 프로퍼티(computed property)로
    // 승격해 재사용한다.
    private var highlights: [VerseHighlight] {
        guard let column = currentColumn else { return [] }
        return viewModel.highlights(translationCode: column.registry.code, verse: verseNumber)
    }

    private var crossReferences: [VerseCrossReference] {
        guard let column = currentColumn else { return [] }
        return viewModel.crossReferences(translationCode: column.registry.code, verse: verseNumber)
    }

    /// [2026-08-15 신설] 사용자 요청 — "확대보기 조회모드 수정 - 관주 영역 위에
    /// 한문 단어 뜻풀이 영역을 따로 두어." 메인 읽기 화면에서 "탭하면 보기"
    /// 아이콘+팝오버를 없애고(TranslationColumnView 참고) 절 선택 시 국한문
    /// 인라인 표시로 바꾸면서, 한자 "뜻"(훈음)은 이제 여기 확대보기에서만
    /// 볼 수 있다.
    private var hanjaWords: [HanjaWordAnnotation] {
        guard let column = currentColumn else { return [] }
        return viewModel.hanjaWords(translationCode: column.registry.code, verse: verseNumber)
    }

    private var phraseMemos: [UserMemo] {
        guard let column = currentColumn else { return [] }
        return viewModel.phraseMemos(translationCode: column.registry.code, verse: verseNumber)
    }

    /// [2026-08-11 추가] "메모"(드래그 표현 부연설명) — 형광펜/표시와 같은
    /// 원칙, 특정 번역본의 특정 표현에 종속된다.
    private var phraseNotes: [VersePhraseNote] {
        guard let column = currentColumn else { return [] }
        return viewModel.phraseNotes(translationCode: column.registry.code, verse: verseNumber)
    }

    /// [2026-08-11 추가] "관련 내용" — 번역본과 무관하게 이 절을 언급하는 메모/
    /// 연구문서(위 `onSelectVerseMention` 상단 주석 참고).
    private var verseMentions: [VerseMention] {
        viewModel.verseMentions(verse: verseNumber)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if columns.count > 1 {
                    translationSwitcher
                    Divider()
                }

                ScrollView {
                    Group {
                        if isSelecting {
                            // [2026-08-11 8차 수정] 선택 모드 — 새 구간을 드래그로
                            // 고르는 동안만 뜬다. 기존 형광펜/표시/메모를 예쁘게
                            // 보여줄 필요가 없어(그 책임은 표시 모드로 완전히
                            // 옮겨졌다) 서식 없는 평범한 텍스트만 그린다.
                            // `UITextView`/`NSTextView`는 스스로 폭 기준 자동
                            // 줄바꿈을 하므로 `.frame(width:)`로 폭을 좁혀도
                            // 잘리지 않고 그 폭 안에서 다시 감싸 줄바꿈된다.
                            // [2026-08-11 10차 수정] 사용자 요청 — "한 라인에
                            // 들어가는 텍스트를 선택모드와 동일하게 일치시킬
                            // 것(줄바꿈까지)." 표시 모드(`AnnotatedVerseFlowView`)
                            // 에 넘기는 것과 정확히 같은 `effectiveTextWidth`를
                            // `containerWidth`로 넘겨야 `VerseAnnotationRenderer.
                            // lineRanges(...)`가 두 모드에서 같은 경계를 고른다.
                            // [2026-08-11 11차 수정] 사용자 요청 — "선택모드에서도
                            // 형광펜, 밑줄, 메모가 있는 텍스트(파란색)을 표시할
                            // 것." 표시 모드와 같은 `highlights`/`phraseNotes`를
                            // 그대로 넘긴다 — 메모 박스/화살표는 안 그리지만,
                            // 어느 표현에 무엇이 붙어 있는지는 선택 모드에서도
                            // 보인다.
                            SelectableVerseTextView(
                                text: verseText, font: bibleFont, textColor: labelColor,
                                containerWidth: effectiveTextWidth, targetCharsPerLine: targetCharsPerLine,
                                highlights: highlights, phraseNotes: phraseNotes, crossReferences: crossReferences,
                                hanjaWords: hanjaWords,
                                selectedRange: $selectedRange
                            )
                            .frame(width: effectiveTextWidth, alignment: .leading)
                        } else {
                            // [2026-08-11 8차 수정] 표시 모드(평소) — 순수 SwiftUI
                            // 렌더링. 형광펜 취소/메모 수정·삭제는 이 뷰 안의
                            // `.contextMenu`(길게 누르기/우클릭)로 처리된다.
                            //
                            // ⚠️ 여기에는 일부러 `.frame(width:)`를 씌우지 않는다
                            // — `containerWidth`는 이미 `buildLines(...)`가 줄을
                            // 나눌 때 "목표"로 참고하는 값일 뿐이고, 한글 절은
                            // 23자 단위(폭이 아니라 글자 수 기준)라 실제 렌더링
                            // 폭이 이 목표값보다 약간 넓거나 좁을 수 있다 — 그
                            // 위에 다시 좁은 `.frame(width:)`를 씌우면 한 줄
                            // (`HStack(spacing: 0)`, 자체적으로 다시 줄바꿈하지
                            // 않는다)이 그 폭에 잘려 보일 위험이 있다. 대신
                            // `containerWidth`만 정확히 넘기고, 실제로 그려지는
                            // 폭은 그 콘텐츠 자체가 정하게 둔다.
                            AnnotatedVerseFlowView(
                                text: verseText, highlights: highlights, phraseNotes: phraseNotes,
                                crossReferences: crossReferences, hanjaWords: hanjaWords,
                                font: bibleFont, textColor: labelColor, containerWidth: effectiveTextWidth,
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
                    // [2026-08-11 추가] 사용자 요청 — "왼쪽 정렬." 화면이
                    // `effectiveTextWidth`보다 넓으면 남는 공간은 오른쪽에
                    // 남기고 텍스트 블록 자체는 왼쪽에 붙인다.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
                    scrollWidth = newSize.width
                    scrollHeight = newSize.height
                }

                // [2026-08-08 추가] 사용자 요청 — "확대된 텍스트에도 ... 메모,
                // 관주 여부가 동일하게 표시되도록". 평소 읽기 화면
                // (`TranslationColumnView.VerseRow`)과 똑같은 아이콘 + 팝오버/메뉴
                // 조합을 재사용한다 — 표시만 하는 게 아니라 탭했을 때의 동작(관주
                // 대상으로 이동, 메모 열기)까지 동일하다.
                // [2026-08-15 추가] 사용자 요청 — "관주 영역 위에 한문 단어
                // 뜻풀이 영역을 따로 둘 것." 한자 뜻풀이가 있으면 관주/메모
                // 상태줄보다 먼저(위에) 그린다.
                // [2026-09-02 변경] 사용자 요청 — "개인 묵상의 텍스트를 꼭
                // 팝오버에서 작성을 해야하는가? ... 리스트 항목에 직접
                // 작성을 해서 등록하는 UI." 이 절에 개인 묵상/한자/관주/관련
                // 내용이 하나도 없어도, "+ 개인 묵상"으로 입력칸을 여는
                // 순간(`isComposingPersonalNote`)엔 그 입력칸을 보여줄 이
                // 섹션 자체가 그려져야 한다 — 세 조건 모두에 추가했다.
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

                Divider()
                actionBar

                // [2026-09-01 신설] 사용자 보고 — "맥OS 버전에서 성경조회 -
                // 메모하기에서 원문정보로 이동하는 버튼 없음... 버튼자체가
                // 안보임." 리서치 결과 macOS `.sheet`의 `.confirmationAction`/
                // `.cancellationAction`은 Apple 문서 자체가 "확인/취소 액션 하나"를
                // 위한 자리로 명시하고 있고(ToolbarItemPlacement 문서, "a
                // placement for confirmation actions"), 실측으로도 `ToolbarItem`
                // 이든 `ToolbarItemGroup`이든 그 자리에 두 번째 버튼을 얹으면
                // 조용히 사라진다(잘리거나 오버플로 메뉴로 가는 게 아니라
                // 아예 그려지지 않음) — 한 placement당 버튼 하나만 그린다는
                // 뜻으로 보인다. 그래서 macOS만 이 화면의 하단 버튼줄(닫기/
                // 원문 정보/펜·눈동자)을 시스템 `.toolbar` 자리에 맡기지 않고
                // 이 뷰 본문에 직접 그린다 — 순서 요청("닫기 오른쪽, 편집모드
                // 버튼 왼쪽")대로 닫기 → 원문 정보 → 펜/눈동자 순으로 배치한다.
                // iOS/iPadOS는 내비게이션 바 트레일링 영역이 이 제약이 없어(
                // 여러 bar button item을 그대로 다 그린다) 기존 `.toolbar`
                // 방식을 그대로 둔다(아래 `.toolbar` 참고).
                #if os(macOS)
                Divider()
                HStack {
                    Button("닫기") { dismiss() }
                    Spacer()
                    Button(action: onSwitchToOriginalTextInfo) {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                    .help("원문 정보로 전환")
                    Button {
                        isSelecting.toggle()
                        selectedRange = NSRange(location: 0, length: 0)
                    } label: {
                        Image(systemName: isSelecting ? "eye" : "pencil")
                    }
                }
                .padding()
                #endif
            }
            // [2026-08-09 수정] 사용자 보고 — "[성경] [x] [x]절 확대보기"로 보여
            // 장 번호와 절 번호가 구분 없이 나란히 붙어 있었다(`localizedBookChapterLabel`이
            // "책이름 장번호"까지만 담고 "장" 글자는 없음 — BibleReadingViewModel.
            // reloadVerses 참고). "장"을 직접 붙여 "책이름 장번호장 절번호절"이 되게
            // 고쳤다.
            // [2026-08-29 수정] 사용자 요청 — "타이틀 : ... 확대하기 -> 확대하기
            // 텍스트 제거." 이 화면(메모하기, 구 확대보기) 버튼 이름을 이미
            // "메모하기"로 바꿨는데 타이틀에는 옛 이름("확대보기")이 그대로
            // 남아 있었다 — 책/장/절 위치만 보여주도록 뒷부분을 뺐다.
            .navigationTitle("\(currentColumn?.localizedBookChapterLabel ?? "")장 \(verseNumber)절")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // [2026-09-01 변경] 사용자 보고 — "맥OS 버전에서 ... 버튼자체가
            // 안보임." macOS `.sheet`에서 `.confirmationAction`에 두 번째
            // 버튼을 얹으면(`ToolbarItem`이든 `ToolbarItemGroup`이든) 조용히
            // 사라지는 것을 실측으로 확인했다(위 `actionBar` 아래 `#if
            // os(macOS)` 커스텀 버튼줄 참고 — 그쪽으로 옮겼다) — 그래서 이
            // `.toolbar`는 이제 iOS/iPadOS 전용이다. iOS 내비게이션 바
            // 트레일링 영역은 여러 bar button item을 그대로 다 그리므로
            // (이 화면에서 원문 정보 버튼 미표시 문제가 iOS에서는 보고된 적
            // 없음) 기존 `ToolbarItemGroup` 방식을 그대로 둔다.
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                // [2026-08-11 9차 수정] 사용자 요청 — "기존 UI처럼 눈동자 아이콘과
                // 펜 모양 아이콘으로... 표시모드: 닫기 옆에 펜모양 아이콘(편집모드
                // 진입) / 선택모드: 닫기 옆에 눈동자모양 아이콘." 예전 텍스트
                // 버튼("선택 취소")을 표시/선택 모드를 오가는 상시 아이콘 토글로
                // 바꿨다 — 표시 모드일 땐 펜(누르면 선택 모드 진입), 선택
                // 모드일 땐 눈동자(누르면 표시 모드로 복귀 + 선택 해제).
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        isSelecting.toggle()
                        selectedRange = NSRange(location: 0, length: 0)
                    } label: {
                        Image(systemName: isSelecting ? "eye" : "pencil")
                    }

                    // [2026-08-29 3차 수정] 사용자 요청 — "좌우 화살표 대신
                    // 메모하기 아이콘과, 원어 정보 아이콘으로 각각 대치할 것."
                    // [2026-09-01 수정] 사용자 요청 — "하단 닫기 오른쪽에
                    // 아이콘과 "원문 정보" 이름으로된 버튼 추가." 기존
                    // 아이콘 전용 버튼을, 성경 조회 하단 액션바에서 이미 쓰는
                    // 것과 같은 `Label("원문 정보", systemImage:
                    // "character.book.closed")`(`BibleReadingView.swift` 참고)로
                    // 바꿔 아이콘+이름이 함께 보이게 한다.
                    Button(action: onSwitchToOriginalTextInfo) {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                    .help("원문 정보로 전환")
                }
            }
            #endif
            .onChange(of: selectedColumnID) { _, _ in
                selectedRange = NSRange(location: 0, length: 0)
                isSelecting = false
            }
            .sheet(isPresented: $isCrossReferencePickerPresented) {
                // [2026-08-12 변경] `CrossReferenceTargetPicker.onSave`가 이제
                // 절 목록(DB 저장용, 다 펼친 것)과 항목별 라벨/개수(표시용, 정제된
                // 문구)를 함께 넘긴다 — [2026-08-15 갱신] 그 정제된 라벨은 이제
                // (팝오버가 아니라) 이 시트 자신의 "등록된 관주" 섹션
                // (`existingDisplayEntries`)이 그대로 써서 사용자가 입력한 문구가
                // 정제된 형태로 보이게 한다.
                //
                // [2026-08-12 추가] 사용자 요청 — "새로 만들기 시트 + 기존 관주
                // 보기." 선택 범위가 있으면 그 텍스트(`anchorText`)와 그 범위와
                // 겹치는 기존 관주(`overlappingCrossReferences`)를 함께 넘겨,
                // 시트 자신이 타이틀에 선택된 텍스트를 보여주고 "등록된 관주"
                // 섹션도 함께 그리게 한다.
                // [2026-08-15 변경] 사용자 요청 — "관주 버튼을 누르면, 관주
                // 연결 팝업에 입력된 관주들이 표시되게 할 것." 이전엔 선택
                // 범위가 없으면(`hasSelection == false`, 즉 절 전체 대상) 항상
                // `[]`를 넘겨 이미 등록된 관주가 있어도 시트에 안 보였다 — 이제
                // 선택 범위가 없을 때는 이 절에 걸린 관주 전부(`crossReferences`,
                // 절 전체 관주 포함)를 그대로 넘긴다.
                // [2026-08-15 2차 추가] 사용자 요청 — 확대보기 관주 상태줄의
                // 삭제(X) 기능을 팝오버와 함께 없애면서, 그 삭제 기능을 여기
                // (편집모드의 "등록된 관주" 목록)로 옮겼다 — `onDeleteExisting`
                // 이 실제 삭제(`viewModel.removeCrossReferenceGroup`)를 맡는다.
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
            // [2026-08-11 신설] "메모"(드래그 표현 부연설명) 편집 팝오버 —
            // `editingPhraseNote`가 nil이면 새로 만들기, 있으면 수정(표시
            // 모드에서 박스를 탭하거나 컨텍스트 메뉴 "메모 수정"에서 옴).
            //
            // [2026-08-11 15차 수정] 사용자가 제공한 `[메모진단]` 로그로 확인한
            // 것 — `PhraseNoteEditorPopover`에 `anchorText`/`isEditing`을
            // `let` 생성자 인자로 넘기는 방식 자체가 원인이었다(같은 값도
            // 어떤 시도는 성공, 어떤 시도는 반복 실패 — `.id(...)`나 프레젠
            // 테이션 지연으로도 패턴이 없어지지 않았다). `$editingPhraseNote`/
            // `$editingAnchorText`를 `@Binding`으로 직접 넘겨, 그 뷰의
            // `body`가 그릴 때마다 최신 값을 다시 읽게 했다 — 자세한 이유는
            // `PhraseNoteEditorPopover.swift` 상단 [2026-08-11 15차 수정]
            // 주석 참고. `.id(...)`는 만약을 위해 그대로 남겨 둔다.
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
            // [2026-09-02 변경] 위 `isComposingPersonalNote` 상단 주석 참고 —
            // 팝오버를 없애고 `personalNoteList`가 이 값을 직접 보고 입력칸을
            // 그리므로, 여기엔 더 이상 별도 `.popover`가 필요 없다.
            // 바깥 "개인 묵상" 버튼으로 열렸을 때만 화면이 뜨자마자 자동으로
            // 그 입력칸을 연다(`autoPresentPersonalNoteEditor` 상단 주석 참고).
            .onAppear {
                if autoPresentPersonalNoteEditor {
                    beginComposingPersonalNote()
                }
            }
        }
        #if os(macOS)
        // [2026-08-21 변경] 위 `bibleFont`/`targetCharsPerLine` 주석과 같은
        // 이유 — 본문 글자·목표 줄폭이 커진 만큼 창 최소 폭도 조금 늘렸다
        // (480 → 520, "가로로 조금 더 늘리고" 요청).
        // [2026-08-26 변경] 사용자 요청 — "확대보기 영역을 좌우 넓이를 5px
        // 키우도록." 이 파일에서 "확대보기 영역의 가로 폭"을 나타내는 유일한
        // 명시적 pt 값이 이 macOS 창 최소 폭이라(위 이력 참고, 정확히 같은
        // 종류의 요청으로 480→520이 된 값), 그 값에 5를 더한다.
        .frame(minWidth: 525, minHeight: 420)
        #endif
    }

    // [2026-08-11 16차 수정] 사용자 요청 — "상단 타이틀 밑 picker의 '번역본'
    // 텍스트 제거." iOS의 `.segmented` 피커는 라벨을 안 그리지만, macOS는
    // 세그먼트 컨트롤 옆에 라벨을 텍스트로 그대로 보여준다 — `.labelsHidden()`
    // 으로 라벨만 숨기고 접근성 라벨("번역본")은 그대로 유지한다(스크린
    // 리더 등에서는 계속 "번역본"으로 읽힌다).
    private var translationSwitcher: some View {
        Picker("번역본", selection: $selectedColumnID) {
            ForEach(columns) { column in
                Text(column.registry.displayName).tag(column.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding()
    }

    // [2026-08-11 9차 수정] 사용자 요청 — "선택모드: ... 형광펜 .. ..메모 관주
    // 아이콘 활성화 또는 보이도록 / 표시모드: ... 비활성화 또는 안보이게 처리."
    // 네 버튼(형광펜/개인 주석/메모/관주)을 모두 `isSelecting` 기준으로 한데
    // 묶어 흐리게 처리한다 — 문자 그대로는 "개인 주석"과 "관주"도 포함하는
    // 지시라 그렇게 반영했지만, 이 둘은 원래 드래그 선택과 무관하게 절 전체에
    // 항상 걸 수 있던 기능이라(표시 모드에서도 계속 쓸모가 있었다) 이번에
    // 선택 모드 전용으로 바뀌는 게 실제로 의도한 바가 맞는지 사용자 확인이
    // 필요하다 — README에도 트레이드오프로 남겨 둔다.
    //
    // [2026-08-12 변경] 사용자 요청 — "사용자가 직접 밑줄표시를 하는 기능은
    // 없앨것." 다섯 번째 버튼이던 "표시"(`.mark`, 수동 밑줄)를 통째로 뺐다 —
    // 그 시각 스타일(주황 밑줄) 자체는 사라지지 않고, 이제 관주가 걸린 표현에
    // 자동으로 켜진다(`VerseAnnotationRenderer.buildLines`의 `hasCrossReference`
    // 참고). `VerseHighlightStyle.mark` 열거형 케이스와 그 렌더링 분기는 이미
    // 만들어진 레거시 데이터를 계속 정상적으로 보여주기 위해 그대로 남겨
    // 뒀다 — 다만 이 화면 어디에도 그 스타일을 새로 만드는 진입점은 없다.
    private var actionBar: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(HighlightColorTag.allCases) { tag in
                        Button {
                            if hasSelection {
                                applyHighlight(colorTag: tag)
                            } else {
                                isSelecting = true
                            }
                        } label: {
                            Circle().fill(tag.swiftUIColor).frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("형광펜").font(.caption2).foregroundStyle(.secondary)
            }

            // [2026-08-11 12차 수정] 사용자 요청 — "[개인 주석]과 [메모] 순서를
            // 바꿀 것." 원래 개인 주석 → 메모 순서였던 것을 메모 → 개인 주석
            // 순서로 바꿨다.
            //
            // [2026-08-11 9차 수정] 사용자 보고 — 같은 표현에 메모가 중복 등록될
            // 수 있었고, 그 상태에서 수정 시 정보가 꼬였다. 선택 범위와 겹치는
            // 기존 메모가 있으면(위 `existingPhraseNote(overlapping:)`) 새로
            // 만들지 않고 그 메모를 편집 모드로 연다.
            //
            // [2026-08-11 12차 수정] 사용자 보고 — 팝오버 상단 텍스트 정보가
            // 첫 시도에 안 보이는 버그. 팝오버를 열기로 결정하는 이 순간
            // `selectedRange`/`anchorText`를 `editingAnchorRange`/
            // `editingAnchorText`에 스냅샷으로 떠 둔다(위 상태 선언부 주석
            // 참고) — 팝오버가 열린 뒤 `selectedRange`가 어떻게 바뀌어도
            // 팝오버 표시·저장 둘 다 영향받지 않는다.
            // [2026-08-11 13차 수정] 사용자 보고 — 스냅샷 수정(12차) 이후에도
            // 팝업 상단 텍스트 정보가 여전히 비어 보이는 재현이 있었다.
            // 정확한 원인을 추측 없이 확인하기 위해, 이 핸들러가 실제로
            // 무엇을 캡처하는지 콘솔에 남긴다 — 다음 재현 시 Xcode 콘솔
            // 로그를 확인하면 "탭 시점에 이미 selectedRange가 비어 있었는지"
            // 대 "그 이후 무언가 리셋했는지"를 데이터로 구분할 수 있다.
            // 앞뒤 공백 trim(사용자 요청, 이번 라운드)도 여기서 함께 처리한다.
            actionButton(title: "메모", systemImage: "text.bubble") {
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

            // [2026-08-11 수정] 사용자 요청 — "메모는 관주처럼 항상 활성화되도록.
            // 드래그하지 않아도 절에 종속되도록. 이름을 [개인 주석]으로 변경."
            // [2026-08-12 변경] "개인 주석" → "개인 묵상" 메뉴명 일괄 변경.
            actionButton(title: "개인 묵상", systemImage: "note.text") {
                beginComposingPersonalNote()
            }

            // [2026-08-12 수정] 사용자 정정 — "관주 버튼 → 기존 관주 보기: 내
            // 의도와 다름. 내 의도 -> 새로 만들기 시트 + 기존 관주 보기." 처음엔
            // 겹치는 관주가 있으면 "보기 전용" 팝오버로 대체했는데, 사용자
            // 의도는 그게 아니라 — 새로 만들기 시트(`CrossReferenceTargetPicker`)
            // 는 항상 그대로 열되, 그 시트 "안에" 겹치는 기존 관주 목록도 함께
            // 보여 달라는 것이었다. 그래서 버튼은 다시 무조건 시트를 열고,
            // 겹치는 기존 관주는 `existingReferences`로 시트에 넘겨 그 안에서
            // 보여준다(아래 `.sheet` 참고).
            actionButton(title: "관주", systemImage: "link") {
                isCrossReferencePickerPresented = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .disabled(!isSelecting)
        .opacity(isSelecting ? 1 : 0.35)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 18))
                Text(title).font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var anchorText: String {
        (verseText as NSString).substring(with: selectedRange)
    }

    /// [2026-08-11 13차 수정] 사용자 요청 — "메모 드래그시 앞뒤 텍스트 trim
    /// 처리하여 메모등록할 수 있게 할 것. ex) '더 ', ' 더 ' = '더'." 드래그로
    /// 정확히 단어 경계에 맞추기 어려운 경우가 많아, 실제로 저장되는 메모
    /// 앵커는 앞뒤 공백(스페이스·탭·줄바꿈)을 뺀 알맹이 텍스트와 일치하도록
    /// 범위 자체를 줄인다. 문자를 바꿔치기하는 게 아니라 범위의 시작/끝만
    /// 안쪽으로 옮기는 것이라(길이만 줄어듦) 인덱스가 어긋날 위험이 없다.
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

    /// [2026-08-11 9차 수정] 사용자 보고 — "같은 텍스트에 메모를 두개이상
    /// 입력하면... 수정을 눌렀을 때 관련텍스트 정보와 메모정보가 올바르게
    /// 나오지 않음." 같은 표현에 메모가 여럿이면 `AnnotatedVerseFlowView`의
    /// `.contextMenu`에 "메모 수정"이 그 개수만큼 똑같은 이름으로 나열돼
    /// 사용자가 어느 것을 골랐는지 구별할 수 없었다 — 근본적으로 "한 표현에
    /// 메모는 하나만" 원칙으로 막는 게 맞다고 판단했다. 새 메모를 만들기 전에
    /// 선택한 범위와 겹치는 기존 메모가 있는지 먼저 찾는다 — 있으면 그 메모를
    /// 편집 모드로 열고, 없을 때만 진짜로 새 메모를 만든다.
    /// [2026-08-11 14차 수정] 사용자가 붙여 준 실제 콘솔 로그(`[메모진단]`)로
    /// 확인한 원인 — `editingPhraseNote`/`editingAnchorText`를 설정한 바로 그
    /// 동기 클로저 안에서 `isPhraseNoteEditorPresented = true`까지 같이
    /// 설정하면, 그 `.id(...)` 값(`"new"` 또는 노트 UUID)이 **이 세션에서
    /// 처음 등장하는 경우**(첫 메모 생성, 또는 그 노트를 처음 편집하는 순간)
    /// `PhraseNoteEditorPopover.init`이 빈 문자열/`isEditing: false`를 받는
    /// 게 로그로 실측됐다 — 같은 값으로 두 번째 시도하면 정상 동작했다.
    /// 이는 우리 데이터 흐름의 문제가 아니라(값 자체는 로그에서 항상
    /// 올바르게 계산돼 있었다), SwiftUI `.popover`가 "새 정체성을 처음
    /// 준비하는" 프레임에서 그 정체성의 콘텐츠 클로저를 데이터-상태 변경이
    /// 완전히 커밋되기 전 시점의 스냅샷으로 한 번 평가하는 것으로 보인다
    /// (여러 SwiftUI 개발자 커뮤니티에서 보고된 "팝오버/시트 첫 표시 시
    /// 오래된 데이터" 부류의 알려진 문제와 일치). 데이터 상태 변경
    /// (`editingPhraseNote`/`editingAnchorRange`/`editingAnchorText`)과
    /// 팝오버를 "열라"는 명령(`isPhraseNoteEditorPresented = true`)을 같은
    /// SwiftUI 트랜잭션에 두지 않고, 후자를 다음 런루프 틱으로 한 단계
    /// 미뤄 — 데이터 상태 변경이 완전히 커밋된 뒤에야 팝오버 프레젠테이션
    /// 트랜잭션이 시작되게 한다.
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

    /// [2026-08-12 추가, 2026-08-12 수정] 사용자 요청 — "관주가 있는 텍스트를
    /// 선택하고 관주버튼을 눌렀을 때: 등록된 관주 리스트." 선택 범위와 겹치는
    /// 기존 관주를 전부 골라 `CrossReferenceTargetPicker`(새로 만들기 시트)에
    /// 넘긴다 — 그 시트가 "등록된 관주" 섹션으로 보여준다. 절 전체 관주(구간
    /// 지정 없음)는 겹칠 "특정 표현"이 없어 대상에서 뺀다 —
    /// `VerseAnnotationRenderer.buildLines`가 밑줄을 그릴 때 쓰는 것과 정확히
    /// 같은 자가 치유 앵커링(`resolvedRange`)을 재사용해, 저장된 오프셋이 지금
    /// 본문과 안 맞아도(번역본 데이터가 나중에 고쳐진 경우) `anchorText`로
    /// 다시 찾아 겹침을 판정한다.
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

    /// [2026-09-02 변경] 사용자 요청 — "개인 묵상의 텍스트를 꼭 팝오버에서
    /// 작성을 해야하는가? ... 리스트 항목에 직접 작성을 해서 등록하는 UI는
    /// 불가능한지 검토하라." 검토 후 사용자 확인(1) — 팝오버를 완전히 없애고
    /// 리스트 카드 자체(맨 위의 입력칸)를 여는 방식으로 전환. 예전엔 이 버튼이
    /// `openOrCreateVerseMemo`로 이 절의 (유일한) 절 전체 메모를 찾거나 만들어
    /// 팝오버로 열었는데, 사용자 확인 — "묵상은 한 구절에 하나만 있는 것이
    /// 아니라, 여러개가 등록될 수 있는 요소이다 ... '+ 개인 묵상' 누르면
    /// 리스트 항목이 추가가 되어 새로 등록되는 것"이라, 기존 메모를 찾아
    /// 재사용하지 않고 매번 빈 입력칸을 새로 연다 — 실제 레코드는 아래
    /// `commitNewPersonalNote()`가 "등록"을 눌렀을 때만 만든다.
    private func beginComposingPersonalNote() {
        newPersonalNoteText = ""
        isComposingPersonalNote = true
    }

    /// 위 입력칸의 "등록" 버튼 — 사용자 확인(2) "수정은 지원하지 않는다.
    /// 삭제하고 다시 등록하는 프로세스이다. 자동저장은 하지 않는다."에 따라
    /// 이 버튼을 눌러야만 실제로 저장되고(그 전까지 타이핑은 화면 로컬 상태일
    /// 뿐 DB에 없다), 한 번 만든 뒤엔 고치는 API 자체가 없다(고치려면 리스트의
    /// 삭제 버튼으로 지우고 이 입력칸으로 다시 등록).
    private func commitNewPersonalNote() {
        let trimmed = newPersonalNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.createPersonalNote(verse: verseNumber, contentText: trimmed)
        isComposingPersonalNote = false
        newPersonalNoteText = ""
    }

    /// 사용자 확인(2) — "'+ 개인 묵상'을 눌러 리스트에 입력칸(카드)이 열린 뒤,
    /// 아무것도 쓰지 않고 다른 곳을 탭하면 어떻게 되어야 하나요?" → "그냥
    /// 닫히고 저장 안 됨." 위 `isNewPersonalNoteFieldFocused` 상단 주석 참고 —
    /// 포커스가 빠지는 것을 "다른 곳을 탭함"의 신호로 본다(아래 `body`의
    /// `.onChange(of: isNewPersonalNoteFieldFocused)`). 입력칸의 명시적
    /// "취소" 버튼도 같은 함수를 그대로 부른다 — 결과가 완전히 같기 때문(등록
    /// 안 하고 초안을 버림). `commitNewPersonalNote()`가 먼저
    /// `isComposingPersonalNote = false`로 바꿔 둔 경우(정상 등록)엔 아래
    /// `guard`에 걸려 아무 일도 하지 않는다 — 중복 처리 아님.
    private func discardComposingPersonalNote() {
        guard isComposingPersonalNote else { return }
        isComposingPersonalNote = false
        newPersonalNoteText = ""
    }

    // MARK: - 기존 주석 표시 (2026-08-08 추가)

    /// [2026-08-15 신설, 같은 날 3차 수정] 사용자 요청 — "관주 영역 위에 한문
    /// 단어 뜻풀이 영역을 따로 두어 ... / 영역을 2단으로 나누어서 표시, 중복된
    /// 단어는 제거, 한글+한자 다음줄에 음훈풀이, 한글+한자는 확대보기 성경
    /// 구절 크기와 동일하게, 음훈풀이는 그보다는 작게 현재보다는 크게." /
    /// "그리드간 구분선 추가 / 가운데 정렬 / 음훈풀이 1~2pt 더 크게 / 한자
    /// 옆에 구체적 설명을 하는 링크 아이콘 추가(네이버 한자사전)." 메인 읽기
    /// 화면(`TranslationColumnView`)의 "탭하면 보기" 팝오버가 하던 일(단어 +
    /// 훈음 나열)을 여기로 옮겼다 — `HanjaDictionaryProvider`로 글자별 훈음을
    /// 찾는 방식은 그대로다.
    ///
    /// [2026-08-15 재수정] "그리드간 구분선"을 처음엔 `Grid`/`GridRow`로 구현해
    /// 행(가로)·칸(세로) 구분선을 둘 다 넣었는데, `GridRow` 안의 `Divider()`는
    /// 그 행 하나의 높이만큼만 그려져 행이 여러 개면 세로선이 행마다 끊어져
    /// 보인다(연속된 하나의 중앙 세로선이 아니라 짧은 조각 여러 개) — Grid는
    /// 여러 `GridRow`에 걸쳐 이어지는 셀(행 병합)을 지원하지 않아 이 구조로는
    /// 근본적으로 고칠 수 없다. 2열 그리드라면 "가운데 세로 구분선"이 상식적인
    /// 요청이므로, `Grid`를 버리고 평범한 `VStack`(행)+`HStack`(칸) 위에
    /// `overlay`로 폭 1pt짜리 `Rectangle` 하나를 얹어 전체 높이를 관통하는
    /// 진짜 연속선 하나로 바꿨다. 행 사이 가로 구분선은 그대로 평범한
    /// `Divider()`(가로 스택 안에서는 자동으로 가로선이 된다). 같은 (한글,
    /// 한자) 조합이 절 안에 여러 번 나오면(같은 단어 반복) 첫 등장만
    /// 남긴다(`uniqueHanjaWords`).
    private var hanjaGlossSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("한자 뜻풀이")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                        Divider()
                    }
                }
            }
            .overlay {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// [2026-08-15 신설] 사용자 요청 — "영역을 2단으로 나누어서 표시." 중복
    /// 제거된 단어 목록을 2개씩 짝지어 `GridRow` 하나당 (왼쪽, 오른쪽) 쌍으로
    /// 만든다 — 개수가 홀수면 마지막 쌍의 오른쪽은 nil(빈 칸 처리).
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

    /// [2026-08-15 신설] 그리드 칸 하나 — "가운데 정렬" 요청대로 셀 내용을
    /// 중앙 정렬한다. 한자 옆에 네이버 한자사전 링크 아이콘을 붙인다(사용자
    /// 요청 — "한자 옆에 구체적 설명을 하는 링크 아이콘 추가",
    /// https://hanja.dict.naver.com/#/search?query=한자).
    private func hanjaGlossCell(_ word: HanjaWordAnnotation) -> some View {
        VStack(alignment: .center, spacing: 2) {
            HStack(spacing: 4) {
                // [2026-08-19 수정] 사용자 요청 — "확대보기 한자 뜻풀이의 한자에
                // 조선궁서체 적용." 한글(word.ko)과 한자(word.hanja)를 하나의
                // `Text`로 합쳐 그리던 걸, 서로 다른 `.font()`를 유지한 채 한
                // 줄로 이어 붙여야 했다 — 한글은 기존 성경 본문 글꼴 그대로,
                // 한자만 한자 폰트 설정을 따른다.
                //
                // [2026-08-25 수정, 경고] `Text + Text`(SwiftUI `Text`의 `+`
                // 연산자로 두 `Text`를 이어 붙이는 방식)가 macOS 26에서
                // deprecated됐다. Apple의 경고 메시지("Use string interpolation
                // on Text instead")가 안내하는 단순 문자열 보간(`Text("\(a) \(b)")
                // .font(...)`)으로 바꾸면 폰트 하나만 전체에 적용돼, 이 코드가
                // 원래 요청받은 "한글/한자 각각 다른 폰트"가 깨진다 — 그래서
                // 대신 `AttributedString`의 구간별(run) `.font` 속성으로 같은
                // 결과(두 폰트가 한 줄에 유지)를 내는, 아직 deprecated되지
                // 않은 방식으로 바꿨다.
                {
                    var koText = AttributedString("\(word.ko) ")
                    koText.font = bibleSwiftUIFont
                    var hanjaText = AttributedString(word.hanja)
                    hanjaText.font = hanjaSwiftUIFont
                    return Text(koText + hanjaText)
                }()
                if let url = naverHanjaDictionaryURL(for: word.hanja) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption2)
                    }
                }
            }
            let infos = HanjaDictionaryProvider.shared.infoList(for: word.hanja)
            if !infos.isEmpty {
                // [2026-08-15 변경] 사용자 요청 — "음 훈 뜻풀이 1~2pt 더 크게."
                // 기존 `.subheadline`(기본 크기 약 15pt)에서 16pt로 소폭 확대 —
                // 성경 구절 크기(고정 17pt, `bibleSwiftUIFont`)보다는 여전히
                // 작게 유지하라는 요구와 함께 만족시키는 값.
                Text(infos.map { "\($0.hun)" }.joined(separator: " · "))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    /// [2026-08-15 신설] 네이버 한자사전 검색 URL — 해시(`#`) 뒤가 클라이언트
    /// 라우팅 경로(`/search?query=...`)라 `URLComponents.queryItems`로 만들면
    /// 그 물음표가 해시"앞"(진짜 URL 쿼리)으로 잘못 조립된다 — 대신 리터럴
    /// 문자열에 한자만 퍼센트 인코딩해 끼워 넣는다.
    private func naverHanjaDictionaryURL(for hanja: String) -> URL? {
        guard let encoded = hanja.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://hanja.dict.naver.com/#/search?query=\(encoded)")
    }

    /// [2026-08-15 신설] 사용자 요청 — "중복된 단어는 제거할 것." 같은 절 안에
    /// 같은 (한글단어, 한자) 조합이 여러 번 나올 수 있어(흔치는 않지만
    /// 가능) — 오프셋(`rangeStart`/`rangeEnd`)은 다르더라도 뜻풀이 표시
    /// 목적으로는 같은 항목이라 첫 등장만 남긴다.
    private var uniqueHanjaWords: [HanjaWordAnnotation] {
        var seen = Set<String>()
        var result: [HanjaWordAnnotation] = []
        for word in hanjaWords where seen.insert("\(word.ko)|\(word.hanja)").inserted {
            result.append(word)
        }
        return result
    }

    /// [2026-08-15 신설] 사용자 요청 — "한글+한자: 확대보기의 성경 구절 크기와
    /// 동일하게 키울것." 위 `bibleFont`(PlatformFont, `AnnotatedVerseFlowView`
    /// 등 UIKit/AppKit 기반 렌더러용)와 완전히 같은 글꼴 이름 + 17pt 고정
    /// 크기를 쓰되, `Text(...).font(...)`에 바로 넣을 수 있는 SwiftUI `Font`
    /// 타입으로 만든다.
    private var bibleSwiftUIFont: Font {
        let settings = UserSettingsStore.shared
        guard settings.bibleFontName != "System" else { return .system(size: 17) }
        BundledFontRegistrar.ensureAvailable(settings.bibleFontName)
        return .custom(settings.bibleFontName, size: 17)
    }

    /// [2026-08-19 신설, 2026-08-20 크기 확대] 원래 위 `bibleSwiftUIFont`와 같은
    /// 17pt 고정 크기(확대보기 성경 구절 크기와 동일하게 맞추라는 기존 요청)
    /// 였다 — 이름은 계속 `UserSettingsStore.hanjaFontName`(기본값
    /// 조선궁서체)을 따르되, 사용자 요청("한자 뜻풀이에서 한문을 좀더 키워서
    /// 강조할것")에 맞춰 크기를 26pt로 키우고 굵기를 bold로 올렸다 — 한글
    /// (뜻/음, `bibleSwiftUIFont` 그대로 17pt)보다 한자(원문 글자) 자체가
    /// 시각적으로 먼저 눈에 들어와야 "강조"라는 취지에 맞는다고 판단했다.
    private var hanjaSwiftUIFont: Font {
        UserSettingsStore.shared.hanjaFont(size: 26).weight(.bold)
    }

    private var annotationStatusBar: some View {
        // [2026-08-15 변경] 사용자 요청 — "관주 x개라고 표시된 곳에 관주 개수가
        // 아닌 관주 구절을 가로로 콤마로 구분 + 성경약어로 나열, 인접 구절은
        // 범위로 묶어서, 글씨 크기를 조금만 더 키우기." 이전엔 한 줄 HStack에
        // "관주 N개"/"개인 묵상 N개"/"관련 내용 N개"를 나란히 배치했다 — 관주
        // 라벨이 이제 실제 구절 목록(길어질 수 있음)이라 한 줄에 다 안 들어갈
        // 수 있어, 관주 줄은 따로 빼서 줄바꿈을 허용하고(VStack), 나머지 둘은
        // 기존처럼 한 줄 HStack으로 아래에 둔다.
        VStack(alignment: .leading, spacing: 6) {
            // [2026-08-15 2차 변경] 사용자 요청 — "관주 클릭했을 때 팝업제거
            // (x) -> 관련 성경이동." 이전엔 라벨 전체가 버튼 하나였고 탭하면
            // 이동/삭제 팝오버가 떴다 — 이제 팝오버 없이, 병합된 구절 구간
            // (`crossReferenceInlineSegments`, 예: "고후1:1-2") 각각을 독립된
            // 칩 버튼으로 그려 탭한 칩이 가리키는 구절로 바로 이동한다. 여러
            // 구간이 있으면 칩이 자동으로 줄바꿈되도록 `FlowLayout`(이 파일
            // 하단에 신설)을 쓴다. 삭제(X) 기능은 팝오버와 함께 사라지는 대신
            // 편집모드의 관주 연결 시트("등록된 관주" 목록)로 옮겼다 — 사용자
            // 확인: "삭제기능은 편집모드에 관주버튼 누르면 나오는 관주연결
            // 팝업에서의 리스트에 각 항목별로 (x)를 붙여 삭제기능을 옮길것."
            if !crossReferences.isEmpty {
                // [2026-08-20 변경] 사용자 요청 — "관주 구절을 일반크기로 키울
                // 것." 이 블록 전체가 부모 `annotationStatusBar`의
                // `.font(.caption)`(아래) 아래 있어 원래는 캡션 크기였는데,
                // 칩 텍스트에 별도로 `.footnote`를 얹어 그보다도 더 작게
                // 나왔다 — `.body`(시스템 "일반" 텍스트 크기)로 바꿔 아이콘도
                // 같이 키웠다. 부모의 `.caption`은 여전히 다른 자식(개인
                // 묵상/관련 내용 라벨 등)에 적용되므로 그대로 둔다.
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
                                // [2026-09-02 변경] 사용자 요청 — "메모하기 내
                                // 관주 표시도 목업 html처럼 동일한 스타일로
                                // 할것 (하늘색 배경 + 파란색 글씨)." 밑줄 텍스트
                                // 하나였던 걸 칩 모양(옅은 파란 배경 + 파란
                                // 글씨, 밑줄은 유지)으로 바꿨다.
                                Text(segment.label)
                                    .font(.body)
                                    .underline()
                                    .foregroundStyle(Color.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // [2026-09-02 변경] 사용자 요청 — "개인 묵상을 왼쪽 사이드바
            // '말씀 노트'에서만 보지 말고 구절 클릭 시에도 보여줄 것. 한
            // 구절에 여러 번 묵상할 수 있으므로 리스트로." 목업 확인(옵션
            // 2b) 후 반영 — 탭해야 펼쳐지던 `Menu` 드롭다운을 없애고, 관주
            // 칩 목록 바로 아래에 이 절의 개인 묵상 전부를 카드 목록으로
            // 항상 펼쳐서 보여준다. 카드를 탭하면 기존과 동일하게
            // `onOpenPhraseMemo`로 편집기 시트를 연다. "관련 내용"은 원래도
            // 별도 버튼이었으므로 그대로 아래 자기 줄에 둔다.
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

    /// [2026-09-02 신설] 위 `annotationStatusBar`의 "개인 묵상" 섹션 — 예전
    /// `Menu` 드롭다운을 대체하는 상시 카드 목록. 카드마다 마지막 수정일과
    /// 본문 앞부분(최대 2줄) 미리보기를 보여준다 — `phraseMemos`는 이 절의
    /// 절 전체 메모 + 이 번역본의 표현별 메모를 모두 합친 목록이라(위
    /// `BibleReadingViewModel.phraseMemos(translationCode:verse:)` 참고),
    /// 한 절에 여러 개가 있을 수 있다는 사용자 설명과 정확히 들어맞는다.
    /// [2026-09-02 변경] 사용자 요청 — "개인 묵상의 텍스트를 꼭 팝오버에서
    /// 작성을 해야하는가? ... 리스트 항목에 직접 작성을 해서 등록하는 UI는
    /// 불가능한지 검토하라." 검토 후 확인받은 대로 팝오버를 없애고, 목록
    /// 맨 위에 새 항목 입력칸(`composingPersonalNoteCard`)을 직접 그린다.
    private var personalNoteList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("개인 묵상 \(phraseMemos.count)개", systemImage: "note.text")
            VStack(alignment: .leading, spacing: 6) {
                if isComposingPersonalNote {
                    composingPersonalNoteCard
                }

                ForEach(phraseMemos) { memo in
                    // [2026-09-02 변경] 사용자 확인 — 이 목록엔 사실 두 종류가
                    // 섞여 있다: ① "+ 개인 묵상"으로 만드는 절 전체 메모
                    // (`rangeStart == nil`, 이번 변경으로 수정 미지원·삭제 후
                    // 재등록), ② 텍스트를 드래그 선택한 뒤 "메모" 버튼으로
                    // 만드는 표현별 메모(`rangeStart != nil`, 오늘 요청과
                    // 무관한 기존 기능 — 지금도 카드를 탭하면
                    // `onOpenPhraseMemo`로 편집기를 연다). 사용자 확인 —
                    // "②만 계속 탭해서 수정 가능" — 그래서 탭 가능 여부를
                    // `rangeStart` 유무로 가른다. 삭제 버튼은 두 종류 모두에
                    // 그대로 유지(기존 동작 — "개인묵상 리스트에 삭제버튼을
                    // 추가할 것" 요청이 종류를 구분하지 않았다).
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
                    .padding(8)
                    .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
                    )
                }
            }
        }
    }

    /// 위 `personalNoteList`의 카드 한 장의 본문(날짜 + 미리보기) — 탭
    /// 가능한 표현별 메모(`Button` 라벨)와 탭 불가능한 절 전체 메모(맨몸)가
    /// 똑같은 모양을 공유하도록 분리했다.
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

    /// [2026-09-02 신설] "+ 개인 묵상"을 누르면 위 `personalNoteList` 맨
    /// 위에 뜨는 새 항목 입력칸. 사용자 확인(3) — 카드 배경색(연노랑 + 노란
    /// 테두리)은 다른 카드와 동일하게 유지. 사용자 확인(2) — 자동저장은
    /// 하지 않으므로 "등록"을 눌러야만 `commitNewPersonalNote()`가 실제로
    /// 저장하고, "취소"를 누르거나(또는 아무것도 안 쓰고 다른 곳을 탭해
    /// 포커스를 잃으면) `discardComposingPersonalNote()`가 그냥 입력칸을
    /// 닫는다 — 이 두 경우 다 DB엔 아무것도 남지 않는다.
    private var composingPersonalNoteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $newPersonalNoteText)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 160)
                .focused($isNewPersonalNoteFieldFocused)
                .onChange(of: newPersonalNoteText) { _, newValue in
                    // `UserMemo.contentText`의 저장 규칙과 같다 — "글자수
                    // 2000자 제한"(`MemoTextLimit` 참고, 예전
                    // `PersonalNoteEditorPopover`와 동일한 제한을 그대로 옮김).
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
        .padding(8)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
        )
        .onAppear {
            // 새로 뜬 입력칸에 바로 타이핑을 시작할 수 있도록 커서를 둔다 —
            // `PersonalNoteEditorPopover`가 없어졌으니 그 팝오버가 하던
            // 포커스 이동 역할을 이 카드 스스로 진다.
            isNewPersonalNoteFieldFocused = true
        }
        .onChange(of: isNewPersonalNoteFieldFocused) { _, focused in
            if !focused {
                discardComposingPersonalNote()
            }
        }
    }

    /// [2026-08-15 신설] 이 절에 걸린 `VerseCrossReference` 레코드 전부에서
    /// 실제 대상 구절(`targets`)만 한데 모아 중복을 없앤다 — 아래
    /// `crossReferenceInlineSegments`가 이 목록을 정경 순서로 정렬하고 인접
    /// 구절을 범위로 묶는다.
    private var allCrossReferenceVerses: [BibleVerseRef] {
        Array(Set(crossReferences.flatMap(\.targets)))
    }

    /// [2026-08-15 신설, 같은 날 2차 수정] 사용자 요청 — "관주 구절을 가로로
    /// 콤마로 구분 + 성경약어로 나열, 인접한 구절끼리는 묶어서 표현(고후1:1,
    /// 고후1:2 → 고후1:1-2)." / "클릭했을 때 팝업제거 (x) -> 관련 성경이동."
    /// 정경 순서(책 orderIndex → 장 → 절)로 정렬한 뒤, 같은 책·같은 장에서
    /// 절 번호가 1씩 연속이면 "장:시작-끝" 구간 하나로 합친다. 처음엔 다 이어
    /// 붙인 문자열 하나(`crossReferenceInlineLabel`)를 만들었지만, 그러면
    /// 구간 하나를 골라 이동할 방법이 없어(버튼 하나 = 전체 문자열) 이제
    /// 구간별로 (라벨, 그 구간이 가리키는 절들)을 따로 반환한다 — 호출부
    /// (`annotationStatusBar`)가 구간마다 독립된 탭 버튼(칩)으로 그린다.
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

/// [2026-08-15 신설] 사용자 요청 — "관주 클릭했을 때 팝업제거 (x) -> 관련
/// 성경이동." 관주 구간마다 독립된 탭 버튼(칩)으로 그리되, 구간 개수가
/// 많으면 한 줄에 다 안 들어갈 수 있어 자동으로 줄바꿈되는 배치가 필요했다.
/// SwiftUI `HStack`은 줄바꿈을 지원하지 않고, 이 프로젝트 최소 배포 버전
/// (iOS17+/macOS14+, README "이어서 62" 등 여러 곳에서 이미 전제)은 SwiftUI
/// `Layout` 프로토콜(iOS16+/macOS13+)을 문제없이 쓸 수 있어, 표준적인
/// "줄바꿈되는 가로 나열" 커스텀 레이아웃을 직접 구현했다 — 서드파티
/// 의존성 없이 라인 하나짜리 요구사항(칩 여러 개 줄바꿈)에 맞는 최소
/// 구현이다.
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
