//
//  IPadSidebarInspectorCoordination.swift
//  JBCHBibleResearch
//
//  [2026-08-27 신설] 사용자 요청 — "iOS 아이패드 - 성경조회 ... 아이패드에서
//  인스펙터 창과 사이드바가 동시에 나타나는 일이 없도록 할것. / 사이드바를
//  열면 - 인스펙터 창이 열려있는 경우 - 인스펙터가 닫히고 사이드바가 열림 /
//  인스펙터 창을 열면 - 사이드바가 열려있는경우 - 사이드 바가 닫히고 인스펙터
//  창이 열림." + "사이드바를 닫을 경우 아이콘 순서는 사이드바, 히스토리,
//  인스펙터 창 순서로 할 것"(성경 조회 화면 상단 오른쪽 아이콘 그룹에 사이드바를
//  다시 여는 아이콘 추가).
//
//  [닫힌 뒤 자동 복원 여부 — 사용자 확인, 이번 세션 AskUserQuestion]
//  "아이패드에서 인스펙터 창이 사이드바를 밀어내고 열렸다가, 나중에 인스펙터
//  창을 닫으면 — 그때 밀려났던 사이드바가 자동으로 다시 열려야 하나요, 아니면
//  사용자가 사이드바 버튼을 눌러야만 다시 열려야 하나요?" → "수동으로만 열림".
//  즉 이 조율에는 `SidebarVisibilityRequest`(말씀 요약 편집용, "닫기 직전 상태를
//  기억했다가 편집이 끝나면 자동 복원") 같은 복원 계약이 전혀 없다 — 한쪽을
//  열면 다른 쪽을 닫기만 하고, 그걸로 끝이다.
//
//  [적용 범위 — 아이패드 전용] 사용자가 이 요청을 "iOS 아이패드 - 성경조회"
//  섹션에 명시했다. 아이폰은 애초에 이 사이드바(`NavigationSplitView`/
//  `SidebarNavigationView`) 자체를 쓰지 않고(`PhoneTabView`를 대신 쓴다),
//  macOS는 같은 `SidebarNavigationView`/`columnVisibility`를 쓰지만 이번
//  요청에서 언급되지 않았으므로 이 조율 대상에서 뺀다 — 실제 사용 지점
//  (`BibleReadingView.swift`의 `isIPad`, `SidebarNavigationView.swift`의
//  `isIPadIdiom`)에서 아이패드만 걸러 이 싱글턴을 건드리게 한다. 즉 이 타입
//  자체는 플랫폼 중립이지만, macOS/아이폰 쪽에서는 아무도 값을 바꾸지도
//  읽지도 않아 실질적으로 항상 비활성 상태다.
//
//  [명령이 한쪽(사이드바 열기)에만 있는 이유] 사이드바 "닫기"와 인스펙터
//  "닫기"는 각 뷰가 상대방의 표시 상태(`isSidebarVisible`/`isInspectorVisible`)를
//  관찰하다가 스스로(자기 자신이 소유한 로컬 상태만) 닫으면 된다 — 다른 뷰의
//  로컬 상태를 대신 바꿔줄 필요가 없다. 반면 "사이드바 열기"는 트레일링 아이콘
//  그룹의 새 버튼이 `BibleReadingContentView`(사이드바를 소유하지 않음) 쪽에
//  있어서, `columnVisibility`를 실제로 들고 있는 `SidebarNavigationView`에게
//  "열어 달라"고 명령을 보낼 방법이 하나 필요하다 — `SearchResultsPopRequest.
//  token`과 같은 원리로, 매번 증가하는 카운터를 쓴다(같은 가능성 있는 값
//  재요청 문제 없음, 소비 후 별도 `clear()`도 필요 없음).
//
//  ⚠️ [패턴] `AppNavigationRequest`/`SidebarVisibilityRequest`와 동일한 이유로
//  `@FocusedValue` 대신 plain-Equatable 싱글턴 + `.onChange` 구독을 쓴다(툴바를
//  가진 뷰가 `@FocusedValue`를 구독하면 실기기 무한 루프 크래시가 났던 전례,
//  두 파일 상단 주석 참고).
//

import Foundation
import Observation

@MainActor
@Observable
final class IPadSidebarInspectorCoordination {
    static let shared = IPadSidebarInspectorCoordination()

    /// `SidebarNavigationView`가 `columnVisibility`를 바꿀 때마다(경로 무관 —
    /// 이 파일의 새 "사이드바 열기" 명령이든, 기존 좌상단 버튼이든, 스와이프든)
    /// 최신값을 그대로 반영해 둔다.
    private(set) var isSidebarVisible: Bool = true

    /// `BibleReadingContentView`가 `isRelatedContentPresented`(관련 콘텐츠
    /// 인스펙터)를 바꿀 때마다 최신값을 반영해 둔다. 말씀 요약 편집기가 이
    /// 인스펙터 자리를 대신 쓰는 경우는 여기 포함하지 않는다 — 그건
    /// `SidebarVisibilityRequest`의 별도 자동 복원 계약을 그대로 쓰는 기존
    /// 동작이라 이 조율과 섞지 않는다(위 상단 주석 참고).
    private(set) var isInspectorVisible: Bool = false

    /// 트레일링 아이콘 그룹의 "사이드바 열기" 버튼이 호출한다. 증가할 때마다
    /// `SidebarNavigationView`의 `.onChange`가 반응해 `columnVisibility = .all`로
    /// 바꾼다.
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
