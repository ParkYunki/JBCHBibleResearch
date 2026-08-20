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
            // books.json이 Xcode 타겟(Copy Bundle Resources)에 포함되지 않았거나 손상된
            // 경우 여기로 온다. 앱을 죽이는 대신 빈 목록으로 폴백해 "책 목록이 비어
            // 있음"이 화면에 바로 드러나게 한다 — 임의의 더미 데이터를 만들어 채우지
            // 않는다.
            print("[BooksProvider] books.json 로드 실패: \(error)")
            books = []
        }
        byId = Dictionary(uniqueKeysWithValues: books.map { ($0.bookId, $0) })
    }

    func book(id: Int) -> Book? { byId[id] }

    /// [2026-08-20 추가] 사용자 요청 — "성경 이전 장: 창세기를 제외하고 각
    /// 성경의 1장에서 이전장을 클릭하면 전 성경(前, 이전 책) 마지막 장으로
    /// 이동. 성경 다음장: 요한계시록을 제외하고 각 성경의 마지막 장에서
    /// 다음장을 클릭하면 다음 성경 1장으로 이동." `books`가 이미 orderIndex
    /// 순으로 정렬돼 있으므로(위 프로퍼티 주석) 배열 인덱스만 앞뒤로 옮기면
    /// 된다. 첫/마지막 책(창세기/요한계시록)에서는 nil — 그 경계에서는 더
    /// 넘어갈 책이 없다는 뜻이라, 호출부(`BibleReadingViewModel.previousChapter`/
    /// `nextChapter`)가 nil이면 아무 것도 하지 않는다.
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

    /// 책 그리드 피커의 검색창(2026-08-06 추가) — `Book.matches(query:)`(초성 검색
    /// 포함, Book+Search.swift 참고)로 필터링한다.
    func search(query: String) -> [Book] {
        guard !query.isEmpty else { return books }
        return books.filter { $0.matches(query: query) }
    }

    /// "요한복음 3장", "요3장", "ㅇㅎㅂㅇ3장", "창세기 1" 같은 자유 입력 맨 앞에서
    /// 책 이름/약칭/초성을 찾는다. 여러 후보가 매칭되면 가장 긴(=가장 구체적인)
    /// 것을 우선한다(예: "요한"보다 "요한복음"을 먼저 고려).
    func matchBookPrefix(in text: String) -> (book: Book, remainder: Substring)? {
        let trimmed = Substring(text.trimmingCharacters(in: .whitespaces))
        var best: (Book, Substring)?
        var bestLength = 0

        for book in books {
            // 1) 이름/약칭 정확한 접두 일치.
            for candidate in book.abbreviation + [book.nameKo] where trimmed.hasPrefix(candidate) {
                guard candidate.count > bestLength else { continue }
                best = (book, trimmed.dropFirst(candidate.count))
                bestLength = candidate.count
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
}
