//
//  PhoneTabView.swift
//  JBCHBibleResearch
//
//  screens.md 1장 IA — iPhone 전용 탭바. 원래 5개 탭: 메모/성경/문서·OCR/개요/더보기.
//  순서는 원문서 그대로(메모가 먼저, 성경이 두 번째)를 따랐다 — macOS 사이드바 순서
//  (성경 조회가 첫 항목, AppSection.allCases 순서)와 다른 것은 원문서 1장 IA 자체가
//  iPhone 탭 순서를 그렇게 명시했기 때문이다.
//
//  [2026-08-27, 사용자 결정 — "개요→더보기, 검색→탭바"] `SearchView.swift` 상단
//  주석 참고 — "통합 검색"이 "더보기" 서브메뉴에 중첩된 `NavigationStack` 안에서
//  `.searchable`이 활성 상태인 채로 그 자리에서 성경구절로 바로 push하는 구조는
//  세 차례의 실기기 콘솔 로그로 근본적으로 못 고치는 구조적 결함임이 확인됐다.
//  그래서 "통합 검색"을 이 탭바의 정식 탭으로 승격하고(자기 자신의 독립된
//  `NavigationStack`을 가지므로 그 문제 자체가 성립하지 않는다), 원래 탭이었던
//  "개요"는 대신 "더보기" 메뉴 안 전체화면 모달로 옮겼다.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// [2026-09-09 신설] 사용자 보고 — "성경 하단 기능메뉴(말씀노트, 성경,
/// 문서/OCR, 통합검색, 더보기) 배경도 왜 흰색이지?" 이 탭바는 `TabView`의
/// 진짜 iOS 시스템 탭바(`.tabItem`)라 지난 "테마 확장" 작업이 손댄
/// `BibleReadingView`의 `verseSelectionActionBar`(절 선택 시에만 뜨는 별개의
/// 커스텀 바)와는 완전히 다른 층이다 — 그래서 그 작업에서 빠졌다.
///
/// ⚠️ [3차 시도, 사용자 실기기 확인 후 방식 교체] 처음 두 번은 SwiftUI
/// `.toolbarBackground(_:for: .tabBar)`만 썼다 — 1차: `TabView` 전체에 한
/// 번, 2차: 5개 탭 각각의 `NavigationStack`에 개별로. 사용자가 재빌드·재실행
/// 후에도 "그대로임(흰색)"이라고 확인해줬다. Apple 개발자 포럼 여러
/// 스레드(`developer.apple.com/forums/thread/796052`,
/// `.../thread/798031` 등)가 iOS 26의 새 "Liquid Glass" 탭바에서 이
/// SwiftUI API 자체가 아직 불안정/제한적이라고 보고하는 것과 일치한다 —
/// 그래서 SwiftUI 래퍼 대신, 탭바를 실제로 그리는 더 오래되고 저수준인
/// UIKit `UITabBarAppearance`를 `UITabBar.appearance()`(전역 외형 프록시)에
/// 직접 설정하는 방식으로 바꿨다(아래 `applyThemedTabBarAppearance`). 사용자
/// 확인 후 적용한 시도이며, 같은 포럼 스레드들이 Liquid Glass에서는
/// `configureWithOpaqueBackground()`/`backgroundColor`조차 "유리" 모양
/// 자체를 깨뜨리거나 반영이 불명확한 사례를 함께 보고하고 있어 이번에도
/// 100% 보장되지는 않는다는 점을 사용자에게 그대로 고지했다.
///
/// ⚠️ [알려진 한계] `UITabBar.appearance()`는 UIKit의 "외형 프록시"라 이미
/// 화면에 떠 있는 탭바 인스턴스에는 소급 적용되지 않는 것이 일반적인
/// 동작이다 — 탭바가 "새로 만들어지는 시점"(앱을 새로 띄울 때)엔 반영되지만,
/// 앱이 이미 떠 있는 채로 설정에서 테마를 바꾸면 반영이 늦거나 안 될 수
/// 있다. 아래 `.onChange(of: settings.bibleBackgroundColor)`가 그 경우에도
/// 다시 호출은 하지만, 실제로 이미 떠 있는 탭바에 반영되는지는 검증하지
/// 못했다 — 이번에 사용자가 보고한 증상("재빌드·재실행 후에도 흰색")은
/// "새로 띄울 때" 경우라 이 한계와는 무관하다.
#if os(iOS)
/// [2026-09-09 4차 시도] `private`를 뺐다 — 사용자 실기기 확인 결과 이 함수를
/// `PhoneTabView.onAppear`에서 불러도 탭바가 여전히 흰색이었다. 원인으로
/// 가장 유력한 것은 `UITabBar.appearance()`가 UIKit "외형 프록시"라는 점 —
/// 이 프록시는 대상 뷰가 "윈도우에 처음 추가되는 시점"에 한 번 적용되는
/// 것이 원칙이고, SwiftUI의 `.onAppear`는 그 뷰가 이미 화면 계층에 들어간
/// "이후"에 불린다(공식 문서로 못 박혀 있진 않지만, UIAppearance의
/// 전형적으로 알려진 동작이다). 즉 `.onAppear` 시점엔 이미 늦었을 수
/// 있다 — 그래서 `JBCHBibleResearchApp.init()`(윈도우/탭바가 만들어지기
/// 전, `BundledFontRegistrar.registerBundledFontsIfNeeded()`와 같은 자리)
/// 에서도 이 함수를 먼저 호출하도록 옮긴다. `PhoneTabView`의 `.onAppear`/
/// `.onChange`는 그대로 남겨 둔다(해가 되지 않고, 테마를 나중에 바꿨을 때
/// 다시 시도라도 해보는 편이 아예 안 하는 것보다 낫다).
func applyThemedTabBarAppearance(color: Color?) {
    let appearance = UITabBarAppearance()
    if let color {
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(color)
    } else {
        appearance.configureWithDefaultBackground()
    }
    // [2026-09-11 추가] 사용자 재검토 요청 — "테마색상 팔레트 6개가 실제로는
    // 2~3톤처럼 보인다." 탭 전환마다 항상 보이는 이 자리에 서고 청람
    // (JBCHCategoryPalette.slateTeal)을 선택 아이콘·글자색으로 명시
    // 배정한다 — 이 세션 맨 처음 색상 논의에서 사용자가 직접 예로 들었던
    // 배치와 일치하고, 지금까지 실제로 코드 어디에서도 쓰인 적 없던 색이라
    // 미사용 문제도 함께 해결한다.
    //
    // ⚠️ [대비 계산 확인] 배경이 명시적으로 어두운 값(예: "밤빛 서재"
    // #182644)일 때 원래 서고 청람을 그대로 쓰면 WCAG 대비 2.66:1로
    // UI 구성요소 권장 최소치(3:1)에 못 미친다 — 그때만 밝게 섞은 변형
    // (slateTealOnDark, 대비 4.09:1)을 쓴다. `color`가 nil(시스템 기본)일
    // 때는 시스템이 그리는 반투명 배경이 다크 모드에서도 거의 검정에
    // 가까워(대비 약 3.5~3.7:1로 계산 확인) 원래 색으로 충분하다고 보고
    // 이 분기 대상에서 뺐다.
    let isExplicitDarkBackground: Bool = {
        guard let color else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.5
    }()
    let selectedTint = UIColor(isExplicitDarkBackground ? JBCHCategoryPalette.slateTealOnDark : JBCHCategoryPalette.slateTeal)
    for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
        layout.selected.iconColor = selectedTint
        layout.selected.titleTextAttributes = [.foregroundColor: selectedTint]
    }
    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
}
#endif

