//
//  DocumentSearchRequest.swift
//  JBCHBibleResearch
//
//  [2026-08-11 신설] 사용자 요청 — "[관련 내용]에서 연구문서를 클릭하면 PDF로 띄워
//  (해당 성경장절 텍스트로) 검색할 것." `WindowGroup(id:for:)`는 값 타입 하나만
//  받을 수 있는데, 기존 "document-viewer" 창(PersistentIdentifier만 받음)은 이미
//  "그냥 열기" 흐름(ChapterRelatedContentPanel의 연구문서 목록 등)에 쓰이고 있어
//  그 타입을 바꾸면 그 흐름에 영향을 준다 — 대신 문서 ID + 검색어를 함께 담는 새
//  값 타입을 만들고, 별도의 "document-search" 창(JBCHBibleResearchApp.swift 참고)을
//  하나 더 연다.
//

import Foundation
import SwiftData

public struct DocumentSearchRequest: Codable, Hashable, Sendable {
    public let documentID: PersistentIdentifier
    public let searchText: String

    public init(documentID: PersistentIdentifier, searchText: String) {
        self.documentID = documentID
        self.searchText = searchText
    }
}
