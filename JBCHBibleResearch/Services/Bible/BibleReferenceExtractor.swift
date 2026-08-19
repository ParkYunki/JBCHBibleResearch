//
//  BibleReferenceExtractor.swift
//  JBCHBibleResearch
//
//  [2026-08-11 신설] 사용자 요청 — "메모/연구문서 안에 성경 장절로 되어 있는 모든
//  성경 구절을 추출." 자유 텍스트 안에서 "요한복음 3:16" / "요 3장 16절" / "창1:1" /
//  "창세기 1장" 같은 표현을 정규식으로 찾아 (책, 장, 절?) 좌표로 바꾼다.
//
//  ⚠️ [스캔 범위, 의도적 단순화] 책 이름 뒤에 장 번호가 바로 붙어 있는 경우만 인식한다
//  (`(\d{1,3})`가 정규식에서 필수 그룹) — "요한복음"처럼 장 번호 없이 책 이름만 나온
//  문장은 추출하지 않는다. 장 번호 없는 순수 책 이름 언급은 애초에 "구절"을 가리키지
//  않아 이 기능(특정 절로 이동)의 대상이 아니고, 책 이름 약칭 중 일부(예: "요")가 흔한
//  한글 낱말과 겹칠 수 있어 뒤에 숫자가 없으면 오탐이 너무 잦아질 수 있다고 판단했다.
//
//  ⚠️ [오탐 가능성] 그래도 "약칭+숫자" 조합 자체가 성경 인용이 아닌 다른 문맥(예:
//  전화번호, 목록 번호)과 우연히 겹칠 가능성은 남아 있다 — 완벽한 자연어 이해 없이는
//  피할 수 없는 한계라, 이번 구현은 "놓치는 것보다 몇 개 오탐이 섞이는 편이 기능
//  자체로는 더 쓸모 있다"는 판단으로 진행했다. 실사용 중 오탐이 잦으면 추가 규칙
//  (예: 앞뒤 문맥에 숫자열이 더 있으면 제외)을 나중에 보강할 수 있다.
//
//  [2026-08-11 추가] 사용자 요청 — "성경 범위지정도 가능케 할것. ex) 갈1:6-9,
//  갈1:6~8 또는 갈1:24-2:1, 갈1:24~2:1 이런 범위지정도 각 구절별로 분해해서
//  각 구절에 관련문서정보가 있음을 알려줄것." 정규식에 범위 꼬리("-9"/"~8"처럼
//  같은 장 안의 범위, "-2:1"처럼 장을 넘어가는 범위)를 추가 그룹으로 인식하고,
//  매칭 하나당 `Match`를 여러 개(범위 안 절 개수만큼) 만들어 낸다 — 그래서
//  `Match`/`BibleReferenceIndexingService` 쪽 타입/로직은 전혀 바꾸지 않아도 된다
//  ("책+장+절 하나 = Match 하나"라는 기존 규약 그대로, 정규식 매치 하나가 Match
//  여러 개로 펼쳐질 뿐).
//
//  장을 넘어가는 범위("갈1:24-2:1")를 분해하려면 "1장이 몇 절까지 있는지" 알아야
//  다음 장(2장)으로 넘어갈 위치를 정할 수 있다 — 이 프로젝트엔 그 정보를 담은 정적
//  데이터(books.json 등)가 없어, 번들 기본 번역본(`TranslationBootstrap.
//  resolvedBundledDatabaseURL()`이 가리키는 BibleDB.sqlite)을 실제로 열어
//  `BibleReferenceStore.verses(bookId:chapter:)`로 그 장의 실제 절 개수를 조회한다.
//  ⚠️ [번역본 간 절 구분(versification) 차이 가능성] 번역본마다 장/절 나누는 지점이
//  한두 절 다를 수 있어, 사용자가 다른 번역본을 기준으로 인용했다면 경계 계산이
//  정확히 맞지 않을 수 있다 — 이 프로젝트에 "번역본과 무관하게 장별 절 개수"를
//  담은 정적 데이터가 따로 없어, 가장 신뢰할 수 있는 실제 데이터 소스인 번들
//  번역본을 기준으로 삼았다. 조회 자체가 실패하면(번들 DB 접근 실패 등) 추측하지
//  않고 시작 절 하나만 남긴다(아래 `expandRange` 참고).
//

import Foundation
import BibleResearchModels

@MainActor
enum BibleReferenceExtractor {
    struct Match {
        let range: Range<String.Index>
        /// 실제로 매칭된 원문 그대로(공백 트리밍만) — DB에 검색어로 저장한다. 범위
        /// 표기("갈1:6-9")가 여러 개의 Match로 펼쳐질 때도 이 값은 항상 원문 범위
        /// 표기 전체를 그대로 담는다(어느 절 하나만 잘라내지 않는다) — 사용자가
        /// 실제로 인용한 원문 그대로를 검색어/표시 문구로 남기기 위함.
        let searchText: String
        let bookId: Int
        let chapter: Int
        let verse: Int?
    }

