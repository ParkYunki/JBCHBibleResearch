//
//  BibleReadingView.swift
//  JBCHBibleResearch
//
//  S1(성경 조회) — 다중 번역본 병렬 조회 화면.
//  - macOS/iPadOS: 최대 3열 동시 표시(HStack), 중앙 기준 스크롤 동기화.
//  - iPhone: 1열 + 스와이프(TabView 페이징). 레이아웃만 축소하고 기능은 동일하다.
//  - 순수 뷰어라 primary/accent 버튼이 없다 — 이전/다음 장, 책/장 선택,
//    번역본 선택은 모두 탐색용이다.
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

    /// 지정하면 해당 책/장을 바로 연다(통합 검색 S11 등). 기본값(nil)이면 기존 호출부 동작은 그대로다.
    /// `initialChapter`는 "지정 안 함"과 "1장 지정"을 구분하려고 옵셔널이다 — 둘 다 nil이면 `BibleReadingViewModel.init`이
    /// `LastBiblePositionTracker`(마지막으로 보던 위치)로 폴백하고, `initialBook`을 명시한 호출(SearchView 등)은 마지막 위치를
    /// 무시한다.
    var initialBook: Book? = nil
    var initialChapter: Int? = nil
    /// 지정하면 해당 절까지 스크롤한 뒤 잠시 하이라이트한다(`SearchView.verseRow`가 넘김). nil이면 동작 변화 없음.
    var initialVerse: Int? = nil
    /// false면 관련 콘텐츠(인스펙터)/조회 이력 아이콘을 툴바에서 뺀다. macOS "성경 조회 새 창"(`WindowGroup(id:
    /// "bible-reading")`)만 false를 넘긴다.
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
                        // `onAppear()`가 끝나면 이 장의 절 목록은 이미 로드돼 있어(`reloadVerses()`가 동기 호출) 바로 강조를
                        // 걸어도 안전하다.
                        //
                        // 사이드바 "최근" 이력 항목(`BibleVerseNavigationRequest.pendingTarget`)으로 다른 섹션에서
                        // 넘어와 viewModel이 새로 만들어지는 경로 — `initialBook`/`initialChapter`로 표현할 수 없는 좌표라
                        // 별도 처리한다. 이미 떠 있는 상태에서 다시 탭한 경우는 `BibleReadingContentView`의 `.onChange`가
                        // 처리한다.
                        // ⚠️ 이동 요청(검색 결과 탭 등)은 메인 창만 소비한다. macOS "성경 조회 새 창"(`isPrimaryWindow == false`)이
                        // 먼저 요청을 가져가면 이동·강조가 메인 창이 아닌 새 창에서 일어난다.
                        if isPrimaryWindow,
                           let target = BibleVerseNavigationRequest.shared.pendingTarget,
                           let book = BooksProvider.shared.book(id: target.bookId) {
                            vm.selectBook(book, chapter: target.chapter)
                            vm.highlightVerseTemporarily(target.verse)
                            BibleVerseNavigationRequest.shared.clear()
                        } else if let initialVerse {
                            vm.highlightVerseTemporarily(initialVerse)
                            // `SearchView.verseRow`가 `initialVerse`로 이 화면을 새로 띄운 경로 — `init`이
                            // `selectBook`을 거치지 않아 장 단위 기록도 남지 않으므로 여기서 장:절을 함께 기록한다.
                            vm.recordVerseHistory(verse: initialVerse)
                        }
                        viewModel = vm
                    }
            }
        }
    }
}

/// 아이폰 스와이프 정렬용 1회성 명령 — "이 컬럼(columnID)을 이 절(verse)로 맞춰라". `.onChange(of:)`로 관찰하려고 `Equatable`이다.
private struct PhoneAlignmentTarget: Equatable {
    let columnID: UUID
    let verse: Int
}

/// 컨텍스트 메뉴 [선택]이 연 팝오버(`VerseTextSelectionPopover`)의 대상 절/번역본. `.popover(item:)`이 `Identifiable`을
/// 요구해 `id`를 두며, 매번 새로 여는 팝오버라 `UUID()`로 충분하다.
private struct PartialTextSelectionTarget: Identifiable {
    let id = UUID()
    let verseNumber: Int
    let translationDisplayName: String
    let text: String
    // 개역한글(번들 성경)일 때 팝오버에서 한자 주석까지 보이고 복사되도록 넘기는 해당 절의 한자 단어 목록. KRV가 아닌 번역본은
    // `viewModel.hanjaWords(...)`가 항상 빈 배열을 돌려주므로 무조건 채워 넘겨도 영향이 없다.
    let hanjaWords: [HanjaWordAnnotation]
}

/// 원형 탐색 버튼 스타일. 지름 44pt는 Apple HIG의 최소 탭 영역이다 — 아이콘 글리프는 더 작아서 `.contentShape(Circle())`이 없으면 원
/// 여백을 눌러도 반응하지 않는다.
/// macOS 빌드에서도 쓰이므로 `#if os(iOS)` 밖에 선언해야 하며, 플랫폼 공용 SwiftUI API만 쓴다.
private struct CircularNavButtonModifier: ViewModifier {
    static let diameter: CGFloat = 44
    /// false면 이 모디파이어는 아무것도 하지 않는다. 호출부마다 `#if`를 반복하지 않고 항상 붙인 뒤 내부에서 분기한다.
    let isCircular: Bool
    func body(content: Content) -> some View {
        if isCircular {
            content
                .buttonStyle(.plain)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                // 상단 메뉴 바 배경이 시스템 재질(`.bar`)이 아니라 불투명 테마색일 수 있어, 아이콘 색을 기본 `.primary`에 맡기면 어두운 테마색
                // 위에서 대비를 잃을 수 있다. 다른 배지가 쓰는 `AccentColor`를 그대로 쓴다.
                .foregroundStyle(Color("AccentColor"))
                .contentShape(Circle())
        } else {
            content
        }
    }
}

/// 옅은 원형 배경 배지 버튼 스타일(`CircularNavButtonModifier`와 같은 원리). `BookChapterPicker.compactBarBody`(다른
/// 파일, macOS/iPad 빌드에도 컴파일됨)도 써야 하므로 `private`이 아니며 `#if os(iOS)` 밖에 둔다.
///
/// `isProminent`: true면 진한 배경+흰 아이콘(그룹의 주 실행 동작, 예: "이동"), false면 옅은 배경+accent 아이콘. 40×44 탭 영역(폭
/// 예산)은 유지하고 그 안에 34pt 원만 그린다 — 탭 영역을 키우면 "책 2장" 텍스트가 3줄로 줄바꿈되던 폭 문제가 재발할 수 있다.
struct JoinedNavBadgeModifier: ViewModifier {
    static let diameter: CGFloat = 34
    let isProminent: Bool
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .frame(width: 40, height: 44)
            .background(
                Circle()
                    .fill(isProminent ? Color("AccentColor") : Color("AccentColor").opacity(0.14))
                    .frame(width: Self.diameter, height: Self.diameter)
            )
            .foregroundStyle(isProminent ? Color.white : Color("AccentColor"))
            .contentShape(Rectangle())
    }
}

/// 콘텐츠 가장자리 안쪽에 사각 이전/다음 구절 화살표를 겹쳐(overlay) 표시한다(전 플랫폼 공통, `BibleBarButtonStyle`).
struct VerseNavArrowsModifier: ViewModifier {
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                arrowButton(systemImage: "chevron.left", enabled: canGoPrevious, action: onPrevious)
                    .padding(.leading, 6)
            }
            .overlay(alignment: .trailing) {
                arrowButton(systemImage: "chevron.right", enabled: canGoNext, action: onNext)
                    .padding(.trailing, 6)
            }
    }

    /// 전 플랫폼 공통 — 성경 조회 막대와 같은 사각 버튼(`BibleBarButtonStyle`, 2026-10-02 목업 결정). 본문 글자 위에 겹쳐도 읽히도록
    /// 버튼 뒤에 테마 배경색 92% 바탕을 깔고, 비활성(첫/마지막 구절)은 스타일의 38% 흐림을 따른다.
    /// 크기는 macOS 32pt/모서리 8, 터치 기기(iOS/iPadOS)는 탭 영역 확보를 위해 40pt/모서리 10(모양·농도는 동일).
    @ViewBuilder
    private func arrowButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        #if os(macOS)
        let size = BibleBarMetrics.height
        let radius = BibleBarMetrics.radius
        let iconSize: CGFloat = 13
        let fallbackBackground = Color(nsColor: .windowBackgroundColor)
        #else
        let size: CGFloat = 40
        let radius: CGFloat = 10
        let iconSize: CGFloat = 15
        let fallbackBackground = Color(uiColor: .systemBackground)
        #endif
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
        }
        .buttonStyle(BibleBarButtonStyle(kind: .secondary, isSquare: true, height: size, cornerRadius: radius, fontSize: iconSize))
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill((UserSettingsStore.shared.bibleBackgroundColor ?? fallbackBackground).opacity(0.92))
        )
        .disabled(!enabled)
        .help(systemImage == "chevron.left" ? "이전 구절" : "다음 구절")
    }
}

#if os(iOS)
/// 세로 좁은 화면이면 아이콘만, 아니면 기본 라벨 스타일. `.iconOnly`와 `.automatic`은 서로 다른 구체 타입이라 삼항 연산자로 합칠 수 없어,
/// `@ViewBuilder`인 `body(content:)`의 if/else로 분기한다.
private struct BottomBarLabelStyleModifier: ViewModifier {
    let isNarrow: Bool
    func body(content: Content) -> some View {
        if isNarrow {
            // 텍스트가 사라진 만큼 `.imageScale(.large)`로 SF Symbol 아이콘만 키워 탭 영역과 시인성을 유지한다(폰트 등 다른 텍스트 크기에는
            // 영향 없음).
            content
                .labelStyle(.iconOnly)
                .imageScale(.large)
        } else {
            content.labelStyle(.automatic)
        }
    }
}


/// 하단 액션바(`verseSelectionActionBar`) 버튼 스타일. `isNarrow`(아이콘 전용, `BottomBarLabelStyleModifier`와 같은
/// 값)일 때만 라운드 사각형 배경을 준다 — 글자가 함께 보이는 레이아웃에서는 어색해서 그대로 둔다. 버튼 폭은 남는 폭을
/// 균등 분할하고(`maxWidth: .infinity`) 높이는 HIG 최소 탭 영역인 44pt로 고정해, 절 1개 선택 시 최대 7개 버튼이 좁은
/// 화면에서도 한 줄에 잘리지 않고 들어가게 한다. 높이는 `CircularNavButtonModifier.diameter`를 재사용한다.
///
/// `isProminent`는 [복사]/[말씀 복사]의 강조(진한 배경+흰 아이콘)를 보존한다. narrow가 아닐 때의 강조 버튼은 이 모디파이어가 직접
/// `.borderedProminent`를 지정하므로, 호출부에서 `.buttonStyle`을 중복 지정하지 않는다(우선순위를 가정하지 않기 위해).
private struct ActionBarCircularIconModifier: ViewModifier {
    let isNarrow: Bool
    let isProminent: Bool
    /// 선택 해제처럼 배경 없는 윤곽선으로 낮출 버튼.
    var isGhost = false
    /// 아이콘 전용일 때 길게 누르면 뜨는 이름 풍선에 쓴다(`BibleBarIconOnlyModifier`).
    var title = ""
    var systemImage = ""

