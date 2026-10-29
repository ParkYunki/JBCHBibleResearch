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
//  [2026-10-29 refext1] 한국어 이름·약칭에 더해 앱 언어 책 이름표(`BookNameTable`)의 이름·약칭도 인식한다
//  ("John 3:16", "Jn 3:16-18", "约3:16", "創世記1:1", "Быт 1:1", "Gn 1,1", "约翰福音3章16节").
//  - 인식 범위: 앱 언어와 관계없이 앱 언어로 쓰이는 13개 이름표 전부(`localizedTableOrder`). 색인(`VerseMention`)은
//    CloudKit으로 동기화되고, 소스를 저장한 기기가 그 소스의 색인을 지우고 다시 만든다(`reindexSingleSource`).
//    기기마다 인식 범위가 다르면 다른 언어 기기에서 저장할 때 색인이 지워졌다 생겼다 하므로, 결과가 앱 언어에
//    좌우되지 않게 했다. 예외: 흔한 낱말과 같은 표기(`appLanguageOnlyForms`)는 앱 언어 표에서만 인식하고,
//    언어마다 다른 책을 가리키는 같은 약칭(Jn·雅)은 앱 언어 표를 먼저 쓴다.
//  - 외국어는 반드시 "장:절"이 있어야 한다("Romans 8" 같은 장만 있는 표기는 인식하지 않는다 — 사용자 결정). 범위
//    ("3:16-18", "3:16~18")와 절 목록("3:16,18,20", "3:16, 18")을 받으며, 절 목록은 절마다 Match(`Kind.verseListItem`)로
//    펼친다. 이어지는 장절은 콜론 표기 "; 12:1"과 쉼표 표기 "Joh 3,16; 4,2"를 받는다.
//  - 한국어 경로(아래 `regex`/`continuationRegex`)는 바꾸지 않았다(한국어 "3:16,18"은 이전처럼 3:16만). 외국어 이름은
//    한국어 매치 범위 밖에서만 따로 찾고(`localizedMatches`), 두 결과를 위치 순서로 합친다. 한국어 텍스트의 결과는 이전과 같다.
//  - 오탐 방지 규칙은 `LocalizedNames` 주석 참고.
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
        /// [2026-10-29 refext1] `range` 안에서 장 번호가 시작하는 위치. 책 이름 자체에 숫자가 들어가는 외국어 이름
        /// ("2 Chronicles 35:9", "1-я Царств 3:4")에서 책 이름과 장절 표기를 나눌 때 쓴다(인물·지명 상세의 인용 링크 라벨).
        let chapterStart: String.Index
        /// [2026-10-29 refext1] 이 Match가 원문에서 어떤 모양이었는지 — 인물·지명 상세의 인용 링크 라벨이 쓴다.
        let kind: Kind

        enum Kind {
            /// 책 이름 + 장절("요한복음 3:16", "John 3:16-18"). `range`는 책 이름부터.
            case reference
            /// 책 이름 없이 이어지는 장절(", 3:13", "; 12:1"). `range`는 앞 구분자부터, `chapterStart`가 장 번호.
            case continuation
            /// 장 없이 절만 있는 목록 항목(외국어 "John 3:16, 18"의 ", 18"). `range`는 앞 구분자부터, `chapterStart`는 절 번호를
            /// 가리킨다(이름은 그대로 두었다). 장은 `chapter`(앞 항목에서 물려받음). 한국어 경로에는 없다.
            case verseListItem
        }
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
        /// [2026-10-29 refext1] 앱 언어 책 이름표 인식용. 만들지 못하면 nil — 한국어 인식만 한다.
        let localized: LocalizedNames?
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

        let result = Compiled(
            regex: regex, continuationRegex: continuationRegex, sortedForms: forms,
            localized: buildLocalizedNames()
        )
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
    /// 2026-10-13: 말씀 노트의 관련 말씀 선택 시트(`WordNoteVersePickerSheet`)도 절 수 조회에 쓰도록 `private`을 풀었다.
    /// [2026-10-29 refext1] 조회 결과를 장마다 한 번만 읽도록 캐시한다(번들 DB는 읽기 전용이라 값이 바뀌지 않는다).
    /// 외국어 참조의 절 범위 검사(`isValidLocator`)가 매치마다 부르기 때문이다. 조회 실패(nil)는 캐시하지 않아 이전과 같다.
    static func maxVerse(bookId: Int, chapter: Int) -> Int? {
        let key = bookId * 1_000 + chapter
        if let known = maxVerseCache[key] { return known }
        guard let store = store() else { return nil }
        guard let verses = try? store.verses(bookId: bookId, chapter: chapter),
              let last = verses.map(\.verse).max() else { return nil }
        maxVerseCache[key] = last
        return last
    }
    private static var maxVerseCache: [Int: Int] = [:]

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

    /// - Parameter nameMatching: [2026-10-29 refext1] 앱 언어 책 이름표 이름의 대소문자 비교 방식. 검색창 입력을 해석하는 곳만
    ///   `.searchQuery`(대소문자 무시)를 넘긴다. 한국어 이름 인식에는 영향이 없다.
    static func extract(from text: String, nameMatching: NameMatching = .bodyText) -> [Match] {
        guard !text.isEmpty, let compiled = compiled() else { return [] }
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        // 한국어 매치와 그 UTF-16 범위. 범위는 외국어 이름 탐색에서 이 구간을 건너뛰고 두 결과를 위치 순서로 합치는 데 쓴다.
        var matches: [Match] = []
        var koreanRanges: [NSRange] = []
        func appendKorean(_ match: Match, _ range: NSRange) {
            matches.append(match)
            koreanRanges.append(range)
        }
        func appendKoreanContinuation(_ items: [(range: NSRange, match: Match)]) {
            for item in items { appendKorean(item.match, item.range) }
        }

        compiled.regex.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
            guard let result, let matchRange = Range(result.range, in: text) else { return }
            let matchedText = String(text[matchRange])
            guard let book = compiled.sortedForms.first(where: { matchedText.hasPrefix($0.form) })?.book else { return }
            // 주 매치 뒤에 책 이름 없이 이어지는 "장:절" 항목은 같은 책으로 보고 계속 뽑는다 —
            // 아래 각 분기가 자기 Match를 추가한 직후 `continuationMatches`를 호출한다.
            let continuationStart = result.range.location + result.range.length

            let chapterRange = result.range(at: 1)
            guard chapterRange.location != NSNotFound,
                  let chapter = Int(ns.substring(with: chapterRange)), chapter > 0,
                  let chapterStart = Range(chapterRange, in: text)?.lowerBound else { return }
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
                appendKorean(Match(range: matchRange, searchText: searchText, bookId: book.bookId, chapter: chapter, verse: nil, chapterStart: chapterStart, kind: .reference), result.range)
                appendKoreanContinuation(continuationMatches(compiled: compiled, ns: ns, text: text, book: book, startingAt: continuationStart))
                return
            }

            let endVerseRange = result.range(at: 5)
            guard endVerseRange.location != NSNotFound,
                  let endVerse = Int(ns.substring(with: endVerseRange)), endVerse > 0 else {
                // 범위 표기 없음 — 절 하나만.
                appendKorean(Match(range: matchRange, searchText: searchText, bookId: book.bookId, chapter: chapter, verse: verse, chapterStart: chapterStart, kind: .reference), result.range)
                appendKoreanContinuation(continuationMatches(compiled: compiled, ns: ns, text: text, book: book, startingAt: continuationStart))
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
                appendKorean(Match(
                    range: matchRange, searchText: searchText, bookId: book.bookId,
                    chapter: coordinate.chapter, verse: coordinate.verse, chapterStart: chapterStart, kind: .reference
                ), result.range)
            }
            appendKoreanContinuation(continuationMatches(compiled: compiled, ns: ns, text: text, book: book, startingAt: continuationStart))
        }

        // [2026-10-29 refext1] 앱 언어 책 이름표 이름. 외국어 매치가 없으면 한국어 결과를 그대로 돌려준다(이전과 같음).
        guard let localized = compiled.localized else { return matches }
        let foreign = localizedMatches(in: text, ns: ns, names: localized, excluding: koreanRanges, matching: nameMatching)
        guard !foreign.isEmpty else { return matches }
        // 두 목록은 각각 위치 오름차순이다. 같은 위치면 한국어를 먼저 둔다(겹치는 매치는 `excluding`으로 이미 막았다).
        // 범위 표기를 펼친 Match들은 같은 위치를 공유하므로 각 목록 안의 순서를 그대로 지킨다(안정 병합).
        var merged: [Match] = []
        merged.reserveCapacity(matches.count + foreign.count)
        var k = 0
        var f = 0
        while k < matches.count || f < foreign.count {
            if f >= foreign.count || (k < matches.count && koreanRanges[k].location <= foreign[f].location) {
                merged.append(matches[k])
                k += 1
            } else {
                merged.append(foreign[f].match)
                f += 1
            }
        }
        return merged
    }

    /// 주 매치 바로 뒤(`position`)부터 `continuationRegex`를 `.anchored`로 반복 적용해, 책 이름 없이 이어지는
    /// "장:절" 항목을 같은 책으로 뽑는다. 매치가 끊기는 즉시 멈춰, 중간에 인용이 아닌 텍스트가 끼면
    /// 이후 숫자를 잘못 이어붙이지 않는다.
    /// ⚠️ "장:절" 형태만 인정한다(`Compiled.continuationRegex` 참고).
    private static func continuationMatches(
        compiled: Compiled, ns: NSString, text: String, book: Book, startingAt position: Int
    ) -> [(range: NSRange, match: Match)] {
        var results: [(range: NSRange, match: Match)] = []
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
                  let verse = Int(ns.substring(with: verseRange)), verse > 0,
                  let chapterStart = Range(chapterRange, in: text)?.lowerBound else { break }

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
                    results.append((range: result.range, match: Match(
                        range: matchRange, searchText: searchText, bookId: book.bookId,
                        chapter: coordinate.chapter, verse: coordinate.verse, chapterStart: chapterStart, kind: .continuation
                    )))
                }
            } else {
                results.append((range: result.range, match: Match(
                    range: matchRange, searchText: searchText, bookId: book.bookId, chapter: chapter, verse: verse,
                    chapterStart: chapterStart, kind: .continuation
                )))
            }

            // 방금 소비한 만큼 앞으로 당긴다 — 매치 길이가 0이면(이론상 불가, 방어적) 무한 루프 방지를 위해 멈춘다.
            guard result.range.length > 0 else { break }
            pos = result.range.location + result.range.length
        }
        return results
    }

    // MARK: - 앱 언어 책 이름표 인식 (2026-10-29 refext1)

    /// 앱 언어 이름표 이름의 대소문자 규칙(본문 모드 `.bodyText`). 값이 클수록 관대하다 — 같은 책의 같은 이름이 여러 표에서
    /// 오면 가장 관대한 쪽을 쓴다. 검색어 모드(`.searchQuery`)는 `matchBookPrefix`처럼 대소문자를 가리지 않는다.
    private enum NameCaseRule: Int {
        /// 약칭: 이름표 표기와 글자 단위로 같아야 한다("Mt"는 되고 "MT"(마소라 본문 약어)·"mt"는 안 된다).
        case exact = 0
        /// 한 단어 전체 이름: 첫 글자만 대문자면 나머지는 대소문자를 가리지 않는다("John"·"JOHN"은 되고 "john"은 안 된다).
        case initialUppercase = 1
        /// 여러 단어이거나 숫자로 시작하는 전체 이름: 대소문자를 가리지 않는다("song of solomon", "1 john", "от Иоанна").
        case insensitive = 2
    }

    private struct NameEntry {
        let bookId: Int
        var caseRule: NameCaseRule
        /// `.exact` 비교용 원래 표기(공백 제거).
        var exactForms: Set<String>
        /// 이 키(같은 책)를 가진 이름표가 모두 fr·de·it인지(트라이에 넣을 때 AND로 합친다).
        var allSourcesUseCommaNotation: Bool
        /// 이 키가 앱 언어 이름표에 있고 그 앱 언어가 fr·de·it인지(OR로 합친다).
        var inCommaNotationAppTable: Bool

        /// "장,절" 쉼표 표기("Joh 3,16", "Jn 3,16", "Mt 5,3")를 인정하는지(사용자 결정 "fr·de·it만").
        /// - 앱 언어가 fr·de·it이면 그 언어 이름표의 모든 이름에 허용한다 — "Jn"(fr·es), "Mt"(de·it·pt), "Ps"처럼 가장 흔한 약칭이
        ///   다른 언어와 표기가 같아도 그 언어 사용자는 쉼표 장절로 쓴다.
        /// - 그 밖의 앱 언어에서는 fr·de·it에만 있는 이름("Joh", "Genèse", "Römer")에만 허용한다. en·es·pt·tl과 같은 표기
        ///   ("Ps", "Genesis")는 영어 "Psalms 1,2"(1편과 2편)처럼 장 목록일 수 있어서다.
        /// ⚠️ 그래서 쉼표 표기 인식은 기기 언어에 따라 달라질 수 있다(fr·de·it 앱에서 "Jn 3,16"으로 쓴 메모를 다른 언어 기기에서
        /// 다시 저장하면 그 언급은 빠진다). 이 앱에서 기기 언어에 따라 결과가 갈리는 것은 쉼표 표기, 앱 언어 전용 표기
        /// (`appLanguageOnlyForms`), 충돌 약칭(Jn·雅)의 우선순위뿐이다.
        var allowsCommaSeparator: Bool { allSourcesUseCommaNotation || inCommaNotationAppTable }
    }

    private final class NameTrieNode {
        var children: [UInt16: NameTrieNode] = [:]
        var entry: NameEntry?
        /// 이 노드 다음 글자 앞에 공백(최대 3칸)을 허용하는지 — 이름표 이름에 공백이 있던 자리이거나 숫자 뒤 글자 자리
        /// ("1 Samuel"·"1Samuel", "1Sam"·"1 Sam"). 숫자 뒤면 마침표 하나도 허용한다(독일어 서수 "1. Könige").
        var allowsGapBeforeNext = false
    }

    /// 앱 언어 이름표 이름을 찾는 사전 계산 결과(`compiled()`가 한 번 만든다).
    ///
    /// 탐색: 본문 UTF-16 코드 단위를 한 번 훑으며 `startable`인 위치에서만 트라이를 따라간다. 위치마다 비용은 가장 긴 이름
    /// 길이(공백 제외 최대 25단위)로 묶이므로 전체 O(n·L)이고, 대부분의 글자(한글 본문 등)는 배열 한 번 조회로 끝난다.
    /// 이름 뒤에 숫자가 있을 때만 정규식을 그 위치에 고정(`.anchored`)해 돌린다. 정규식 검색 범위는 최대 `regexWindow`
    /// 단위다 — 모든 꼬리 정규식의 반복을 상한으로 묶어(공백 최대 3칸 등) 매치와 뒤 확인(lookahead)이 창 안에서 끝나므로,
    /// 문서 끝까지 범위를 준 것과 결과가 같다.
    ///
    /// 오탐 방지 규칙:
    /// - 이름 바로 뒤에 (마침표 하나, 공백 최대 3칸 다음) 숫자가 와야 한다(`BooksProvider.localizedPrefixLength`와 같은 규칙).
    /// - 전체 이름이든 약칭이든 "장:절"(CJK "N章M节", fr·de·it "장,절")이 있어야 한다. 장만 있는 표기("Romans 8")는
    ///   인식하지 않는다(사용자 결정 — 한국어 경로는 기존대로 장만 있는 표기도 인식).
    /// - 대소문자: `NameCaseRule`(본문 모드).
    /// - 라틴·키릴 문자처럼 대소문자가 있는 글자나 숫자로 시작하는 이름은 앞 글자가 글자·숫자면 인정하지 않는다
    ///   ("Johnny 3:16"의 "John", "11Sam 3:4"의 "1Sam"). 한자·가나·태국 문자는 띄어 쓰지 않으므로 앞 글자를 보지 않는다.
    /// - 장 번호는 그 책의 장 수 이하, 절 번호는 번들 번역본의 그 장 마지막 절 이하여야 한다. 범위 끝 장·절도 같이 검사하고,
    ///   끝이 범위를 넘으면 참조 전체를 거절한다(`isValidReference`). 한국어 경로에는 이 검사가 없다.
    /// - "장,절" 쉼표 표기는 `NameEntry.allowsCommaSeparator` 규칙으로만 인정한다(앱 언어가 fr·de·it이면 그 언어 이름 전부,
    ///   그 밖에는 fr·de·it 전용 이름).
    /// - 절 목록 항목 뒤에 공백과 라틴·키릴 글자가 오면 그 항목은 버린다("Acts 2:38, 39 people"). CJK 글자·반절 "18a"는 받는다.
    /// - 이 검사들을 통과하지 못하면 그 이름 끝까지 건너뛴다("3 John 5:4"가 요한삼서에서 떨어진 뒤 안쪽 "John 5:4"로
    ///   다시 잡히지 않게).
    /// - 장절 바로 뒤에 시각 표지(am/pm/a.m./p.m./o'clock/h/Uhr/hrs/horas, 左右/出发/开会/集合/点钟)가 오면 거절한다(`timeMarker`).
    ///   "之后/以前/开始/时"는 넣지 않았다 — 실제 참조 뒤에도 온다("耶利米书40:8 之后的经文", "从…1:1开始").
    ///   "am"은 독일어 "Joh 3,16 am Sonntag"(~에)와 겹쳐, 뒤에 문장부호·끝이 올 때만 시각으로 본다.
    /// - 흔한 낱말과 같은 표기(`appLanguageOnlyForms`)는 그 표기를 가진 이름표가 앱 언어 표일 때만 넣는다.
    private struct LocalizedNames {
        let root: NameTrieNode
        /// UTF-16 코드 단위 → 이름의 첫 글자가 될 수 있는지(대소문자 변형 포함). 65,536칸.
        let startable: [Bool]
        /// 이름표에 나오는 글자의 대문자·제목 문자 → 소문자. 없는 글자는 그대로 비교한다.
        let fold: [UInt16: UInt16]
        /// "3:16", "3:16-18", "3:16~18", "3:16-4:2". 그룹: 1 장, 2 절, 3 범위 끝 장, 4 범위 끝 절.
        let colonTail: NSRegularExpression
        /// fr·de·it "3,16", "3,16-18", "3,16-4,2". 그룹은 `colonTail`과 같다.
        let commaTail: NSRegularExpression
        /// CJK "3章16节", "第3章16節", "3章16-18节". 그룹: 1 장, 2 절, 3 범위 끝 절.
        let cjkTail: NSRegularExpression
        /// 이름 없이 이어지는 "장:절" — 그룹은 `colonTail`과 같다. 구분자는 `, . ; ， ； 、`.
        let continuation: NSRegularExpression
        /// 쉼표 표기 뒤에 ";"로 이어지는 "장,절"("Joh 3,16; 4,2", "3,16; 4,2-5"). 그룹은 `commaTail`과 같다.
        /// 쉼표 표기에서 ","·"."는 장절·절 목록 구분자라 ";"(전각 "；")만 이어짐으로 본다.
        let commaContinuation: NSRegularExpression
        /// "장:절" 뒤 절 목록 항목 ", 18", ",18", "，18", "、18", ", 18-20". 그룹: 1 절, 2 범위 끝 절.
        /// 뒤에 ":"가 오면(다음 "장:절"의 장) 항목이 아니다. 공백 다음 라틴·키릴 글자가 와도 항목이 아니다("39 people", "1 and 2").
        /// 반절 "18a"는 18절로 받는다.
        let colonListItem: NSRegularExpression
        /// "장,절" 뒤 절 목록 항목 ".18", ".18-20"(독일어 Loccumer 규칙·프랑스어 TOB 관례). 그룹은 `colonListItem`과 같다.
        /// 뒤에 ",숫자"가 오면(다음 "장,절"의 장) 항목이 아니다.
        let commaListItem: NSRegularExpression
        let timeMarker: NSRegularExpression
    }

    /// 텍스트 종류에 따른 외국어 이름 비교 방식.
    enum NameMatching {
        /// 메모·설교·문서·말씀요약 본문과 인물·지명 설명 — `NameCaseRule`을 적용한다.
        case bodyText
        /// 사용자가 검색창에 직접 입력한 검색어 — 대소문자를 가리지 않는다(`BooksProvider.matchBookPrefix`와 같은 규칙).
        /// 그 밖의 규칙(장:절 필수, 단어 경계, 장절 범위, 시각 표지, 앱 언어 전용 표기)은 본문과 같다.
        case searchQuery
    }

    /// 정규식 검색 범위 상한(UTF-16 단위). 꼬리 정규식 매치 최대 길이(약 45단위)와 뒤 확인 길이(최대 5단위)보다 충분히 길다.
    private static let regexWindow = 256

    /// 인식하는 이름표 — `AppLanguage.bookNameTableID`가 고를 수 있는 13개(앱 언어로 쓰이지 않는 몽골어·네팔어 제외).
    /// 순서는 같은 약칭이 서로 다른 책을 가리킬 때의 우선순위다(앱 언어 표가 항상 맨 앞으로 온다).
    /// 2026-10-29 이름표 기준 충돌 4개 중 "Es"·"Ab"는 `appLanguageOnlyForms`라 앱 언어 표에서만 들어가고,
    /// "Jn"(es·fr 요한복음 / pt 요나), "雅"(ja 아가 / zh 야고보서)만 이 순서를 탄다.
    private static var localizedTableOrder: [String] {
        typealias T = BookNameTable.BuiltInBookNameTable
        return [
            T.english, T.spanish, T.french, T.german, T.italian, T.japanese, T.thai, T.portuguese,
            T.russian, T.vietnamese, T.tagalog, T.chineseSimplified, T.chineseTraditional,
        ]
    }

    /// 흔한 낱말과 글자까지 같은 표기 — 그 표기를 가진 이름표가 앱 언어 표일 때만 인식한다. 앱 언어가 아닌 언어의 글에서는
    /// 문장 첫머리의 낱말 + 시각·점수·비율("At 10:30", "Is 3:1", "So 3:1", "Es 10:30", "Hi 3:4", "Ex 2:1",
    /// 중국어 "约10:30"(약 10시 30분))과 구분할 수 없기 때문이다.
    /// 기준: 앱이 지원하는 라틴 문자 언어(en·es·fr·de·it·pt·fil)의 기능어·흔한 낱말과 같은 이름표 표기, 그리고 중국어 "约/約"(약).
    /// "Job"(욥기 전체 이름)은 넣지 않는다 — 모든 언어 앱에서 인식한다(사용자 결정, 말씀요약 전체 이름 삽입과 기기 간 일관성 우선).
    /// ⚠️ 이 표기들만은 기기 언어에 따라 인식 여부가 달라진다(색인 동기화 일관성의 예외).
    private static let appLanguageOnlyForms: Set<String> = [
        "At", "Am", "Is", "So", "Hi", "Ex", "Es", "Os", "Na", "Ha", "Mi", "Ne", "Ab", "Ed", "Est", "约", "約",
    ]

    /// 2026-10-29 zhnames1에서 바꾸기 전의 중국어 전체 이름. 이름표에서는 뺐지만 그 전에 저장된 본문(복사·붙여넣기,
    /// 사용자가 직접 쓴 흔한 이체 표기)에 남아 있을 수 있어 본문 인식에만 받는다. 입력칸(`matchBookPrefix`)은 받지 않는다.
    private static var legacyChineseFullNames: [String: [(bookId: Int, name: String)]] {
        typealias T = BookNameTable.BuiltInBookNameTable
        return [
            T.chineseSimplified: [(1, "创世纪"), (50, "腓利比书"), (62, "约翰壹书"), (63, "约翰贰书"), (64, "约翰参书")],
            T.chineseTraditional: [(1, "創世紀"), (50, "腓利比書"), (62, "約翰壹書"), (63, "約翰貳書"), (64, "約翰參書")],
        ]
    }

    private static func buildLocalizedNames() -> LocalizedNames? {
        typealias T = BookNameTable.BuiltInBookNameTable
        let commaTables: Set<String> = [T.french, T.german, T.italian]
        var tablesByID: [String: BookNameTable] = [:]
        for table in BookNameTable.builtInBookNameTables() where tablesByID[table.id] == nil {
            tablesByID[table.id] = table
        }
        let appTableID = AppLanguage.bookNameTableID
        var order = localizedTableOrder
        if let appTableID, let index = order.firstIndex(of: appTableID) {
            order.remove(at: index)
            order.insert(appTableID, at: 0)
        }

        let root = NameTrieNode()
        var fold: [UInt16: UInt16] = [:]
        for tableID in order {
            guard let table = tablesByID[tableID] else { continue }
            var names: [(bookId: Int, name: String, isFullName: Bool)] = []
            for index in 0..<66 {
                if table.fullNames.indices.contains(index), !table.fullNames[index].isEmpty {
                    names.append((index + 1, table.fullNames[index], true))
                }
                if table.shortNames.indices.contains(index), !table.shortNames[index].isEmpty {
                    names.append((index + 1, table.shortNames[index], false))
                }
            }
            for legacy in legacyChineseFullNames[tableID] ?? [] {
                names.append((legacy.bookId, legacy.name, true))
            }
            for item in names {
                if appLanguageOnlyForms.contains(item.name), tableID != appTableID { continue }
                insertName(
                    item.name, bookId: item.bookId, isFullName: item.isFullName,
                    usesCommaNotation: commaTables.contains(tableID),
                    isCommaNotationAppTable: tableID == appTableID && commaTables.contains(tableID),
                    into: root, fold: &fold
                )
            }
        }
        guard !root.children.isEmpty else { return nil }

        var startable = [Bool](repeating: false, count: 65_536)
        for unit in root.children.keys { startable[Int(unit)] = true }
        for (variant, lower) in fold where root.children[lower] != nil { startable[Int(variant)] = true }

        // 정규식 조각. `\d` 대신 반각·전각 숫자만 쓴다(`number(_:in:)`가 읽을 수 있는 숫자). 공백 반복은 모두 최대 3칸으로
        // 묶는다 — 매치 길이에 상한이 있어야 `regexWindow`로 범위를 잘라도 결과가 같다.
        let digit = "[0-9\\uFF10-\\uFF19]"
        let number = "(\(digit){1,3})"
        let space3 = "[ \\t\\u00A0]{0,3}"
        let colon = "\(space3)[\\uFF1A:]\(space3)"
        let dash = "\(space3)[\\-\\u2013~\\uFF5E\\u223C]\(space3)"
        let lead = "\\.?[ \\t\\u00A0\\u3000]{0,3}"
        let colonGuard = "(?!\(digit)|[\\uFF1A:]\(digit))"
        let commaGuard = "(?!\(digit)|,\(digit))"
        let colonPattern = lead + number + colon + number
            + "(?:\(dash)(?:\(number)\(colon))?\(number))?" + colonGuard
        let commaPattern = lead + number + "," + number
            + "(?:\(dash)(?:\(number),)?\(number))?" + commaGuard
        let cjkPattern = lead + "第?" + number + "\(space3)章\(space3)第?" + number
            + "(?:\(dash)\(number))?\(space3)[节節]"
        let continuationPattern = "[,.;\\uFF0C\\uFF1B\\u3001]\(space3)" + number + colon + number
            + "(?:\(dash)(?:\(number)\(colon))?\(number))?" + colonGuard
        let commaContinuationPattern = "[;\\uFF1B]\(space3)" + number + "," + number
            + "(?:\(dash)(?:\(number),)?\(number))?" + commaGuard
        // 절 목록 항목 뒤 규칙: 반절 표기 "18a"는 a–c 한 글자를 항목에 포함해 18절로 연결한다(뒤에 글자가 더 오면 반절이 아니다 —
        // 소유 수량자 `?+`라 "18a and"에서 "a"를 내주고 "18"만 남기는 되돌림을 하지 않는다). 공백 다음 라틴·키릴 글자
        // ("39 people", "1 and 2", "39 человек")가 오면 항목이 아니다. CJK 글자가 붙는 경우("18节", "18中")는 항목으로 둔다.
        let verseSuffix = "(?:[a-c](?!\\p{L}))?+"
        let latinWordAfterSpace = "[ \\t\\u00A0]{1,3}[\\p{Latin}\\p{Cyrillic}]"
        let colonListPattern = "\(space3)[,\\uFF0C\\u3001]\(space3)" + number + "(?:\(dash)\(number))?"
            + verseSuffix + "(?!\(digit)|\(space3)[\\uFF1A:]|\(latinWordAfterSpace))"
        let commaListPattern = "\\." + number + "(?:\(dash)\(number))?"
            + verseSuffix + "(?!\(digit)|,\(digit)|\(space3)[\\uFF1A:]|\(latinWordAfterSpace))"
        // "am"은 독일어 "Joh 3,16 am Sonntag"(~에)와 겹쳐, 뒤에 문장부호·끝이 올 때만 시각으로 본다.
        let timePattern = "[ \\t\\u00A0]{0,2}(?:[AaPp]\\.[Mm]\\.|(?:AM|PM|pm)(?!\\p{L})|am(?=\(space3)(?:$|[^\\w\\s]))"
            + "|o['\\u2019]clock|[hH](?!\\p{L})|Uhr(?!\\p{L})|hrs?(?!\\p{L})|horas?(?!\\p{L})"
            + "|左右|出发|出發|开会|開會|集合|点钟|點鐘)"
        guard let colonTail = try? NSRegularExpression(pattern: colonPattern),
              let commaTail = try? NSRegularExpression(pattern: commaPattern),
              let cjkTail = try? NSRegularExpression(pattern: cjkPattern),
              let continuation = try? NSRegularExpression(pattern: continuationPattern),
              let commaContinuation = try? NSRegularExpression(pattern: commaContinuationPattern),
              let colonListItem = try? NSRegularExpression(pattern: colonListPattern),
              let commaListItem = try? NSRegularExpression(pattern: commaListPattern),
              let timeMarker = try? NSRegularExpression(pattern: timePattern) else { return nil }

        return LocalizedNames(
            root: root, startable: startable, fold: fold, colonTail: colonTail, commaTail: commaTail, cjkTail: cjkTail,
            continuation: continuation, commaContinuation: commaContinuation, colonListItem: colonListItem, commaListItem: commaListItem, timeMarker: timeMarker
        )
    }

    /// 이름 하나를 트라이에 넣는다. 키는 공백을 뺀 소문자 UTF-16 코드 단위다. 같은 키가 이미 있으면 먼저 넣은
    /// (우선순위가 높은) 표의 책을 유지하고, 같은 책이면 규칙을 합친다.
    private static func insertName(
        _ name: String, bookId: Int, isFullName: Bool, usesCommaNotation: Bool, isCommaNotationAppTable: Bool,
        into root: NameTrieNode, fold: inout [UInt16: UInt16]
    ) {
        var key: [UInt16] = []
        var original: [UInt16] = []
        var gapPositions = Set<Int>()
        var hasWhitespace = false
        for unit in name.utf16 {
            if Unicode.Scalar(unit)?.properties.isWhitespace == true {
                gapPositions.insert(key.count)
                hasWhitespace = true
                continue
            }
            if let last = key.last, isASCIIDigit(last), !isASCIIDigit(unit) {
                gapPositions.insert(key.count)
            }
            let lower = caseMapped(unit, upper: false)
            if lower != unit { fold[unit] = lower }
            let upper = caseMapped(lower, upper: true)
            if upper != lower { fold[upper] = lower }
            key.append(lower)
            original.append(unit)
        }
        guard !key.isEmpty else { return }

        let caseRule: NameCaseRule
        if !isFullName {
            caseRule = .exact
        } else if hasWhitespace || isASCIIDigit(key[0]) {
            caseRule = .insensitive
        } else if let firstCased = name.unicodeScalars.first(where: { $0.properties.changesWhenCaseMapped }),
                  firstCased.properties.isUppercase {
            caseRule = .initialUppercase
        } else {
            caseRule = .insensitive
        }

        var node = root
        for (index, unit) in key.enumerated() {
            if gapPositions.contains(index) { node.allowsGapBeforeNext = true }
            if let next = node.children[unit] {
                node = next
            } else {
                let next = NameTrieNode()
                node.children[unit] = next
                node = next
            }
        }
        let exactForm = String(decoding: original, as: UTF16.self)
        if var existing = node.entry {
            guard existing.bookId == bookId else { return }
            if caseRule.rawValue > existing.caseRule.rawValue { existing.caseRule = caseRule }
            existing.exactForms.insert(exactForm)
            existing.allSourcesUseCommaNotation = existing.allSourcesUseCommaNotation && usesCommaNotation
            existing.inCommaNotationAppTable = existing.inCommaNotationAppTable || isCommaNotationAppTable
            node.entry = existing
        } else {
            node.entry = NameEntry(
                bookId: bookId, caseRule: caseRule, exactForms: [exactForm],
                allSourcesUseCommaNotation: usesCommaNotation, inCommaNotationAppTable: isCommaNotationAppTable
            )
        }
    }

    /// 코드 단위 하나를 소문자(또는 대문자)로 바꾼다. 결과가 한 단위가 아니면(예: "İ") 그대로 둔다.
    private static func caseMapped(_ unit: UInt16, upper: Bool) -> UInt16 {
        guard let scalar = Unicode.Scalar(unit) else { return unit }
        let mapped = upper ? scalar.properties.uppercaseMapping : scalar.properties.lowercaseMapping
        let units = Array(mapped.utf16)
        return units.count == 1 ? units[0] : unit
    }

    private static func isASCIIDigit(_ unit: UInt16) -> Bool { (0x30...0x39).contains(unit) }

    private static func isHorizontalSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0xA0 }

    /// 이 글자로 시작하는 이름은 앞 글자가 단어 글자면 인정하지 않는다(대소문자가 있는 글자, 반각·전각 숫자).
    private static func requiresWordBoundary(_ unit: UInt16) -> Bool {
        if isASCIIDigit(unit) || (0xFF10...0xFF19).contains(unit) { return true }
        return Unicode.Scalar(unit)?.properties.changesWhenCaseMapped ?? false
    }

    /// `index` 바로 앞 글자(서로게이트 쌍이면 합친 스칼라)가 글자·결합 부호·10진 숫자인지.
    private static func isWordCharacter(before index: Int, in units: [UInt16]) -> Bool {
        guard index > 0 else { return false }
        let last = units[index - 1]
        let scalar: Unicode.Scalar?
        if UTF16.isTrailSurrogate(last), index >= 2, UTF16.isLeadSurrogate(units[index - 2]) {
            let value = 0x10000 + ((UInt32(units[index - 2]) - 0xD800) << 10) + (UInt32(last) - 0xDC00)
            scalar = Unicode.Scalar(value)
        } else {
            scalar = Unicode.Scalar(last)
        }
        guard let scalar else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber:
            return true
        default:
            return false
        }
    }

    /// 반각·전각 숫자 그룹을 정수로 읽는다. 그룹이 없으면 nil.
    private static func number(_ range: NSRange, in ns: NSString) -> Int? {
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        var value = 0
        for unit in ns.substring(with: range).utf16 {
            switch unit {
            case 0x30...0x39: value = value * 10 + Int(unit - 0x30)
            case 0xFF10...0xFF19: value = value * 10 + Int(unit - 0xFF10)
            default: return nil
            }
        }
        return value
    }

    /// 장은 그 책의 장 수 이하, 절은 번들 번역본의 그 장 마지막 절 이하인지. 마지막 절을 조회하지 못하면 절 검사는 건너뛴다.
    private static func isValidLocator(bookId: Int, chapter: Int?, verse: Int?) -> Bool {
        guard let chapter, chapter >= 1,
              let book = BooksProvider.shared.book(id: bookId), chapter <= book.chapterCount else { return false }
        guard let verse else { return true }
        guard verse >= 1 else { return false }
        if let last = maxVerse(bookId: bookId, chapter: chapter), verse > last { return false }
        return true
    }

    /// 시작 장절(`isValidLocator`)과 범위 끝을 함께 검사한다. 끝이 있으면
    /// - 장을 넘는 범위: 끝 장이 시작 장보다 크고 그 책의 장 수 이하이며, 끝 절이 그 장의 마지막 절 이하여야 한다.
    /// - 같은 장 범위(끝 장이 없거나 시작 장과 같은 "3:16-3:18"): 끝 절이 시작 절 이상이고 그 장의 마지막 절 이하여야 한다.
    /// - 끝 장이 0이거나 시작 장보다 작으면("3:1-0:5", "3:5-2:1") 거절한다.
    /// 끝이 범위를 넘으면 참조 전체를 거절한다(끝을 잘라 쓰지 않는다). "John 3:16-99", "Jude 1:3-2:4"는 오타이거나 성경 참조가
    /// 아닌 숫자일 가능성이 커서, 잘라 쓰면 원문에 없는 구간을 색인하게 된다. 한국어 경로(`expandRange`만 사용)에는 이 검사가 없다.
    private static func isValidReference(bookId: Int, chapter: Int?, verse: Int?, endChapter: Int?, endVerse: Int?) -> Bool {
        guard let verse, isValidLocator(bookId: bookId, chapter: chapter, verse: verse), let chapter else { return false }
        guard let endVerse else { return true }
        if let endChapter {
            if endChapter > chapter { return isValidLocator(bookId: bookId, chapter: endChapter, verse: endVerse) }
            guard endChapter == chapter else { return false }
        }
        return endVerse >= verse && isValidLocator(bookId: bookId, chapter: chapter, verse: endVerse)
    }

    /// 이름 끝(`index`)에서 마침표 하나, 공백 최대 3칸, "第" 하나를 건너뛴 다음 글자가 반각·전각 숫자인지.
    /// 꼬리 정규식(`colonTail`/`commaTail`/`cjkTail`)의 앞부분과 같은 조건이라, 이것이 거짓이면 셋 다 실패한다.
    private static func tailStartsWithDigit(_ units: [UInt16], at index: Int) -> Bool {
        let count = units.count
        var probe = index
        if probe < count, units[probe] == 0x2E { probe += 1 }
        var spaces = 0
        while probe < count, spaces < 3, isHorizontalSpace(units[probe]) || units[probe] == 0x3000 { probe += 1; spaces += 1 }
        if probe < count, units[probe] == 0x7B2C { probe += 1 } // "第"
        guard probe < count else { return false }
        return isASCIIDigit(units[probe]) || (0xFF10...0xFF19).contains(units[probe])
    }

    private static func passesCaseRule(_ entry: NameEntry, matchedUnits: [UInt16], matching: NameMatching) -> Bool {
        if matching == .searchQuery { return true }
        switch entry.caseRule {
        case .insensitive:
            return true
        case .exact:
            return entry.exactForms.contains(String(decoding: matchedUnits, as: UTF16.self))
        case .initialUppercase:
            let matched = String(decoding: matchedUnits, as: UTF16.self)
            guard let firstCased = matched.unicodeScalars.first(where: { $0.properties.changesWhenCaseMapped }) else { return true }
            return firstCased.properties.isUppercase
        }
    }

    /// `location`부터 최대 `regexWindow` 단위(문서 끝을 넘지 않게)에서 `regex`를 그 위치에 고정해 맞춰 본다.
    private static func anchoredMatch(_ regex: NSRegularExpression, in text: String, at location: Int, count: Int) -> NSTextCheckingResult? {
        guard location < count else { return nil }
        let range = NSRange(location: location, length: min(regexWindow, count - location))
        return regex.firstMatch(in: text, options: [.anchored], range: range)
    }

    /// 트라이를 따라 `start`에서 시작하는 이름 후보(긴 것이 뒤)를 모은다.
    private static func nameCandidates(
        at start: Int, units: [UInt16], names: LocalizedNames
    ) -> [(entry: NameEntry, end: Int, matchedUnits: [UInt16])] {
        let count = units.count
        var node = names.root
        var index = start
        var matchedUnits: [UInt16] = []
        var candidates: [(entry: NameEntry, end: Int, matchedUnits: [UInt16])] = []
        while true {
            if node !== names.root, node.allowsGapBeforeNext {
                var probe = index
                if let last = matchedUnits.last, isASCIIDigit(last), probe < count, units[probe] == 0x2E { probe += 1 }
                var spaces = 0
                while probe < count, spaces < 3, isHorizontalSpace(units[probe]) { probe += 1; spaces += 1 }
                if probe < count, node.children[names.fold[units[probe]] ?? units[probe]] != nil { index = probe }
            }
            guard index < count, let next = node.children[names.fold[units[index]] ?? units[index]] else { break }
            matchedUnits.append(units[index])
            node = next
            index += 1
            if let entry = node.entry { candidates.append((entry, index, matchedUnits)) }
        }
        return candidates
    }

    /// 한국어 매치 범위(`excluded`, 위치 오름차순) 밖에서 앱 언어 이름표 이름으로 된 참조를 찾는다.
    /// 결과는 위치 오름차순이며, 범위 표기·절 목록은 한국어와 같이 절마다 Match로 펼친다.
    private static func localizedMatches(
        in text: String, ns: NSString, names: LocalizedNames, excluding excluded: [NSRange], matching: NameMatching
    ) -> [(location: Int, match: Match)] {
        let units = Array(text.utf16)
        let count = units.count
        let skipped = excluded.sorted { $0.location < $1.location }
        var skipIndex = 0
        var results: [(location: Int, match: Match)] = []
        var position = 0

        while position < count {
            while skipIndex < skipped.count, NSMaxRange(skipped[skipIndex]) <= position { skipIndex += 1 }
            if skipIndex < skipped.count, skipped[skipIndex].location <= position {
                position = NSMaxRange(skipped[skipIndex])
                continue
            }
            let unit = units[position]
            guard names.startable[Int(unit)] else { position += 1; continue }
            if requiresWordBoundary(unit), isWordCharacter(before: position, in: units) { position += 1; continue }
            switch referenceStarting(at: position, units: units, text: text, ns: ns, names: names, matching: matching) {
            case .found(let matches, let end):
                results.append(contentsOf: matches)
                position = end
            case .rejectedName(let end):
                position = end
            case .noName:
                position += 1
            }
        }
        return results
    }

    private enum ReferenceScan {
        /// 참조를 읽었다. `end`는 이어지는 장절·절 목록까지 포함한 끝.
        case found([(location: Int, match: Match)], end: Int)
        /// 숫자가 뒤따르는 책 이름은 있었지만 장절 형식·범위·시각 표지 검사에서 떨어졌다. 그 이름 끝까지 건너뛴다.
        case rejectedName(end: Int)
        /// 이 위치에서 시작하는 (숫자가 뒤따르는) 이름이 없다.
        case noName
    }

    /// `start`에서 시작하는 이름 + 장절을 읽는다. 가장 긴 이름부터 규칙을 확인하고, 처음으로 꼬리 정규식이 맞은 이름에서
    /// 장절이 범위 밖이거나 시각 표지가 뒤따르면 더 짧은 이름으로 내려가지 않고 실패로 본다.
    private static func referenceStarting(
        at start: Int, units: [UInt16], text: String, ns: NSString, names: LocalizedNames, matching: NameMatching
    ) -> ReferenceScan {
        let count = units.count
        var recognizedEnd: Int?
        for candidate in nameCandidates(at: start, units: units, names: names).reversed() {
            // 정규식을 돌리기 전에 "이름 뒤 숫자" 규칙만 먼저 본다 — 이름 후보 대부분("John said")이 여기서 걸러진다.
            guard tailStartsWithDigit(units, at: candidate.end),
                  passesCaseRule(candidate.entry, matchedUnits: candidate.matchedUnits, matching: matching) else { continue }
            if recognizedEnd == nil { recognizedEnd = candidate.end }
            let bookId = candidate.entry.bookId
            let parsedChapter: Int?
            let parsedVerse: Int?
            var endChapter: Int?
            let endVerse: Int?
            let chapterGroup: NSRange
            let tail: NSTextCheckingResult
            let listItem: NSRegularExpression?
            if let colon = anchoredMatch(names.colonTail, in: text, at: candidate.end, count: count) {
                tail = colon
                listItem = names.colonListItem
                endChapter = number(colon.range(at: 3), in: ns)
            } else if candidate.entry.allowsCommaSeparator,
                      let comma = anchoredMatch(names.commaTail, in: text, at: candidate.end, count: count) {
                tail = comma
                listItem = names.commaListItem
                endChapter = number(comma.range(at: 3), in: ns)
            } else if let cjk = anchoredMatch(names.cjkTail, in: text, at: candidate.end, count: count) {
                tail = cjk
                listItem = nil
            } else {
                continue
            }
            chapterGroup = tail.range(at: 1)
            parsedChapter = number(tail.range(at: 1), in: ns)
            parsedVerse = number(tail.range(at: 2), in: ns)
            endVerse = number(tail.range(at: listItem == nil ? 3 : 4), in: ns)

            let tailEnd = NSMaxRange(tail.range)
            guard isValidReference(
                      bookId: bookId, chapter: parsedChapter, verse: parsedVerse, endChapter: endChapter, endVerse: endVerse
                  ),
                  let chapter = parsedChapter, let verse = parsedVerse,
                  anchoredMatch(names.timeMarker, in: text, at: tailEnd, count: count) == nil,
                  let range = Range(NSRange(location: start, length: tailEnd - start), in: text),
                  let chapterStart = Range(chapterGroup, in: text)?.lowerBound else {
                return .rejectedName(end: recognizedEnd ?? candidate.end)
            }
            let searchText = String(text[range]).trimmingCharacters(in: .whitespaces)
            var results: [(location: Int, match: Match)] = []
            let crossesChapter = (endChapter ?? 0) > chapter  // "3:16-3:18"은 같은 장 범위
            if let endVerse {
                let expanded = expandRange(
                    bookId: bookId, startChapter: chapter, startVerse: verse,
                    endChapter: crossesChapter ? endChapter : nil, endVerse: endVerse
                )
                for coordinate in expanded {
                    results.append((location: start, match: Match(
                        range: range, searchText: searchText, bookId: bookId,
                        chapter: coordinate.chapter, verse: coordinate.verse, chapterStart: chapterStart, kind: .reference
                    )))
                }
            } else {
                results.append((location: start, match: Match(
                    range: range, searchText: searchText, bookId: bookId, chapter: chapter, verse: verse,
                    chapterStart: chapterStart, kind: .reference
                )))
            }
            var end = tailEnd
            // 절 목록("3:16,18", "3,16.18")은 같은 장 안의 범위까지만 이어 읽는다(장을 넘는 범위 뒤의 절은 어느 장인지 모호).
            if let listItem, !crossesChapter {
                end = appendVerseList(
                    listItem, names: names, text: text, ns: ns, units: units, bookId: bookId, chapter: chapter,
                    segmentStart: start, startingAt: end, into: &results
                )
            }
            // 이어지는 장절은 앞 참조와 같은 표기로 읽는다(쉼표 표기 → "; 장,절", 그 밖 → "장:절").
            let usesCommaNotation = listItem === names.commaListItem
            end = appendContinuation(
                usesCommaNotation ? names.commaContinuation : names.continuation,
                listItem: usesCommaNotation ? names.commaListItem : names.colonListItem,
                names: names, text: text, ns: ns, units: units, bookId: bookId, startingAt: end, into: &results
            )
            return .found(results, end: end)
        }
        if let recognizedEnd { return .rejectedName(end: recognizedEnd) }
        return .noName
    }

    /// 절 목록 항목을 이어 읽어 `results`에 더하고 끝 위치를 돌려준다. 항목 번호가 숫자로 시작하는 책 이름의 일부면
    /// ("2 Kings 23:31, 2 Kings 24:18"의 ", 2") 멈춘다. 절·범위 끝이 범위 밖이거나 시각 표지가 뒤따라도 멈춘다.
    /// 항목 뒤에 공백과 라틴·키릴 글자가 오면 그 항목은 목록이 아니다("Acts 2:38, 39 people", "Ps 23:1, 1 and 2") — `colonListItem` 참고.
    /// `searchText`는 항목 숫자만이 아니라 `segmentStart`(앞 참조 또는 이어짐의 시작)부터 항목 끝까지다("John 3:16, 18") —
    /// ", 18"만으로는 문서 검색 문구(`DocumentViewerView.verseSearchLiteralTerms`)가 너무 일반적이라서다.
    private static func appendVerseList(
        _ listItem: NSRegularExpression, names: LocalizedNames, text: String, ns: NSString, units: [UInt16],
        bookId: Int, chapter: Int, segmentStart: Int, startingAt position: Int,
        into results: inout [(location: Int, match: Match)]
    ) -> Int {
        let count = units.count
        var cursor = position
        while let item = anchoredMatch(listItem, in: text, at: cursor, count: count), item.range.length > 0 {
            let itemEnd = NSMaxRange(item.range)
            guard !startsDigitPrefixedName(at: item.range(at: 1).location, units: units, names: names),
                  let verse = number(item.range(at: 1), in: ns),
                  isValidReference(
                      bookId: bookId, chapter: chapter, verse: verse, endChapter: nil, endVerse: number(item.range(at: 2), in: ns)
                  ),
                  anchoredMatch(names.timeMarker, in: text, at: itemEnd, count: count) == nil,
                  let matchRange = Range(item.range, in: text),
                  let segmentRange = Range(NSRange(location: segmentStart, length: itemEnd - segmentStart), in: text),
                  let chapterStart = Range(item.range(at: 1), in: text)?.lowerBound else { break }
            let searchText = String(text[segmentRange]).trimmingCharacters(in: .whitespaces)
            if let endVerse = number(item.range(at: 2), in: ns) {
                for coordinate in expandRange(bookId: bookId, startChapter: chapter, startVerse: verse, endChapter: nil, endVerse: endVerse) {
                    results.append((location: item.range.location, match: Match(
                        range: matchRange, searchText: searchText, bookId: bookId,
                        chapter: coordinate.chapter, verse: coordinate.verse, chapterStart: chapterStart, kind: .verseListItem
                    )))
                }
            } else {
                results.append((location: item.range.location, match: Match(
                    range: matchRange, searchText: searchText, bookId: bookId, chapter: chapter, verse: verse,
                    chapterStart: chapterStart, kind: .verseListItem
                )))
            }
            cursor = itemEnd
        }
        return cursor
    }

    /// `index`(숫자)에서 숫자로 시작하는 책 이름("2 Kings", "1 John", "1-я Царств")이 시작되는지.
    private static func startsDigitPrefixedName(at index: Int, units: [UInt16], names: LocalizedNames) -> Bool {
        nameCandidates(at: index, units: units, names: names).contains { candidate in
            candidate.matchedUnits.last.map { !isASCIIDigit($0) } ?? false
        }
    }

    /// 외국어 참조 뒤에 이름 없이 이어지는 "장:절"("Rom 8:28; 12:1", "创世记30:10-13；35:26") 또는 쉼표 표기의 "; 장,절"
    /// ("Joh 3,16; 4,2" — `continuation`·`listItem`으로 표기를 고른다)과 그 절 목록을 읽어
    /// `results`에 더하고 끝 위치를 돌려준다. `continuationMatches`와 같이 매치가 끊기거나 장절이 범위 밖이면 멈춘다.
    private static func appendContinuation(
        _ continuation: NSRegularExpression, listItem: NSRegularExpression, names: LocalizedNames,
        text: String, ns: NSString, units: [UInt16], bookId: Int, startingAt position: Int,
        into results: inout [(location: Int, match: Match)]
    ) -> Int {
        let count = units.count
        var cursor = position
        while let result = anchoredMatch(continuation, in: text, at: cursor, count: count), result.range.length > 0 {
            let resultEnd = NSMaxRange(result.range)
            let parsedChapter = number(result.range(at: 1), in: ns)
            let parsedVerse = number(result.range(at: 2), in: ns)
            let endChapter = number(result.range(at: 3), in: ns)
            let endVerse = number(result.range(at: 4), in: ns)
            guard isValidReference(
                      bookId: bookId, chapter: parsedChapter, verse: parsedVerse, endChapter: endChapter, endVerse: endVerse
                  ),
                  let chapter = parsedChapter, let verse = parsedVerse,
                  anchoredMatch(names.timeMarker, in: text, at: resultEnd, count: count) == nil,
                  let matchRange = Range(result.range, in: text),
                  let chapterStart = Range(result.range(at: 1), in: text)?.lowerBound else { break }
            let searchText = String(text[matchRange]).trimmingCharacters(in: .whitespaces)
            let crossesChapter = (endChapter ?? 0) > chapter  // "3:16-3:18"은 같은 장 범위
            if let endVerse {
                let expanded = expandRange(
                    bookId: bookId, startChapter: chapter, startVerse: verse,
                    endChapter: crossesChapter ? endChapter : nil, endVerse: endVerse
                )
                for coordinate in expanded {
                    results.append((location: result.range.location, match: Match(
                        range: matchRange, searchText: searchText, bookId: bookId,
                        chapter: coordinate.chapter, verse: coordinate.verse, chapterStart: chapterStart, kind: .continuation
                    )))
                }
            } else {
                results.append((location: result.range.location, match: Match(
                    range: matchRange, searchText: searchText, bookId: bookId, chapter: chapter, verse: verse,
                    chapterStart: chapterStart, kind: .continuation
                )))
            }
            cursor = resultEnd
            if !crossesChapter {
                cursor = appendVerseList(
                    listItem, names: names, text: text, ns: ns, units: units, bookId: bookId, chapter: chapter,
                    segmentStart: result.range.location, startingAt: cursor, into: &results
                )
            }
        }
        return cursor
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
