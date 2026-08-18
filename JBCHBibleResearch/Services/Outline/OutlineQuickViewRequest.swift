//
//  OutlineQuickViewRequest.swift
//  JBCHBibleResearch
//
//  [2026-08-15 신설] 사용자 요청 — "[성경 조회] 오른쪽 인스펙터 — 개요의 '별도
//  창에서 보기' 버튼: 기존 창을 재사용하지 말고 신규 창을 만들 것. 책 개요 /
//  장 개요(해당 장) 두 내용만 표시, 상단에 검색창 + 돋보기(배율 확대/축소/원본
//  크기) 버튼." `WindowGroup(id:for:)`(JBCHBibleResearchApp.swift의
//  "outline-quick-view")가 여는 창에 넘기는 값이다.
//
//  ⚠️ [매번 새 창을 강제하는 이유] SwiftUI `WindowGroup(for:)`는 기본적으로
//  "같은 값으로 이미 열려 있는 창이 있으면 그 창을 앞으로 가져온다"(문서 기반
//  앱에서 같은 문서를 두 번 열지 않는 것과 같은 동작)는 재사용 동작을 한다.
//  하지만 사용자가 명시적으로 "기존 창을 재사용하지 말 것"이라고 요청했으므로,
//  같은 책/장이어도 매번 값 자체가 달라지도록 `requestID`(호출마다 새로
//  생성하는 `UUID`)를 식별성에 포함시켰다 — 이러면 SwiftUI 입장에서 매번
//  "처음 보는 값"이라 항상 새 창을 연다.
//

import Foundation

public struct OutlineQuickViewRequest: Codable, Hashable, Sendable {
    public let bookId: Int
    public let chapter: Int
    public let requestID: UUID

    public init(bookId: Int, chapter: Int, requestID: UUID = UUID()) {
        self.bookId = bookId
        self.chapter = chapter
        self.requestID = requestID
    }
}