struct PhoneTabView: View {
    /// [2026-09-09 추가] `BibleReadingView.BibleReadingContentView`/
    /// `WordNoteHomeView`/`SearchView`와 같은 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }

    /// [2026-08-08 추가, 크래시 수정으로 방식 변경] S1의 "관련 콘텐츠" 패널에서
    /// "개요 화면 열기"를 누르면 이 탭뷰가 개요 탭으로 전환돼야 한다. 처음엔
    /// `@FocusedValue(\.selectSection)`(SidebarNavigationView가 macOS/iPadOS에서
    /// 쓰던 것과 같은 메커니즘)로 이 탭뷰가 값을 "게시"하게 했는데, 그 값을
    /// 읽는 쪽(BibleReadingContentView, 자체 `.toolbar`를 가진 뷰)에서 실기기
    /// 크래시가 나 `AppNavigationRequest`(평범한 `Equatable` 값 기반)로 바꿨다 —
    /// 자세한 이유는 `Services/AppNavigationRequest.swift` 상단 주석 참고.
    ///
    /// [2026-09-03 변경, `@State` → `@SceneStorage`] 사용자 보고 — "더보기 > 설정
    /// > 성경 > 모양의 화면모드를 바꾸면 자동으로 성경으로 이동한다." 재확인
    /// 결과 여전히 재현됨: 화면 모드를 바꾸면 정확히 이 프로퍼티의 선언 기본값
    /// (`.bibleReading`, "성경" 탭)으로 되돌아간다 — 다른 값이 아니라 "정확히
    /// 이 기본값"이라는 점이, `TabView`를 감싼 `PhoneTabView` 구조체 자체가
    /// (정확한 트리거는 아직 못 밝혔다 — `.preferredColorScheme`가 iOS에서
    /// `TabView`의 UIKit 구현(`UITabBarController`)에 트레이트 컬렉션 변경을
    /// 전파하는 방식과 관련된 것으로 보인다) 통째로 다시 만들어지며 `@State`가
    /// 초기화되고 있다는 뜻이다. 근본 원인(왜 다시 만들어지는지)을 확실히
    /// 잡기 전이라도, `@State`를 이 뷰 인스턴스가 살아있는 동안만 유지되는
    /// 저장소가 아니라 "같은 Scene(창) 안에서는 뷰가 다시 만들어져도 값이
    /// 살아남는" `@SceneStorage`로 바꾸면 — 뷰가 다시 만들어지는 근본 원인과
    /// 무관하게 — 마지막으로 선택돼 있던 탭이 그대로 복원된다(Apple 공식 문서가
    /// `@SceneStorage`를 권장하는 바로 그 용도 — 시스템이 뷰를 다시 만드는
    /// 상황에서도 UI 상태를 보존). `AppSection`이 이미 `String` raw value를
    /// 가진 `RawRepresentable`이라 `@SceneStorage`가 바로 지원한다.
    ///
    /// ⚠️ [남은 한계, 사용자에게 고지] 이 수정은 "어느 탭에 있었는지"만
    /// 복원한다 — "더보기" 탭 안에서 설정 > 성경 > 모양까지 눌러 들어간
    /// 세부 위치(`NavigationStack` 푸시 경로)까지 복원하지는 못한다(그 경로는
    /// `MorePlaceholderView`를 감싼 `NavigationStack`이 값 없는 단순한
    /// `NavigationStack { ... }`라 애초에 외부에 저장할 대상이 없다 — 이 뷰
    /// 자체가 다시 만들어지면 그 안의 `NavigationStack`도 함께 다시 만들어져
    /// 푸시 기록이 비워진다). 그 경로까지 보존하려면 내비게이션을 값 기반
    /// (`NavigationPath`/`.navigationDestination(for:)`)으로 바꾸고 그 경로 자체를
    /// 별도로 영속화해야 하는, 이 파일 하나를 넘어서는 더 큰 구조 변경이 필요해
    /// 이번 수정 범위에 넣지 않았다 — 필요하시면 별도로 진행하겠다.
    @SceneStorage("PhoneTabView.selectedTab") private var selectedTab: AppSection = .bibleReading