    private var kind: BibleBarButtonStyle.Kind { isProminent ? .primary : (isGhost ? .ghost : .secondary) }

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    /// 아이패드(세로)는 폭이 넉넉해 아이콘 아래에 기능 이름을 보인다. 아이폰은 폭이 빠듯해 지금처럼 아이콘만.
    private var showsCaption: Bool {
        !title.isEmpty && UIDevice.current.userInterfaceIdiom != .phone
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isNarrow {
            // 좁은 화면(아이폰 세로/아이패드 세로, 키보드 표시 중): 아이콘 전용 44pt 둥근 사각형.
            // 폭은 남는 폭을 균등 분할하고(`maxWidth: .infinity`) 높이는 HIG 최소 탭 영역 44pt로 고정해, 절 1개 선택 시 최대 7개 버튼이
            // 좁은 화면에서도 한 줄에 잘리지 않고 들어가게 한다.
            if showsCaption {
                // 아이패드 세로: 버튼(44pt) 바깥 아래에 기능 이름을 둔다(버튼 안이 아님). 이름은 누르는 대상이 아니라 글자일 뿐이다.
                VStack(spacing: 4) {
                    content.modifier(BibleBarIconOnlyModifier(kind: kind, title: title, systemImage: systemImage))
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(BibleBarPalette(environment: environment, colorScheme: colorScheme).text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
            } else {
                content.modifier(BibleBarIconOnlyModifier(kind: kind, title: title, systemImage: systemImage))
            }
        } else {
            // 넓은 화면(아이패드 가로 등): 맥OS와 같은 배경·테두리·강조 규격을 터치용 크기(40pt/모서리 10/글자 15pt)로 쓴다.
            // 이전에는 비강조 버튼이 배경 없는 금색 글자뿐이고 복사만 `.borderedProminent`(흰 글자 on 금색 ≈3.2:1)였다.
            content.buttonStyle(BibleBarButtonStyle(kind: kind, height: 40, cornerRadius: 10, fontSize: 15))
        }
    }
}

#endif

/// 시스템 내비게이션 바(`.navigationTitle`+`.toolbar`) 배경을 테마색에 맞춘다. `.background()`로는 바뀌지 않아 iOS 16+의
/// `.toolbarBackground(_:for:)`를 쓴다. 테마 배경이 없으면(nil) 모디파이어를 적용하지 않아 시스템 기본(automatic) 배경을 유지한다.
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    // `Color.resolve(in:)`에 넘길 현재 환경. `Color(hex:)`로 만든 고정 RGB 색이라 라이트/다크 모드와 무관하게 항상 같은 값이 나온다.
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        // `ToolbarPlacement.navigationBar`는 iOS 계열 전용이라 macOS에는 심볼이 없다(macOS는 아래 `.windowToolbar` 분기).
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // `.toolbarColorScheme`을 함께 지정하지 않으면 시스템 바 아이템의 기본 색이 바 배경이 아니라 앱 전체의 라이트/다크 모드만 따라
                // 정해져, 라이트 모드에서 어두운 테마 배경을 고르면 짙은 색 아이템이 거의 안 보일 수 있다. 배경색의 상대 휘도(WCAG 2.1 공식)로
                // 어두우면 `.dark`, 밝으면 `.light`를 지정한다.
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
        } else {
            content
        }
        #elseif os(macOS)
        // macOS도 창 통합 툴바(`.windowToolbar`) 배경을 테마색에 맞춘다 — 연구 문서/말씀 노트 등 다른 화면의 같은 이름 수정자와 동일(2026-10-01).
        // ⚠️ 그래도 이 화면은 툴바 띠가 본문보다 살짝 밝게(48 vs 42) 남는다 — 아래 시도들이 모두 효과 없었음(2026-10-01 실기기 확인):
        // `.toolbarBackgroundVisibility(.hidden)`, 루트 테마 `.background`/`.overlay`, `.inspector` 제거, 상단 `.safeAreaInset` 제거,
        // `.scrollEdgeEffectHidden(true, for: .top)`(루트/ScrollView 양쪽). 원인 미확정(툴바 뒤로 스크롤 영역이 닿을 때 시스템이 그리는 재질 추정).
        if let color {
            content
                .toolbarBackground(color, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .windowToolbar)
        } else {
            content
        }
        #else
        content
        #endif
    }

    private static func isDarkBackground(_ color: Color, in environment: EnvironmentValues) -> Bool {
        let resolved = color.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance < 0.5
    }
}

/// `TranslationRegistry` 중 화면 구성에 영향을 주는 값만 뽑은 비교용 스냅샷 — 번역본이 추가/삭제되거나 켜고 꺼질 때만 달라진다.
private struct TranslationRegistryState: Equatable {
    let id: PersistentIdentifier
    let code: String
    let isEnabled: Bool
}

private struct BibleReadingContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// 설정에서 번역본을 켜고 끄거나 다른 기기의 변경이 동기화로 도착하면 `@Query`가 갱신된다. 이를 아래 `.onChange`가 받아
    /// 뷰모델의 번역본 목록·표시 열을 즉시 다시 맞춘다(뷰모델은 화면 진입 때만 목록을 읽어 와 변경을 스스로 알 수 없다).
    /// 정렬은 뷰모델과 같은 등록 순이다. `sqliteData`(대용량)는 읽지 않고 id/code/isEnabled만 비교한다.
    @Query(sort: \TranslationRegistry.addedAt, order: .forward) private var translationRegistries: [TranslationRegistry]
    /// "성경 조회 새 창" 진입점(메뉴 AppCommands.swift와 이 화면 툴바 아이콘). 창마다 다른 번역본을 조회할 수 있다.
    @Environment(\.openWindow) private var openWindow
    let viewModel: BibleReadingViewModel
    /// false면(macOS 보조 창) 관련 콘텐츠/조회 이력 아이콘을 툴바에서 뺀다(`BibleReadingView.isPrimaryWindow` 참고).
    let isPrimaryWindow: Bool
    @State private var isTranslationPickerPresented = false
    /// "본문에서 찾기"(⌘F) 상태 — 창마다 따로다(`BibleChapterFind.swift` 참고).
    @State private var findModel = BibleChapterFindModel()
    /// 절 컨텍스트 메뉴의 "메모 작성"으로 만든 새 메모나 관련 콘텐츠 패널에서 고른 기존 메모를 시트 편집기로 띄운다. UserMemo가 SwiftData
    /// `@Model`이라 이미 Identifiable이어서 `.sheet(item:)`에 바로 쓸 수 있다.
    @State private var memoBeingCreated: UserMemo?
    /// 절 선택 하단 메뉴의 "설교작성"이 채우는 새 설교. 항상 새 설교 작성 화면을 연다(`memoBeingCreated`와 같은 옵셔널 모델 +
    /// `.sheet(item:)` 패턴, 채우는 곳은 `startSermonFromSelectedVerses()`).
    @State private var pendingSermonFromVerses: Sermon?
    /// 아이폰은 다중 씬을 지원하지 않아 `openWindow`가 크래시하므로("Unable to open a window when the app does not
    /// support multiple scenes"), 관련 콘텐츠의 "본문에서 언급됨" 문서(`handleVerseMentionSelected`의 `.document`
    /// 분기)를 새 창 대신 이 화면의 `NavigationStack`에 밀어 넣는다. 탭 시점에 대상이 정해지는 콜백이라 `NavigationLink`를 쓸 수 없어
    /// 옵셔널 상태 + `.navigationDestination(item:)`을 쓴다. macOS/iPad는 `openWindow`로 새 창을 연다.
    @State private var documentSearchRequest: DocumentSearchRequest?
    /// `documentSearchRequest`와 같은 이유·패턴 — 아이폰에서 "내 설교" 언급을 이 화면 스택에 밀어 넣는 값 기반 상태.
    /// `SermonContentTarget`은 "sermon-viewer" `WindowGroup`이 쓰는 값 타입을 그대로 재사용한다.
    @State private var sermonMentionTarget: SermonContentTarget?
    /// 관련 콘텐츠 패널(ChapterRelatedContentPanel) 표시 여부 — `.inspector(isPresented:)`에 연결한다. 과거 크래시의 진짜
    /// 원인은 `.inspector`가 아니라 이 화면에서 `@FocusedValue(\.selectSection)`을 읽은 것(자체 툴바가 있는 뷰에서 읽으면 툴바 무한
    /// 재계산 루프)이었다(`AppNavigationRequest.swift` 참고).
    @State private var isRelatedContentPresented = false
    /// 조회 이력(`BibleReadingHistorySheet`) 팝오버 표시 여부. 가끔 열어 보는 용도라 인스펙터가 아닌 팝오버로 띄운다.
    @State private var isHistoryPresented = false
    /// 책갈피 이동 팝오버(`TranslationPickerPopover`와 같은 `.popover` 패턴) 표시 여부.
    @State private var isBookmarkListPresented = false
    /// 아이폰 스와이프 정렬용 — `phoneColumns`의 `TabView` 선택 상태. 페이지가 바뀔 때마다 새로 보이는 컬럼을 정렬시킨다.
    @State private var selectedPhoneColumnID: UUID?
    /// 방금 페이지가 바뀌어 "이 컬럼을 이 절로 맞춰라"고 명령한
    /// 대상(`phoneColumns`/`TranslationColumnView.pendingCenterAlignment` 참고).
    @State private var phoneAlignmentTarget: PhoneAlignmentTarget?
    /// 구간 주석(형광펜/표시/메모/관주) "구절 확대보기" 시트 표시 여부. 정확히 절 1개가 선택됐을 때만 `verseSelectionActionBar`의 버튼이 켠다.
    @State private var isVerseZoomPresented = false
    /// `openPersonalNoteDirectly()`가 true로 세우고 확대보기를 열면
    /// `VerseZoomView(autoPresentPersonalNoteEditor:)`로 전달돼, 화면이 뜨자마자 "개인 묵상" 입력 카드가 자동으로
    /// 표시된다(`VerseZoomView.beginComposingPersonalNote()` 참고). 다음 번엔 평범하게 열리도록 시트가 닫힐 때(`onDismiss`)
    /// 항상 false로 되돌린다.
    @State private var shouldAutoPresentPersonalNoteEditor = false
    /// 확대보기에서 만든 구간 메모를 확대보기 시트가 완전히 닫힌 뒤 편집기 시트로 이어 열기 위한 임시 저장소. 같은 화면이 시트를 동시에 두 개 띄울 수 없어
    /// `onDismiss`에서 `memoBeingCreated`로 넘긴다.
    @State private var pendingPhraseMemo: UserMemo?
    /// "원문 정보"(히브리어/그리스어 단어별 Strong번호+음역+영어+한글) 시트 표시 여부. 원문은 번역본과 무관하게 book/chapter/verse에만 종속되어
    /// 별도의 열 선택 상태가 필요 없다.
    @State private var isOriginalTextInfoPresented = false
    /// "메모하기 → 원문 정보" 전환용. 두 시트를 동시에 열 수 없어(`pendingPhraseMemo`와 같은 이유) 메모하기 시트를 닫은 뒤 `onDismiss`에서
    /// 이 값을 보고 원문 정보 시트를 연다.
    @State private var pendingSwitchToOriginalTextInfo = false
    /// 반대 방향("원문 정보 → 메모하기") 전환용 — 원문 정보 시트가 완전히 닫힌 뒤 확대보기(메모하기) 시트를 연다.
    @State private var pendingSwitchToVerseZoom = false
    /// nil이 아니면 "지금 인스펙터에 말씀 요약 편집기를 띄우는 중"이라는 신호다. `isRelatedContentPresented`(관련 내용 패널)와 같은 인스펙터
    /// 자리를 공유하며 내용만 바뀐다(아래 `.inspector` 참고).
    @State private var wordSummaryBeingEdited: VerseSummary?
    /// "닫으라는 신호"와 "인스펙터가 그리는 데이터"를 분리하는 값. 아이폰(좁은 폭)에서는 `.inspector`가 시트로 뜨는데,
    /// `wordSummaryBeingEdited`를 즉시 비우면 닫힘 애니메이션 중에 밑의 콘텐츠가 "관련 내용"으로 바뀌는 것이 잠깐 보인다. 이 값은 표시 여부(즉시
    /// 내려 애니메이션 시작)만 맡고, `wordSummaryBeingEdited`는 0.3초 늦게 비운다(`closeWordSummaryEditor()` 참고). macOS는 인스펙터 대신
    /// 별도 `NSPanel`을 써서 이 값을 읽지 않는다.
    @State private var isWordSummaryInspectorVisible = false
    /// 말씀 요약 편집기를 여는 동안 기준 번역본 하나로 줄이기 전의 번역본 목록. 편집을 마치면 이 값으로 자동 복원하며, nil이면 좁혀 놓은 상태가 아니다.
    @State private var displayedTranslationIDsBeforeWordSummary: [PersistentIdentifier]?
/// 하단 액션바의 [말씀 복사]가 열려 있는 편집기 리치 텍스트뷰의 커서 위치에 직접 삽입하는 데 쓰는
/// 프록시(`WordSummaryEditorView.externalProxy` 참고).
/// macOS는 "말씀 요약"이 별도 떠 있는 패널(`WordSummaryPanelController`, 앱 전체 싱글턴)에서 열려, 성경 조회 창을 여러 개 띄워도 그
/// 패널과 항상 같은 프록시를 봐야 한다 — 창별 `@State` 대신 싱글턴이 가진 프록시를 가리킨다. iOS는 창별 `@State`를 그대로 쓴다.
#if os(macOS)
    private var wordSummaryProxy: RichTextEditingProxy { WordSummaryPanelController.shared.proxy }
#else
    @State private var wordSummaryProxy = RichTextEditingProxy()
