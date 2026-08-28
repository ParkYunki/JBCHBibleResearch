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

struct PhoneTabView: View {
    /// [2026-08-08 추가, 크래시 수정으로 방식 변경] S1의 "관련 콘텐츠" 패널에서
    /// "개요 화면 열기"를 누르면 이 탭뷰가 개요 탭으로 전환돼야 한다. 처음엔
    /// `@FocusedValue(\.selectSection)`(SidebarNavigationView가 macOS/iPadOS에서
    /// 쓰던 것과 같은 메커니즘)로 이 탭뷰가 값을 "게시"하게 했는데, 그 값을
    /// 읽는 쪽(BibleReadingContentView, 자체 `.toolbar`를 가진 뷰)에서 실기기
    /// 크래시가 나 `AppNavigationRequest`(평범한 `Equatable` 값 기반)로 바꿨다 —
    /// 자세한 이유는 `Services/AppNavigationRequest.swift` 상단 주석 참고.
    @State private var selectedTab: AppSection = .wordNote

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
                .tabItem { Label("문서·OCR", systemImage: "doc.text.viewfinder") }
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
