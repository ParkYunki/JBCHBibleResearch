//
//  SearchViewModel.swift
//  JBCHBibleResearch
//
//  S11(통합 검색) 상태 관리. 성경구절/개요/연구문서/메모/개인 묵상/말씀 요약
//  6분류 키워드 검색 결과를 채운다(screens.md S11 목업 그대로).
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
//  [2026-08-19 삭제] 사용자 요청 — "의미검색(AI) 기능 삭제, 관련 DB 삭제." 이
//  파일에 있던 [키워드 검색]/[의미검색(AI)] 모드 토글과 `EmbeddingChunk` 기반
//  코사인 유사도 검색을 통째로 뺐다.
//
//  [2026-08-19 신설, 이후 전면 교체] 사용자 요청 — "오른쪽 상단 검색창 왼쪽 옆
//  AI 토글 추가. 애플 인텔리전스기능으로 검색어를 성경장절로 변환하여
//  검색하도록." 처음엔 자유 문장을 FoundationModels로 "책이름장:절" 텍스트로
//  직접 변환해 키워드 검색에 흘려보내는 방식이었다. 그런데 "AI 검색을 잘
//  못함. 결과가 거의 나오지 않음"이라는 문제가 보고됐고, 뒤이어 "애플
//  인텔리전스로 텍스트를 정제하고, 방식 A — 임베딩 기반 의미검색을 한다면?" →
//  "이 새 파이프라인이 기존 AI 토글을 완전히 대체할까요?" → "완전 대체"로
//  방향이 바뀌었다. 지금 `isAIQueryEnabled`가 켜져 있으면
//  `BibleSemanticSearchService`(정제 → 임베딩 → 코사인 유사도 검색, 그 파일
//  상단 주석 참고)를 쓴다 — 더 이상 `BibleReferenceExtractor`/키워드 검색
//  경로를 거치지 않는다(AI 검색 결과는 이제 성경구절 섹션만 채운다 — 개요/
//  메모/문서 등은 임베딩 색인 대상이 아니라서 비운다).
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
    /// [2026-08-18 추가] 키워드 검색에서 강조할 단어들 — 성경구절 참조 자체로
    /// 직접 조회된 결과(`referenceMatchedVerses`)는 비워 둔다(정확히 그 절을
    /// 찾아온 것이라 특정 단어를 강조할 이유가 없다).
    var highlightKeywords: [String] = []
    /// 검색어 자체가 이 절을 가리키는 성경 참조였는지(예: "창1:3") — true면
    /// 목록 맨 위, 본문 검색으로 걸린 결과와 구분해 보여준다.
    var isReferenceMatch: Bool = false
    /// [2026-08-19 추가] AI 검색(의미검색) 결과에만 채워지는 코사인 유사도
    /// (`BibleSemanticSearchService.SemanticVerseMatch.similarity`) — 일반
    /// 키워드 검색 결과는 nil이다. `SearchView`가 이 값이 있으면 "참조 일치"
    /// 배지 대신 "유사도 xx%" 배지를 보여준다.
    var similarityScore: Double? = nil
}

struct MemoSearchResult: Identifiable {
    let memo: UserMemo
    var id: PersistentIdentifier { memo.persistentModelID }
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
    let pageNumber: Int?
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var matchedTagNames: [String] = []
    var highlightKeywords: [String] = []
}

