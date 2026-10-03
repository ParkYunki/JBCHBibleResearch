//
//  SceneDiagnostics.swift
//  JBCHBibleResearch
//
//  [임시 진단 — DEBUG + iOS/iPadOS 전용] 설교 "뷰어" 버튼이 가끔 먹통이 되는 문제(2026-10-03 보고)를 추적하기 위한 로그.
//  `openWindow`가 새 씬(창)을 만드는지, 이미 있는 씬을 앞으로 가져오기만 하는지, 닫은 뒤 씬이 실제로 사라지는지를
//  Xcode 콘솔의 "[SceneDiag]" 줄로 보여 준다. 동작은 바꾸지 않는다. 원인을 찾으면 이 파일과 호출부(`JBCHBibleResearchApp.init`,
//  `SermonContentWindowContent`, `SermonViewerView`의 `SceneDiag` 줄)를 함께 지운다.
//
//  읽는 법: 뷰어 버튼을 누른 직후
//   - `willConnect`가 찍히면 새 씬이 만들어진 것 → 정상.
//   - `didActivate`만 찍히면(기존 씬을 앞으로) 이미 열려 있던 뷰어 씬이 있다는 뜻 → 가려진 옛 씬 문제.
//   - 아무 줄도 안 찍히면 `openWindow` 요청이 씬 단계까지 가지 못한 것 → OS/SwiftUI 쪽 문제 가능성.
//  뷰어의 X 버튼 뒤에는 `didDisconnect`가 찍혀야 씬이 정리된 것이다.
//

#if DEBUG && os(iOS)
import UIKit

@MainActor
enum SceneDiag {
    private static var observers: [NSObjectProtocol] = []

    /// 앱 시작 시 한 번만 호출한다.
    static func start() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [
            UIScene.willConnectNotification, UIScene.didDisconnectNotification,
            UIScene.didActivateNotification, UIScene.willDeactivateNotification,
            UIScene.willEnterForegroundNotification, UIScene.didEnterBackgroundNotification,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                // 큐가 메인이라 메인 액터 위에서 불린다(UIKit 객체 접근을 위해 명시).
                MainActor.assumeIsolated {
                    guard let scene = note.object as? UIScene else { return }
                    log(note.name.rawValue, scene)
                }
            }
            observers.append(token)
        }
        print("[SceneDiag] 시작 — 씬 알림 구독")
    }

    /// 뷰어/닫기 등 앱 코드 쪽 이벤트도 같은 형식으로 남긴다.
    static func note(_ message: String) {
        let sessions = UIApplication.shared.openSessions.count
        print("[SceneDiag] \(message) · 열린 세션 \(sessions)")
    }

    private static func log(_ event: String, _ scene: UIScene) {
        let short = event.replacingOccurrences(of: "UISceneWillConnectNotification", with: "willConnect")
            .replacingOccurrences(of: "UISceneDidDisconnectNotification", with: "didDisconnect")
            .replacingOccurrences(of: "UISceneDidActivateNotification", with: "didActivate")
            .replacingOccurrences(of: "UISceneWillDeactivateNotification", with: "willDeactivate")
            .replacingOccurrences(of: "UISceneWillEnterForegroundNotification", with: "willEnterForeground")
            .replacingOccurrences(of: "UISceneDidEnterBackgroundNotification", with: "didEnterBackground")
        let id = String(scene.session.persistentIdentifier.prefix(6))
        let title = scene.title ?? "-"
        let sessions = UIApplication.shared.openSessions.count
        print("[SceneDiag] \(short) · 씬 \(id) · 제목 \"\(title)\" · state \(scene.activationState.rawValue) · 열린 세션 \(sessions)")
    }
}
#endif

/// 호출부에서 `#if` 없이 쓰는 진단 로그 — DEBUG+iOS가 아니면 아무것도 하지 않는다.
@MainActor
func sceneDiagNote(_ message: String) {
    #if DEBUG && os(iOS)
    SceneDiag.note(message)
    #endif
}
