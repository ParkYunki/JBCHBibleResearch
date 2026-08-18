//
//  SearchViewModel.swift
//  JBCHBibleResearch
//
//  S11(통합 검색/의미검색) 상태 관리. [키워드 검색]/[의미검색(AI)] 토글에 따라
//  성경구절/내 메모/연구문서 3분류 결과를 채운다(screens.md S11 목업 그대로).
//
//  [2026-08-18 대폭 확장] 사용자 요청 — "왼쪽 사이드바 맨 위 상단 검색기능 ...
//  이전 대화의 내용의 연구문서 리스트 검색 기능처럼 성경 장절 검색기능이
//  포함되도록. - 검색 결과를 표현하는 것도 연구문서 리스트 검색 결과처럼
//  검색일치 횟수+ 태그 + 본문내용+ 형광펜 강조 ... 성경 조회 / 개요 / 연구문서 /
//  메모 / 개인 묵상 / 말씀 요약 --> 모든 내용이 다 검색 되어야 함." 키워드 검색을
//  6개 분류(성경구절/개요/연구문서/메모(VersePhraseNote)/개인 묵상(UserMemo)/
//  말씀 요약(VerseSummary))로 넓히고, 결과 표현을 `DocumentsHomeView.searchScore`가
//  이미 정립해 둔 방식(띄어쓰기 단어별 OR 매칭 + 태그 뱃지 + "(xx 회 일치)" 본문
//  발췌 + 형광펜 강조 + 성경장절 인식)과 통일한다 — 정확히 같은 로직을 공유하는
//  대신(그 화면 것은 여전히 `DocumentText`가 페이지/줄 단위인 문서 전용 구조라
//  타입이 다르다), 이 파일 안에 같은 원리로 새로 작성했다(이 프로젝트가 이미
//  택한 "세 번째 사용처가 생기기 전엔 공통 헬퍼로 추출하지 않는다" 원칙 —
//  `SearchViewModel.storeCache` 상단 주석 참고).
//
//  ⚠️ [범위 결정] 의미검색(AI) 모드는 이번 확장 대상이 아니다 — 사용자 요청
//  문구가 명시한 것(일치 횟수/태그/본문/형광펜)은 전부 키워드 검색 특유의
//  개념이고, `DocumentsHomeView` 쪽 원본 기능도 키워드 검색 전용이었다. 의미
//  검색은 기존 3분류(성경구절/개인 묵상/연구문서, `EmbeddingChunk.sourceType`
//  범위 그대로)를 그대로 유지한다 — 개요/메모/말씀 요약까지 의미검색 색인
//  파이프라인(`EmbeddingIndexingService`)을 넓히는 건 이번 요청 범위 밖의 별도
//  작업이라 판단했다.
//

import Foundation
import SwiftData
import Observation
import BibleResearchModels

struct VerseSearchResult: Identifiable {
    var id: String { "\(bookId)-\(chapter)-\(verse)" }
    let bookId: Int
    let chapter: Int
    let verse: Int
    let content: String
    let bookNameKo: String
    /// 의미검색일 때만 채워진다(0~1, 코사인 유사도). 키워드 검색 결과는 nil.
    var score: Float?
    /// [2026-08-18 추가] 키워드 검색에서 강조할 단어들 — 성경구절 참조 자체로
    /// 직접 조회된 결과(`referenceMatchedVerses`)는 비워 둔다(정확히 그 절을
    /// 찾아온 것이라 특정 단어를 강조할 이유가 없다).
    var highlightKeywords: [String] = []
    /// 검색어 자체가 이 절을 가리키는 성경 참조였는지(예: "창1:3") — true면
    /// 목록 맨 위, 본문 검색으로 걸린 결과와 구분해 보여준다.
    var isReferenceMatch: Bool = false
}

struct MemoSearchResult: Identifiable {
    let memo: UserMemo
    var id: PersistentIdentifier { memo.persistentModelID }
    var score: Float?
    /// 의미검색 결과의 스니펫(고정 80자). 키워드 검색은 `bodyExcerpt`를 쓴다.
    var snippet: String = ""
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var matchedTagNames: [String] = []
    var highlightKeywords: [String] = []
}

struct SummarySearchResult: Identifiable {
    let summary: VerseSummary
    var id: PersistentIdentifier { summary.persistentModelID }
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var matchedTagNames: [String] = []
    var highlightKeywords: [String] = []
}

