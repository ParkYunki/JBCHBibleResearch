//
//  BibleReferenceExtractor.swift
//  JBCHBibleResearch
//
//  메모/연구문서 같은 자유 텍스트에서 "요한복음 3:16" / "요 3장 16절" / "창1:1" / "창세기 1장" 등
//  성경 장절 표현을 정규식으로 찾아 (책, 장, 절?) 좌표(`Match`)로 바꾼다.
//  범위 표기("갈1:6-9", "갈1:24-2:1")는 절 단위 `Match` 여러 개로 펼친다("책+장+절 하나 = Match 하나" 규약 유지).
//  장을 넘는 범위는 번들 기본 번역본(BibleDB.sqlite)에서 장별 절 수를 조회해 분해하며,
//  조회에 실패하면 추측하지 않고 시작 절 하나만 남긴다.
//
//  ⚠️ 장 번호 없이 책 이름만 나오는 경우는 추출하지 않는다(약칭이 흔한 낱말과 겹쳐 오탐이 잦아짐).
//  "약칭+숫자"가 전화번호·목록 번호와 우연히 겹치는 오탐은 남을 수 있다 — 놓치는 것보다 낫다고 보고 허용했다.
//  ⚠️ 번역본마다 절 구분이 다르면 장 경계 계산이 어긋날 수 있다(번들 번역본 기준).
//

import Foundation
import BibleResearchModels

@MainActor
enum BibleReferenceExtractor {
    struct Match {
        let range: Range<String.Index>
        /// 실제로 매칭된 원문(공백 트리밍만) — DB에 검색어로 저장한다. 범위 표기가 여러 Match로
        /// 펼쳐져도 항상 원문 범위 표기 전체를 담는다(사용자가 인용한 그대로 남기기 위함).
        let searchText: String
        let bookId: Int
        let chapter: Int
        let verse: Int?
    }

    private struct Compiled {
        let regex: NSRegularExpression
        /// 책 이름 없이 "구분자(,/.) + 장:절[-범위]"만 이어지는 인용("살전 1:10. 2:19-20, 3:13")용.
        /// 주 매치 직후 위치부터 `.anchored`로 반복 적용해 같은 책으로 계속 뽑는다(`continuationMatches` 참고).
        /// ⚠️ "요 3:16, 17"처럼 장 없이 절만 이어지는 표기는 번호 매김/날짜/비율 오탐 위험 때문에
        /// 의도적으로 제외했다 — "장:절" 형태만 인정한다.
        let continuationRegex: NSRegularExpression
        /// 길이 내림차순 — 매치된 문자열이 어느 책 이름으로 시작하는지 되짚어 찾을 때
        /// 가장 구체적인(긴) 이름부터 비교해야 "요한"이 "요한복음"을 가로채지 않는다.
        let sortedForms: [(form: String, book: Book)]
    }

    private static var cached: Compiled?
    private static var bundledStore: BibleReferenceStore?
    /// 번들 DB를 열어봤지만 실패했던 경우 매 호출마다 다시 시도하지 않기 위한 플래그.
    private static var bundledStoreLoadAttempted = false

