//
//  PlaceholderScreens.swift
//  JBCHBibleResearch
//
//  이번 구현 범위(내비게이션 뼈대 + S1 + S2/S3 메모)에서는 성경 조회·메모 화면만
//  실제로 만든다. 나머지 화면(S5~S7 문서/OCR, S8/S9 개요, S10 태그 관계, S11 통합
//  검색, 설정, 번역본 관리)은 내비게이션 뼈대가 완전한 형태로 동작하는지 확인할 수
//  있도록 자리만 잡아 두는 플레이스홀더다 — 실제 데이터/기능은 없다.
//
//  2026-08-06: 메모(S2/S3)가 실제로 구현되면서 MemosPlaceholderView는 제거하고
//  Views/Memo/MemoHomeView.swift로 교체했다(SidebarNavigationView/PhoneTabView 참고).
//  같은 날, 개요(S8/S9)가 구현되면서 OutlinePlaceholderView도 같은 이유로 제거하고
//  Views/Outline/OutlineView.swift로 교체했다. 이어서 연구문서(S5/S6/S7)가
//  구현되면서 DocumentsPlaceholderView도 제거하고 Views/Documents/
//  DocumentsHomeView.swift로 교체했다. 이어서 태그 관계(S10)가 구현되면서
//  TagRelationsPlaceholderView도 제거하고 Views/TagRelations/TagRelationsView.swift로
//  교체했다(아이폰 "더보기" 진입점은 스펙 "iOS는 전체화면 모달로 대응"에 맞춰
//  NavigationLink 대신 .fullScreenCover로 바꿨다 — MorePlaceholderView 참고).
//  이어서 설정(8장)이 구현되면서 SettingsPlaceholderView도 제거하고
//  Views/Settings/SettingsView.swift로 교체했다. 이어서 통합 검색(S11)이
//  구현되면서 UnifiedSearchPlaceholderView도 제거하고 Views/Search/SearchView.swift로
//  교체했다. 이어서 [2026-08-07] 번역본 관리(S12)가 구현되면서
//  TranslationManagementPlaceholderView도 제거하고
//  Views/Translations/TranslationManagementView.swift로 교체했다 — 이걸로 이
//  파일에는 더 이상 대체 대상 플레이스홀더가 남아 있지 않다(MorePlaceholderView
//  자체는 플레이스홀더가 아니라 "더보기" 탭의 진짜 메뉴 화면이라 남겨 둔다).
//

import SwiftUI

private struct ComingSoonView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
            Text("곧 제공됩니다")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}

/// iPhone "더보기" 탭 — screens.md 1장 IA: 태그관계·설정 등으로 진입.
/// 태그 관계(S10)는 스펙 "iOS는 전체화면 모달로 대응"에 따라 NavigationLink push가
/// 아니라 `.fullScreenCover`로 연다(macOS/iPadOS의 별도 창과 같은 역할을 하는
/// iPhone식 대응).
///
/// [2026-09-03 정정] 바로 위 문단이 "번역본 관리(S12)는 NavigationLink로
/// `TranslationManagementView`를 push한다"고 적어 뒀던 것은 이제 사실이
/// 아니다 — 사용자 결정("번역본 화면 통합안: 더보기 > 설정 > 성경 > 번역본으로
/// 통합, 더보기 > 번역본 관리의 항목 삭제")으로 이 메뉴에서 "번역본 관리"
/// 항목 자체를 뺐고, `TranslationManagementView.swift`도 삭제했다. 같은 기능은
/// 이제 "설정" 항목 → 성경 → 번역본(`SettingsView.swift`의
/// `TranslationsManagementTab`)에서 접근한다.
///
/// ⚠️ [2026-08-07 추가, IA 대비 보완] 1장 IA 원문은 iPhone 탭바를 "메모/성경/
/// 문서·OCR/개요/더보기" 5개로만 명시했고 "통합 검색"은 그 목록에 없다. 하지만
/// 2장 화면 총괄표는 S11(통합 검색)의 iOS 접근 수준을 "동일"(macOS/iPadOS와 같은
/// 전체 기능)로 명시했다 — 즉 iPhone에서도 반드시 닿을 수 있어야 한다는 뜻인데
/// 탭바엔 자리가 없다. 이미 같은 이유로 S12(번역본 관리)가 탭바 목록에 없으면서도
/// "더보기"에 들어가 있는 선례가 있어, 한때 통합 검색도 같은 자리에 추가했었다.
///
/// [2026-08-27, 최종적으로 자리를 다시 바꿈 — 사용자 결정 "개요→더보기,
/// 검색→탭바"] "통합 검색"을 이 메뉴 안에 두는 동안(중첩된 `NavigationStack`
/// 안에서 `.searchable`이 활성 상태로 그 자리에서 성경구절로 push하는 구조)
/// 세 차례의 실기기 콘솔 로그로 근본적으로 못 고치는 구조적 결함이 확인됐다
/// (`SearchView.swift` 상단 주석 참고). 그래서 "통합 검색"을 `PhoneTabView`의
/// 정식 탭으로 승격하고, 대신 원래 탭이었던 "개요"(`OutlineTreeView`)를 이
/// 메뉴 안 전체화면 모달로 옮겼다 — "태그 관계"와 똑같은 패턴이다. `OutlineTreeView`가
/// 아이폰 분기에서 자기 자신의 `NavigationStack(path:)`를 이미 소유하고 있어서
/// (`OutlineTreeView.swift` 상단 주석 참고) "태그 관계"처럼 이 파일에서 별도
/// `NavigationStack`으로 한 번 더 감싸지 않는다 — 그러면 내비게이션 스택이
/// 중첩돼(공식적으로 지원되지 않는 구성) `PhoneTabView.swift`가 이미 한 번 겪은
/// 것과 같은 문제가 재현된다.
///
/// `isOutlinePresented`는 이 화면 로컬 상태가 아니라 `PhoneTabView`가 들고
/// 있다가 바인딩으로 내려준다 — 성경 조회 화면의 "관련 콘텐츠 > 개요 화면
/// 열기"(`AppNavigationRequest.shared.request(.outline)`)가 "더보기"가 현재
/// 선택된 탭이 아닐 때도 이 모달을 띄워야 하는데, 이 값이 이 화면(현재
/// 선택되지 않은 탭이면 화면 계층 자체가 안 보임) 안에 로컬로 있으면 그 경우
/// 모달이 뜨지 않는다(`PhoneTabView.swift` 상단 주석 참고).
struct MorePlaceholderView: View {
    @State private var isTagRelationsPresented = false
    @Binding var isOutlinePresented: Bool

