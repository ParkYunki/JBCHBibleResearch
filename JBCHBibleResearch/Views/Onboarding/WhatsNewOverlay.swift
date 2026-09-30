//
//  WhatsNewOverlay.swift
//  JBCHBibleResearch
//
//  앱 버전(`CFBundleShortVersionString`)이 지난 실행 때와 달라졌으면 1회,
//  `WhatsNewContent.swift`에 등록된 그 버전의 안내 항목을 보여주는 "새로워진 점" 화면.
//
//  `ViewModifier` + `extension View` 패턴(`AppOnboardingOverlay.swift`와 동일)이며,
//  처음 설치한 사용자에게는 뜨지 않도록 두 겹으로 막는다:
//  1) `hasCompletedOnboarding`이 꺼져 있으면(온보딩 전) 관여하지 않는다.
//  2) 온보딩 완료 시 `lastSeenAppVersion`이 이미 현재 버전으로 채워져 "버전이 달라짐"
//     조건이 성립하지 않는다.
//

import SwiftUI
#if DEBUG
import Observation
#endif

#if DEBUG
/// DEBUG 전용 — 설정의 "개발자" 탭이 이 값을 증가시키면 "새로워진 점"을 다시 띄운다.
/// 값 자체엔 의미가 없고 매번 바뀐다는 사실만 `.onChange`가 감지한다
/// (`AppOnboardingReplayRequest`와 같은 패턴).
@MainActor
@Observable
final class WhatsNewReplayRequest {
    static let shared = WhatsNewReplayRequest()

    private(set) var token: Int = 0

    private init() {}

    /// "새로워진 점 다시 보기" 버튼이 호출한다. 현재 버전의 `WhatsNewContent` 항목을
    /// 미리 보여주며, 등록된 항목이 없으면 `presentReplayPreview()`가 아무 일도 하지 않는다.
    func requestReplay() {
        token += 1
    }
}
#endif

/// `ContentView`가 앱 시작 시 1회 붙이는 컨트롤러.
struct WhatsNewPresenter: ViewModifier {
    /// "보여줄지"와 "뭘 보여줄지"를 `isPresented` + 옵셔널 `entry` 두 `@State`로 나누면,
    /// 실행 후 처음 여는 시트에서 콘텐츠 클로저가 오래된(nil) 스냅숏을 읽어 `if let`이
    /// 실패하고 `.frame`도 못 받은 빈 시트가 뜨는 문제가 있다. 단일 옵셔널
    /// `presentedEntry` + `.sheet(item:)`으로 합치면 클로저가 언랩된 값을 직접 받아
    /// 이 stale-read 지점이 없어진다.
    @State private var presentedEntry: WhatsNewEntry?
    #if DEBUG
    /// "새로워진 점 다시 보기"로 열린 미리보기 여부. 이 경우 `markSeen()`이
    /// `lastSeenAppVersion`을 건드리지 않아, 아직 이번 버전 안내를 못 본 상태에서
    /// 미리보기만 해도 다음 정식 실행의 안내가 사라지지 않는다.
    @State private var isReplayPreview = false
    #endif

    func body(content: Content) -> some View {
        content
            .task {
                presentIfNeeded()
            }
            #if DEBUG
            .onChange(of: WhatsNewReplayRequest.shared.token) { _, _ in
                presentReplayPreview()
            }
            #endif
            .sheet(item: $presentedEntry, onDismiss: markSeen) { entry in
                WhatsNewSheet(entry: entry, onDismiss: { presentedEntry = nil })
                    #if os(macOS)
                    .frame(width: 420, height: 480)
                    #endif
            }
    }

    private func presentIfNeeded() {
        let settings = UserSettingsStore.shared
        // 온보딩을 아직 안 마쳤으면(방금 처음 설치) 관여하지 않는다.
        guard settings.hasCompletedOnboarding else { return }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let currentVersion, settings.lastSeenAppVersion != currentVersion else { return }

        guard let matched = WhatsNewContent.entry(for: currentVersion) else {
            // 등록된 안내 항목이 없으면(문구 준비 전 빌드 번호만 올린 경우) 빈 화면 대신
            // 버전만 기록하고 넘어간다.
            settings.lastSeenAppVersion = currentVersion
            return
        }
        presentedEntry = matched
    }

    #if DEBUG
    private func presentReplayPreview() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let currentVersion, let matched = WhatsNewContent.entry(for: currentVersion) else { return }
        isReplayPreview = true
        presentedEntry = matched
    }
    #endif

    private func markSeen() {
        #if DEBUG
        // 개발자 미리보기 경로는 `lastSeenAppVersion`을 건드리지 않는다.
        if isReplayPreview {
            isReplayPreview = false
            return
        }
        #endif
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
