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

    /// [2026-09-05 `DispatchQueue.main.async`로 한 틱 지연 — 사용자 신고]
    /// "아이폰이든 맥이든 아이패드든 다 이동이 안됨 ... 개요 화면은 뜨는데
    /// 최상위(책 목록) 화면만 보임." 이 함수의 호출부(`ChapterRelatedContentPanel`
    /// "개요 화면 열기" 버튼, `SearchView.groupedOutlineRow`)는 전부 바로 앞
    /// 줄에서 `AppNavigationRequest.shared.request(.outline)`을 같은 동기
    /// 호출 안에서 먼저 부른다 — 그 호출이 섹션을 개요로 전환시켜야 비로소
    /// `OutlineTreeSplitContent`(맥OS/아이패드)/`OutlineTreeView`의 아이폰
    /// 분기가 새로 만들어지고, 그 안의 `.onChange(of: requestedSelection)`이
    /// 등록된다. 그런데 SwiftUI는 `selection` 변경으로 그 새 화면을 실제로
    /// 만드는 걸 다음 렌더 패스로 미루는 반면, 바로 다음 줄의 이 함수는 같은
    /// 동기 호출 안에서 즉시 실행돼 `requestedSelection`을 그 화면이 아직
    /// 만들어지기도 전에 바꿔버린다. `.onChange`는 "그 시점부터의 변화"만
    /// 감지하므로(마운트 시점의 현재값을 초기 기준값으로 삼을 뿐, 그 값
    /// 자체가 바뀌었다고 소급 반응하지 않는다), 화면이 뒤늦게 마운트됐을 땐
    /// 이미 지나간 변화라 아무도 반응하지 못하고 트리 최상위만 보였다 —
    /// `DispatchQueue.main.async`로 대입을 한 틱 미뤄, 방금 전환된 개요
    /// 화면이 먼저 마운트되고 `.onChange`가 등록된 뒤에 값이 바뀌도록 한다.
    /// 이 프로젝트가 같은 목적으로 이미 여러 곳(`SelectableVerseTextView.
    /// swift`, `RichTextEditor.swift` 등, "한 틱 늦게" 패턴)에 쓰던 방식을
    /// 그대로 재사용했다.

    /// `ChapterRelatedContentPanel`의 "개요 화면 열기" 버튼이 호출한다 — 지금
    /// 성경 조회 화면이 보고 있는 책/장을 그대로 넘긴다.
    func request(bookId: Int, chapter: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.requestedSelection = .chapter(bookId, chapter)
        }
    }

    /// [2026-08-18 추가] 사용자 요청 — 통합 검색의 "개요" 결과 중 책 단위 개요
    /// (`BookOutline`, 장 구분 없음)를 탭했을 때 쓴다 — `request(bookId:chapter:)`는
    /// 항상 `.chapter` 선택만 만들어서 책 단위 개요를 정확히 가리킬 수 없었다.
    func requestBook(bookId: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.requestedSelection = .book(bookId)
        }
    }

    /// 요청을 소비한 쪽(`OutlineTreeSplitContent`)이 처리 후 반드시 호출해 비운다
    /// — 안 비우면 다음에 우연히 같은 책/장을 다시 요청했을 때 `.onChange`가
    /// "값이 그대로"라고 판단해 반응하지 않을 수 있다(`AppNavigationRequest.clear()`
    /// 상단 주석과 같은 이유).
    func clear() {
        requestedSelection = nil
    }
}