/// [2026-08-18 신설] "메모" — `VersePhraseNote`(절 안의 특정 구간에 짧게 붙이는
/// 200자 미만 텍스트, `VerseAnnotations.swift` 상단 주석 참고). 개인 묵상
/// (`UserMemo`, 리치 텍스트 저널)과는 별개 모델이다.
struct PhraseNoteSearchResult: Identifiable {
    let note: VersePhraseNote
    var id: PersistentIdentifier { note.persistentModelID }
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var highlightKeywords: [String] = []
    /// 검색어가 이 메모가 붙은 절을 가리키는 성경 참조였는지 — `noteText`
    /// 자체엔 매칭이 없어도(예: 참조만 입력) 이 값이 true면 목록에 포함한다.
    var isReferenceMatch: Bool = false
}

/// [2026-08-18 신설] "개요" — 책 단위(`BookOutline`)와 장 단위(`ChapterSummary`)
/// 두 모델을 `WordNoteItem`(WordNoteHomeView.swift)과 같은 원칙으로 얇게
/// 감싼다 — 데이터 자체를 합치지 않고 표시/검색만 한 목록으로 다룬다.
enum OutlineSearchKind {
    case book(BookOutline)
    case chapter(ChapterSummary)
}

struct OutlineSearchResult: Identifiable {
    let kind: OutlineSearchKind
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var highlightKeywords: [String] = []
    /// 검색어가 이 개요의 책(+장)을 가리키는 성경 참조였는지.
    var isReferenceMatch: Bool = false

    var id: String {
        switch kind {
        case .book(let outline): return "outline-book-\(outline.id.uuidString)"
        case .chapter(let summary): return "outline-chapter-\(summary.id.uuidString)"
        }
    }
    var bookId: Int {
        switch kind {
        case .book(let outline): return outline.bookId
        case .chapter(let summary): return summary.bookId
        }
    }
    var chapter: Int? {
        switch kind {
        case .book: return nil
        case .chapter(let summary): return summary.chapter
        }
    }
    var contentText: String {
        switch kind {
        case .book(let outline): return outline.contentText
        case .chapter(let summary): return summary.contentText
        }
    }
    var updatedAt: Date {
        switch kind {
        case .book(let outline): return outline.updatedAt
        case .chapter(let summary): return summary.updatedAt
        }
    }
}

struct DocumentSearchResult: Identifiable {
    let document: SourceDocument
    var id: PersistentIdentifier { document.persistentModelID }
    /// 의미검색(문서는 페이지 단위 청크)에서만 채워진다.
    let pageNumber: Int?
    var score: Float?
    var snippet: String = ""
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var matchedTagNames: [String] = []
    var highlightKeywords: [String] = []
}

@MainActor
@Observable
final class SearchViewModel {
    enum Mode: String, CaseIterable {
        case keyword = "키워드 검색"
        case semantic = "의미검색(AI)"
    }

    var query: String = "" {
        didSet { scheduleSearch() }
    }
    var mode: Mode = .keyword {
        didSet { scheduleSearch() }
    }

    private(set) var verseResults: [VerseSearchResult] = []
    private(set) var memoResults: [MemoSearchResult] = []
    private(set) var documentResults: [DocumentSearchResult] = []
    /// [2026-08-18 추가] 아래 세 분류는 키워드 검색 전용(의미검색 범위 밖 —
    /// 파일 상단 "범위 결정" 주석 참고)이라, 의미검색 모드에서는 항상 빈 배열로
    /// 남는다.
    private(set) var outlineResults: [OutlineSearchResult] = []
    private(set) var phraseNoteResults: [PhraseNoteSearchResult] = []
    private(set) var summaryResults: [SummarySearchResult] = []
    private(set) var isSearching = false
    var errorDescription: String?

    private(set) var embeddingAvailability: EmbeddingService.Availability = .unknown
    private(set) var isReindexingMemosAndDocuments = false

    /// 성경 전체 장 단위 색인(수동 트리거) 진행 상태.
    private(set) var isReindexingBible = false
    private(set) var bibleIndexProgress: (done: Int, total: Int)?
    private var bibleIndexTask: Task<Void, Never>?

    private let modelContext: ModelContext
    private let booksProvider: BooksProvider
    private var searchTask: Task<Void, Never>?
    /// registry.sqliteFileReference(또는 번들 경로) 기준 BibleReferenceStore 캐시.
    /// BibleReadingViewModel.store(for:)와 같은 목적의 캐시를 여기서도 별도로
    /// 둔다 — 화면(뷰모델)마다 독립된 상태라 공유 싱글턴으로 묶지 않았다(같은
    /// 이유로 두 번째 발생이지만, 아직 세 번째 사용처가 없어 공통 헬퍼로
    /// 추출하지는 않았다 — 오버엔지니어링 방지 원칙, README 참고).
    private var storeCache: [String: BibleReferenceStore] = [:]

