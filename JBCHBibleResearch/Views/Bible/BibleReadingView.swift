//
//  BibleReadingView.swift
//  JBCHBibleResearch
//
//  S1(성경 조회) — 다중 번역본 병렬 조회 화면. screens.md 3장/4장/10장 근거:
//  - macOS/iPadOS: 최대 3열 동시 표시(HStack), 중앙 기준 스크롤 동기화.
//  - iPhone: 1열 + 스와이프(TabView 페이징) — "레이아웃만 축소, 기능 동일"이라
//    스크롤 동기화 자체는 그대로 두되(각 페이지가 독립 컬럼이라 실질적으로 한 번에
//    하나만 보임), 여러 컬럼이 동시에 보이지 않으므로 동기화 결과를 눈으로 확인할
//    일이 macOS/iPadOS보다 적다.
//  - 10.3: S1은 순수 뷰어라 primary/accent 버튼이 없다 — 여기 있는 버튼들(이전/다음 장,
//    책/장 선택, 번역본 선택)은 전부 탐색용이지 "생성/저장" 같은 주 동작이 아니다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct BibleReadingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: BibleReadingViewModel?

    /// 2026-08-07(S11) 추가 — 기본은 nil이라 기존 호출부(사이드바/탭바에서 매개변수
    /// 없이 그냥 `BibleReadingView()`로 쓰는 곳)의 동작은 전혀 바뀌지 않는다.
    /// 통합 검색(S11)에서 구절 결과를 탭했을 때 그 구절이 있는 책/장으로 바로
    /// 열기 위해서만 쓴다(SearchView.swift 참고).
    ///
    /// [2026-08-08 추가] `initialChapter`를 `Int = 1`에서 `Int? = nil`로 바꿨다 —
    /// 사용자 요청("다른 메뉴 이동 후 성경조회로 돌아오면 직전 위치 유지")을 구현하려면
    /// "장을 명시적으로 지정하지 않음"과 "1장을 명시적으로 지정함"을 구분해야 하는데,
    /// 기존 `Int = 1` 기본값으로는 이 둘을 구분할 수 없었다(항상 1이 넘어감). nil이면
    /// `BibleReadingViewModel.init`이 `LastBiblePositionTracker`(마지막으로 보던 위치)로
    /// 폴백한다 — `initialBook`도 nil일 때만 그렇게 한다(SearchView.swift처럼 책까지
    /// 명시한 호출은 "명확한 사용자 의도"로 보고 마지막 위치를 무시한다).
    var initialBook: Book? = nil
    var initialChapter: Int? = nil
    /// [2026-08-08 추가] 사용자 요청 — macOS에서 "성경 조회 새 창"으로 연 보조
    /// 창은 관련 콘텐츠(인스펙터)/조회 이력 아이콘을 빼야 한다. 기본값 true는
    /// 기존 호출부(사이드바/탭바에서 매개변수 없이 그냥 `BibleReadingView()`로
    /// 쓰는 곳, 즉 "주 창"에 표시되는 인스턴스)의 동작을 그대로 유지한다 —
    /// `JBCHBibleResearchApp.swift`의 `WindowGroup(id: "bible-reading")`(새 창
    /// 전용 Scene)만 명시적으로 `false`를 넘긴다.
    var isPrimaryWindow: Bool = true

    var body: some View {
        Group {
            if let viewModel {
                BibleReadingContentView(viewModel: viewModel, isPrimaryWindow: isPrimaryWindow)
            } else {
                ProgressView()
                    .onAppear {
                        let vm = BibleReadingViewModel(modelContext: modelContext, initialBook: initialBook, initialChapter: initialChapter)
                        vm.onAppear()
                        viewModel = vm
                    }
            }
        }
    }
}

/// [2026-08-08 추가] 아이폰 스와이프 정렬 — "이 컬럼(columnID)을 이 절(verse)로
/// 맞춰라"는 1회성 명령. `Equatable`이라 `.onChange(of:)`로 관찰할 수 있다.
private struct PhoneAlignmentTarget: Equatable {
    let columnID: UUID
    let verse: Int
}

