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
#if DEBUG
import Observation
#endif

#if DEBUG
/// [2026-09-03 신설] 사용자 요청 — "설정.. 개발자 메뉴에 '새로워진 점'을
/// 다시볼 수 있도록 기능을 추가할 것." `AppOnboardingReplayRequest`
/// (AppOnboardingOverlay.swift)와 완전히 같은 "이벤트가 일어났다" 증가 카운터
/// 싱글턴 패턴을 그대로 따랐다 — 값 자체엔 의미가 없고 매번 바뀐다는 사실만
/// `.onChange`가 감지하면 된다. DEBUG 빌드에서만 존재하므로 배포 빌드엔 이
/// 타입 자체가 포함되지 않는다.
@MainActor
@Observable
final class WhatsNewReplayRequest {
    static let shared = WhatsNewReplayRequest()

    private(set) var token: Int = 0

    private init() {}

    /// "개발자" 탭의 "새로워진 점 다시 보기" 버튼이 호출한다. 항상 현재 버전
    /// (`CFBundleShortVersionString`)의 `WhatsNewContent` 항목을 미리 보여준다
    /// — 그 버전에 등록된 항목이 없으면(예: 아직 이번 버전 문구를 안 적어 둔
    /// 경우) 아래 `WhatsNewPresenter.presentReplayPreview()`가 조용히 아무
    /// 일도 하지 않는다.
    func requestReplay() {
        token += 1
    }
}
#endif

/// `ContentView`가 앱 시작 시 1회 붙이는 컨트롤러.
struct WhatsNewPresenter: ViewModifier {
    /// [2026-09-03 변경] 사용자가 "새로워진 점 다시 보기"를 앱 실행 뒤 처음
    /// 눌렀을 때만 빈 시트가 뜨고, 두 번째부터는 정상적으로 뜨는 걸 직접
    /// 재현했다 — "이 프레젠터의 특정 시트가 이번 실행에서 처음 준비되는
    /// 순간에만 실패하고, 그 다음부터는 잘 된다"는 패턴은 이번 세션에서 이미
    /// 두 번 만난 것과 같은 종류다(`PhraseNoteEditorPopover.swift` 2026-08-11
    /// 15차 수정, `VerseZoomView.autoPresentPersonalNoteEditor` — 둘 다 데이터
    /// 값과 "열어라" 신호를 같은 트랜잭션에서 같이 바꾸고, 그 값을 `let`으로
    /// (혹은 이 경우처럼 별도의 옵셔널 `@State` + 별도의 `Bool` 두 상태로)
    /// 들고 있다가 시트/팝오버 콘텐츠 클로저가 그 값을 처음 읽는 순간에만
    /// 방금 커밋된 값이 아니라 그 이전 스냅숏을 읽는 문제였다). 두 사례 모두
    /// 고친 방법은 "값을 얼려서 들고 있지 않고, 프레젠테이션이 실제로 일어나는
    /// 그 순간에 다시 읽게" 만드는 것이었다.
    ///
    /// 여기서는 `isPresented: Bool` + `entry: WhatsNewEntry?` 두 개의 별도
    /// `@State`로 "보여줄지"와 "뭘 보여줄지"를 따로 관리하던 것이 바로 그
    /// 위험한 모양이다 — `.sheet(isPresented:)`는 그 콘텐츠 클로저가 실제로
    /// 평가되는 시점에 `entry`를 다시 읽긴 하지만, 이 프레젠터의 `.sheet`가
    /// 이번 실행에서 "처음" 열리는 바로 그 순간엔 SwiftUI가 오래된(nil)
    /// 스냅숏을 읽어 `if let entry`가 실패하고 — 그 결과 크기 지정(`.frame`)도
    /// 못 받은 빈 콘텐츠만 시트로 뜬다. `WhatsNewEntry`가 이미 `Identifiable`
    /// 이므로, 이 두 상태를 "보여줄 항목이 있으면 그게 곧 표시 여부"인 단일
    /// 옵셔널 `presentedEntry`로 합치고 `.sheet(isPresented:)` 대신
    /// `.sheet(item:)`을 쓰도록 바꿨다 — `.sheet(item:)`의 콘텐츠 클로저는
    /// 언랩된 값 자체를 인자로 직접 받으므로("아직 nil인 별도 값을 클로저 밖에서
    /// 다시 읽어와 언랩"하는 단계 자체가 없어), 애초에 이 클래스의 stale-read가
    /// 일어날 지점이 없다.
    @State private var presentedEntry: WhatsNewEntry?
    #if DEBUG
    /// [2026-09-03 신설] "개발자" 탭의 "새로워진 점 다시 보기"로 열린 것인지
    /// 표시한다 — `AppOnboardingPresenter.isReplayPreview`와 같은 이유. 이
    /// 경로로 열렸을 때는 `markSeen()`이 `lastSeenAppVersion`을 건드리지
    /// 않게 막는다 — 미리보기일 뿐인데 이 값이 조용히 현재 버전으로 채워지면
    /// (아직 실제로 이번 버전 안내를 못 본 사용자 계정 상태에서 개발자가
    /// 미리보기만 했는데) 다음 정식 실행에서 정작 "새로워진 점"이 안 뜨는
    /// 부작용이 생긴다.
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
        // 위 `isReplayPreview` 상단 주석 참고 — 개발자 미리보기 경로는
        // `lastSeenAppVersion`을 건드리지 않고 조용히 끝낸다.
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