    private struct Compiled {
        let regex: NSRegularExpression
        /// [2026-08-18 추가] 사용자 보고 — "살전 1:10. 2:19-20, 3:13, 4:13-18,
        /// 5:23)" 같은 문자열이 전부 데살로니가전서를 가리키는데 어디까지
        /// 추출되는지 확인해 달라는 요청. 실제로 확인해 보니 `regex`(위)는
        /// "살전 1:10"만 잡고 나머지는 전부 놓쳤다 — 책 이름이 매 항목 앞에
        /// 반복되지 않고 한 번만 나온 뒤 쉼표/마침표로 이어지는 관용적인 인용
        /// 표기(영어 성경 인용에서도 흔한 "1 Thess 1:10, 2:19-20, 3:13..." 방식)
        /// 는 `regex`의 "책 이름이 매 매치 앞에 있어야 한다"는 전제와 안
        /// 맞았기 때문이다. 이 정규식이 그 간극을 메운다 — `extract(from:)`가
        /// 주 매치를 찾은 직후, 그 매치 바로 뒤 위치부터 이 정규식을
        /// `.anchored`(그 위치에서 시작하는 매치만 허용)로 반복 적용해
        /// "구분자(,/.) + 장:절[-범위]" 패턴이 계속 이어지는 동안 같은 책으로
        /// 간주해 계속 뽑아낸다(`continuationMatches` 참고).
        ///
        /// ⚠️ [의도적 축소, 오탐 방지] "요 3:16, 17"처럼 장 없이 절만 이어지는
        /// 표기("같은 장 안의 추가 절")는 이 패턴에 없다 — 그 형태까지
        /// 지원하려면 구분자 뒤에 숫자 하나만 있어도 매치해야 하는데, 그러면
        /// "요 3:16, 1. 원칙"처럼 성경 인용과 전혀 무관한 번호 매김/날짜/비율
        /// 표기까지 절로 오인할 위험이 커진다(직접 시뮬레이션으로 확인함).
        /// "장:절" 형태(콜론 또는 "장"/"절" 글자로 장과 절이 둘 다 명시된
        /// 경우)만 이어지는 것으로 인정해 이 위험을 크게 줄였다 — 이번에
        /// 신고된 실제 사례(모두 "장:절" 형태)는 전부 커버한다.
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
        // [2026-08-20 수정, 버그 수정] 사용자 보고 — "창세기 1장 1절 -> 창1:1이나
        // 창1:5절, 창1:12으로 검색이 됨. 창1:1로 검색이 될 수 있도록." 실제로
        // Python `re`(ICU와 호환되는 부분집합)로 이 패턴을 직접 재현해 확인한
        // 결과, "N장 M절"(장/절 조사가 숫자 뒤에 붙는 표준 한글 어순 — 파일
        // 상단 주석이 지원 예시로 든 "요 3장 16절"도 포함)을 넣으면 절 그룹이
        // 통째로 매칭 실패해 "책+장"까지만 잡히고 절 정보가 사라졌다(verse가
        // nil). 원인은 바로 아래 옛 패턴의 `[:,절]`— 이건 절 앞에 구분자로
        // ':'/','/'절' 문자가 "먼저" 와야 한다는 뜻인데, "1장 1절"은 숫자
        // "1" 뒤에 "절"이 붙는 어순이라 앞쪽에 구분자가 없다. verse가 nil이면
        // (챕터만 있는 참조로 취급되면) 아래 `extract(from:)`가 만드는 `Match`도
        // `verse: nil`이 되고, 그 Match가 다른 `VerseMention`과 좌표 비교될 때
        // (`query.verse == nil || ...`, DocumentViewerView.verseSearchLiteralTerms/
        // SearchViewModel.verseMentionSearchTexts 등 여러 곳에서 반복되는 규칙)
        // "장이 같으면 절 상관없이 다 일치"로 취급돼 — 정확히 신고된 증상
        // (1절로 검색했는데 5절/12절짜리도 걸림)과 들어맞는다.
        //
        // 고침 — 절 앞에 구분자가 있는 기존 경로(그룹2, ":"/","+숫자, 뒤에
        // "절"은 있어도 없어도 됨)에 더해, 구분자 없이 "숫자+절"만으로도 절로
        // 인정하는 두 번째 경로(그룹3, 대신 뒤의 "절"은 필수 — 그래야 순수
        // 숫자를 함부로 절로 오인하지 않는다, 이 파일 상단 "오탐 가능성" 주석과
        // 같은 원칙)를 추가했다. 그룹3이 새로 끼어들면서 범위 끝 그룹 번호가
        // 하나씩 밀렸다 — 그룹4 = 범위 끝 장(선택, "-2:1"처럼 장까지 다시
        // 적었을 때만), 그룹5 = 범위 끝 절(선택, "-9"/"~8"/"-2:1"의 마지막
        // 숫자). 아래 `extract(from:)`도 이 번호에 맞춰 함께 고쳤다.
        //
        // ⚠️ [건드리지 않은 부분] 아래 `continuationRegex`("장:절" 형태만
        // 인정)는 그대로 뒀다 — 그 옆 주석이 이미 "숫자+절" 형태까지 넓히면
        // 오탐 위험이 커진다고 명시적으로 판단해 둔 것이라(연속 인용 스캔은
        // 임의의 뒤따르는 텍스트를 계속 훑는 더 위험한 문맥), 새 정보 없이
        // 그 판단을 뒤집지 않았다.
        let pattern = "(?:\(bookAlternation))\\s*(\\d{1,3})\\s*장?\\s*"
            + "(?:(?:[:,]\\s*(\\d{1,3})\\s*절?|(\\d{1,3})\\s*절)"
            + "(?:\\s*[-~]\\s*(?:(\\d{1,3})\\s*[:장]\\s*)?(\\d{1,3})\\s*절?)?"
            + ")?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        // [2026-08-18 추가] 위 `Compiled.continuationRegex` 주석 참고 — 책 이름
        // 없이 "구분자(,/.) + 장:절[-범위]"만 이어지는 항목을 잡는다. `^`로
        // 시작을 고정하고(`extract`가 `.anchored` 옵션으로 특정 위치에서부터만
        // 매치하도록 호출하므로 사실 `^` 없이도 동작은 같지만, 의도를 명확히
        // 남기려고 넣었다). 그룹1=장, 그룹2=절(둘 다 필수 — "장:절" 형태만
        // 인정), 그룹3=범위 끝 장(선택), 그룹4=범위 끝 절(선택) — 메인 패턴의
        // 그룹3/4와 같은 규칙.
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
            // [2026-08-18 추가] 이 주 매치 바로 뒤에 "책 이름 없이 이어지는
            // 장:절" 항목이 있으면 같은 책으로 간주해 계속 뽑는다 — 아래 세
            // 분기(장만/절 하나/범위) 어느 쪽이든 공통으로 적용해야 하므로,
            // 각 분기가 자기 Match를 추가한 직후 이 호출을 반복한다.
            let continuationStart = result.range.location + result.range.length

