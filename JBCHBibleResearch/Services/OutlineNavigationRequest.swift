//
//  OutlineNavigationRequest.swift
//  JBCHBibleResearch
//
//  [2026-08-15 신설] 사용자 요청 — "'개요 화면 열기' 버튼 -> 왼쪽 사이드바의 개요
//  -> 성경선택 -> 장 선택 후 나오는 에디터 화면으로 전환." 이 버튼은 원래
//  (2026-08-08~09) `AppNavigationRequest.shared.request(.outline)`만으로 메인
//  내비게이션을 개요 섹션으로 전환했었는데(그 파일 상단 주석), 그 뒤 "이동/
//  크기조절 가능한 별도 창을 조회모드로 띄운다"로 바뀌었다가, 이번 요청으로
//  다시 "메인 내비게이션 전환"으로 되돌아왔다 — 다만 이번엔 책/장까지 미리
//  선택된 채로 에디터 화면(`OutlineBookBulkEditView`, 기본값이 편집 가능)에
//  바로 진입해야 한다는 요구가 추가됐다. `AppNavigationRequest`(섹션 전환)만
//  으로는 "이 책의 이 장을 선택한 채로"까지 표현할 수 없어(그 타입은 `AppSection`
//  만 다룬다), 트리 선택 상태(`OutlineTreeSelection`, `OutlineTreeView.swift`)를
//  실어 나르는 이 새 싱글턴을 별도로 둔다.
//
//  `AppNavigationRequest`/`SidebarVisibilityRequest`와 완전히 같은 패턴 — 가벼운
//  메모리 전용 싱글턴, plain Equatable 값(`OutlineTreeSelection`은 `Hashable`이라
//  `Equatable`도 만족)을 관찰한다. `@FocusedValue` 클로저 게시 대신 이 방식을
//  쓰는 이유는 `AppNavigationRequest.swift` 상단 주석 참고(클로저는 Equatable이
//  아니라 툴바를 가진 뷰에서 읽으면 실기기 크래시가 났었다).
//

import Foundation
import Observation

@MainActor
@Observable
final class OutlineNavigationRequest {
    static let shared = OutlineNavigationRequest()

    private(set) var requestedSelection: OutlineTreeSelection?

    private init() {}

    /// `ChapterRelatedContentPanel`의 "개요 화면 열기" 버튼이 호출한다 — 지금
    /// 성경 조회 화면이 보고 있는 책/장을 그대로 넘긴다.
    func request(bookId: Int, chapter: Int) {
        requestedSelection = .chapter(bookId, chapter)
    }

    /// [2026-08-18 추가] 사용자 요청 — 통합 검색의 "개요" 결과 중 책 단위 개요
    /// (`BookOutline`, 장 구분 없음)를 탭했을 때 쓴다 — `request(bookId:chapter:)`는
    /// 항상 `.chapter` 선택만 만들어서 책 단위 개요를 정확히 가리킬 수 없었다.
    func requestBook(bookId: Int) {
        requestedSelection = .book(bookId)
    }

    /// 요청을 소비한 쪽(`OutlineTreeSplitContent`)이 처리 후 반드시 호출해 비운다
    /// — 안 비우면 다음에 우연히 같은 책/장을 다시 요청했을 때 `.onChange`가
    /// "값이 그대로"라고 판단해 반응하지 않을 수 있다(`AppNavigationRequest.clear()`
    /// 상단 주석과 같은 이유).
    func clear() {
        requestedSelection = nil
    }
}
