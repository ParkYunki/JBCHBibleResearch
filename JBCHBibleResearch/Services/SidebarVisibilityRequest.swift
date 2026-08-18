//
//  SidebarVisibilityRequest.swift
//  JBCHBibleResearch
//
//  [2026-08-12 신설] 사용자 요청 — "성경 구절 선택시 확대보기 오른쪽 옆 [말씀
//  요약]버튼 ... 왼쪽 사이드바 닫고." 말씀 요약 편집기를 열 때 macOS/iPadOS의
//  바깥쪽 좌측 사이드바(`SidebarNavigationView`가 갖고 있는 `columnVisibility`
//  로컬 `@State`)를 접었다가, 편집이 끝나면 원래 있던 상태로 되돌려야 한다.
//
//  ⚠️ [설계 근거 — AppNavigationRequest.swift와 완전히 같은 이유] 이 상태를
//  `@FocusedValue`로 직접 노출/구독하는 방식(예: `scrollSyncEnabled` 패턴)은
//  여기서 쓸 수 없다 — 구독하는 쪽(`BibleReadingContentView`)이 자체 `.toolbar`를
//  가진 뷰이기 때문이다. 바로 이 조합(툴바 있는 뷰 + `@FocusedValue` 구독)이
//  과거 `@FocusedValue(\.selectSection)`에서 실기기 무한 루프 크래시를 냈던
//  원인이었다(`AppNavigationRequest.swift` 상단 주석에 근본 원인 전체가 정리돼
//  있다 — 클로저 값은 Equatable이 아니라서 게시하는 쪽이 다시 그려질 때마다
//  "값이 바뀌었다"는 신호가 나가고, 그걸 툴바 있는 뷰가 받으면 툴바 재계산 →
//  레이아웃 무효화 루프에 빠진다). 그래서 `AppNavigationRequest`와 똑같이,
//  평범한 `Equatable` 값만 들고 있는 가벼운 `@Observable` 싱글턴 + `.onChange`
//  구독 조합으로 만든다.
//
//  [복원 값 저장 이유] "복원"이 단순히 "무조건 다시 연다"이면, 사용자가 편집을
//  시작하기 전부터 이미 손수 사이드바를 접어 둔 경우에도 편집을 마치자마자
//  강제로 열리는 부작용이 생긴다. 그래서 `.hide`를 실제로 처리하는 쪽
//  (`SidebarNavigationView`)이 처리 직전의 실제 상태를 이 싱글턴에 기록해 두고,
//  `.restore`가 오면 그 값 그대로 되돌린다.
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
    /// `.hide`를 처리하기 직전 실제 표시 상태(true = 열려 있었음). `.restore`가
    /// 오면 이 값으로 되돌린다. 기본값 true는 "한 번도 hide를 처리한 적이 없는"
    /// 이론상 도달하지 않는 상황을 위한 안전값일 뿐이다.
    private(set) var wasVisibleBeforeHide: Bool = true

    private init() {}

    /// 말씀 요약 편집기를 여는 쪽(`BibleReadingContentView`)이 호출한다.
    func requestHide() { pendingRequest = .hide }

    /// 말씀 요약 편집기를 닫는 쪽이 호출한다.
    func requestRestore() { pendingRequest = .restore }

    /// `.hide`를 처리하는 쪽(`SidebarNavigationView`)이, 실제로 사이드바를 접기
    /// 직전에 그 순간의 상태를 기록해 둔다.
    func recordVisibilityBeforeHide(_ visible: Bool) { wasVisibleBeforeHide = visible }

    /// 요청을 소비한 쪽이 처리 후 반드시 호출해 비운다 — `AppNavigationRequest.clear()`와
    /// 같은 이유(안 비우면 같은 요청을 연달아 보냈을 때 `.onChange`가 "값이
    /// 그대로"라고 판단해 반응하지 않을 수 있다).
    func clear() { pendingRequest = nil }
}