            let chapterRange = result.range(at: 1)
            guard chapterRange.location != NSNotFound,
                  let chapter = Int(ns.substring(with: chapterRange)), chapter > 0 else { return }
            let searchText = matchedText.trimmingCharacters(in: .whitespaces)

            // [2026-08-20 수정] 위 `pattern` 상단 주석 참고 — 절 그룹이 이제 둘로
            // 나뉜다(그룹2 = "구분자+숫자" 경로, 그룹3 = "숫자+절" 경로). 어느
            // 한쪽만 매칭되므로 둘 중 실제로 값이 있는 쪽을 쓴다.
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

    /// [2026-08-18 신설] 사용자 보고 — "살전 1:10. 2:19-20, 3:13, 4:13-18,
    /// 5:23)"가 전부 데살로니가전서를 가리키는데 어디까지 추출되는지 확인해
    /// 달라는 요청. 확인 결과 원래 `regex`는 "살전 1:10"만 잡고 나머지 네
    /// 항목을 전부 놓쳤다(직접 시뮬레이션으로 검증) — 이 함수가 그 간극을
    /// 메운다. `position`(주 매치 바로 뒤)부터 시작해 `continuationRegex`를
    /// `.anchored`(그 위치에서 시작하는 매치만 인정, 뒤쪽을 넘겨짚어 찾지
    /// 않음)로 반복 적용한다 — 매치가 안 되는 순간(구분자+숫자 조합이 더 이상
    /// 안 이어지면) 바로 멈춘다. 그래서 "살전 1:10, 그런데 다른 얘기..."처럼
    /// 중간에 성경 인용이 아닌 텍스트가 끼면 그 즉시 멈추고, 이후에 다시
    /// 나오는 숫자를 엉뚱하게 이어붙이지 않는다.
    ///
    /// ⚠️ 이 함수는 `장:절` 형태(둘 다 명시)만 이어지는 것으로 인정한다 —
    /// `Compiled.continuationRegex` 상단 주석의 오탐 방지 설명 참고.
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

            // 다음 이어지는 항목을 찾으려면 방금 소비한 만큼 앞으로 당긴다 —
            // 무한 루프 방지를 위해 매치 길이가 0이면(이론상 일어날 수 없지만
            // 방어적으로) 멈춘다.
            guard result.range.length > 0 else { break }
            pos = result.range.location + result.range.length
        }
        return results
    }

    /// 사이드바/팝오버 미리보기용 — 매치 위치를 포함한 줄과 앞뒤 한 줄씩(최대 3줄)을
    /// 잘라 돌려준다.
    static func snippet(for match: Match, in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return match.searchText }
        let offset = text.distance(from: text.startIndex, to: match.range.lowerBound)
        var runningLength = 0
        var lineIndex = 0
        for (index, line) in lines.enumerated() {
            let lineLength = line.count + 1 // 개행 포함
            if offset < runningLength + lineLength {
                lineIndex = index
                break
            }
            runningLength += lineLength
        }
        let start = max(0, lineIndex - 1)
        let end = min(lines.count - 1, lineIndex + 1)
        let snippet = lines[start...end].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? match.searchText : snippet
    }
}
