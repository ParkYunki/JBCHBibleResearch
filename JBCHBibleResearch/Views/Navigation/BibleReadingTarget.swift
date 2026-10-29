//
//  BibleReadingTarget.swift
//  JBCHBibleResearch
//
//  [relverse1 2026-10-29] 통합검색에서 구절을 누르면 macOS·iPadOS는 그 구절이 열린 성경 조회 새 창을 띄운다.
//  창: `WindowGroup(id: "bible-reading-at", for: BibleReadingTarget.self)`.
//  대상: "관련 성경구절", 관계 칩, "성경구절" 탭의 절 행, 인물·지명 본문 인용 링크, 아이패드의 메모 행.
//  아이폰과 다중 창을 쓸 수 없는 환경(`supportsMultipleWindows == false`)은 "성경 조회" 섹션 전환
//  (`AppNavigationRequest` + `BibleVerseNavigationRequest`)으로 대신한다.
//
//  같은 구절을 다시 누를 때 — 이미 열린 창을 앞으로(사용자 결정 2026-10-29)
//  - 공식 동작(`OpenWindowAction` 문서): "If the interface already has a window from the group that's presenting the specified value,
//    the system brings the window to the front. Otherwise, the system creates a new window."
//  - 같은 값만으로는 부족하다. 이 앱의 아이패드 설교 뷰어에서, 같은 값의 창을 닫은 뒤 같은 값으로 다시 열면 `openWindow`가
//    씬 이벤트 없이 버려진 기록이 있다(`SermonViewerTarget` 주석, 2026-10-03 `SceneDiag` 로그).
//  - 그래서 `SermonWindowTokenStore`와 같은 방식으로 토큰을 붙인다(`BibleReadingWindowTokenStore`).
//    · 같은 구절의 창이 떠 있거나 방금 요청 중(3초 이내)이면 같은 토큰을 돌려준다 → 같은 값 → 그 창이 앞으로 온다.
//      빠르게 두 번 눌러도 창이 둘로 늘지 않는다.
//    · 닫힌 뒤에는 새 토큰이다 → 새 값 → 항상 새 창이 열린다.
//    · 아이패드: "떠 있음" 기록을 재사용하기 직전에 그 창의 씬이 아직 연결돼 있는지 확인한다(`token(for:)` 주석).
//      앱 전환기에서 밀어 닫는 등 `onDisappear` 없이 창이 사라진 경우에도, 그 구절이 계속 같은 값으로 버려지지 않게 한다.
//  - 키는 처음 연 구절(책·장·절)이다. 바인딩 값은 앱이 쓰지 않으므로 창이 다른 장으로 옮겨도 처음 연 값 그대로다.
//    그래서 처음 연 구절을 다시 누르면, 다른 장으로 옮긴 그 창이 옮긴 위치 그대로 앞으로 온다.
//
//  `Codable`이라 창 복원(앱 재실행) 때 값(토큰 포함)이 그대로 돌아온다. 복원된 창이 나타나면 `windowDidAppear`가 그 토큰을
//  "떠 있음"으로 등록하므로, 같은 구절을 누르면 복원된 창이 앞으로 온다.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 창을 처음 연 구절 — `BibleReadingWindowTokenStore`의 키.
struct BibleReadingLocation: Codable, Hashable, Sendable {
    let bookId: Int
    let chapter: Int
    /// nil이면 장만 연다(`BibleReadingView.initialVerse`의 nil과 같다).
    let verse: Int?
}

/// "bible-reading-at" 창의 값. `token`은 `BibleReadingWindowTokenStore.token(for:)`에서 받는다.
struct BibleReadingTarget: Codable, Hashable, Sendable {
    let location: BibleReadingLocation
    let token: UUID
}

/// 열려 있는(또는 방금 열기를 요청한) 구절 창의 토큰 기록. `SermonWindowTokenStore`와 같은 규칙이다(그 타입 주석 참고).
/// - `token(for:)`: 같은 구절의 창이 떠 있거나(`windowDidAppear` 이후) 방금 요청 중(3초 이내)이면 그 토큰, 아니면 새 토큰.
/// - 요청 직후 3초가 지나도 창이 안 나타났다면(요청이 버려진 경우) 다음 누름은 새 토큰으로 다시 시도한다.
/// - 사전(Dictionary) 대신 배열을 쓰는 것도 `SermonWindowTokenStore`와 같다. 항목은 열린 창 수만큼이라 매우 적다.
@MainActor
final class BibleReadingWindowTokenStore {
    static let shared = BibleReadingWindowTokenStore()