    init(modelContext: ModelContext, booksProvider: BooksProvider? = nil) {
        self.modelContext = modelContext
        self.booksProvider = booksProvider ?? .shared
    }

    func onAppear() {
        Task {
            await EmbeddingService.shared.prepareIfNeeded()
            embeddingAvailability = EmbeddingService.shared.availability
        }
        Task {
            isReindexingMemosAndDocuments = true
            await EmbeddingIndexingService.reindexMemosAndDocuments(context: modelContext)
            isReindexingMemosAndDocuments = false
            // 색인이 막 끝난 시점에 이미 의미검색 모드로 검색어가 입력돼 있었을 수
            // 있으니 한 번 더 검색을 갱신한다.
            if mode == .semantic { scheduleSearch() }
        }
    }

    func onDisappear() {
        searchTask?.cancel()
        bibleIndexTask?.cancel()
    }

    // MARK: - 성경 전체 색인(수동)

    func startBibleReindex() {
        guard !isReindexingBible else { return }
        bibleIndexTask?.cancel()
        isReindexingBible = true
        bibleIndexProgress = nil
        bibleIndexTask = Task { [weak self] in
            guard let self else { return }
            guard let (registry, store) = self.defaultBibleStore() else {
                self.isReindexingBible = false
                return
            }
            await EmbeddingIndexingService.reindexBundledBibleChapters(
                context: self.modelContext,
                store: store,
                books: self.booksProvider.books,
                translationCode: registry.code
            ) { done, total in
                Task { @MainActor in
                    self.bibleIndexProgress = (done, total)
                }
            }
            self.isReindexingBible = false
            if self.mode == .semantic { self.scheduleSearch() }
        }
    }

    func cancelBibleReindex() {
        bibleIndexTask?.cancel()
        isReindexingBible = false
    }

