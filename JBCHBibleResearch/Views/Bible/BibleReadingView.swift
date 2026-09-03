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
    /// [2026-08-19 추가] 사용자 요청 — "검색 결과중 - 성경구절을 클릭하면
    /// 해당하는 절까지 스크롤 이동해서 잠시 하이라이트 표시해줄것." nil이면
    /// (기존 호출부 전부) 동작이 전혀 바뀌지 않는다 — `SearchView.verseRow`만
    /// 이 값을 넘긴다.
    var initialVerse: Int? = nil
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
                        // [2026-08-19 추가] `onAppear()`가 끝난 시점엔 이 장의
                        // 절 목록이 이미 로드돼 있다(`reloadVerses()`가 동기
                        // 호출이라 — `BibleReadingViewModel.selectBook` 참고) —
                        // 그래서 여기서 바로 강조를 걸어도 안전하다.
                        //
                        // [2026-08-25 추가] 사이드바 "최근" 이력(형광펜/메모/관주)
                        // 항목을 탭했을 때(`SidebarNavigationView.navigateToBibleVerse`,
                        // `BibleVerseNavigationRequest.swift` 상단 주석 참고) — 다른
                        // 섹션에 있다가 이 화면(`.bibleReading`, 매개변수 없는 단일
                        // 상시 인스턴스)으로 막 전환돼 `viewModel`이 새로 만들어지는
                        // 경로다. `initialBook`/`initialChapter`(둘 다 nil, 이
                        // 인스턴스는 SearchView처럼 그 값을 넘겨받지 않는다)로는
                        // 표현할 수 없는 목표 좌표라 별도로 처리한다 — 이미 떠 있는
                        // 채로 다시 탭한 경우는 `BibleReadingContentView`의
                        // `.onChange(of: BibleVerseNavigationRequest.shared.pendingTarget)`가
                        // 대신 처리한다(이 `.onAppear`는 재생성될 때만 실행되므로).
                        if let target = BibleVerseNavigationRequest.shared.pendingTarget,
                           let book = BooksProvider.shared.book(id: target.bookId) {
                            vm.selectBook(book, chapter: target.chapter)
                            vm.highlightVerseTemporarily(target.verse)
                            BibleVerseNavigationRequest.shared.clear()
                        } else if let initialVerse {
                            vm.highlightVerseTemporarily(initialVerse)
                            // [2026-08-26 추가] 사용자 요청 — "왼쪽 사이드바 상단
                            // 검색기능을 통해 직접 성경 장절로 이동을 한경우는
                            // 히스토리 이력에 남김." 이 분기는 `SearchView.verseRow`가
                            // `initialVerse`를 넘겨 이 화면을 새로 띄운 경로뿐이다 —
                            // `init`이 `selectBook`을 거치지 않아(위 주석) 장 단위
                            // 기록조차 안 남았으므로, 여기서 장:절을 함께 기록한다.
                            vm.recordVerseHistory(verse: initialVerse)
                        }
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

/// [2026-08-26 신설] `VerseTextSelectionPopover` 상단 주석 참고 — 컨텍스트
/// 메뉴 [선택]이 연 팝오버가 어느 절/번역본을 대상으로 하는지 담는다.
/// `.popover(item:)`이 `Identifiable`을 요구해 `id`를 두되, 매번 새로 여는
/// 팝오버라 값 비교보다 "다른 인스턴스인가"만 중요하므로 `UUID()`로 충분하다.
private struct PartialTextSelectionTarget: Identifiable {
    let id = UUID()
    let verseNumber: Int
    let translationDisplayName: String
    let text: String
    // [2026-08-27 신설] 개역한글(번들 성경)일 때 "선택" 팝오버 안에서 한자
    // 주석까지 함께 보이고 복사되도록 넘겨주는 해당 절의 한자 단어 목록.
    // KRV가 아닌 번역본은 `viewModel.hanjaWords(...)`가 항상 빈 배열을
    // 돌려주므로(BibleReadingViewModel의 기존 가드), 이 필드를 무조건
    // 채워 넘겨도 다른 번역본 동작에는 영향이 없다.
    let hanjaWords: [HanjaWordAnnotation]
}

#if os(iOS)
/// [2026-08-21 신설, 빌드에러 수정] `verseSelectionActionBar`(아래)가 사용자
/// 요청 — "세로보기에서 탭하면 하단 메뉴는 한글 메뉴명은 빼고 아이콘만
/// 나오도록" — 을 구현하려던 코드가 `.labelStyle(isNarrow ? .iconOnly :
/// .automatic)`(삼항 연산자)로 되어 있었는데, 이게 Xcode 빌드 에러였다:
/// `.iconOnly`(`IconOnlyLabelStyle`)와 `.automatic`(`DefaultLabelStyle`)은
/// 서로 다른 구체 타입이라 삼항 연산자가 "공통 타입"을 찾지 못해 컴파일이
/// 안 된다(`LabelStyle` 프로토콜은 연관 타입이 있어 두 구체 타입을 하나로
/// 합칠 수 없다). `ViewModifier.body(content:)`는 `@ViewBuilder`라 if/else
/// 분기(`_ConditionalContent`로 감싸져 서로 다른 구체 타입이어도 허용됨)는
/// 문제없이 컴파일된다 — 그래서 삼항 연산자 대신 이 작은 전용
/// `ViewModifier`로 옮겼다(로직 의도는 그대로: 세로 좁은 화면이면 아이콘만,
/// 아니면 기존 기본 스타일).
private struct BottomBarLabelStyleModifier: ViewModifier {
    let isNarrow: Bool
    func body(content: Content) -> some View {
        if isNarrow {
            // [2026-08-26 수정] 사용자 요청 — "아이콘만 나올수 있도록 + 아이콘
            // 크기를 조금 더 키울것"(아이폰)/"아이콘 크기를 조금 더 키우고..."
            // (아이패드 세로모드) — 텍스트가 사라진 만큼(iconOnly) 아이콘을
            // 키워야 탭 영역과 시인성이 유지된다. `.imageScale`은 SF Symbol
            // 아이콘 크기만 키우고 폰트(이 앱이 쓰는 커스텀 Paperlogy 등)나
            // 다른 텍스트 크기엔 영향을 주지 않는, 이 목적에 정확히 맞는
            // API다.
            content
                .labelStyle(.iconOnly)
                .imageScale(.large)
        } else {
            content.labelStyle(.automatic)
        }
    }
}

/// [2026-08-26 신설] 사용자 요청 — "iOS - 아이패드 ... 성경 이동버튼(히스토리
/// 이전, 이전장, 다음장, 히스토리 다음)을 동그라미 버튼으로 하되 UX/UI
/// 측면에서 사용자들이 버튼 누르기에 불편하지 않도록 처리 -> iOS - 아이폰
/// 가로보기 할때도 적용할 수 있도록(세로보기는 현행 그대로)." 아이폰
/// 세로보기/macOS는 이 모디파이어를 아예 붙이지 않아(호출부 `chapterNavigationControls`
/// 참고) 기존 모습이 그대로 유지된다.
///
/// 지름 44pt는 애플 HIG가 명시하는 탭 가능 영역 최소 크기다 — SF Symbol
/// 아이콘 글리프 자체는 이보다 훨씬 작으므로, `.contentShape(Circle())`이
/// 없으면 아이콘 밖 원 여백을 눌러도 반응하지 않아 "버튼 누르기에 불편함"이
/// 오히려 그대로 남는다(사용자가 명시적으로 지적한 요구사항).