private struct BibleReadingContentView: View {
    @Environment(\.modelContext) private var modelContext
    /// [2026-08-07 추가] 사용자 요청 — "성경 조회 창은 여러 개를 띄울 수 있어야
    /// 하고, 각 창마다 다른 성경을 동시에 조회할 수 있어야 한다." 메뉴(AppCommands.swift
    /// "성경 조회 새 창")뿐 아니라 이 화면 툴바에도 아이콘으로 진입점을 둔다.
    @Environment(\.openWindow) private var openWindow
    let viewModel: BibleReadingViewModel
    /// [2026-08-08 추가] `BibleReadingView.isPrimaryWindow` 상단 주석 참고 —
    /// false면(macOS 보조 창) 관련 콘텐츠/조회 이력 아이콘을 툴바에서 뺀다.
    let isPrimaryWindow: Bool
    @State private var isTranslationPickerPresented = false
    /// screens.md 5장 — 절 클릭 컨텍스트 메뉴의 "메모 작성"으로 만든 새 메모를
    /// 시트로 띄운다. `.sheet(item:)`은 UserMemo가 SwiftData `@Model`이라 이미
    /// Identifiable을 만족하므로 별도 래퍼 없이 바로 쓸 수 있다.
    /// [2026-08-08 추가] 관련 콘텐츠 패널에서 기존 메모를 탭했을 때도 이 상태를
    /// 재사용한다 — 새로 만든 메모든 기존 메모든 "이 메모를 시트로 편집기에
    /// 띄운다"는 동작 자체는 똑같기 때문.
    @State private var memoBeingCreated: UserMemo?
    /// [2026-08-08 추가] 관련 콘텐츠 패널(ChapterRelatedContentPanel) 표시 여부 —
    /// `.inspector(isPresented:)`에 연결한다. 한때 실기기 크래시 때문에
    /// `.sheet`로 바꿨다가, 진짜 원인이 `.inspector`가 아니라 이 화면에서
    /// `@FocusedValue(\.selectSection)`를 읽던 것(자체 툴바가 있는 뷰에서 읽으면
    /// 툴바 무한 재계산 루프가 남)으로 밝혀져(`AppNavigationRequest.swift` 상단
    /// 주석 참고) 원래 요청대로 다시 `.inspector`로 되돌렸다.
    @State private var isRelatedContentPresented = false
    /// [2026-08-08 추가] 조회 이력(히스토리) 시트 표시 여부 — `BibleReadingHistorySheet`
    /// 참고. 보조 사이드 패널(`.inspector`)과 달리 이력 목록은 "가끔 열어 보는" 용도라
    /// 상시 노출할 필요가 없어 시트로 띄운다.
    @State private var isHistoryPresented = false
    /// [2026-08-08 추가] 아이폰 스와이프 정렬용 — `phoneColumns`의 `TabView`
    /// 선택 상태. 페이지가 바뀔 때마다 새로 보이는 컬럼을 정렬시킨다.
    @State private var selectedPhoneColumnID: UUID?
    /// [2026-08-08 추가] 방금 페이지가 바뀌어 "이 컬럼을 이 절로 맞춰라"라고
    /// 명령한 대상 — `phoneColumns`/`TranslationColumnView.pendingCenterAlignment`
    /// 참고.
    @State private var phoneAlignmentTarget: PhoneAlignmentTarget?
    /// [2026-08-08 추가] 구간 주석(형광펜/표시/메모/관주) — "구절 확대보기" 시트
    /// 표시 여부. `verseSelectionActionBar`의 새 버튼이 켠다(정확히 절 1개가
    /// 선택돼 있을 때만 보인다).
    @State private var isVerseZoomPresented = false
    /// [2026-08-08 추가] 확대보기에서 "메모" 액션으로 만든 구간 메모를, 확대보기
    /// 시트가 완전히 닫힌 뒤 이어서 편집기 시트로 열기 위한 임시 저장소 — 같은
    /// 화면(BibleReadingContentView)이 시트를 두 개 동시에 띄울 수 없어서, 확대보기
    /// `.sheet`의 `onDismiss`에서 이 값을 확인해 `memoBeingCreated`로 넘긴다.
    @State private var pendingPhraseMemo: UserMemo?
    /// [2026-08-09 추가] "원문 정보"(히브리어/그리스어 원어 단어별 Strong번호+음역+
    /// 영어+한글) 시트 표시 여부 — `verseSelectionActionBar`의 "확대보기" 옆 버튼이
    /// 켠다. 원문은 번역본과 무관하게 book/chapter/verse에만 종속되므로(구절
    /// 확대보기와 달리) 별도의 열 선택 상태가 필요 없다.
    @State private var isOriginalTextInfoPresented = false
    /// [2026-08-12 추가] 사용자 요청 — "성경 구절 선택시 확대보기 오른쪽 옆
    /// [말씀 요약]버튼 ... 기존 [관련 내용] 인스펙터 자리를 재사용하되 필기가
    /// 용이하도록 넓게." nil이 아니면 그 값이 곧 "지금 인스펙터에 말씀 요약
    /// 편집기를 띄우는 중"이라는 신호다 — `isRelatedContentPresented`(관련 내용
    /// 패널)와 자리를 공유하되 내용만 바뀐다(아래 `.inspector` 참고).
    @State private var wordSummaryBeingEdited: VerseSummary?
    /// 말씀 요약 편집기를 여는 동안에만 기준 번역본 하나로 줄인 번역본 목록 —
    /// 편집을 마치면 이 값으로 되돌린다(사용자 확인 — "편집 종료 시 자동 복원").
    /// nil이면 "지금 좁혀 놓은 상태가 아님"을 뜻한다.
    @State private var displayedTranslationIDsBeforeWordSummary: [PersistentIdentifier]?
    /// [2026-08-12 추가] `WordSummaryEditorView.externalProxy` 상단 주석 참고 —
    /// 하단 액션바의 [말씀 복사] 버튼이 이 프록시를 통해 인스펙터 안의 리치
    /// 텍스트뷰 커서 위치에 직접 삽입한다.
    @State private var wordSummaryProxy = RichTextEditingProxy()
    /// [2026-08-12 추가] 사용자 요청 — "말씀 구절과 오른쪽 사이드바 에디터
    /// 영역의 비율을 50:50으로 하게 할것." `.inspectorColumnWidth`는 고정 pt
    /// 값만 받고 화면 폭 비율을 직접 알 방법이 없어, 이 화면(인스펙터가 아직
    /// 열리기 전 = 성경 본문이 전체 폭을 다 쓰고 있는 상태)의 실제 렌더 폭을
    /// 아래 `.background`의 `GeometryReader`로 계속 측정해 뒀다가, 인스펙터가
    /// 열리는 "그 순간"의 값을 절반으로 얼려서 쓴다(`openWordSummaryEditor()`
    /// 참고). 인스펙터가 열린 뒤에는 본문 폭 자체가 줄어들어 이 값을 계속
    /// 실시간으로 다시 재는 방식은 "줄어든 폭의 절반 → 인스펙터가 더 좁아짐 →
    /// 본문이 다시 넓어짐 → ..." 식으로 매 프레임 흔들리는 피드백 루프가 될 수
    /// 있어 피했다.
    @State private var lastMeasuredContentWidth: CGFloat = 0
    /// 말씀 요약을 여는 순간 `lastMeasuredContentWidth`의 절반으로 고정한 값 —
    /// nil이면 "지금 50:50 모드가 아님"을 뜻한다.
    @State private var wordSummaryInspectorWidth: CGFloat?

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// [2026-08-12 추가] "말씀 요약" 첫 줄("현재날짜 '말씀'")용 — 요청 문구
    /// 그대로 "년.월.일" 숫자 표기를 쓴다(다른 화면의 날짜 표기와 맞출 근거
    /// 문서가 따로 없어 가장 무난한 표기를 골랐다).
    private static let wordSummaryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    /// [2026-08-08 추가] 사용자 요청 — "아이패드에서는 새 창 아이콘 빼기",
    /// "아이폰에서는 새 창 아이콘 빼기" — 즉 "성경 조회 새 창"은 macOS
    /// 전용이다(다른 두 요청이 각각 아이폰/아이패드에서 이 아이콘을 빼 달라고
    /// 했으므로, 남는 건 macOS뿐).
    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// [2026-08-08 추가] 사용자 보고 — "아이패드 오른쪽 상단에 관련 콘텐츠/조회
    /// 이력 아이콘이 안 보임". `.primaryAction`은 iOS에서 "적응형" 배치라, 툴바
    /// 공간이 빠듯하면 OS가 알아서 항목을 "···" 더 보기 메뉴로 접어 버릴 수
    /// 있다 — 아이콘이 사라진 게 아니라 더 보기 메뉴 안에 숨어 있었을 가능성이
    /// 크다. iOS 전용 `.topBarTrailing`(더 명시적으로 "항상 상단 바 오른쪽에"
    /// 배치)으로 바꿔 이 적응형 축소를 피한다. macOS엔 이 케이스가 없어(넉넉한
    /// 툴바 폭) 기존 `.primaryAction`을 그대로 쓴다.
    private var trailingIconPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            if let lastErrorDescription = viewModel.lastErrorDescription {
                Text(lastErrorDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            if viewModel.columns.isEmpty {
                emptyState
            } else if isPhone {
                phoneColumns
            } else {
                sideBySideColumns
            }
        }
        // [2026-08-12 추가] 위 `lastMeasuredContentWidth`/`wordSummaryInspectorWidth`
        // 상단 주석 참고 — 레이아웃에 영향을 주지 않는 `.background`에 넣어
        // 순수하게 폭 측정 용도로만 쓴다.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { lastMeasuredContentWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        guard wordSummaryBeingEdited == nil else { return }
                        lastMeasuredContentWidth = newValue
                    }
            }
        )
        // [2026-08-08 추가] 사용자 보고 — "아이패드에서 성경검색, 성경 장이동
        // 기능 없음". 이전엔 `chapterNavigationControls`(이전/다음 장 버튼 +
        // 책/장 선택 버튼 + 자유 텍스트 검색창 + "이동" 버튼)를 툴바
        // `.principal` 자리에 넣었었다 — macOS는 툴바 폭이 넉넉해 문제가 없었지만,
        // 아이패드(특히 세로/Split View)는 내비게이션 바의 principal 영역 폭이
        // 훨씬 좁고, 양옆(leading/trailing)에도 다른 툴바 버튼(관련 콘텐츠/조회
        // 이력/새 창 등)이 있어 이 HStack 전체가 들어갈 자리가 없으면 iOS가 그냥
        // 통째로 안 보이게 처리하는 것으로 보인다 — "기능이 아예 없다"는 증상과
        // 정확히 들어맞는다. 그래서 툴바에서 빼고, 화면 하단 액션바(바로 아래
        // `verseSelectionActionBar`)와 같은 원칙으로 상단 세이프에어리어 인셋에
        // 항상 표시되는 별도 줄로 옮겼다 — 화면 전체 너비를 그대로 쓸 수 있어
        // 좁은 화면에서도 잘리지 않는다.
        // [2026-08-08 추가] 사용자 요청 — "상단 공백 영역을 반으로 줄일 수
        // 있도록". 세로 패딩을 8pt→4pt로 줄였다(가로 패딩은 좌우 버튼이
        // 화면 끝에 바짝 붙지 않게 하는 최소한의 여백이라 그대로 둔다).
        .safeAreaInset(edge: .top) {
            chapterNavigationControls
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(.bar)
        }
        // [2026-08-08 추가] 사용자 요청 — 절 선택 → 클립보드 복사. 선택이 하나도
        // 없으면 아예 안 보이게 해서, 평소 화면(순수 뷰어)을 방해하지 않는다
        // (OCRReviewView의 하단 액션바와 같은 배치 원칙).
        .safeAreaInset(edge: .bottom) {
            if viewModel.hasVerseSelection {
                verseSelectionActionBar
            }
        }
        .sheet(item: $memoBeingCreated, onDismiss: {
            // [2026-08-08 추가] 메모를 새로 만들었거나 내용을 고친 뒤 닫으면,
            // 관련 콘텐츠 패널의 메모 목록/순서(최신 수정순)가 곧바로 반영되도록
            // 새로고침한다.
            viewModel.refreshRelatedContent()
        }) { memo in
            NavigationStack {
                // [2026-08-09 변경] 사용자 요청 — 성경 조회 사이드바/확대보기에서
                // 여는 메모는 좌표가 이미 정해진 채로 열리므로 `.contextual`을
                // 넘긴다(좌표 선택 UI 제거 + 전용 서식 — MemoDetailView.swift
                // 상단 주석 참고). "내 메모" 탭(MemoHomeView)은 이 콜사이트를
                // 거치지 않으므로 영향이 없다.
                MemoDetailView(memo: memo, presentationContext: .contextual)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기") { memoBeingCreated = nil }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 420)
            #endif
        }
        // [2026-08-08 신설, 크래시 조사 끝에 원래 배치로 복귀] 사용자 요청 —
        // "성경 장을 읽을 때 이 장의 개요/메모/연구문서가 있다는 것을 한번에
        // 확인". 사용자가 고른 "보조 사이드 패널"(창 폭이 넓으면 상시 노출,
        // 좁으면 모달처럼 접힘) 배치 그대로 `.inspector(isPresented:)`로 구현.
        //
        // ⚠️ 한때 실기기 크래시 때문에 `.sheet`로 바꿨던 적이 있다 — 그런데
        // `.sheet`로 바꾼 뒤에도 완전히 같은 크래시가 재현돼, `.inspector`는
        // 애초에 원인이 아니었다는 게 드러났다. 진짜 원인은 이 화면(자체
        // `.toolbar`를 가진 뷰)에서 `@FocusedValue(\.selectSection)`을 읽은 것 —
        // 그 값을 게시하는 쪽(SidebarNavigationView)이 클로저(비교 불가능한 값)를
        // 넘기다 보니, 그 화면이 다시 그려질 때마다 "포커스 값이 바뀌었다"는
        // 신호가 나갔고, 툴바를 가진 뷰가 그 신호를 받으면 툴바를 다시 계산하며
        // 레이아웃 무효화 루프에 빠졌다(자세한 내용은 `AppNavigationRequest.swift`
        // 상단 주석). 그 부분을 고친 뒤로는 `.inspector`를 그대로 써도 안전하다.
        // [2026-08-12 변경] 사용자 요청 — "말씀 요약" 편집기가 이 인스펙터 자리를
        // 재사용한다(사용자 확인 — "기존 [관련 내용] 인스펙터 자리를 재사용하되
        // 필기가 용이하도록 넓게"). 두 콘텐츠(관련 내용/말씀 요약)가 같은 자리를
        // 두고 배타적으로 나오므로, `isPresented` 바인딩을 두 상태를 합친
        // 계산값으로 바꾸고 `set`에서 "닫힘"을 감지해 말씀 요약 쪽이면 뒷정리
        // (번역본/사이드바 복원)까지 같이 처리한다 — 인스펙터의 자체 접기
        // 동작(코너의 화살표 등 시스템 UI)으로 닫아도 이 경로를 그대로 탄다.
        .inspector(isPresented: Binding(
            get: { isRelatedContentPresented || wordSummaryBeingEdited != nil },
            set: { newValue in
                guard !newValue else { return }
                if wordSummaryBeingEdited != nil {
                    closeWordSummaryEditor()
                }
                isRelatedContentPresented = false
            }
        )) {
            Group {
                if let wordSummaryBeingEdited {
                    // [2026-08-12] `ChapterRelatedContentPanel`과 같은 원칙 —
                    // 이 패널도 자체 닫기 버튼을 두지 않는다(`.inspector` 안에
                    // `.toolbar`를 얹는 조합은 이 코드베이스에서 실기기 검증된
                    // 적이 없어 굳이 새로 시도하지 않았다). 닫기는 아래 툴바의
                    // "관련 콘텐츠" 버튼(말씀 요약 중엔 "닫기"로 동작하도록 바꿈,
                    // `toolbarContent` 참고)과 시스템이 제공하는 인스펙터 접기
                    // 동작 두 경로로 처리한다.
                    WordSummaryEditorView(
                        summary: wordSummaryBeingEdited, presentationContext: .contextual,
                        externalProxy: wordSummaryProxy
                    )
                } else {
                    // [2026-08-15 변경] `onJumpToOutline` 콜백을 없앴다 — 사용자
                    // 요청으로 "개요 화면 열기" 버튼이 다시 메인 내비게이션 전환
                    // (`AppNavigationRequest`) 방식으로 돌아갔고(이 창 자체는 폐기
                    // 하지 않음, `WindowGroup(id: "outline")`은 여전히 존재), "별도
                    // 창에서 보기"는 완전히 새로운 전용 창(`outline-quick-view`)을
                    // 쓰게 되면서, 이 패널이 그 두 요청을 직접(싱글턴을 통해) 보낸다
                    // — `ChapterRelatedContentPanel.swift`의 `jumpToOutlineEditor`/
                    // `openOutlineQuickViewWindow` 상단 주석 참고. 그래서 이 뷰가
                    // 더 이상 클로저를 만들어 넘길 필요가 없다.
                    ChapterRelatedContentPanel(
                        viewModel: viewModel,
                        onSelectMemo: { memo in
                            memoBeingCreated = memo
                        },
                        // [2026-08-12 추가] "[관련 말씀 요약]" — 기존 항목을 고르면
                        // 같은 자리에서 그대로 편집기로 이어 연다.
                        // ⚠️ 이 인자는 반드시 `selectedVerse`보다 앞에 와야 한다 —
                        // 전부 레이블을 붙여 호출해도 Swift는 선언 순서
                        // (`ChapterRelatedContentPanel`의 프로퍼티 순서)와 다르면
                        // "Argument 'X' must precede argument 'Y'" 컴파일 에러를
                        // 낸다(레이블이 있어도 순서 자유가 아니다 — 여기서 실제로
                        // 겪은 에러).
                        onSelectWordSummary: presentWordSummaryEditor,
                        // [2026-08-11 추가] "구절 선택 후 오른쪽 사이드바 [관련 내용]" —
                        // 정확히 절 하나가 선택돼 있을 때만 넘긴다(위 ChapterRelatedContentPanel.
                        // selectedVerse 상단 주석 참고).
                        selectedVerse: viewModel.selectedVerses.count == 1 ? viewModel.selectedVerses.first : nil,
                        onSelectVerseMention: handleVerseMentionSelected
                    )
                }
            }
            // [2026-08-12 변경] 사용자 요청 — "말씀 구절과 오른쪽 사이드바
            // 에디터 영역의 비율을 50:50으로 하게 할것." 위
            // `wordSummaryInspectorWidth`(연 시점에 측정해 얼려 둔 절반 값)를
            // min/ideal/max에 모두 같은 값으로 넣어 사실상 고정폭처럼 동작하게
            // 한다 — `.inspectorColumnWidth`가 세 값 사이에서 자유롭게 고르게
            // 두면(예: 창을 늘렸다 줄였다 할 때) 50:50이 흐트러질 수 있어서다.
            // 아직 측정 전(0)이면 이전의 근사값(아이패드 절반 정도)으로 폴백한다.
            // 관련 내용 패널은 기존 폭 그대로 유지.
            .inspectorColumnWidth(
                min: wordSummaryBeingEdited != nil ? (wordSummaryInspectorWidth ?? 380) : 260,
                ideal: wordSummaryBeingEdited != nil ? (wordSummaryInspectorWidth ?? 520) : 300,
                max: wordSummaryBeingEdited != nil ? (wordSummaryInspectorWidth ?? 520) : 400
            )
        }
        // [2026-08-12 추가] 안전망 — 말씀 요약 편집기가 열린 채로 이 화면 자체가
        // 사라지면(예: 사이드바에서 다른 섹션으로 이동) 위 `.inspector`의
        // `set` 클로저가 아예 호출되지 않을 수 있다 — 그러면 번역본 열이 좁혀진
        // 채, 바깥쪽 사이드바가 닫힌 채로 영영 남는다. 화면이 사라질 때 한 번 더
        // 뒷정리를 강제한다.
        .onDisappear {
            closeWordSummaryEditor()
        }
        // [2026-08-08 신설] 조회 이력 시트.
        .sheet(isPresented: $isHistoryPresented) {
            BibleReadingHistorySheet(viewModel: viewModel) {
                isHistoryPresented = false
            }
            #if os(macOS)
            .frame(minWidth: 360, minHeight: 420)
            #endif
        }
        // 11장 Bible 메뉴 "다음 장 ⌘]" / "이전 장 ⌘[", View 메뉴 "스크롤 동기화" —
        // AppCommands.swift 참고.
        .focusedSceneValue(\.nextChapterAction) { viewModel.nextChapter() }
        .focusedSceneValue(\.previousChapterAction) { viewModel.previousChapter() }
        .focusedSceneValue(\.scrollSyncEnabled, Binding(
            get: { viewModel.scrollSyncCoordinator.isEnabled },
            set: { viewModel.scrollSyncCoordinator.isEnabled = $0 }
        ))
        // [2026-08-08 재배치, 두 번째 근본 원인 조사] 사용자가 "내 메모" 화면은
        // 타이틀·아이콘이 정상적으로 보인다고 확인해줬다 — 그 화면과 이 화면의
        // 결정적 차이는 이 화면에만 있는 `.inspector(isPresented:)`다.
        // `.navigationTitle`/`.toolbar`를 이 modifier 체인 "앞쪽"(즉 `.inspector`
        // 보다 안쪽 레이어)에 선언해 두면, `.inspector`가 그 콘텐츠를 감싸면서
        // 타이틀/툴바 프리퍼런스가 바깥쪽 NavigationStack까지 제대로 전달되지
        // 못하고 `.inspector`가 만드는 중간 레이어 안에 갇힐 가능성이 있다고
        // 보고, `.navigationTitle`/`.toolbar`를 `.inspector`/`.sheet`들보다
        // 뒤(= 그것들을 전부 감싸는 가장 바깥쪽 레이어)로 옮겼다. 이러면
        // 이 뷰의 최종 결과물 전체에 타이틀/툴바가 씌워져, 중간의 `.inspector`
        // 레이어와 무관하게 바깥쪽 NavigationStack에 곧바로 전달돼야 한다.
        .navigationTitle("성경 조회")
        // [2026-08-08 추가] 사용자 보고 — "아이패드 [성경 조회] 상단에 알 수 없는
        // 넓은 빈 영역". 원인: 이 화면만 자체 상단 바(이전/다음 장 + 책/장 선택 +
        // 검색창, `.safeAreaInset(edge: .top)`)를 하나 더 갖고 있는데,
        // `.navigationTitle`이 iOS 기본값인 "큰 제목(large title)" 모드로
        // 표시되면 그 큰 제목 영역(글자 자체는 작아도 위아래 여백이 상당함) 위에
        // 이 커스텀 바까지 더해져 헤더 전체가 비정상적으로 커진다 — 다른
        // 화면(내 메모/연구문서/개요 등)은 이런 추가 상단 바가 없어 큰 제목이어도
        // 눈에 띄게 크지 않았다. 이 화면만 컴팩트한 "inline" 모드로 강제해 큰
        // 제목이 차지하던 여유 공간을 없앤다. (macOS엔 이 모디파이어 자체가 없어
        // `#if os(iOS)`로 감싼다.)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
    }

    /// screens.md 13.1 — 성경조회(S1)에서 절 클릭 → "메모 작성"은 클릭한 정확한
    /// (book_id, chapter, verse)로 채워진다.
    private func createMemo(for verse: BibleVerse) {
        let memo = UserMemo(bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse)
        modelContext.insert(memo)
        try? modelContext.save()
        // [2026-08-11 추가] 이벤트 기반 인덱싱 — 이 생성 경로가 누락돼 있었다.
        // 다른 메모 생성 지점(MemoHomeView.createNewMemo/
        // BibleReadingViewModel.createPhraseMemo/openOrCreateVerseMemo)과
        // 동일하게 저장 직후 호출한다.
        BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
        memoBeingCreated = memo
    }

    /// [2026-08-08 추가] 관주 팝오버에서 대상 구절을 탭했을 때 — 그 책/장으로
    /// 이동한다. 정확한 절 위치로 스크롤까지 맞추는 것은 이번 구현 범위 밖이다
    /// (README "이어서 17" 참고) — `TranslationColumnView.centerVerseID`가
    /// private이라 밖에서 직접 지정할 방법이 없고, 아이폰 스와이프 정렬처럼
    /// 새 상태 전달 경로를 또 만들 만큼 이 기능에 필수적이지 않다고 판단했다.
    private func jumpToCrossReferenceTarget(_ target: BibleVerseRef) {
        guard let book = BooksProvider.shared.book(id: target.bookId) else { return }
        viewModel.selectBook(book, chapter: target.chapter)
    }

    /// [2026-08-11 추가] 사용자 요청 — "[관련 내용]을 클릭하면 팝업으로 띄워 해당
    /// 성경장절이 검색어로 검색되어 해당 구절로 바로 이동... 연구 문서는 pdf로
    /// 띄워 검색." 메모는 기존 "메모 작성" 시트 흐름을 그대로 재사용하고(이미
    /// 어느 절 것인지 정해진 채 열리는 `.contextual` 팝업), 연구문서는 새
    /// "document-search" 창(JBCHBibleResearchApp.swift 참고)을 검색어와 함께 연다.
    private func handleVerseMentionSelected(_ mention: VerseMention) {
        switch mention.sourceType {
        case .memo:
            if let memo = viewModel.resolveMemo(for: mention) {
                memoBeingCreated = memo
            }
        case .document:
            if let document = viewModel.resolveDocument(for: mention) {
                openWindow(
                    id: "document-search",
                    value: DocumentSearchRequest(documentID: document.persistentModelID, searchText: mention.searchText)
                )
            }
        // [2026-08-12 추가] "[관련 말씀 요약]"도 개인 묵상과 같은 방식으로
        // 다룬다 — 이미 있는 말씀 요약을 인스펙터 편집기로 연다(번역본 좁히기/
        // 사이드바 닫기 등은 `presentWordSummaryEditor(_:)`가 새로 만들 때와
        // 동일하게 처리한다).
        case .wordSummary:
            if let summary = viewModel.resolveWordSummary(for: mention) {
                presentWordSummaryEditor(summary)
            }
        }
    }

    /// [2026-08-12 신설, 2026-08-12 2차 수정] 사용자 요청 — "성경 구절 선택시
    /// 확대보기 오른쪽 옆 [말씀 요약]버튼 ... 기준 번역본 성경(맨 왼쪽 성경)만
    /// 남기고, 왼쪽 사이드바 닫고 ... 에디터 제일 첫줄: 현재날짜 '말씀', 그
    /// 다음줄: 선택된 성경구절 자동입력." "매번 새 글 생성"(사용자 확인)
    /// 방식이라 누를 때마다 새 `VerseSummary`를 만든다 — 이미 그 절의 요약이
    /// 있어도 이어 쓰는 게 아니라 새 레코드다(저널/묵상노트 성격, `VerseSummary`
    /// 모델 상단 주석 참고).
    ///
    /// [2026-08-12 2차 수정] 사용자 요청 — "성경구절을 2개이상 선택시에도 하단의
    /// 버튼이 유지될것." 단일 절만 받던 것을 선택된 절 전체(`viewModel.
    /// selectedVerses`)로 넓혔다 — 좌표(`VerseSummary.verse`)는 정렬된 첫 절을
    /// "앵커"로 저장하고(목록/좌표 표시는 여전히 절 하나가 필요하므로), 프리필
    /// 본문은 선택된 절 전체를 `BibleVerseCopyFormatter`가 지원하는 "이어진 구간/
    /// 떨어진 구간" 표기로 채운다.
    private func openWordSummaryEditor() {
        let verses = viewModel.selectedVerses
        guard let anchorVerse = verses.sorted().first else { return }

        let dateText = Self.wordSummaryDateFormatter.string(from: .now)
        let verseText = viewModel.formattedBaseTranslationText(forVerses: verses) ?? ""
        let seedText = verseText.isEmpty ? "\(dateText) 말씀" : "\(dateText) 말씀\n\(verseText)"

        let summary = VerseSummary(
            bookId: viewModel.selectedBook.bookId,
            chapter: viewModel.selectedChapter,
            verse: anchorVerse,
            // `contentHtml`은 실제로는 RTF 저장소다(RichTextEditor.swift 상단
            // 주석) — `{\rtf1`로 시작하지 않는 일반 문자열을 넣으면 "레거시
            // 텍스트"로 인식돼 기본 서식으로 표시된다. 여기서는 그 경로를 그대로
            // 이용해 프리필한다(별도 RTF 인코딩 불필요).
            contentHtml: seedText,
            contentText: seedText
        )
        modelContext.insert(summary)
        try? modelContext.save()
        // [2026-08-12 추가] 개인 묵상/연구문서와 같은 프로세스로 저장 직후
        // 관련 성경구절을 추출해 인덱싱한다(과제 #12 — `handleVerseMentionSelected`/
        // `ChapterRelatedContentPanel`의 "관련 말씀 요약" 섹션이 이 인덱스를 쓴다).
        BibleReferenceIndexingService.reindexWordSummary(summary, context: modelContext)
        presentWordSummaryEditor(summary)
    }

    /// [2026-08-12 신설] `openWordSummaryEditor()`(새로 만들기)와 "관련 말씀
    /// 요약"/"[관련 내용]"에서 기존 항목을 고르는 경우가 공유하는 "편집기 열기"
    /// 절차 — 번역본 열 좁히기/왼쪽 사이드바 닫기/인스펙터 50:50 폭 고정을
    /// 똑같이 적용한다.
    private func presentWordSummaryEditor(_ summary: VerseSummary) {
        // 번역본 열 좁히기 — 나중에 정확히 되돌릴 수 있도록 지금 상태를 먼저
        // 저장해 둔다. 이미 편집기가 열려 있는 상태에서 다시 호출됐다면(예: 관련
        // 콘텐츠 패널에서 다른 항목을 연달아 고름) 기존 저장값을 덮어쓰지 않는다.
        if displayedTranslationIDsBeforeWordSummary == nil {
            displayedTranslationIDsBeforeWordSummary = viewModel.displayedTranslationIDs
        }
        if let baseID = viewModel.displayedTranslationIDs.first {
            viewModel.setDisplayedTranslations([baseID])
        }

        // 왼쪽(바깥쪽) 사이드바 닫기 — macOS/iPadOS에서만 의미가 있다
        // (SidebarVisibilityRequest.swift 상단 주석 참고). 아이폰 탭바 레이아웃은
        // 이 요청을 구독하지 않아 조용히 무시된다.
        SidebarVisibilityRequest.shared.requestHide()

        // [2026-08-12 추가] 사용자 요청 — "말씀 구절과 오른쪽 사이드바 에디터
        // 영역의 비율을 50:50으로." 인스펙터가 열리기 직전(=아직 본문이 전체
        // 폭을 다 쓰고 있는 지금) 측정된 폭의 절반을 얼려 둔다 — 위
        // `lastMeasuredContentWidth` 상단 주석 참고. 이미 열려 있던 상태에서
        // 다른 항목으로 갈아타는 경우엔 폭을 다시 재지 않는다(이미 좁아진 본문
        // 폭 기준으로 재면 값이 계속 작아지는 문제 — 위 프로퍼티 상단 주석 참고).
        if wordSummaryInspectorWidth == nil {
            wordSummaryInspectorWidth = lastMeasuredContentWidth / 2
        }

        wordSummaryBeingEdited = summary
    }

    /// 말씀 요약 편집기를 닫으면서 번역본 열/사이드바를 편집 시작 전 상태로
    /// 되돌린다(사용자 확인 — "편집 종료 시 자동 복원").
    private func closeWordSummaryEditor() {
        guard wordSummaryBeingEdited != nil else { return }
        wordSummaryBeingEdited = nil
        if let previousIDs = displayedTranslationIDsBeforeWordSummary {
            viewModel.setDisplayedTranslations(previousIDs)
        }
        displayedTranslationIDsBeforeWordSummary = nil
        wordSummaryInspectorWidth = nil
        SidebarVisibilityRequest.shared.requestRestore()
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("표시할 번역본이 없습니다. 번역본을 등록해 주세요.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phoneColumns: some View {
        // [2026-08-08 변경] 사용자 요청 — "아이폰에서 스크롤 실시간 동기화는
        // 하지 않아도 됨. 단 스와이프해서 번역본을 넘길 때 다음 번역본의 절
        // 위치가, 넘기기 전 화면 정가운데 절 위치가 되도록." 한 번에 컬럼
        // 하나만 보이는 아이폰에서는 다른 컬럼이 안 보이는 동안 계속 실시간
        // 애니메이션으로 따라다닐 필요가 없다 — `TranslationColumnView.
        // respondsToSyncEvents: false`로 그 동작을 끄고, 대신 페이지가 바뀌는
        // 순간에만 `pendingCenterAlignment`로 한 번 맞춘다.
        TabView(selection: $selectedPhoneColumnID) {
            ForEach(viewModel.columns) { column in
                TranslationColumnView(
                    columnID: column.id,
                    translationDisplayName: column.registry.displayName,
                    localizedBookChapterLabel: column.localizedBookChapterLabel,
                    verses: column.verses,
                    errorDescription: column.errorDescription,
                    onCreateMemo: createMemo,
                    selectedVerses: viewModel.selectedVerses,
                    onSelectSingleVerse: viewModel.selectSingleVerse,
                    onToggleVerseSelection: viewModel.toggleVerseSelection,
                    onExtendVerseSelection: viewModel.extendVerseSelection,
                    coordinator: viewModel.scrollSyncCoordinator,
                    respondsToSyncEvents: false,
                    pendingCenterAlignment: phoneAlignmentTarget?.columnID == column.id ? phoneAlignmentTarget?.verse : nil,
                    highlightsProvider: { verse in viewModel.highlights(translationCode: column.registry.code, verse: verse) },
                    crossReferencesProvider: { verse in viewModel.crossReferences(translationCode: column.registry.code, verse: verse) },
                    phraseMemosProvider: { verse in viewModel.phraseMemos(translationCode: column.registry.code, verse: verse) },
                    phraseNotesProvider: { verse in viewModel.phraseNotes(translationCode: column.registry.code, verse: verse) },
                    marginalNotesProvider: { verse in viewModel.marginalNotes(translationCode: column.registry.code, verse: verse) },
                    hanjaWordsProvider: { verse in viewModel.hanjaWords(translationCode: column.registry.code, verse: verse) },
                    verseMentionsProvider: { verse in viewModel.verseMentions(verse: verse) },
                    onSelectCrossReferenceTarget: jumpToCrossReferenceTarget,
                    onSelectPhraseMemo: { memo in memoBeingCreated = memo },
                    onSelectVerseMention: handleVerseMentionSelected
                )
                .tag(column.id)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: viewModel.columns.count > 1 ? .always : .never))
        #endif
        .onChange(of: selectedPhoneColumnID) { _, newValue in
            // 방금까지 보고 있던(=스크롤 가능했던 유일한) 컬럼이 리더로서 마지막
            // 보고한 중앙 절을 그대로 새로 보이는 컬럼에 넘긴다. 아직 아무도
            // 스크롤한 적이 없으면(latestEvent == nil) 아무 것도 하지 않는다 —
            // 각 컬럼이 원래(장 첫머리) 위치를 그대로 보여준다.
            guard let newValue, let verse = viewModel.scrollSyncCoordinator.latestEvent?.verse else { return }
            phoneAlignmentTarget = PhoneAlignmentTarget(columnID: newValue, verse: verse)
        }
    }

    private var sideBySideColumns: some View {
        HStack(spacing: 0) {
            ForEach(Array(viewModel.columns.enumerated()), id: \.element.id) { index, column in
                if index > 0 { Divider() }
                TranslationColumnView(
                    columnID: column.id,
                    translationDisplayName: column.registry.displayName,
                    localizedBookChapterLabel: column.localizedBookChapterLabel,
                    verses: column.verses,
                    errorDescription: column.errorDescription,
                    onCreateMemo: createMemo,
                    selectedVerses: viewModel.selectedVerses,
                    onSelectSingleVerse: viewModel.selectSingleVerse,
                    onToggleVerseSelection: viewModel.toggleVerseSelection,
                    onExtendVerseSelection: viewModel.extendVerseSelection,
                    coordinator: viewModel.scrollSyncCoordinator,
                    highlightsProvider: { verse in viewModel.highlights(translationCode: column.registry.code, verse: verse) },
                    crossReferencesProvider: { verse in viewModel.crossReferences(translationCode: column.registry.code, verse: verse) },
                    phraseMemosProvider: { verse in viewModel.phraseMemos(translationCode: column.registry.code, verse: verse) },
                    phraseNotesProvider: { verse in viewModel.phraseNotes(translationCode: column.registry.code, verse: verse) },
                    marginalNotesProvider: { verse in viewModel.marginalNotes(translationCode: column.registry.code, verse: verse) },
                    hanjaWordsProvider: { verse in viewModel.hanjaWords(translationCode: column.registry.code, verse: verse) },
                    verseMentionsProvider: { verse in viewModel.verseMentions(verse: verse) },
                    onSelectCrossReferenceTarget: jumpToCrossReferenceTarget,
                    onSelectPhraseMemo: { memo in memoBeingCreated = memo },
                    onSelectVerseMention: handleVerseMentionSelected
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 절 선택 → 클립보드 복사 (2026-08-08 추가)

    private var verseSelectionActionBar: some View {
        HStack {
            Text("\(viewModel.selectedVerses.count)개 절 선택됨")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            // [2026-08-12 변경] 사용자 요청 — "말씀 요약 상태일 때 왼쪽 성경 영역
            // 하단 버튼 변화 -> [선택 해제][복사][말씀 요약]버튼 제거, [말씀 복사]
            // 추가." 편집기가 열려 있는 동안은 이 줄 전체가 "지금 편집 중인 요약에
            // 구절을 보태는" 용도로 바뀐다 — 원래 있던 확대보기/원문 정보/말씀
            // 요약/선택 해제/복사는 편집 중엔 의미가 없거나 혼란을 준다고 판단해
            // 감췄다.
            if wordSummaryBeingEdited != nil {
                Button {
                    copySelectedVersesIntoWordSummary()
                } label: {
                    Label("말씀 복사", systemImage: "text.insert")
                }
                .buttonStyle(.borderedProminent)
                // [2026-08-12] "1구절 이상 선택할때 항상 [말씀 복사]버튼 활성화" —
                // 바깥쪽 `.safeAreaInset`이 이미 `hasVerseSelection`(1개 이상)일
                // 때만 이 바 자체를 그리므로, 여기선 추가 조건이 필요 없다.
            } else {
                // [2026-08-08 추가] 구간 주석(형광펜/표시/메모/관주) 진입점 —
                // README "이어서 16" 설계 논의에서 사용자가 직접 제안한 방식.
                // 절을 여러 개 골랐을 때는 "어느 절을 확대할지" 모호해지므로,
                // 정확히 1개일 때만 보인다(말씀 요약과 달리 이 두 기능은 태생적으로
                // "절 하나"를 다룬다 — VerseZoomView/OriginalTextInfoView 모두
                // 단일 verseNumber를 받는다).
                if viewModel.selectedVerses.count == 1 {
                    Button {
                        isVerseZoomPresented = true
                    } label: {
                        Label("확대보기", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    // [2026-08-09 추가] 사용자 요청 — "확대보기 버튼 옆에 '원문 정보'라는
                    // 버튼이 있어 히브리어 그리스어 원문에 대한 정보를 넣고자 함."
                    Button {
                        isOriginalTextInfoPresented = true
                    } label: {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                }
                // [2026-08-12 변경] 사용자 요청 — "성경구절을 2개이상 선택시에도
                // 하단의 버튼이 유지될것. 현재는 한구절일때만 뜨게 됨." 말씀
                // 요약은 확대보기/원문 정보와 달리 여러 절을 한 번에 요약해도
                // 자연스러워, 정확히 1개가 아니라 "1개 이상"이면 노출한다.
                if !viewModel.selectedVerses.isEmpty {
                    Button {
                        openWordSummaryEditor()
                    } label: {
                        Label("말씀 요약", systemImage: "text.book.closed")
                    }
                }
                Button("선택 해제") { viewModel.clearVerseSelection() }
                Button {
                    copySelectedVerses()
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
        .sheet(isPresented: $isVerseZoomPresented, onDismiss: {
            // [2026-08-08 추가] 확대보기에서 "메모"를 만들었으면, 확대보기 시트가
            // 완전히 닫힌 뒤 이어서 편집기 시트를 연다 — 같은 화면이 시트 두 개를
            // 동시에 띄울 수 없어 순서를 맞춘 것(위 `pendingPhraseMemo` 상단
            // 주석 참고).
            if let memo = pendingPhraseMemo {
                pendingPhraseMemo = nil
                memoBeingCreated = memo
            }
        }) {
            if let verseNumber = viewModel.selectedVerses.first {
                VerseZoomView(
                    verseNumber: verseNumber, columns: viewModel.columns, viewModel: viewModel,
                    onOpenPhraseMemo: { memo in pendingPhraseMemo = memo },
                    onJumpToCrossReference: jumpToCrossReferenceTarget,
                    onSelectVerseMention: handleVerseMentionSelected
                )
            }
        }
        .sheet(isPresented: $isOriginalTextInfoPresented) {
            if let verseNumber = viewModel.selectedVerses.first {
                OriginalTextInfoView(
                    bookId: viewModel.selectedBook.bookId,
                    chapter: viewModel.selectedChapter,
                    verseNumber: verseNumber
                )
            }
        }
    }

    /// 뷰모델이 환경설정대로 만들어 준 문자열을 플랫폼 클립보드에 넣는다.
    /// `BibleReadingViewModel.formattedCopyText()` 상단 주석 참고 — 플랫폼 API
    /// (UIPasteboard/NSPasteboard) 분기는 뷰 레이어의 책임이다.
    private func copySelectedVerses() {
        guard let text = viewModel.formattedCopyText() else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// [2026-08-12 신설] 사용자 요청 — "[말씀 복사] 탭/클릭시 오른쪽 사이드바
    /// 에디터 커서 위치한 곳에 성경구절 복사 붙여넣기 실행." 클립보드를 거치지
    /// 않고 `wordSummaryProxy`(위 상단 주석 참고)로 곧바로 인스펙터 안의 텍스트뷰에
    /// 삽입한다 — 기준 번역본 한 곳(`formattedBaseTranslationText`, 말씀 요약을
    /// 열 때 이미 그 한 열로 좁혀 둔 상태와 일치)만 쓰는 게 `copySelectedVerses()`
    /// (지금 보이는 모든 번역본)와의 차이다.
    private func copySelectedVersesIntoWordSummary() {
        guard !viewModel.selectedVerses.isEmpty,
              let text = viewModel.formattedBaseTranslationText(forVerses: viewModel.selectedVerses) else { return }
        wordSummaryProxy.insertTextAtCursor(text)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // [2026-08-08 이동] `chapterNavigationControls`(이전/다음 장 + 책/장
        // 선택 + 검색창)는 더 이상 여기(툴바 `.principal`) 두지 않는다 — 위
        // `.safeAreaInset(edge: .top)` 참고. 좁은 화면(아이패드 등)에서 통째로
        // 사라지는 문제가 있었다.
        //
        // [2026-08-08 추가] 사용자 요청 — "타이틀을 좀 더 크게 볼드체로". iOS
        // 기본 inline 타이틀(17pt, semibold 정도)은 굵기·크기를 직접 바꿀 수
        // 없어, `.principal` 자리에 직접 스타일을 준 `Text`를 넣어 대체한다.
        // `.navigationTitle`은 그대로 남겨 둔다(윈도우 전환기/음성 제어 등
        // 시스템이 내부적으로 쓰는 제목은 계속 필요하다) — 이 `.principal`
        // 아이템이 화면에 실제로 보이는 타이틀을 시각적으로만 덮어쓴다. macOS는
        // 창 제목 표시줄(타이틀 바)이 이미 `.navigationTitle`을 그대로 보여주고
        // 있고 그건 시스템 chrome이라 앱이 굵기를 바꿀 수 없다 — 여기에 같은
        // 글자를 툴바에 또 하나 굵게 띄우면 창 제목이 중복돼 보일 수 있어
        // iOS(아이폰/아이패드)에만 적용한다.
        #if os(iOS)
        ToolbarItem(placement: .principal) {
            Text("성경 조회")
                .font(.title2)
                .fontWeight(.bold)
        }
        #endif
        //
        // [2026-08-08 변경] 사용자 요청 3건을 한 번에 반영 — "① macOS 보조
        // 창(새 창으로 연 것)에서는 관련 콘텐츠/조회 이력 아이콘을 뺀다, ②
        // 아이패드는 새 창 아이콘 자체를 빼고 관련 콘텐츠/조회 이력만 남긴다
        // (아이콘이 너무 많아 툴바가 좁은 화면에서 넘쳐 안 보였던 문제도 겸사
        // 겸사 줄어든다), ③ 아이폰도 새 창 아이콘을 뺀다(멀티 씬을 지원하지
        // 않아 누르면 크래시가 났다 — 아래 참고)." 정리하면: 관련 콘텐츠/조회
        // 이력은 "주 창"에서는 모든 플랫폼에 보이고 macOS 보조 창에서만 빠지고,
        // "성경 조회 새 창"은 macOS에서만 보인다(아이폰/아이패드는 플랫폼
        // 특성상 별도 창 개념이 없거나 지원하지 않는다).
        if isPrimaryWindow {
            // [2026-08-08 추가] 관련 콘텐츠 패널(개요/메모/연구문서) 토글 — 항상
            // 활성화(다른 토글형 버튼들과 같은 원칙). 아이콘은 표준 "inspector" 심벌.
            ToolbarItem(placement: trailingIconPlacement) {
                // [2026-08-12 변경] 말씀 요약 편집기가 이 자리를 빌려 쓰는 동안은
                // (`wordSummaryBeingEdited != nil`) 이 버튼이 `isRelatedContentPresented`를
                // 건드려 봐야 인스펙터가 계속 열려 있다(위 `.inspector`의 `get`이
                // `wordSummaryBeingEdited != nil`도 함께 보기 때문) — 그래서 이
                // 경우엔 같은 버튼이 "닫기"(뒷정리 포함)로 동작하도록 바꾼다.
                Button {
                    if wordSummaryBeingEdited != nil {
                        closeWordSummaryEditor()
                    } else {
                        isRelatedContentPresented.toggle()
                    }
                } label: {
                    if wordSummaryBeingEdited != nil {
                        Label("말씀 요약 닫기", systemImage: "xmark.circle")
                    } else {
                        Label("관련 콘텐츠", systemImage: "sidebar.trailing")
                    }
                }
                .help(wordSummaryBeingEdited != nil ? "말씀 요약 편집 마치기" : "이 장의 개요·메모·연구문서 보기")
            }
            // [2026-08-08 추가] 조회 이력(히스토리) 진입점.
            // [2026-08-12 변경] 사용자 요청 — "[맥OS] 오른쪽 사이드바 에디터
            // 영역의 상단버튼 중 닫기 버튼 왼쪽 3개 버튼을 없앨 수 있으면
            // 없앨것." 말씀 요약 편집 중엔 조회 이력/새 창/번역본 선택 세
            // 버튼이 편집을 방해하는 잡음이라 판단해 감춘다(닫기 버튼만 남음).
            if wordSummaryBeingEdited == nil {
                ToolbarItem(placement: trailingIconPlacement) {
                    Button {
                        isHistoryPresented = true
                    } label: {
                        Label("조회 이력", systemImage: "clock")
                    }
                    .help("최근 조회한 책/장 이력 보기")
                }
            }
        }
        // [2026-08-07 추가, 2026-08-08 macOS 전용으로 범위 축소] "성경 조회 새
        // 창" 아이콘 진입점. 메뉴(AppCommands.swift)와 같은 동작. 아이폰은
        // 멀티 씬(여러 창)을 지원하지 않아 이 버튼을 누르면 "Unable to open a
        // window when the app does not support multiple scenes" 크래시가
        // 났다 — 사용자 요청대로 아이패드와 함께 아이폰에서도 아예 뺀다.
        if isMac && wordSummaryBeingEdited == nil {
            ToolbarItem(placement: trailingIconPlacement) {
                Button {
                    openWindow(id: "bible-reading")
                } label: {
                    Label("성경 조회 새 창", systemImage: "macwindow.badge.plus")
                }
                .help("성경 조회 새 창으로 열기")
            }
        }
        if viewModel.availableTranslations.count > viewModel.maxColumns && wordSummaryBeingEdited == nil {
            ToolbarItem(placement: trailingIconPlacement) {
                Button {
                    isTranslationPickerPresented = true
                } label: {
                    Label("번역본 선택", systemImage: "text.book.closed")
                }
                .popover(isPresented: $isTranslationPickerPresented) {
                    TranslationPickerPopover(
                        available: viewModel.availableTranslations,
                        selected: viewModel.columns.map(\.registry.persistentModelID),
                        maxSelection: viewModel.maxColumns
                    ) { selected in
                        viewModel.setDisplayedTranslations(Array(selected))
                        isTranslationPickerPresented = false
                    }
                }
            }
        }
    }

    private var chapterNavigationControls: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.previousChapter()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.selectedChapter <= 1)

            BookChapterPicker(
                books: BooksProvider.shared.books,
                selectedBook: viewModel.selectedBook,
                selectedChapter: viewModel.selectedChapter
            ) { book, chapter in
                viewModel.selectBook(book, chapter: chapter)
            }

            Button {
                viewModel.nextChapter()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        // [2026-08-08 추가] 툴바 principal 자리(폭 제한)에서 상단 세이프에어리어
        // 인셋(화면 전체 너비)으로 옮기면서 가운데 정렬을 유지하려고 추가.
        .frame(maxWidth: .infinity)
    }
}