    var body: some View {
        List {
            Button {
                isTagRelationsPresented = true
            } label: {
                Label("태그 관계", systemImage: "circle.grid.cross")
            }
            Button {
                isOutlinePresented = true
            } label: {
                Label("개요", systemImage: "list.bullet.rectangle")
            }
            // [2026-09-03 삭제] 사용자 결정 — "번역본 화면 통합안: 더보기 >
            // 설정 > 성경 > 번역본으로 통합(더보기 > 번역본 관리의 항목
            // 삭제)." 여기 있던 "번역본 관리"(`TranslationManagementView`
            // push) 항목을 없앴다 — 그 화면이 갖고 있던 표시 이름/라이선스
            // 편집·책이름표 언어 피커는 `SettingsView.swift`의
            // `TranslationsManagementTab`("번역본" MARK 섹션)으로 그대로
            // 옮겨, 아래 "설정" 진입점 → 성경 → 번역본에서 이어서 접근한다.
            // `TranslationManagementView.swift`/`TranslationManagementViewModel
            // .swift` 자체도 이 항목이 유일한 참조처였어서 함께 지웠다.
            // [2026-09-03 변경] 사용자 요청 — "아이폰 - 더보기 - 설정의
            // 레이아웃을 UX/UI 전문가 관점에서 최적화." 여기서 직접 push하던
            // `SettingsView()`(macOS `Settings` Scene용 최상위 `TabView` 구조를
            // 그대로 갖고 있어, 이 화면 안에 중첩되면 하단에 탭바가 이중으로
            // 뜨는 문제가 있었다 — 자세한 이유는 `SettingsView.swift`의
            // `SettingsHomeView` 선언부 주석 참고) 대신, 같은 세 카테고리(일반/
            // 성경/개발자)를 아이콘 목록으로 보여주는 iPhone 전용 진입 화면
            // `SettingsHomeView`로 바꿨다.
            NavigationLink {
                SettingsHomeView()
            } label: {
                Label("설정", systemImage: "gearshape")
            }
        }
        .navigationTitle("더보기")
        // [2026-09-03 추가] 사용자 보고 — "아이폰 하단 메뉴 중 말씀 노트/문서
        // OCR/통합 검색/더보기는 상단 우측 아이콘과 그 밑 타이틀이 따로 있어
        // 아이콘 좌측 영역이 낭비됨." `WordNoteHomeView.swift`의 같은 날짜
        // 주석과 같은 이유·같은 해법 — `.navigationBarTitleDisplayMode(.inline)`.
        // 이 화면 자체는 이미 아이폰 전용(PhoneTabView)이라 `#if os(iOS)` 없이도
        // 안전하지만, 멀티플랫폼 단일 타겟이 macOS에서도 이 파일을 컴파일하는
        // 것은 바로 아래 `.fullScreenCover`와 같은 사정이라 똑같이 감싼다.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // ⚠️ 2026-08-06 Xcode 빌드 오류로 확인: `fullScreenCover`는 iOS/iPadOS
        // 전용이라 macOS에는 심볼 자체가 없다(`'fullScreenCover(isPresented:onDismiss:content:)'
        // is unavailable in macOS`). 이 뷰(MorePlaceholderView)는 실제로 PhoneTabView를
        // 통해 아이폰에서만 쓰이지만, 멀티플랫폼 단일 타겟이라 macOS 빌드에서도 이
        // 파일 전체가 컴파일되므로 `#if os(iOS)`로 감싸야 한다 — macOS 쪽은 이
        // 뷰 자체가 쓰이지 않으니 대체 없이 그냥 비워 둔다.
        #if os(iOS)
        .fullScreenCover(isPresented: $isTagRelationsPresented) {
            NavigationStack {
                TagRelationsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기") { isTagRelationsPresented = false }
                        }
                    }
            }
        }
        #endif
    }
}