@MainActor
@Observable
final class SearchViewModel {
    /// [2026-08-19 변경] 사용자 요청 — "택스트 입력시 자동검색은 빼도록. 중간중간
    /// 검색이 되는데, 프리징이 됨. 엔터를 쳐야만 검색이 되도록." 예전엔 타이핑을
    /// 멈추고 350ms 뒤 자동으로 검색됐는데, AI 검색의 무거운 계산(코사인 유사도
    /// brute-force, 31,102개 절 × 절/문맥 벡터 2개)이 타이핑 도중 반복 실행되며
    /// 화면이 멈추는 문제가 있었다. 이제 텍스트를 입력하는 것만으로는 검색이
    /// 실행되지 않는다 — 검색어가 비워졌을 때 결과만 정리하고, 실제 검색은
    /// `searchImmediately()`(엔터/검색 버튼, `SearchView`의 `.onSubmit(of:
    /// .search)`)로만 실행한다.
    var query: String = "" {
        didSet {
            searchTask?.cancel()
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearResults()
            }
        }
    }
    /// [2026-08-19 신설, 이후 전면 교체] 검색창 왼쪽 AI 토글 — 켜면 검색어를
    /// `BibleSemanticSearchService`(질의 정제 → 임베딩 → 코사인 유사도)로 의미
    /// 검색한다(아래 `performAIQuerySearch` 참고). 끄면(기본값) 예전과 같은 순수
    /// 키워드 검색. [2026-08-19 변경] 타이핑과 달리 토글을 켜고 끄는 건 한 번의
    /// 명시적 동작이라(연속 반복 호출이 아님) 여전히 곧바로 재검색한다.
    var isAIQueryEnabled = false {
        didSet { searchImmediately() }
    }

    /// [2026-08-19 신설] 사용자 요청 — "애플인텔리전스를 끈것과 켠것을 비교하고
    /// 싶음." 기본 켜짐(정제 사용) — 끄면 `BibleSemanticSearchService`가 1단계
    /// (Apple Intelligence 질의 정제)를 건너뛰고 사용자가 입력한 원문 그대로
    /// 임베딩한다. `SearchView`에 AI 토글이 켜져 있을 때만 보이는 보조 토글로
    /// 노출한다.
    var isQueryRefinementEnabled = true {
        didSet { searchImmediately() }
    }

    /// [2026-08-19 추가] 사용자 요청 — "Reranker도 고민해볼것." 임베딩 검색
    /// 결과(상위 10개)를 Apple Intelligence가 한 번 더 판단해 순서를 다듬는
    /// 마지막 단계 켬/끔. `isQueryRefinementEnabled`와 독립적인 별도 스위치다
    /// (`BibleSearchRerankerService.swift` 상단 주석 참고 — 두 AI 단계를 같은
    /// 스위치에 묶으면 어느 쪽이 결과를 개선했는지 구분할 수 없다).
    var isRerankEnabled = true {
        didSet { searchImmediately() }
    }

    /// [2026-08-19 v3 추가] 사용자 지시 — "verse/context weight 최적화... 0.4:
    /// 0.6으로 고정... 이것도 상당히 임의적인 값입니다... 0.2/0.8 ... 0.8/0.2
    /// 이렇게만 해도 검색 결과가 상당히 달라질 수 있습니다." 고정 상수 대신
    /// 슬라이더로 노출해 재빌드 없이 스윕 테스트할 수 있게 한다
    /// (`BibleSemanticSearchService.search(contextWeight:)` 참고). 절 가중치는
    /// `1 - contextWeight`. 기본값 0.6은 이전 고정값과 동일 — 출발점일 뿐 최적값
    /// 이라는 근거는 없다.
    var contextWeight: Double = 0.6 {
        didSet { searchImmediately() }
    }

    /// [2026-08-19 신설] 방금 AI 검색이 실제로 임베딩에 넘긴 문장 — 정제 토글을
    /// 켰을 때 원문이 어떻게 바뀌었는지 화면에 보여줘서 비교를 돕는다
    /// (`SearchView`의 "검색에 사용된 문장" 안내 참고). 일반 키워드 검색에서는
    /// 항상 nil.
    private(set) var lastAIQueryUsed: String?

    private(set) var verseResults: [VerseSearchResult] = []
    private(set) var memoResults: [MemoSearchResult] = []
    private(set) var documentResults: [DocumentSearchResult] = []
    private(set) var outlineResults: [OutlineSearchResult] = []
    private(set) var phraseNoteResults: [PhraseNoteSearchResult] = []
    private(set) var summaryResults: [SummarySearchResult] = []
    private(set) var isSearching = false
    var errorDescription: String?

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

    /// [2026-08-19 수정] 새 임베딩 의미검색이 들어오면서, 색인이 이미 있는지
    /// (파일 헤더만 읽는 가벼운 확인) 화면 진입 시점에 한 번 확인해 둔다 —
    /// 색인 자체를 여기서 만들지는 않는다(사용자가 명시적으로
    /// `startBibleEmbeddingIndexing()`을 눌러야 시작).
    func onAppear() {
        refreshBibleIndexStatus()
    }

    func onDisappear() {
        searchTask?.cancel()
        // [2026-08-19] 성경 전체 색인 작업(`EmbeddingIndexingService.shared`)은
        // 여기서 취소하지 않는다 — 그 Task는 이 화면(뷰모델)이 아니라 앱 전역
        // 싱글턴이 들고 있어서, 사용자가 검색 화면을 나가도 백그라운드에서 계속
        // 진행된다(수 분 걸릴 수 있는 일회성 작업을 화면 전환마다 처음부터
        // 다시 시작하게 만들고 싶지 않다).
    }

    // MARK: - 검색 실행 (엔터/토글 변경 시에만 — 타이핑 자동검색 없음)

    /// [2026-08-19] 사용자 요청 — "AI토글을 누를 때 두글자 이상 입력시 검색이
    /// 되도록." AI 검색은 한 글자마다 온디바이스 모델을 호출하면(타이핑 중간의
    /// "ㅎ", "하" 같은 미완성 입력에도 매번 호출) 낭비도 크고 어차피 그런
    /// 입력으로는 의미 있는 변환이 나올 수 없다 — 일반 키워드 검색(글자 수
    /// 제한 없음)과 달리 AI 검색만 최소 길이를 둔다.
    private static let minimumAIQueryLength = 2

    /// [2026-08-19] 검색어가 비었을 때(또는 AI 검색 최소 길이 미만일 때)
    /// 결과 상태를 한 번에 정리한다 — `query` didSet과 `searchImmediately()`
    /// 양쪽에서 쓴다.
    private func clearResults() {
        verseResults = []
        memoResults = []
        documentResults = []
        outlineResults = []
        phraseNoteResults = []
        summaryResults = []
        errorDescription = nil
        lastAIQueryUsed = nil
    }

    /// [2026-08-19 변경] 사용자 요청 — "엔터를 쳐야만 검색이 되도록." 예전엔
    /// 타이핑 멈추고 350ms 뒤 자동 검색(디바운스)됐는데, 그 자동 검색 자체를
    /// 없앴다 — 이제 이 함수(엔터/검색 버튼, `SearchView`의 `.onSubmit(of:
    /// .search)`, 그리고 AI/정제/재순위화 토글 변경 시)를 호출해야만 실제
    /// 검색(무거운 코사인 유사도 계산 포함)이 실행된다.
    func searchImmediately() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }
        if isAIQueryEnabled && trimmed.count < Self.minimumAIQueryLength {
            clearResults()
            return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.performSearch(query: trimmed)
        }
    }

    private func performSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }
        if isAIQueryEnabled {
            await performAIQuerySearch(query: query)
        } else {
            lastAIQueryUsed = nil
            performKeywordSearch(query: query)
        }
    }

    // MARK: - 키워드 검색

    /// [2026-08-18 대폭 확장] 6개 분류 전부를 채운다. 성경장절 인식(4가지 요구사항
    /// — 띄어쓰기 무시/약어↔전체이름/범위 포함)은 `BibleReferenceExtractor` 하나로
    /// 충족한다(`DocumentsHomeView.searchVerseQueryMatches` 상단 주석과 같은 근거).
    ///
    /// [2026-08-19 단순화] 한때 AI 토글 검색이 이 함수에 `referenceOnlyMatches`를
    /// 넘겨 재사용했었지만, AI 검색이 임베딩 기반 의미검색(`performAIQuerySearch`
    /// 참고)으로 완전히 바뀌면서 더 이상 이 함수를 거치지 않는다 — 순수 키워드
    /// 검색 전용으로 되돌렸다.
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

    // MARK: - AI 검색(임베딩 기반 의미검색, 2026-08-19 전면 교체)

    /// [2026-08-19] 사용자 요청 — "애플 인텔리전스로 텍스트를 정제하고, 방식 A —
    /// 임베딩 기반 의미검색을 한다면?" → "완전 대체". `isAIQueryEnabled`가 켜져
    /// 있을 때의 검색 경로를 `BibleSemanticSearchService`(정제→임베딩→코사인
    /// 유사도, 그 파일 상단 주석 참고)로 완전히 바꿨다 — 더 이상 키워드 검색
    /// 경로를 거치지 않는다. 의미검색은 성경 구절만 대상으로 하므로(개요/메모/
    /// 문서는 임베딩 색인 대상이 아니다) 나머지 5개 섹션은 항상 비운다.
    private func performAIQuerySearch(query: String) async {
        errorDescription = nil
        let result = await BibleSemanticSearchService.search(
            query: query, refinementEnabled: isQueryRefinementEnabled, rerankEnabled: isRerankEnabled,
            contextWeight: Float(contextWeight)
        )
        switch result {
        case .success(let outcome):
            verseResults = outcome.matches.map { match in
                VerseSearchResult(
                    bookId: match.bookId, chapter: match.chapter, verse: match.verse,
                    content: match.content,
                    bookNameKo: booksProvider.book(id: match.bookId)?.nameKo ?? "\(match.bookId)권",
                    similarityScore: Double(match.similarity)
                )
            }
            lastAIQueryUsed = outcome.queryUsedForEmbedding
        case .failure(let error):
            errorDescription = error.description
            verseResults = []
            lastAIQueryUsed = nil
        }
        memoResults = []; documentResults = []
        outlineResults = []; phraseNoteResults = []; summaryResults = []
    }

    // MARK: - 성경 전체 임베딩 색인 (2026-08-19 신설)

    /// AI 검색을 쓰려면 먼저 이 색인이 있어야 한다(`BibleSemanticSearchService.
    /// SearchError.indexNotReady`). `SearchView`가 이 상태를 보고 색인이 없으면
    /// "색인 만들기" 버튼을, 진행 중이면 진행률 바를 보여준다.
    ///
    /// [2026-08-19] `EmbeddingIndexingService`는 `@Observable`이 아닌 평범한
    /// `@MainActor` 싱글턴이라(그 Task를 화면 생명주기와 분리해 계속 돌리기
    /// 위한 선택 — `onDisappear()` 주석 참고), 그 내부 `status`가 바뀌어도
    /// SwiftUI가 자동으로 다시 그리지 않는다. 그래서 이 프로퍼티는 계산
    /// 프로퍼티가 아니라 저장 프로퍼티로 두고, 상태가 바뀌는 시점마다
    /// (`refreshBibleIndexStatus()`/진행률 콜백/완료 콜백) 명시적으로 대입해
    /// `@Observable`이 변경을 감지하게 한다.
    private(set) var bibleIndexStatus: EmbeddingIndexingService.IndexStatus = .notBuilt

    /// `onAppear()`에서 호출 — 파일 헤더만 읽는 가벼운 확인이라 매번 불러도 부담
    /// 없다(전체 로드는 실제 검색 시점에만, `EmbeddingIndexingService.ensureLoaded()`).
    func refreshBibleIndexStatus() {
        EmbeddingIndexingService.shared.refreshStatus()
        bibleIndexStatus = EmbeddingIndexingService.shared.status
    }

    func startBibleEmbeddingIndexing() {
        bibleIndexStatus = .building(progress: 0)
        EmbeddingIndexingService.shared.startBuilding(
            progress: { [weak self] fraction in self?.bibleIndexStatus = .building(progress: fraction) },
            completion: { [weak self] finalStatus in self?.bibleIndexStatus = finalStatus }
        )
    }

    func cancelBibleEmbeddingIndexing() {
        EmbeddingIndexingService.shared.cancelBuilding()
    }

    // MARK: - BibleReferenceStore 캐시(키워드 검색 공용)

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

}
