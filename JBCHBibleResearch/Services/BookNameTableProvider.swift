//
//  BookNameTableProvider.swift
//  JBCHBibleResearch
//
//  `BookNameTable`(내장 9개 언어 이름표) 위에, 번역본(`TranslationRegistry`)이 가리키는
//  이름표로 책 이름을 어떻게 표시할지 결정하는 조회 로직. `BooksProvider`와 대칭이 되도록
//  별도 타입으로 뒀다.
//
//  ⚠️ 사용자가 이름표를 직접 만들거나 수정하는 기능은 없다(S12 범위). 내장 9종 중 골라 쓰는
//  것만 가능하며 그 연결 UI도 아직 없다(`bookNameTableID`는 항상 nil = 한글 기본 표시).
//

import Foundation
import BibleResearchModels

@MainActor
final class BookNameTableProvider {
    static let shared = BookNameTableProvider()

    let builtIn: [BookNameTable] = BookNameTable.builtInBookNameTables()
    private let byId: [String: BookNameTable]

    private init() {
        byId = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.id, $0) })
    }

    func table(id: String) -> BookNameTable? { byId[id] }

    /// `bookNameTableID`가 가리키는 이름표에서 `bookId`의 이름을 구한다. 이름표가 없거나(`nil`),
    /// 등록되지 않은 id거나, 해당 이름이 비어 있으면(예: shortNames 미확보) 한글 기본 이름
    /// (BooksProvider)으로 폴백한다.
    func displayName(forBookId bookId: Int, bookNameTableID: String?, preferShort: Bool = false) -> String {
        let fallback = BooksProvider.shared.book(id: bookId)?.nameKo ?? "\(bookId)권"

        guard let bookNameTableID, let table = table(id: bookNameTableID) else { return fallback }
        let index = bookId - 1
        guard index >= 0, index < table.fullNames.count else { return fallback }

        if preferShort, index < table.shortNames.count {
            let short = table.shortNames[index]
            if !short.isEmpty { return short }
        }
        let full = table.fullNames[index]
        return full.isEmpty ? fallback : full
    }
}
