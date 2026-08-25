//
//  BibleVerseNavigationRequest.swift
//  JBCHBibleResearch
//
//  [2026-08-25 신설] 사용자 요청 — "왼쪽 사이드바 메뉴 명 하단 수정된 이력
//  리스트에 성경 내용의 메모, 형광펜, 주석 수정한 내용도 이력에 나타날 수
//  있도록." 그 히스토리 항목(형광펜/메모/관주)을 탭하면 그 절이 있는 성경
//  조회 화면으로 이동해야 하는데, `SidebarNavigationView`는 `BibleReadingView`가
//  들고 있는 `BibleReadingViewModel`(그 섹션이 선택돼 있을 때만 존재하는 로컬
//  `@State`)에 직접 접근할 방법이 없다 — `OutlineNavigationRequest`/
//  `AppNavigationRequest`/`SidebarSearchRequest`와 완전히 같은 패턴(가벼운
//  메모리 전용 싱글턴 + plain Equatable 값 + `.onChange`)으로 목표 좌표
//  (책/장/절)를 대신 전달한다. `@FocusedValue`에 클로저를 게시하는 방식을
//  안 쓰는 이유도 그 파일들과 같다(`AppNavigationRequest.swift` 상단 주석
//  참고 — 실기기 크래시 전례).
//
//  `SidebarNavigationView.openQuickItem`이 이 요청과 함께 `selection =
//  .bibleReading`도 직접 바꾼다(이미 그 상태를 들고 있어 `AppNavigationRequest`를
//  거칠 필요가 없다 — memo/summary 케이스가 `selection = .wordNote`를 직접
//  하는 것과 같은 원칙). 소비 쪽(`BibleReadingView`)은 두 경로 모두 처리해야
//  한다 — 화면이 막 새로 만들어지는 경우(다른 섹션에서 전환, `BibleReadingView`
//  바깥 `.onAppear`)와 이미 성경 조회 화면을 보고 있던 경우(같은 섹션 안에서
//  다른 항목을 다시 탭, `BibleReadingContentView`의 `.onChange`) — 이는
//  `SidebarSearchRequest`(`SearchView`의 `.onAppear`+`.onChange` 이중 처리)와
//  같은 이유다.
//

import Foundation
import Observation

struct BibleVerseNavigationTarget: Equatable {
    let bookId: Int
    let chapter: Int
    let verse: Int
}

@MainActor
@Observable
final class BibleVerseNavigationRequest {
    static let shared = BibleVerseNavigationRequest()

    private(set) var pendingTarget: BibleVerseNavigationTarget?

    private init() {}

    /// 사이드바의 "최근" 항목(형광펜/메모/관주)을 탭하면 호출한다.
    func request(bookId: Int, chapter: Int, verse: Int) {
        pendingTarget = BibleVerseNavigationTarget(bookId: bookId, chapter: chapter, verse: verse)
    }

    /// 요청을 소비한 쪽(`BibleReadingView`)이 처리 후 반드시 호출해 비운다 —
    /// 안 비우면 다음에 우연히 같은 좌표를 다시 요청했을 때 `.onChange`가 "값이
    /// 그대로"라고 판단해 반응하지 않을 수 있다(`SidebarSearchRequest.clear()`
    /// 상단 주석과 같은 이유).
    func clear() {
        pendingTarget = nil
    }
}
