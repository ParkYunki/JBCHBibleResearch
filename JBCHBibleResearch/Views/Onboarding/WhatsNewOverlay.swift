//
//  WhatsNewOverlay.swift
//  JBCHBibleResearch
//
//  [2026-08-28 신설] 사용자 요청 — "업데이트 할때마다 어떤 것을 업데이트 했는지
//  소개해주는 화면 필요함. 처음 설치하는 사람에게는 필요하지 않음." 앱 버전
//  (`CFBundleShortVersionString`)이 지난번 실행 때와 달라졌으면(=업데이트가
//  있었으면) 1회, `WhatsNewContent.swift`에 등록된 그 버전의 안내 항목을
//  보여준다.
//
//  구조는 `AppOnboardingOverlay.swift`/`BibleIndexOnboardingOverlay.swift`와
//  같은 패턴(`ViewModifier` + `extension View`, `ContentView`에 한 줄만
//  추가). "처음 설치하는 사람에게는 필요하지 않음" 요구사항은 두 겹으로
//  지킨다:
//  1) `UserSettingsStore.hasCompletedOnboarding`이 아직 꺼져 있으면(=온보딩을
//     아직 안 봄 = 방금 처음 설치함) 이 화면은 아예 관여하지 않는다.
//  2) 온보딩을 마치는 순간(`AppOnboardingOverlay.markCompleted`) 이미
//     `lastSeenAppVersion`을 지금 버전으로 채워 두므로, 온보딩 직후에도 이
//     화면의 "버전이 달라졌다" 조건 자체가 성립하지 않는다.
//
//  결과적으로 이 화면은 "온보딩을 이미 마친 사용자가, 이전과 다른 버전으로
//  앱을 실행했을 때"에만 뜬다 — 정확히 "업데이트 안내" 화면이 뜻하는 바다.
//

import SwiftUI

/// `ContentView`가 앱 시작 시 1회 붙이는 컨트롤러.
struct WhatsNewPresenter: ViewModifier {
    @State private var isPresented = false
    @State private var entry: WhatsNewEntry?

    func body(content: Content) -> some View {
        content
            .task {
                presentIfNeeded()
            }
            .sheet(isPresented: $isPresented, onDismiss: markSeen) {
                if let entry {
                    WhatsNewSheet(entry: entry, onDismiss: { isPresented = false })
                        #if os(macOS)
                        .frame(width: 420, height: 480)
                        #endif
                }
            }
    }

    private func presentIfNeeded() {
        let settings = UserSettingsStore.shared
        // 위 상단 주석 1) — 온보딩을 아직 안 마쳤으면(방금 처음 설치) 관여하지
        // 않는다.
        guard settings.hasCompletedOnboarding else { return }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let currentVersion, settings.lastSeenAppVersion != currentVersion else { return }

        guard let matched = WhatsNewContent.entry(for: currentVersion) else {
            // 이 버전에 대해 아직 등록된 안내 항목이 없으면(예: 안내 문구를
            // 준비하기 전에 빌드 번호만 올린 경우) 빈 "새로워진 점" 화면을
            // 보여주는 대신 조용히 버전만 기록하고 다음 실행부터는 다시
            // 검사하지 않는다.
            settings.lastSeenAppVersion = currentVersion
            return
        }
        entry = matched
        isPresented = true
    }

    private func markSeen() {
        UserSettingsStore.shared.lastSeenAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

extension View {
    /// `ContentView`에서 `.task` 하나 붙이듯 쓴다 — 실제 조건 판단/시트 표시는
    /// 전부 `WhatsNewPresenter` 안에 있다.
    func whatsNewOverlay() -> some View {
        modifier(WhatsNewPresenter())
    }
}

private struct WhatsNewSheet: View {
    let entry: WhatsNewEntry
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.22), Color.teal.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            VStack(spacing: 4) {
                Text("새로워진 점")
                    .font(.title2.weight(.bold))
                Text("버전 \(entry.version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(entry.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                            Text(item)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 28)
            }

            Button(action: onDismiss) {
                Text("확인")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 28)
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
