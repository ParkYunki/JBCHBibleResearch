//
//  AppNavigationRequest.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설, 크래시 수정] S1의 관련 콘텐츠 시트에서 "개요 화면 열기"를
//  누르면 앱 전체 내비게이션을 개요(S8/S9) 섹션으로 전환해야 하는데, 처음엔
//  `@FocusedValue(\.selectSection)`(AppCommands.swift가 메뉴바 명령에 쓰는 것과
//  같은 메커니즘)를 재사용했다. 그런데 이 값을 **툴바를 가진 뷰**
//  (`BibleReadingContentView`) 안에서 읽자 실기기(macOS)에서 앱 실행 직후
//  크래시가 났다 — 크래시 로그가 명확히 `ToolbarBridge.preferencesDidChange` →
//  `Toolbar.LocationStorage.updatedVendedItems(newFocusedValues:)` → 레이아웃
//  무한 재요청을 가리켰다. 원인: `.focusedSceneValue(\.selectSection, closure)`는
//  클로저(함수 값)를 게시하는데, 함수는 `Equatable`이 아니라서 게시하는 뷰
//  (`SidebarNavigationView`)가 다시 그려질 때마다(다른 이유로) 매번 "새 값"으로
//  취급된다. 그 값을 읽는 쪽이 툴바를 가진 뷰라면, 매번 "포커스 값이 바뀌었다"는
//  신호가 툴바 재계산을 유발하고, 툴바 재계산이 다시 레이아웃 무효화를 유발해
//  루프에 빠진다(AppCommands.swift처럼 툴바가 없는 `Commands` 구조체에서 읽는
//  건 이 문제가 없다 — 지금까지 문제없이 동작해 온 이유).
//
//  그래서 툴바를 가진 뷰가 섹션 전환을 "요청"할 때는 이 대신 쓴다 — 평범한
//  `AppSection?` 값(Equatable)만 관찰하므로 클로저 게시 특유의 문제가 없다.
//  `LastBiblePositionTracker`와 같은 원칙(가벼운 메모리 전용 싱글턴, 영구 저장
//  불필요)의 새 싱글턴이다.
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

    /// 요청을 소비한 쪽(SidebarNavigationView/PhoneTabView)이 처리 후 반드시
    /// 호출해 비운다 — 안 비우면 다음에 우연히 같은 섹션을 다시 요청했을 때
    /// `.onChange`가 "값이 그대로"라고 판단해 반응하지 않을 수 있다.
    func clear() {
        requestedSection = nil
    }
}
