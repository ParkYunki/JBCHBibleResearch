//
//  BulkCrossReferenceParser.swift
//  JBCHBibleResearch
//
//  [2026-08-12 신설] 사용자 요청 — "관주를 일괄로 처리할 수 있도록 텍스트박스를 두고,
//  거기에 입력하는 텍스트에 성경장절 문구를 추출하여 일괄 등록. ex) 창1:1, 출애굽기1:2~3,
//  시편112편1,3,5절 -> DB 등록 텍스트 : 창1:1, 출1:2-3, 시112:1,3,5 -> DB 저장 (창1:1,
//  출1:2, 출1:3, 시112:1, 시112:3, 시112:5) 로 분해하여, 각 성경 시퀀스와 장 idx, 절
//  idx를 등록할 것." `CrossReferenceTargetPicker`의 일괄 입력란이 쓰는 파서 — 콤마/
//  줄바꿈으로 나눈 조각을 순서대로 훑으며, 책 이름이 새로 나오면 "현재 책/장" 문맥을
//  갱신하고, 책 이름 없이 숫자만 나오면(예: "시편112편1,3,5절"을 콤마로 쪼갠 뒤 남는
//  "3"과 "5절") 직전 조각이 정한 문맥을 그대로 물려받는다.
//
//  [2026-08-12 재작성] 사용자 보고 — "DB 등록 텍스트... 반영안됨. 사용자가 관주를
//  클릭해서 볼 때는 사용자가 입력한 텍스트가 정제되어서 보여져야 함." 처음 버전은
//  절 단위로 다 분해한 `[BibleVerseRef]` 하나만 돌려줬는데(표시용 문구가 없었음),
//  이제는 "책 이름이 나온 지점부터 다음 책 이름이 나오기 전까지"를 하나의 논리적
//  항목(`ParsedGroup`)으로 묶어 그 항목 전체를 대표하는 정제된 문구(예: "시112:1,3,5")
//  와, DB에 낱개로 저장할 절 목록을 함께 돌려준다 — 분해는 여전히 하되(`verses`),
//  "사용자가 원래 입력한 덩어리가 무엇이었는지"를 잃지 않는다.
//
//  ⚠️ [기존 BibleReferenceExtractor와 다른 목적] `BibleReferenceExtractor`는 자유
//  문장(메모/연구문서) 속에서 "책 이름 + 숫자"가 우연히 함께 나오는 자리를 찾는
//  용도라, 매치 하나가 항상 "책+장+절"을 자기 완결적으로 담고 있어야 오탐을 줄일 수
//  있다 — 그 정규식/문맥 규약을 이번 요구사항(콤마로 나열된 "3", "5절"처럼 책/장이
//  생략된 조각이 앞 조각의 문맥을 이어받는 것)에 맞게 억지로 늘리면, 원래 용도(자유
//  문장 스캔)에서 오탐이 늘어날 위험이 있다고 판단해 이 화면 전용의 별도 파서를
//  새로 뒀다. 책 이름 인식(`BooksProvider.matchBookPrefix`)만 공유한다.
//

import Foundation
import BibleResearchModels

@MainActor
enum BulkCrossReferenceParser {
    /// 사용자가 입력한 하나의 논리적 항목 — 예: "출애굽기1:2~3" 하나가 여기서는
    /// `label: "출1:2-3"`, `verses: [출1:2, 출1:3]`으로 나뉜다. `label`은 화면에
    /// 그대로 보여줄 정제된 문구, `verses`는 DB에 낱개로 저장할 절 목록.
    struct ParsedGroup {
        let label: String
        let verses: [BibleVerseRef]
    }

    struct ParsedResult {
        let groups: [ParsedGroup]
        /// 책/장/절로 해석할 수 없었던 조각 원문(사용자에게 그대로 보여줄 용도).
        let unrecognizedFragments: [String]
    }

    /// 콤마/줄바꿈으로 조각을 나눈 뒤, 각 조각을 순서대로 해석해 항목(그룹)
    /// 단위로 묶는다.
    static func parse(_ text: String) -> ParsedResult {
        let pieces = text
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var groups: [ParsedGroup] = []
        var unrecognized: [String] = []

        var currentBook: Book?
        var currentChapter: Int?
        var currentSpecs: [String] = []
        var currentVerses: [BibleVerseRef] = []

        func flushCurrentGroup() {
            guard let book = currentBook, let chapter = currentChapter, !currentSpecs.isEmpty else { return }
            let label = "\(canonicalAbbreviation(for: book))\(chapter):"
                + currentSpecs.map(normalizedSpecLabel).joined(separator: ",")
            groups.append(ParsedGroup(label: label, verses: currentVerses))
            currentSpecs = []
            currentVerses = []
        }

        for piece in pieces {
            if let (book, chapter, verseSpec) = parseWithBookPrefix(piece) {
                // 새 책 이름이 나오면 지금까지 모은 항목을 확정하고 새로 시작한다
                // — 같은 책/장이 다시 나와도(예: "창1:1, ..., 창1:5") 별개의
                // 항목으로 취급한다(사용자가 실제로 다시 책 이름을 적었으므로).
                flushCurrentGroup()
                currentBook = book
                currentChapter = chapter
                guard let verseSpec else {
                    // 책+장만 있고 절이 없는 조각("창세기 1장") — 이 기능은 절
                    // 단위 등록이 목적이라 절 번호 없는 조각은 인식 실패로
                    // 취급한다(임의로 1절을 채워 넣지 않는다). 다만 책/장 문맥
                    // 자체는 남겨 둬 바로 뒤에 오는 "맨 숫자" 조각이 이 책/장을
                    // 물려받을 수 있게 한다.
                    unrecognized.append(piece)
                    continue
                }
                currentSpecs.append(verseSpec)
                currentVerses.append(contentsOf: expandVerses(verseSpec).map {
                    BibleVerseRef(bookId: book.bookId, chapter: chapter, verse: $0)
                })
                continue
            }

            // 책 이름이 없는 조각 — 직전 조각이 정한 책/장 문맥을 물려받는 "맨
            // 숫자" 절 지정("3", "5절", "6~8")인지 확인한다.
            if let book = currentBook, let chapter = currentChapter, let spec = bareVerseSpec(piece) {
                currentSpecs.append(spec)
                currentVerses.append(contentsOf: expandVerses(spec).map {
                    BibleVerseRef(bookId: book.bookId, chapter: chapter, verse: $0)
                })
                continue
            }

            unrecognized.append(piece)
        }
        flushCurrentGroup()

        return ParsedResult(groups: groups, unrecognizedFragments: unrecognized)
    }