/// [2026-08-27 신설] 사용자 요청 — "iOS 아이폰 성경 조회 세로보기 - 구절 탭 시
/// 나타나는 하단 메뉴(`verseSelectionActionBar`) UI 수정: 각각의 아이콘을
/// 동그란 도형에 넣어서 버튼간 간격을 넓히고 버튼의 이미지라는 것을 좀더
/// 명확히 할것." 아이콘 전용(`.iconOnly`)으로 보일 때만 — 즉
/// `BottomBarLabelStyleModifier`가 같은 `isNarrow` 값으로 라벨을 아이콘만
/// 남길 때만 — 원형 배경을 준다. 아이콘+글자가 함께 보이는 상태(가로보기 등)
/// 에서는 이 요청 대상이 아니고, 원 안에 텍스트까지 넣으면 잘리거나 어색해질
/// 뿐이라 적용하지 않는다(그 경우 `content`를 그대로 돌려줘 기존 모습 그대로
/// 유지).
///
/// 지름은 새 숫자를 만들지 않고 바로 위 `CircularNavButtonModifier`(상단 장
/// 이동 버튼)가 이미 쓰는 44pt(애플 HIG 최소 탭 영역)를 그대로 재사용한다.
///
/// `isProminent`는 기존에 `.buttonStyle(.borderedProminent)`로 강조되던
/// [복사]/[말씀 복사] 버튼의 시각적 우선순위(진한 배경+흰 아이콘)를 보존하기
/// 위한 구분이다. narrow면(아래 `if isNarrow`) 원형 배지(진한 accent 채우기
/// +흰 아이콘)로, narrow가 아니면 `else if isProminent`에서 예전과 같은
/// `.buttonStyle(.borderedProminent)`를 이 모디파이어가 직접 낸다 — 호출부가
/// 별도로 `.buttonStyle(.borderedProminent)`를 체이닝해 두고 이 모디파이어와
/// "어느 `.buttonStyle` 호출이 이기는지" 순서에 기대는 방식은 검증 없이는
/// 확신할 수 없어(추측 금지) 쓰지 않았다 — 항상 이 모디파이어 하나가
/// `.buttonStyle`을 딱 한 번만 호출해 애매함이 없게 했다. 그 외 버튼
/// (확대보기/원문 정보/말씀 요약/선택 해제)은 원래도 `.buttonStyle`을 따로
/// 지정하지 않았으므로 `isProminent: false`로 옅은 배경을 준다.
private struct ActionBarCircularIconModifier: ViewModifier {
    let isNarrow: Bool
    let isProminent: Bool
    func body(content: Content) -> some View {
        if isNarrow {
            content
                .buttonStyle(.plain)
                .frame(width: CircularNavButtonModifier.diameter, height: CircularNavButtonModifier.diameter)
                .background(
                    Circle().fill(isProminent ? Color.accentColor : Color.accentColor.opacity(0.12))
                )
                .foregroundStyle(isProminent ? Color.white : Color.accentColor)
                .contentShape(Circle())
        } else if isProminent {
            // [2026-08-27 신설] narrow가 아닐 때(가로보기/아이패드 등)는 예전
            // 그대로 `.borderedProminent`(진한 배경 pill 버튼)를 써야 한다.
            // 호출부에서 이 모디파이어와 별개로 `.buttonStyle(.borderedProminent)`를
            // 또 체이닝해 "두 개의 .buttonStyle 호출 중 어느 쪽이 이기는지"에
            // 기대는 대신(추측 금지 — 검증 없이 SwiftUI의 중복 환경값 우선순위를
            // 가정하지 않는다), 이 분기 자체가 그 스타일을 직접 낸다 — 어느
            // 경우든 `.buttonStyle` 호출은 딱 하나뿐이라 애매함이 없다.
            content.buttonStyle(.borderedProminent)
        } else {
            content
        }
    }
}

private struct CircularNavButtonModifier: ViewModifier {
    static let diameter: CGFloat = 44
    /// 호출부(`chapterNavigationControls`)가 `isCompactChapterNavButtons`를
    /// 그대로 넘긴다 — false(아이폰 세로보기)면 이 모디파이어가 완전히
    /// 아무것도 하지 않아 예전 모습(디폴트 버튼 스타일) 그대로다. 호출부에서
    /// `#if os(iOS)`로 감싸는 대신 이렇게 항상 붙이고 내부에서 분기하는 이유는
    /// 위 `BottomBarLabelStyleModifier`와 같다 — 버튼 4개마다 `#if`를 반복하는
    /// 것보다 한 곳에서 조건을 관리하는 편이 낫다.
    let isCircular: Bool
    func body(content: Content) -> some View {
        if isCircular {
            content
                .buttonStyle(.plain)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                .contentShape(Circle())
        } else {
            content
        }
    }
}
#endif

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
    /// [2026-08-28 신설, 실기기 크래시 fix] 사용자 보고 — "성경조회 인스펙터 >
    /// 관련 연구문서 클릭시 반응없음" 진단·수정 과정에서 별도로 발견된 크래시:
    /// "Unable to open a window when the app does not support multiple scenes."
    /// `handleVerseMentionSelected`(아래)의 `.document` 분기가 "본문에서
    /// 언급됨"(자동 추출) 문서를 항상 `openWindow(id: "document-search", ...)`로
    /// 열었는데, 이 자리는 `taggedDocuments`(바로 위 "이 장에 연결됨" 문서
    /// 목록)의 `isPhoneIdiom` 분기와 달리 플랫폼 구분이 아예 없었다 — 다중 씬을
    /// 지원하지 않는 아이폰에서 100% 크래시로 이어진다(`DocumentsHomeView.swift`
    /// 등 이 코드베이스의 다른 `openWindow` 호출들이 전부 `isPhone`으로 막아
    /// 두는 것과 같은 문제).
    ///
    /// 고치는 방법도 같은 원칙 — 아이폰은 새 창 대신 지금 화면의 `NavigationStack`
    /// 안으로 밀어 넣는다. `taggedDocuments`처럼 `NavigationLink`로 직접 표현할
    /// 수는 없다(이 호출은 `ChapterRelatedContentPanel`이 넘겨준 콜백
    /// (`onSelectVerseMention`) 안에서 일어나는 값 기반 트리거라 탭 시점에 어떤
    /// 문서/검색어인지 미리 알 수 없다) — 그래서 `.sheet(item:)`
    /// (`memoBeingCreated`)과 같은 원리로 이 옵셔널 상태 + 아래
    /// `.navigationDestination(item:)`을 쓴다. macOS/iPad는 기존 그대로
    /// `openWindow`로 진짜 새 창을 연다(다중 씬 지원 플랫폼이라 크래시 리포트가
    /// 없었다).
    @State private var documentSearchRequest: DocumentSearchRequest?
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
    /// [2026-08-28 신설] 사용자 요청 — "성경조회 기능의 책갈피 기능 추가." 책갈피
    /// 이동 팝오버(작은 레이어 팝업창, `번역본 선택`의 `TranslationPickerPopover`와
    /// 같은 `.popover` 패턴) 표시 여부.
    @State private var isBookmarkListPresented = false
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
    /// [2026-09-02 신설] 사용자 요청 — "메모하기 버튼 옆 '개인 묵상' 버튼을
    /// 클릭할 때 동작 = 메모하기 내 '개인 묵상' 버튼 클릭할 때와 동일하게."
    /// `openPersonalNoteDirectly()`가 이 값을 `true`로 세우고 확대보기를 열면,
    /// `VerseZoomView(autoPresentPersonalNoteEditor:)`로 그대로 전달돼 그
    /// 화면이 뜨자마자 안쪽 "개인 묵상" 버튼을 누른 것과 같은 동작이
    /// 일어난다. [2026-09-02 변경] 그 "같은 동작"의 내용물은 팝오버에서
    /// 목록 맨 위 입력칸(카드) 자동 표시로 바뀌었다(`VerseZoomView.
    /// beginComposingPersonalNote()` 참고) — 이 값 자체의 역할은 그대로다.
    /// 확대보기가 어떤 경로로 열렸든 다음 번엔 평범하게 열리도록, 시트가
    /// 닫힐 때(`onDismiss`) 항상 `false`로 되돌린다.
    @State private var shouldAutoPresentPersonalNoteEditor = false
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
    /// [2026-08-28 신설] 사용자 요청 — "[메모하기]-[원문정보] 각 레이어창 마다
    /// 쉽게 오갈 수 있도록 화살표라든지 기능을 추가할 것." 두 시트는 같은
    /// 화면에서 동시에 열 수 없으므로(`pendingPhraseMemo`와 같은 이유), "메모
    /// 하기 → 원문 정보"로 전환할 때 이 값을 true로 세우고 메모하기 시트를
    /// 닫은 뒤, 그 `onDismiss`에서 이 값을 보고 원문 정보 시트를 연다.
    @State private var pendingSwitchToOriginalTextInfo = false
    /// 반대 방향("원문 정보 → 메모하기") 전환용 — 원문 정보 시트가 완전히
    /// 닫힌 뒤 이어서 메모하기(구절 확대보기) 시트를 연다.
    @State private var pendingSwitchToVerseZoom = false
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
    /// 하단 액션바의 [말씀 복사] 버튼이 이 프록시를 통해 지금 열려 있는 편집기
    /// 리치 텍스트뷰 커서 위치에 직접 삽입한다.
    ///
    /// [2026-08-27 변경] 사용자 요청 — "팝업창으로 구현하기를 원함(macOS
    /// 한정, iOS는 기존기능 그대로)." macOS는 "말씀 요약" 편집기가 더 이상
    /// 이 창의 인스펙터가 아니라 별도 떠 있는 패널(`WordSummaryPanelController`,
    /// 앱 전체에서 하나뿐인 싱글턴)에서 열린다 — 성경 조회 창을 여러 개
    /// 띄워도(mac "새 창") 그 패널과 이 창의 [말씀 복사] 버튼이 항상 같은
    /// `RichTextEditingProxy`를 봐야 커서 삽입이 되므로, 창마다 따로 두는
    /// `@State` 대신 그 싱글턴이 들고 있는 프록시를 그대로 가리킨다. 이름과
    /// 타입이 그대로라 [말씀 복사] 등 기존 호출부(`wordSummaryProxy.
    /// insertTextAtCursor(_:)`)는 손대지 않아도 그대로 컴파일된다. iOS는
    /// "기존기능 그대로" 요청대로 원래의 창별 `@State`를 그대로 둔다.
#if os(macOS)
    private var wordSummaryProxy: RichTextEditingProxy { WordSummaryPanelController.shared.proxy }
#else
    @State private var wordSummaryProxy = RichTextEditingProxy()
