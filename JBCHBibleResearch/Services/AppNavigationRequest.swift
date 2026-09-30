//
//  AppNavigationRequest.swift
//  JBCHBibleResearch
//
//  툴바를 가진 뷰(예: 관련 콘텐츠 시트의 "개요 화면 열기")가 앱 전체 내비게이션 섹션 전환을
//  요청하는 메모리 전용 싱글턴(`LastBiblePositionTracker`와 같은 원칙).
//
//  ⚠️ `@FocusedValue(\.selectSection)`을 툴바를 가진 뷰에서 읽으면 안 된다.
//  `.focusedSceneValue`가 게시하는 클로저는 `Equatable`이 아니라 게시하는 뷰가 다시 그려질
//  때마다 새 값으로 취급되고, 이것이 툴바 재계산 → 레이아웃 무효화 → 재계산 루프를 만들어
//  macOS에서 실행 직후 크래시가 났다(`ToolbarBridge.preferencesDidChange`). 툴바가 없는
//  `Commands`(AppCommands.swift)에서 읽는 것은 문제없다. 이 싱글턴은 `Equatable`인
//  `AppSection?`만 관찰하므로 해당 문제가 없다.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppNavigationRequest {
    static let shared = AppNavigationRequest()

    private(set) var requestedSection: AppSection?

    private init() {}

    /// 툴바를 가진 뷰(예: S1)가 다른 섹션으로 전환해 달라고 요청한다.
    func request(_ section: AppSection) {
        requestedSection = section
    }

    /// 요청을 소비한 쪽(SidebarNavigationView/PhoneTabView)이 처리 후 반드시 비운다.
    /// 안 비우면 같은 섹션을 다시 요청해도 `.onChange`가 값 변화를 감지하지 못한다.
    func clear() {
        requestedSection = nil
    }
}