    private struct Entry {
        let location: BibleReadingLocation
        let token: UUID
        var requestedAt: Date
        var isShown: Bool
        /// 이 토큰의 창이 올라간 씬 세션의 `UISceneSession.persistentIdentifier`(아이패드). 창 안의 `SceneSessionIdentifierReader`가
        /// 알려 준다. 아직 모르면 nil이고, 이때는 아래 `openSessions` 안전망만 적용된다. macOS는 항상 nil이다.
        var sessionID: String?
        /// [relverse2] 이 창을 열어 달라고 한 메인 창(`EnvironmentValues.mainWindowID`). [메인 창으로]가 이 창을 먼저 앞으로 가져온다.
        /// 같은 구절을 다른 메인 창에서 다시 누르면 그 창으로 바뀐다. 창 복원으로 나타난 창은 nil이다(그 창의 `@SceneStorage`가 대신한다).
        var originWindowID: String?
    }

    /// 요청 후 창이 나타나기를 기다려 주는 시간(이 안의 재요청은 같은 토큰).
    private static let pendingGrace: TimeInterval = 3

    private var entries: [Entry] = []

    private init() {}

    func token(for location: BibleReadingLocation, originWindowID: String? = nil) -> UUID {
        #if os(iOS)
        // [B-1] 재사용 전에 "떠 있음" 기록의 창이 실제로 살아 있는지 확인한다. 기준은 씬 연결이다.
        // - `UIApplication.connectedScenes`: "The app's currently connected scenes."
        // - 사용자가 창을 닫으면 씬 연결이 끊긴다. `UISceneSession` 문서: "destroying the session in response to the user closing
        //   the scene in the app switcher".
        // - `openSessions`("currently active or archived by the system")에 남아 있는지로 판정하지 않는 이유: 보관(archived)된 세션도
        //   포함하고, iPadOS 26에서는 사용자가 닫은 창도 "최근 닫은 창 복원"용으로 한동안 남는다는 개발자 포럼 보고가 있다.
        //   그러면 닫힌 창을 살아 있다고 보고 같은 토큰을 다시 줘서, 이 앱이 겪은 "같은 값이 버려짐"이 되풀이될 수 있다.
        // - 대가: 시스템이 백그라운드 창의 씬을 해제해 보관만 된 상태면 새 창이 하나 더 열린다(먹통보다 낫다).
        let connectedSessionIDs = Set(UIApplication.shared.connectedScenes.map { $0.session.persistentIdentifier })
        entries.removeAll { entry in
            guard entry.isShown, let sessionID = entry.sessionID else { return false }
            return !connectedSessionIDs.contains(sessionID)
        }
        // 세션 식별자를 아직 못 받은 기록을 위한 기존 안전망(`SermonWindowTokenStore`와 같다) — 열린 세션이 메인 하나뿐이면
        // 보조 창이 하나도 없으므로 "떠 있음" 기록은 모두 낡은 것이다.
        if UIApplication.shared.openSessions.count <= 1 {
            entries.removeAll { $0.isShown }
        }
        #endif
        let now = Date()
        // 오래 기다려도 안 뜬 요청 기록은 정리한다.
        entries.removeAll { !$0.isShown && now.timeIntervalSince($0.requestedAt) >= Self.pendingGrace }
        if let index = entries.firstIndex(where: { $0.location == location }) {
            let entry = entries[index]
            sceneDiagNote("성경 창 토큰 재사용 \(entry.token.uuidString.prefix(4)) (열림 \(entry.isShown))")
            // [relverse2] 가장 최근에 이 구절을 요청한 메인 창을 출처로 둔다(출처를 모르면 기존 값을 지우지 않는다).
            if let originWindowID {
                entries[index].originWindowID = originWindowID
            }
            return entry.token
        }
        let token = UUID()
        entries.append(Entry(location: location, token: token, requestedAt: now, isShown: false, originWindowID: originWindowID))
        sceneDiagNote("성경 창 토큰 새로 발급 \(token.uuidString.prefix(4))")
        return token
    }

    /// 창 내용이 나타났을 때(`onAppear`, `sessionID` nil)와 창의 씬 세션을 알아냈을 때(아이패드, `sessionID` 있음) 부른다.
    /// 두 호출의 순서는 정해져 있지 않아 어느 쪽이 먼저 와도 같은 결과가 되게 합친다.
    func windowDidAppear(location: BibleReadingLocation, token: UUID, sessionID: String? = nil) {
        if let index = entries.firstIndex(where: { $0.token == token }) {
            entries[index].isShown = true
            entries[index].requestedAt = Date()
            if let sessionID {
                entries[index].sessionID = sessionID
            }
        } else {
            // 창 복원 등으로 이 저장소를 거치지 않고 나타난 창.
            entries.append(Entry(location: location, token: token, requestedAt: Date(), isShown: true, sessionID: sessionID))
        }
    }