#endif
    /// [2026-08-12 추가, 2026-08-21 폐기] 사용자 요청 — "말씀 구절과 오른쪽
    /// 사이드바 에디터 영역의 비율을 50:50으로 하게 할것." 처음엔 인스펙터가
    /// 열리기 직전 본문 실측 폭을 `.background`의 `GeometryReader`로 얼려 그
    /// 절반을 썼다. ⚠️ [2026-08-21 사용자 보고] 아이패드 실기기에서 이 폭이
    /// "상황에 따라 왔다갔다함, 줄었다가 늘었다가 함, 절반보다 작아짐" — 얼린
    /// 값이 iPad에서는 안정적으로 유지되지 않는 것으로 보인다(정확한 원인은
    /// 미확인 — GeometryReader가 인스펙터 열림/닫힘 시점에 다시 그려지며
    /// `.onAppear`가 재실행되는 등의 가능성을 의심할 뿐 실기기 없이 확정할
    /// 근거는 없다). 사용자가 "고정 크기이길 바람"이라고 명확히 요청해, 화면
    /// 폭에서 유도하는 계산을 완전히 버리고 아래 `.inspectorColumnWidth`에서
    /// `Self.wordSummaryInspectorFixedWidth` 상수를 직접 쓰는 것으로 바꿨다 —
    /// 더 이상 폭을 실측할 필요가 없어져 그 전용이던 `lastMeasuredContentWidth`
    /// 상태 자체를 지웠다.
    ///
    /// [2026-08-21 신설] "세로보기에서 하단 메뉴 아이콘만 표시" 판정 — 위에서
    /// 쓰던 것과 같은 `GeometryReader` 배경을 재활용한다. `UIDevice.current.
    /// orientation`은 방향 알림 생성을 별도로 켜야 하고, Split View/Slide
    /// Over에서는 "기기 방향"과 "이 화면이 실제로 받는 폭"이 다를 수 있어(예:
    /// 가로로 눕힌 아이패드에서 세로로 좁게 Split View) 신뢰할 수 없다 — 이
    /// 화면이 실제로 좁고 길게 그려지는지가 중요하지, 기기 자체의 방향 센서
    /// 값은 중요하지 않다(하단 액션바 버튼이 잘리지 않게 하는 게 목적이므로).
    @State private var isNarrowBottomBarLayout: Bool = false
    /// [2026-08-21 신설] 위 주석 참고 — "말씀 요약" 인스펙터의 고정 폭. 처음엔
    /// 예전 계산값의 대략적인 중간값(최소 380/이상적 520이던 기존 폴백 범위)을
    /// 그대로 상수화해 420을 썼다.
    ///
    /// [2026-08-27 확대] 사용자 요청 — "말씀요약모드시 문제가 생기지 않도록
    /// 에디터 영역 비율을 넓게 조절할 것." 배경: macOS 네이티브 서식 팝업
    /// (`usesInspectorBar`)을 다시 쓰기로 하면서(`WordSummaryEditorView.
    /// showsToolbarOnMac` 되돌림 참고) 2026-08-12에 보고됐던 문제 — 팝업이
    /// 선택 지점 기준으로 뜨는데, 이 인스펙터 열이 좁으면 팝업을 오른쪽 열
    /// 안에 다 그릴 공간이 없어 왼쪽 성경 본문 위로 넘쳐 보이는 문제 — 가
    /// 재발할 수 있다. 열을 넉넉히 넓히면 어느 선택 지점에서든 팝업이 열
    /// 왼쪽 경계를 넘지 않고 그 안에서 뜰 여유가 커진다는 추론으로 420 →
    /// 640(+220, 약 1.5배)으로 늘렸다.
    ///
    /// ⚠️ [확인 필요] 이 도구(클라우드 세션)에는 실기기/Xcode가 없어 macOS
    /// 네이티브 서식 팝업의 실제 렌더링 폭을 직접 재거나, 640pt에서 정말
    /// 넘치지 않는지 확인할 수 없었다 — 문서화된 동작(팝업이 선택 지점 기준
    /// 화면 좌표로 뜨고, 공간이 부족하면 반대쪽으로 밀려난다)에 근거한
    /// 추론이다. 실기기에서 열어 텍스트를 열의 여러 위치(위/아래/왼쪽 끝
    /// 가까이)에서 선택해 보고, 그래도 팝업이 넘치면 이 상수를 더 키워
    /// 달라고 알려주시면 된다.
    private static let wordSummaryInspectorFixedWidth: CGFloat = 640

    /// [2026-08-26 신설] 사용자 요청 — "하단 복사버튼 클릭(탭)하면 '복사되었습니다.'
    /// toast 메세지. 후 선택해제." 절 복사(하단 액션바/컨텍스트 메뉴 모두)가
    /// 성공했을 때 잠깐 보였다 사라지는 배너 문구. nil이면 감춘다.
    @State private var toastMessage: String?
    /// 위 `toastMessage`를 일정 시간 뒤 지우는 예약 작업 — 연달아 복사하면
    /// 매번 새로 예약해야 하므로, 이전 예약을 취소하지 않으면 먼저 예약된
    /// 타이머가 방금 띄운 새 토스트를 조기에 지워 버릴 수 있다(`guardReleaseWorkItem`
    /// 상단 주석과 같은 원칙).
    @State private var toastDismissWorkItem: DispatchWorkItem?

    /// [2026-08-26 신설] 컨텍스트 메뉴 [선택]이 지금 열려는 대상(절 번호 +
    /// 번역본 이름 + 그 번역본만의 절 본문) — `.popover(item:)`이 이 값이
    /// nil이 아닐 때 `VerseTextSelectionPopover`를 띄운다.
    @State private var partialTextSelectionTarget: PartialTextSelectionTarget?

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// [2026-08-26 신설] `CircularNavButtonModifier` 상단 주석 참고 — "아이패드
    /// (세로/가로 모두) 또는 아이폰 가로보기"일 때만 true. `isNarrowBottomBarLayout`은
    /// 화면 폭<높이로만 판정해 아이폰 세로/아이패드 세로 모두 narrow가 되므로
    /// (`isNarrowBottomBarLayout` 상단 주석 참고), 기기 종류(`isPhone`)와 함께
    /// 봐야 "아이폰 세로보기만 제외"라는 요구사항을 정확히 표현할 수 있다 —
    /// 아이패드는 `!isPhone`이 항상 true라 방향과 무관하게 이 값도 항상 true,
    /// 아이폰은 가로보기(narrow가 아닐 때)에만 true가 된다. macOS는 이 프로퍼티를
    /// 아예 참조하지 않는(호출부가 `#if os(iOS)`로 감싼) 요청 범위라 여기 값
    /// 자체는 macOS에서 의미가 없다.
    private var isCompactChapterNavButtons: Bool {
        !isPhone || !isNarrowBottomBarLayout
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

    /// [2026-08-27 추가] 사용자 요청 — "iOS 아이패드 - 성경조회"의 사이드바/
    /// 인스펙터 동시 노출 방지 + 트레일링 그룹 "사이드바 열기" 아이콘
    /// (`IPadSidebarInspectorCoordination.swift` 상단 주석 참고). 위 `isMac`/
    /// `isPhone`을 조합하면 "아이패드만" 판정할 수 있어(둘 다 아니면 아이패드)
    /// 새 `#if os(iOS)` 분기를 또 만들 필요가 없다.
    private var isIPad: Bool { !isMac && !isPhone }

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
        // [2026-08-12 추가, 2026-08-21 목적 축소] 위 `isNarrowBottomBarLayout`
        // 상단 주석 참고 — 레이아웃에 영향을 주지 않는 `.background`에 넣어
        // 순수하게 세로/가로 판정용으로만 쓴다("말씀 요약" 50:50 폭 계산은
        // 더 이상 이 측정값에 의존하지 않는다 — 고정 상수로 바뀌었다).
        //
        // [2026-08-26 수정] 사용자 보고 — "오른쪽 인스펙터 창 열면 버벅거리면서
        // 열림." 조사 결과 `ChapterRelatedContentPanel`이 여는 데이터
        // (`viewModel.relatedBookOutlinePreview` 등)는 인스펙터를 열 때가 아니라
        // 장을 이동할 때 이미 `refreshRelatedContent()`로 미리 계산돼 있다
        // (`BibleReadingViewModel.selectBook`/`goToChapter`/`navigate(toHistory:)`
        // 참고) — 즉 인스펙터를 여는 시점 자체엔 새로 데이터를 읽어오는 무거운
        // 작업이 없다. 반면 macOS/아이패드에서 `.inspector`가 열리는 동안은
        // 애니메이션 매 프레임마다 이 화면(본문 열 전체를 그리는 무거운
        // `sideBySideColumns`/`phoneColumns`를 포함한 이 `VStack`)의 가용 폭이
        // 연속적으로 줄어든다 — 그런데 이 `GeometryReader`가 정확히 그 폭 변화를
        // 감시하고 있어(`.onChange(of: proxy.size)`), 인스펙터가 열리는 그 짧은
        // 시간 동안 매 프레임 `isNarrowBottomBarLayout`에 **항상 같은 값**(가로가
        // 세로보다 넓은 상태 유지 — 인스펙터가 열려도 이 화면이 세로보다 좁아질
        // 정도로 줄어들진 않음)을 반복해서 대입하고 있었다. 조건 없이 매번
        // 대입하면 값이 실제로 안 바뀌어도 SwiftUI가 이 `@State` 쓰기 자체를
        // "변경"으로 보고 무거운 본문(`sideBySideColumns`)까지 포함해 이 화면의
        // `body`를 다시 계산하게 만들 수 있다 — 인스펙터가 슬라이드해 들어오는
        // 매 프레임마다 그 재계산이 겹치면 정확히 "버벅거리면서 열림"으로
        // 보일 수 있다. 값이 실제로 바뀔 때만 대입하도록 막아 이 불필요한
        // 재계산을 없앤다 — 동작(세로/가로 판정 결과) 자체는 전혀 바뀌지 않고,
        // 값이 같을 때의 쓸모없는 쓰기만 없앤다.
        //
        // ⚠️ [확인 필요] 이 도구(클라우드 세션)에는 Xcode/Instruments가 없어
        // 실기기에서 이 수정이 실제로 버벅임을 없애는지 직접 프로파일링할 수
        // 없었다 — 코드 레벨 추론(위)에 근거한 수정이다. 적용 후에도 버벅임이
        // 남아 있다면, Xcode의 SwiftUI 인스트루먼트(또는 Time Profiler)로 인스펙터
        // 여는 순간 어느 뷰의 `body`가 반복 호출되는지 직접 확인해 알려주시면
        // 좋겠다 — 특히 `ChapterRelatedContentPanel` 자체(29KB, 아직 전체를
        // 검토하지 않았다)의 렌더링 비용일 가능성도 남아 있다.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        let isNarrow = proxy.size.width < proxy.size.height
                        if isNarrow != isNarrowBottomBarLayout {
                            isNarrowBottomBarLayout = isNarrow
                        }
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        let isNarrow = newSize.width < newSize.height
                        if isNarrow != isNarrowBottomBarLayout {
                            isNarrowBottomBarLayout = isNarrow
                        }
                    }
            }
        )
        // [2026-08-27 신설] 사용자 보고 — "상단 성경 검색영역에 포커스를 둔
        // 상태에서 구절을 탭하고 가로모드↔세로모드를 전환하면, 세로모드로
        // 돌아와도 하단 메뉴 텍스트(아이콘+글자)가 사라지지 않음. 포커스가
        // 없을 때는 방향 전환이 항상 정확함."
        //
        // 원인: 위 `GeometryReader`가 측정하는 것은 이 화면(VStack) 자체의
        // 렌더링 크기인데, iOS는 포커스된 텍스트 필드가 있으면 기본적으로
        // 소프트웨어 키보드가 뜬 만큼 화면의 세이프에어리어를 줄여(그 결과
        // 이 VStack에 실제로 배정되는 높이도 함께 줄어) 콘텐츠가 키보드를
        // 피하게 만든다. 세로 키보드(더 큼)와 가로 키보드(더 작음)의 높이
        // 차이 때문에, 세로모드로 돌아왔을 때 "화면 높이 - 키보드 높이 - 상단
        // 성경검색줄 - 하단 액션바" 값이 화면 폭보다 오히려 작아질 수 있다 —
        // `isNarrow`(=폭<높이) 판정이 실제 기기 방향과 반대로(가짜 "가로") 나와
        // 버튼 라벨이 계속 보이는 채로 멈춘 것처럼 보인다(사실은 매번 정확히
        // 그 순간의 — 키보드로 오염된 — 크기를 기준으로 다시 계산되고 있었을
        // 뿐이다). 포커스가 없을 때(키보드가 없을 때)는 이 오염이 없어 항상
        // 정확했다는 사용자 관찰과 정확히 들어맞는다.
        //
        // 해결: 이 화면은 세로/가로 "판정"에만 이 크기를 쓰고, 검색 필드는
        // 화면 맨 위(`.safeAreaInset(edge: .top)`)에 있어 키보드(화면 아래)와
        // 겹칠 일이 없으므로, 이 VStack이 키보드 세이프에어리어를 아예 무시하게
        // (`.ignoresSafeArea(.keyboard, edges: .bottom)`) 만들면 방향 판정이
        // 키보드 유무와 완전히 무관해진다 — 키보드가 떠 있는 동안은 화면 맨
        // 아래(마지막 구절/하단 액션바)가 키보드에 가려질 수 있지만, 이는
        // "검색 중엔 키보드가 화면 일부를 덮는다"는 흔한 트레이드오프이고,
        // 위 `BookChapterPicker`에 새로 추가한 "완료" 버튼으로 언제든 키보드를
        // 내릴 수 있다.
        //
        // ⚠️ [확인 필요] 이 도구(클라우드 세션)에는 실기기/시뮬레이터가 없어
        // 회전+키보드 조합을 직접 재현해 검증하지 못했다 — 위는 iOS의 문서화된
        // 키보드 세이프에어리어 동작에 근거한 추론이다. 적용 후에도 증상이
        // 남아 있다면 알려주시면 좋겠다.
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
        // [2026-08-26 신설] 사용자 요청 — 복사 시 "복사되었습니다." toast.
        // 하단 액션바(`verseSelectionActionBar`)와 컨텍스트 메뉴(단일 번역본
        // 복사) 양쪽 모두 이 오버레이 하나를 공유한다 — 화면 어디서 복사하든
        // 배너가 한 곳(화면 하단 중앙)에만 뜨게 하기 위함.
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        // [2026-08-26 신설] 컨텍스트 메뉴 [선택]이 여는 팝오버 — `.popover`는
        // 아이폰(컴팩트 폭)에서 자동으로 시트로, 아이패드/macOS에서는 팝오버로
        // 적응해서 뜬다(`VerseTextSelectionPopover` 상단 주석 참고).
        .popover(item: $partialTextSelectionTarget) { target in
            VerseTextSelectionPopover(
                verseNumber: target.verseNumber,
                translationDisplayName: target.translationDisplayName,
                text: target.text,
                hanjaWords: target.hanjaWords,
                onCopy: copyRawText
            )
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
        // [2026-08-28 신설, 실기기 크래시 fix] 위 `documentSearchRequest` 상단
        // 주석 참고 — 아이폰 전용 경로. `DocumentSearchRequest`가 이미
        // `Hashable`이라(`DocumentSearchRequest.swift` 참고) `.navigationDestination
        // (for:)`도 쓸 수 있었지만, 값 기반(item:)을 쓴 이유는 `BibleVerseDestination`
        // 때 겪은 "같은 스택에 같은 타입의 `.navigationDestination`이 두 번
        // 등록되면 스택 루트에 더 가까운 쪽만 쓰인다" 문제(`SearchView.swift`
        // 상단 주석 참고)를 원천적으로 피하기 위해서다 — `item:` 쪽은 이
        // 화면 하나에만 있는 전용 상태를 직접 바인딩하므로 다른 화면의 동일
        // 타입 등록과 충돌할 여지가 없다. `DocumentSearchWindowContent`는
        // macOS/iPad의 "document-search" `WindowGroup`이 쓰는 것과 완전히
        // 같은 뷰(문서 조회 + `@Query` 기반 삭제 안전성)를 그대로 재사용한다.
        .navigationDestination(item: $documentSearchRequest) { request in
            DocumentSearchWindowContent(request: request)
        }
        #if os(macOS)
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
        //
        // [2026-08-12 변경, 2026-08-27 원복] macOS는 한때 "말씀 요약" 편집기가
        // 이 인스펙터 자리를 공유해 썼다(사용자 확인 — "기존 [관련 내용]
        // 인스펙터 자리를 재사용하되 필기가 용이하도록 넓게") — 그 뒤 같은 창
        // 안의 `.overlay` 카드로도 시도해 봤지만(2026-08-27 1차), 네이티브 서식
        // 팝업이 여전히 같은 창 좌표계 안에서 넘치는 문제가 그대로 남아 사용자가
        // 거부했다("내가 원하는 방향이 아님").
        //
        // [2026-08-27 변경] 사용자 요청 — "팝업창으로 구현하기를 원함(macOS
        // 한정 — 이 논의는 전부 macOS에 대한 것이고 iOS는 기존기능 그대로)."
        // macOS는 이제 이 인스펙터를 다시 "관련 내용"(`ChapterRelatedContentPanel`)
        // 전용으로 되돌린다 — "말씀 요약"은 이 인스펙터가 아니라 진짜 별도
        // 창(뜬 도구창 스타일 `NSPanel`, `WordSummaryPanelController.swift`
        // 참고)으로 뜬다. `openWordSummaryEditor`/`presentWordSummaryEditor`/
        // `closeWordSummaryEditor`/`wordSummaryProxy`는 전부 그대로 재사용한다.
        .inspector(isPresented: $isRelatedContentPresented) {
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
                // `presentWordSummaryEditor`를 그대로 타고 위 별도 패널
                // (`WordSummaryPanelController`)이 뜬다.
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
            .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
#else
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
                    // [2026-08-21 수정] "확대보기"/"원문 정보" 진입점이 예전엔
                    // 여기(WordSummaryEditorView 안)에 있었다 — 이제 아래
                    // `verseSelectionActionBar`의 "말씀 복사" 옆으로 옮겨서
                    // 그 두 콜백은 더 이상 넘기지 않는다.
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
            // [2026-08-12 변경, 2026-08-21 고정폭으로 교체] 사용자 요청 — "말씀
            // 구절과 오른쪽 사이드바 에디터 영역의 비율을 50:50으로." → [2026-08-21
            // 재요청] 아이패드에서 화면 폭 기반 계산이 불안정하다는 보고로 순수
            // 고정 pt 상수(`Self.wordSummaryInspectorFixedWidth`)로 바꿨다 — 위
            // 그 상수 상단 주석 참고. min/ideal/max에 모두 같은 값을 넣어 고정폭
            // 처럼 동작하게 하는 원칙은 그대로 유지한다(`.inspectorColumnWidth`가
            // 세 값 사이에서 자유롭게 고르게 두면 크기가 흔들릴 수 있어서).
            // 관련 내용 패널은 기존 폭 그대로 유지.
            .inspectorColumnWidth(
                min: wordSummaryBeingEdited != nil ? Self.wordSummaryInspectorFixedWidth : 260,
                ideal: wordSummaryBeingEdited != nil ? Self.wordSummaryInspectorFixedWidth : 300,
                max: wordSummaryBeingEdited != nil ? Self.wordSummaryInspectorFixedWidth : 400
            )
        }
        // [2026-08-12 추가] 안전망 — 말씀 요약 편집기가 열린 채로 이 화면 자체가
        // 사라지면(예: 사이드바에서 다른 섹션으로 이동) 위 `.inspector`의
        // `set` 클로저가 아예 호출되지 않을 수 있다 — 그러면 번역본 열이 좁혀진
        // 채, 바깥쪽 사이드바가 닫힌 채로 영영 남는다. 화면이 사라질 때 한 번 더
        // 뒷정리를 강제한다.
#endif
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
        // [2026-08-25 추가] 사이드바 "최근" 이력(형광펜/메모/관주) 항목을, 이미 이
        // 화면(성경 조회)을 보고 있는 채로 다시 탭한 경우 — 이 화면 자체는 다시
        // 만들어지지 않으므로(`viewModel`이 그대로 유지된다) 위 `BibleReadingView`
        // 바깥쪽 `.onAppear`가 실행되지 않는다. `SidebarSearchRequest`를 소비하는
        // `SearchView`가 `.onAppear`+`.onChange` 두 경로를 모두 처리하는 것과
        // 같은 이유로, 여기서도 `.onChange`를 짝으로 둔다.
        .onChange(of: BibleVerseNavigationRequest.shared.pendingTarget) { _, newValue in
            guard let newValue, let book = BooksProvider.shared.book(id: newValue.bookId) else { return }
            viewModel.selectBook(book, chapter: newValue.chapter)
            viewModel.highlightVerseTemporarily(newValue.verse)
            BibleVerseNavigationRequest.shared.clear()
        }
        // [2026-08-27 추가] 사용자 요청 — 아이패드에서 사이드바/인스펙터 동시
        // 노출 방지(`IPadSidebarInspectorCoordination.swift` 상단 주석 참고).
        // 관련 콘텐츠 인스펙터가 (어떤 경로로든) 열리고/닫히는 것을 그대로
        // 싱글턴에 보고한다 — 말씀 요약 편집기가 이 자리를 대신 쓰는 경우는
        // 포함하지 않는다(위 참고, 그건 기존 `SidebarVisibilityRequest` 계약을
        // 그대로 쓴다).
        .onChange(of: isRelatedContentPresented) { _, newValue in
            guard isIPad else { return }
            IPadSidebarInspectorCoordination.shared.reportInspectorVisibility(newValue)
        }
        // 사이드바가 (어떤 경로로든) 열리는 순간을 관찰해, 이 화면 스스로
        // (자기 로컬 상태만) 관련 콘텐츠 인스펙터를 닫는다 — 사이드바 쪽에
        // 인스펙터를 대신 닫아 달라는 명령을 보낼 필요가 없다.
        .onChange(of: IPadSidebarInspectorCoordination.shared.isSidebarVisible) { _, newValue in
            guard isIPad, newValue, isRelatedContentPresented else { return }
            isRelatedContentPresented = false
        }
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

    /// [2026-08-08 추가, 2026-08-19 보완] 관주 팝오버에서 대상 구절을 탭했을 때
    /// — 그 책/장으로 이동한다. [2026-08-19] 정확한 절로 스크롤+강조하는 것은
    /// 당시엔 범위 밖이었다("`TranslationColumnView.centerVerseID`가 private이라
    /// 밖에서 직접 지정할 방법이 없고") — 검색 결과 탭 기능("검색 결과중 -
    /// 성경구절을 클릭하면 해당하는 절까지 스크롤 이동해서 잠시 하이라이트
    /// 표시해줄것")을 구현하며 그 경로(`BibleReadingViewModel.
    /// highlightVerseTemporarily`)가 이미 생겼으므로, 여기서도 그대로 재사용한다.
    private func jumpToCrossReferenceTarget(_ target: BibleVerseRef) {
        guard let book = BooksProvider.shared.book(id: target.bookId) else { return }
        viewModel.selectBook(book, chapter: target.chapter)
        viewModel.highlightVerseTemporarily(target.verse)
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
                let request = DocumentSearchRequest(documentID: document.persistentModelID, searchText: mention.searchText)
                // [2026-08-28 변경, 실기기 크래시 fix] 위 `documentSearchRequest`
                // 상단 주석 참고 — 아이폰은 새 창 대신 지금 화면 스택에 밀어
                // 넣는다(`.navigationDestination(item: $documentSearchRequest)`).
                if isPhone {
                    documentSearchRequest = request
                } else {
                    openWindow(id: "document-search", value: request)
                }
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

        // [2026-08-12 추가, 2026-08-21 삭제] 예전엔 여기서 인스펙터가 열리기
        // 직전 측정된 본문 폭의 절반을 얼려 뒀다 — 이제(iOS/iPadOS는)
        // `.inspectorColumnWidth`가 `Self.wordSummaryInspectorFixedWidth`
        // 고정 상수를 직접 쓰므로(위 그 상수 상단 주석 참고) 여기서 따로
        // 계산해 둘 값이 없다.
        wordSummaryBeingEdited = summary

        // [2026-08-27 신설] 사용자 요청 — "팝업창으로 구현하기를 원함(macOS
        // 한정)." macOS는 위 `wordSummaryBeingEdited` 신호를 인스펙터가 아니라
        // 이 별도 떠 있는 패널이 소비한다(`WordSummaryPanelController.swift`
        // 상단 주석 참고) — 여기서 그 패널을 띄운다. `modelContext`를 명시적으로
        // 넘기는 이유/`ownerToken`의 역할은 그 파일의 `present(...)` 문서
        // 참고. `onClose`로 이 함수의 짝인 `closeWordSummaryEditor()`를 그대로
        // 넘겨, 패널이 어떻게 닫히든(사용자가 패널 자체 닫기 버튼을 누르든,
        // 아래 툴바 "닫기" 버튼을 누르든) 번역본/사이드바 복원이 항상 똑같이
        // 실행되게 한다.
        #if os(macOS)
        WordSummaryPanelController.shared.present(
            summary: summary,
            modelContext: modelContext,
            ownerToken: ObjectIdentifier(viewModel)
        ) {
            closeWordSummaryEditor()
        }
        #endif
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
        SidebarVisibilityRequest.shared.requestRestore()
        // [2026-08-27 신설] macOS 별도 패널 닫기 — `WordSummaryPanelController.
        // hide()`가 `NSPanel.close()`를 부르면 그 델리게이트(`windowWillClose`)가
        // 다시 이 함수를 재호출하지만(패널 쪽에 등록해 둔 `onClose`가 바로 이
        // 함수라서), 바로 위에서 이미 `wordSummaryBeingEdited = nil`을 실행한
        // 뒤라 맨 위 `guard`에서 조용히 반환된다 — 재진입은 안전하다.
        #if os(macOS)
        WordSummaryPanelController.shared.hide()
        #endif
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
                    // [2026-08-19 추가] 사용자 요청 — "검색 결과중 - 성경구절을
                    // 클릭하면 해당하는 절까지 스크롤 이동해서 잠시 하이라이트
                    // 표시해줄것." 모든 컬럼(번역본)에 같은 값을 넘긴다 — 검색
                    // 결과는 특정 번역본을 지정하지 않으므로, 지금 보이는 컬럼
                    // 전부에서 그 절이 강조된다.
                    highlightedVerse: viewModel.highlightedVerse,
                    onCreateMemo: createMemo,
                    onCopySingleTranslation: copySingleTranslation,
                    onSelectPartialText: { verse, translationDisplayName in
                        presentPartialTextSelection(
                            verse, translationDisplayName,
                            hanjaWords: viewModel.hanjaWords(translationCode: column.registry.code, verse: verse.verse)
                        )
                    },
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
                    onSelectVerseMention: handleVerseMentionSelected,
                    // [2026-09-02 신설] 사용자 보고 — "왼쪽 기본 성경 칸 스크롤
                    // 버벅임 — 한자/난외주 인라인 캐싱." 위 다른 provider들과
                    // 같은 패턴으로 `column.registry.code`를 붙잡아 넘긴다 —
                    // 실제 캐시는 `BibleReadingViewModel.
                    // cachedInlineAnnotatedContent`(세션 전체 유지 정책, 그
                    // 함수 상단 주석 참고)가 갖고 있다.
                    inlineAnnotatedContentProvider: { verse, highlights, phraseNotes, hanjaWords, marginalNotes, font, textColor, hanjaFont in
                        viewModel.cachedInlineAnnotatedContent(
                            bookId: verse.bookId, chapter: verse.chapter, translationCode: column.registry.code, verse: verse.verse,
                            text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
                            hanjaWords: hanjaWords, marginalNotes: marginalNotes, font: font, textColor: textColor, hanjaFont: hanjaFont
                        )
                    }
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
                    // [2026-08-19 추가] 사용자 요청 — "검색 결과중 - 성경구절을
                    // 클릭하면 해당하는 절까지 스크롤 이동해서 잠시 하이라이트
                    // 표시해줄것." 모든 컬럼(번역본)에 같은 값을 넘긴다 — 검색
                    // 결과는 특정 번역본을 지정하지 않으므로, 지금 보이는 컬럼
                    // 전부에서 그 절이 강조된다.
                    highlightedVerse: viewModel.highlightedVerse,
                    onCreateMemo: createMemo,
                    onCopySingleTranslation: copySingleTranslation,
                    onSelectPartialText: { verse, translationDisplayName in
                        presentPartialTextSelection(
                            verse, translationDisplayName,
                            hanjaWords: viewModel.hanjaWords(translationCode: column.registry.code, verse: verse.verse)
                        )
                    },
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
                    onSelectVerseMention: handleVerseMentionSelected,
                    // [2026-09-02 신설] 사용자 보고 — "왼쪽 기본 성경 칸 스크롤
                    // 버벅임 — 한자/난외주 인라인 캐싱." 위 다른 provider들과
                    // 같은 패턴으로 `column.registry.code`를 붙잡아 넘긴다 —
                    // 실제 캐시는 `BibleReadingViewModel.
                    // cachedInlineAnnotatedContent`(세션 전체 유지 정책, 그
                    // 함수 상단 주석 참고)가 갖고 있다.
                    inlineAnnotatedContentProvider: { verse, highlights, phraseNotes, hanjaWords, marginalNotes, font, textColor, hanjaFont in
                        viewModel.cachedInlineAnnotatedContent(
                            bookId: verse.bookId, chapter: verse.chapter, translationCode: column.registry.code, verse: verse.verse,
                            text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
                            hanjaWords: hanjaWords, marginalNotes: marginalNotes, font: font, textColor: textColor, hanjaFont: hanjaFont
                        )
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// [2026-08-26 신설] 사용자 요청 — "확대보기 하거나 ... 히스토리 이력에
    /// 남김." 확대보기 버튼이 아래 두 분기(말씀 요약 편집 중/아닐 때)에 똑같이
    /// 있어 중복을 피하려고 공통 함수로 뺐다 — 시트를 여는 것과 이력 기록을
    /// 항상 같이 하게 해서, 나중에 버튼이 더 늘어나도 기록이 누락되지 않게 한다.
    private func openVerseZoom() {
        if let verseNumber = viewModel.selectedVerses.first {
            viewModel.recordVerseHistory(verse: verseNumber)
        }
        isVerseZoomPresented = true
    }

    /// [2026-09-02 변경] 사용자 요청 — "메모하기 버튼 옆 '개인 묵상' 버튼을
    /// 클릭할 때 동작 = 메모하기 내 '개인 묵상' 버튼 클릭할 때와 동일하게."
    /// 예전엔 확대보기(`VerseZoomView`)를 아예 열지 않고 바로 편집기 시트
    /// (`MemoDetailView`)로 넘어갔다 — 그러면 말씀구절/한자/관주/다른 개인
    /// 묵상 목록이 안 보이는 채로 등록하게 된다는 문제가 있었다(위 "메모하기
    /// 내 개인 묵상" 요청과 같은 문제). 이제 `openVerseZoom()`과 똑같이
    /// 확대보기를 열되, `shouldAutoPresentPersonalNoteEditor`를 함께 세워
    /// 그 화면이 뜨자마자 안쪽 "개인 묵상" 버튼을 누른 것과 동일하게 동작하게
    /// 한다(`VerseZoomView.autoPresentPersonalNoteEditor` 상단 주석 참고).
    ///
    /// [2026-09-02 버그 수정 시도 1, 실패] 사용자 보고 — "성경조회 - 메모하기
    /// 옆 개인 묵상 버튼을 처음 눌렀을 때(다른 기능에서 성경 조회 기능을
    /// 클릭한 후) 개인 묵상 UI가 나타나지 않음. 팝업을 닫고 다시 눌렀을 때는
    /// 보여짐." 처음엔 "시트를 여는 시점(`isVerseZoomPresented = true`)이
    /// 데이터 상태 변경과 같은 트랜잭션에 있어서"라고 보고 그 시점만
    /// `DispatchQueue.main.async`로 미뤄 봤으나 — 사용자 재확인 결과 "해결
    /// 안됨, 증상 동일함." 실제 원인은 이 함수 쪽 타이밍이 아니라
    /// `VerseZoomView`가 `autoPresentPersonalNoteEditor`를 `let`으로(생성자
    /// 인자로 한 번만) 받던 것 자체였다 — `PhraseNoteEditorPopover.swift`의
    /// 2026-08-11 15차 수정이 이미 같은 결론(런루프 틱을 미루는 것만으로는
    /// 이 어긋남이 없어지지 않는다)에 도달했던 것과 정확히 같다. 그래서
    /// `VerseZoomView.autoPresentPersonalNoteEditor`를 `@Binding`으로
    /// 바꿔(아래 호출부의 `$shouldAutoPresentPersonalNoteEditor` 참고) 그
    /// 화면이 실제로 화면에 붙은 뒤 `onAppear`가 최신 값을 다시 읽게 했다 —
    /// 그래서 이 함수 자체는 `openVerseZoom()`과 똑같이 다시 단순한 동기
    /// 코드로 되돌린다.
    private func openPersonalNoteDirectly() {
        if let verseNumber = viewModel.selectedVerses.first {
            viewModel.recordVerseHistory(verse: verseNumber)
        }
        shouldAutoPresentPersonalNoteEditor = true
        isVerseZoomPresented = true
    }

    // MARK: - 토스트 배너 (2026-08-26 신설)

    /// `message`를 잠깐 띄웠다 1.6초 뒤 스스로 사라지게 한다. 연달아 부르면
    /// 이전 예약(`toastDismissWorkItem`)을 취소하고 새로 예약해, 먼저 뜬
    /// 토스트의 타이머가 방금 새로 띄운 문구를 조기에 지우는 일이 없게 한다.
    private func showToast(_ message: String) {
        toastDismissWorkItem?.cancel()
        withAnimation {
            toastMessage = message
        }
        let workItem = DispatchWorkItem {
            withAnimation {
                toastMessage = nil
            }
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toastMessage {
            Text(toastMessage)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.8), in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: - 절 선택 → 클립보드 복사 (2026-08-08 추가)

    private var verseSelectionActionBar: some View {
        // [2026-08-26 수정] 사용자 요청 — 아이패드 세로모드에서 "간격을 좀더
        // 넓힐 수 있도록." 당시엔 아이폰 쪽 요청이 없어 `!isPhone`으로 아이패드
        // 세로모드에만 적용했었다.
        //
        // [2026-08-27 확장] 사용자 요청 — "iOS 아이폰 성경 조회 세로보기 —
        // 구절 탭 시 나타나는 하단 메뉴 UI 수정: ... 버튼간 간격을 넓히고."
        // 이번엔 아이폰도 대상이라 `!isPhone` 제외 조건을 없앴다 — narrow일 때
        // (아이폰 세로/아이패드 세로 모두) 16pt를 쓴다. 새 숫자를 만들지 않고
        // 바로 위 2026-08-26에 이미 검증된 16pt를 그대로 재사용했다.
        HStack(spacing: isNarrowBottomBarLayout ? 16 : nil) {
            Text("\(viewModel.selectedVerses.count)개 절 선택됨")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            // [2026-08-12 변경, 2026-08-21 일부 복원] 사용자 요청 — "말씀 요약
            // 상태일 때 왼쪽 성경 영역 하단 버튼 변화 -> [선택 해제][복사][말씀
            // 요약]버튼 제거, [말씀 복사] 추가." 편집기가 열려 있는 동안은 이 줄
            // 전체가 "지금 편집 중인 요약에 구절을 보태는" 용도로 바뀐다 — 말씀
            // 요약/선택 해제/복사는 편집 중엔 의미가 없거나 혼란을 준다고 판단해
            // 계속 감춘다. [2026-08-21 재요청] 확대보기/원문 정보만은 사용자가
            // "macOS처럼 하단 말씀복사 옆에 자리할 수 있도록" 다시 요청해 복원한다
            // — 한때 `WordSummaryEditorView` 안(상단 좌표 라인)으로 옮겼었지만
            // (2026-08-20), 실제로 원했던 자리는 여기였다. 확대보기/원문 정보는
            // 태생적으로 "절 하나"를 다루므로(`VerseZoomView`/`OriginalTextInfoView`
            // 모두 단일 verseNumber를 받는다) 아래 비-편집 분기와 똑같이 정확히
            // 1개가 선택돼 있을 때만 보인다.
            if wordSummaryBeingEdited != nil {
                if viewModel.selectedVerses.count == 1 {
                    Button {
                        openVerseZoom()
                    } label: {
                        Label("메모하기", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false))
                    #endif
                    // [2026-09-02 신설, 같은 날 재수정] 사용자 요청 —
                    // "메모하기 버튼 옆 '개인 묵상' 버튼 클릭 시 동작 = 메모하기
                    // 내 '개인 묵상' 버튼 클릭할 때와 동일하게." 위
                    // `openPersonalNoteDirectly()` 상단 주석 참고 — 확대보기를
                    // 열고 그 안의 개인 묵상 입력칸(카드)을 자동으로 연다.
                    Button {
                        openPersonalNoteDirectly()
                    } label: {
                        Label("개인 묵상", systemImage: "note.text")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false))
                    #endif
                    Button {
                        isOriginalTextInfoPresented = true
                    } label: {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false))
                    #endif
                }
                Button {
                    copySelectedVersesIntoWordSummary()
                } label: {
                    Label("말씀 복사", systemImage: "text.insert")
                }
                #if os(iOS)
                .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: true))
                #else
                .buttonStyle(.borderedProminent)
                #endif
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
                        openVerseZoom()
                    } label: {
                        Label("메모하기", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false))
                    #endif
                    // [2026-09-02 신설, 같은 날 재수정] 사용자 요청 —
                    // "메모하기 버튼 옆 '개인 묵상' 버튼 클릭 시 동작 = 메모하기
                    // 내 '개인 묵상' 버튼 클릭할 때와 동일하게." 위
                    // `openPersonalNoteDirectly()` 상단 주석 참고 — 확대보기를
                    // 열고 그 안의 개인 묵상 입력칸(카드)을 자동으로 연다.
                    Button {
                        openPersonalNoteDirectly()
                    } label: {
                        Label("개인 묵상", systemImage: "note.text")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false))
                    #endif
                    // [2026-08-09 추가] 사용자 요청 — "확대보기 버튼 옆에 '원문 정보'라는
                    // 버튼이 있어 히브리어 그리스어 원문에 대한 정보를 넣고자 함."
                    Button {
                        isOriginalTextInfoPresented = true
                    } label: {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false))
                    #endif
                }
                // [2026-08-12 변경] 사용자 요청 — "성경구절을 2개이상 선택시에도
                // 하단의 버튼이 유지될것. 현재는 한구절일때만 뜨게 됨." 말씀
                // 요약은 확대보기/원문 정보와 달리 여러 절을 한 번에 요약해도
                // 자연스러워, 정확히 1개가 아니라 "1개 이상"이면 노출한다.
                if !viewModel.selectedVerses.isEmpty {
                    Button {
                        openWordSummaryEditor()
                    } label: {
                        Label("말씀 요약", systemImage: "text.quote")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false))
                    #endif
                }
                Button {
                    viewModel.clearVerseSelection()
                } label: {
                    // [2026-08-21 수정] 사용자 요청 — "세로보기에서 탭하면 하단
                    // 메뉴는 한글 메뉴명은 빼고 아이콘만 나오도록." 아래
                    // `.labelStyle(.iconOnly)`가 이 줄의 버튼 전부에 적용되려면
                    // 이 버튼도 다른 버튼들처럼 `Label`(아이콘+텍스트)이어야 한다 —
                    // 예전엔 순수 `Button("선택 해제")`(텍스트만, 아이콘 없음)라
                    // 아이콘 전용으로 못 줄어들었다.
                    Label("선택 해제", systemImage: "xmark.circle")
                }
                #if os(iOS)
                .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false))
                #endif
                Button {
                    copySelectedVerses()
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
                #if os(iOS)
                .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: true))
                #else
                .buttonStyle(.borderedProminent)
                #endif
            }
        }
        // [2026-08-21 추가] 사용자 요청 — "세로보기에서 탭하면 하단 메뉴는
        // 한글 메뉴명은 빼고 아이콘만 나오도록." 위 `isNarrowBottomBarLayout`
        // 상단 주석 참고 — macOS는 창 폭이 넉넉해 해당 요청 대상이 아니므로
        // iOS(아이폰/아이패드)에서만 적용한다.
        #if os(iOS)
        .modifier(BottomBarLabelStyleModifier(isNarrow: isNarrowBottomBarLayout))
        #endif
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
            // [2026-08-28 신설] "메모하기 → 원문 정보" 전환 — 위
            // `pendingSwitchToOriginalTextInfo` 상단 주석 참고.
            if pendingSwitchToOriginalTextInfo {
                pendingSwitchToOriginalTextInfo = false
                isOriginalTextInfoPresented = true
            }
            // [2026-09-02 신설] 위 `shouldAutoPresentPersonalNoteEditor` 상단
            // 주석 참고 — 이 확대보기 세션이 끝났으니, 다음 번엔(어느 버튼으로
            // 열리든) 항상 기본값(자동 표시 없음)에서 다시 시작한다.
            shouldAutoPresentPersonalNoteEditor = false
        }) {
            if let verseNumber = viewModel.selectedVerses.first {
                VerseZoomView(
                    verseNumber: verseNumber, columns: viewModel.columns, viewModel: viewModel,
                    onOpenPhraseMemo: { memo in pendingPhraseMemo = memo },
                    onJumpToCrossReference: jumpToCrossReferenceTarget,
                    onSelectVerseMention: handleVerseMentionSelected,
                    onSwitchToOriginalTextInfo: {
                        pendingSwitchToOriginalTextInfo = true
                        isVerseZoomPresented = false
                    },
                    autoPresentPersonalNoteEditor: $shouldAutoPresentPersonalNoteEditor
                )
            }
        }
        .sheet(isPresented: $isOriginalTextInfoPresented, onDismiss: {
            // [2026-08-28 신설] "원문 정보 → 메모하기" 전환 — 위
            // `pendingSwitchToVerseZoom` 상단 주석 참고. `openVerseZoom()`을
            // 그대로 재사용해, 이 전환으로 열리는 경우에도 다른 진입 경로와
            // 똑같이 조회 이력에 남게 한다(`openVerseZoom()` 상단 주석 —
            // "시트를 여는 것과 이력 기록을 항상 같이 하게 해서, 나중에
            // 버튼이 더 늘어나도 기록이 누락되지 않게 한다").
            if pendingSwitchToVerseZoom {
                pendingSwitchToVerseZoom = false
                openVerseZoom()
            }
        }) {
            if let verseNumber = viewModel.selectedVerses.first {
                OriginalTextInfoView(
                    bookId: viewModel.selectedBook.bookId,
                    chapter: viewModel.selectedChapter,
                    verseNumber: verseNumber,
                    onSwitchToMemo: {
                        pendingSwitchToVerseZoom = true
                        isOriginalTextInfoPresented = false
                    }
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
        // [2026-08-26 추가] 사용자 요청 — "하단 복사버튼 클릭(탭)하면
        // '복사되었습니다.' toast 메세지. 후 선택해제." 복사가 실제로 클립보드에
        // 쓰인 뒤에만(위 guard 통과 후) 토스트를 띄우고 선택을 비운다 — 복사할
        // 내용이 없어 guard에서 일찍 반환되면 토스트도 선택 해제도 일어나지
        // 않는다(사용자에게 "복사됐다"는 잘못된 신호를 주지 않기 위함).
        showToast("복사되었습니다.")
        viewModel.clearVerseSelection()
    }

    /// [2026-08-26 신설] 사용자 요청 — iOS 길게 프레스/macOS 오른쪽버튼 메뉴의
    /// [복사]("해당 번역본만 복사 -> 클릭하면 toast 메세지"). 위
    /// `copySelectedVerses()`(하단 액션바 — 지금 선택된 모든 절 × 화면에 보이는
    /// 모든 번역본)와 달리, 이 경로는 컨텍스트 메뉴를 연 그 절 하나 + 그
    /// 컨텍스트 메뉴가 속한 번역본 컬럼 하나만 대상으로 한다 — 그래서 절 선택
    /// 상태(`viewModel.selectedVerses`)는 건드리지 않는다("복사" 버튼처럼 선택을
    /// 전제하거나 바꾸는 동작이 아니다).
    private func copySingleTranslation(_ verse: BibleVerse, _ translationDisplayName: String) {
        guard let text = BibleVerseCopyFormatter.format(
            book: viewModel.selectedBook,
            chapter: viewModel.selectedChapter,
            selectedVerses: [verse.verse],
            translations: [BibleVerseCopyFormatter.TranslationSnapshot(displayName: translationDisplayName, verses: [verse])]
        ) else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        showToast("복사되었습니다.")
    }

    /// [2026-08-26 신설] 컨텍스트 메뉴 [선택] — `VerseTextSelectionPopover`를
    /// 열 대상을 정한다. 실제 클립보드 접근/토스트는 팝오버의 "복사" 버튼이
    /// 눌렸을 때 `copyRawText(_:)`가 한다(아래).
    private func presentPartialTextSelection(
        _ verse: BibleVerse, _ translationDisplayName: String, hanjaWords: [HanjaWordAnnotation]
    ) {
        partialTextSelectionTarget = PartialTextSelectionTarget(
            verseNumber: verse.verse, translationDisplayName: translationDisplayName, text: verse.content,
            hanjaWords: hanjaWords
        )
    }

    /// [2026-08-26 신설] `VerseTextSelectionPopover`가 넘기는 "지금 드래그로
    /// 고른 부분 문자열"(또는 아무것도 안 골랐으면 절 전체)을 그대로 클립보드에
    /// 쓴다 — `copySingleTranslation`/`copySelectedVerses`와 달리
    /// `BibleVerseCopyFormatter`를 거치지 않는다: "일부 텍스트를 선택하여 복사"는
    /// 사용자가 화면에서 직접 드래그로 고른 글자 그대로를 복사하는 것이지,
    /// 장:절 참조나 번역본 이름표를 덧붙이는 기능이 아니다.
    private func copyRawText(_ text: String) {
        guard !text.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        showToast("복사되었습니다.")
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
            // [2026-08-27 순서 변경] 사용자 요청("아이패드 - 성경조회") —
            // "오른쪽 성경 본문 영역의 상단 오른쪽 끝 아이콘 배치 수정. 아이콘
            // 순서가 인스펙터 창, 히스토리 버튼으로 되어있는데 이를 히스토리
            // 버튼, 인스펙터 창 순으로 바꿀것." 아래 두 `ToolbarItem`
            // (조회 이력 → 관련 콘텐츠)의 선언 순서를 그대로 뒤집었다 — 이
            // 코드베이스에서 `trailingIconPlacement`(iOS `.topBarTrailing`) 여러
            // 개는 선언 순서가 화면에 보이는 좌우 순서와 일치한다(사용자가
            // "바뀌기 전 순서"로 보고한 것과 바뀌기 전 코드 선언 순서가 정확히
            // 일치하는 것으로 확인).
            //
            // [2026-08-27 추가] 사용자 요청 — "사이드바를 닫을 경우 아이콘
            // 순서는 사이드바, 히스토리, 인스펙터 창 순서로 할 것." 아이패드
            // 전용(`IPadSidebarInspectorCoordination.swift` 상단 주석 참고) —
            // 왼쪽 사이드바가 닫혀 있을 때만 이 트레일링 그룹의 맨 앞자리에
            // 사이드바를 다시 여는 아이콘을 추가한다. 말씀 요약 편집 중엔
            // (바로 아래 조회 이력 버튼과 같은 이유로) 노출하지 않는다 — 말씀
            // 요약 편집은 `SidebarVisibilityRequest`의 별도 자동 복원 계약으로
            // 이미 사이드바를 접어 두는데, 이 새 버튼(자동 복원 없음)이 그
            // 위에 겹치면 두 계약이 서로 다른 값으로 사이드바를 다투게 된다.
            if isIPad && wordSummaryBeingEdited == nil && !IPadSidebarInspectorCoordination.shared.isSidebarVisible {
                ToolbarItem(placement: trailingIconPlacement) {
                    Button {
                        IPadSidebarInspectorCoordination.shared.requestShowSidebar()
                    } label: {
                        Label("사이드바 열기", systemImage: "sidebar.leading")
                    }
                    .help("왼쪽 사이드바 보이기")
                }
            }
            // [2026-08-28 신설] 사용자 요청 — "성경조회 상단 히스토리 왼쪽
            // 옆에 책갈피 아이콘(해제, 설정), 책갈피 아이콘 왼쪽 옆에 책갈피
            // 이동 아이콘 추가." 코드 순서(=`trailingIconPlacement` 그룹 안에서
            // 먼저 추가하는 쪽이 왼쪽)로 배치를 맞춘다 — 그래서 "이동" 버튼을
            // "토글" 버튼보다 먼저, "토글" 버튼을 아래 "조회 이력" 버튼보다
            // 먼저 둔다. 두 버튼 모두 조회 이력/새 창/번역본 선택과 같은 이유로
            // 말씀 요약 편집 중엔 감춘다.
            if wordSummaryBeingEdited == nil {
                ToolbarItem(placement: trailingIconPlacement) {
                    Button {
                        isBookmarkListPresented = true
                    } label: {
                        Label("책갈피 이동", systemImage: "list.star")
                    }
                    .help("책갈피로 이동")
                    .popover(isPresented: $isBookmarkListPresented) {
                        BookmarkListPopover(viewModel: viewModel) {
                            isBookmarkListPresented = false
                        }
                    }
                }
                ToolbarItem(placement: trailingIconPlacement) {
                    Button {
                        viewModel.toggleBookmarkForCurrentPosition()
                    } label: {
                        if viewModel.isCurrentPositionBookmarked {
                            Label("책갈피 해제", systemImage: "bookmark.fill")
                        } else {
                            Label("책갈피 설정", systemImage: "bookmark")
                        }
                    }
                    .help(viewModel.isCurrentPositionBookmarked ? "이 위치 책갈피 해제" : "이 위치 책갈피로 설정")
                }
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
            // [2026-08-20 추가] 사용자 요청 — "이전 장 이동하는 화살표 옆에
            // 이전에 찾아봤던 장 바로가기 아이콘 추가(history.back)." 바로
            // 옆의 `chevron.left`(항상 -1장, `previousChapter`)와는 다른
            // 개념이라 아이콘도 다르게 뒀다 — 브라우저 뒤로가기와 같은
            // `arrow.uturn.backward`(원 모양 화살표)를 써서 "인접 장 이동"과
            // "임의 위치로 되짚어가기"가 시각적으로도 구분되게 했다.
            // `viewModel.canGoBackInHistory`가 false면 갈 곳이 없다는 뜻이라
            // 비활성화한다.
            Button {
                viewModel.goBackInHistory()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canGoBackInHistory)
            .help("이전에 보던 위치로 돌아가기")
            #if os(iOS)
            .modifier(CircularNavButtonModifier(isCircular: isCompactChapterNavButtons))
            #endif

            Button {
                viewModel.previousChapter()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.selectedChapter <= 1 && BooksProvider.shared.book(before: viewModel.selectedBook) == nil)
            .help("이전 장")
            #if os(iOS)
            .modifier(CircularNavButtonModifier(isCircular: isCompactChapterNavButtons))
            #endif

            BookChapterPicker(
                books: BooksProvider.shared.books,
                selectedBook: viewModel.selectedBook,
                selectedChapter: viewModel.selectedChapter,
                // [2026-08-21 추가] 사용자 요청 — "절까지 포함시키면... 스크롤한
                // 다음 하이라이트 잠시 표시할 것(검색 결과 클릭한 것과 동일한
                // 기능)". `jumpToCrossReferenceTarget`(바로 아래, 관주 팝오버
                // 탭 처리)이 이미 쓰는 것과 똑같은 두 단계(장 이동 → 절 임시
                // 하이라이트)를 그대로 재사용한다.
                onSelectVerse: { book, chapter, verse in
                    viewModel.selectBook(book, chapter: chapter)
                    viewModel.highlightVerseTemporarily(verse)
                }
            ) { book, chapter in
                viewModel.selectBook(book, chapter: chapter)
            }

            Button {
                viewModel.nextChapter()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(
                viewModel.selectedChapter >= viewModel.selectedBook.chapterCount
                    && BooksProvider.shared.book(after: viewModel.selectedBook) == nil
            )
            .help("다음 장")
            #if os(iOS)
            .modifier(CircularNavButtonModifier(isCircular: isCompactChapterNavButtons))
            #endif

            // [2026-08-20 추가] 사용자 요청 — "다음 장 이동하는 화살표 옆에
            // 앞에서 온 성경 장을 바로가는 아이콘 추가(history.forward())."
            // 위 뒤로가기 버튼과 대칭 — `arrow.uturn.forward`.
            Button {
                viewModel.goForwardInHistory()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.canGoForwardInHistory)
            .help("뒤로가기 이전 위치로 다시 가기")
            #if os(iOS)
            .modifier(CircularNavButtonModifier(isCircular: isCompactChapterNavButtons))
            #endif
        }
        // [2026-08-08 추가] 툴바 principal 자리(폭 제한)에서 상단 세이프에어리어
        // 인셋(화면 전체 너비)으로 옮기면서 가운데 정렬을 유지하려고 추가.
        .frame(maxWidth: .infinity)
    }
}
