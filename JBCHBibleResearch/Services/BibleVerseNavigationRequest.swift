//
//  BibleVerseNavigationRequest.swift
//  JBCHBibleResearch
//
//  사이드바 "최근" 항목(형광펜/메모/관주)을 탭했을 때 해당 절의 성경 조회 화면으로 이동하기
//  위한 요청 전달용 싱글턴. `SidebarNavigationView`는 `BibleReadingView`의 로컬 `@State`
//  뷰모델에 접근할 수 없어, `OutlineNavigationRequest`/`AppNavigationRequest`/
//  `SidebarSearchRequest`와 같은 패턴(메모리 전용 싱글턴 + Equatable 값 + `.onChange`)으로
//  목표 좌표(책/장/절)를 넘긴다. `@FocusedValue`로 클로저를 게시하지 않는 이유도 같다
//  (실기기 크래시 전례).
//
//  소비 쪽(`BibleReadingView`)은 화면이 새로 만들어지는 경우(`.onAppear`)와 이미 성경 조회
//  화면을 보고 있던 경우(`BibleReadingContentView`의 `.onChange`)를 모두 처리해야 한다.
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

    /// 소비한 쪽이 처리 후 반드시 호출해 비운다 — 안 비우면 같은 좌표를 다시 요청했을 때
    /// `.onChange`가 값이 그대로라고 판단해 반응하지 않을 수 있다.
    func clear() {
        pendingTarget = nil
    }
}
