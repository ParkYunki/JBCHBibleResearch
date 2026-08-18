//
//  BookNameTableProvider.swift
//  JBCHBibleResearch
//
//  BookNameTable.swift(내장 9개 언어 이름표) 위에, "이 번역본(TranslationRegistry)이
//  가리키는 이름표로 이 책 이름을 어떻게 표시할지" 결정하는 조회 로직을 얹는다.
//  이전 앱의 `resolvedBookDisplayName(bookID:...)`에 해당하는 부분 — 원본에는 없던
//  타입이지만(원본은 화면 코드 쪽에 흩어져 있었을 가능성이 큼), 이 프로젝트의
//  BooksProvider와 대칭이 되도록 별도 타입으로 분리했다.
//
//  ⚠️ [범위 밖] "사용자가 직접 이름표를 새로 만들거나 수정"하는 기능(원본 주석의
//  "일괄 붙여넣기 또는 개별 수정")은 S12(번역본 관리)에서 다룰 일이라 이번 구현에는
//  없다 — 지금은 내장 9종 중 골라 쓰는 것만 가능하고, 그 연결 UI 자체도 아직 없다
//  (TranslationRegistry.bookNameTableID는 항상 nil로 시작 = 한글 기본 표시).
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

    /// `bookNameTableID`가 가리키는 이름표에서 `bookId`의 이름을 구한다. 이름표가
    /// 없거나(`nil`), 등록되지 않은 id거나, 해당 이름표에 이 책 이름이 비어 있으면
    /// (예: 네팔어/타갈로그 등 shortNames 미확보) 한글 기본 이름(BooksProvider)으로
    /// 폴백한다 — 원본의 "채우기 전까지는 한글로 자동 표시" 정책 그대로.
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
