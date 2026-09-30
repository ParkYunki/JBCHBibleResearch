//
//  SearchViewModel.swift
//  JBCHBibleResearch
//
//  S11(통합 검색) 상태 관리. 성경구절/개요/연구문서/메모/개인 묵상/말씀 요약/내 설교 분류별 키워드
//  검색 결과를 채운다.
//  결과 표현(단어별 OR 매칭 + 태그 뱃지 + 본문 발췌 + 형광펜 강조 + 성경장절 인식)은
//  `DocumentsHomeView.searchScore`와 같은 원리로 이 파일에 따로 작성했다(세 번째
//  사용처가 생기기 전엔 공통 헬퍼로 추출하지 않는다 — `storeCache` 주석 참고).
//  `isAIQueryEnabled`가 켜져 있으면 `BibleSemanticSearchService`(정제
//  → 임베딩 → 코사인 유사도)로 의미 검색하며, 이때는 성경구절 섹션만 채운다(개요/메모/문서 등은
//  임베딩 색인 대상이 아님).
//

import Foundation
import SwiftData
import Observation
import BibleResearchModels

struct VerseSearchResult: Identifiable {
    // 같은 절이 번역본마다 별도 결과로 존재할 수 있으므로 id에 translationCode를 포함한다(id가
    // 겹치면 `ForEach`가 행을 뒤섞거나 누락한다).
    var id: String { "\(bookId)-\(chapter)-\(verse)-\(translationCode)" }
    let bookId: Int
    let chapter: Int
    let verse: Int
    let content: String
    let bookNameKo: String
    /// 검색결과 행의 "선택"/"복사" 버튼이 이 절이 나온 번역본을 알아야 해서 화면까지 전달한다.
    let translationCode: String
    let translationDisplayName: String
    /// 키워드 검색에서 강조할 단어들. 성경 참조로 직접 조회된
    /// 결과(`referenceMatchedVerses`)는 비워 둔다.
    var highlightKeywords: [String] = []
    /// 검색어 자체가 이 절을 가리키는 성경 참조였는지(예: "창1:3") — true면
    /// 목록 맨 위, 본문 검색으로 걸린 결과와 구분해 보여준다.
    var isReferenceMatch: Bool = false
    /// 중복 제거된 매칭 검색어 수(`matchedWordCount`) — 랭킹 tie-break와 같은
    /// 값이다(`BibleKeywordMatching.swift` 참고). 본문 내 총 등장 횟수가 아니다. 참조
    /// 매치는 단어 점수를 계산하지 않아 0이며, 0이면 화면에서 배지를 숨긴다.
    var matchCount: Int = 0
}

struct MemoSearchResult: Identifiable {
    let memo: UserMemo
    var id: PersistentIdentifier { memo.persistentModelID }
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var matchedTagNames: [String] = []
    var highlightKeywords: [String] = []
    /// 중복 제거된 매칭 검색어 수(`WordMatchScore.distinctTermMatchCount`). 화면
    /// 표시와 정렬이 성경구절 탭과 같은 값을 쓴다.
    var matchedWordCount: Int = 0
}

struct SummarySearchResult: Identifiable {
    let summary: VerseSummary
    var id: PersistentIdentifier { summary.persistentModelID }
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var matchedTagNames: [String] = []
    var highlightKeywords: [String] = []
    /// `MemoSearchResult.matchedWordCount`와 같은 의미.
    var matchedWordCount: Int = 0
}

/// "메모" — `VersePhraseNote`(절 안의 특정 구간에 붙이는 200자 미만 텍스트). 개인
/// 묵상(`UserMemo`)과는 별개 모델이다.
struct PhraseNoteSearchResult: Identifiable {
    let note: VersePhraseNote
    var id: PersistentIdentifier { note.persistentModelID }
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var highlightKeywords: [String] = []
    /// 검색어가 이 메모가 붙은 절을 가리키는 성경 참조였는지 — `noteText`
    /// 자체엔 매칭이 없어도(예: 참조만 입력) 이 값이 true면 목록에 포함한다.
    var isReferenceMatch: Bool = false
    /// `MemoSearchResult.matchedWordCount`와 같은 의미.
    var matchedWordCount: Int = 0
}

/// "개요" — 책 단위(`BookOutline`)와 장 단위(`ChapterSummary`)를
/// `WordNoteItem`과 같은 원칙으로 얇게 감싸, 데이터는 합치지 않고 표시/검색만 한 목록으로
/// 다룬다.
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
    /// `MemoSearchResult.matchedWordCount`와 같은 의미.
    var matchedWordCount: Int = 0

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
    /// `MemoSearchResult.matchedWordCount`와 같은 의미.
    var matchedWordCount: Int = 0
}

/// "내 설교" 검색 결과 — `DocumentSearchResult`와 같은 모양이며, 설교문엔 PDF 페이지
/// 개념이 없어 `pageNumber`만 뺐다.
struct SermonSearchResult: Identifiable {
    let sermon: Sermon
    var id: PersistentIdentifier { sermon.persistentModelID }
    var bodyExcerpt: String?
    var bodyOccurrenceSum: Int = 0
    var matchedTagNames: [String] = []
    var highlightKeywords: [String] = []
    var matchedWordCount: Int = 0
}

