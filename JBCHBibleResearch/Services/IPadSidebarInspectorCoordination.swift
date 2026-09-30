//
//  IPadSidebarInspectorCoordination.swift
//  JBCHBibleResearch
//
//  아이패드 성경 조회 화면에서 사이드바와 인스펙터가 동시에 열려 있지 않도록 조율한다.
//  한쪽을 열면 다른 쪽을 닫기만 하며, 닫힌 뒤 자동 복원은 하지 않는다(수동으로만 다시 연다).
//  `SidebarVisibilityRequest`와 달리 복원 계약이 없다.
//
//  아이패드 전용: 사용 지점(`BibleReadingView`의 `isIPad`, `SidebarNavigationView`의 `isIPadIdiom`)에서만
//  아이패드를 걸러 이 싱글턴을 건드린다. 타입 자체는 플랫폼 중립이지만 아이폰/macOS에서는 값을 바꾸거나
//  읽지 않아 항상 비활성이다.
//
//  "닫기"는 각 뷰가 상대방의 표시 상태를 관찰하다가 자신의 로컬 상태만 닫으면 된다. 반면 "사이드바 열기"는
//  `columnVisibility`를 가진 `SidebarNavigationView`에 명령을 전달해야 하므로, 매번 증가하는 카운터를 쓴다
//  (`SearchResultsPopRequest.token`과 같은 방식 — 같은 값 재요청 문제가 없고 별도 `clear()`도 필요 없다).
//
//  ⚠️ `AppNavigationRequest`/`SidebarVisibilityRequest`와 동일한 이유로 `@FocusedValue` 대신
//  plain-Equatable 싱글턴 + `.onChange` 구독을 쓴다(툴바를 가진 뷰가 `@FocusedValue`를 구독하면
//  실기기에서 무한 루프 크래시가 난다).
//

import Foundation
import Observation

@MainActor
@Observable
final class IPadSidebarInspectorCoordination {
    static let shared = IPadSidebarInspectorCoordination()

    /// `SidebarNavigationView`가 `columnVisibility`를 바꿀 때마다(사이드바 열기 명령, 좌상단 버튼,
    /// 스와이프 등 경로 무관) 최신값을 반영한다.
    private(set) var isSidebarVisible: Bool = true

    /// `BibleReadingContentView`가 `isRelatedContentPresented`(관련 콘텐츠 인스펙터)를 바꿀 때마다
    /// 최신값을 반영한다. 말씀 요약 편집기가 인스펙터 자리를 쓰는 경우는 `SidebarVisibilityRequest`의
    /// 자동 복원 계약을 따르므로 여기 포함하지 않는다.
    private(set) var isInspectorVisible: Bool = false

    /// 트레일링 아이콘 그룹의 "사이드바 열기" 버튼이 호출한다. 증가할 때마다 `SidebarNavigationView`의
    /// `.onChange`가 `columnVisibility = .all`로 바꾼다.
    private(set) var showSidebarRequestToken: Int = 0

    private init() {}

    func reportSidebarVisibility(_ visible: Bool) {
        isSidebarVisible = visible
    }

    func reportInspectorVisibility(_ visible: Bool) {
        isInspectorVisible = visible
    }

    func requestShowSidebar() {
        showSidebarRequestToken += 1
    }
}
