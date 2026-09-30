//
//  SidebarSearchRequest.swift
//  JBCHBibleResearch
//
//  사이드바 상단 검색창(`SidebarNavigationView`)이 검색어를 "요청"하면, 본문의 `SearchView`/`SearchViewModel`이
//  그 값을 읽어 검색을 실행한다.
//
//  `AppNavigationRequest.swift`와 같은 이유로 평범한 Equatable 값을 담는 @Observable 싱글턴 + `.onChange`를 쓴다
//  (`.focusedSceneValue`에 클로저를 게시하고 툴바를 가진 뷰에서 읽으면 실기기 크래시 전례가 있다).
//

import Foundation
import Observation

@MainActor
@Observable
final class SidebarSearchRequest {
    static let shared = SidebarSearchRequest()

    private(set) var pendingQuery: String?

    private init() {}

    /// 사이드바 상단 검색창이 검색을 요청한다. 호출부가 2글자 이상인지 검증한 뒤에만 부른다.
    func request(_ query: String) {
        pendingQuery = query
    }

    /// 소비한 쪽(`SearchView`)이 처리 후 반드시 비운다 — 안 비우면 같은 검색어를 다시 요청해도
    /// `.onChange`가 "값이 그대로"라고 판단해 반응하지 않을 수 있다.
    func clear() {
        pendingQuery = nil
    }
}
