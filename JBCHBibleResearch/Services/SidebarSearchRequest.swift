//
//  SidebarSearchRequest.swift
//  JBCHBibleResearch
//
//  [2026-08-18 신설] 사용자 요청 — "왼쪽 사이드바 맨 위 상단 검색기능 : 버튼이
//  아니라 검색 텍스트박스+버튼으로 배치 : 두글자이상 입력후 검색 버튼을
//  누르면(또는 엔터키) 오른쪽 메인영역에 검색결과가 나타날 수 있도록." 사이드바
//  (`SidebarNavigationView`, 툴바를 가진 뷰)가 검색어를 "요청"하면, 본문 영역의
//  `SearchView`/`SearchViewModel`이 그 값을 읽어 검색을 실행한다.
//
//  `AppNavigationRequest.swift` 상단 주석과 완전히 같은 이유로 이 방식(평범한
//  Equatable 값을 담는 @Observable 싱글턴 + `.onChange`)을 쓴다 —
//  `.focusedSceneValue`에 클로저를 게시하는 방식은 툴바를 가진 뷰에서 읽으면
//  실기기 크래시로 이어진 전례가 있다(그 파일 주석 참고). 여기서는 애초에
//  `@FocusedValue`를 쓸 필요도 없다 — `SidebarNavigationView`가 이미
//  `selection`을 직접 들고 있어 그 값을 바로 `.search`로 바꾸고, 검색어만 이
//  싱글턴으로 전달하면 된다.
//

import Foundation
import Observation

@MainActor
@Observable
final class SidebarSearchRequest {
    static let shared = SidebarSearchRequest()

    private(set) var pendingQuery: String?

    private init() {}

    /// 사이드바 상단 검색창이 "검색해 달라"고 요청한다 — 호출부(`SidebarNavigationView`)가
    /// 이미 2글자 이상인지 검증한 뒤에만 부른다.
    func request(_ query: String) {
        pendingQuery = query
    }

    /// 요청을 소비한 쪽(`SearchView`)이 처리 후 반드시 호출해 비운다 — 안 비우면
    /// 다음에 우연히 같은 검색어를 다시 요청했을 때 `.onChange`가 "값이 그대로"라고
    /// 판단해 반응하지 않을 수 있다(`AppNavigationRequest.clear()`와 같은 이유).
    func clear() {
        pendingQuery = nil
    }
}
