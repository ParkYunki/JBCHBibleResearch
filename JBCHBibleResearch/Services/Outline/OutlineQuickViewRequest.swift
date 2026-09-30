//
//  OutlineQuickViewRequest.swift
//  JBCHBibleResearch
//
//  개요 인스펙터의 "별도 창에서 보기"로 여는 개요 빠른 보기 창에 넘기는 값이다.
//  `WindowGroup(id:for:)`(JBCHBibleResearchApp.swift의 "outline-quick-view")가 받는다.
//
//  ⚠️ 매번 새 창을 열도록 `requestID`(호출마다 새로 만드는 `UUID`)를 값에 포함한다. `WindowGroup(for:)`는
//  같은 값으로 이미 열린 창이 있으면 그 창을 앞으로 가져오므로, 같은 책/장이어도 값이 매번 달라지게 해
//  SwiftUI가 항상 "처음 보는 값"으로 보고 새 창을 열게 한다.
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
