//
//  SearchResultsPopRequest.swift
//  JBCHBibleResearch
//
//  검색을 다시 실행할 때 `SidebarNavigationView`가 `detailNavigationPath`를 비우도록
//  (성경 조회 화면 등을 pop) 알리는 신호. 사이드바 검색창과 `SearchView` 자체
//  `.searchable` 검색창 모두 `SearchViewModel.searchImmediately()`로 모이므로 그 한
//  곳에서만 `requestPop()`을 보내, 검색 진입점이 늘어도 자동으로 커버된다.
//
//  `AppNavigationRequest`/`SidebarSearchRequest`와 같은 메모리 전용 `@Observable`
//  싱글턴 원칙을 따른다(`.focusedSceneValue` 클로저 게시는 툴바를 가진 뷰에서 크래시
//  전례가 있어 쓰지 않음). 다만 값이 "정보"가 아니라 "이벤트 발생 여부"라 옵셔널 +
//  `clear()` 대신 증가 카운터를 쓴다 — 같은 검색어로 다시 검색해도 값이 항상 바뀌어
//  `.onChange`가 반응하므로 소비 후 되돌릴 필요가 없다. `Int.max` 오버플로는
//  현실적으로 일어나지 않아 별도 처리하지 않는다.
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
