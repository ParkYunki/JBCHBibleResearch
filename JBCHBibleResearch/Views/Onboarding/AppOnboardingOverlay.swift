//
//  AppOnboardingOverlay.swift
//  JBCHBibleResearch
//
//  [2026-08-28 신설] 사용자 요청 — "처음 설치하시는 사람을 위한 가이드 화면이
//  필요함." 앱을 처음 실행했을 때 딱 한 번, 주요 기능(성경 조회/통합 검색/
//  연구문서 관리/말씀 노트·책갈피)을 소개하는 카러셀을 보여준다.
//
//  구조는 `BibleIndexOnboardingOverlay.swift`(2026-08-19, 이 앱의 첫 "1회성
//  안내 화면" 선례)와 같은 패턴 — `ViewModifier` + `extension View`로
//  `ContentView`가 한 줄만 붙이면 되게 하고, 반복 노출은
//  `UserSettingsStore.hasCompletedOnboarding` 플래그로 막는다. 다만 내용은
//  진행 상태 하나가 아니라 여러 "페이지"라, `TabView(.page)`(macOS엔 이
//  스타일 자체가 없다) 대신 직접 만든 최소 카러셀(현재 페이지 인덱스 +
//  이전/다음 버튼 + 점 인디케이터)을 썼다 — 이러면 macOS/iPadOS/iPhone
//  전부 같은 코드로 동작한다.
//
//  ⚠️ [의도적으로 "이미지" 대신 SF Symbol 조합을 씀] `BibleIndexOnboardingOverlay.
//  swift` 상단 주석과 같은 이유 — 이 프로젝트엔 커스텀 일러스트 에셋이 없어,
//  이미 앱 전체가 쓰는 언어(SF Symbol + 그라디언트 원)로 대신했다. 나중에
//  실제 일러스트가 준비되면 `OnboardingPage.icon`을 쓰는 자리만
//  `Image("파일명")`으로 바꾸면 된다.
//
//  [완료 시점에 `lastSeenAppVersion`도 함께 채우는 이유] 사용자 요청 2번 —
//  "업데이트 안내 화면은 처음 설치하는 사람에게는 필요하지 않음." 이 온보딩을
//  마치는 순간 `UserSettingsStore.lastSeenAppVersion`을 지금 버전으로
//  채워 둔다 — 그러면 `WhatsNewOverlay.swift`의 "버전이 달라졌으면 보여준다"
//  조건이 곧바로 거짓이 되어, 방금 설치를 마친 사람에게 업데이트 안내가
//  잇따라 뜨는 일이 없다.
//

import SwiftUI
#if DEBUG
import Observation
#endif

#if DEBUG
/// [2026-08-29 신설] 사용자 요청 — "온보딩 메세지가 한번봤기 때문에 안보이는데
/// 개발자모드에서는 볼 수 있도록 하게 해줘." 설정 화면의 "개발자" 탭
/// (`SettingsView.swift`, 마찬가지로 DEBUG 빌드 전용)이 이 값을 증가시키면
/// `AppOnboardingPresenter`가 `hasCompletedOnboarding` 값과 무관하게 온보딩
/// 카루셀을 다시 띄운다. `SearchResultsPopRequest`(Services/SearchResultsPopRequest.swift)
/// 와 같은 "이벤트가 일어났다" 증가 카운터 싱글턴 패턴을 그대로 따랐다 — 값
/// 자체엔 의미가 없고 매번 바뀐다는 사실만 `.onChange`가 감지하면 된다. DEBUG
/// 빌드에서만 존재하므로 배포 빌드엔 이 타입 자체가 포함되지 않는다.
@MainActor
@Observable
final class AppOnboardingReplayRequest {
    static let shared = AppOnboardingReplayRequest()

    private(set) var token: Int = 0

    private init() {}

    /// "개발자" 탭의 "온보딩 다시 보기" 버튼이 호출한다.
    func requestReplay() {
        token += 1
    }
}
#endif

