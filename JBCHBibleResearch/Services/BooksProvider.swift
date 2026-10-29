//
//  BooksProvider.swift
//  JBCHBibleResearch
//
//  BibleResearchModels.BooksCatalog는 리소스를 담은 Bundle을 호출부가 넘겨주도록
//  설계돼 있다(패키지 자체엔 books.json이 없음, BibleReferenceModels.swift 참고).
//  이 타입이 앱 번들(.main)의 books.json을 로드해 화면 레이어 전역에서 쓸 수 있게
//  캐시해 둔다.
//

import Foundation
import BibleResearchModels

@MainActor
final class BooksProvider {
    static let shared = BooksProvider()

    /// orderIndex(=정경 순서 1~66) 기준 정렬.
    let books: [Book]
    private let byId: [Int: Book]

    private init() {
        do {
            books = try BooksCatalog.load(from: .main).sorted { $0.orderIndex < $1.orderIndex }
        } catch {
            // books.json이 타겟 리소스에 포함되지 않았거나 손상된 경우. 앱을 죽이는 대신 빈
            // 목록으로 폴백해 "책 목록이 비어 있음"이 화면에 드러나게 한다(더미 데이터로 채우지 않는다).
            print("[BooksProvider] books.json 로드 실패: \(error)")
            books = []
        }
        byId = Dictionary(uniqueKeysWithValues: books.map { ($0.bookId, $0) })
    }

    func book(id: Int) -> Book? { byId[id] }

    /// 정경 순서상 다음 책(`books`가 orderIndex순 정렬이라 인덱스만 옮긴다). 마지막 책(요한계시록)이면
    /// nil — 호출부(`BibleReadingViewModel.nextChapter`)는 nil이면 아무것도 하지 않는다.
    func book(after book: Book) -> Book? {
        guard let index = books.firstIndex(where: { $0.bookId == book.bookId }), index + 1 < books.count else {
            return nil
        }
        return books[index + 1]
    }

    func book(before book: Book) -> Book? {
        guard let index = books.firstIndex(where: { $0.bookId == book.bookId }), index > 0 else {
            return nil
        }
        return books[index - 1]
    }

    /// 책 그리드 피커 검색창용 — `Book.matches(query:)`(초성 검색 포함)로 필터링한다.
    /// 한국어가 아닌 화면에서는 앱 언어 책 이름/약칭(`displayName`/`displayShortName`)도 함께 비교한다.
    /// (자유 입력 파싱 `matchBookPrefix`도 2026-10-29부터 앱 언어 이름표를 함께 인식한다 — 아래 함수 주석 참고.)
    func search(query: String) -> [Book] {
        guard !query.isEmpty else { return books }
        return books.filter { book in
            if book.matches(query: query) { return true }
            guard !AppLanguage.isKorean else { return false }
            return book.displayName.localizedCaseInsensitiveContains(query)
                || book.displayShortName.localizedCaseInsensitiveContains(query)
        }
    }

