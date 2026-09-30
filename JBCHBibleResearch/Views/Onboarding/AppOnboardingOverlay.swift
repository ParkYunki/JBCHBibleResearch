//
//  AppOnboardingOverlay.swift
//  JBCHBibleResearch
//
//  앱 최초 실행 시 한 번만 주요 기능(성경 조회/통합 검색/연구문서 관리/
//  말씀 노트·책갈피)을 소개하는 카러셀 온보딩 화면.
//
//  `ViewModifier` + `extension View` 패턴이라 `ContentView`가 한 줄만 붙이면 되고,
//  반복 노출은 `UserSettingsStore.hasCompletedOnboarding` 플래그로 막는다.
//  `TabView(.page)`는 macOS에 없어 직접 만든 최소 카러셀(페이지 인덱스 +
//  이전/다음 버튼 + 점 인디케이터)을 써서 macOS/iPadOS/iPhone이 같은 코드로 동작한다.
//
//  커스텀 일러스트 에셋이 없어 SF Symbol + 그라디언트 원을 쓴다. 일러스트가
//  준비되면 `OnboardingPage.icon`을 쓰는 자리만 `Image("파일명")`으로 바꾸면 된다.
//
//  완료 시 `UserSettingsStore.lastSeenAppVersion`도 현재 버전으로 채워, 갓 설치한
//  사용자에게 `WhatsNewOverlay`의 업데이트 안내가 잇따라 뜨지 않게 한다.
//

import SwiftUI
#if DEBUG
import Observation
#endif

#if DEBUG
/// DEBUG 전용 — 설정의 "개발자" 탭이 이 값을 증가시키면 `AppOnboardingPresenter`가
/// `hasCompletedOnboarding`과 무관하게 온보딩을 다시 띄운다. 값 자체엔 의미가 없고
/// 매번 바뀐다는 사실만 `.onChange`가 감지한다(`SearchResultsPopRequest`와 같은 패턴).
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
        title: "엠마오 성경 연구에 오신 것을 환영합니다",
        description: "성경 본문, 연구자료, 개인 묵상을 한곳에서 관리하는 앱입니다. 주요 기능을 간단히 소개합니다."
    ),
    OnboardingPage(
        icon: "book",
        gradientColors: [.indigo, .blue],
        title: "성경 조회",
        description: "여러 번역본을 나란히 놓고 비교하며 읽고, 구절을 탭해 메모·말씀 요약으로 이어갈 수 있습니다."
    ),
    // 인물/지명/예언/AI 의미검색은 뒷단 데이터셋(인덱스, 임베딩 색인)이 아직 다 채워지지
    // 않아 소개하지 않는다. 안정적으로 동작하는 성경구절/메모/연구문서 검색만 소개한다.
    OnboardingPage(
        icon: "magnifyingglass",
        gradientColors: [.purple, .pink],
        title: "통합 검색",
        description: "성경구절·메모·연구문서를 한 번에 검색합니다."
    ),
    OnboardingPage(
        icon: "doc.text.magnifyingglass",
        gradientColors: [.orange, .yellow],
        title: "연구 문서 관리",
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
    /// "온보딩 다시 보기"로 열린 미리보기 여부. 이 경우 `markCompleted()`가
    /// `hasCompletedOnboarding`/`lastSeenAppVersion`을 건드리지 않아, 미리보기를 닫아도
    /// 의도적으로 비워 둔 `lastSeenAppVersion`이 다시 채워지지 않는다.
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
            // "시작하기" 버튼과 시스템 스와이프 종료 모두 시트가 닫히는 것이므로,
            // 어느 경로든 완료 기록이 남도록 `onDismiss`에서 처리한다.
            .sheet(isPresented: $isPresented, onDismiss: markCompleted) {
                AppOnboardingSheet(onFinish: { isPresented = false })
                    #if os(macOS)
                    .frame(width: 480, height: 560)
                    #endif
            }
    }

    private func markCompleted() {
        #if DEBUG
        // 개발자 미리보기 경로는 완료 플래그/버전 기록을 건드리지 않는다.
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

            VStack(spacing: 10) {
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

                // 부트스트랩(`ContentView`의 `.task`)이 끝나기 전에는 "다음" 반응이 늦을 수 있어,
                // 멈춘 것처럼 보이지 않게 안내만 보여준다. 항목 수에 따라 소요 시간이 들쭉날쭉해
                // 퍼센트 진행률은 계산하지 않는다.
                if AppBootstrapProgress.shared.isPreparingInitialData {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("초기 데이터를 준비하는 중입니다…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                    .fill(index == pageIndex ? Color("AccentColor") : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