private struct OnboardingPage {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let description: String
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        icon: "book.closed.fill",
        gradientColors: [.blue, .cyan],
        title: "JBCH 성경 연구에 오신 것을 환영합니다",
        description: "성경 본문, 연구자료, 개인 묵상을 한곳에서 관리하는 앱입니다. 주요 기능을 간단히 소개합니다."
    ),
    OnboardingPage(
        icon: "book",
        gradientColors: [.indigo, .blue],
        title: "성경 조회",
        description: "여러 번역본을 나란히 놓고 비교하며 읽고, 구절을 탭해 메모·말씀 요약으로 이어갈 수 있습니다."
    ),
    // [2026-08-29 수정] 사용자 요청 — "현재는 DB구축이 완료되지 않았으므로
    // 인물, 지명, 예언, AI 의미검색을 지원하지 않음." 실제 화면(SearchView)엔
    // 이 기능들의 UI/의도 카드가 이미 있지만, 그 뒤에서 조회하는 데이터셋
    // (인물/지명/예언 인덱스, 임베딩 색인)이 아직 다 채워지지 않아 온보딩에서
    // 미리 홍보하면 첫 사용자에게 실망을 줄 수 있다 — 지금 실제로 안정적으로
    // 동작하는 범위(성경구절/메모/연구문서 검색)만 소개한다.
    OnboardingPage(
        icon: "magnifyingglass",
        gradientColors: [.purple, .pink],
        title: "통합 검색",
        description: "성경구절·메모·연구문서를 한 번에 검색합니다."
    ),
    OnboardingPage(
        icon: "doc.text.magnifyingglass",
        gradientColors: [.orange, .yellow],
        title: "연구문서 관리",
        description: "hwp·pdf 연구자료를 업로드하면 자동으로 텍스트를 추출하고 성경 장절과 연결해 줍니다."
    ),
    OnboardingPage(
        icon: "bookmark.fill",
        gradientColors: [.teal, .green],
        title: "말씀 노트 · 책갈피",
        description: "개인 묵상을 기록하고, 자주 보는 장·절은 책갈피로 저장해 언제든 빠르게 돌아올 수 있습니다."
    ),
]

/// `ContentView`가 앱 시작 시 1회 붙이는 컨트롤러.
struct AppOnboardingPresenter: ViewModifier {
    @State private var isPresented = false
    #if DEBUG
    /// [2026-08-29 신설] "개발자" 탭의 "온보딩 다시 보기"로 열린 것인지 표시한다
    /// — 이 경로로 열렸을 때는 `markCompleted()`가 `hasCompletedOnboarding`/
    /// `lastSeenAppVersion`을 건드리지 않게 막는다. 이미 온보딩을 마친 기기에서
    /// 내용만 미리보는 용도라, 미리보기를 닫았다고 해서 (예: 다른 목적으로
    /// 일부러 지워 둔) `lastSeenAppVersion`이 조용히 현재 버전으로 다시
    /// 채워지면 "새로워진 점" 화면 테스트가 엉킬 수 있다.
    @State private var isReplayPreview = false
    #endif

    func body(content: Content) -> some View {
        content
            .task {
                if !UserSettingsStore.shared.hasCompletedOnboarding {
                    isPresented = true
                }
            }
            #if DEBUG
            .onChange(of: AppOnboardingReplayRequest.shared.token) { _, _ in
                isReplayPreview = true
                isPresented = true
            }
            #endif
            // [2026-08-28] `onDismiss`에서 완료 처리를 하는 이유 — "시작하기"
            // 버튼(명시적으로 `isPresented = false`)과 시스템 스와이프 종료
            // (버튼을 안 거치는 경로) 둘 다 결국 이 시트가 닫히는 것이므로,
            // 어느 쪽으로 닫히든 "봤다"는 사실과 버전 기록은 항상 남아야 한다.
            .sheet(isPresented: $isPresented, onDismiss: markCompleted) {
                AppOnboardingSheet(onFinish: { isPresented = false })
                    #if os(macOS)
                    .frame(width: 480, height: 560)
                    #endif
            }
    }

    private func markCompleted() {
        #if DEBUG
        // 위 `isReplayPreview` 상단 주석 참고 — 개발자 미리보기 경로는 완료
        // 플래그/버전 기록을 건드리지 않고 조용히 끝낸다.
        if isReplayPreview {
            isReplayPreview = false
            return
        }
        #endif
        UserSettingsStore.shared.hasCompletedOnboarding = true
        UserSettingsStore.shared.lastSeenAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

extension View {
    /// `ContentView`에서 `.task` 하나 붙이듯 쓴다 — 실제 조건 판단/시트 표시는
    /// 전부 `AppOnboardingPresenter` 안에 있다.
    func appOnboarding() -> some View {
        modifier(AppOnboardingPresenter())
    }
}

private struct AppOnboardingSheet: View {
    let onFinish: () -> Void
    @State private var pageIndex = 0

    private var page: OnboardingPage { onboardingPages[pageIndex] }
    private var isLastPage: Bool { pageIndex == onboardingPages.count - 1 }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: page.gradientColors.map { $0.opacity(0.22) },
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 128, height: 128)
                Image(systemName: page.icon)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: page.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .frame(minHeight: 120, alignment: .top)

            pageIndicator

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                if pageIndex > 0 {
                    Button("이전") { pageIndex -= 1 }
                        .buttonStyle(.bordered)
                }
                Button(isLastPage ? "시작하기" : "다음") {
                    if isLastPage {
                        onFinish()
                    } else {
                        pageIndex += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 28)
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: pageIndex)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(onboardingPages.indices, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