    // MARK: - 조각 하나 해석

    /// 조각이 책 이름으로 시작하면 (책, 장, 절지정?)을 돌려준다. 절지정이 nil이면
    /// "책+장"까지만 있고 절이 없었다는 뜻(위 호출부가 인식 실패로 처리).
    private static func parseWithBookPrefix(_ piece: String) -> (book: Book, chapter: Int, verseSpec: String?)? {
        guard let (book, remainder) = BooksProvider.shared.matchBookPrefix(in: piece) else { return nil }
        guard let (chapter, verseSpec) = chapterAndVerseSpec(from: String(remainder)) else { return nil }
        return (book, chapter, verseSpec)
    }

    /// "112편1", "1:2~3", " 1장 1절" 같은, 책 이름을 뗀 나머지에서 (장, 절지정?)을
    /// 뽑아낸다. 장 번호는 필수, 절지정은 선택(없으면 nil).
    private static func chapterAndVerseSpec(from remainder: String) -> (chapter: Int, verseSpec: String?)? {
        guard let regex = chapterVerseRegex else { return nil }
        let ns = remainder as NSString
        guard let match = regex.firstMatch(in: remainder, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let chapterRange = match.range(at: 1)
        guard chapterRange.location != NSNotFound, let chapter = Int(ns.substring(with: chapterRange)), chapter > 0 else { return nil }
        let verseRange = match.range(at: 2)
        guard verseRange.location != NSNotFound else { return (chapter, nil) }
        return (chapter, ns.substring(with: verseRange))
    }

    /// 책 이름 없이 절 지정만 있는 조각("3", "5절", "6~8", "6-8절")인지 확인한다.
    private static func bareVerseSpec(_ piece: String) -> String? {
        guard let regex = bareVerseRegex else { return nil }
        let ns = piece as NSString
        guard let match = regex.firstMatch(in: piece, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let verseRange = match.range(at: 1)
        guard verseRange.location != NSNotFound else { return nil }
        return ns.substring(with: verseRange)
    }

    /// "2", "2~3", "2-3" 형태의 절지정을 낱개 절 번호 배열로 편다(안전장치로 200개
    /// 초과 범위는 시작 절 하나만 남긴다).
    private static func expandVerses(_ spec: String) -> [Int] {
        let cleaned = spec.replacingOccurrences(of: "절", with: "").trimmingCharacters(in: .whitespaces)
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: "~-"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { Int($0) }
        guard let start = parts.first else { return [] }
        guard let end = parts.dropFirst().first else { return [start] }
        guard end >= start, end - start < 200 else { return [start] }
        return Array(start...end)
    }

    /// 화면/DB 등록 문구용 축약 이름 — books.json의 `abbreviation[0]`이 "창"/
    /// "출"/"시"처럼 가장 짧은 표준 약칭이라 그대로 쓴다(약칭이 없으면 정식 이름).
    private static func canonicalAbbreviation(for book: Book) -> String {
        book.abbreviation.first ?? book.nameKo
    }

    /// 절지정 하나를 정제된 표시 문구로 바꾼다 — "절" 접미사를 떼고, 범위 구분자를
    /// "~"든 "-"든 전부 "-"로 통일한다("2~3" -> "2-3", "5절" -> "5").
    private static func normalizedSpecLabel(_ spec: String) -> String {
        spec.replacingOccurrences(of: "절", with: "")
            .replacingOccurrences(of: "~", with: "-")
            .components(separatedBy: CharacterSet(charactersIn: " "))
            .joined()
    }

    // MARK: - 정규식

    /// 그룹1 = 장(필수), 그룹2 = 절지정(선택) — "1:2~3" / "112편1" / " 1장 1절" 등.
    private static let chapterVerseRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\s*(\d{1,3})\s*(?:장|편)?\s*(?:[:,]\s*)?(\d{1,3}(?:\s*[~-]\s*\d{1,3})?)?\s*절?\s*$"#
    )

    /// 책 이름 없이 절 지정만 있는 조각 — "3" / "5절" / "6~8" / "6-8절".
    private static let bareVerseRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\s*(\d{1,3}(?:\s*[~-]\s*\d{1,3})?)\s*절?\s*$"#
    )
}
