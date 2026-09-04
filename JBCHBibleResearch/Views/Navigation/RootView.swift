//
//  RootView.swift
//  JBCHBibleResearch
//
//  근거: 사용자 확인 — 이 프로젝트는 macOS/iPadOS/iOS를 별도 타겟이 아니라 하나의
//  멀티플랫폼 타겟으로 개발한다. 그래서 screens.md가 원래 "iOS는 타겟 멤버십 제외로
//  뷰어 전용" 식으로 상정했던 부분을, 여기서는 런타임/컴파일 타임 조건부(#if os(...),
//  UIDevice.current.userInterfaceIdiom)로 대체한다.
//
//  화면 전환 흐름(screens.md 5장): macOS/iPadOS는 사이드바 기반, iPhone은 탭바 기반.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    var body: some View {
        content
            // [2026-09-03 이전] 여기서 `.preferredColorScheme(UserSettingsStore
            // .shared.colorSchemePreference.colorScheme)`을 직접 걸었었다 —
            // 사용자 보고: "설정 > 성경 > 모양의 화면모드를 바꾸면 자동으로
            // 성경으로 이동한다(더보기 > 설정 하위 어느 화면에 있었든 상관없이)."
            // 원인 확인(Apple Developer Forums 스레드 726363, "App Lost all
            // selection info of navigation and tab, after update a AppStorage
            // state" — 같은 증상: `@AppStorage` 값을 읽는 바로 그 뷰가 동시에
            // `TabView`를 직접 구성하고 있으면, 그 값이 바뀔 때마다 `TabView`
            // 자체가 다시 만들어져 선택된 탭(`PhoneTabView.selectedTab`, 기본값
            // `.bibleReading` = "성경")과 그 안의 내비게이션 스택이 초기화된다):
            // 이 `body`가 `content`(바로 아래, `PhoneTabView`를 직접 만든다)를
            // 만드는 동시에 `colorSchemePreference`도 읽고 있어 정확히 같은
            // 구성이었다. 그 포럼 답변의 해법대로 — 이 값을 읽는 자리와 TabView를
            // 만드는 자리를 분리 — 이 modifier는 `ContentView.swift`의
            // `RootView()`(이 뷰의 "바깥"에서 이 뷰를 만드는 자리)로 옮겼다.
            // `RootView.body`는 이제 이 값을 전혀 읽지 않으므로, 값이 바뀌어도
            // 이 아래 `content`/`PhoneTabView`는 다시 만들어지지 않고 그대로
            // 유지된다 — "화면 모드"는 여전히 앱 전체(모든 창/탭)에 적용된다,
            // 적용 위치만 한 단계 바깥으로 옮겼을 뿐이다.
            // [2026-08-08 추가, 2026-08-16 되돌림] 사용자 요청으로 한때 "앱에서
            // 사용되는 글꼴도 여기에 내장된 기본글꼴(Paperlogy-4Regular)로"
            // `.appDefaultFont()`(BundledFontRegistrar.swift)를 메인 창 전체에
            // 걸었었다 — 그런데 그 뒤로 화면마다 "이 화면은 시스템 기본폰트로
            // 되돌려달라"는 요청이 반복돼(ChapterRelatedContentPanel/
            // DocumentsHomeView/WordNoteHomeView/OutlineTreeView/BookChapterPicker/
            // CrossReferenceTargetPicker 등 각 파일 상단 주석 참고), 결국 "Paperlogy는
            // 성경 본문과 관련될 때만 쓰고, 나머지는 전부 시스템 기본 글꼴/보통
            // 크기로" 정리하기로 했다. 그래서 이 전역 강제를 아예 뺐다 — 이제 이
            // 아래 어디서도 `.font(...)`를 명시하지 않은 `Text`/`Label`은 SwiftUI
            // 기본값(시스템 폰트)을 그대로 쓴다.
            //
            // Paperlogy는 여전히 실제로 필요한 곳(성경 본문/절 텍스트)에만 남는다 —
            // `UserSettingsStore.bibleBodyFont`(TranslationColumnView/
            // OriginalTextInfoView가 명시적으로 `.font(settings.bibleBodyFont)`로
            // 적용, 환경설정에서 "System"으로 바꿀 수도 있음)와 메모 편집기 기본
            // 서식(`EditorDefaultStyle`), 그리고 `RichTextEditor`의 글꼴 선택
            // 메뉴(사용자가 원하면 직접 고르는 옵션) — 이 세 곳은 각자 독립적으로
            // 폰트를 지정하므로 이 줄을 빼도 영향받지 않는다.
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
