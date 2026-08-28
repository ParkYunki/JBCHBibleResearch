//
//  SearchResultsPopRequest.swift
//  JBCHBibleResearch
//
//  [2026-08-26 신설] 사용자 재보고 — "검색결과에서 성경구절 클릭 → 다시
//  검색해도 검색결과가 안 보임"이 재빌드 후에도 재현됨. 같은 날짜에
//  `SidebarNavigationView.detailNavigationPath`로 한 번 고쳤던 건 "왼쪽
//  사이드바 상단 검색창"(`submitSidebarSearch()`)에서 다시 검색하는 경로
//  하나뿐이었다 — 그런데 검색은 그 경로 말고도 `SearchView` 자신의
//  `.searchable` 검색창(엔터 → `.onSubmit(of: .search)` →
//  `SearchViewModel.searchImmediately()`, `SearchView.swift` 참고)으로도
//  실행할 수 있고, macOS/iPadOS의 `NavigationSplitView`에서는 이 검색창이
//  `NavigationStack` 툴바에 붙어 있어 성경 조회 화면이 push된 상태에서도
//  계속 입력·제출이 가능하다 — 이 경로로 다시 검색하면 `detailNavigationPath`를
//  건드리는 코드가 전혀 실행되지 않아 같은 증상이 그대로 남아 있었다.
//
//  기존 두 코드 경로(사이드바 검색창 / SearchView 자체 검색창)가 최종적으로
//  전부 모이는 유일한 지점은 `SearchViewModel.searchImmediately()`다 — 그래서
//  거기 한 곳에서만 이 신호를 보내고, `SidebarNavigationView`가 그 신호를
//  받아 `detailNavigationPath`를 비운다. 이렇게 하면 앞으로 검색 진입점이
//  하나 더 생기더라도(예: 다른 화면에서의 검색 단축키) 똑같이 자동으로
//  커버된다 — 진입점마다 pop 로직을 따로 심어야 했던 기존 방식보다 더
//  근본적인 위치의 수정이다.
//
//  `AppNavigationRequest`/`SidebarSearchRequest`와 같은 원칙(가벼운 메모리
//  전용 `@Observable` 싱글턴, `.focusedSceneValue` 클로저 게시는 툴바를 가진
//  뷰에서 크래시 전례가 있어 쓰지 않음 — `AppNavigationRequest.swift` 상단
//  주석 참고)을 따르되, 가지고 다니는 값 자체는 "정보"가 아니라 "이벤트
//  발생 여부"라서 두 파일처럼 `nil`/`clear()`가 필요한 옵셔널 값 대신 매번
//  값이 바뀌는 걸 보장하는 증가 카운터를 쓴다 — 같은 검색어로 다시 검색해도
//  (`AppNavigationRequest.clear()` 주석이 설명하는 "값이 그대로라 `.onChange`가
//  반응 안 함" 문제) 카운터는 항상 증가하므로 그 문제 자체가 성립하지 않고,
//  그래서 소비 후 되돌리는 `clear()`도 필요 없다.
//
//  [2026-08-26 참고] `Int.max` 근처까지 증가할 일은 실질적으로 없다(사용자가
//  평생 검색을 그만큼 반복할 수 없음) — 오버플로 방지용 wrap-around 처리는
//  근거 없는 방어 코드라 넣지 않았다.
//

import Foundation
import Observation

@MainActor
@Observable
final class SearchResultsPopRequest {
    static let shared = SearchResultsPopRequest()

    private(set) var token: Int = 0

    private init() {}

    /// `SearchViewModel.searchImmediately()`가 실제로 새 검색을 시작할 때마다
    /// 호출한다 — "다시 검색했다"는 사실만 알리면 되므로 인자가 없다.
    func requestPop() {
        token += 1
    }
}
