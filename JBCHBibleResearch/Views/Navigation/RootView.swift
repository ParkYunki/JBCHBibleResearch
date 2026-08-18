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
            // 8.6 "화면 모드" — UserSettingsStore.shared.colorSchemePreference를
            // body 안에서 직접 읽었으므로(Observation이 자동 추적) 설정 화면에서
            // 값이 바뀌면 이 뷰도 다시 그려진다. `.system`은 nil이라 강제하지 않는다.
            .preferredColorScheme(UserSettingsStore.shared.colorSchemePreference.colorScheme)
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