    /// [2026-08-27 신설, 사용자 결정 — "개요→더보기, 검색→탭바"] 개요
    /// (`OutlineTreeView`)를 탭바에서 빼고 "더보기" 메뉴 안 전체화면 모달로
    /// 옮기면서, 성경 조회 화면의 "관련 콘텐츠 > 개요 화면 열기"
    /// (`AppNavigationRequest.shared.request(.outline)`)가 더 이상 탭 전환만으로는
    /// 개요 화면을 보여줄 수 없게 됐다. 그 요청을 받으면 아래 `.onChange`가 이
    /// 값을 true로 바꿔 전체화면 모달을 연다.
    ///
    /// 이 상태를 "더보기" 탭의 내용(`MorePlaceholderView`) 안에 로컬로 두지
    /// 않고 여기(`PhoneTabView`)에 두는 이유 — SwiftUI `TabView`는 선택되지
    /// 않은 탭의 화면 계층도 메모리에는 유지하지만, 그 계층 안에서 연 모달은
    /// 그 탭이 실제로 화면에 보여지기 전까지는 나타나지 않는다. "개요 화면
    /// 열기"는 사용자가 "성경" 탭 등 다른 탭을 보고 있을 때도 호출될 수 있으므로,
    /// 이 값과 아래 `.fullScreenCover`를 `TabView` 자체의 최상위(어느 탭이
    /// 선택돼 있든 항상 화면에 존재하는 계층)에 붙여 둔다.
    @State private var isOutlinePresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // [2026-08-13 변경] 사용자 요청 — "왼쪽 사이드바 [개인 묵상], [말씀
            // 요약] 통합할 것 : 메뉴명 - [말씀 노트]." 이전엔 "메모"/"말씀 요약"
            // 두 탭이었다 — `WordNoteHomeView`(목록+NavigationLink push 편집기)
            // 하나로 합쳤다.
            NavigationStack { WordNoteHomeView() }
                .tabItem { Label("말씀 노트", systemImage: "note.text") }
                .tag(AppSection.wordNote)

            NavigationStack { BibleReadingView() }
                .tabItem { Label("성경", systemImage: "book") }
                .tag(AppSection.bibleReading)

            NavigationStack { DocumentsHomeView() }
                .tabItem { Label("연구문서", systemImage: "doc.text.viewfinder") }
                .tag(AppSection.documents)

