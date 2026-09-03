//
//  BibleIndexOnboardingOverlay.swift
//  JBCHBibleResearch
//
//  [2026-08-19 신설] 사용자 요청 — "앱을 설치할 때, 처음 시작할 때 색인을
//  자동으로 설치하면 안되는가? 그때 가이드 이미지도 보여주면서 설치하는 것은?"
//  지금까지는 사용자가 검색 화면에서 AI 토글을 켜고 "색인 만들기"를 직접
//  눌러야 했다(`SearchView.bibleIndexStatusRow`) — 이 화면은 그 수고를 없애고,
//  앱을 처음 켰을 때 자동으로 색인을 시작하면서 진행 상황을 보여주는
//  안내 화면이다.
//
//  ⚠️ [의도적으로 "이미지" 대신 SF Symbol 조합을 씀] 사용자가 "가이드 이미지"라고
//  표현했지만, 이 프로젝트엔 커스텀 일러스트 에셋이 없다 — 새 이미지 파일을
//  만들어 넣는 대신, 이미 이 앱 전체가 쓰는 언어(SF Symbol + 그라디언트,
//  `SearchView.categoryIcon`과 같은 원리)로 큼직한 아이콘을 만들었다. 나중에
//  실제 일러스트를 준비하면 이 뷰의 아이콘 부분만 `Image("파일명")`으로
//  바꾸면 된다.
//
//  [반복 노출 방지] `UserSettingsStore.hasOfferedBibleIndexOnboarding`이 켜져
//  있으면(한 번이라도 이 화면을 보여준 적 있으면) 다시 자동으로 뜨지 않는다 —
//  색인이 실패했거나 사용자가 건너뛰었어도, 그 이후엔 검색 화면의 기존
//  "색인 만들기" 버튼으로 언제든 수동으로 다시 시도할 수 있다(막다른 길이
//  아니다).
//

import SwiftUI

/// `ContentView`가 앱 시작 시 1회 붙이는 컨트롤러. 색인 상태를 직접 폴링하지
/// 않고 `EmbeddingIndexingService.shared.startBuilding`의 progress/completion
/// 콜백으로만 갱신한다(`SearchViewModel.startBibleEmbeddingIndexing`과 같은 이유
/// — 그 서비스가 `@Observable`이 아니라서).
struct BibleIndexOnboardingPresenter: ViewModifier {
    @State private var isPresented = false
    @State private var status: EmbeddingIndexingService.IndexStatus = .notBuilt
    /// [2026-09-03 추가] 사용자 보고 — "다른 맥에서 설치한 후 온보딩 내용
    /// 또는 새로워진 점이 떠야 할텐데 뜨지 않고 내용 없는 빈 시트만 나타남."
    /// `ContentView.swift`의 `.appOnboarding()` 상단 주석이 이미 예측해 둔
    /// 경합이 실제로 재현된 것이었다 — 완전히 새로 설치한 기기에서는
    /// `AppOnboardingPresenter`와 이 프레젠터의 `.task`가 동시에 실행되어,
    /// 서로 독립적으로 자기 `.sheet`를 띄우려다 macOS에서 둘 다 제대로
    /// 그려지지 않고 빈 시트만 남았다. 색인 자체(백그라운드 작업)는 온보딩과
    /// 무관하게 즉시 시작해도 되지만(사용자 확인), 이 화면(시트)만큼은 온보딩
    /// 카루셀이 끝난 뒤에 띄워 두 시트가 동시에 뜨는 일이 없게 한다 — 이
    /// 플래그는 "색인은 이미 시작했고 보여줄 시트도 준비됐지만, 온보딩이 아직
    /// 안 끝나 대기 중"이라는 뜻이다.
    @State private var hasPendingSheet = false

    func body(content: Content) -> some View {
        content
            .task {
                await presentIfNeeded()
            }
            // [2026-09-03 추가] `UserSettingsStore`가 `@Observable`이라(다른
            // 화면들이 `settings.xxx`를 직접 읽는 것과 같은 방식) 이 값이
            // `AppOnboardingPresenter.markCompleted()`에서 `true`로 바뀌는
            // 순간을 별도의 알림 채널 없이 그대로 감지할 수 있다 — 온보딩
            // 카루셀이 막 끝났고, 위 `presentIfNeeded()`가 대기시켜 둔 시트가
            // 있으면 그제서야 띄운다.
            .onChange(of: UserSettingsStore.shared.hasCompletedOnboarding) { _, completed in
                guard completed, hasPendingSheet else { return }
                hasPendingSheet = false
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                BibleIndexOnboardingSheet(status: status, onDismiss: dismiss)
                    #if os(macOS)
                    .frame(width: 420, height: 480)
                    #endif
                    .interactiveDismissDisabled(false)
            }
    }