    /// [relverse2] 이 토큰의 창을 열어 달라고 한 메인 창. 모르면 nil.
    func originWindowID(for token: UUID) -> String? {
        entries.first(where: { $0.token == token })?.originWindowID
    }

    /// [relverse2] 이 토큰의 창이 올라간 씬 세션(iPadOS). 모르면 nil.
    func sessionID(for token: UUID) -> String? {
        entries.first(where: { $0.token == token })?.sessionID
    }

    func windowDidDisappear(token: UUID) {
        entries.removeAll { $0.token == token }
    }
}

/// "bible-reading-at" 창의 내용. 창마다 선택이 따로인 보조 창 규칙(`isPrimaryWindow: false`)을 따른다.
/// 책 ID를 찾지 못하면(복원된 값이 낡은 경우 등) 좌표 없이 연다. 장만 넘기면 `BibleReadingViewModel.init`이
/// 마지막으로 보던 다른 책에 그 장 번호를 붙이므로 장·절도 함께 버린다.
struct BibleReadingWindowContent: View {
    let target: BibleReadingTarget?

    /// 이 창(씬)에서 처음 연 구절의 조회 이력을 이미 남겼는지. `@SceneStorage`는 씬마다 따로이고, 시스템이 창 복원 때 함께 되살린다.
    /// 그래서 복원으로 다시 만들어진 창은 true라 이력을 또 남기지 않는다(`BibleReadingView.shouldRecordInitialVerseHistory`).
    @SceneStorage("bibleReadingAt.didRecordInitialHistory") private var didRecordInitialHistory = false
    /// [relverse2] 이 창을 연 메인 창의 식별자(`MainWindowRegistry`). 창 복원 뒤에도 [메인 창으로]가 같은 메인 창을 고르게 씬마다 저장한다.
    /// 빈 문자열 = 모름. iPadOS의 세션 식별자는 세션이 남아 있는 동안 유지되고, macOS의 창 식별자는 앱을 다시 켜면 맞지 않아
    /// (그때는 가장 최근 메인 창으로) 대신 고른다.
    @SceneStorage("bibleReadingAt.originWindowID") private var storedOriginWindowID = ""
    /// [relverse2] 진짜 `WindowGroup` 창은 `dismiss`가 기댈 프레젠테이션이 없어 `dismissWindow()`로 닫는다(`SermonContentWindowContent`·
    /// `OutlineQuickViewWindowContent`와 같다).
    @Environment(\.dismissWindow) private var dismissWindow

    /// 요청 출처 메인 창 — 토큰 저장소의 최신 값(같은 구절을 다른 메인 창에서 다시 누른 경우 포함)을 먼저, 없으면 씬 저장값.
    private var originWindowID: String? {
        if let target, let origin = BibleReadingWindowTokenStore.shared.originWindowID(for: target.token) {
            return origin
        }
        return storedOriginWindowID.isEmpty ? nil : storedOriginWindowID
    }

    /// [relverse2] 상단바(iPadOS)·도구 레일(macOS)의 [닫기]·[메인 창으로]. 닫힘은 `onDisappear` → `windowDidDisappear`로 토큰 기록이 지워진다
    /// (iPadOS는 `onDisappear`가 오지 않아도 `token(for:)`의 씬 연결 확인이 지운다).
    private var secondaryWindowActions: BibleSecondaryWindowActions {
        BibleSecondaryWindowActions(
            close: { dismissWindow() },
            showMainWindow: {
                // 메인 창이 앞으로 온 것이 확인된 뒤에만 닫는다(iPadOS는 대상 씬의 활성 알림을 기다린다). 실패·시간 초과면 남긴다.
                MainWindowActivator.showMainWindow(
                    preferredID: originWindowID,
                    requestingSessionID: target.flatMap { BibleReadingWindowTokenStore.shared.sessionID(for: $0.token) },
                    onConfirmed: { dismissWindow() }
                )
            },
            canShowMainWindow: MainWindowActivator.canShowMainWindow
        )
    }

