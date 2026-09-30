//
//  BibleIndexOnboardingOverlay.swift
//  JBCHBibleResearch
//
//  앱 첫 실행 시 성경 의미검색 색인을 자동으로 시작하고 진행 상황을 보여주는 안내 시트.
//  가이드 이미지 대신 SF Symbol + 그라디언트 아이콘을 쓴다(커스텀 일러스트 에셋 없음).
//
//  `UserSettingsStore.hasOfferedBibleIndexOnboarding`이 켜져 있으면 다시 자동으로 뜨지 않는다.
//  색인이 실패하거나 건너뛰어도 검색 화면의 "색인 만들기" 버튼으로 수동 재시도할 수 있다.
//

import SwiftUI

/// `ContentView`가 앱 시작 시 1회 붙이는 컨트롤러. `EmbeddingIndexingService`가 `@Observable`이 아니라
/// 색인 상태는 폴링하지 않고 `startBuilding`의 progress/completion 콜백으로만 갱신한다.
struct BibleIndexOnboardingPresenter: ViewModifier {
    @State private var isPresented = false
    @State private var status: EmbeddingIndexingService.IndexStatus = .notBuilt
    /// 온보딩 카루셀/"새로워진 점" 시트가 아직 끝나지 않아 이 시트를 대기시키는 중인지.
    /// 두 시트와 동시에 `.sheet`를 띄우면 macOS에서 빈 시트만 남는 경합이 생긴다.
    /// 색인 자체(백그라운드 작업)는 대기와 무관하게 즉시 시작한다.
    @State private var hasPendingSheet = false

    func body(content: Content) -> some View {
        content
            .task {
                await presentIfNeeded()
            }
            // `UserSettingsStore`가 `@Observable`이라 온보딩/새로워진 점 완료(두 값의 변경)를 그대로 감지해
            // 대기 중인 시트가 있으면 다시 확인한다.
            .onChange(of: UserSettingsStore.shared.hasCompletedOnboarding) { _, _ in
                presentPendingSheetIfReady()
            }
            .onChange(of: UserSettingsStore.shared.lastSeenAppVersion) { _, _ in
                presentPendingSheetIfReady()
            }
            .sheet(isPresented: $isPresented) {
                BibleIndexOnboardingSheet(status: status, onDismiss: dismiss)
                    #if os(macOS)
                    .frame(width: 420, height: 480)
                    #endif
                    .interactiveDismissDisabled(false)
            }
    }

    /// 이번 실행에서 뜰 차례였던 첫 화면 안내(온보딩 카루셀 또는 새로워진 점)가 모두 끝났는지.
    /// 버전이 바뀌지 않은 일반 실행에서는 `lastSeenAppVersion`이 이미 현재 버전과 같아 즉시 참이다.
    private var isFirstRunAnnouncementResolved: Bool {
        let settings = UserSettingsStore.shared
        guard settings.hasCompletedOnboarding else { return false }
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return settings.lastSeenAppVersion == currentVersion
    }

    private func presentPendingSheetIfReady() {
        guard hasPendingSheet, isFirstRunAnnouncementResolved else { return }
        hasPendingSheet = false
        // 앞선 시트가 닫히는 순간 같은 뷰 계층에서 바로 다음 시트를 열면 macOS SwiftUI가 상태를 정리하지
        // 못해 빈 시트가 뜨므로 짧은 지연을 둔다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = true
        }
    }

    /// 색인이 이미 있거나(`.ready`) 이 안내를 이미 보여준 적 있으면 아무것도 하지 않는다.
    /// 그 외에는 색인을 즉시 시작하고, 시트는 첫 화면 안내가 끝난 경우에만 바로 띄우며 아니면 `hasPendingSheet`로 대기시킨다.
    private func presentIfNeeded() async {
        guard !UserSettingsStore.shared.hasOfferedBibleIndexOnboarding else { return }
        EmbeddingIndexingService.shared.refreshStatus()
        guard case .notBuilt = EmbeddingIndexingService.shared.status else {
            // 이미 색인이 있으면 안내가 필요 없다. 이후 색인을 지우고 다시 만들 때도 자동 안내가 끼어들지 않도록
            // 플래그는 여기서도 켠다.
            UserSettingsStore.shared.hasOfferedBibleIndexOnboarding = true
            return
        }

        status = .building(progress: 0)
        EmbeddingIndexingService.shared.startBuilding(
            progress: { fraction in status = .building(progress: fraction) },
            completion: { finalStatus in status = finalStatus }
        )

        if isFirstRunAnnouncementResolved {
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
            .tint(Color("AccentColor"))
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