    // MARK: - 검색 디바운스

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            verseResults = []
            memoResults = []
            documentResults = []
            outlineResults = []
            phraseNoteResults = []
            summaryResults = []
            errorDescription = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(query: trimmed)
        }
    }

    private func performSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }
        switch mode {
        case .keyword:
            performKeywordSearch(query: query)
        case .semantic:
            await performSemanticSearch(query: query)
        }
    }

    // MARK: - 키워드 검색

    /// [2026-08-18 대폭 확장] 6개 분류 전부를 채운다. 성경장절 인식(4가지 요구사항
    /// — 띄어쓰기 무시/약어↔전체이름/범위 포함)은 `BibleReferenceExtractor` 하나로
    /// 충족한다(`DocumentsHomeView.searchVerseQueryMatches` 상단 주석과 같은 근거).
    private func performKeywordSearch(query: String) {
        errorDescription = nil
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        let queryMatches = BibleReferenceExtractor.extract(from: query)

        verseResults = searchVerses(query: query, words: words, queryMatches: queryMatches)
        outlineResults = searchOutlines(words: words, queryMatches: queryMatches)
        phraseNoteResults = searchPhraseNotes(words: words, queryMatches: queryMatches)
        memoResults = searchMemos(words: words, queryMatches: queryMatches)
        summaryResults = searchSummaries(words: words, queryMatches: queryMatches)
        documentResults = searchDocuments(words: words, queryMatches: queryMatches)
    }

    // MARK: - 키워드 검색: 공통 단어 매칭 헬퍼

    /// `DocumentsHomeView.searchScore(for:)`와 같은 원리 — 검색어를 띄어쓰기로
    /// 쪼갠 각 단어(+성경구절 원문 표현)가 `contentText` 안에 몇 번 나오는지 세고,
    /// 첫 등장 위치 기준 발췌를 만든다.
    private struct WordMatchScore {
        let bodyOccurrenceSum: Int
        let bodyExcerpt: String?
        let highlightKeywords: [String]
        let distinctTermMatchCount: Int
        var isTextMatch: Bool { distinctTermMatchCount > 0 }
    }

    private func computeWordMatchScore(words: [String], verseTerms: [String], contentText: String) -> WordMatchScore {
        var seenTerms = Set<String>()
        let allTerms = (words + verseTerms).filter { seenTerms.insert($0.lowercased()).inserted }
        guard !allTerms.isEmpty else {
            return WordMatchScore(bodyOccurrenceSum: 0, bodyExcerpt: nil, highlightKeywords: [], distinctTermMatchCount: 0)
        }

        var occurrenceCounts: [String: Int] = [:]
        var firstExcerpts: [String: String] = [:]
        for term in allTerms where !term.isEmpty {
            var searchRange = contentText.startIndex..<contentText.endIndex
            while let found = contentText.range(of: term, options: [.caseInsensitive], range: searchRange) {
                occurrenceCounts[term, default: 0] += 1
                if firstExcerpts[term] == nil {
                    let tailEnd = contentText.index(found.upperBound, offsetBy: 9, limitedBy: contentText.endIndex) ?? contentText.endIndex
                    firstExcerpts[term] = String(contentText[found.lowerBound..<tailEnd])
                }
                searchRange = found.upperBound..<contentText.endIndex
            }
        }
        var distinctTermMatchCount = occurrenceCounts.keys.count
        // `verseTerms`(성경장절 원문 표현)가 이론상 본문에서 못 찾아졌더라도
        // (예: 범위 확장 경계 오차) 매칭 자체는 이미 확정된 사실이라 최소 1은
        // 반영한다 — `DocumentsHomeView.searchScore`와 같은 방어적 규칙.
        if !verseTerms.isEmpty && verseTerms.allSatisfy({ occurrenceCounts[$0] == nil }) {
            distinctTermMatchCount += 1
        }
        let bodyOccurrenceSum = occurrenceCounts.values.reduce(0, +)
        let bodyExcerpt = Self.buildSnippet(words: allTerms, excerpts: firstExcerpts)
        return WordMatchScore(
            bodyOccurrenceSum: bodyOccurrenceSum, bodyExcerpt: bodyExcerpt,
            highlightKeywords: allTerms, distinctTermMatchCount: distinctTermMatchCount
        )
    }

    /// `DocumentsHomeView.buildContentSnippet`과 완전히 같은 규칙 — 단어별
    /// "첫 등장+뒤 9자" 발췌를 " ... "로 이어붙이고 70자에서 자른다.
    private static func buildSnippet(words: [String], excerpts: [String: String]) -> String? {
        let segments = words.compactMap { excerpts[$0] }
        guard !segments.isEmpty else { return nil }
        let joined = segments.joined(separator: " ... ")
        guard joined.count > 70 else { return joined }
        let cutIndex = joined.index(joined.startIndex, offsetBy: 70)
        return String(joined[..<cutIndex]) + "…"
    }

    /// `sourceType`/`sourceId`에 걸린 `VerseMention`들 중 이번 검색어의 성경 참조와
    /// 겹치는 것들의 원문 표현(중복 제거) — `DocumentsHomeView.verseMentionSearchTexts`와
    /// 같은 로직을, memo/document/wordSummary 세 소스 타입에 공용으로 쓸 수 있게
    /// 일반화했다.
    private func verseMentionSearchTexts(
        mentions: [VerseMention], sourceType: VerseMentionSourceType, sourceId: String,
        queryMatches: [BibleReferenceExtractor.Match]
    ) -> [String] {
        guard !queryMatches.isEmpty else { return [] }
        var seen = Set<String>()
        return mentions
            .filter { mention in
                guard mention.sourceType == sourceType, mention.sourceId == sourceId else { return false }
                return queryMatches.contains { query in
                    query.bookId == mention.bookId
                        && query.chapter == mention.chapter
                        && (query.verse == nil || mention.verse == nil || query.verse == mention.verse)
                }
            }
            .map(\.searchText)
            .filter { seen.insert($0).inserted }
    }

    // MARK: - 키워드 검색: 성경구절

    /// [2026-08-18 확장] 검색어가 성경 참조로 해석되면(`queryMatches`) 그 절(들)을
    /// 직접 조회해 맨 앞에 보여준다 — 창1:3으로 검색하면 본문에 "1:3"이라는
    /// 글자가 없어도 정확히 창세기 1:3이 나와야 하기 때문("연구문서 리스트 검색
    /// 기능처럼 성경 장절 검색기능이 포함되도록" 요청 그대로). 그 외엔 기존처럼
    /// 각 단어를 `BibleReferenceStore.searchVerses`(본문 텍스트 검색)로 OR
    /// 조회한다.
    private func searchVerses(query: String, words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [VerseSearchResult] {
        guard let registries = try? modelContext.fetch(FetchDescriptor<TranslationRegistry>()) else { return [] }
        var seen = Set<String>()
        var results: [VerseSearchResult] = []

        for registry in registries {
            guard let store = try? store(for: registry) else { continue }
            let versionCode = store.hasVersionCodeColumn ? registry.code : nil

            for match in queryMatches {
                let candidateVerses: [BibleVerse]
                if let verseNumber = match.verse {
                    // [2026-08-18 수정, 컴파일 에러] `store.verse(...)`가 `throws
                    // -> BibleVerse?`라 `try?`를 붙이면 Swift 5(SE-0230)부터는
                    // `BibleVerse??`로 이중 래핑되지 않고 `BibleVerse?` 하나로
                    // 자동 평탄화된다 — `guard let`을 두 번 걸면(이전 코드) 첫
                    // 단계에서 이미 `BibleVerse`까지 풀려 두 번째 `let`이 옵셔널이
                    // 아닌 값을 다시 언래핑하려 해 컴파일 에러가 났다. 한 번만
                    // 언래핑한다.
                    guard let verse = try? store.verse(bookId: match.bookId, chapter: match.chapter, verse: verseNumber, versionCode: versionCode) else { continue }
                    candidateVerses = [verse]
                } else {
                    candidateVerses = (try? store.verses(bookId: match.bookId, chapter: match.chapter, versionCode: versionCode)) ?? []
                }
                for verse in candidateVerses {
                    let key = "\(verse.bookId)-\(verse.chapter)-\(verse.verse)"
                    guard seen.insert(key).inserted else { continue }
                    results.append(VerseSearchResult(
                        bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse,
                        content: verse.content,
                        bookNameKo: booksProvider.book(id: verse.bookId)?.nameKo ?? "\(verse.bookId)권",
                        isReferenceMatch: true
                    ))
                    if results.count >= 30 { return results }
                }
            }
        }

        for registry in registries {
            guard let store = try? store(for: registry) else { continue }
            let versionCode = store.hasVersionCodeColumn ? registry.code : nil
            for word in words {
                guard let verses = try? store.searchVerses(query: word, versionCode: versionCode, limit: 30) else { continue }
                for verse in verses {
                    let key = "\(verse.bookId)-\(verse.chapter)-\(verse.verse)"
                    guard seen.insert(key).inserted else { continue }
                    results.append(VerseSearchResult(
                        bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse,
                        content: verse.content,
                        bookNameKo: booksProvider.book(id: verse.bookId)?.nameKo ?? "\(verse.bookId)권",
                        highlightKeywords: words
                    ))
                    if results.count >= 30 { return results }
                }
            }
        }
        return results
    }

    // MARK: - 키워드 검색: 개요

    /// [2026-08-18 신설] `BookOutline`(책 단위)/`ChapterSummary`(장 단위) — 둘 다
    /// 자기 자신이 "이 책(+장)에 대한 개요"라는 성경 좌표를 이미 갖고 있어(문서/
    /// 메모처럼 본문을 스캔해 성경구절을 뽑을 필요 없이) 검색어의 성경 참조와
    /// 자기 좌표가 겹치는지만 보면 된다.
    private func searchOutlines(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [OutlineSearchResult] {
        let bookOutlines = (try? modelContext.fetch(
            FetchDescriptor<BookOutline>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []
        let chapterSummaries = (try? modelContext.fetch(
            FetchDescriptor<ChapterSummary>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []

        var results: [(result: OutlineSearchResult, score: Int)] = []

        for outline in bookOutlines {
            let refMatch = queryMatches.contains { $0.bookId == outline.bookId }
            let wordScore = computeWordMatchScore(words: words, verseTerms: [], contentText: outline.contentText)
            guard refMatch || wordScore.isTextMatch else { continue }
            let result = OutlineSearchResult(
                kind: .book(outline), bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                highlightKeywords: wordScore.highlightKeywords, isReferenceMatch: refMatch
            )
            results.append((result, wordScore.distinctTermMatchCount + (refMatch ? 1 : 0)))
        }
        for summary in chapterSummaries {
            let refMatch = queryMatches.contains { $0.bookId == summary.bookId && $0.chapter == summary.chapter }
            let wordScore = computeWordMatchScore(words: words, verseTerms: [], contentText: summary.contentText)
            guard refMatch || wordScore.isTextMatch else { continue }
            let result = OutlineSearchResult(
                kind: .chapter(summary), bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                highlightKeywords: wordScore.highlightKeywords, isReferenceMatch: refMatch
            )
            results.append((result, wordScore.distinctTermMatchCount + (refMatch ? 1 : 0)))
        }
        return results.sorted { $0.score > $1.score }.map(\.result)
    }

    // MARK: - 키워드 검색: 메모(VersePhraseNote)

    private func searchPhraseNotes(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [PhraseNoteSearchResult] {
        let notes = (try? modelContext.fetch(
            FetchDescriptor<VersePhraseNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []
        var results: [(result: PhraseNoteSearchResult, score: Int)] = []
        for note in notes {
            let refMatch = queryMatches.contains { query in
                query.bookId == note.bookId && query.chapter == note.chapter
                    && (query.verse == nil || query.verse == note.verse)
            }
            let wordScore = computeWordMatchScore(words: words, verseTerms: [], contentText: note.noteText)
            guard refMatch || wordScore.isTextMatch else { continue }
            let result = PhraseNoteSearchResult(
                note: note, bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                highlightKeywords: wordScore.highlightKeywords, isReferenceMatch: refMatch
            )
            results.append((result, wordScore.distinctTermMatchCount + (refMatch ? 1 : 0)))
        }
        return results.sorted { $0.score > $1.score }.map(\.result)
    }

    // MARK: - 키워드 검색: 개인 묵상(UserMemo)

    private func searchMemos(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [MemoSearchResult] {
        let memos = (try? modelContext.fetch(
            FetchDescriptor<UserMemo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []
        let mentions = queryMatches.isEmpty ? [] : ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
        var results: [(result: MemoSearchResult, score: Int)] = []
        for memo in memos {
            let tagNames = (memo.memoTags ?? []).compactMap { $0.tag?.name }
            let tagCount = words.filter { word in tagNames.contains { $0.localizedCaseInsensitiveContains(word) } }.count
            var seenTagNames = Set<String>()
            let matchedTagNames = tagNames.filter { name in
                words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
            }
            let verseTerms = verseMentionSearchTexts(mentions: mentions, sourceType: .memo, sourceId: memo.id.uuidString, queryMatches: queryMatches)
            let wordScore = computeWordMatchScore(words: words, verseTerms: verseTerms, contentText: memo.contentText)
            guard tagCount > 0 || wordScore.isTextMatch else { continue }
            let result = MemoSearchResult(
                memo: memo, bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                matchedTagNames: matchedTagNames, highlightKeywords: wordScore.highlightKeywords
            )
            results.append((result, tagCount + wordScore.distinctTermMatchCount))
        }
        return results.sorted { $0.score > $1.score }.map(\.result)
    }

    // MARK: - 키워드 검색: 말씀 요약(VerseSummary)

    private func searchSummaries(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [SummarySearchResult] {
        let summaries = (try? modelContext.fetch(
            FetchDescriptor<VerseSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )) ?? []
        let mentions = queryMatches.isEmpty ? [] : ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
        var results: [(result: SummarySearchResult, score: Int)] = []
        for summary in summaries {
            let tagNames = (summary.summaryTags ?? []).compactMap { $0.tag?.name }
            let tagCount = words.filter { word in tagNames.contains { $0.localizedCaseInsensitiveContains(word) } }.count
            var seenTagNames = Set<String>()
            let matchedTagNames = tagNames.filter { name in
                words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
            }
            let verseTerms = verseMentionSearchTexts(mentions: mentions, sourceType: .wordSummary, sourceId: summary.id.uuidString, queryMatches: queryMatches)
            let wordScore = computeWordMatchScore(words: words, verseTerms: verseTerms, contentText: summary.contentText)
            guard tagCount > 0 || wordScore.isTextMatch else { continue }
            let result = SummarySearchResult(
                summary: summary, bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                matchedTagNames: matchedTagNames, highlightKeywords: wordScore.highlightKeywords
            )
            results.append((result, tagCount + wordScore.distinctTermMatchCount))
        }
        return results.sorted { $0.score > $1.score }.map(\.result)
    }

    // MARK: - 키워드 검색: 연구문서(SourceDocument)

    /// `DocumentsHomeView.searchScore(for:)`와 원리는 같지만, 이 화면은 문서
    /// 전체를 대상으로 하므로(그 화면은 카테고리 필터를 먼저 거친 뒤였다) 모든
    /// `SourceDocument`를 훑는다. 태그/파일명/본문을 굳이 3단계로 나눠 정렬하던
    /// 그 화면의 예전 방식 대신, 최종 확정 규칙("검색결과 정렬은 일치하는 갯수
    /// 내림차순")을 그대로 따른다.
    private func searchDocuments(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [DocumentSearchResult] {
        let documents = (try? modelContext.fetch(
            FetchDescriptor<SourceDocument>(sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)])
        )) ?? []
        let mentions = queryMatches.isEmpty ? [] : ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
        var results: [(result: DocumentSearchResult, score: Int)] = []
        for document in documents {
            let tagNames = (document.documentTags ?? []).compactMap { $0.tag?.name }
            let tagCount = words.filter { word in tagNames.contains { $0.localizedCaseInsensitiveContains(word) } }.count
            var seenTagNames = Set<String>()
            let matchedTagNames = tagNames.filter { name in
                words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
            }

            var titleFields = [document.originalFilename]
            if let category = document.category { titleFields.append(category.name) }
            let titleCount = words.filter { word in titleFields.contains { $0.localizedCaseInsensitiveContains(word) } }.count

            let lines = (document.documentTexts ?? []).sorted {
                $0.pageNumber != $1.pageNumber ? $0.pageNumber < $1.pageNumber : $0.lineIndex < $1.lineIndex
            }
            let combinedText = lines.map(\.lineText).joined(separator: "\n")
            let verseTerms = verseMentionSearchTexts(mentions: mentions, sourceType: .document, sourceId: document.id.uuidString, queryMatches: queryMatches)
            let wordScore = computeWordMatchScore(words: words, verseTerms: verseTerms, contentText: combinedText)

            guard tagCount > 0 || titleCount > 0 || wordScore.isTextMatch else { continue }
            let result = DocumentSearchResult(
                document: document, pageNumber: nil,
                bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                matchedTagNames: matchedTagNames, highlightKeywords: wordScore.highlightKeywords
            )
            results.append((result, tagCount + titleCount + wordScore.distinctTermMatchCount))
        }
        return results.sorted { $0.score > $1.score }.map(\.result)
    }

    // MARK: - 의미검색

    private func performSemanticSearch(query: String) async {
        guard EmbeddingService.shared.availability == .available else {
            embeddingAvailability = EmbeddingService.shared.availability
            errorDescription = semanticUnavailableMessage(for: EmbeddingService.shared.availability)
            verseResults = []; memoResults = []; documentResults = []
            outlineResults = []; phraseNoteResults = []; summaryResults = []
            return
        }
        guard let queryVector = EmbeddingService.shared.embed(query) else {
            errorDescription = "검색어를 해석하지 못했습니다."
            return
        }
        guard let chunks = try? modelContext.fetch(FetchDescriptor<EmbeddingChunk>()), !chunks.isEmpty else {
            errorDescription = nil
            verseResults = []; memoResults = []; documentResults = []
            outlineResults = []; phraseNoteResults = []; summaryResults = []
            return
        }
        errorDescription = nil
        // [2026-08-18 참고] 의미검색은 개요/메모/말씀 요약을 다루지 않는다(파일
        // 상단 "범위 결정" 주석 참고) — 이 모드로 전환하면 그 세 목록은 그대로
        // 비워 둔다.
        outlineResults = []
        phraseNoteResults = []
        summaryResults = []

        // schema.md 4장 확정 방식 — brute-force 코사인 유사도. ⚠️ 성능 유의사항(S11
        // 원문)도 그대로 적용된다: 청크 수가 아주 많아지면(특히 성경 전체 색인 후)
        // 이 루프가 오래 걸릴 수 있다 — 이번 구현은 async 컨텍스트에서 돌려 최소한
        // UI를 완전히 멈추지는 않지만, 실제 대규모 성능은 실기기 검증이 필요하다.
        var scored: [(chunk: EmbeddingChunk, score: Float)] = []
        scored.reserveCapacity(chunks.count)
        // [2026-08-07 수정] screens.md S11 성능 유의사항 — 청크 수가 많아지면 이
        // 루프가 오래 걸릴 수 있다고 명시돼 있었는데, 지금까지는 async 함수 안에
        // 있다는 것만으로 UI가 안 멈춘다고 (잘못) 적어 뒀다. 실제로는 이 for 루프
        // 자체가 await 지점 없이 MainActor에서 끝까지 동기 실행되므로, 도중에
        // SwiftUI가 화면을 다시 그릴 기회가 전혀 없어 청크가 많을 때 입력 중
        // 끊김이 그대로 발생한다 — 200개마다 Task.yield()로 다른 작업(렌더링 등)에
        // 제어를 양보한다.
        for (index, chunk) in chunks.enumerated() {
            let vector = chunk.embeddingVector.asFloatArray
            guard !vector.isEmpty else { continue }
            let score = EmbeddingService.shared.cosineSimilarity(queryVector, vector)
            scored.append((chunk, score))
            if index % 200 == 199 {
                await Task.yield()
            }
        }
        scored.sort { $0.score > $1.score }
        // ⚠️ 0.3 임계값은 임의 지정이다 — 실측 후 조정 필요(스펙에 근거 없음).
        let top = scored.filter { $0.score > 0.3 }.prefix(60)

        var newVerseResults: [VerseSearchResult] = []
        var newMemoResults: [MemoSearchResult] = []
        var newDocumentResults: [DocumentSearchResult] = []

        for entry in top {
            switch entry.chunk.sourceType {
            case .verse:
                guard let ref = entry.chunk.verseRef else { continue }
                newVerseResults.append(VerseSearchResult(
                    bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse,
                    content: entry.chunk.chunkText,
                    bookNameKo: booksProvider.book(id: ref.bookId)?.nameKo ?? "\(ref.bookId)권",
                    score: entry.score
                ))
            case .memo:
                guard let uuid = UUID(uuidString: entry.chunk.sourceId) else { continue }
                var descriptor = FetchDescriptor<UserMemo>(predicate: #Predicate { $0.id == uuid })
                descriptor.fetchLimit = 1
                guard let memo = try? modelContext.fetch(descriptor).first else { continue }
                newMemoResults.append(MemoSearchResult(
                    memo: memo,
                    score: entry.score,
                    snippet: String(entry.chunk.chunkText.prefix(80))
                ))
            case .document:
                guard let uuid = UUID(uuidString: entry.chunk.sourceId) else { continue }
                var descriptor = FetchDescriptor<SourceDocument>(predicate: #Predicate { $0.id == uuid })
                descriptor.fetchLimit = 1
                guard let document = try? modelContext.fetch(descriptor).first else { continue }
                newDocumentResults.append(DocumentSearchResult(
                    document: document, pageNumber: entry.chunk.chunkIndex,
                    score: entry.score,
                    snippet: String(entry.chunk.chunkText.prefix(80))
                ))
            }
        }

        verseResults = newVerseResults
        memoResults = newMemoResults
        documentResults = newDocumentResults
    }

    private func semanticUnavailableMessage(for availability: EmbeddingService.Availability) -> String {
        switch availability {
        case .unsupportedLanguage:
            return "이 기기에서 한국어 의미검색 모델을 지원하지 않습니다."
        case .assetPreparationFailed(let reason):
            return "의미검색 모델을 준비하지 못했습니다: \(reason)"
        case .unknown, .available:
            return "의미검색을 준비하는 중입니다."
        }
    }

    // MARK: - BibleReferenceStore 캐시(키워드 검색 + 성경 전체 색인 공용)

    private func store(for registry: TranslationRegistry) throws -> BibleReferenceStore {
        // 2026-08-07(S12): BibleReadingViewModel.store(for:)와 동일한 이유로
        // TranslationFileMaterializer를 거친다 — TranslationFileMaterializer.swift
        // 상단 주석 참고.
        // [2026-08-14 수정] BibleReadingViewModel.store(for:)와 같은 이유 —
        // 번들 번역본이 둘로 늘어나 `registry.code`로 구분해야 한다.
        let path = registry.isBundled
            ? try TranslationBootstrap.resolvedBundledDatabaseURL(for: registry.code).path
            : try TranslationFileMaterializer.ensureMaterialized(registry, context: modelContext)
        if let cached = storeCache[path] { return cached }
        let store = try BibleReferenceStore(filePath: path)
        storeCache[path] = store
        return store
    }

    /// 성경 전체 색인은 여러 번역본을 동시에 처리하지 않는다(스펙에 다중 번역본
    /// 동시 색인 요구가 없고, 규모를 키우는 선택이라 근거 없이 확장하지 않았다) —
    /// 등록된 번역본 중 첫 번째(보통 번들 KRV)만 색인 대상으로 삼는다.
    private func defaultBibleStore() -> (TranslationRegistry, BibleReferenceStore)? {
        guard let registries = try? modelContext.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt, order: .forward)])),
              let first = registries.first,
              let store = try? store(for: first) else { return nil }
        return (first, store)
    }
}