    var body: some View {
        let location = target?.location
        let book = location.flatMap { BooksProvider.shared.book(id: $0.bookId) }
        BibleReadingView(
            initialBook: book,
            initialChapter: book == nil ? nil : location?.chapter,
            initialVerse: book == nil ? nil : location?.verse,
            isPrimaryWindow: false,
            // viewModel을 만드는 순간(`BibleReadingView`의 첫 `onAppear`)에만 불린다. 처음 한 번만 true를 돌려준다.
            shouldRecordInitialVerseHistory: {
                guard !didRecordInitialHistory else { return false }
                didRecordInitialHistory = true
                return true
            }
        )
        // [B-2] `.id(target)`은 두지 않는다(`SermonContentWindowContent`와 같다). 앱은 창 바인딩에 쓰지 않으므로 값은 창이
        // 만들어질 때 정해진 뒤 바뀌지 않는다. `openWindow(id:value:)`는 "creates a new window and passes a binding to the specified
        // value"(공식 문서)라 첫 렌더부터 값이 있고, nil은 값 없이 만들어진 창(복원 값을 못 읽은 경우 등)뿐이다.
        #if os(iOS)
        .background {
            if let target {
                SceneSessionIdentifierReader { sessionID in
                    BibleReadingWindowTokenStore.shared.windowDidAppear(
                        location: target.location, token: target.token, sessionID: sessionID
                    )
                }
            }
        }
        #endif
        .environment(\.bibleSecondaryWindowActions, secondaryWindowActions)
        .onAppear {
            if let target {
                BibleReadingWindowTokenStore.shared.windowDidAppear(location: target.location, token: target.token)
                // [relverse2] 요청 출처를 씬 저장소에 옮겨 둔다(창 복원 뒤 토큰 기록이 없어도 쓰도록).
                if let origin = BibleReadingWindowTokenStore.shared.originWindowID(for: target.token) {
                    storedOriginWindowID = origin
                }
            }
        }
        .onDisappear {
            if let target {
                BibleReadingWindowTokenStore.shared.windowDidDisappear(token: target.token)
            }
        }
    }
}

#if os(iOS)
/// [relverse2] `MainWindowRegistration`(메인 창 등록)도 쓰도록 `private`을 뗐다.
/// 이 뷰가 올라간 창의 씬 세션 식별자를 알려 준다. SwiftUI에는 뷰에서 자기 `UIScene`을 얻는 공개 API가 없어 UIKit 뷰를 하나 끼운다.
/// 근거(UIKit 문서): `UIView.didMoveToWindow()` "Tells the view that its window object changed.",
/// `UIView.window` → `UIWindow.windowScene`("The scene containing the window.") → `UIScene.session` →
/// `UISceneSession.persistentIdentifier`("A unique identifier that persists for the lifetime of the session.").
/// 창이 없어질 때(`window == nil`)는 알리지 않는다. 기록 정리는 `onDisappear`와 `token(for:)`의 씬 연결 확인이 맡는다.
struct SceneSessionIdentifierReader: UIViewRepresentable {
    let onResolve: (String) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.onResolve = onResolve
        return view
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {
        uiView.onResolve = onResolve
    }

    final class ReaderView: UIView {
        var onResolve: ((String) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let sessionID = window?.windowScene?.session.persistentIdentifier {
                onResolve?(sessionID)
            }
        }
    }
}
#endif

/// 구절 열기 동작. 각 화면이 환경값(`openWindow`, `supportsMultipleWindows`)을 넘겨 만든다.
@MainActor
struct BibleVerseOpener {
    static let windowID = "bible-reading-at"

    let openWindow: OpenWindowAction
    let supportsMultipleWindows: Bool
    /// [relverse2] 요청한 메인 창(`EnvironmentValues.mainWindowID`). 새 창의 [메인 창으로]가 이 창을 앞으로 가져온다.
    var originWindowID: String? = nil

    /// 아이폰은 항상 섹션 전환이다. 아이패드·맥은 다중 창을 쓸 수 있을 때만 새 창이다.
    private var opensInNewWindow: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone && supportsMultipleWindows
        #else
        return supportsMultipleWindows
        #endif
    }

    func open(bookId: Int, chapter: Int, verse: Int?) {
        if opensInNewWindow {
            let location = BibleReadingLocation(bookId: bookId, chapter: chapter, verse: verse)
            let token = BibleReadingWindowTokenStore.shared.token(for: location, originWindowID: originWindowID)
            openWindow(id: Self.windowID, value: BibleReadingTarget(location: location, token: token))
        } else {
            AppNavigationRequest.shared.request(.bibleReading)
            // `BibleVerseNavigationTarget.verse`는 옵셔널이 아니다. 절이 없으면 1절로 대신한다(`SearchView.bibleVerseRow`의 기존 처리와 같다).
            BibleVerseNavigationRequest.shared.request(bookId: bookId, chapter: chapter, verse: verse ?? 1)
        }
    }
}
