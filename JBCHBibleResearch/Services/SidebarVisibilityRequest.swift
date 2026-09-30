//
//  SidebarVisibilityRequest.swift
//  JBCHBibleResearch
//
//  말씀 요약 편집기를 열 때 바깥쪽 좌측 사이드바(`SidebarNavigationView`의 `columnVisibility`)를 접었다가,
//  편집이 끝나면 원래 상태로 되돌리기 위한 요청 채널.
//
//  ⚠️ `@FocusedValue`로 노출/구독하는 방식은 쓸 수 없다 — 구독하는 `BibleReadingContentView`가 자체 `.toolbar`를
//  가진 뷰인데, 이 조합이 과거 실기기 무한 루프 크래시의 원인이었다(`AppNavigationRequest.swift` 상단 주석 참고).
//  그래서 평범한 `Equatable` 값만 든 @Observable 싱글턴 + `.onChange` 구독을 쓴다.
//
//  복원 값을 따로 저장하는 이유: 무조건 다시 열면 편집 전부터 사용자가 접어 둔 사이드바까지 강제로 열린다.
//  `.hide`를 처리하는 쪽이 직전 실제 상태를 기록해 두고, `.restore`가 오면 그 값으로 되돌린다.
//

import Foundation
import Observation

@MainActor
@Observable
final class SidebarVisibilityRequest {
    static let shared = SidebarVisibilityRequest()

    enum Request: Equatable {
        case hide
        case restore
    }

    private(set) var pendingRequest: Request?
    /// `.hide` 처리 직전의 실제 표시 상태(true = 열려 있었음). 기본값 true는 hide를 처리한 적 없는 경우의 안전값이다.
    private(set) var wasVisibleBeforeHide: Bool = true

    private init() {}

    /// 말씀 요약 편집기를 여는 쪽(`BibleReadingContentView`)이 호출한다.
    func requestHide() { pendingRequest = .hide }

    /// 말씀 요약 편집기를 닫는 쪽이 호출한다.
    func requestRestore() { pendingRequest = .restore }

    /// `.hide`를 처리하는 쪽(`SidebarNavigationView`)이 사이드바를 접기 직전의 상태를 기록한다.
    func recordVisibilityBeforeHide(_ visible: Bool) { wasVisibleBeforeHide = visible }

    /// 소비한 쪽이 처리 후 반드시 비운다 — 안 비우면 같은 요청을 연달아 보낼 때 `.onChange`가 반응하지 않을 수 있다.
    func clear() { pendingRequest = nil }
}
