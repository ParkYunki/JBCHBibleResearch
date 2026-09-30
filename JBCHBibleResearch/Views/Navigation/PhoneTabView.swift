//
//  PhoneTabView.swift
//  JBCHBibleResearch
//
//  iPhone 전용 탭바: 말씀 노트 / 성경 / 연구 문서 / 통합 검색 / 더보기.
//  macOS 사이드바 순서(성경 조회가 첫 항목)와 달리 iPhone 탭 순서는 별도로 정해져 있다.
//
//  통합 검색은 자기 독립 `NavigationStack`을 가진 정식 탭이다. "더보기" 서브메뉴에
//  중첩하면 `.searchable`이 활성인 채로 성경구절로 push하는 구조가 깨지기 때문이다
//  (`SearchView.swift` 참고). 개요는 대신 "더보기" 안 전체화면 모달로 연다.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 탭바 배경/선택색을 앱 테마에 맞춘다. 시스템 탭바(`.tabItem`)는 SwiftUI
/// `.toolbarBackground(_:for: .tabBar)`만으로는 iOS 26 Liquid Glass 탭바에 반영되지 않아,
/// UIKit `UITabBarAppearance`를 `UITabBar.appearance()`에 직접 설정한다.
///
/// ⚠️ `UITabBar.appearance()`는 외형 프록시라 이미 화면에 떠 있는 탭바에는 소급 적용되지
/// 않는 것이 일반적이다. 앱을 새로 띄울 때는 반영되지만, 실행 중 테마를 바꾸면 반영이
/// 늦거나 안 될 수 있다. Liquid Glass에서는 `configureWithOpaqueBackground()`/
/// `backgroundColor`도 결과가 불명확하다.
#if os(iOS)
/// 외형 프록시는 대상 뷰가 윈도우에 처음 추가되는 시점에 적용되는데 `.onAppear`는 그보다 늦을
/// 수 있으므로, `JBCHBibleResearchApp.init()`(윈도우/탭바 생성 전)에서도 먼저 호출한다.
/// `PhoneTabView`가 아닌 앱 진입점에서 부르기 때문에 `private`이 아니다.
func applyThemedTabBarAppearance(color: Color?) {
    let appearance = UITabBarAppearance()
    if let color {
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(color)
    } else {
        appearance.configureWithDefaultBackground()
    }
    // 선택 아이콘·글자색에 청람(JBCHCategoryPalette.slateTeal)을 배정한다.
    // 배경이 명시적으로 어두운 값이면 원래 청람은 WCAG 대비가 2.66:1로 UI 구성요소
    // 권장 최소치(3:1)에 못 미치므로 밝게 섞은 변형(slateTealOnDark, 4.09:1)을 쓴다.
    // `color`가 nil(시스템 기본)이면 반투명 배경이 다크 모드에서도 거의 검정에 가까워
    // (대비 약 3.5~3.7:1) 원래 색으로 충분하다.
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
    /// 다른 화면들과 같은 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }

    /// 선택된 탭. "개요 화면 열기" 요청은 `@FocusedValue(\.selectSection)` 대신
    /// `AppNavigationRequest`로 받는다(`@FocusedValue`를 읽는 쪽에서 실기기 크래시가 났다 —
    /// `Services/AppNavigationRequest.swift` 참고).
    ///
    /// `@State`가 아니라 `@SceneStorage`인 이유: 화면 모드 변경 등으로 이 구조체가 통째로
    /// 다시 만들어지면 `@State`는 기본값(`.bibleReading`)으로 초기화된다. `@SceneStorage`는
    /// 같은 Scene 안에서 뷰가 다시 만들어져도 값이 유지되어 마지막 탭이 복원된다.
    /// `AppSection`이 `String` raw value를 가져 바로 지원된다.
    ///
    /// ⚠️ 한계: 복원되는 것은 탭뿐이다. "더보기" 안에서 푸시한 `NavigationStack` 경로는
    /// 값 없는 단순 `NavigationStack { ... }`이라 뷰가 다시 만들어지면 비워진다. 경로까지
    /// 보존하려면 내비게이션을 값 기반(`NavigationPath`)으로 바꾸고 별도로 영속화해야 한다.
    @SceneStorage("PhoneTabView.selectedTab") private var selectedTab: AppSection = .bibleReading

    /// 개요(`OutlineTreeView`) 전체화면 모달 표시 여부. "더보기" 화면 안에 로컬로 두지 않고
    /// 여기에 두는 이유: "개요 화면 열기"는 다른 탭을 보고 있을 때도 호출되는데, 선택되지 않은
    /// 탭 계층 안의 모달은 그 탭이 보이기 전까지 나타나지 않는다. 그래서 이 값과 아래
    /// `.fullScreenCover`를 항상 존재하는 `TabView` 최상위에 붙인다.
    @State private var isOutlinePresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { WordNoteHomeView() }
                .tabItem { Label("말씀 노트", systemImage: "note.text") }
                .tag(AppSection.wordNote)

            NavigationStack { BibleReadingView() }
                .tabItem { Label("성경", systemImage: "book") }
                .tag(AppSection.bibleReading)

            NavigationStack { DocumentsHomeView() }
                .tabItem { Label("연구 문서", systemImage: "doc.text.viewfinder") }
                .tag(AppSection.documents)

            NavigationStack { SearchView() }
                .tabItem { Label("통합 검색", systemImage: "magnifyingglass") }
                .tag(AppSection.search)

            NavigationStack { MorePlaceholderView(isOutlinePresented: $isOutlinePresented) }
                .tabItem { Label("더보기", systemImage: "ellipsis.circle") }
        }
        // 탭바 외형 재적용(`applyThemedTabBarAppearance`)의 `.onAppear`/`.onChange`는 여기서
        // `settings.bibleBackgroundColor`를 읽으면 값이 바뀔 때마다 이 body가 다시 실행되어
        // `TabView`가 통째로 재생성될 위험이 있어 `ContentView.swift`에 둔다.
        // `.outline`은 탭바 항목이 아니므로(`AppSection.phoneTabBarSections`) 탭 전환 대신
        // 전체화면 모달을 연다.
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
        // `fullScreenCover`는 iOS/iPadOS 전용이라 macOS에는 심볼이 없다. 멀티플랫폼 단일
        // 타겟이라 macOS 빌드도 이 파일을 컴파일하므로 `#if os(iOS)`로 감싼다.
        #if os(iOS)
        .fullScreenCover(isPresented: $isOutlinePresented) {
            OutlineTreeView(onRequestDismiss: { isOutlinePresented = false })
        }
        #endif
    }
}