    private static func compiled() -> Compiled? {
        if let cached { return cached }
        let books = BooksProvider.shared.books
        guard !books.isEmpty else { return nil }

        var seen = Set<String>()
        var forms: [(form: String, book: Book)] = []
        for book in books {
            for form in book.abbreviation + [book.nameKo] where !form.isEmpty {
                guard !seen.contains(form) else { continue }
                seen.insert(form)
                forms.append((form, book))
            }
        }
        forms.sort { $0.form.count > $1.form.count }

        let escaped = forms.map { NSRegularExpression.escapedPattern(for: $0.form) }
        let bookAlternation = escaped.joined(separator: "|")
        // 절 그룹: 그룹2 = "구분자(:,) + 숫자"(뒤 "절" 선택), 그룹3 = "숫자 + 절"("1장 1절" 어순, "절" 필수 —
        // 순수 숫자를 절로 오인하지 않기 위함). 그룹3이 없으면 "1장 1절"이 verse nil(장 단위)로 잡혀
        // 같은 장의 다른 절까지 일치하게 된다. 그룹4 = 범위 끝 장(선택), 그룹5 = 범위 끝 절(선택) —
        // `extract(from:)`가 이 번호에 의존한다.
        // `continuationRegex`는 오탐 위험 때문에 "장:절" 형태만 인정한다.
        let pattern = "(?:\(bookAlternation))\\s*(\\d{1,3})\\s*장?\\s*"
            + "(?:(?:[:,]\\s*(\\d{1,3})\\s*절?|(\\d{1,3})\\s*절)"
            + "(?:\\s*[-~]\\s*(?:(\\d{1,3})\\s*[:장]\\s*)?(\\d{1,3})\\s*절?)?"
            + ")?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        // `Compiled.continuationRegex` 참고. 그룹1=장, 그룹2=절(둘 다 필수), 그룹3=범위 끝 장(선택),
        // 그룹4=범위 끝 절(선택). `^`는 `.anchored` 호출과 동작이 같지만 의도를 드러내려고 둔다.
        let continuationPattern = "^[,.]\\s*(\\d{1,3})\\s*장?\\s*[:절]\\s*(\\d{1,3})\\s*절?"
            + "(?:\\s*[-~]\\s*(?:(\\d{1,3})\\s*[:장]\\s*)?(\\d{1,3})\\s*절?)?"
        guard let continuationRegex = try? NSRegularExpression(pattern: continuationPattern) else { return nil }

        let result = Compiled(regex: regex, continuationRegex: continuationRegex, sortedForms: forms)
        cached = result
        return result
    }

    /// 번들 기본 번역본(BibleDB.sqlite)을 읽기 전용으로 한 번만 연다 — 장 경계를
    /// 넘는 범위 표기를 분해할 때 "그 장이 몇 절까지 있는지" 조회하는 용도로만 쓴다.
    private static func store() -> BibleReferenceStore? {
        if let bundledStore { return bundledStore }
        guard !bundledStoreLoadAttempted else { return nil }
        bundledStoreLoadAttempted = true
        guard let url = try? TranslationBootstrap.resolvedBundledDatabaseURL(),
              let opened = try? BibleReferenceStore(filePath: url.path) else { return nil }
        bundledStore = opened
        return opened
    }

    /// 특정 책의 특정 장이 실제로 몇 절까지 있는지(번들 번역본 기준). 조회에
    /// 실패하면 nil — 호출부(`expandRange`)가 추측 없이 안전하게 처리한다.
    private static func maxVerse(bookId: Int, chapter: Int) -> Int? {
        guard let store = store() else { return nil }
        guard let verses = try? store.verses(bookId: bookId, chapter: chapter), !verses.isEmpty else { return nil }
        return verses.map(\.verse).max()
    }

    /// (startChapter, startVerse) ~ (endChapter, endVerse) 구간의 모든 절 좌표를
    /// 순서대로 나열한다. `endChapter`가 nil이면 같은 장 안의 범위("6-9")로 본다.
    /// 장 경계를 넘는 범위("24-2:1")는 중간 장들이 몇 절까지 있는지 실제 데이터로
    /// 확인해야 하는데, 그 조회가 하나라도 실패하거나 범위 자체가 앞뒤가 뒤바뀐
    /// 등 이상하면 잘못 추측하는 대신 시작 절 하나만 돌려준다.
    private static func expandRange(
        bookId: Int, startChapter: Int, startVerse: Int, endChapter: Int?, endVerse: Int
    ) -> [(chapter: Int, verse: Int)] {
        let fallback: [(chapter: Int, verse: Int)] = [(startChapter, startVerse)]
        let targetChapter = endChapter ?? startChapter
        guard targetChapter >= startChapter else { return fallback }

        if targetChapter == startChapter {
            guard endVerse >= startVerse else { return fallback }
            guard endVerse - startVerse < 300 else { return fallback } // 안전장치 — 비정상적으로 큰 범위 방지.
            return (startVerse...endVerse).map { (startChapter, $0) }
        }

        guard targetChapter - startChapter < 30 else { return fallback } // 안전장치 — 30개 장을 넘는 범위는 오탐으로 간주.

        var result: [(chapter: Int, verse: Int)] = []
        var chapter = startChapter
        var verse = startVerse
        while chapter < targetChapter {
            guard let lastVerse = maxVerse(bookId: bookId, chapter: chapter), lastVerse >= verse else {
                return fallback
            }
            for v in verse...lastVerse { result.append((chapter, v)) }
            chapter += 1
            verse = 1
        }
        guard endVerse >= verse, result.count + (endVerse - verse + 1) < 300 else {
            return result.isEmpty ? fallback : result
        }
        for v in verse...endVerse { result.append((chapter, v)) }
        return result
    }

