//
//  RootView.swift
//  JBCHBibleResearch
//
//  macOS/iPadOS/iOS를 별도 타겟이 아니라 하나의 멀티플랫폼 타겟으로 개발하므로,
//  플랫폼별 분기는 컴파일 타임(#if os(...))과 런타임(UIDevice.current.userInterfaceIdiom)
//  조건으로 처리한다. macOS/iPadOS는 사이드바 기반, iPhone은 탭바 기반 화면 전환이다.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    var body: some View {
        content
        // 이 body에서 `.preferredColorScheme`(`@AppStorage` 계열 값)을 읽으면 안 된다.
        // 값을 읽는 뷰가 동시에 `TabView`를 직접 구성하면 값이 바뀔 때마다 `TabView`가
        // 다시 만들어져 선택 탭(`PhoneTabView.selectedTab`)과 내비게이션 스택이
        // 초기화된다(Apple Developer Forums 스레드 726363). 그래서 화면 모드 적용은
        // 이 뷰 바깥인 `ContentView.swift`의 `RootView()` 호출부에서 한다.
        //
        // 전역 폰트도 여기서 강제하지 않는다. Paperlogy는 성경 본문(`UserSettingsStore
        // .bibleBodyFont`), 메모 편집기 기본 서식(`EditorDefaultStyle`), `RichTextEditor`
        // 글꼴 메뉴에서만 각자 명시하고, 나머지는 시스템 기본 폰트를 쓴다.
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        SidebarNavigationView()
        #else
        if UIDevice.current.userInterfaceIdiom == .phone {
            PhoneTabView()
        } else {
            SidebarNavigationView()
        }
        #endif
    }
}