            // [2026-08-27 변경, 사용자 결정 — "개요→더보기, 검색→탭바"] 예전엔
            // 여기가 개요(`OutlineTreeView`) 탭이었다(장 칩이 자기 자신의
            // `NavigationStack(path:)`에 직접 append하는 방식 — `OutlineTreeView.swift`
            // 상단 주석 참고, 그 구조 자체는 이번 변경과 무관해 그대로 둔다).
            // 통합 검색을 이 탭바의 정식 탭으로 승격하면서 자리를 맞바꿨다 —
            // 검색이 "더보기" 서브메뉴에 중첩돼 있으면 검색이 "활성" 상태인
            // 채로 그 자리에서 성경구절로 push하는 조합이 구조적으로 깨진다는
            // 걸 여러 차례 실기기 로그로 확인했다(`SearchView.swift` 상단 주석
            // 참고) — 이 탭은 그 자신만의 독립된 `NavigationStack`이라 그
            // 문제 자체가 성립하지 않는다. 개요는 "더보기" 메뉴 안 전체화면
            // 모달로 옮겼다(`PlaceholderScreens.swift` 참고).
            NavigationStack { SearchView() }
                .tabItem { Label("통합 검색", systemImage: "magnifyingglass") }
                .tag(AppSection.search)

            NavigationStack { MorePlaceholderView(isOutlinePresented: $isOutlinePresented) }
                .tabItem { Label("더보기", systemImage: "ellipsis.circle") }
        }
        // [2026-09-11 이동, 사용자 보고 — "테마색상을 바꾸면 성경의 상단
        // 메뉴가 사라짐"] 이 자리에 있던 `.onAppear`/`.onChange(of: settings.
        // bibleBackgroundColor)`(탭바 UIKit 외형 재적용)를 `ContentView.swift`로
        // 옮겼다 — 여기(`PhoneTabView.body`)는 바로 위에서 `TabView`를 직접
        // 구성하는 자리라, 여기서 `settings.bibleBackgroundColor`(관찰
        // 프로퍼티)를 읽으면 그 값이 바뀔 때마다 이 body 전체가 다시 실행되며
        // `TabView`가 통째로 다시 만들어질 위험이 있다 — `@SceneStorage`로
        // 바꿔 고쳤던 위 `selectedTab` 관련 주석, 그리고 `ContentView.swift`가
        // `colorSchemePreference`에 대해 이미 겪고 고친 것(Apple Developer
        // Forums 스레드 726363)과 같은 계열의 문제다. `applyThemedTabBarAppearance`
        // 함수 자체(바로 위 선언)는 `ContentView.swift`에서도 그대로 불러
        // 쓰므로 여기 남겨 둔다.
        // [2026-08-27 변경, 사용자 결정 — "개요→더보기, 검색→탭바"] `.outline`은
        // 더 이상 탭바 항목이 아니므로(`AppSection.phoneTabBarSections`에서
        // 뺐다) 이 값이 오면 탭 전환 대신 전체화면 모달을 연다 — "관련 콘텐츠 >
        // 개요 화면 열기" 기능 자체는 그대로 유지하되, 보여주는 방식만 바뀐다.
        .onChange(of: AppNavigationRequest.shared.requestedSection) { _, newValue in
            guard let newValue else { return }
            if newValue == .outline {
                isOutlinePresented = true
                AppNavigationRequest.shared.clear()
            } else if AppSection.phoneTabBarSections.contains(newValue) {
                selectedTab = newValue
                AppNavigationRequest.shared.clear()
            }
        }
        // ⚠️ 2026-08-06 Xcode 빌드 오류로 이미 한 번 확인된 것과 같은 문제
        // (`PlaceholderScreens.swift`의 `isTagRelationsPresented` `.fullScreenCover`
        // 상단 주석 참고): `fullScreenCover`는 iOS/iPadOS 전용이라 macOS에는
        // 심볼 자체가 없다(`'fullScreenCover(isPresented:onDismiss:content:)'
        // is unavailable in macOS`). `PhoneTabView`는 실제로 아이폰에서만
        // 쓰이지만(`RootView.swift` 참고) 멀티플랫폼 단일 타겟이라 macOS
        // 빌드에서도 이 파일 전체가 컴파일되므로 여기도 `#if os(iOS)`로
        // 감싼다 — macOS 쪽은 이 뷰 자체가 쓰이지 않으니 대체 없이 비워 둔다.
        #if os(iOS)
        .fullScreenCover(isPresented: $isOutlinePresented) {
            OutlineTreeView(onRequestDismiss: { isOutlinePresented = false })
        }
        #endif
    }
}
