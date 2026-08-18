//
//  PhoneTabView.swift
//  JBCHBibleResearch
//
//  screens.md 1장 IA — iPhone 전용 탭바. 5개 탭: 메모/성경/문서·OCR/개요/더보기.
//  순서는 원문서 그대로(메모가 먼저, 성경이 두 번째)를 따랐다 — macOS 사이드바 순서
//  (성경 조회가 첫 항목, AppSection.allCases 순서)와 다른 것은 원문서 1장 IA 자체가
//  iPhone 탭 순서를 그렇게 명시했기 때문이다.
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

            // [2026-08-14 변경] 사용자 요청 — "개요: 구약/신약 > 책 > 장 폴더
            // 구조로." SidebarNavigationView.swift와 같은 변경.
            NavigationStack { OutlineTreeView() }
                .tabItem { Label("개요", systemImage: "list.bullet.rectangle") }
                .tag(AppSection.outline)

            NavigationStack { MorePlaceholderView() }
                .tabItem { Label("더보기", systemImage: "ellipsis.circle") }
        }
        // ⚠️ [범위] "통합검색"/"태그 관계"는 이 탭바에 직접적인 탭이 없다("더보기"
        // 안에 있을 후보 — MorePlaceholderView가 아직 플레이스홀더라 실제 배치는
        // 미확정). 그래서 탭이 없는 값이 오면 무시한다 — 지금 이 패널이 실제로
        // 요청하는 값은 `.outline` 하나뿐이라 당장은 문제가 되지 않는다.
        .onChange(of: AppNavigationRequest.shared.requestedSection) { _, newValue in
            guard let newValue, AppSection.phoneTabBarSections.contains(newValue) else { return }
            selectedTab = newValue
            AppNavigationRequest.shared.clear()
        }
    }
}