    /// "요한복음 3장", "요3장", "ㅇㅎㅂㅇ3장", "창세기 1" 같은 자유 입력 맨 앞에서
    /// 책 이름/약칭/초성을 찾는다. 여러 후보가 매칭되면 가장 긴(=가장 구체적인)
    /// 것을 우선한다(예: "요한"보다 "요한복음"을 먼저 고려).
    ///
    /// [2026-10-29 booklabel1] 한국어가 아닌 앱에서는 앱 언어 이름표(`AppLanguage.bookNameTable`의
    /// fullNames/shortNames)도 후보로 인식한다("John 3:16", "1 Sam 3", "Gén. 1", "创世纪1"). 비교 규칙은
    /// `localizedPrefixLength(of:in:)` 참고. 한국어 후보(1)와 초성(2)은 앱 언어와 관계없이 항상 인식하며,
    /// 한국어 앱은 이름표가 nil이라 동작이 이전과 같다. 호출부: `BookChapterPicker.submitFreeText`,
    /// `BulkCrossReferenceParser`(저장 라벨은 그쪽에서 한국어 약칭으로 따로 만든다).
    func matchBookPrefix(in text: String) -> (book: Book, remainder: Substring)? {
        let trimmed = Substring(text.trimmingCharacters(in: .whitespaces))
        var best: (Book, Substring)?
        var bestLength = 0
        let localizedTable = AppLanguage.bookNameTable

        for book in books {
            // 1) 이름/약칭 정확한 접두 일치.
            for candidate in book.abbreviation + [book.nameKo] where trimmed.hasPrefix(candidate) {
                guard candidate.count > bestLength else { continue }
                best = (book, trimmed.dropFirst(candidate.count))
                bestLength = candidate.count
            }

            // 1-b) 앱 언어 이름표 후보(한국어 앱은 nil이라 건너뛴다). 길이 비교 기준은 입력에서 소비한 글자 수.
            // 아래 2)의 `guard … else { continue }`보다 먼저 둬야 이 후보가 건너뛰어지지 않는다.
            if let localizedTable {
                let index = book.bookId - 1
                let names = [
                    localizedTable.fullNames.indices.contains(index) ? localizedTable.fullNames[index] : "",
                    localizedTable.shortNames.indices.contains(index) ? localizedTable.shortNames[index] : ""
                ]
                for candidate in names where !candidate.isEmpty {
                    guard let consumed = Self.localizedPrefixLength(of: candidate, in: trimmed),
                          consumed > bestLength else { continue }
                    best = (book, trimmed.dropFirst(consumed))
                    bestLength = consumed
                }
            }

            // 2) 초성 입력 지원 — 예: "ㅇㅎㅂㅇ3장"처럼 책 이름 전체를 초성으로
            // 입력한 경우. nameKo와 같은 글자 수만큼 앞부분을 잘라 Book.matches로
            // 확인한다(Book+Search.swift의 위치별 비교 규칙 그대로 재사용).
            let nameLength = book.nameKo.count
            guard trimmed.count >= nameLength, nameLength > bestLength else { continue }
            let candidatePrefix = String(trimmed.prefix(nameLength))
            if book.matches(query: candidatePrefix) {
                best = (book, trimmed.dropFirst(nameLength))
                bestLength = nameLength
            }
        }
        return best
    }

    /// 이름표 후보 `candidate`가 `text` 맨 앞에 오면 `text`에서 소비한 글자(Character) 수를, 아니면 nil을 돌려준다.
    /// - 대소문자를 구분하지 않는다(`Character.lowercased()` — 로캘과 무관한 유니코드 기본 규칙).
    /// - 후보와 입력 양쪽의 공백을 건너뛰고 비교한다("1 Samuel" ↔ "1Samuel", 영어 약칭 "1Sam" ↔ "1 Sam").
    ///   `text`는 호출부에서 앞 공백을 이미 잘랐다.
    /// - 일치 직후의 마침표 하나는 이름에 포함해 소비한다("Gén. 1", "1 Jn. 3").
    /// - 일치(와 마침표) 뒤 나머지를 공백 기준으로 잘랐을 때 비어 있거나 숫자(반각 0-9·전각 ０-９)로 시작할 때만 인정한다.
    ///   예: "Song of Songs 2"에서 약칭 "Song"은 나머지가 "of …"라 거절되고 전체 이름 후보만 남는다. 독일어 "Joh"가
    ///   "Johan 3"에 걸려 1장으로 가 버리는 일도 막는다(일치 없음 → 오류 알림). "创世纪1", "Gen 1", "Jn 3:16"은 통과.
    ///   `Character.isNumber`는 쓰지 않는다 — "一"(CJK 숫자 값 보유), "Ⅰ" 같은 문자도 참이 되기 때문.
    private static func localizedPrefixLength(of candidate: String, in text: Substring) -> Int? {
        let nameCharacters = candidate.filter { !$0.isWhitespace }.map { $0.lowercased() }
        guard !nameCharacters.isEmpty else { return nil }

        var index = text.startIndex
        var consumed = 0
        var matched = 0
        while matched < nameCharacters.count {
            guard index < text.endIndex else { return nil }
            let character = text[index]
            if !character.isWhitespace {
                guard character.lowercased() == nameCharacters[matched] else { return nil }
                matched += 1
            }
            index = text.index(after: index)
            consumed += 1
        }

        if index < text.endIndex, text[index] == "." {
            index = text.index(after: index)
            consumed += 1
        }

        // 나머지가 비었거나(공백만 포함) 숫자로 시작해야 한다.
        guard let first = text[index...].first(where: { !$0.isWhitespace }) else { return consumed }
        guard Self.isChapterDigit(first) else { return nil }
        return consumed
    }

    /// 반각 0-9 또는 전각 ０-９(U+FF10…U+FF19) 한 글자인지.
    private static func isChapterDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        return (0x30...0x39).contains(scalar.value) || (0xFF10...0xFF19).contains(scalar.value)
    }
}
