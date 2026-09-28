import SwiftUI
import AppKit

//
//  PersonSeedEditorApp.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] 앱 진입점. `Package.swift`/`RepoPaths.swift` 상단
//  주석 참고 — 메인 앱(JBCHBibleResearch)과 완전히 분리된 별도 macOS
//  앱으로, `swift run`으로 실행한다.
//
//  [2026-09-16 추가] 사용자 보고 — "실행 후 수정 입력 자체가 안 됨"(창은
//  뜨는데 텍스트 필드를 클릭해서 타이핑해도 반응이 없음). 원인 — Xcode가
//  만드는 정식 .app 번들과 달리 `swift run`으로 띄운 실행 파일은 macOS가
//  "일반 전면 앱"으로 자동 활성화해주지 않는다(별도 Info.plist/번들
//  식별자가 없는 raw 실행 파일이라 기본 활성화 정책이 다름) — 창은
//  화면에 보여도 실제로 키보드 포커스(key window)를 받지 못해 입력이
//  전혀 씹히는 것으로 보이는, `swift run` + SwiftUI macOS 앱의 잘 알려진
//  문제다. `AppDelegate`에서 앱 실행이 끝나는 시점에 명시적으로
//  `.regular`(일반 앱) 정책을 지정하고 `activate(ignoringOtherApps:)`를
//  호출해 강제로 전면에 올리고 키보드 포커스를 받게 한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PersonSeedEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PersonSeedStore()

    var body: some Scene {
        WindowGroup("PersonSeed 편집기") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
