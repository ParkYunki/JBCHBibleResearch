//
//  OutlineNavigationRequest.swift
//  JBCHBibleResearch
//
//  개요 화면으로 메인 내비게이션을 전환하되, 책/장까지 미리 선택된 채로 에디터 화면(`OutlineBookBulkEditView`)에
//  진입시키는 요청. `AppNavigationRequest`는 `AppSection`만 다루므로 트리 선택 상태(`OutlineTreeSelection`)를
//  실어 나르는 별도 싱글턴을 둔다.
//
//  `AppNavigationRequest`/`SidebarVisibilityRequest`와 같은 패턴이다 — 메모리 전용 싱글턴이 plain Equatable 값을
//  관찰한다(`@FocusedValue` 클로저는 Equatable이 아니라 툴바를 가진 뷰에서 읽으면 실기기 크래시가 난다).
//

import Foundation
import Observation

@MainActor
@Observable
final class OutlineNavigationRequest {
    static let shared = OutlineNavigationRequest()

    private(set) var requestedSelection: OutlineTreeSelection?

    private init() {}

    /// `ChapterRelatedContentPanel`의 "개요 화면 열기" 버튼이 호출한다 — 지금 성경 조회 화면이 보고 있는 책/장을 넘긴다.
    /// 대입을 `DispatchQueue.main.async`로 한 틱 미룬다: 호출부는 직전에 같은 동기 호출 안에서
    /// `AppNavigationRequest.shared.request(.outline)`을 부르는데, 개요 화면은 다음 렌더 패스에야 마운트된다.
    /// 즉시 대입하면 `.onChange`가 등록되기 전에 값이 바뀌어(마운트 시점의 값은 기준값일 뿐 변화로 감지되지 않는다)
    /// 아무도 반응하지 못하고 트리 최상위만 보인다.
    func request(bookId: Int, chapter: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.requestedSelection = .chapter(bookId, chapter)
        }
    }

    /// 통합 검색의 책 단위 개요(`BookOutline`, 장 구분 없음) 결과를 탭했을 때 쓴다 —
    /// `request(bookId:chapter:)`는 항상 `.chapter` 선택만 만든다.
    func requestBook(bookId: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.requestedSelection = .book(bookId)
        }
    }

    /// 요청을 소비한 쪽(`OutlineTreeSplitContent`)이 처리 후 반드시 호출해 비운다 — 안 비우면 같은 책/장을
    /// 다시 요청했을 때 `.onChange`가 값이 그대로라고 판단해 반응하지 않을 수 있다.
    func clear() {
        requestedSelection = nil
    }
}