    /// 색인이 이미 있거나(`.ready`) 예전에 한 번이라도 이 화면을 보여준 적
    /// 있으면 아무것도 하지 않는다 — 그 외(첫 실행, 아직 색인 없음)에만
    /// 자동으로 색인을 시작하고 이 화면을 띄운다.
    ///
    /// [2026-09-03 변경] 색인 시작(`EmbeddingIndexingService.startBuilding`)은
    /// 여전히 무조건 즉시 실행하되(사용자 확인 — 온보딩 카루셀과 무관하게
    /// 앱 시작과 동시에 백그라운드에서 바로 시작), 시트를 "보여주는" 시점만
    /// `hasCompletedOnboarding`에 따라 갈린다 — 이미 온보딩을 마친 기존
    /// 사용자(가장 흔한 경우)는 예전과 동일하게 즉시 뜨고, 온보딩을 아직
    /// 안 마친 새 설치에서만 위 `hasPendingSheet`로 대기시켰다가 온보딩이
    /// 끝나는 순간(`onChange` 위 참고) 띄운다.
    private func presentIfNeeded() async {
        guard !UserSettingsStore.shared.hasOfferedBibleIndexOnboarding else { return }
        EmbeddingIndexingService.shared.refreshStatus()
        guard case .notBuilt = EmbeddingIndexingService.shared.status else {
            // 이미 색인이 있으면(.ready) 굳이 안내할 필요가 없다 — 다만 "한 번
            // 보여준 적 있음" 플래그는 여기서도 같이 켜서, 이후 색인을 지우고
            // 다시 만드는 경우(설정 등)까지 이 자동 안내가 다시 끼어들지
            // 않게 한다.
            UserSettingsStore.shared.hasOfferedBibleIndexOnboarding = true
            return
        }

        status = .building(progress: 0)
        EmbeddingIndexingService.shared.startBuilding(
            progress: { fraction in status = .building(progress: fraction) },
            completion: { finalStatus in status = finalStatus }
        )

        if UserSettingsStore.shared.hasCompletedOnboarding {
            isPresented = true
        } else {
            hasPendingSheet = true
        }
    }

    private func dismiss() {
        UserSettingsStore.shared.hasOfferedBibleIndexOnboarding = true
        isPresented = false
    }
}

extension View {
    /// `ContentView`에서 `.task` 하나 붙이듯 쓴다 — 실제 조건 판단/색인 시작/시트
    /// 표시는 전부 `BibleIndexOnboardingPresenter` 안에 있다.
    func bibleIndexOnboarding() -> some View {
        modifier(BibleIndexOnboardingPresenter())
    }
}

private struct BibleIndexOnboardingSheet: View {
    let status: EmbeddingIndexingService.IndexStatus
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.22), Color.indigo.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 128, height: 128)
                Image(systemName: iconName)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .symbolEffect(.pulse, isActive: isBuilding)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            progressSection

            Spacer(minLength: 12)

            Button(action: onDismiss) {
                Text(buttonTitle)
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 28)
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity)
    }

    private var isBuilding: Bool {
        if case .building = status { return true }
        return false
    }

    private var iconName: String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "sparkles"
        }
    }

    private var title: String {
        switch status {
        case .ready: return "AI 의미검색 준비 완료"
        case .failed: return "색인을 만들지 못했습니다"
        default: return "AI 의미검색 준비 중"
        }
    }

    private var description: String {
        switch status {
        case .ready(let count, _):
            return "성경 \(count)개 절을 전부 분석했습니다. 이제 검색창에서 AI 검색을 켜고 질문하듯 검색해보세요."
        case .failed(let message):
            return message + " 나중에 검색 화면의 AI 검색 토글에서 다시 시도할 수 있습니다."
        default:
            return "성경 전체(66권 31,102절)의 뜻을 한 번만 분석해두면, 이후엔 정확한 구절이 기억나지 않아도 질문하듯 검색할 수 있습니다. 이 화면을 닫아도 백그라운드에서 계속됩니다."
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        switch status {
        case .building(let progress):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(maxWidth: 260)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .notBuilt:
            ProgressView()
        case .ready, .failed:
            EmptyView()
        }
    }

    private var buttonTitle: String {
        switch status {
        case .ready: return "확인"
        case .failed: return "닫기"
        default: return "백그라운드에서 계속하기"
        }
    }
}