#endif
    /// 테마의 배경/글자색(`UserSettingsStore.bibleBackgroundColor`/`bibleTextColor`)을 읽기 전용으로
    /// 가져온다(`TranslationColumnView`와 같은 계산 프로퍼티 방식 — 바인딩이 필요 없다).
    private var settings: UserSettingsStore { .shared }
    /// "세로보기에서 하단 메뉴 아이콘만 표시" 판정용(폭<높이면 true). `GeometryReader` 배경으로 이 화면이 실제로 받는 크기를 잰다 —
    /// `UIDevice.current.orientation`은 방향 알림을 별도로 켜야 하고, Split View/Slide Over에서는 기기 방향과 실제 폭이 달라
    /// 신뢰할 수 없다.
    @State private var isNarrowBottomBarLayout: Bool = false
    /// 키보드가 떠 있는 동안은 `isNarrowBottomBarLayout` 판정과 무관하게 아이콘 전용으로 강제한다. 그 판정은 키보드 세이프에어리어를 일부러
    /// 무시하므로(`.ignoresSafeArea(.keyboard, edges: .bottom)`) 키보드로 실제 가용 폭이 줄어도 "넉넉하다"고 나와 하단 메뉴 라벨이
    /// 세로로 깨져 보일 수 있다.
    @State private var isKeyboardVisible = false
    /// "말씀 요약" 인스펙터의 고정 폭. min/ideal/max에 같은 값을 넣어 고정한다 — 화면 폭에서 유도한 계산은 iPad에서 값이 불안정했다. macOS
    /// 네이티브 서식 팝업(`usesInspectorBar`)이 좁은 열 밖으로 넘치는 문제를 줄이려고 넉넉하게(640pt) 잡았다.
    private static let wordSummaryInspectorFixedWidth: CGFloat = 640

    /// 절 복사 성공 시 잠깐 보였다 사라지는 "복사되었습니다." 배너 문구(하단 액션바/컨텍스트 메뉴 공통). nil이면 감춘다.
    @State private var toastMessage: String?
    /// `toastMessage`를 일정 시간 뒤 지우는 예약 작업. 연달아 복사할 때 이전 예약을 취소하지 않으면 먼저 예약된 타이머가 새 토스트를 조기에 지운다.
    @State private var toastDismissWorkItem: DispatchWorkItem?

    /// 컨텍스트 메뉴 [선택]이 열려는 대상. nil이 아니면 `.popover(item:)`이 `VerseTextSelectionPopover`를 띄운다.
    @State private var partialTextSelectionTarget: PartialTextSelectionTarget?

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// 툴바의 책갈피 토글/조회 버튼(화면에 하나뿐)이 대상으로 삼을 번역본 코드.
    /// - macOS/iPadOS(나란히 표시): 맨 왼쪽 컬럼 — `viewModel.columns`는 `displayedTranslationIDs` 순서 그대로다.
    /// - iPhone: 지금 스와이프로 보고 있는 컬럼(`selectedPhoneColumnID`). 아직 스와이프 전이라 nil이면 첫 컬럼.
    /// 표시된 번역본이 없으면(`emptyState`) nil이며, 이때는 책갈피 버튼을 비활성화한다.
    private var bookmarkTargetTranslationCode: String? {
        #if os(iOS)
        if isPhone {
            let visibleColumnID = selectedPhoneColumnID ?? viewModel.columns.first?.id
            return viewModel.columns.first(where: { $0.id == visibleColumnID })?.registry.code
        }
        #endif
        return viewModel.columns.first?.registry.code
    }

    /// "지금 실제로 보고 있는 번역본" 이름 — `bookmarkTargetTranslationCode`와 같은 규칙(아이폰은 스와이프 중인 컬럼, 그 외는 맨 왼쪽
    /// 컬럼). 표시된 번역본이 없으면 빈 문자열.
    private var currentColumnTranslationDisplayName: String {
        #if os(iOS)
        if isPhone {
            let visibleColumnID = selectedPhoneColumnID ?? viewModel.columns.first?.id
            return viewModel.columns.first(where: { $0.id == visibleColumnID })?.registry.displayName ?? ""
        }
        #endif
        return viewModel.columns.first?.registry.displayName ?? ""
    }

    /// 기기 종류/방향/플랫폼과 무관하게 항상 44pt 원형 탐색 버튼을 쓴다(`CircularNavButtonModifier` 참고).
    private var isCompactChapterNavButtons: Bool {
        true
    }


    /// "성경 조회 새 창"은 macOS 전용이다(아이폰/아이패드에서는 새 창 아이콘을 뺀다).
    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// 아이패드 판정 — `isMac`/`isPhone`이 둘 다 아니면 아이패드다. 사이드바/인스펙터 동시 노출 방지 등에
    /// 쓴다(`IPadSidebarInspectorCoordination.swift` 참고).
    private var isIPad: Bool { !isMac && !isPhone }

    /// iOS에서 `.primaryAction`은 적응형 배치라 툴바 공간이 빠듯하면 항목이 "···" 더 보기 메뉴로 접힐 수 있어, 항상 상단 바 오른쪽에 두는
    /// `.topBarTrailing`을 쓴다. macOS는 툴바 폭이 넉넉해 `.primaryAction`을 그대로 쓴다.
    private var trailingIconPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    /// 말씀 요약 편집 중 툴바 아이콘(책갈피/조회 이력/번역본 선택)을 숨길지 여부 — 아이패드/맥에서만 true가 될 수 있다.
    /// 아이폰은 편집기가 시트로 화면을 덮어 아이콘이 어차피 가려지므로 숨기지 않는다. 숨기면 시트가 열리고 닫히는 동안(닫힐 때는
    /// `closeWordSummaryEditor()`가 0.3초 뒤 `wordSummaryBeingEdited`를 비운다) 시스템 내비게이션 바의 항목이 통째로 제거/재삽입돼,
    /// 시트 전환 애니메이션과 겹치는 순간 상단 바가 사라진 채 남을 수 있다(`NavigationBarGuard.swift` 참고). 아이폰은 툴바 구성을
    /// 항상 같게 유지한다.
    private var hidesToolbarIconsWhileEditingSummary: Bool {
        !isPhone && wordSummaryBeingEdited != nil
    }

    #if os(iOS)
    /// 시트/팝오버/커버 중 하나라도 떠 있는지 — 모두 닫힌 순간 `NavigationBarGuard`가 상단 바 상태를 다시 점검하게 하는 신호.
    private var isAnyPresentationActive: Bool {
        isRelatedContentPresented || isWordSummaryInspectorVisible || isHistoryPresented || isBookmarkListPresented
            || isTranslationPickerPresented || isVerseZoomPresented || isOriginalTextInfoPresented
            || memoBeingCreated != nil || partialTextSelectionTarget != nil
    }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if let lastErrorDescription = viewModel.lastErrorDescription {
                Text(lastErrorDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            // "본문에서 찾기"(⌘F) 막대 — 겹쳐 그리지 않고 본문 위의 한 줄로 끼워 상단 바/레일과 충돌하지 않게 한다.
            if findModel.isPresented {
                BibleChapterFindBar(model: findModel, onNext: findNext, onPrevious: findPrevious)
            }

            #if os(macOS)
            // macOS: 본문 왼쪽에 세로 도구 레일(`BibleToolRail`)을 둔다 — 예전 툴바 오른쪽 아이콘 묶음(시스템 유리 캡슐)을 대체한다.
            // 번역본이 하나도 없는 빈 화면에서도 레일(번역본 선택·새 창)을 쓸 수 있도록 빈 화면도 같은 HStack 안에 둔다.
            HStack(spacing: 0) {
                BibleToolRail(
                    viewModel: viewModel,
                    isPrimaryWindow: isPrimaryWindow,
                    isWordSummaryEditing: wordSummaryBeingEdited != nil,
                    isBookmarkListPresented: $isBookmarkListPresented,
                    isHistoryPresented: $isHistoryPresented,
                    isRelatedContentPresented: $isRelatedContentPresented,
                    isTranslationPickerPresented: $isTranslationPickerPresented,
                    onCloseWordSummary: closeWordSummaryEditor
                )
                if viewModel.columns.isEmpty {
                    emptyState
                } else {
                    sideBySideColumns
                }
            }
            #else
            if viewModel.columns.isEmpty {
                emptyState
            } else if isPhone {
                phoneColumns
            } else {
                sideBySideColumns
            }
            #endif
        }
        // 레이아웃에 영향을 주지 않는 `.background`의 `GeometryReader`로 세로/가로 판정(`isNarrowBottomBarLayout`)만 한다.
        // 값이 실제로 바뀔 때만 대입한다 — 인스펙터가 열리는 동안 매 프레임 폭이 바뀌는데, 같은 값을 무조건 대입하면 `@State` 쓰기가 "변경"으로 취급돼
        // 무거운 본문(`sideBySideColumns`/`phoneColumns`)의 `body`가 불필요하게 재계산될 수 있다.
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
        // 이 VStack이 키보드 세이프에어리어를 무시하게 한다. 위 `GeometryReader`가 재는 것은 이 화면의 렌더링 크기인데, 포커스된 텍스트 필드가
        // 있으면 키보드만큼 배정 높이가 줄어 회전 후 `폭<높이` 판정이 실제 방향과 반대로 나올 수 있다. 검색 필드는 화면 맨
        // 위(`.safeAreaInset(edge: .top)`)라 키보드와 겹치지 않는다.
        // 트레이드오프: 키보드가 떠 있는 동안 화면 맨 아래(마지막 구절/하단 액션바)가 가려질 수 있으며, `BookChapterPicker`의 "완료" 버튼으로
        // 키보드를 내릴 수 있다.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // 이전/다음 장 + 책/장 선택 + 검색창 + "이동" 줄은 툴바 `.principal`이 아니라 상단 세이프에어리어 인셋에 둔다. 아이패드(세로/Split
        // View)는 principal 영역이 좁고 양옆 툴바 버튼과 겹쳐 이 HStack이 통째로 사라질 수 있다.
        // 세로 패딩은 상단 공백을 줄이려 4pt로 하고, 가로 패딩은 좌우 버튼이 화면 끝에 붙지 않게 유지한다.
        .safeAreaInset(edge: .top) {
            chapterNavigationControls
                .padding(.horizontal)
                .padding(.vertical, 4)
                // 배경 테마를 골랐으면(`bibleBackgroundColor` != nil) 그 색을, 아니면 기존 `.bar` 재질을 쓴다. `Color`와
                // `Material`은 타입이 달라 삼항연산자로 넣을 수 없어 `@ViewBuilder` 분기를 쓴다.
                .background {
                    if let bg = settings.bibleBackgroundColor {
                        bg
                    } else {
                        Rectangle().fill(.bar)
                    }
                }
        }
        // 절 선택 → 클립보드 복사 액션바. 선택이 없으면 보이지 않는다.
        // `.safeAreaInset(edge: .bottom)`이 아니라 `.overlay`로 띄운다 — safeAreaInset은 나타나고 사라질 때 스크롤 영역
        // 크기를 바꾸는데, 같은 순간 `TranslationColumnView.columnScrollViewSyncTracking`의
        // `.scrollPosition(id:anchor:)`도 `nil ↔ .center`로 바뀌어 재중앙정렬이 겹치면서 화면이 위/아래로 튀었다.
        // `.overlay`는 부모 레이아웃 크기에 영향을 주지 않는다.
        // ⚠️ 트레이드오프: 스크롤 영역이 액션바 높이만큼 여백을 확보해 주지 않는다. 대신 `TranslationColumnView`가 목록 맨 아래에
        // 고정 여백(`bottomBufferPadding`)을 둬, 장 끝까지 스크롤하면 마지막 절을 액션바 위로 올려 볼 수 있다.
        .overlay(alignment: .bottom) {
            if viewModel.hasVerseSelection {
                verseSelectionActionBar
            }
        }
        // 하단 액션바와 컨텍스트 메뉴(단일 번역본 복사)가 이 오버레이 하나를 공유해, 복사 토스트가 화면 하단 중앙 한 곳에만 뜬다.
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        // 컨텍스트 메뉴 [선택]이 여는 팝오버 — `.popover`는 아이폰(컴팩트 폭)에서 자동으로 시트로, 아이패드/macOS에서는 팝오버로
        // 적응한다(`VerseTextSelectionPopover` 참고).
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
            // 메모를 만들거나 고친 뒤 닫으면 관련 콘텐츠 패널의 메모 목록/순서(최신 수정순)에 바로 반영되도록 새로고침한다.
            viewModel.refreshRelatedContent()
        }) { memo in
            NavigationStack {
                // 좌표가 이미 정해진 채로 열리므로 `.contextual`을 넘긴다(좌표 선택 UI 제거 + 전용 서식, MemoDetailView.swift
                // 참고). "내 메모" 탭(MemoHomeView)은 이 경로를 거치지 않는다.
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
        // 아이폰 전용 경로(`documentSearchRequest` 참고). `item:` 바인딩을 쓰는 이유 — 같은 스택에 같은 타입의
        // `.navigationDestination(for:)`가 두 번 등록되면 루트에 가까운 쪽만 쓰이는 문제(`SearchView.swift` 참고)를, 이 화면
        // 전용 상태를 직접 바인딩해 피하기 위해서다. `DocumentSearchWindowContent`는 macOS/iPad "document-search"
        // `WindowGroup`이 쓰는 뷰를 그대로 재사용한다.
        .navigationDestination(item: $documentSearchRequest) { request in
            DocumentSearchWindowContent(request: request)
        }
        // 아이폰 전용 경로(`sermonMentionTarget` 참고). `SermonContentWindowContent`는 macOS/iPad
        // "sermon-viewer" `WindowGroup`이 쓰는 뷰를 그대로 재사용한다(`SermonSupport.swift` 참고).
        .navigationDestination(item: $sermonMentionTarget) { target in
            SermonContentWindowContent(mode: .viewer, target: target)
        }
        #if os(macOS)
        // 관련 콘텐츠는 macOS에서 `.inspector`가 아니라 떠 있는 도구창(`RelatedContentPanelController`)으로 띄운다(2026-10-01).
        // 인스펙터를 열면 창 폭에서 사이드바 + 본문 최소 폭 + 인스펙터가 빠듯해 분할 뷰가 자식 호스팅 뷰의 최소 크기를 제약 갱신 도중
        // 계속 다시 알리는 순환에 빠져 "Update Constraints in Window pass" 한도 초과로 앱이 종료됐다(상세는 컨트롤러 파일 머리말).
        // 열림/닫힘은 기존처럼 `isRelatedContentPresented` 하나로 맞춘다 — 툴바 버튼이 토글하고, 패널의 닫기 버튼은 `onClose`로 이 값을 내린다.
        // 이 화면의 `.sheet`/`.popover`는 그대로이며, 메모·말씀 요약·언급 항목을 고르면 기존 콜백이 이 창에서 동작한다.
        .onChange(of: isRelatedContentPresented) { _, newValue in
            if newValue {
                presentRelatedContentPanel()
            } else {
                RelatedContentPanelController.shared.hide(owner: ObjectIdentifier(viewModel))
            }
        }
#else
        // 관련 콘텐츠 보조 사이드 패널(`.inspector(isPresented:)`). 크래시의 원인은 `.inspector`가 아니라
        // `@FocusedValue(\.selectSection)` 읽기였다(위 macOS 분기 주석과 `AppNavigationRequest.swift` 참고).
        // "말씀 요약" 편집기가 같은 인스펙터 자리를 배타적으로 공유하므로, `isPresented` 바인딩을 두 상태를 합친 계산값으로 두고 `set`에서 "닫힘"을
        // 감지해 말씀 요약 쪽이면 뒷정리(번역본/사이드바 복원)까지 처리한다 — 시스템 UI(코너 화살표 등)로 닫아도 이 경로를 탄다.
        .inspector(isPresented: Binding(
            // 표시 여부는 `isWordSummaryInspectorVisible`이 맡고, `wordSummaryBeingEdited`는 "지금 그릴 데이터"로만
            // 쓴다(닫을 때 바뀌는 타이밍이 다르다).
            get: { isRelatedContentPresented || isWordSummaryInspectorVisible },
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
                    // 이 패널도 `ChapterRelatedContentPanel`처럼 자체 닫기 버튼이 없다(`.inspector` 안에 `.toolbar`를
                    // 얹는 조합은 피했다). 닫기는 툴바의 "관련 콘텐츠" 버튼(말씀 요약 중엔 "닫기"로 동작, `toolbarContent` 참고)과 시스템
                    // 인스펙터 접기 동작으로 처리한다.
                    // "확대보기"/"원문 정보" 진입점은 `verseSelectionActionBar`에 있어 해당 콜백은 넘기지 않는다.
                    WordSummaryEditorView(
                        summary: wordSummaryBeingEdited, presentationContext: .contextual,
                        externalProxy: wordSummaryProxy,
                        // 아이폰에서는 `.inspector`가 시트로 바뀌어 바깥의 "말씀 요약 닫기" 툴바 버튼이 가려지므로, 같은
                        // 동작(`closeWordSummaryEditor()`)을 이 화면 안에서도 호출할 수 있게
                        // 넘긴다(`WordSummaryEditorView.onRequestClose` 참고).
                        onRequestClose: closeWordSummaryEditor
                    )
                } else {
                    // 개요 화면 열기/별도 창에서 보기는 이 패널이 직접(싱글턴을 통해) 요청하므로 콜백을 넘기지
                    // 않는다(`ChapterRelatedContentPanel.swift`의
                    // `jumpToOutlineEditor`/`openOutlineQuickViewWindow` 참고).
                    ChapterRelatedContentPanel(
                        viewModel: viewModel,
                        onSelectMemo: { memo in
                            memoBeingCreated = memo
                        },
                        // "[관련 말씀 요약]" 항목을 고르면 같은 자리에서 그대로 편집기로 이어 연다.
                        // ⚠️ 이 인자는 `selectedVerse`보다 앞에 와야 한다 — 레이블이 있어도 Swift는 선언
                        // 순서(`ChapterRelatedContentPanel`의 프로퍼티 순서)와 다르면 "Argument 'X' must precede
                        // argument 'Y'" 컴파일 에러를 낸다.
                        onSelectWordSummary: presentWordSummaryEditor,
                        // 정확히 절 하나가 선택돼 있을 때만 넘긴다(`ChapterRelatedContentPanel.selectedVerse` 참고).
                        selectedVerse: viewModel.selectedVerses.count == 1 ? viewModel.selectedVerses.first : nil,
                        onSelectVerseMention: handleVerseMentionSelected
                    )
                }
            }
            // 아이패드: 본문과 맞닿는 왼쪽 가장자리에 헤어라인(`IPadPaneSeparation.swift`; 아이폰은 시트라 동작 안 함).
            .iPadPaneSeparator(.leading)
            // 화면 폭에서 유도하는 계산 대신 고정 pt 상수(`Self.wordSummaryInspectorFixedWidth`)를 쓴다. min/ideal/max에
            // 같은 값을 넣어 고정폭처럼 동작시킨다(세 값 사이에서 고르게 두면 크기가 흔들릴 수 있다). 관련 내용 패널은 기존 폭 그대로다.
            .inspectorColumnWidth(
                min: wordSummaryBeingEdited != nil ? Self.wordSummaryInspectorFixedWidth : 260,
                ideal: wordSummaryBeingEdited != nil ? Self.wordSummaryInspectorFixedWidth : 300,
                max: wordSummaryBeingEdited != nil ? Self.wordSummaryInspectorFixedWidth : 400
            )
        }
// 안전망 — 말씀 요약 편집기가 열린 채 이 화면이 사라지면(예: 사이드바에서 다른 섹션으로 이동) 위 `.inspector`의 `set`이 호출되지 않을 수
// 있어, 번역본 열이 좁혀지고 바깥 사이드바가 닫힌 채 남는다. 사라질 때 뒷정리를 강제한다.
#endif
        .onDisappear {
            closeWordSummaryEditor()
            #if os(macOS)
            // 이 창(또는 성경 조회 화면)이 사라지면 그 창이 연 관련 콘텐츠 패널도 닫는다 — 패널은 이 화면의 `viewModel`에 묶여 있다.
            RelatedContentPanelController.shared.hide(owner: ObjectIdentifier(viewModel))
            #endif
        }
        // 조회 이력은 시트가 아니라 팝오버로 띄운다 — macOS는 `BibleToolRail`의 시계 아이콘, iOS는 아래 툴바 버튼에 붙는다
        // (책갈피 목록과 같은 방식, 아이폰은 시스템이 시트로 바꾼다).
        // Bible 메뉴 "다음 장 ⌘]"/"이전 장 ⌘[", View 메뉴 "스크롤 동기화" — AppCommands.swift 참고.
        .focusedSceneValue(\.nextChapterAction) { viewModel.nextChapter() }
        .focusedSceneValue(\.previousChapterAction) { viewModel.previousChapter() }
        .focusedSceneValue(\.scrollSyncEnabled, Binding(
            get: { viewModel.scrollSyncCoordinator.isEnabled },
            set: { viewModel.scrollSyncCoordinator.isEnabled = $0 }
        ))
        // Bible 메뉴 "본문에서 찾기… ⌘F" — 일치 계산·표시·메뉴 연결은 `BibleChapterFind.swift`.
        .bibleChapterFind(viewModel: viewModel, model: findModel)
        // `.navigationTitle`/`.toolbar`는 `.inspector`/`.sheet`보다 뒤(가장 바깥 레이어)에 둔다 — 안쪽에 두면
        // `.inspector`가 만드는 중간 레이어에 타이틀/툴바 프리퍼런스가 갇혀 바깥 NavigationStack에 전달되지 않을 가능성이 있다.
        .navigationTitle("성경 조회")
        .macSerifTitle("성경 조회")
        // 이 화면만 자체 상단 바(`.safeAreaInset(edge: .top)`)가 하나 더 있어, 큰 제목(large title)이면 헤더가 비정상적으로 커진다
        // — inline 모드로 강제한다. macOS에는 이 모디파이어가 없어 `#if os(iOS)`로 감싼다.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // macOS는 트레일링 아이콘이 본문 왼쪽 레일(`BibleToolRail`)로 옮겨져 툴바 항목이 없다(2026-10-02).
        #if os(iOS)
        .toolbar { toolbarContent }
        #endif
        // 시스템 내비게이션 바 배경을 테마에 맞춘다(`ThemedNavigationBarBackgroundModifier` 참고).
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        #if os(iOS)
        // 아이폰 상단 바가 간헐적으로 사라지는 증상 대응 — 시트/팝오버가 모두 닫힌 뒤와 화면이 다시 보일 때 바 상태를 점검하고,
        // 숨겨져 있으면 되돌린다(`NavigationBarGuard.swift` 참고). 레이아웃/터치에 영향을 주지 않는다.
        .background {
            if isPhone {
                NavigationBarGuard(recheckToken: isAnyPresentationActive)
            }
        }
        #endif
        // 이미 성경 조회를 보고 있는 채로 사이드바 "최근" 이력 항목을 다시 탭한 경우 — 화면이 다시 만들어지지 않아 `BibleReadingView`의
        // `.onAppear`가 실행되지 않으므로 `.onChange`로 처리한다.
        .onChange(of: translationRegistries.map { TranslationRegistryState(id: $0.persistentModelID, code: $0.code, isEnabled: $0.isEnabled) }) { _, _ in
            viewModel.loadAvailableTranslations()
        }
        // 설정 > 번역본에서 사용 중인 번역본을 켜고 끄거나 순서를 바꾼 경우(이 기기의 목록 `defaultDisplayedTranslationCodes`).
        .onChange(of: UserSettingsStore.shared.defaultDisplayedTranslationCodes) { _, _ in
            viewModel.loadAvailableTranslations()
        }
        // 동기화 대기 때문에 번역본 열이 오류로 남아 있다가(파일 도착 전) 앱이 다시 활성화되면 한 번 다시 시도한다.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, viewModel.columns.contains(where: { $0.errorDescription != nil }) else { return }
            viewModel.loadAvailableTranslations()
        }
        .onChange(of: BibleVerseNavigationRequest.shared.pendingTarget) { _, newValue in
            // 메인 창만 소비한다 — 보조 창(`isPrimaryWindow == false`)이 가져가면 이동·강조가 새 창에서 일어난다.
            guard isPrimaryWindow, let newValue, let book = BooksProvider.shared.book(id: newValue.bookId) else { return }
            viewModel.selectBook(book, chapter: newValue.chapter)
            viewModel.highlightVerseTemporarily(newValue.verse)
            BibleVerseNavigationRequest.shared.clear()
        }
        // 관련 콘텐츠 인스펙터가 (어떤 경로로든) 열리고 닫히는 것을 `IPadSidebarInspectorCoordination` 싱글턴에 보고한다(아이패드에서
        // 사이드바/인스펙터 동시 노출 방지). 말씀 요약 편집기가 이 자리를 쓰는 경우는 포함하지 않는다(기존 `SidebarVisibilityRequest` 계약을
        // 따른다).
        .onChange(of: isRelatedContentPresented) { _, newValue in
            guard isIPad else { return }
            IPadSidebarInspectorCoordination.shared.reportInspectorVisibility(newValue)
        }
        // 사이드바가 (어떤 경로로든) 열리는 순간을 관찰해 이 화면이 스스로(로컬 상태만) 관련 콘텐츠 인스펙터를 닫는다 — 사이드바 쪽에 대신 닫아 달라는 명령을 보낼
        // 필요가 없다.
        .onChange(of: IPadSidebarInspectorCoordination.shared.isSidebarVisible) { _, newValue in
            guard isIPad, newValue, isRelatedContentPresented else { return }
            isRelatedContentPresented = false
        }
    }

    /// 절 팝업 메뉴(길게 누르기/오른쪽 클릭)의 "개인 묵상 작성" 처리 — 그 절만 선택한 뒤
    /// `openPersonalNoteDirectly()`로 확대보기를 거쳐 열어, 하단 액션바의 "개인 묵상" 버튼과
    /// 동일하게 동작한다.
    private func createMemo(for verse: BibleVerse) {
        viewModel.selectSingleVerse(verse.verse)
        openPersonalNoteDirectly()
    }

    // MARK: - 장 끝 버튼 (이전 장 / 다음 장 / 이 장의 개인 묵상)

    /// 이전/다음 장의 표시 이름. 책 경계를 넘으면 이웃 책의 첫/마지막 장이고(`BibleReadingViewModel.previousChapter/nextChapter`와 같은
    /// 규칙), 창세기 1장의 이전·계시록 마지막 장의 다음은 nil이다.
    private func adjacentChapterLabel(forward: Bool) -> String? {
        let book = viewModel.selectedBook
        let chapter = viewModel.selectedChapter
        if forward {
            if chapter < book.chapterCount { return "\(book.nameKo) \(chapter + 1)장" }
            if let next = BooksProvider.shared.book(after: book) { return "\(next.nameKo) 1장" }
        } else {
            if chapter > 1 { return "\(book.nameKo) \(chapter - 1)장" }
            if let previous = BooksProvider.shared.book(before: book) { return "\(previous.nameKo) \(previous.chapterCount)장" }
        }
        return nil
    }

    private var chapterEndActions: ChapterEndActions {
        ChapterEndActions(
            previousLabel: adjacentChapterLabel(forward: false),
            nextLabel: adjacentChapterLabel(forward: true),
            onPrevious: { viewModel.previousChapter() },
            onNext: { viewModel.nextChapter() },
            existingNotes: viewModel.chapterLevelMemos.prefix(8).map { memo in
                let firstLine = memo.contentText
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                return ChapterNoteItem(id: memo.id, preview: String(firstLine.prefix(28))) { memoBeingCreated = memo }
            },
            onNewNote: { memoBeingCreated = viewModel.createChapterMemo() }
        )
    }

    /// 관주 팝오버에서 대상 구절을 탭했을 때 해당 책/장으로 이동한 뒤 그 절을 잠시 강조한다.
    private func jumpToCrossReferenceTarget(_ target: BibleVerseRef) {
        guard let book = BooksProvider.shared.book(id: target.bookId) else { return }
        viewModel.selectBook(book, chapter: target.chapter)
        viewModel.highlightVerseTemporarily(target.verse)
    }

    /// 관련 내용 선택 처리 — 메모는 `.contextual` 메모 시트로, 연구문서는 검색어와 함께
    /// "document-search" 창으로 연다.
    private func handleVerseMentionSelected(_ mention: VerseMention) {
        switch mention.sourceType {
        case .memo:
            if let memo = viewModel.resolveMemo(for: mention) {
                memoBeingCreated = memo
            }
        case .document:
            if let document = viewModel.resolveDocument(for: mention) {
                let request = DocumentSearchRequest(documentID: document.persistentModelID, searchText: mention.searchText)
                // 아이폰은 새 창 대신 현재 화면 스택에 밀어 넣는다(`documentSearchRequest` 참고).
                if isPhone {
                    documentSearchRequest = request
                } else {
                    openWindow(id: "document-search", value: request)
                }
            }
        // 관련 말씀 요약도 개인 묵상과 같은 방식으로, 기존 요약을 인스펙터 편집기로 연다.
        case .wordSummary:
            if let summary = viewModel.resolveWordSummary(for: mention) {
                presentWordSummaryEditor(summary)
            }
        // 아이폰은 이 화면 스택에 밀어 넣고(`sermonMentionTarget`), macOS/iPad는
        // 기존 "sermon-viewer" 창을 연다.
        case .sermon:
            if let sermon = viewModel.resolveSermon(for: mention) {
                if isPhone {
                    sermonMentionTarget = SermonContentTarget.sermon(sermon)
                } else {
                    openWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(sermon))
                }
            }
        }
    }

    /// 선택된 절로 새 `VerseSummary`를 만들어 편집기를 연다(누를 때마다 새 레코드).
    /// 좌표(`VerseSummary.verse`)는 정렬된 첫 절을 앵커로 저장한다.
    /// 기본 문구는 `WordSummaryDefaultSeed.text(for:)`로만 계산한다 —
    /// `WordSummaryEditorView.handleDisappear()`가 같은 함수로 "기본 문구뿐인지" 판정하므로
    /// 두 곳의 문자열이 달라지면 안 된다.
    private func openWordSummaryEditor() {
        let verses = viewModel.selectedVerses
        guard let anchorVerse = verses.sorted().first else { return }

        let now = Date.now
        let seedText = WordSummaryDefaultSeed.text(for: now)

        let summary = VerseSummary(
            bookId: viewModel.selectedBook.bookId,
            chapter: viewModel.selectedChapter,
            verse: anchorVerse,
            // `contentHtml`은 실제로는 RTF 저장소다 — `{\rtf1`로 시작하지 않는 일반 문자열은
            // "레거시 텍스트"로 인식돼 기본 서식으로 표시되므로, 별도 RTF 인코딩 없이 프리필한다.
            contentHtml: seedText,
            contentText: seedText,
            createdAt: now
        )
        modelContext.insert(summary)
        try? modelContext.save()
        // 저장 직후 관련 성경구절을 추출해 인덱싱한다(관련 말씀 요약 섹션이 이 인덱스를 쓴다).
        BibleReferenceIndexingService.reindexWordSummary(summary, context: modelContext)
        presentWordSummaryEditor(summary)
    }

    #if os(macOS)
    /// 관련 콘텐츠 떠 있는 도구창을 연다(이미 떠 있으면 앞으로). 패널은 SwiftUI 창 계층 밖이라 `modelContext`와 `openWindow`를 명시적으로
    /// 넘긴다. 패널이 어떻게 닫히든(닫기 버튼 포함) `onClose`가 "열림" 표시를 내려 툴바 버튼 상태와 어긋나지 않는다.
    private func presentRelatedContentPanel() {
        let root = RelatedContentPanelRoot(
            viewModel: viewModel,
            onSelectMemo: { memo in memoBeingCreated = memo },
            onSelectWordSummary: presentWordSummaryEditor,
            onSelectVerseMention: handleVerseMentionSelected,
            openWindow: openWindow
        )
        .environment(\.modelContext, modelContext)
        RelatedContentPanelController.shared.present(
            content: AnyView(root),
            ownerToken: ObjectIdentifier(viewModel)
        ) {
            isRelatedContentPresented = false
        }
    }
    #endif

    /// 새로 만들기와 기존 항목 선택이 공유하는 "편집기 열기" 절차 —
    /// 번역본 열 좁히기/왼쪽 사이드바 닫기를 동일하게 적용한다.
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

        // 왼쪽 사이드바 닫기 — macOS/iPadOS에서만 의미가 있다.
        // 아이폰 탭바 레이아웃은 이 요청을 구독하지 않아 무시된다.
        SidebarVisibilityRequest.shared.requestHide()

        wordSummaryBeingEdited = summary
        // 아이폰 인스펙터(시트)의 표시 여부는 `isWordSummaryInspectorVisible`이 단독으로 맡는다.
        isWordSummaryInspectorVisible = true

        // macOS는 `wordSummaryBeingEdited`를 인스펙터 대신 별도 떠 있는 패널
        // (`WordSummaryPanelController`)이 소비한다. `onClose`로 `closeWordSummaryEditor()`를 넘겨,
        // 패널이 어떻게 닫히든 번역본/사이드바 복원이 항상 똑같이 실행되게 한다.
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

    /// 말씀 요약 편집기를 닫으면서 번역본 열/사이드바를 편집 시작 전 상태로 되돌린다.
    private func closeWordSummaryEditor() {
        guard wordSummaryBeingEdited != nil else { return }
        // 닫으라는 신호를 즉시 내려 시트 닫힘 애니메이션을 바로 시작시킨다
        // (macOS는 이 값을 읽지 않아 무해하다).
        isWordSummaryInspectorVisible = false
        if let previousIDs = displayedTranslationIDsBeforeWordSummary {
            viewModel.setDisplayedTranslations(previousIDs)
        }
        displayedTranslationIDsBeforeWordSummary = nil
        SidebarVisibilityRequest.shared.requestRestore()
        #if os(macOS)
        // macOS는 인스펙터가 아닌 별도 `NSPanel`을 쓰므로 `wordSummaryBeingEdited`를 즉시 비운다.
        // `hide()`가 패널을 닫으면 델리게이트가 `onClose`(이 함수)를 다시 부르지만,
        // 이미 nil이라 맨 위 `guard`에서 반환되므로 재진입은 안전하다.
        wordSummaryBeingEdited = nil
        WordSummaryPanelController.shared.hide()
        #else
        // 아이폰은 인스펙터가 시트로 뜨므로, 시트가 사라질 시간(0.3초)만큼 `wordSummaryBeingEdited`를
        // 늦게 비운다 — 그동안 같은 `WordSummaryEditorView`가 그려져 전환이 눈에 보이지 않는다.
        // 지연 중 다른 항목이 열렸다면 그 새 값을 지우지 않도록 id를 확인한다.
        let closingSummaryID = wordSummaryBeingEdited?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if wordSummaryBeingEdited?.id == closingSummaryID {
                wordSummaryBeingEdited = nil
            }
        }
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
        // 아이폰은 한 번에 컬럼 하나만 보이므로 실시간 스크롤 동기화를 끄고(`respondsToSyncEvents: false`),
        // 페이지가 바뀌는 순간에만 `pendingCenterAlignment`로 넘기기 전 중앙 절에 한 번 맞춘다.
        TabView(selection: $selectedPhoneColumnID) {
            ForEach(viewModel.columns) { column in
                TranslationColumnView(
                    columnID: column.id,
                    translationDisplayName: column.registry.displayName,
                    localizedBookChapterLabel: column.localizedBookChapterLabel,
                    verses: column.verses,
                    errorDescription: column.errorDescription,
                    // 검색 결과는 특정 번역본을 지정하지 않으므로 모든 컬럼에 같은 값을 넘겨,
                    // 보이는 컬럼 전부에서 그 절이 강조된다.
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
                    // 표시 중인 번역본이 하나뿐이면 스와이프해서 넘어갈 다른 페이지가 없다.
                    hasAdditionalDisplayedColumns: viewModel.columns.count > 1,
                    highlightsProvider: { verse in viewModel.highlights(translationCode: column.registry.code, verse: verse) },
                    crossReferencesProvider: { verse in viewModel.crossReferences(translationCode: column.registry.code, verse: verse) },
                    phraseMemosProvider: { verse in viewModel.phraseMemos(translationCode: column.registry.code, verse: verse) },
                    phraseNotesProvider: { verse in viewModel.phraseNotes(translationCode: column.registry.code, verse: verse) },
                    marginalNotesProvider: { verse in viewModel.marginalNotes(translationCode: column.registry.code, verse: verse) },
                    hanjaWordsProvider: { verse in viewModel.hanjaWords(translationCode: column.registry.code, verse: verse) },
                    verseMentionsProvider: { verse in viewModel.verseMentions(verse: verse) },
                    // 인자는 프로퍼티 선언 순서(멤버와이즈 초기화)를 따라야 하므로 `verseMentionsProvider` 바로 뒤에 둔다.
                    // 책갈피는 번역본별이므로 이 컬럼의 `column.registry.code`를 넘긴다.
                    isBookmarkedProvider: { verse in viewModel.isVerseBookmarked(translationCode: column.registry.code, verse: verse) },
                    isChapterBookmarked: viewModel.isChapterBookmarked(translationCode: column.registry.code),
                    onSelectCrossReferenceTarget: jumpToCrossReferenceTarget,
                    onSelectPhraseMemo: { memo in memoBeingCreated = memo },
                    onSelectVerseMention: handleVerseMentionSelected,
                    // 다른 provider들과 같이 `column.registry.code`를 붙잡아 넘긴다 — 실제 캐시는
                    // `BibleReadingViewModel.cachedInlineAnnotatedContent`(세션 전체 유지)가 갖고 있다.
                    inlineAnnotatedContentProvider: { verse, highlights, phraseNotes, hanjaWords, marginalNotes, font, textColor, hanjaFont in
                        viewModel.cachedInlineAnnotatedContent(
                            bookId: verse.bookId, chapter: verse.chapter, translationCode: column.registry.code, verse: verse.verse,
                            text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
                            hanjaWords: hanjaWords, marginalNotes: marginalNotes, font: font, textColor: textColor, hanjaFont: hanjaFont
                        )
                    },
                    // 아이폰은 컬럼마다 별도 페이지라 모든 페이지의 장 끝에 붙인다.
                    chapterEndActions: chapterEndActions,
                    findMatchVerses: findModel.matchedVerses(in: column.id),
                    currentFindVerse: findModel.currentVerse
                )
                .tag(column.id)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: viewModel.columns.count > 1 ? .always : .never))
        #endif
        // 상단 내비게이션 바와 본문 사이에 흰 줄이 남는 문제 대응 — `NavigationStack` 본문에 `TabView`가
        // 있으면 조상 뷰에만 건 `.toolbarBackground`가 완전히 반영되지 않는 경우가 있어
        // (Apple Developer Forums #774036) 이 `TabView`에도 직접 건다. 같은 값을 읽으므로
        // `BibleReadingContentView.body`의 것과 중복돼도 해가 없다.
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        // `.page` 스타일 `TabView` 컨테이너 프레임 자체는 배경을 칠한 곳이 없어 기본색 띠가 보일 수 있으므로,
        // 다른 컨테이너처럼 "nil이면 기존 그대로" 폴백으로 배경을 준다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
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
                    // 검색 결과는 특정 번역본을 지정하지 않으므로 모든 컬럼에 같은 값을 넘겨,
                    // 보이는 컬럼 전부에서 그 절이 강조된다.
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
                    // 인자는 프로퍼티 선언 순서(멤버와이즈 초기화)를 따라야 하므로 `verseMentionsProvider` 바로 뒤에 둔다.
                    // 책갈피는 번역본별이므로 이 컬럼의 `column.registry.code`를 넘긴다.
                    isBookmarkedProvider: { verse in viewModel.isVerseBookmarked(translationCode: column.registry.code, verse: verse) },
                    isChapterBookmarked: viewModel.isChapterBookmarked(translationCode: column.registry.code),
                    onSelectCrossReferenceTarget: jumpToCrossReferenceTarget,
                    onSelectPhraseMemo: { memo in memoBeingCreated = memo },
                    onSelectVerseMention: handleVerseMentionSelected,
                    // 다른 provider들과 같이 `column.registry.code`를 붙잡아 넘긴다 — 실제 캐시는
                    // `BibleReadingViewModel.cachedInlineAnnotatedContent`(세션 전체 유지)가 갖고 있다.
                    inlineAnnotatedContentProvider: { verse, highlights, phraseNotes, hanjaWords, marginalNotes, font, textColor, hanjaFont in
                        viewModel.cachedInlineAnnotatedContent(
                            bookId: verse.bookId, chapter: verse.chapter, translationCode: column.registry.code, verse: verse.verse,
                            text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
                            hanjaWords: hanjaWords, marginalNotes: marginalNotes, font: font, textColor: textColor, hanjaFont: hanjaFont
                        )
                    },
                    // 여러 컬럼이면 버튼이 중복되지 않게 첫 컬럼에만 붙인다.
                    chapterEndActions: index == 0 ? chapterEndActions : nil,
                    findMatchVerses: findModel.matchedVerses(in: column.id),
                    currentFindVerse: findModel.currentVerse
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 찾기 막대의 다음/이전 — 일치 절로 옮기고 모든 컬럼을 그 절로 스크롤한다(검색 결과 이동과 같은 `highlightVerseTemporarily` 경로).
    private func findNext() {
        findModel.next()
        scrollToCurrentFindMatch()
    }

    private func findPrevious() {
        findModel.previous()
        scrollToCurrentFindMatch()
    }

    private func scrollToCurrentFindMatch() {
        if let verse = findModel.currentVerse {
            viewModel.highlightVerseTemporarily(verse)
        }
    }

    /// 확대보기 시트를 열면서 조회 이력도 항상 함께 기록한다 — 버튼이 늘어나도
    /// 기록이 누락되지 않도록 공통 함수로 뺐다.
    private func openVerseZoom() {
        if let verseNumber = viewModel.selectedVerses.first {
            viewModel.recordVerseHistory(verse: verseNumber)
        }
        isVerseZoomPresented = true
    }

    /// 확대보기(`VerseZoomView`)를 열면서 `shouldAutoPresentPersonalNoteEditor`를 세워, 그 화면이 뜨자마자
    /// 안쪽 "개인 묵상" 버튼을 누른 것과 동일하게 동작하게 한다.
    /// `VerseZoomView`는 `autoPresentPersonalNoteEditor`를 `@Binding`으로 받아 `onAppear`에서 최신 값을
    /// 다시 읽는다 — 생성자 인자(`let`)로 한 번만 받으면 첫 표시 때 값이 반영되지 않았고,
    /// 시트 표시 시점만 `DispatchQueue.main.async`로 미루는 것으로는 해결되지 않았다.
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
        // narrow(아이폰 세로/아이패드 세로)에서는 아이콘 전용 원형 버튼(44pt 고정,
        // `CircularNavButtonModifier.diameter` — HIG 최소 탭 영역이라 줄일 수 없다)이 한 줄 폭을 거의
        // 차지해 "x개 절 선택됨" 문구가 잘릴 수 있다. 그래서 narrow일 때만 문구를 버튼 줄 위 별도 한 줄로
        // 두고, 버튼 간격은 16pt, 세로 여백은 줄인다. narrow가 아니면 한 줄 배치를 그대로 쓴다.
        VStack(alignment: .leading, spacing: isNarrowBottomBarLayout ? 6 : 0) {
            if isNarrowBottomBarLayout {
                BibleBarCountChip(text: "\(viewModel.selectedVerses.count)개 절 선택됨")
            }
            verseSelectionActionButtonsRow
        }
        // 키보드가 떠 있으면 하단 메뉴 텍스트가 세로로 보이는 문제가 있어(`isKeyboardVisible`),
        // 키보드 표시/숨김을 직접 관찰해 아이콘 전용 판정에 OR로 더한다.
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        #endif
        // 세로보기(narrow)에서는 한글 메뉴명 없이 아이콘만 표시한다.
        // macOS는 창 폭이 넉넉하므로 iOS(아이폰/아이패드)에서만 적용한다.
        #if os(iOS)
        .modifier(BottomBarLabelStyleModifier(isNarrow: isNarrowBottomBarLayout || isKeyboardVisible))
        #endif
        .padding(.horizontal)
        .padding(.vertical, isNarrowBottomBarLayout ? 8 : nil)
        // 배경은 테마색이 있으면 그 색, 없으면 기존 `.bar` 재질(상단 메뉴 바와 같은 패턴).
        // 아이패드에서 배경이 홈 인디케이터 안전영역 위에서 멈춰 화면 바닥과 간격이 생기므로 배경에만
        // `.ignoresSafeArea(edges: .bottom)`을 준다 — 버튼 콘텐츠는 이 modifier 밖이라 안전영역
        // 패딩을 유지해 홈 인디케이터 제스처 구역과 겹치지 않는다.
        // 본문과 구분되도록 (1) 강조색 6% 톤을 얹고 (2) 맨 위에 0.5pt 헤어라인을 긋고 (3) 위쪽으로 옅은 그림자를 드리운다.
        // 톤·라인은 테마 배경색/글자색에서 파생해 어떤 테마에서도 어색하지 않게 한다.
        .background {
            ZStack {
                if let bg = settings.bibleBackgroundColor {
                    bg
                } else {
                    Rectangle().fill(.bar)
                }
                Color("AccentColor").opacity(0.06)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill((settings.bibleTextColor ?? Color.secondary).opacity(0.25))
                    .frame(height: 0.5)
            }
            .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: -2)
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $isVerseZoomPresented, onDismiss: {
            // 확대보기에서 만든 메모는 시트가 완전히 닫힌 뒤 이어서 편집기 시트를 연다 —
            // 한 화면에서 시트 두 개를 동시에 띄울 수 없기 때문(`pendingPhraseMemo`).
            if let memo = pendingPhraseMemo {
                pendingPhraseMemo = nil
                memoBeingCreated = memo
            }
            // 메모하기 → 원문 정보 전환(`pendingSwitchToOriginalTextInfo`).
            if pendingSwitchToOriginalTextInfo {
                pendingSwitchToOriginalTextInfo = false
                isOriginalTextInfoPresented = true
            }
            // 확대보기 세션이 끝났으니 자동 표시 플래그를 기본값으로 되돌린다.
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
                    // 실제 이동은 뷰모델의 `goToPreviousVerse(from:)`/`goToNextVerse(from:)`가 책임진다
                    // (장/책 경계 넘기 포함) — 이 화면은 현재 절 번호만 넘긴다.
                    onNavigateToPreviousVerse: { viewModel.goToPreviousVerse(from: verseNumber) },
                    onNavigateToNextVerse: { viewModel.goToNextVerse(from: verseNumber) },
                    canGoToPreviousVerse: viewModel.canGoToPreviousVerse(from: verseNumber),
                    canGoToNextVerse: viewModel.canGoToNextVerse(from: verseNumber),
                    autoPresentPersonalNoteEditor: $shouldAutoPresentPersonalNoteEditor
                )
            }
        }
        .sheet(isPresented: $isOriginalTextInfoPresented, onDismiss: {
            // 원문 정보 → 메모하기 전환(`pendingSwitchToVerseZoom`). `openVerseZoom()`을 재사용해
            // 이 경로로 열리는 경우에도 조회 이력에 남긴다.
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
                    },
                    // 위 `VerseZoomView` 호출부와 같은 방식.
                    onNavigateToPreviousVerse: { viewModel.goToPreviousVerse(from: verseNumber) },
                    onNavigateToNextVerse: { viewModel.goToNextVerse(from: verseNumber) },
                    canGoToPreviousVerse: viewModel.canGoToPreviousVerse(from: verseNumber),
                    canGoToNextVerse: viewModel.canGoToNextVerse(from: verseNumber)
                )
            }
        }
        // `memoBeingCreated`와 같은 패턴 — `Sermon`이 `id: UUID`를 직접 선언하므로 `.sheet(item:)`에 바로 쓸 수 있다.
        // 아이패드·맥의 "설교작성"은 새 창("sermon-new")으로 열리므로(`startSermonFromSelectedVerses`) 이 시트는 사실상 아이폰
        // 전용이다. `SermonEditorView`의 페이지 안 "완료/취소" 줄은 `!isPhoneIdiom`일 때만 보이므로, 아이폰에서는 이 시트를
        // 감싸는 `NavigationStack` 쪽에서 별도로 "취소" 버튼을 더한다.
        .sheet(item: $pendingSermonFromVerses) { sermon in
            NavigationStack {
                SermonEditorView(
                    subject: .sermon(sermon), isNewSermon: true,
                    onRequestClose: { pendingSermonFromVerses = nil }
                )
                #if os(iOS)
                .toolbar {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("취소") { pendingSermonFromVerses = nil }
                        }
                    }
                }
                #endif
            }
        }
    }

    /// 라벨 버튼 줄(맥OS, 아이패드 가로): 창이 좁아 한 줄에 다 안 들어가면 라벨을 줄여 아이콘만 남긴다(툴팁은 맥OS `.help`).
    /// `ViewThatFits`가 "라벨+아이콘" 줄이 들어가면 그것을, 아니면 "아이콘만" 줄을 고른다.
    /// iOS에서 이미 아이콘 전용으로 강제된 상태(좁은 화면/키보드 표시)는 바깥 `BottomBarLabelStyleModifier`가 정하므로 여기서 건드리지 않는다
    /// (안쪽 `.labelStyle`이 바깥 것을 덮어쓰기 때문).
    @ViewBuilder
    private var verseSelectionActionButtonsRow: some View {
        if allowsActionRowCollapse {
            ViewThatFits(in: .horizontal) {
                verseSelectionActionButtonsRowContent.labelStyle(.titleAndIcon)
                verseSelectionActionButtonsRowContent.labelStyle(.iconOnly)
            }
        } else {
            verseSelectionActionButtonsRowContent
        }
    }

    private var allowsActionRowCollapse: Bool {
        #if os(macOS)
        return true
        #else
        return !(isNarrowBottomBarLayout || isKeyboardVisible)
        #endif
    }

    /// 버튼 묶음 사이 구분선 — 라벨 버튼 줄(맥OS, 아이패드 가로)에서만. 아이콘 전용 줄은 폭이 빠듯해 두지 않는다.
    private var showsActionGroupDividers: Bool {
        #if os(macOS)
        return true
        #else
        return !(isNarrowBottomBarLayout || isKeyboardVisible)
        #endif
    }

    private var actionRowSpacing: CGFloat? {
        #if os(macOS)
        return 6
        #else
        return (isNarrowBottomBarLayout || isKeyboardVisible) ? 4 : 6
        #endif
    }

    private var verseSelectionActionButtonsRowContent: some View {
        HStack(spacing: actionRowSpacing) {
            if !isNarrowBottomBarLayout {
                BibleBarCountChip(text: "\(viewModel.selectedVerses.count)개 절 선택됨")
            }
            if !isNarrowBottomBarLayout {
                Spacer()
            }

            // 말씀 요약 편집 중에는 이 줄이 "편집 중인 요약에 구절을 보태는" 용도로 바뀌므로 말씀 요약/선택 해제/복사는
            // 감추고 "말씀 복사"를 둔다. 확대보기/원문 정보는 절 하나를 다루므로(`VerseZoomView`/`OriginalTextInfoView`가
            // 단일 verseNumber를 받는다) 정확히 1개가 선택돼 있을 때만 보인다.
            if wordSummaryBeingEdited != nil {
                if viewModel.selectedVerses.count == 1 {
                    Button {
                        openVerseZoom()
                    } label: {
                        Label("메모하기", systemImage: "text.bubble")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, title: "메모하기", systemImage: "text.bubble"))
                    #else
                    .modifier(BibleBarActionModifier(kind: .secondary, help: "메모하기"))
                    #endif
                    // `openPersonalNoteDirectly()` — 확대보기를 열고 안쪽 개인 묵상 입력칸(카드)을 자동으로 연다.
                    Button {
                        openPersonalNoteDirectly()
                    } label: {
                        Label("개인 묵상", systemImage: "note.text")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, title: "개인 묵상", systemImage: "note.text"))
                    #else
                    .modifier(BibleBarActionModifier(kind: .secondary, help: "개인 묵상"))
                    #endif
                    Button {
                        isOriginalTextInfoPresented = true
                    } label: {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, title: "원문 정보", systemImage: "character.book.closed"))
                    #else
                    .modifier(BibleBarActionModifier(kind: .secondary, help: "원문 정보"))
                    #endif
                }
                if showsActionGroupDividers && viewModel.selectedVerses.count == 1 { BibleBarGroupDivider() }
                Button {
                    copySelectedVersesIntoWordSummary()
                } label: {
                    Label("말씀 복사", systemImage: "text.insert")
                }
                #if os(iOS)
                .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: true, title: "말씀 복사", systemImage: "text.insert"))
                #else
                .modifier(BibleBarActionModifier(kind: .primary, help: "말씀 복사"))
                #endif
                // 바깥쪽 `.safeAreaInset`이 이미 `hasVerseSelection`(1개 이상)일 때만 이 바를 그리므로
                // 여기선 추가 조건이 필요 없다.
            } else {
                // 구간 주석(형광펜/표시/메모/관주) 진입점 — 확대보기/원문 정보는 절 하나를 다루므로
                // 정확히 1개가 선택됐을 때만 보인다.
                if viewModel.selectedVerses.count == 1 {
                    Button {
                        openVerseZoom()
                    } label: {
                        Label("메모하기", systemImage: "text.bubble")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, title: "메모하기", systemImage: "text.bubble"))
                    #else
                    .modifier(BibleBarActionModifier(kind: .secondary, help: "메모하기"))
                    #endif
                    // `openPersonalNoteDirectly()` — 확대보기를 열고 안쪽 개인 묵상 입력칸(카드)을 자동으로 연다.
                    Button {
                        openPersonalNoteDirectly()
                    } label: {
                        Label("개인 묵상", systemImage: "note.text")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, title: "개인 묵상", systemImage: "note.text"))
                    #else
                    .modifier(BibleBarActionModifier(kind: .secondary, help: "개인 묵상"))
                    #endif
                    Button {
                        isOriginalTextInfoPresented = true
                    } label: {
                        Label("원문 정보", systemImage: "character.book.closed")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, title: "원문 정보", systemImage: "character.book.closed"))
                    #else
                    .modifier(BibleBarActionModifier(kind: .secondary, help: "원문 정보"))
                    #endif
                }
                // 맥OS: 단일 절 작업 묶음과 요약·설교 묶음 사이 구분선.
                if showsActionGroupDividers && viewModel.selectedVerses.count == 1 { BibleBarGroupDivider() }
                // 말씀 요약은 여러 절을 한 번에 요약해도 자연스러우므로 1개 이상이면 노출한다.
                if !viewModel.selectedVerses.isEmpty {
                    Button {
                        openWordSummaryEditor()
                    } label: {
                        Label("말씀 요약", systemImage: "text.quote")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, title: "말씀 요약", systemImage: "text.quote"))
                    #else
                    .modifier(BibleBarActionModifier(kind: .secondary, help: "말씀 요약"))
                    #endif
                    // 말씀 요약과 같은 노출 조건(1개 이상).
                    Button {
                        startSermonFromSelectedVerses()
                    } label: {
                        Label("설교작성", systemImage: "text.book.closed")
                    }
                    #if os(iOS)
                    .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, title: "설교작성", systemImage: "text.book.closed"))
                    #else
                    .modifier(BibleBarActionModifier(kind: .secondary, help: "설교작성"))
                    #endif
                }
                if showsActionGroupDividers { BibleBarGroupDivider() }
                Button {
                    viewModel.clearVerseSelection()
                } label: {
                    // 아이콘 전용 표시가 이 줄의 버튼 전부에 적용되려면 다른 버튼처럼 `Label`(아이콘+텍스트)이어야 한다.
                    Label("선택 해제", systemImage: "xmark.circle")
                }
                #if os(iOS)
                .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: false, isGhost: true, title: "선택 해제", systemImage: "xmark.circle"))
                #else
                .modifier(BibleBarActionModifier(kind: .ghost, help: "선택 해제"))
                #endif
                Button {
                    copySelectedVerses()
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
                #if os(iOS)
                .modifier(ActionBarCircularIconModifier(isNarrow: isNarrowBottomBarLayout, isProminent: true, title: "복사", systemImage: "doc.on.doc"))
                #else
                .modifier(BibleBarActionModifier(kind: .primary, help: "복사"))
                #endif
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
        // 복사가 실제로 클립보드에 쓰인 뒤에만 토스트를 띄우고 선택을 비운다 —
        // 복사할 내용이 없어 위 guard에서 반환되면 둘 다 하지 않는다.
        showToast("복사되었습니다.")
        viewModel.clearVerseSelection()
    }

    /// 컨텍스트 메뉴를 연 절 하나 + 그 메뉴가 속한 번역본 컬럼 하나만 복사한다.
    /// 절 선택 상태(`viewModel.selectedVerses`)는 건드리지 않는다.
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

    /// 컨텍스트 메뉴 [선택] — `VerseTextSelectionPopover`를 열 대상을 정한다.
    /// 실제 복사/토스트는 팝오버의 "복사" 버튼이 `copyRawText(_:)`로 처리한다.
    private func presentPartialTextSelection(
        _ verse: BibleVerse, _ translationDisplayName: String, hanjaWords: [HanjaWordAnnotation]
    ) {
        partialTextSelectionTarget = PartialTextSelectionTarget(
            verseNumber: verse.verse, translationDisplayName: translationDisplayName, text: verse.content,
            hanjaWords: hanjaWords
        )
    }

    /// 팝오버에서 드래그로 고른 문자열(없으면 절 전체)을 그대로 클립보드에 쓴다.
    /// 장:절 참조나 번역본 이름표를 붙이지 않으므로 `BibleVerseCopyFormatter`를 거치지 않는다.
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

    /// 선택 절의 기준 번역본 텍스트를 클립보드를 거치지 않고 `wordSummaryProxy`로 인스펙터 에디터의 커서 위치에 삽입한다.
    /// 말씀 요약이 기준 번역본 한 열만 쓰므로 `formattedBaseTranslationText`를 사용한다.
    private func copySelectedVersesIntoWordSummary() {
        guard !viewModel.selectedVerses.isEmpty,
              let text = viewModel.formattedBaseTranslationText(forVerses: viewModel.selectedVerses) else { return }
        wordSummaryProxy.insertTextAtCursor(text)
    }

    /// 선택된 절을 각각 "책 장:절 본문" `.verseQuote` 문단으로 만들어 새 설교를 시작한다.
    /// 절마다 독립된 문단이어야 해서(나중에 한 절만 서식 변경 가능) 절을 한 참조로 합칠 수 있는
    /// `BibleVerseCopyFormatter`는 쓰지 않는다. 기준 번역본(맨 왼쪽 열)만 사용한다.
    private func startSermonFromSelectedVerses() {
        guard !viewModel.selectedVerses.isEmpty, let firstColumn = viewModel.columns.first else { return }
        let sortedVerseNumbers = viewModel.selectedVerses.sorted()
        let versesByNumber = Dictionary(uniqueKeysWithValues: firstColumn.verses.map { ($0.verse, $0) })
        let selectedBibleVerses = sortedVerseNumbers.compactMap { versesByNumber[$0] }
        guard !selectedBibleVerses.isEmpty else { return }

        let bookName = viewModel.selectedBook.nameKo
        let chapter = viewModel.selectedChapter
        let paragraphTexts = selectedBibleVerses.map { verse in
            "\(bookName) \(chapter):\(verse.verse) \(verse.content)"
        }

        // 아이패드·맥은 새 창("sermon-new")으로 연다 — 선택한 절 본문/위치를 창에 실어 보내고 창이 같은 내용으로 새 설교를 만든다
        // (내 설교의 "새 설교"와 같은 창·같은 완료/취소 위치). 아이폰은 다중 씬을 지원하지 않아 아래 시트 경로를 그대로 쓴다.
        if !isPhone {
            let seeds = zip(selectedBibleVerses, paragraphTexts).map { verse, text in
                SermonNewTarget.VerseSeed(bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse, text: text)
            }
            openWindow(id: "sermon-new", value: SermonNewTarget(verseSeeds: seeds))
            viewModel.clearVerseSelection()
            return
        }
        let settings = UserSettingsStore.shared
        let (rtf, plain, styles) = SermonParagraphStyleCodec.buildVerseQuoteDocument(verseTexts: paragraphTexts, settings: settings)
        let sermon = Sermon(title: "", contentHtml: rtf, contentText: plain, paragraphStyles: styles)
        for (index, verse) in selectedBibleVerses.enumerated() {
            let reference = SermonVerseReference(
                bookId: verse.bookId, chapter: verse.chapter, verseStart: verse.verse, verseEnd: nil,
                paragraphIndex: index, sermon: sermon
            )
            modelContext.insert(reference)
        }
        pendingSermonFromVerses = sermon
        viewModel.clearVerseSelection()
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // `chapterNavigationControls`는 좁은 화면(아이패드 등)에서 통째로 사라지는 문제가 있어
        // 툴바 `.principal`이 아니라 `.safeAreaInset(edge: .top)`에 둔다.
        //
        // `.navigationTitle`은 시스템(윈도우 전환기/음성 제어 등)이 쓰므로 유지하고, `.principal` 아이템이
        // 보이는 타이틀을 시각적으로만 덮어쓴다. macOS는 타이틀 바 제목이 시스템 chrome이라 굵기를 바꿀 수 없고
        // 툴바에 또 띄우면 제목이 중복돼 보이므로 iOS에만 적용한다.
        #if os(iOS)
        ToolbarItem(placement: .principal) {
            // 타이틀 폰트는 국민대학교 성곡 세리프체(`SpecialPurposeFonts.titleSerif`, CC BY-ND — 설정 > 라이센스 탭 고지).
            // 아이폰은 좁은 `.principal` 영역에 번역본/책+장을 두 줄로 표시하며, 크기는
            // `BookChapterPicker.compactBarBody`가 쓰는 `.title3`(size 20)과 맞춘다.
            if isPhone {
                VStack(spacing: 0) {
                    Text(currentColumnTranslationDisplayName)
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(viewModel.selectedBook.nameKo) \(viewModel.selectedChapter)장")
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // 내비게이션 바 배경이 임의의 테마색일 수 있어 명시적 색이 없으면 대비를 잃을 수 있다.
                // `CircularNavButtonModifier`와 같은 폴백(`bibleTextColor ?? .primary`)을 쓴다.
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            } else {
                // 아이패드: 크기는 `DocumentsHomeView`/`WordNoteHomeView` 타이틀과 동일(size 20, `.title3` 배율).
                // 텍스트는 아이폰 두 번째 줄과 같은 "책 장" 조합이고, `.fontWeight(.semibold)`는 합성 볼드 보정이다.
                Text("\(viewModel.selectedBook.nameKo) \(viewModel.selectedChapter)장")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        #endif
        // 관련 콘텐츠/조회 이력은 주 창에서는 모든 플랫폼에 보이고 macOS 보조 창에서만 뺀다.
        // "성경 조회 새 창"은 macOS에서만 보인다(아이폰/아이패드는 별도 창 개념이 없거나 미지원).
        if isPrimaryWindow {
            // 트레일링 아이콘은 선언 순서가 화면의 좌우 순서와 일치한다(`trailingIconPlacement`):
            // 사이드바 열기(아이패드) → 책갈피 이동 → 책갈피 설정/해제 → 조회 이력 → 관련 콘텐츠.
            //
            // 사이드바 열기 버튼은 아이패드에서 왼쪽 사이드바가 닫혀 있을 때만 맨 앞에 둔다. 말씀 요약 편집 중에는
            // `SidebarVisibilityRequest`의 자동 복원 계약과 사이드바 값을 다투게 되므로 노출하지 않는다.
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
            // 책갈피 버튼 둘은 조회 이력/새 창/번역본 선택과 같은 이유로 말씀 요약 편집 중엔 감춘다(아이폰 제외 — `hidesToolbarIconsWhileEditingSummary`).
            if !hidesToolbarIconsWhileEditingSummary {
                ToolbarItem(placement: trailingIconPlacement) {
                    Button {
                        isBookmarkListPresented = true
                    } label: {
                        Label("책갈피 이동", systemImage: "list.star")
                    }
                    .help("책갈피로 이동")
                    // 와인 색 오버라이드는 아이폰에서만 적용하고, 맥/아이패드는 기존 액센트를 쓴다.
                    .tint(isPhone ? JBCHCategoryPalette.wine : nil)
                    .popover(isPresented: $isBookmarkListPresented) {
                        BookmarkListPopover(viewModel: viewModel) {
                            isBookmarkListPresented = false
                        }
                    }
                }
                ToolbarItem(placement: trailingIconPlacement) {
                    Button {
                        // 대상 번역본(`bookmarkTargetTranslationCode`)이 없으면(`emptyState`) 아무것도 하지 않는다.
                        // 아래 `.disabled`가 이 경우 버튼을 비활성화한다.
                        guard let code = bookmarkTargetTranslationCode else { return }
                        viewModel.toggleBookmarkForCurrentPosition(translationCode: code)
                    } label: {
                        if let code = bookmarkTargetTranslationCode, viewModel.isCurrentPositionBookmarked(translationCode: code) {
                            Label("책갈피 해제", systemImage: "bookmark.fill")
                        } else {
                            Label("책갈피 설정", systemImage: "bookmark")
                        }
                    }
                    // 책갈피 아이콘은 SF Symbol(`bookmark`/`bookmark.fill`)을 쓰고, 색은 아래 `.tint` 하나로만 준다.
                    .disabled(bookmarkTargetTranslationCode == nil)
                    .help(bookmarkTargetTranslationCode.map { viewModel.isCurrentPositionBookmarked(translationCode: $0) ? "이 위치 책갈피 해제" : "이 위치 책갈피로 설정" } ?? "이 위치 책갈피로 설정")
                    // 와인 색은 플랫폼과 무관하게 항상 적용한다(위 "책갈피 이동" 버튼의 `.tint`는 아이폰에서만 적용).
                    .tint(JBCHCategoryPalette.wine)
                }
            }
            // 조회 이력 진입점. 말씀 요약 편집 중에는 조회 이력/새 창/번역본 선택 버튼을 숨긴다(편집 방해 방지, 아이폰 제외).
            if !hidesToolbarIconsWhileEditingSummary {
                ToolbarItem(placement: trailingIconPlacement) {
                    Button {
                        isHistoryPresented = true
                    } label: {
                        Label("조회 이력", systemImage: "clock")
                    }
                    .help("최근 조회한 책/장 이력 보기")
                    .popover(isPresented: $isHistoryPresented) {
                        BibleReadingHistorySheet(viewModel: viewModel) {
                            isHistoryPresented = false
                        }
                    }
                }
            }
            // 관련 콘텐츠 패널(개요/메모/연구문서) 토글. 항상 활성화한다.
            ToolbarItem(placement: trailingIconPlacement) {
                // 말씀 요약 편집기가 이 자리를 빌려 쓰는 동안에는 `isRelatedContentPresented`를 토글해도
                // 인스펙터가 계속 열려 있으므로(`.inspector`의 `get`이 `wordSummaryBeingEdited`도 봄),
                // 같은 버튼이 "닫기"(뒷정리 포함)로 동작한다.
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
        // "성경 조회 새 창" 진입점(macOS 전용, 메뉴 AppCommands.swift와 같은 동작).
        // 아이폰은 멀티 씬을 지원하지 않아 누르면 크래시하므로 아이패드와 함께 뺀다.
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
        // 활성 번역본이 둘 이상이면 창마다 1~`maxColumns`개를 고를 수 있게 보인다(`BibleToolRail.showTranslationPicker`와 같은 규칙).
        if viewModel.availableTranslations.count > 1 && !hidesToolbarIconsWhileEditingSummary {
            ToolbarItem(placement: trailingIconPlacement) {
                Button {
                    isTranslationPickerPresented = true
                } label: {
                    Label("번역본 선택", systemImage: "text.book.closed")
                }
                // 번역본 아이콘은 아이폰에서만 가죽 표지색(`JBCHCategoryPalette.wood`)으로 칠한다.
                .tint(isPhone ? JBCHCategoryPalette.wood : nil)
                .popover(isPresented: $isTranslationPickerPresented) {
                    TranslationPickerPopover(
                        available: viewModel.availableTranslations,
                        selected: viewModel.columns.map(\.registry.persistentModelID),
                        maxSelection: viewModel.maxColumns
                    ) { selected in
                        // `TranslationPickerPopover.selectedIDs`가 선택 순서를 보존하는 배열이라 `Set` 변환 없이 그대로 넘긴다.
                        viewModel.setDisplayedTranslations(selected)
                        isTranslationPickerPresented = false
                    }
                }
            }
        }
    }
    #endif

    /// iOS(아이폰/아이패드)는 `ViewThatFits`로 표준 막대 → 캡슐 막대 순서로 고르고, macOS는 `chapterNavigationControlsStandard`를 쓴다.
    @ViewBuilder
    private var chapterNavigationControls: some View {
        #if os(iOS)
        // 아이패드·아이폰 공통(2026-10-02): 맥OS와 같은 막대(묶음 2개 + 책 버튼 + 검색창 + 이동, 터치용 40pt)를 쓰고,
        // 폭이 모자라 한 줄에 다 안 들어가면(아이폰 세로, 아이패드 분할 보기) 캡슐 막대(`compactChapterNavigationBar`)로 대신한다.
        // 표준 막대는 약 534pt가 필요해 아이폰 가로(약 700pt)에서는 표준, 세로(358pt)에서는 캡슐이 선택된다.
        // 캡슐 막대의 자연 폭은 최대 약 344pt(버튼 6×40 + 구분선 6 + 검색 칸 최대 90 + 좌우 4×2)라 358pt 안에 들어간다.
        ViewThatFits(in: .horizontal) {
            chapterNavigationControlsStandard
            compactChapterNavigationBar
        }
        #else
        chapterNavigationControlsStandard
        #endif
    }

    /// 상단 이동 막대 크기 — 맥은 포인터용 32pt, 아이패드는 터치용 40pt.
    private var barSizing: BibleBarSizing {
        #if os(macOS)
        return .regular
        #else
        return .touch
        #endif
    }

    /// 원형 장 이동 버튼. frame/background를 라벨 안쪽에서 입힌 뒤 Button으로 감싸고,
    /// `.buttonStyle(.plain)` + `.contentShape`를 Button 바깥에 붙인다. 바깥에서 씌우는 방식
    /// (`CircularNavButtonModifier`)은 macOS에서 원형 배경을 눌러도 반응하지 않았다(`.plain` 스타일이
    /// 바깥에서 씌운 frame/contentShape를 클릭 판정에 반영하지 못하는 것으로 보인다).
    @ViewBuilder
    private func circularChapterNavButton(
        systemImage: String, help: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        if isCompactChapterNavButtons {
            Button(action: action) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: CircularNavButtonModifier.diameter, height: CircularNavButtonModifier.diameter)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .disabled(disabled)
            .help(help)
        } else {
            // `isCompactChapterNavButtons`가 조건부로 바뀌어도 옛 `CircularNavButtonModifier`의
            // "off일 땐 아무것도 안 함" 동작을 보존한다(현재는 항상 true).
            Button(action: action) {
                Image(systemName: systemImage)
            }
            .disabled(disabled)
            .help(help)
        }
    }

    private var chapterNavigationControlsStandard: some View {
        // 2026-10-02: 맥OS 상단 막대를 `BibleBarControls.swift` 규격(높이 32pt, 모서리 8pt, 글자색 10% 배경 + 24% 테두리)으로 통일.
        // 이전 쪽(히스토리 이전·이전 장)과 다음 쪽(다음 장·히스토리 이후)을 각각 한 묶음으로 두어 좌우 대칭으로 보이게 한다.
        // 이전/다음 장(`chevron`)은 항상 ±1장 이동이고, 히스토리 버튼(`arrow.uturn.*`)은 임의의 이전 위치로 되짚어간다.
        // 각 버튼은 갈 곳이 없으면(`canGo…`/첫·마지막 장) 비활성화된다.
        HStack(spacing: 10) {
            BibleBarSegmentGroup {
                barIconButton(
                    systemImage: "arrow.uturn.backward",
                    help: "이전에 보던 위치로 돌아가기",
                    disabled: !viewModel.canGoBackInHistory,
                    action: { viewModel.goBackInHistory() }
                )
                BibleBarSegmentDivider()
                barIconButton(
                    systemImage: "chevron.left",
                    help: "이전 장",
                    disabled: viewModel.selectedChapter <= 1 && BooksProvider.shared.book(before: viewModel.selectedBook) == nil,
                    action: { viewModel.previousChapter() }
                )
            }

            BookChapterPicker(
                books: BooksProvider.shared.books,
                selectedBook: viewModel.selectedBook,
                selectedChapter: viewModel.selectedChapter,
                // 장 이동 후 절을 임시 하이라이트한다(`jumpToCrossReferenceTarget`과 같은 두 단계).
                onSelectVerse: { book, chapter, verse in
                    viewModel.selectBook(book, chapter: chapter)
                    viewModel.highlightVerseTemporarily(verse)
                },
                unifiedBarStyle: true
            ) { book, chapter in
                viewModel.selectBook(book, chapter: chapter)
            }

            BibleBarSegmentGroup {
                barIconButton(
                    systemImage: "chevron.right",
                    help: "다음 장",
                    disabled: viewModel.selectedChapter >= viewModel.selectedBook.chapterCount
                        && BooksProvider.shared.book(after: viewModel.selectedBook) == nil,
                    action: { viewModel.nextChapter() }
                )
                BibleBarSegmentDivider()
                // 히스토리 앞으로 가기 — 위 뒤로가기 버튼과 대칭.
                barIconButton(
                    systemImage: "arrow.uturn.forward",
                    help: "뒤로가기 이전 위치로 다시 가기",
                    disabled: !viewModel.canGoForwardInHistory,
                    action: { viewModel.goForwardInHistory() }
                )
            }
        }
        .environment(\.bibleBarSizing, barSizing)
        // 툴바 principal 대신 상단 세이프에어리어 인셋(전체 너비)에 놓이므로 가운데 정렬을 유지하려고 필요하다.
        .frame(maxWidth: .infinity)
    }

    /// 상단 막대의 아이콘 버튼 한 칸(`BibleBarSegmentGroup` 안에서 쓴다). 스타일(32×32, 올림/눌림 색)은 묶음이 입힌다.
    private func barIconButton(
        systemImage: String, help: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: barSizing.iconSize, weight: .semibold))
        }
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }

    #if os(iOS)
    /// iOS 장 이동 막대: 히스토리 이전·이전장·`BookChapterPicker`(현재장/검색/이동)·다음장·히스토리 다음을
    /// 하나의 캡슐 배경에 담는다. 각 버튼은 `JoinedNavBadgeModifier`(40×44 탭 영역 안의 34pt 원 배지)로 통일한다.
    private var compactChapterNavigationBar: some View {
        // 2026-10-02: 원 배지를 없애고 캡슐(글자색 10% 채움 + 24% 테두리) 안에 글자색 아이콘을 두며, 모든 버튼 사이에 구분선을 넣었다
        // (`BibleBarControls.swift`의 `BibleCapsule*`). 탭 영역 40×44는 그대로라 폭 예산은 이전보다 오히려 줄었다.
        HStack(spacing: 0) {
            Button {
                viewModel.goBackInHistory()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canGoBackInHistory)
            .buttonStyle(BibleCapsuleItemStyle())
            .accessibilityLabel("이전에 보던 위치로 돌아가기")

            BibleCapsuleDivider()

            Button {
                viewModel.previousChapter()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.selectedChapter <= 1 && BooksProvider.shared.book(before: viewModel.selectedBook) == nil)
            .buttonStyle(BibleCapsuleItemStyle())
            .accessibilityLabel("이전 장")

            BibleCapsuleDivider()

            BookChapterPicker(
                books: BooksProvider.shared.books,
                selectedBook: viewModel.selectedBook,
                selectedChapter: viewModel.selectedChapter,
                onSelectVerse: { book, chapter, verse in
                    viewModel.selectBook(book, chapter: chapter)
                    viewModel.highlightVerseTemporarily(verse)
                },
                compactTouchTargets: true
            ) { book, chapter in
                viewModel.selectBook(book, chapter: chapter)
            }

            BibleCapsuleDivider()

            Button {
                viewModel.nextChapter()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(
                viewModel.selectedChapter >= viewModel.selectedBook.chapterCount
                    && BooksProvider.shared.book(after: viewModel.selectedBook) == nil
            )
            .buttonStyle(BibleCapsuleItemStyle())
            .accessibilityLabel("다음 장")

            BibleCapsuleDivider()

            Button {
                viewModel.goForwardInHistory()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.canGoForwardInHistory)
            .buttonStyle(BibleCapsuleItemStyle())
            .accessibilityLabel("뒤로가기 이전 위치로 다시 가기")
        }
        .padding(.horizontal, 4)
        .frame(height: 44)
        .modifier(BibleCapsuleChrome())
        .frame(maxWidth: .infinity)
    }
    #endif
}
