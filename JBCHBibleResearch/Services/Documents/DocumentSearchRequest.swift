//
//  DocumentSearchRequest.swift
//  JBCHBibleResearch
//
//  `WindowGroup(id:for:)`는 값 타입 하나만 받고, 기존 "document-viewer" 창은
//  PersistentIdentifier만 받는 "그냥 열기" 흐름에 쓰이므로 그 타입을 바꾸지 않는다.
//  대신 문서 ID + 검색어를 담는 이 값 타입으로 별도의 "document-search" 창을 연다.
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