    static func extract(from text: String) -> [Match] {
        guard !text.isEmpty, let compiled = compiled() else { return [] }
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var matches: [Match] = []

        compiled.regex.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
            guard let result, let matchRange = Range(result.range, in: text) else { return }
            let matchedText = String(text[matchRange])
            guard let book = compiled.sortedForms.first(where: { matchedText.hasPrefix($0.form) })?.book else { return }
            // 주 매치 뒤에 책 이름 없이 이어지는 "장:절" 항목은 같은 책으로 보고 계속 뽑는다 —
            // 아래 각 분기가 자기 Match를 추가한 직후 `continuationMatches`를 호출한다.
            let continuationStart = result.range.location + result.range.length

            let chapterRange = result.range(at: 1)
            guard chapterRange.location != NSNotFound,
                  let chapter = Int(ns.substring(with: chapterRange)), chapter > 0 else { return }
            let searchText = matchedText.trimmingCharacters(in: .whitespaces)

            // 절 그룹은 둘 중 하나만 매칭된다(그룹2 "구분자+숫자" / 그룹3 "숫자+절") — 값이 있는 쪽을 쓴다.
            let verseRange = result.range(at: 2)
            let verseParticleRange = result.range(at: 3)
            let verse: Int?
            if verseRange.location != NSNotFound, let v = Int(ns.substring(with: verseRange)), v > 0 {
                verse = v
            } else if verseParticleRange.location != NSNotFound, let v = Int(ns.substring(with: verseParticleRange)), v > 0 {
                verse = v
            } else {
                verse = nil
            }
            guard let verse else {
                // 절 번호 없이 "책 이름 + 장"만 매칭된 경우 — 범위 표기가 있을 수
                // 없으니 장 단위 Match 하나만 추가한다.
                matches.append(Match(range: matchRange, searchText: searchText, bookId: book.bookId, chapter: chapter, verse: nil))
                matches.append(contentsOf: continuationMatches(compiled: compiled, ns: ns, text: text, book: book, startingAt: continuationStart))
                return
            }

            let endVerseRange = result.range(at: 5)
            guard endVerseRange.location != NSNotFound,
                  let endVerse = Int(ns.substring(with: endVerseRange)), endVerse > 0 else {
                // 범위 표기 없음 — 절 하나만.
                matches.append(Match(range: matchRange, searchText: searchText, bookId: book.bookId, chapter: chapter, verse: verse))
                matches.append(contentsOf: continuationMatches(compiled: compiled, ns: ns, text: text, book: book, startingAt: continuationStart))
                return
            }

            var endChapter: Int?
            let endChapterRange = result.range(at: 4)
            if endChapterRange.location != NSNotFound,
               let ec = Int(ns.substring(with: endChapterRange)), ec > 0 {
                endChapter = ec
            }

            let expanded = expandRange(
                bookId: book.bookId, startChapter: chapter, startVerse: verse,
                endChapter: endChapter, endVerse: endVerse
            )
            for coordinate in expanded {
                matches.append(Match(
                    range: matchRange, searchText: searchText, bookId: book.bookId,
                    chapter: coordinate.chapter, verse: coordinate.verse
                ))
            }
            matches.append(contentsOf: continuationMatches(compiled: compiled, ns: ns, text: text, book: book, startingAt: continuationStart))
        }
        return matches
    }

    /// 주 매치 바로 뒤(`position`)부터 `continuationRegex`를 `.anchored`로 반복 적용해, 책 이름 없이 이어지는
    /// "장:절" 항목을 같은 책으로 뽑는다. 매치가 끊기는 즉시 멈춰, 중간에 인용이 아닌 텍스트가 끼면
    /// 이후 숫자를 잘못 이어붙이지 않는다.
    /// ⚠️ "장:절" 형태만 인정한다(`Compiled.continuationRegex` 참고).
    private static func continuationMatches(
        compiled: Compiled, ns: NSString, text: String, book: Book, startingAt position: Int
    ) -> [Match] {
        var results: [Match] = []
        var pos = position
        let totalLength = ns.length

        while pos < totalLength {
            let searchRange = NSRange(location: pos, length: totalLength - pos)
            guard let result = compiled.continuationRegex.firstMatch(in: text, options: [.anchored], range: searchRange),
                  let matchRange = Range(result.range, in: text) else { break }
            let searchText = String(text[matchRange]).trimmingCharacters(in: .whitespaces)

            let chapterRange = result.range(at: 1)
            let verseRange = result.range(at: 2)
            guard chapterRange.location != NSNotFound, verseRange.location != NSNotFound,
                  let chapter = Int(ns.substring(with: chapterRange)), chapter > 0,
                  let verse = Int(ns.substring(with: verseRange)), verse > 0 else { break }

            var endVerse: Int?
            let endVerseRange = result.range(at: 4)
            if endVerseRange.location != NSNotFound, let ev = Int(ns.substring(with: endVerseRange)), ev > 0 {
                endVerse = ev
            }

            if let endVerse {
                var endChapter: Int?
                let endChapterRange = result.range(at: 3)
                if endChapterRange.location != NSNotFound,
                   let ec = Int(ns.substring(with: endChapterRange)), ec > 0 {
                    endChapter = ec
                }
                let expanded = expandRange(
                    bookId: book.bookId, startChapter: chapter, startVerse: verse,
                    endChapter: endChapter, endVerse: endVerse
                )
                for coordinate in expanded {
                    results.append(Match(
                        range: matchRange, searchText: searchText, bookId: book.bookId,
                        chapter: coordinate.chapter, verse: coordinate.verse
                    ))
                }
            } else {
                results.append(Match(range: matchRange, searchText: searchText, bookId: book.bookId, chapter: chapter, verse: verse))
            }

            // 방금 소비한 만큼 앞으로 당긴다 — 매치 길이가 0이면(이론상 불가, 방어적) 무한 루프 방지를 위해 멈춘다.
            guard result.range.length > 0 else { break }
            pos = result.range.location + result.range.length
        }
        return results
    }

    /// 미리보기에서 구절 표기 앞/뒤로 남기는 글자 수(Character 기준).
    /// ⚠️ 연구문서(HWP 등)는 한 "줄"이 페이지 한 장 분량(1,000자 이상)일 수 있어 줄 단위로 자르면 표기가 화면 밖으로 밀린다.
    /// 앞은 짧게(화면 첫 줄 안에 표기가 보이게), 뒤는 넉넉히 둔다. 값을 바꾸면 `BibleReferenceIndexingService.snippetFormatVersion`도 올려
    /// 기존 미리보기가 한 번 다시 만들어지게 한다.
    static let snippetLeadingCharacters = 30
    static let snippetTrailingCharacters = 120

    /// 사이드바/팝오버 미리보기용 — 매치된 표기 앞 `snippetLeadingCharacters`자, 뒤 `snippetTrailingCharacters`자를 잘라
    /// 돌려준다. 연속 공백/줄바꿈은 공백 하나로 합치고, 앞뒤가 잘렸으면 "…"를 붙인다.
    /// `match.range`는 `text`의 인덱스라 그대로 쓸 수 있다.
    static func snippet(for match: Match, in text: String) -> String {
        let lower = text.index(match.range.lowerBound, offsetBy: -snippetLeadingCharacters, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(match.range.upperBound, offsetBy: snippetTrailingCharacters, limitedBy: text.endIndex) ?? text.endIndex
        let collapsed = String(text[lower..<upper])
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return match.searchText }
        return (lower > text.startIndex ? "…" : "") + collapsed + (upper < text.endIndex ? "…" : "")
    }
}