@MainActor
@Observable
final class SearchViewModel {
    /// 텍스트 입력만으로는 검색하지 않는다(타이핑 중 AI 검색의 무거운 계산이 반복 실행되어 화면이 멈췄다).
    /// 비워지면 결과만 정리하고, 실제 검색은 `searchImmediately()`(엔터/검색 버튼)로만
    /// 실행한다.
    var query: String = "" {
        didSet {
            searchTask?.cancel()
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearResults()
            }
        }
    }
    /// 검색창 왼쪽 AI 토글 — 켜면 `BibleSemanticSearchService`로 의미
    /// 검색(`performAIQuerySearch` 참고), 끄면(기본값) 순수 키워드 검색. 토글은 명시적 단발
    /// 동작이라 곧바로 재검색한다.
    var isAIQueryEnabled = false {
        didSet { searchImmediately() }
    }

    // `BibleSemanticSearchService.search`는 Apple Intelligence 질의
    // 정제/재순위화를 호출하지 않는다(결정론적 `stripTrailingMetaPhrase`와 LLM이 아닌
    // `BibleStructuralRerankerService`만 항상 적용). `BibleQueryRefinem
    // entService.refine`/`BibleSearchRerankerService`는 호출되지 않지만
    // 나중에 다시 연결할 수 있도록 파일을 보관한다.
    //
    // 절/문맥 가중치는 `search`의 `contextWeight` 매개변수(기본 0.6)로만 남아 있고
    // 호출부는 기본값을 쓴다(`performAIQuerySearch` 참고). 0.6은 최적값이라는 근거가 없는
    // 출발점이다.

    /// 방금 AI 검색이 실제로 임베딩에 넘긴 문장(`SearchView`의 "검색에 사용된 문장" 안내에 표시).
    /// 일반 키워드 검색에서는 항상 nil.
    private(set) var lastAIQueryUsed: String?

    /// Layer 1(`QueryIntentClassifier`) + Layer
    /// 2(`QueryIntentHandler`) 결과 — 검색어가 관계/인물·지명 정보/예언/주제·속성/서사 중
    /// 하나로 읽히면 해당 카테고리의 실제 데이터를 담는다. `SearchView`가 결과 목록 맨 위에 카드로
    /// 보여준다.
    /// `isAIQueryEnabled`가 켜져 있을 때만 계산되고 순수 키워드 검색에서는 항상
    /// nil이다(`performSearch` 참고). `performAIQuerySearch`는
    /// `QueryIntentCard.verseRefs`를 "성경구절" 섹션에도 활용한다.
    private(set) var intentCard: QueryIntentCard?

    /// AI 카드가 항목을 여러 개 찾았을 때 사용자가 탭해 단일 항목 상세로 들어간 행의
    /// 인덱스(`intentCard`가 가리키는 배열의 인덱스만 담는다). 항목이 1개뿐이면
    /// `SearchView`가 이 값과 무관하게 자동으로 상세를 보여준다. 이전 검색의 선택이 새 결과에 잘못
    /// 대응되지 않도록 새 검색 시작 시 항상 nil로
    /// 되돌린다(`clearResults`/`performSearch`).
    var aiCardSelectedIndex: Int?

    /// `searchVerses`가 돌려준 매칭 절 전체(무제한, 성경순 정렬). 화면엔
    /// `visibleVerseResultCount`만큼 자른 `verseResults`만 보여주며, "더보기"는
    /// DB를 다시 조회하지 않고 노출 개수만 늘린다.
    private(set) var allVerseResults: [VerseSearchResult] = []

    /// "더보기 확인창" 조건 판단(`effectiveMatchedWordCount()`)에 쓰는, 이번 키워드
    /// 검색에 쓰인 단어 목록. `performKeywordSearch`만 채우고, AI 검색은 단어 개념이 없어
    /// 빈 배열이므로 확인창 조건(2개 이상)을 만족하지 않는다.
    private var lastSearchWords: [String] = []

    /// "더보기 확인창"을 이번 검색에서 이미 보여줬는지(검색 1회당 최초 1번).
    /// `setVerseResults`가 새 결과를 채울 때 함께 리셋된다.
    private var hasShownMoreResultsNotice = false

    /// nil이 아니면 `SearchView`가 alert을 띄운다(두 단어 이상 검색 후 더보기 시). "확인"을
    /// 누르면 `confirmMoreResultsNotice()`로 닫히고 더보기가 이어서 진행된다.
    struct MoreResultsNotice: Identifiable {
        let id = UUID()
        /// 아직 화면에 보여주지 않은 결과(`allVerseResults`의
        /// `visibleVerseResultCount` 이후)에 걸친 서로 다른 성경책 수. "성경별"은 번역본이
        /// 아니라 책 단위이며, 메모리에 있는 데이터에서 직접 센 값이다.
        let additionalBookCount: Int
    }
    private(set) var pendingMoreResultsNotice: MoreResultsNotice?
    // 저장 프로퍼티 초기화식 안에서는 `Self`를 참조할 수 없어 타입 이름을 직접 쓴다(메서드 본문에서는
    // `Self` 사용 가능).
    private var visibleVerseResultCount = SearchViewModel.verseResultPageSize
    // "더보기" 한 번에 노출하는 개수(DB를 다시 조회하지 않는다).
    private static let verseResultPageSize = 50

    var verseResults: [VerseSearchResult] {
        Array(allVerseResults.prefix(visibleVerseResultCount))
    }

    /// 성경 검색 결과를 장 단위로 묶어 표시한다. `verseResults`의 순서는 유지한 채 그룹만 다시
    /// 나열하는 순수 표시용이라 `allVerseResults`/`verseResults`(가중치 랭킹, 더보기
    /// 기준)는 건드리지 않는다. 그룹 안 절은 절 번호 오름차순.
    ///
    /// 그룹 정렬: 그룹 안 최대 `matchCount`(중복 제거된 매칭 검색어 수,
    /// `VerseSearchResult.matchCount` 참고) 내림차순이 1순위, 같은 값끼리만
    /// 정경순(책ID/장 오름차순).
    struct VerseSearchResultGroup: Identifiable {
        let bookId: Int
        let chapter: Int
        let bookNameKo: String
        let verses: [VerseSearchResult]
        var id: String { "\(bookId)-\(chapter)" }
    }

    /// 절 목록을 장 단위로 묶고 매치 강도순으로 정렬하는 공용 헬퍼 —
    /// `groupedVerseResults`(전체 기준)와
    /// `groupedVerseResults(translationCode:)`(번역본별 기준)가 입력만 달리해
    /// 공유한다.
    private static func groupByChapter(_ results: [VerseSearchResult]) -> [VerseSearchResultGroup] {
        var versesByChapter: [String: [VerseSearchResult]] = [:]
        var orderedKeys: [(bookId: Int, chapter: Int)] = []
        for result in results {
            let key = "\(result.bookId)-\(result.chapter)"
            if versesByChapter[key] == nil {
                orderedKeys.append((bookId: result.bookId, chapter: result.chapter))
            }
            versesByChapter[key, default: []].append(result)
        }
        let groups = orderedKeys.map { key -> VerseSearchResultGroup in
            let verses = (versesByChapter["\(key.bookId)-\(key.chapter)"] ?? [])
                .sorted { $0.verse < $1.verse }
            return VerseSearchResultGroup(
                bookId: key.bookId,
                chapter: key.chapter,
                bookNameKo: verses.first?.bookNameKo ?? "",
                verses: verses
            )
        }
        return groups.sorted { lhs, rhs in
            let lhsMaxMatchCount = lhs.verses.map(\.matchCount).max() ?? 0
            let rhsMaxMatchCount = rhs.verses.map(\.matchCount).max() ?? 0
            if lhsMaxMatchCount != rhsMaxMatchCount { return lhsMaxMatchCount > rhsMaxMatchCount }
            return (lhs.bookId, lhs.chapter) < (rhs.bookId, rhs.chapter)
        }
    }

    var groupedVerseResults: [VerseSearchResultGroup] {
        Self.groupByChapter(verseResults)
    }

    /// 번역본별 하위 탭용 — 현재 화면 노출분 `verseResults`를 `translationCode`로 거른
    /// 뒤 장 단위로 그룹핑한다. "더보기"는 번역본과 무관하게 `allVerseResults` 하나로
    /// 페이지네이션하므로, 결과가 적게 로드된 번역본 탭은 더보기를 여러 번 눌러야 결과가 더 나타날 수 있다.
    func groupedVerseResults(translationCode: String) -> [VerseSearchResultGroup] {
        Self.groupByChapter(verseResults.filter { $0.translationCode == translationCode })
    }

    /// "현재 활성화된 번역본" —
    /// `BibleReadingViewModel.displayedTranslationIDs`(해당 뷰모델의 런타임
    /// 상태)에 접근할 수 없어, `loadAvailableTranslations()`가 처음 표시 번역본을 정할
    /// 때 쓰는 영속화된 규칙(`UserSettingsStore.shared.defaultDisplayedTrans
    /// lationCodes` 우선, 없으면 등록순 + `defaultTranslationCode` 맨 앞)을
    /// 재현한다. 따라서 "설정상 기본 표시 번역본"의 근사치이며, 성경 조회 화면에서 세션 중 임시로 고른
    /// 조합과는 다를 수 있다.
    private(set) var activeTranslations: [TranslationRegistry] = []

    private func resolveActiveTranslations(from registries: [TranslationRegistry]) -> [TranslationRegistry] {
        let maxCount = 3
        let ordered = registries.sorted { $0.addedAt < $1.addedAt }
        let preferredCodes = UserSettingsStore.shared.defaultDisplayedTranslationCodes
        if !preferredCodes.isEmpty {
            let byCode = Dictionary(uniqueKeysWithValues: ordered.map { ($0.code, $0) })
            let chosen = preferredCodes.compactMap { byCode[$0] }
            if !chosen.isEmpty {
                return Array(chosen.prefix(maxCount))
            }
        }
        var fallback = ordered
        if let preferredCode = UserSettingsStore.shared.defaultTranslationCode,
           let index = fallback.firstIndex(where: { $0.code == preferredCode }) {
            let preferred = fallback.remove(at: index)
            fallback.insert(preferred, at: 0)
        }
        return Array(fallback.prefix(maxCount))
    }

    /// 개요 검색결과를 책 단위로 그룹핑한다(`groupedVerseResults`와 같은 순수 표시용 재배열,
    /// `outlineResults` 자체는 건드리지 않음). 책 단위(`chapter == nil`)와 장 단위
    /// 결과가 함께 있어 장 기준으로 나누면 같은 책의 개요가 흩어지므로 키는 "책"이다.
    ///
    /// 그룹 정렬: 그룹 안 `matchedWordCount` 최댓값 내림차순(일치도 우선), 같을 때만
    /// `Book.orderIndex`(정경 순서 — `bookId`는 정경 순서를 보장하지 않는다)로 비교한다.
    /// 그룹 안에서는 책 전체 개요(`chapter == nil`)를 먼저, 그다음 장 오름차순.
    struct OutlineSearchResultGroup: Identifiable {
        let bookId: Int
        let bookNameKo: String
        let items: [OutlineSearchResult]
        var id: Int { bookId }
    }

    var groupedOutlineResults: [OutlineSearchResultGroup] {
        var itemsByBook: [Int: [OutlineSearchResult]] = [:]
        var orderedBookIds: [Int] = []
        for result in outlineResults {
            if itemsByBook[result.bookId] == nil {
                orderedBookIds.append(result.bookId)
            }
            itemsByBook[result.bookId, default: []].append(result)
        }
        return orderedBookIds
            .map { bookId -> OutlineSearchResultGroup in
                let items = (itemsByBook[bookId] ?? [])
                    .sorted { ($0.chapter ?? -1) < ($1.chapter ?? -1) }
                return OutlineSearchResultGroup(
                    bookId: bookId,
                    bookNameKo: booksProvider.book(id: bookId)?.nameKo ?? "\(bookId)권",
                    items: items
                )
            }
            .sorted { lhs, rhs in
                // 일치도(그룹 내 최댓값) 우선, 같을 때만 정경 순서.
                let lhsRelevance = lhs.items.map(\.matchedWordCount).max() ?? 0
                let rhsRelevance = rhs.items.map(\.matchedWordCount).max() ?? 0
                if lhsRelevance != rhsRelevance {
                    return lhsRelevance > rhsRelevance
                }
                let lhsOrder = booksProvider.book(id: lhs.bookId)?.orderIndex ?? lhs.bookId
                let rhsOrder = booksProvider.book(id: rhs.bookId)?.orderIndex ?? rhs.bookId
                return lhsOrder < rhsOrder
            }
    }

    /// "더보기" 버튼을 보여줄지 — 아직 화면에 안 보여준 결과가 남아 있는지.
    var hasMoreVerseResults: Bool {
        allVerseResults.count > visibleVerseResultCount
    }

    /// "더보기" 버튼이 호출. 새 검색이 시작되면
    /// `performKeywordSearch`/`clearResults`가
    /// `verseResultPageSize`로 되돌린다.
    ///
    /// 이번 검색에서 확인창을 아직 안 보였고 매칭에 기여한 서로 다른 단어가 2개 이상이면, 페이지를 늘리는 대신
    /// `pendingMoreResultsNotice`만 채우고 멈춘다. 실제 증가는
    /// `confirmMoreResultsNotice()`에서 일어난다.
    func loadMoreVerseResults() {
        if !hasShownMoreResultsNotice, effectiveMatchedWordCount() >= 2 {
            hasShownMoreResultsNotice = true
            let additionalBookCount = Set(allVerseResults.dropFirst(visibleVerseResultCount).map(\.bookId)).count
            pendingMoreResultsNotice = MoreResultsNotice(additionalBookCount: additionalBookCount)
            return
        }
        visibleVerseResultCount += Self.verseResultPageSize
    }

    /// `pendingMoreResultsNotice` alert의 "확인" 버튼용 — 확인창을 닫고
    /// `loadMoreVerseResults()`가 하려던 페이지 증가를 이어서 한다.
    func confirmMoreResultsNotice() {
        pendingMoreResultsNotice = nil
        visibleVerseResultCount += Self.verseResultPageSize
    }

    /// `pendingMoreResultsNotice`가 `private(set)`이라 `SearchView`가
    /// 직접 nil을 대입할 수 없어 둔 진입점. alert이 "확인" 외의 경로(스와이프/ESC 등)로 닫힐 때
    /// 상태만 정리하며, 페이지 증가는 하지 않는다.
    func dismissMoreResultsNotice() {
        pendingMoreResultsNotice = nil
    }

    /// "더보기 확인창" 표시 조건 — `lastSearchWords`(중복 제거) 중 메모리의
    /// `allVerseResults` 본문에 대소문자 무시 부분일치로 한 번이라도 등장하는 서로 다른 단어 수를
    /// 센다(DB 재조회 없음). 예: "다윗 컴퓨터"는 "컴퓨터"가 본문에 없어 1, "다윗 다윗 맥북"도
    /// `Set` 중복 제거로 1이라 조건(>= 2)을 만족하지 않는다.
    private func effectiveMatchedWordCount() -> Int {
        let distinctWords = Set(lastSearchWords.map { $0.lowercased() }).filter { !$0.isEmpty }
        guard distinctWords.count > 1 else { return distinctWords.count }
        var matched = Set<String>()
        for result in allVerseResults {
            if matched.count == distinctWords.count { break }
            for word in distinctWords where !matched.contains(word) {
                if result.content.range(of: word, options: [.caseInsensitive]) != nil {
                    matched.insert(word)
                }
            }
        }
        return matched.count
    }

    /// `allVerseResults`를 채울 때 "더보기" 노출 개수와 확인창
    /// 상태(`hasShownMoreResultsNotice`/`pendingMoreResultsNotice`)를
    /// 함께 초기화한다 — 이전 검색의 상태가 새 결과에 남지 않도록 대입 지점(`clearResults`,
    /// `performKeywordSearch`, `performAIQuerySearch`)의 리셋 누락을 한
    /// 곳으로 묶었다.
    private func setVerseResults(_ results: [VerseSearchResult]) {
        allVerseResults = results
        visibleVerseResultCount = Self.verseResultPageSize
        hasShownMoreResultsNotice = false
        pendingMoreResultsNotice = nil
    }

    private(set) var memoResults: [MemoSearchResult] = []
    private(set) var documentResults: [DocumentSearchResult] = []
    private(set) var outlineResults: [OutlineSearchResult] = []
    private(set) var phraseNoteResults: [PhraseNoteSearchResult] = []
    private(set) var summaryResults: [SummarySearchResult] = []
    /// `clearResults()`/`performKeywordSearch`/`performAIQuerySearc
    /// h`가 `documentResults`와 같은 자리에서 함께 갱신한다.
    private(set) var sermonResults: [SermonSearchResult] = []
    private(set) var isSearching = false
    var errorDescription: String?

    private let modelContext: ModelContext
    private let booksProvider: BooksProvider
    private var searchTask: Task<Void, Never>?
    /// registry.sqliteFileReference(또는 번들 경로) 기준
    /// BibleReferenceStore 캐시. BibleReadingViewModel.store(for:)와
    /// 같은 목적이지만 뷰모델마다 독립 상태라 공유 싱글턴으로 묶지 않았고, 세 번째 사용처가 생기기 전엔 공통
    /// 헬퍼로 추출하지 않는다.
    private var storeCache: [String: BibleReferenceStore] = [:]

    init(modelContext: ModelContext, booksProvider: BooksProvider? = nil) {
        self.modelContext = modelContext
        self.booksProvider = booksProvider ?? .shared
    }

    /// 화면 진입 시 색인이 이미 있는지(파일 헤더만 읽는 가벼운 확인) 한 번 확인한다. 색인 생성은 사용자가
    /// 명시적으로 `startBibleEmbeddingIndexing()`을 눌러야 시작된다.
    func onAppear() {
        refreshBibleIndexStatus()
    }

    func onDisappear() {
        searchTask?.cancel()
        // 성경 전체 색인 작업(`EmbeddingIndexingService.shared`)은 앱 전역 싱글턴이 들고
        // 있어 화면을 나가도 취소하지 않고 백그라운드에서 계속 진행한다(수 분 걸릴 수 있는 일회성 작업이라).
    }

    // MARK: - 검색 실행 (엔터/토글 변경 시에만 — 타이핑 자동검색 없음)

    /// AI 검색의 최소 검색어 길이 — 미완성 입력("ㅎ", "하")으로 온디바이스 모델을 호출하는 낭비를
    /// 막는다. 일반 키워드 검색은 글자 수 제한이 없다.
    private static let minimumAIQueryLength = 2

    /// 검색어가 비었을 때(또는 AI 검색 최소 길이 미만일 때) 결과 상태를 한 번에 정리한다.
    private func clearResults() {
        intentCard = nil
        aiCardSelectedIndex = nil
        setVerseResults([])
        memoResults = []
        documentResults = []
        outlineResults = []
        phraseNoteResults = []
        summaryResults = []
        sermonResults = []
        errorDescription = nil
        lastAIQueryUsed = nil
    }

    /// 실제 검색(무거운 코사인 유사도 계산 포함)을 실행하는 진입점 — 엔터/검색 버튼(`SearchView`의
    /// `.onSubmit(of: .search)`)과 AI 토글 변경 시에만 호출된다.
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
        // 새 검색이 시작되는 지점은 여기 하나뿐이므로, 성경 조회 화면이 push된 채로 검색해도 결과 화면이
        // 보이도록 `SidebarNavigationView`에 pop을
        // 요청한다(`SearchResultsPopRequest.swift` 참고).
        SearchResultsPopRequest.shared.requestPop()
        // 검색 이력도 실제 검색이 실행되는 이 지점에서만 기록한다(위 guard에서 걸러진 빈 입력/AI 최소 길이
        // 미달은 기록되지 않는다).
        SearchHistoryService.record(query: trimmed, context: modelContext)
        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.performSearch(query: trimmed)
        }
    }

    /// 검색창이 포커스를 받을 때마다(검색어가 비어 있을 때) `SearchView`의
    /// `.searchSuggestions`가 다시 불러 보여주는 최근 검색이력. 다른 창에서 쌓인 이력까지
    /// 반영되도록 캐싱하지 않는다.
    func recentSearchHistory() -> [SearchHistoryEntry] {
        SearchHistoryService.fetchRecent(context: modelContext)
    }

    private func performSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }

        // `Task.yield()`로 실행을 한 번 양보해 SwiftUI가 `isSearching = true`
        // 상태로 최소 한 프레임을 그리게 한다. Task는 첫 `await`까지 동기적으로 실행되는데 키워드
        // 검색(`performKeywordSearch`)에는 await가 없어, 양보하지 않으면 스피너가 뜰 틈 없이
        // "결과 없음"이 먼저 보이다가 결과가 한꺼번에 나타난다. AI 검색은 이미 await가 있다.
        await Task.yield()

        // 관계정보 카드(Layer 1/2)는 AI 토글이 켜졌을 때만 계산한다(`intentCard` 선언부 참고).
        // 새 검색마다 이전 카드 안 항목 선택을 지운다 — 남아 있으면 새 결과 배열의 같은 인덱스가 전혀 다른
        // 항목을 가리킬 수 있다.
        aiCardSelectedIndex = nil
        if isAIQueryEnabled {
            let intent = QueryIntentClassifier.classify(query)
            intentCard = QueryIntentHandler.handle(query, intent: intent)
            await performAIQuerySearch(query: query)
        } else {
            intentCard = nil
            lastAIQueryUsed = nil
            await performKeywordSearch(query: query)
        }
    }

    // MARK: - 키워드 검색

    /// 각 분류를 채우는 순수 키워드 검색. 성경장절 인식(띄어쓰기 무시/약어↔전체이름/범위 포함)은
    /// `BibleReferenceExtractor` 하나로 충족한다.
    private func performKeywordSearch(query: String) async {
        errorDescription = nil
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        // "더보기 확인창" 조건 판단(`effectiveMatchedWordCount()`)에 쓰도록 이번 검색
        // 단어를 저장한다.
        lastSearchWords = words
        let queryMatches = BibleReferenceExtractor.extract(from: query)

        // 성경구절을 먼저 채우고, 각 단계 직후 `await Task.yield()`로 실행을 양보해 SwiftUI가
        // 그 시점까지의 결과로 다시 그리게 한다(성경 → 개요 → 메모/말씀노트 → 연구문서 순으로 이어서 나타남).
        // 중간 양보가 없으면 한 틱 안에 전부 끝나 화면이 갱신될 기회가 없다.
        //
        // 실제 백그라운드 병렬 대신 양보 방식을 쓴 이유: 이 클래스는 `@MainActor`이고
        // `modelContext`(SwiftData)와
        // `storeCache`(`BibleReferenceStore`는 스레드 안전을 보장하지 않음)도 메인 액터에
        // 묶여 있다. 병렬화하려면 분류마다 별도 `ModelContext`와 `BibleReferenceStore`를
        // 만들고 결과 타입을 `Sendable`에 맞춰야 한다(패키지는 Swift 6 모드). 진짜 멀티스레드
        // 병렬화가 필요하면 별도 작업으로 진행해야 한다.
        setVerseResults(searchVerses(query: query, words: words, queryMatches: queryMatches))
        await Task.yield()

        outlineResults = searchOutlines(words: words, queryMatches: queryMatches)
        await Task.yield()

        phraseNoteResults = searchPhraseNotes(words: words, queryMatches: queryMatches)
        memoResults = searchMemos(words: words, queryMatches: queryMatches)
        summaryResults = searchSummaries(words: words, queryMatches: queryMatches)
        await Task.yield()

        documentResults = searchDocuments(words: words, queryMatches: queryMatches)
        sermonResults = searchSermons(words: words, queryMatches: queryMatches)
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

    /// `maxSegmentLength`가 nil이면 매칭 단어 끝 + 9자를 발췌하고(메모/개인 묵상/말씀
    /// 요약/연구문서 기본 동작), 값이 있으면 매칭 시작부터 최대 N자로 총 노출 길이를 상한한다. 개요
    /// 검색(`searchOutlines`)만 35를 넘기며, 공유하는 나머지 호출부의 발췌 길이는 바뀌지 않는다.
    private func computeWordMatchScore(
        words: [String], verseTerms: [String], contentText: String, maxSegmentLength: Int? = nil
    ) -> WordMatchScore {
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
                    let tailEnd: String.Index
                    if let maxSegmentLength {
                        tailEnd = contentText.index(found.lowerBound, offsetBy: maxSegmentLength, limitedBy: contentText.endIndex) ?? contentText.endIndex
                    } else {
                        tailEnd = contentText.index(found.upperBound, offsetBy: 9, limitedBy: contentText.endIndex) ?? contentText.endIndex
                    }
                    firstExcerpts[term] = String(contentText[found.lowerBound..<tailEnd])
                }
                searchRange = found.upperBound..<contentText.endIndex
            }
        }
        var distinctTermMatchCount = occurrenceCounts.keys.count
        // `verseTerms`가 본문에서 못 찾아져도(예: 범위 확장 경계 오차) 매칭 자체는 이미 확정이므로
        // 최소 1은 반영한다 — `DocumentsHomeView.searchScore`와 같은 방어적 규칙.
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

    /// 단어 커버리지가 큰 항목을 먼저 두고, 같을 때만 보너스(태그/참조/제목 일치)로 순위를 가른다.
    /// 성경구절 탭(`KeywordMatchScorer.Score`)의 계층적 비교와 같은 원칙이다. `sorted(by:)`는
    /// 안정 정렬이라 둘 다 같은 항목은 각 카테고리가 조회한 원래 순서(최신순)를 유지한다.
    private static func sortedByWordCoverage<T>(
        _ results: [(result: T, wordCount: Int, bonus: Int)]
    ) -> [(result: T, wordCount: Int, bonus: Int)] {
        results.sorted { lhs, rhs in
            if lhs.wordCount != rhs.wordCount { return lhs.wordCount > rhs.wordCount }
            return lhs.bonus > rhs.bonus
        }
    }

    /// `sourceType`/`sourceId`에 걸린 `VerseMention` 중 검색어의 성경 참조와 겹치는 것의
    /// 원문 표현(중복 제거) — `DocumentsHomeView.verseMentionSearchTexts`의 공용 일반화.
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

    /// `verseMentionSearchTexts`와 같은 필터이지만 `sourceId`를 좁히지 않고 카테고리 전체 기준으로 모은다.
    /// FTS 후보 좁히기는 카테고리당 한 번만 질의하므로, 개별 항목의 verseTerms는 이 집합의
    /// 부분집합이다 — 이 값으로 좁혀도 verseTerms를 놓치지 않는다(안전한 상위집합).
    private func categoryWideVerseSearchTexts(
        mentions: [VerseMention], sourceType: VerseMentionSourceType, queryMatches: [BibleReferenceExtractor.Match]
    ) -> [String] {
        guard !queryMatches.isEmpty else { return [] }
        var seen = Set<String>()
        return mentions
            .filter { mention in
                guard mention.sourceType == sourceType else { return false }
                return queryMatches.contains { query in
                    query.bookId == mention.bookId
                        && query.chapter == mention.chapter
                        && (query.verse == nil || mention.verse == nil || query.verse == mention.verse)
                }
            }
            .map(\.searchText)
            .filter { seen.insert($0).inserted }
    }

    /// FTS5 보조 인덱스(unicode61, `UserContentSearchIndex`)로 검색 후보 source_id를 좁힌다.
    /// 이 카테고리에서 아직 색인되지 않은 항목은 먼저 채워 넣고(self-healing, 기능 도입 이전 데이터용),
    /// `words`(+`extraTerms` — 성경 참조 검색어의 원문 표기, 카테고리 전체 기준) 중 하나라도
    /// 매치되는 source_id만 돌려준다.
    ///
    /// 정확성 안전장치: 색인 디렉터리 접근이나 질의가 하나라도 실패하면 `liveContentById`의
    /// 모든 키를 후보로 반환해, 호출부가 전체 항목에 `computeWordMatchScore`를 돌리게 한다.
    ///
    /// 알려진 트레이드오프: unicode61은 토큰 접두어 매칭이라 검색어가 토큰 중간에 낀 경우
    /// (예: "사랑"으로 "내사랑")는 후보에서 빠질 수 있다. 성경구절 전체 검색(번들 FTS5)과
    /// 같은 특성이며, 자세한 내용은 `UserContentSearchIndex.swift` 상단 주석 참고.
    private func contentCandidateSourceIds(
        category: UserContentSearchIndexLocation.Category, words: [String], extraTerms: [String] = [],
        liveContentById: [String: String]
    ) -> Set<String> {
        let allTerms = words + extraTerms
        guard !allTerms.isEmpty else { return [] }
        guard let indexDirectory = try? UserContentSearchIndexLocation.directory() else {
            return Set(liveContentById.keys)
        }
        let indexedIds = UserContentSearchIndex.existingSourceIds(category: category.rawValue, indexDirectory: indexDirectory)
        for (id, content) in liveContentById where !indexedIds.contains(id) {
            UserContentSearchIndexLocation.upsert(category: category, sourceId: id, content: content)
        }
        var candidates = Set<String>()
        var sawFailure = false
        for term in allTerms where !term.isEmpty {
            if let matches = try? UserContentSearchIndex.matchingSourceIds(
                category: category.rawValue, indexDirectory: indexDirectory, matching: term
            ) {
                candidates.formUnion(matches)
            } else {
                sawFailure = true
            }
        }
        // 질의 자체가 하나라도 실패했으면(파일 손상 등) 좁혀진 결과를 신뢰할
        // 수 없으므로 안전하게 전체를 후보로 되돌린다.
        return sawFailure ? Set(liveContentById.keys) : candidates
    }

    // MARK: - 키워드 검색: 성경구절

    /// 검색어가 성경 참조로 해석되면(`queryMatches`) 그 절(들)을 직접 조회해 맨 앞에 보여준다 —
    /// 본문에 "1:3"이라는 글자가 없어도 창1:3은 창세기 1:3이 나와야 하기 때문. 그 외엔 각 단어를
    /// `BibleReferenceStore.searchVerses`(본문 텍스트 검색)로 OR 조회한다.
    private func searchVerses(query: String, words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [VerseSearchResult] {
        // 비활성 번역본은 조회 대상에서 빠지므로 검색 결과·번역본 하위 탭 어디에도 나타나지 않는다.
        guard let allRegistries = try? modelContext.fetch(FetchDescriptor<TranslationRegistry>()) else { return [] }
        let registries = allRegistries.filter(\.isEnabled)
        // 활성 번역본 목록은 검색 1회당 한 번만 계산해 캐싱한다 — 연산 프로퍼티로 두면 SwiftUI
        // 렌더링마다 SwiftData 재조회가 생긴다(`resolveActiveTranslations` 참고).
        activeTranslations = resolveActiveTranslations(from: registries)
        var seen = Set<String>()
        var results: [VerseSearchResult] = []

        for registry in registries {
            guard let store = try? store(for: registry) else { continue }
            let versionCode = store.hasVersionCodeColumn ? registry.code : nil

            for match in queryMatches {
                let candidateVerses: [BibleVerse]
                if let verseNumber = match.verse {
                    // `try?`는 Swift 5(SE-0230)부터 이중 옵셔널을 평탄화하므로 `guard let` 한 번만 쓴다.
                    guard let verse = try? store.verse(bookId: match.bookId, chapter: match.chapter, verse: verseNumber, versionCode: versionCode) else { continue }
                    candidateVerses = [verse]
                } else {
                    candidateVerses = (try? store.verses(bookId: match.bookId, chapter: match.chapter, versionCode: versionCode)) ?? []
                }
                for verse in candidateVerses {
                    // 번역본 하위 탭을 위해 같은 절도 번역본마다 별개 결과로 남기도록 dedup 키에 `registry.code`를 포함한다.
                    let key = "\(verse.bookId)-\(verse.chapter)-\(verse.verse)-\(registry.code)"
                    guard seen.insert(key).inserted else { continue }
                    results.append(VerseSearchResult(
                        bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse,
                        content: verse.content,
                        bookNameKo: booksProvider.book(id: verse.bookId)?.nameKo ?? "\(verse.bookId)권",
                        translationCode: registry.code, translationDisplayName: registry.displayName,
                        isReferenceMatch: true
                    ))
                    // 참조 매치만으로 조기 반환하지 않는다 — 뒤의 단어 기반 후보와 "더보기"를 위해 전체를 유지한다.
                }
            }
        }

        // 모든 단어(동의어 포함, `RelationSynonyms`)의 후보를 전부 모은 뒤 `KeywordMatchScorer`로 점수를 매겨
        // 내림차순 정렬한다 — 일부만 일치하는 흔한 단어 결과가 전체 일치 결과를 밀어내지 않게 하기 위함이다.
        //
        // 번들 기본 번역본(개역한글)은 `ReferenceDataStore.searchVersesFullText`(FTS5 unicode61,
        // 접두어 검색)를 쓴다. 그 외 번역본은 아래 보조 인덱스 또는 LIKE 검색을 쓴다.
        var wordCandidates: [String: (verse: BibleVerse, bookNameKo: String, translationCode: String, translationDisplayName: String)] = [:]
        let fullTextStore = ReferenceDataProvider.shared.store
        for registry in registries {
            guard let store = try? store(for: registry) else { continue }
            let versionCode = store.hasVersionCodeColumn ? registry.code : nil
            let useBundledFullText = registry.code == TranslationBootstrap.bundledTranslationCode && fullTextStore != nil

            // 사용자 추가 번역본은 `TranslationSearchIndex`(보조 FTS5 인덱스 파일 — 원본 번역본 파일은
            // `BibleReferenceStore`가 READONLY로 열므로 건드리지 않는다)가 있을 때만 사용한다. 이 경로는
            // 인덱스를 만들지 않고 존재만 확인하며, 빌드는 `TranslationFileMaterializer.writeLocalCopy`에서만
            // 일어난다. 인덱스가 없으면 `companionIndexDirectory`가 nil로 남아 LIKE 경로로 폴백한다(자동 백필 없음).
            var companionIndexDirectory: URL?
            if !useBundledFullText {
                let directory = URL(fileURLWithPath: store.filePath).deletingLastPathComponent()
                if TranslationSearchIndex.indexExists(registryID: registry.id, indexDirectory: directory) {
                    companionIndexDirectory = directory
                }
            }

            // FTS5 매치 결과(번들 경로/보조 인덱스 경로 공통, `FullTextVerseMatch`)를 wordCandidates에 반영한다.
            func ingestFullTextMatches(_ matches: [FullTextVerseMatch]) {
                for match in matches {
                    // 번역본별 별개 결과를 남기도록 키에 `registry.code`를 포함한다.
                    let key = "\(match.bookId)-\(match.chapter)-\(match.verse)-\(registry.code)"
                    guard !seen.contains(key), wordCandidates[key] == nil else { continue }
                    wordCandidates[key] = (
                        BibleVerse(uid: 0, versionCode: versionCode, bookId: match.bookId, chapter: match.chapter, verse: match.verse, content: match.content, paragraph: nil),
                        booksProvider.book(id: match.bookId)?.nameKo ?? "\(match.bookId)권",
                        registry.code, registry.displayName
                    )
                }
            }

            // `limit`을 넘기지 않아 해당 단어의 실제 등장 전체를 후보로 모은다 — FTS5 bm25 상위 N개만 자르면
            // 흔한 단어(예: "다윗")에서 성경순 앞쪽 결과가 후보에서 빠진다. 화면 표시 개수는
            // `verseResults`/`loadMoreVerseResults()`가 결정한다.
            for word in words {
                for variant in RelationSynonyms.expanded(word) {
                    if useBundledFullText, let fullTextStore {
                        guard let matches = try? fullTextStore.searchVersesFullText(matching: variant) else { continue }
                        ingestFullTextMatches(matches)
                    } else if let directory = companionIndexDirectory,
                              let matches = try? TranslationSearchIndex.search(registryID: registry.id, indexDirectory: directory, matching: variant) {
                        ingestFullTextMatches(matches)
                    } else {
                        guard let verses = try? store.searchVerses(query: variant, versionCode: versionCode) else { continue }
                        for verse in verses {
                            // 번역본별 결과 유지(위와 같은 이유).
                            let key = "\(verse.bookId)-\(verse.chapter)-\(verse.verse)-\(registry.code)"
                            guard !seen.contains(key), wordCandidates[key] == nil else { continue }
                            wordCandidates[key] = (verse, booksProvider.book(id: verse.bookId)?.nameKo ?? "\(verse.bookId)권", registry.code, registry.displayName)
                        }
                    }
                }
            }
        }

        // 점수가 같으면 (정경 순서, 장, 절) 오름차순으로 명시적으로 끊는다 — `wordCandidates`는 Dictionary라
        // `.values` 순서가 실행마다 달라질 수 있다. `KeywordMatchScorer.Score`가 등장 횟수로 가중치를 매기지
        // 않으므로 단어 1개 질의는 모든 결과의 점수가 같아져, 이 tie-break가 곧 성경 순서 정렬이 된다.
        let scoredCandidates = wordCandidates.values
            .map { entry -> (result: VerseSearchResult, score: KeywordMatchScorer.Score, orderIndex: Int) in
                let score = KeywordMatchScorer.score(words: words, in: entry.verse.content)
                let result = VerseSearchResult(
                    bookId: entry.verse.bookId, chapter: entry.verse.chapter, verse: entry.verse.verse,
                    content: entry.verse.content, bookNameKo: entry.bookNameKo,
                    translationCode: entry.translationCode, translationDisplayName: entry.translationDisplayName,
                    highlightKeywords: words,
                    // `matchCount`는 정렬 tie-break에 쓰는 `score`의 중복 제거된 매칭 검색어 수를 그대로 재사용한다
                    // (`VerseSearchResult.matchCount` 참고).
                    matchCount: score.matchedWordCount
                )
                let orderIndex = booksProvider.book(id: entry.verse.bookId)?.orderIndex ?? entry.verse.bookId
                return (result, score, orderIndex)
            }
            .filter { $0.score.isAnyMatch }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.orderIndex != rhs.orderIndex { return lhs.orderIndex < rhs.orderIndex }
                if lhs.result.chapter != rhs.result.chapter { return lhs.result.chapter < rhs.result.chapter }
                return lhs.result.verse < rhs.result.verse
            }

        // 여기서 자르지 않고 전체를 돌려준다 — 화면 표시 개수는 `verseResults`("더보기")가 결정하며,
        // 자르면 "더보기"가 보여줄 데이터가 사라진다.
        results.append(contentsOf: scoredCandidates.map(\.result))
        return results
    }

    // MARK: - 키워드 검색: 개요

    /// `BookOutline`(책 단위)/`ChapterSummary`(장 단위)는 자신이 성경 좌표를 이미 갖고 있으므로
    /// 본문에서 성경구절을 뽑을 필요 없이 검색어의 성경 참조와 좌표가 겹치는지만 본다.
    private func searchOutlines(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [OutlineSearchResult] {
        let bookOutlines = (try? modelContext.fetch(
            FetchDescriptor<BookOutline>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []
        let chapterSummaries = (try? modelContext.fetch(
            FetchDescriptor<ChapterSummary>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []

        // 책 개요/장별 개요는 서로 다른 모델이라 카테고리도 따로 좁힌다. `verseTerms`가 없으므로
        // `extraTerms`는 넘기지 않는다.
        let outlineContentCandidates = contentCandidateSourceIds(
            category: .outline, words: words,
            liveContentById: Dictionary(uniqueKeysWithValues: bookOutlines.map { ($0.id.uuidString, $0.contentText) })
        )
        let chapterSummaryContentCandidates = contentCandidateSourceIds(
            category: .chapterSummary, words: words,
            liveContentById: Dictionary(uniqueKeysWithValues: chapterSummaries.map { ($0.id.uuidString, $0.contentText) })
        )

        var results: [(result: OutlineSearchResult, wordCount: Int, bonus: Int)] = []

        for outline in bookOutlines {
            let refMatch = queryMatches.contains { $0.bookId == outline.bookId }
            // 참조매치도 아니고 FTS 후보에도 없으면 본문에 매치될 가능성이 거의 없으므로
            // `computeWordMatchScore`의 전체 문자열 스캔을 건너뛴다(위 헬퍼의 트레이드오프 참고).
            guard refMatch || outlineContentCandidates.contains(outline.id.uuidString) else { continue }
            // `maxSegmentLength: 35` — 개요 전용 확장 발췌(`computeWordMatchScore` 참고).
            let wordScore = computeWordMatchScore(words: words, verseTerms: [], contentText: outline.contentText, maxSegmentLength: 35)
            guard refMatch || wordScore.isTextMatch else { continue }
            let result = OutlineSearchResult(
                kind: .book(outline), bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                highlightKeywords: wordScore.highlightKeywords, isReferenceMatch: refMatch,
                matchedWordCount: wordScore.distinctTermMatchCount
            )
            results.append((result, wordScore.distinctTermMatchCount, refMatch ? 1 : 0))
        }
        for summary in chapterSummaries {
            let refMatch = queryMatches.contains { $0.bookId == summary.bookId && $0.chapter == summary.chapter }
            // 책 개요 루프와 같은 이유.
            guard refMatch || chapterSummaryContentCandidates.contains(summary.id.uuidString) else { continue }
            // `maxSegmentLength: 35` — 개요 전용 확장 발췌.
            let wordScore = computeWordMatchScore(words: words, verseTerms: [], contentText: summary.contentText, maxSegmentLength: 35)
            guard refMatch || wordScore.isTextMatch else { continue }
            let result = OutlineSearchResult(
                kind: .chapter(summary), bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                highlightKeywords: wordScore.highlightKeywords, isReferenceMatch: refMatch,
                matchedWordCount: wordScore.distinctTermMatchCount
            )
            results.append((result, wordScore.distinctTermMatchCount, refMatch ? 1 : 0))
        }
        return Self.sortedByWordCoverage(results).map(\.result)
    }

    // MARK: - 키워드 검색: 메모(VersePhraseNote)

    private func searchPhraseNotes(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [PhraseNoteSearchResult] {
        let notes = (try? modelContext.fetch(
            FetchDescriptor<VersePhraseNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []
        // FTS 후보 좁히기(`contentCandidateSourceIds` 참고).
        let phraseNoteContentCandidates = contentCandidateSourceIds(
            category: .phraseNote, words: words,
            liveContentById: Dictionary(uniqueKeysWithValues: notes.map { ($0.id.uuidString, $0.noteText) })
        )
        var results: [(result: PhraseNoteSearchResult, wordCount: Int, bonus: Int)] = []
        for note in notes {
            let refMatch = queryMatches.contains { query in
                query.bookId == note.bookId && query.chapter == note.chapter
                    && (query.verse == nil || query.verse == note.verse)
            }
            // 참조매치도 아니고 FTS 후보에도 없으면 전체 문자열 스캔을 건너뛴다.
            guard refMatch || phraseNoteContentCandidates.contains(note.id.uuidString) else { continue }
            let wordScore = computeWordMatchScore(words: words, verseTerms: [], contentText: note.noteText)
            guard refMatch || wordScore.isTextMatch else { continue }
            let result = PhraseNoteSearchResult(
                note: note, bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                highlightKeywords: wordScore.highlightKeywords, isReferenceMatch: refMatch,
                matchedWordCount: wordScore.distinctTermMatchCount
            )
            results.append((result, wordScore.distinctTermMatchCount, refMatch ? 1 : 0))
        }
        return Self.sortedByWordCoverage(results).map(\.result)
    }

    // MARK: - 키워드 검색: 개인 묵상(UserMemo)

    private func searchMemos(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [MemoSearchResult] {
        let memos = (try? modelContext.fetch(
            FetchDescriptor<UserMemo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []
        let mentions = queryMatches.isEmpty ? [] : ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
        // `verseTerms`도 후보를 좁히는 질의어에 포함해야 정확성이 유지된다
        // (`categoryWideVerseSearchTexts` 참고).
        let memoContentCandidates = contentCandidateSourceIds(
            category: .memo, words: words,
            extraTerms: categoryWideVerseSearchTexts(mentions: mentions, sourceType: .memo, queryMatches: queryMatches),
            liveContentById: Dictionary(uniqueKeysWithValues: memos.map { ($0.id.uuidString, $0.contentText) })
        )
        var results: [(result: MemoSearchResult, wordCount: Int, bonus: Int)] = []
        for memo in memos {
            let tagNames = (memo.memoTags ?? []).compactMap { $0.tag?.name }
            let tagCount = words.filter { word in tagNames.contains { $0.localizedCaseInsensitiveContains(word) } }.count
            var seenTagNames = Set<String>()
            let matchedTagNames = tagNames.filter { name in
                words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
            }
            // 태그매치도 아니고 FTS 후보에도 없으면 전체 문자열 스캔을 건너뛴다.
            guard tagCount > 0 || memoContentCandidates.contains(memo.id.uuidString) else { continue }
            let verseTerms = verseMentionSearchTexts(mentions: mentions, sourceType: .memo, sourceId: memo.id.uuidString, queryMatches: queryMatches)
            let wordScore = computeWordMatchScore(words: words, verseTerms: verseTerms, contentText: memo.contentText)
            guard tagCount > 0 || wordScore.isTextMatch else { continue }
            let result = MemoSearchResult(
                memo: memo, bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                matchedTagNames: matchedTagNames, highlightKeywords: wordScore.highlightKeywords,
                matchedWordCount: wordScore.distinctTermMatchCount
            )
            results.append((result, wordScore.distinctTermMatchCount, tagCount))
        }
        return Self.sortedByWordCoverage(results).map(\.result)
    }

    // MARK: - 키워드 검색: 말씀 요약(VerseSummary)

    private func searchSummaries(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [SummarySearchResult] {
        let summaries = (try? modelContext.fetch(
            FetchDescriptor<VerseSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )) ?? []
        let mentions = queryMatches.isEmpty ? [] : ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
        // `searchMemos`와 같은 이유.
        let summaryContentCandidates = contentCandidateSourceIds(
            category: .wordSummary, words: words,
            extraTerms: categoryWideVerseSearchTexts(mentions: mentions, sourceType: .wordSummary, queryMatches: queryMatches),
            liveContentById: Dictionary(uniqueKeysWithValues: summaries.map { ($0.id.uuidString, $0.contentText) })
        )
        var results: [(result: SummarySearchResult, wordCount: Int, bonus: Int)] = []
        for summary in summaries {
            let tagNames = (summary.summaryTags ?? []).compactMap { $0.tag?.name }
            let tagCount = words.filter { word in tagNames.contains { $0.localizedCaseInsensitiveContains(word) } }.count
            var seenTagNames = Set<String>()
            let matchedTagNames = tagNames.filter { name in
                words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
            }
            // `searchMemos`와 같은 이유.
            guard tagCount > 0 || summaryContentCandidates.contains(summary.id.uuidString) else { continue }
            let verseTerms = verseMentionSearchTexts(mentions: mentions, sourceType: .wordSummary, sourceId: summary.id.uuidString, queryMatches: queryMatches)
            let wordScore = computeWordMatchScore(words: words, verseTerms: verseTerms, contentText: summary.contentText)
            guard tagCount > 0 || wordScore.isTextMatch else { continue }
            let result = SummarySearchResult(
                summary: summary, bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                matchedTagNames: matchedTagNames, highlightKeywords: wordScore.highlightKeywords,
                matchedWordCount: wordScore.distinctTermMatchCount
            )
            results.append((result, wordScore.distinctTermMatchCount, tagCount))
        }
        return Self.sortedByWordCoverage(results).map(\.result)
    }

    // MARK: - 키워드 검색: 연구문서(SourceDocument)

    /// `DocumentsHomeView.searchScore(for:)`와 원리는 같지만 이 화면은 문서 전체를 대상으로 하므로
    /// 모든 `SourceDocument`를 훑는다. 정렬은 태그/파일명/본문 3단계가 아니라 일치 개수 내림차순이다.
    private func searchDocuments(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [DocumentSearchResult] {
        let documents = (try? modelContext.fetch(
            FetchDescriptor<SourceDocument>(sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)])
        )) ?? []
        let mentions = queryMatches.isEmpty ? [] : ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
        // `cachedCombinedText`가 비어 있는데 `documentTexts`는 있는 문서(캐시 필드 도입 이전 업로드분)는
        // 여기서 한 번 다시 만들고 함수 끝에서 한 번에 저장한다. `documentTexts`도 비어 있는 문서(텍스트
        // 추출 실패 등)는 캐시가 비어 있는 게 정당하므로 다시 만들지 않는다.
        // FTS 후보 좁히기에 넘길 `liveContentById`가 최신 `cachedCombinedText`를 담도록
        // 백필을 그 단계보다 먼저 끝낸다.
        var needsBackfillSave = false
        for document in documents {
            if document.cachedCombinedText.isEmpty, !(document.documentTexts ?? []).isEmpty {
                document.rebuildCachedCombinedText()
                needsBackfillSave = true
            }
        }

        // FTS 후보 좁히기(`contentCandidateSourceIds` 참고).
        let documentContentCandidates = contentCandidateSourceIds(
            category: .document, words: words,
            extraTerms: categoryWideVerseSearchTexts(mentions: mentions, sourceType: .document, queryMatches: queryMatches),
            liveContentById: Dictionary(uniqueKeysWithValues: documents.map { ($0.id.uuidString, $0.cachedCombinedText) })
        )

        var results: [(result: DocumentSearchResult, wordCount: Int, bonus: Int)] = []
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

            // 태그/제목매치도 아니고 FTS 후보에도 없으면 전체 문자열 스캔을 건너뛴다.
            guard tagCount > 0 || titleCount > 0 || documentContentCandidates.contains(document.id.uuidString) else { continue }
            let combinedText = document.cachedCombinedText
            let verseTerms = verseMentionSearchTexts(mentions: mentions, sourceType: .document, sourceId: document.id.uuidString, queryMatches: queryMatches)
            let wordScore = computeWordMatchScore(words: words, verseTerms: verseTerms, contentText: combinedText)

            guard tagCount > 0 || titleCount > 0 || wordScore.isTextMatch else { continue }
            let result = DocumentSearchResult(
                document: document, pageNumber: nil,
                bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                matchedTagNames: matchedTagNames, highlightKeywords: wordScore.highlightKeywords,
                matchedWordCount: wordScore.distinctTermMatchCount
            )
            results.append((result, wordScore.distinctTermMatchCount, tagCount + titleCount))
        }
        if needsBackfillSave {
            try? modelContext.save()
        }
        return Self.sortedByWordCoverage(results).map(\.result)
    }

    // MARK: - 키워드 검색: 내 설교(Sermon)

    /// `searchDocuments`와 같은 구조 — 제목(`sermon.title`)/태그(`sermon.sermonTags`)/본문
    /// (`sermon.contentText`) + 성경구절 파싱. 회차 사본(`SermonDelivery`)은 범위 밖이라
    /// 메인 설교문만 대상으로 한다(`VerseMentionSourceType.sermon` 참고).
    private func searchSermons(words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [SermonSearchResult] {
        let sermons = (try? modelContext.fetch(
            FetchDescriptor<Sermon>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )) ?? []
        let mentions = queryMatches.isEmpty ? [] : ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
        let sermonContentCandidates = contentCandidateSourceIds(
            category: .sermon, words: words,
            extraTerms: categoryWideVerseSearchTexts(mentions: mentions, sourceType: .sermon, queryMatches: queryMatches),
            liveContentById: Dictionary(uniqueKeysWithValues: sermons.map { ($0.id.uuidString, $0.contentText) })
        )

        var results: [(result: SermonSearchResult, wordCount: Int, bonus: Int)] = []
        for sermon in sermons {
            let tagNames = (sermon.sermonTags ?? []).compactMap { $0.tag?.name }
            let tagCount = words.filter { word in tagNames.contains { $0.localizedCaseInsensitiveContains(word) } }.count
            var seenTagNames = Set<String>()
            let matchedTagNames = tagNames.filter { name in
                words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
            }

            let titleCount = words.filter { sermon.title.localizedCaseInsensitiveContains($0) }.count

            guard tagCount > 0 || titleCount > 0 || sermonContentCandidates.contains(sermon.id.uuidString) else { continue }
            let verseTerms = verseMentionSearchTexts(mentions: mentions, sourceType: .sermon, sourceId: sermon.id.uuidString, queryMatches: queryMatches)
            let wordScore = computeWordMatchScore(words: words, verseTerms: verseTerms, contentText: sermon.contentText)

            guard tagCount > 0 || titleCount > 0 || wordScore.isTextMatch else { continue }
            let result = SermonSearchResult(
                sermon: sermon,
                bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                matchedTagNames: matchedTagNames, highlightKeywords: wordScore.highlightKeywords,
                matchedWordCount: wordScore.distinctTermMatchCount
            )
            results.append((result, wordScore.distinctTermMatchCount, tagCount + titleCount))
        }
        return Self.sortedByWordCoverage(results).map(\.result)
    }

    // MARK: - AI 검색(임베딩 기반 의미검색, 2026-08-19 전면 교체)

    /// `isAIQueryEnabled`일 때의 검색 경로로, 키워드 검색을 거치지 않고
    /// `BibleSemanticSearchService`(정제→임베딩→코사인 유사도)를 쓴다. 의미검색은 성경 구절만
    /// 대상이므로 나머지 섹션은 항상 비운다.
    ///
    /// `intentCard`가 확정되고 실제 성경 좌표(`QueryIntentCard.verseRefs`)가 있으면 근사 검색을
    /// 건너뛰고 그 좌표를 그대로 "성경구절" 섹션에 채운다. 카드가 없거나 좌표가 비어 있으면
    /// 의미검색으로 넘어간다.
    private func performAIQuerySearch(query: String) async {
        errorDescription = nil
        // AI(의미) 검색은 단어로 쪼개지 않으므로, "더보기 확인창" 조건(`effectiveMatchedWordCount()`)의
        // 전제인 `lastSearchWords`를 매번 비워 이전 키워드 검색의 값이 남지 않게 한다.
        lastSearchWords = []

        if let intentCard, !intentCard.verseRefs.isEmpty {
            setVerseResults(resolveVerseResults(intentCard.verseRefs))
            lastAIQueryUsed = nil
            memoResults = []; documentResults = []
            outlineResults = []; phraseNoteResults = []; summaryResults = []
            sermonResults = []
            return
        }

        let result = await BibleSemanticSearchService.search(query: query)
        switch result {
        case .success(let outcome):
            setVerseResults(outcome.matches.map { match in
                VerseSearchResult(
                    bookId: match.bookId, chapter: match.chapter, verse: match.verse,
                    content: match.content,
                    bookNameKo: booksProvider.book(id: match.bookId)?.nameKo ?? "\(match.bookId)권",
                    translationCode: TranslationBootstrap.bundledTranslationCode,
                    translationDisplayName: TranslationBootstrap.bundledDisplayName
                )
            })
            lastAIQueryUsed = outcome.queryUsedForEmbedding
        case .failure(let error):
            errorDescription = error.description
            setVerseResults([])
            lastAIQueryUsed = nil
        }
        memoResults = []; documentResults = []
        outlineResults = []; phraseNoteResults = []; summaryResults = []
        sermonResults = []
    }

    /// `QueryIntentCard.verseRefs`(카드가 확정한 성경 좌표)를 절 본문과 함께 `VerseSearchResult`로
    /// 바꾼다. 키워드 검색과 같은 근거로 30개에서 자른다 — 관계가 많은 인물일 때 목록이 무한정
    /// 길어지지 않게.
    private func resolveVerseResults(_ refs: [BibleVerseRef]) -> [VerseSearchResult] {
        guard let store = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedBundledDatabaseURL().path) else { return [] }
        var results: [VerseSearchResult] = []
        for ref in refs {
            guard let verse = try? store.verse(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse) else { continue }
            results.append(VerseSearchResult(
                bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse,
                content: verse.content,
                bookNameKo: booksProvider.book(id: verse.bookId)?.nameKo ?? "\(verse.bookId)권",
                translationCode: TranslationBootstrap.bundledTranslationCode,
                translationDisplayName: TranslationBootstrap.bundledDisplayName
            ))
            if results.count >= 30 { break }
        }
        return results
    }

    // MARK: - 성경 전체 임베딩 색인 (2026-08-19 신설)

    /// AI 검색은 이 색인이 먼저 있어야 한다(`BibleSemanticSearchService.SearchError.indexNotReady`).
    /// `SearchView`가 이 상태로 "색인 만들기" 버튼/진행률 바를 보여준다.
    ///
    /// `EmbeddingIndexingService`는 `@Observable`이 아닌 `@MainActor` 싱글턴이라(Task를 화면
    /// 생명주기와 분리하기 위함 — `onDisappear()` 참고) 내부 `status` 변경으로 SwiftUI가 다시
    /// 그리지 않는다. 그래서 저장 프로퍼티로 두고 상태가 바뀔 때마다 명시적으로 대입한다.
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
        // `BibleReadingViewModel.store(for:)`와 같은 이유로 `TranslationFileMaterializer`를 거치며
        // (`TranslationFileMaterializer.swift` 상단 주석 참고), 번들 번역본이 여러 개라 `registry.code`로 구분한다.
        let path = registry.isBundled
            ? try TranslationBootstrap.resolvedBundledDatabaseURL(for: registry.code).path
            : try TranslationFileMaterializer.ensureMaterialized(registry, context: modelContext)
        if let cached = storeCache[path] { return cached }
        let store = try BibleReferenceStore(filePath: path)
        storeCache[path] = store
        return store
    }

}
