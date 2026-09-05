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
    // [2026-09-05 변경] 사용자 요청("성경구절 탭의 하위 탭으로 활성
    // 번역본별 결과 노출")에 따라 `searchVerses`의 dedup 키가 절 좌표만
    // 쓰던 것에서 `registry.code`를 더하는 것으로 바뀌면서(이 파일
    // 아래쪽 dedup 키 변경 주석 참고), 같은 절이 번역본마다 별도
    // `VerseSearchResult`로 함께 존재할 수 있게 됐다. 이 `id`가 여전히
    // 절 좌표만 쓰면 서로 다른 번역본의 같은 절 결과끼리 `id`가 충돌해
    // `ForEach(group.verses)`(SearchView.groupedVerseRow 호출부)가 같은
    // id를 가진 두 행을 받게 되어 SwiftUI가 행을 뒤섞거나 하나를 못
    // 그리는 등 정의되지 않은 동작을 일으킨다 — dedup 키 변경의 직접적인
    // 필연적 결과이므로 함께 고친다(새로운 범위 확장이 아니다).
    var id: String { "\(bookId)-\(chapter)-\(verse)-\(translationCode)" }
    let bookId: Int
    let chapter: Int
    let verse: Int
    let content: String
    let bookNameKo: String
    /// [2026-08-29 추가] 검색결과 행의 "선택"/"복사" 버튼이 이 절이 실제로
    /// 어느 번역본에서 나왔는지 알아야 해서 추가했다 — 원래는 검색 매칭
    /// 과정(`searchVerses`)에서만 잠깐 쓰이고 화면까지 전달되지 않았다.
    /// 같은 절에 여러 번역본이 매칭되면 먼저 처리된 번역본만 남는 기존
    /// dedup 동작(`seen`/`wordCandidates` 키가 절 좌표만 쓰는 것)은 그대로
    /// 두고(이 필드 추가가 그 동작을 바꾸지 않는다), 그 결과가 실제로 어느
    /// 번역본인지 값만 함께 실어 나른다.
    let translationCode: String
    let translationDisplayName: String
    /// [2026-08-18 추가] 키워드 검색에서 강조할 단어들 — 성경구절 참조 자체로
    /// 직접 조회된 결과(`referenceMatchedVerses`)는 비워 둔다(정확히 그 절을
    /// 찾아온 것이라 특정 단어를 강조할 이유가 없다).
    var highlightKeywords: [String] = []
    /// 검색어 자체가 이 절을 가리키는 성경 참조였는지(예: "창1:3") — true면
    /// 목록 맨 위, 본문 검색으로 걸린 결과와 구분해 보여준다.
    var isReferenceMatch: Bool = false
    /// [2026-08-26 추가, 같은 날 정정] 사용자 요청 — "각 절마다 몇개
    /// 매칭되었는지 오른쪽 끝에다 표시해줄것." 처음엔 `KeywordMatchScorer.
    /// Score.totalOccurrences`(그 절 본문 안에서 검색어가 총 몇 번 등장했는지
    /// — 같은 단어가 반복되면 계속 올라감)를 옮겨 왔었는데, 사용자가 이후
    /// 명시적으로 정정했다: "[가장 많이 일치된 절]의 의미가 횟수를 의미하는
    /// 것이 아니라 [중복 제거된 매칭된 검색어의 수]를 의미함." 즉 원하는 값은
    /// `matchedWordCount`(서로 다른 검색어가 몇 개나 일치했는지, 중복 제거) —
    /// 정확히 랭킹 tie-break가 이미 쓰는 바로 그 값이다(`BibleKeywordMatching.
    /// swift` 상단 주석 참고). 이 필드는 `matchedWordCount`를 그대로 옮겨
    /// 담으므로 정렬 기준과 화면 표시가 이제 같은 수치를 가리킨다(예전엔
    /// 랭킹=matchedWordCount, 표시=totalOccurrences로 서로 달랐다). 참조 매치
    /// (`referenceMatchedVerses`)는 단어 매칭 점수를 계산하지 않으므로 기본값
    /// 0을 그대로 둔다(0이면 화면에서 배지 자체를 숨긴다).
    var matchCount: Int = 0
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

    /// [2026-08-19 신설, 2026-08-20 제거] "애플인텔리전스를 끈것과 켠것을
    /// 비교하고 싶음"으로 만든 두 보조 토글(질의 정제/재순위화)이었으나,
    /// 사용자가 "결과가 너무 이상함"(정제)/"너무 느리고 결과가 큰 차이
    /// 안 남"(재순위화)이라는 이유로 두 체크박스 자체를 없애 달라고 요청했다
    /// — `SearchView`의 Toggle 두 개도 함께 제거했다. `BibleSemanticSearchService.
    /// search`는 이제 Apple Intelligence 질의 정제/재순위화를 아예 호출하지
    /// 않는다(결정론적 `stripTrailingMetaPhrase`와, LLM이 아닌 `BibleStructuralRerankerService`는
    /// 계속 항상 적용된다 — 이 둘은 "Apple Intelligence"가 아니라서 사용자가
    /// 제거 대상으로 언급하지 않았다). `BibleQueryRefinementService.refine`/
    /// `BibleSearchRerankerService`는 더 이상 호출되지 않지만 파일 자체는
    /// 지우지 않았다(이 프로젝트의 기존 관례 — `AIRelationExtractor`처럼
    /// 필요하면 나중에 다시 연결할 수 있도록 보관, 완전 삭제는 요청받지 않음).
    ///
    /// [2026-08-19 v3 신설, 2026-08-20 제거, Phase 5] 사용자 지시로 만들었던
    /// "verse/context weight" 슬라이더("절 x% · 문맥 x%")를 없앴다. 사용자가
    /// 직접 다시 리뷰하며 "의미가 있는가? 없으면 삭제할 것"이라고 물었는데,
    /// 판단 근거: 이 값은 `BibleSemanticSearchService.search`의 코사인 유사도
    /// 블렌드 비율(절 벡터 vs 문맥 벡터)을 바꾸는 내부 튜닝 파라미터일 뿐이고,
    /// 애초에 만들 때부터 "0.6은 출발점일 뿐 최적값이라는 근거는 없다"고 밝혀둔
    /// 값이었다(임의적 실험용 슬라이더, 이 문서 이전 버전 참고) — 최종
    /// 사용자에게 "절/문맥 가중치"라는 ML 내부 개념 자체가 해석 가능한 정보가
    /// 아니고, 어느 값이 "더 나은 결과"인지 검증된 기준도 없다. 슬라이더(UI)만
    /// 없앴고, `BibleSemanticSearchService.search`의 `contextWeight` 매개변수
    /// 자체는 그대로 남겨(기본값 0.6, 이전 슬라이더 기본값과 동일 — 동작 변화
    /// 없음) 나중에 내부적으로 다시 스윕 테스트할 수 있게 했다(호출부는 이제
    /// 인자를 넘기지 않고 기본값을 쓴다, 아래 `performAIQuerySearch` 참고).
    /// `SearchView`의 슬라이더 UI도 함께 제거했다.

    /// [2026-08-19 신설] 방금 AI 검색이 실제로 임베딩에 넘긴 문장 — 정제 토글을
    /// 켰을 때 원문이 어떻게 바뀌었는지 화면에 보여줘서 비교를 돕는다
    /// (`SearchView`의 "검색에 사용된 문장" 안내 참고). 일반 키워드 검색에서는
    /// 항상 nil.
    private(set) var lastAIQueryUsed: String?

    /// [2026-08-20 신설, 2026-08-20 재수정 Phase 5] Layer 1(`QueryIntentClassifier`)
    /// + Layer 2(`QueryIntentHandler`) 결과 — 검색어가 관계/인물·지명 정보/
    /// 예언/주제·속성/서사 중 하나로 읽히면, 그 카테고리의 실제 데이터를 찾아
    /// 둔다. `SearchView`가 이 값이 있으면 결과 목록 맨 위에 카드로 보여준다.
    ///
    /// **[2026-08-20 재수정] 사용자 요청 — "단순 키워드 검색시(AI 토글 off
    /// 상태) 순수 키워드 검색결과만 나올 것 ... 관계정보 라든지, 그런것은 AI
    /// 토글을 켰을 때만 나오도록." 처음 설계(3계층 구조 문서 상단 주석)는
    /// "Layer 1/2는 모드와 무관하게 항상 같은 결과를 내야 한다"는 전제였는데,
    /// 사용자가 실사용 후 이 전제를 명시적으로 뒤집었다 — 이제 이 카드는
    /// `isAIQueryEnabled`가 켜져 있을 때만 계산되고(꺼져 있으면 항상 nil),
    /// 순수 키워드 검색은 이 카드의 존재 자체를 모른다(`performSearch` 참고).
    /// 아래 `performAIQuerySearch`가 이 카드의 성경 좌표(`QueryIntentCard.
    /// verseRefs`)를 "성경구절" 섹션에 직접 활용하기도 한다.
    private(set) var intentCard: QueryIntentCard?

    /// [2026-08-25 신설] 사용자 요청 — "limit 50을 해제할 수 있는 방법도
    /// 추가할 것 — 더보기 버튼." `searchVerses`가 이제 매칭된 절 전체(무제한)를
    /// 성경순으로 정렬해 돌려주므로, 그 전체를 여기 들고 있다가 화면엔
    /// `verseResults`(아래, `visibleVerseResultCount`만큼만 자른 부분집합)만
    /// 보여준다. "더보기"를 누르면 `loadMoreVerseResults()`가 이 값만 늘릴
    /// 뿐 DB를 다시 조회하지 않는다 — 이미 메모리에 다 있는 정렬된 배열에서
    /// 더 꺼내 보여주는 것뿐이라 비용이 사실상 없다.
    private(set) var allVerseResults: [VerseSearchResult] = []

    /// [2026-08-26 신설] "더보기 확인창" 조건 판단(아래 `effectiveMatchedWordCount()`)
    /// 에 쓰는, 이번 키워드 검색에 실제 쓰인 단어 목록. `performKeywordSearch`만
    /// 채운다 — AI(의미) 검색은 문장을 단어로 쪼개지 않고 임베딩으로 통째로
    /// 비교하므로 "단어 개수"라는 개념 자체가 없다. `performAIQuerySearch`가
    /// 항상 빈 배열로 되돌리므로(해당 함수 상단 참고) AI 검색에서는 이
    /// 배열이 비어 있어 확인창 조건(2개 이상)을 절대 만족하지 않는다.
    private var lastSearchWords: [String] = []

    /// [2026-08-26 신설] "더보기 확인창"을 이번 검색에서 이미 보여줬는지 —
    /// AskUserQuestion으로 확정한 답변("검색 1회당 최초 1번만") 그대로.
    /// `setVerseResults`가 새 결과를 채울 때마다(= 새 검색이 시작될 때마다)
    /// 함께 리셋된다.
    private var hasShownMoreResultsNotice = false

    /// [2026-08-26 신설] 사용자 요청 — "두 개 단어 이상 검색시 더보기를 누르면
    /// 확인창 ... 각 성경별로 추가 검색결과를 반영했으니 확인해보라는 내용."
    /// nil이 아니면 `SearchView`가 alert을 띄운다. "확인"을 누르면
    /// `confirmMoreResultsNotice()`가 호출되어 닫히고 이어서 더보기가
    /// 진행된다(AskUserQuestion 답변: "그냥 닫히고 더보기가 정상 진행").
    struct MoreResultsNotice: Identifiable {
        let id = UUID()
        /// 아직 화면에 보여주지 않은 결과들(`allVerseResults`의
        /// `visibleVerseResultCount` 이후 구간)에 걸친 서로 다른 성경책 수.
        /// AskUserQuestion에서 "성경별"이 번역본이 아니라 구약/신약 또는
        /// 개별 책 단위를 뜻한다는 확인을 받았으므로, 추측이 아니라 이미
        /// 메모리에 있는 데이터에서 직접 센 값을 안내 문구에 쓴다.
        let additionalBookCount: Int
    }
    private(set) var pendingMoreResultsNotice: MoreResultsNotice?
    // [2026-08-25 수정, 컴파일 에러] 저장 프로퍼티 초기화식 안에서는 `Self`
    // (공변 타입)를 참조할 수 없다 — `final class`라도 예외가 아니다(Swift가
    // 저장 프로퍼티 초기화 표현식 자체를 `Self`와 무관하게 컴파일하기
    // 때문). 메서드 본문 안(`loadMoreVerseResults`, `setVerseResults`)의
    // `Self.verseResultPageSize`는 이 제약이 적용되지 않아 문제없다 —
    // 여기 초기화식만 타입 이름을 직접 써야 한다.
    private var visibleVerseResultCount = SearchViewModel.verseResultPageSize
    // [2026-08-26 변경] 사용자 요청 — "검색결과를 100개 단위로 보여줄것."
    // 30 → 100.
    // [2026-09-05 변경] 사용자 요청 — "성경 검색결과를 50개 단위로
    // 불러올것." 100 → 50. 페이지 크기만 바뀔 뿐 그 위 주석의 "더보기는
    // DB를 다시 조회하지 않는다"는 동작은 그대로다.
    private static let verseResultPageSize = 50

    var verseResults: [VerseSearchResult] {
        Array(allVerseResults.prefix(visibleVerseResultCount))
    }

    /// [2026-08-26 신설] 사용자 요청 — "성경 검색 결과가 장별로 그룹핑되고, 그
    /// 같은 장안에 절이 세부적으로 표시될 수 있도록." `verseResults`(현재 화면에
    /// 보여주는, "더보기"로 늘어나는 부분집합)가 담긴 순서는 그대로 두되(가중치
    /// 정렬 결과라 장이 뒤섞여 있을 수 있음), 그룹(장) 자체를 별도 규칙으로
    /// 다시 나열한다. 그룹 안의 절은 절 번호 오름차순으로 다시 정렬해 "장 안에서
    /// 절이 순서대로 세부 표시"되게 한다. 이 그룹핑은 순수 표시용이라
    /// `allVerseResults`/`verseResults` 자체(가중치 랭킹, "더보기" 페이지네이션
    /// 기준)는 전혀 건드리지 않는다.
    ///
    /// [2026-08-26 그룹 정렬 규칙 변경, 같은 날 재정정] 사용자 요청 — "절 내에
    /// 가장 많이 일치가 된 이 구절을 가진 성경 장을 제일 먼저 나타내고, 일치된
    /// 절이 동일한 성경장은 정경순서 장 오름차순으로 표현할 것." 이전엔 이
    /// 자리에 "정경순(책/장) 오름차순 고정"이라고 사용자에게 직접 확인까지
    /// 받아 적어뒀었는데(8.2 문서 기록 참고), 이번 요청이 그 결정을 명시적으로
    /// 뒤집었다 — 애매한 요청이 아니라 구체적인 새 규칙이라 다시 확인을 구하지
    /// 않고 그대로 반영했다.
    ///
    /// [재정정] "가장 많이 일치된 절"이 무엇을 뜻하는지도 사용자가 예시로 다시
    /// 확인해 줬다 — "요약 횟수를 의미하는 것이 아니라 [중복 제거된 매칭된
    /// 검색어의 수]를 의미함"(예: "다윗 요압 이스라엘" 검색 시 세 단어가 모두
    /// 걸린 절이 있는 장이 1순위, 두 단어만 걸린 장들은 2순위 동점으로 묶여
    /// 정경순 2차 정렬). `VerseSearchResult.matchCount`가 이제 정확히 이
    /// "중복 제거된 매칭 단어 수"(`matchedWordCount`)를 담으므로(그 필드 상단
    /// 주석 참고), 이 정렬 로직 자체는 고칠 게 없었다 — `matchCount`의 정의를
    /// 고치는 것만으로 여기 정렬도 함께 올바르게 동작한다. 그룹 정렬의 1순위는
    /// 그 그룹 안에서 가장 큰 `matchCount` 내림차순, 이 값이 같은 그룹끼리만
    /// 정경순(책ID/장 오름차순)으로 2차 정렬한다.
    struct VerseSearchResultGroup: Identifiable {
        let bookId: Int
        let chapter: Int
        let bookNameKo: String
        let verses: [VerseSearchResult]
        var id: String { "\(bookId)-\(chapter)" }
    }

    /// [2026-09-05 추출] 사용자 요청 — "검색 결과에 [성경 구절] 탭의 하위
    /// 탭으로서 현재 활성화되어있는 번역본별로 노출." 아래 `groupedVerseResults`
    /// (전체 결과 기준)와 새로 추가하는 `groupedVerseResults(translationCode:)`
    /// (번역본별 하위 탭 기준)이 "절 목록을 장 단위로 묶고 매치 강도순으로
    /// 정렬한다"는 완전히 같은 로직을 입력만 다르게 받아 수행하므로, 그 로직을
    /// 여기 공용 헬퍼로 뽑아냈다 — 기존 `groupedVerseResults`의 동작(정렬
    /// 기준, 그룹 안 정렬 기준)은 한 글자도 바뀌지 않았고, 입력을 매개변수로
    /// 받도록만 옮겼다.
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

    /// [2026-09-05 신설] 사용자 요청 — "검색 결과에 [성경 구절] 탭의 하위
    /// 탭으로서 현재 사용하고 있는(활성화되어있는) 번역본별로 노출 시키도록."
    /// `verseResults`(페이지네이션 적용된, `allVerseResults`가 아닌 현재 화면
    /// 노출분)를 먼저 `translationCode`로 걸러낸 뒤 위 공용 헬퍼로 장 단위
    /// 그룹핑한다 — "더보기"가 여전히 `allVerseResults`/`visibleVerseResultCount`
    /// 하나만 관리하는 기존 페이지네이션 구조를 그대로 쓰므로(번역본별 별도
    /// 페이지네이션이 아니다), 어떤 번역본은 아직 화면에 로드된 결과가 적어
    /// "더보기"를 여러 번 눌러야 이 번역본 탭에 결과가 더 나타날 수 있다.
    func groupedVerseResults(translationCode: String) -> [VerseSearchResultGroup] {
        Self.groupByChapter(verseResults.filter { $0.translationCode == translationCode })
    }

    /// [2026-09-05 신설] "현재 활성화되어있는 번역본"의 근거 — `SearchViewModel`
    /// 은 `BibleReadingViewModel.displayedTranslationIDs`(해당 뷰모델 인스턴스
    /// 안에서만 사는 런타임 상태)에 접근할 방법이 없어(별개의 화면/뷰모델,
    /// 공유되는 지속 상태가 아님), 그 값 자체를 그대로 가져올 수 없다. 대신
    /// `BibleReadingViewModel.loadAvailableTranslations()`가 "표시할 번역본을
    /// 처음 정할 때" 쓰는 것과 동일한, 실제로 영속화된 소스(`UserSettingsStore.
    /// shared.defaultDisplayedTranslationCodes` 우선, 없으면 등록순 +
    /// `defaultTranslationCode` 맨 앞) 규칙을 여기서도 그대로 재현한다 — 그
    /// 뷰모델의 "이미 선택된 목록이 있으면 그대로 유지"(사용자가 팝오버에서
    /// 직접 골라 그 세션 동안 바꾼 값) 분기는 이 화면엔 대응 개념이 없으므로
    /// 재현하지 않는다. 따라서 이 값은 "설정상 기본 표시 번역본"의 최선의
    /// 근사치이며, 사용자가 성경 조회 화면에서 그 세션 중 임시로 다른 조합을
    /// 선택해둔 상태와는 다를 수 있음을 알린다(README/사용자 안내 필요).
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

    /// [2026-09-05 신설] 사용자 요청 — "개요 검색결과를 성경단위로 그룹핑
    /// 할것. (성경검색 결과가 장단위로 그룹핑 된것처럼)" 바로 위
    /// `VerseSearchResultGroup`/`groupedVerseResults`와 같은 목적(순수
    /// 표시용 재배열, `outlineResults` 자체의 순서/필터링은 건드리지 않음)
    /// 이지만 그룹 키는 "장"이 아니라 "책"이다 — `OutlineSearchResult`가
    /// 책 단위(`BookOutline`, `chapter == nil`)와 장 단위(`ChapterSummary`)
    /// 결과를 함께 담고 있어(위 `OutlineSearchKind` 참고), 장 단위로
    /// 나누면 같은 책의 "책 전체 개요"와 "N장 개요"가 서로 다른 그룹으로
    /// 흩어져 버리기 때문이다.
    ///
    /// [그룹 정렬 규칙, 2026-09-05 수정] 사용자 요청 — "성경 정경 순서대로
    /// 정렬할 것." 처음엔 대응하는 매칭-강도 필드가 없어(`VerseSearchResult.
    /// matchCount`처럼 "중복 제거된 매칭 단어 수"를 담는 필드가
    /// `OutlineSearchResult`엔 없음 — `bodyOccurrenceSum`은 "본문 총 등장
    /// 횟수"라 의미가 다름) 관련도 순서(`outlineResults`가 이미 정렬해 온
    /// 순서)를 그룹 등장 순서로 썼는데, 이번 요청이 그 결정을 명시적으로
    /// 정경 순서로 뒤집었다 — `Book.orderIndex`(원본 `Books.order_index`
    /// 컬럼, `BibleReferenceModels.Book` 선언부 주석 참고 — `bookId`는
    /// 그냥 기본키일 뿐 정경 순서를 보장하는 필드가 아니다)를 오름차순으로
    /// 쓴다. `searchVerses`의 정경순 정렬(`orderIndex` 사용, 이 파일
    /// 위쪽)과 같은 필드·같은 근거다. 그룹 안에서는 여전히 `chapter`가
    /// `nil`(책 전체 개요)인 항목을 먼저, 그다음 장 오름차순으로 정렬한다 —
    /// `groupedVerseResults`가 그룹 안에서 절 오름차순으로 정렬하는 것과
    /// 같은 이유(그룹 헤더 아래 세부 항목이 순서대로 읽히도록)이며, 책
    /// 전체 개요가 장별 개요보다 상위 개념이므로 먼저 보여주는 것이
    /// 자연스럽다.
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
                let lhsOrder = booksProvider.book(id: lhs.bookId)?.orderIndex ?? lhs.bookId
                let rhsOrder = booksProvider.book(id: rhs.bookId)?.orderIndex ?? rhs.bookId
                return lhsOrder < rhsOrder
            }
    }

    /// "더보기" 버튼을 보여줄지 — 아직 화면에 안 보여준 결과가 남아 있는지.
    var hasMoreVerseResults: Bool {
        allVerseResults.count > visibleVerseResultCount
    }

    /// [2026-08-25 신설, 2026-08-26 확인창 추가] "더보기" 버튼이 호출. 새
    /// 검색이 시작되면 `performKeywordSearch`/`clearResults`가
    /// `verseResultPageSize`로 되돌린다.
    ///
    /// [2026-08-26] 사용자 요청 — "두 개 단어 이상 검색시 더보기를 누르면
    /// 확인창 ... 한 단어이거나 여러 단어를 검색했더라도 한 단어밖에 검색할
    /// 수 없으면 확인창이 안떠도 됨." 이번 검색에서 아직 확인창을 안
    /// 보여줬고, 실제로 매칭에 기여한 서로 다른 단어가 2개 이상이면
    /// 페이지를 늘리는 대신 `pendingMoreResultsNotice`만 채우고 멈춘다 —
    /// 실제 페이지 증가는 사용자가 확인창에서 "확인"을 눌러
    /// `confirmMoreResultsNotice()`를 호출해야 일어난다.
    func loadMoreVerseResults() {
        if !hasShownMoreResultsNotice, effectiveMatchedWordCount() >= 2 {
            hasShownMoreResultsNotice = true
            let additionalBookCount = Set(allVerseResults.dropFirst(visibleVerseResultCount).map(\.bookId)).count
            pendingMoreResultsNotice = MoreResultsNotice(additionalBookCount: additionalBookCount)
            return
        }
        visibleVerseResultCount += Self.verseResultPageSize
    }

    /// [2026-08-26 신설] `pendingMoreResultsNotice` alert의 "확인" 버튼이
    /// 호출 — 확인창을 닫고, 원래 `loadMoreVerseResults()`가 하려던 페이지
    /// 증가를 그대로 이어서 한다(AskUserQuestion 답변: "그냥 닫히고 더보기가
    /// 정상 진행").
    func confirmMoreResultsNotice() {
        pendingMoreResultsNotice = nil
        visibleVerseResultCount += Self.verseResultPageSize
    }

    /// [2026-08-26 신설] `pendingMoreResultsNotice`가 `private(set)`이라
    /// `SearchView`가 직접 `nil`을 대입할 수 없다(빌드 에러: "setter is
    /// inaccessible") — alert이 "확인" 버튼이 아닌 다른 경로(시스템
    /// 스와이프/ESC 등, `.alert(isPresented:)` 바인딩의 `set` 클로저가
    /// `false`를 받는 모든 경우)로 닫힐 때 상태를 정리하는 전용 진입점을
    /// 대신 둔다. `confirmMoreResultsNotice()`와 달리 더보기 페이지 증가는
    /// 하지 않는다 — 그냥 닫기만 한다.
    func dismissMoreResultsNotice() {
        pendingMoreResultsNotice = nil
    }

    /// [2026-08-26 신설] "더보기 확인창"을 띄울지 판단하는 핵심 로직 —
    /// AskUserQuestion으로 확정한 기준 그대로: `lastSearchWords`(이번 검색
    /// 단어들, 중복 제거) 중 이미 메모리에 있는 `allVerseResults`(DB 재조회
    /// 없음) 어딘가의 본문에 대소문자 무시 부분일치로 최소 1번이라도
    /// 등장하는 서로 다른 단어의 개수를 센다. 예: "다윗 컴퓨터"는 두
    /// 단어지만 "컴퓨터"가 성경 본문 어디에도 없어 매칭 0건이므로 이 값이
    /// 1(다윗만)이 되어 확인창 조건(>= 2)을 만족하지 못한다. "다윗 다윗
    /// 맥북"처럼 같은 단어가 중복 입력돼도 `Set`으로 중복 제거되어 정확히
    /// 1로 계산된다.
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

    /// [2026-08-25 신설] `allVerseResults`를 새로 채울 때마다 "더보기" 스크롤
    /// 위치(`visibleVerseResultCount`)를 첫 페이지로 되돌린다 — 이전 검색에서
    /// 눌러둔 "더보기" 상태가 새 검색 결과에 그대로 남아있으면 안 되므로,
    /// 대입이 일어나는 여러 곳(`clearResults`, `performKeywordSearch`,
    /// `performAIQuerySearch`)이 각자 리셋을 빠뜨릴 위험 없이 하나로 묶었다.
    ///
    /// [2026-08-26 확장] "더보기 확인창" 상태(`hasShownMoreResultsNotice`/
    /// `pendingMoreResultsNotice`)도 같은 이유로 여기서 함께 리셋한다 — 새
    /// 검색마다 확인창이 다시 최초 1번 뜰 수 있어야 한다.
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
        intentCard = nil
        setVerseResults([])
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
        // [2026-08-26 추가] `SearchResultsPopRequest.swift` 상단 주석 참고 —
        // 검색이 사이드바 상단 검색창이든 이 화면 자체의 `.searchable`
        // 검색창이든, 실제로 새 검색이 시작되는 지점은 결국 여기 하나뿐이다.
        // 성경 조회 화면이 push된 채로 다시 검색해도 검색결과 화면이 보이도록
        // `SidebarNavigationView`에 pop을 요청한다.
        SearchResultsPopRequest.shared.requestPop()
        // [2026-09-04 신설] 사용자 요청 — "검색이력 기능 추가." 실제로 검색이
        // 실행되는 지점이 여기 하나뿐이라(위 주석 참고), 검색 이력도 정확히
        // 여기서만 기록한다 — 타이핑 중간값이나(위 `guard` 이전) AI 검색
        // 최소 길이 미달로 실행되지 못한 시도(바로 위 `guard` — 그 경우
        // 이미 return해 여기까지 오지 않는다)는 기록되지 않는다.
        SearchHistoryService.record(query: trimmed, context: modelContext)
        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.performSearch(query: trimmed)
        }
    }

    /// [2026-09-04 신설] 사용자 요청 — "통합검색을 클릭했을 때 검색창 밑으로
    /// 검색이력 최근 20개가 나올 수 있도록." `SearchView`의 `.searchSuggestions`가
    /// 검색창이 포커스를 받을 때마다(검색어가 비어 있을 때) 이 값을 다시
    /// 불러 보여준다 — 책갈피/조회 이력과 같은 이유로 캐싱하지 않는다(다른
    /// 창에서 쌓인 검색이력까지 반영되도록).
    func recentSearchHistory() -> [SearchHistoryEntry] {
        SearchHistoryService.fetchRecent(context: modelContext)
    }

    private func performSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }

        // [2026-09-05 신설] 사용자 요청 — "검색어를 입력하고 검색하면
        // 결과없음 이라는 페이지가 먼저 뜨다가 2-3초 후에 결과가 나옴...
        // 스피너 또는 프로그레스 창이 뜰 수 있도록 할 것." `SearchView`엔
        // 이미 `viewModel.isSearching`을 보고 "검색 중..." 스피너를 그리는
        // 코드가 있었다(위 `isSearching` 프로퍼티 위 로직) — 문제는 이
        // 함수가 실행되는 방식이었다. Swift 구조적 동시성에서 `Task { ... }`
        // 클로저는 첫 `await` 지점까지는 동기적으로(런루프에 제어권을
        // 넘기지 않고) 실행된다(Swift 공식 문서, "Tasks and Task Groups" —
        // a task starts running immediately when created, up to its first
        // suspension point). 아래 `else` 분기(AI 토글 off, 기본 키워드
        // 검색)는 `performKeywordSearch`가 완전히 동기 함수라 `await`가
        // 전혀 없었다 — 즉 `isSearching = true`를 SwiftUI가 화면에 반영할
        // 기회(런루프 한 틱)를 얻기도 전에 2-3초짜리 동기 연산이 같은
        // 틱에서 끝나 버리고 `defer`로 곧장 `false`가 되어, 스피너가 뜰 새
        // 없이 "결과 없음"(검색 시작 직후의 빈 상태)이 먼저 그려졌다가
        // 결과가 한꺼번에 나타난 것처럼 보였다. `Task.yield()`로 현재
        // 실행을 한 번 실제로 중단시켜 런루프에 제어권을 돌려주면, SwiftUI가
        // 그 사이에 `isSearching = true` 상태로 최소 한 프레임을 그릴 수
        // 있다. AI 검색(`if` 분기)은 이미 `await performAIQuerySearch(...)`가
        // 있어 이 문제가 없었다.
        await Task.yield()

        // [2026-08-20 재수정, Phase 5] 사용자 요청 — "단순 키워드 검색시(AI
        // 토글 off)엔 순수 키워드 검색결과만, 관계정보 카드는 AI 토글을 켰을
        // 때만." 이전엔 모드와 무관하게 항상 Layer 1/2를 먼저 계산했는데(3계층
        // 구조의 원래 전제), 이제 AI 검색일 때만 계산한다 — `intentCard`
        // 선언부 주석 참고.
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

    /// [2026-08-18 대폭 확장] 6개 분류 전부를 채운다. 성경장절 인식(4가지 요구사항
    /// — 띄어쓰기 무시/약어↔전체이름/범위 포함)은 `BibleReferenceExtractor` 하나로
    /// 충족한다(`DocumentsHomeView.searchVerseQueryMatches` 상단 주석과 같은 근거).
    ///
    /// [2026-08-19 단순화] 한때 AI 토글 검색이 이 함수에 `referenceOnlyMatches`를
    /// 넘겨 재사용했었지만, AI 검색이 임베딩 기반 의미검색(`performAIQuerySearch`
    /// 참고)으로 완전히 바뀌면서 더 이상 이 함수를 거치지 않는다 — 순수 키워드
    /// 검색 전용으로 되돌렸다.
    private func performKeywordSearch(query: String) async {
        errorDescription = nil
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        // [2026-08-26 추가] "더보기 확인창" 조건 판단(`effectiveMatchedWordCount()`)
        // 이 이번 검색에 실제 쓰인 단어들을 알아야 하므로 저장해 둔다 — 위
        // `lastSearchWords` 선언부 주석 참고.
        lastSearchWords = words
        let queryMatches = BibleReferenceExtractor.extract(from: query)

        // [2026-09-05 변경] 사용자 요청 — "검색을 하면 성경검색 결과가
        // 제일먼저 나오니.. 먼저 성경검색결과가 나오는대로 화면에 출력하고
        // 병렬로 백그라운드에서 나머지 탭을 [개요][메모/말씀노트][연구문서]
        // 구성할 것." 예전엔 이 함수가 완전한 동기 함수라 6개 분류를 전부
        // 계산할 때까지 SwiftUI가 다시 그릴 기회 자체가 없었다 — 중간에
        // `await`가 없으면 러프 한 틱 안에서 전부 끝나 버리기 때문이다(위
        // `performSearch`의 `Task.yield()` 도입 주석과 같은 원리, Swift
        // 공식 문서: 태스크는 첫 중단 지점까지 동기적으로 실행된다). 이제
        // 각 결과를 채운 직후 `await Task.yield()`로 실행을 한 번 실제로
        // 양보해 SwiftUI가 그 시점까지의 결과로 화면을 다시 그릴 기회를
        // 준다 — 성경구절이 가장 먼저 채워지고, 그다음 개요, 그다음
        // 메모/말씀노트(검색 결과 탭이 이 셋을 하나로 묶어 보여주므로
        // 함께 채운다 — `SearchView.SearchResultTab.notes`, title "메모/
        // 말씀노트" 참고), 마지막으로 연구문서 순으로 화면에 이어서
        // 나타난다.
        //
        // [스레딩 근거 — 진짜 "백그라운드 스레드 병렬"을 쓰지 않은 이유]
        // 이 클래스는 `@MainActor`이고, `modelContext`(SwiftData)와
        // `storeCache`(`BibleReferenceStore` — "스레드 안전을 자체
        // 보장하지 않는다"는 그 타입 상단 주석)도 전부 메인 액터에 묶여
        // 있다. 이 상태 그대로 각 분류를 실제 백그라운드 스레드에서
        // 동시에 돌리려면 분류마다 별도 `ModelContext`(SwiftData 표준
        // 패턴 — `ModelContext(modelContext.container)`)와 별도
        // `BibleReferenceStore` 인스턴스를 새로 만들어야 하고, 이 패키지가
        // 이미 Swift 6(Package.swift `swift-tools-version: 6.0`)라 각
        // 결과 타입의 `Sendable` 적합성까지 새로 맞아야 한다 — 이 세션은
        // Xcode 빌드를 실행할 수 없어 그 정도 범위의 동시성 변경을
        // "검증된 코드"로 낼 근거가 없다고 판단했다. 대신 메인 액터 위에서
        // `Task.yield()`로 단계마다 실행을 양보하는 방식을 택했다 —
        // 사용자가 실제로 체감하는 결과("성경 먼저, 나머지는 이어서 채워짐")는
        // 동일하게 달성하면서, 컴파일 확인 없이 SwiftData/SQLite 동시성
        // 코드를 새로 추가하는 위험을 지지 않는다. 진짜 멀티스레드 병렬화가
        // 필요하면 Xcode에서 직접 빌드 검증이 가능한 별도 작업으로 진행할
        // 것을 권장한다(아래 최종 요약에서도 안내).
        setVerseResults(searchVerses(query: query, words: words, queryMatches: queryMatches))
        await Task.yield()

        outlineResults = searchOutlines(words: words, queryMatches: queryMatches)
        await Task.yield()

        phraseNoteResults = searchPhraseNotes(words: words, queryMatches: queryMatches)
        memoResults = searchMemos(words: words, queryMatches: queryMatches)
        summaryResults = searchSummaries(words: words, queryMatches: queryMatches)
        await Task.yield()

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

    /// [2026-09-05 `maxSegmentLength` 파라미터 추가] 사용자 요청(개요 검색
    /// 결과 전용) — "일치하는 텍스트의 해당 라인의 노출되는 글자를 35자
    /// 이내로 늘릴것." 기존엔 매칭된 단어마다 "단어 자체 + 뒤 9자"만 잘라
    /// 발췌를 만들었는데(바로 아래 `nil` 분기 — 이 상수 9는 그대로 남아
    /// 있다), 그 발췌가 이 함수를 공유하는 5개 분류(개요/메모/개인 묵상/
    /// 말씀 요약/연구문서) 중 개요 화면에서 한 줄로 새로 그리기엔
    /// (`SearchView.groupedOutlineRow`, 9.5일 재설계) 너무 짧았다. 이
    /// 함수는 `DocumentsHomeView.searchScore`와 같은 발췌 규칙을 공유하는
    /// 5곳 모두가 호출하므로, 상수 9를 그냥 35로 올리면 요청하지 않은 나머지
    /// 4개 분류(메모/개인 묵상/말씀 요약/연구문서)의 발췌 길이까지 함께
    /// 바뀐다 — 그건 이번 요청 범위 밖이다(근거 없는 리팩토링 금지). 그래서
    /// 기본값 `nil`일 때는 기존 "단어 끝(`upperBound`) + 9자" 공식을 한 글자도
    /// 안 바꾸고 그대로 두고, 값이 주어질 때만 "매칭 시작(`lowerBound`)부터
    /// 최대 N자"로 총 노출 길이 자체를 상한선으로 못 박는 새 계산을 쓴다 —
    /// `searchOutlines`(개요 전용 호출부, 아래)만 `maxSegmentLength: 35`를
    /// 넘겨 이 새 계산을 쓰고, 나머지 4곳은 파라미터를 안 넘겨 기존 동작이
    /// 100% 그대로다.
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

    /// [2026-09-05 신설] `verseMentionSearchTexts`와 같은 필터 조건이지만
    /// 특정 `sourceId` 하나로 좁히지 않고 카테고리 전체 기준으로 모은다 —
    /// `contentCandidateSourceIds`(FTS 후보 좁히기)는 항목 하나하나가 아니라
    /// 카테고리 전체에 대해 한 번만 질의하므로, 그 카테고리 안 "어떤 항목의
    /// 것이든" 매치될 수 있는 원문 표기를 전부 모아 둬야 한다 — 항목별
    /// `verseMentionSearchTexts` 결과는 이 집합의 부분집합이므로(sourceId
    /// 조건만 더 좁을 뿐 같은 필터), 이 값으로 후보를 좁혀도 개별 항목이
    /// 실제로 검사할 verseTerms를 놓치지 않는다(안전한 상위집합).
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

    /// [2026-09-05 신설] 사용자 요청 — "개요/메모/개인 묵상/말씀 요약/연구문서
    /// 5개 카테고리 전체스캔 최적화 → FTS5 보조 인덱스(unicode61)로 후보 축소."
    /// 6개 SwiftData 모델(개요/장별개요/메모/개인묵상/말씀요약/연구문서) 검색
    /// 함수가 공통으로 쓰는 "후보 좁히기" 한 단계 — `UserContentSearchIndex`
    /// (BibleResearchModels 패키지)에 이 카테고리에서 아직 안 채워진 항목을
    /// 자가 치유(self-healing)로 채워 넣은 뒤(`SourceDocument.cachedCombinedText`
    /// 백필과 같은 패턴 — 이 기능 도입 이전의 기존 데이터를 위한 것, 새로
    /// 저장되는 항목은 각 화면의 저장 지점에서 이미 최신 상태로 유지된다),
    /// `words`(+`extraTerms` — 성경 참조 검색어의 원문 표기, 아래 호출부의
    /// `verseMentionSearchTexts`와 같은 개념이지만 항목 하나가 아니라 카테고리
    /// 전체 기준으로 모은 것) 중 하나라도 매치되는 source_id만 돌려준다.
    ///
    /// [정확성 안전장치] FTS든 자가 치유 백필이든 어느 단계에서 실패하면
    /// (디렉터리 접근 실패, SQLite 오류) `liveContentById`의 모든 키를 후보로
    /// 반환한다 — "속도보다 정확성이 보장돼야 한다"는 요청 원칙에 따라, 이
    /// 최적화 계층 자체가 고장 나도 결과가 누락되는 일은 없어야 한다(그 경우
    /// 그냥 기존처럼 호출부가 전체 항목에 `computeWordMatchScore`를 돌리게
    /// 된다).
    ///
    /// [알려진 트레이드오프, 사용자에게 이미 고지·확정됨] `UserContentSearchIndex.
    /// swift` 상단 주석 참고 — unicode61은 토큰 접두어 매칭이라 "검색어가
    /// 토큰 중간에 낌"(예: "사랑"으로 "내사랑"을 못 찾음) 케이스는 이 좁히기
    /// 단계에서 후보 밖으로 빠질 수 있다. 이미 성경구절 전체 검색(번들 FTS5)이
    /// 갖고 있던 것과 같은 특성이고, 그 기준을 나머지 카테고리에도 그대로
    /// 맞추는 것이 이번 요청의 취지다(trigram 방식은 사용자가 명시적으로
    /// 거절했다, 2026-09-05).
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

    /// [2026-08-18 확장] 검색어가 성경 참조로 해석되면(`queryMatches`) 그 절(들)을
    /// 직접 조회해 맨 앞에 보여준다 — 창1:3으로 검색하면 본문에 "1:3"이라는
    /// 글자가 없어도 정확히 창세기 1:3이 나와야 하기 때문("연구문서 리스트 검색
    /// 기능처럼 성경 장절 검색기능이 포함되도록" 요청 그대로). 그 외엔 기존처럼
    /// 각 단어를 `BibleReferenceStore.searchVerses`(본문 텍스트 검색)로 OR
    /// 조회한다.
    private func searchVerses(query: String, words: [String], queryMatches: [BibleReferenceExtractor.Match]) -> [VerseSearchResult] {
        guard let registries = try? modelContext.fetch(FetchDescriptor<TranslationRegistry>()) else { return [] }
        // [2026-09-05 추가] 사용자 요청 — "성경구절 탭의 하위 탭으로 활성
        // 번역본별 결과 노출." 이 함수가 검색 1회당 정확히 1번만 호출되므로
        // (호출부 `performKeywordSearch` 참고, 이 파일 내 유일한 호출 지점)
        // 여기서 한 번만 계산해 캐싱한다 — `activeTranslations`를 SwiftUI가
        // 매 렌더링마다 다시 계산하는 연산 프로퍼티로 두면 렌더링 때마다
        // SwiftData 재조회가 생기므로 피한다(위 `resolveActiveTranslations`
        // 선언부 주석 참고).
        activeTranslations = resolveActiveTranslations(from: registries)
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
                    // [2026-09-05 변경] 사용자 요청 — "성경구절 탭의 하위 탭으로
                    // 활성 번역본별 결과를 노출." 이 dedup 키는 2026-08-29
                    // 추가 당시엔 "같은 절에 여러 번역본이 매칭되면 먼저 처리된
                    // 번역본만 남긴다"는 의도로 절 좌표만 썼다(VerseSearchResult.
                    // translationCode 선언부의 그 날짜 주석 참고) — 번역본별
                    // 하위 탭을 만들려면 같은 절이라도 번역본마다 별도 결과로
                    // 남아야 하므로, 그 결정을 뒤집어 키에 `registry.code`를
                    // 더한다(번역본이 다르면 같은 절이어도 별개 항목).
                    let key = "\(verse.bookId)-\(verse.chapter)-\(verse.verse)-\(registry.code)"
                    guard seen.insert(key).inserted else { continue }
                    results.append(VerseSearchResult(
                        bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse,
                        content: verse.content,
                        bookNameKo: booksProvider.book(id: verse.bookId)?.nameKo ?? "\(verse.bookId)권",
                        translationCode: registry.code, translationDisplayName: registry.displayName,
                        isReferenceMatch: true
                    ))
                    // [2026-08-25 삭제] 예전엔 여기서 `results.count >= 30`이면
                    // 함수 전체를 조기 반환했다 — "시편 119편"처럼 참조 매치만으로
                    // 30개를 넘는 질의는 뒤의 단어 기반 후보(scoredCandidates)를
                    // 아예 계산하지도 못하고 끝나 버렸다. 이제 30개라는 화면
                    // 표시 개수 자체가 없다(아래 최종 반환부 참고 — 전체를
                    // 돌려주고 "더보기"는 `SearchViewModel`이 화면에 보여줄
                    // 개수만 조절한다), 그러니 여기서도 조기 반환할 이유가
                    // 없다.
                }
            }
        }

        // [2026-08-20 재작성] 사용자 요청 — "띄어쓰기 단어가 모두 일치하면
        // 100, 한 단어만 일치하면 50, 그 중 여러 번 일치한 횟수*10처럼
        // 가중치로 계산 ... 모두 일치해야 가장 높은 점수가 확보되어야 함 ...
        // 가중치 내림차순으로 나와야 함." 이전엔 단어마다 순서대로 LIKE 조회해
        // 30개 채우면 그 자리에서 바로 반환했다(정렬이라는 개념 자체가 없었다).
        // 이제는 먼저 모든 단어(동의어 포함, `RelationSynonyms`)의 후보를 전부
        // 모은 뒤 `KeywordMatchScorer`로 점수를 매기고, 내림차순 정렬 후에야
        // 상위 30개를 자른다 — 그래야 "일부만 일치하지만 흔한 단어라 결과가
        // 많은" 후보가 "모두 일치하는" 진짜 정답보다 먼저 채워져 뒤의 정답을
        // 밀어내는 일이 없다.
        //
        // [2026-08-20 신설, FTS5 전환] 사용자 요청 — "개역한글 기본 번들
        // 성경은 FTS5 unicode61로 변환할 것. 앞뒤 라이크하지 말고 뒤
        // 라이크(prefix)로만." 번들 기본 번역본(`TranslationBootstrap.
        // bundledTranslationCode`, 개역한글)에 한해 이미 만들어져 있었지만
        // 실제 검색 경로 어디에도 연결되지 않았던 `ReferenceDataStore.
        // searchVersesFullText`(FTS5 unicode61, prefix 검색, `ReferenceData.
        // sqlite`의 `VerseSearchIndex` — 소스가 BibleDB.sqlite와 동일한
        // 개역한글 31,102절이라 새 DB를 만들 필요가 없었다)를 쓴다. 사용자가
        // 추가한 다른 번역본 파일은 이 FTS5 인덱스가 없으므로(요청 범위 밖)
        // 기존 LIKE(`BibleReferenceStore.searchVerses`)를 그대로 쓴다.
        var wordCandidates: [String: (verse: BibleVerse, bookNameKo: String, translationCode: String, translationDisplayName: String)] = [:]
        let fullTextStore = ReferenceDataProvider.shared.store
        for registry in registries {
            guard let store = try? store(for: registry) else { continue }
            let versionCode = store.hasVersionCodeColumn ? registry.code : nil
            let useBundledFullText = registry.code == TranslationBootstrap.bundledTranslationCode && fullTextStore != nil

            // [2026-09-05 추가, 같은 날 재수정] 사용자 요청 — "사용자 추가
            // 번역본에 대해서도 FTS5를 할 수 있도록 수정할 것"(검색 속도 질의에
            // 대한 원인 설명 후속) → 이후 "인덱스 생성은 검색 시점이 아니라
            // 번역본 업로드 시점을 기본으로 하고, 기존 업로드된 번역본은
            // 신경쓰지 않도록" 요청으로 정정. 번들 번역본 전용이던 위 FTS5
            // 경로를, 번들이 아닌 번역본에도 `TranslationSearchIndex`(보조
            // FTS5 인덱스 파일 — 원본 번역본 파일은 `BibleReferenceStore`가
            // 항상 SQLITE_OPEN_READONLY로 열므로 그 파일 자체는 손대지 않는다,
            // 그 타입 상단 주석 참고)로 확장하되, 이 검색 경로는 인덱스를
            // 새로 만들지 않고 "이미 있는지"만 확인한다 — 빌드는
            // `TranslationFileMaterializer.writeLocalCopy`(번역본이 이 기기에
            // 처음 로컬로 써지는 시점)에서만 일어난다. 그래서 이 변경 이전에
            // 이미 이 기기에 있던 번역본은 인덱스가 없을 것이고, 그 경우
            // `companionIndexDirectory`가 nil로 남아 기존 LIKE 경로로 그대로
            // 폴백한다(요청하신 대로 자동 백필 없음).
            var companionIndexDirectory: URL?
            if !useBundledFullText {
                let directory = URL(fileURLWithPath: store.filePath).deletingLastPathComponent()
                if TranslationSearchIndex.indexExists(registryID: registry.id, indexDirectory: directory) {
                    companionIndexDirectory = directory
                }
            }

            // FTS5(번들 전용 경로/사용자 추가 번역본 보조 인덱스 경로) 매치
            // 결과를 wordCandidates에 반영하는 공통 처리 — 두 경로 모두
            // `FullTextVerseMatch` 배열을 반환하므로 동일한 변환 로직을
            // 재사용한다(아래 각 호출부의 versionCode/registry는 이 registry
            // 순회 스코프의 값을 그대로 캡처).
            func ingestFullTextMatches(_ matches: [FullTextVerseMatch]) {
                for match in matches {
                    // [2026-09-05 변경] 위 참조매치 dedup 키 변경과 같은 이유 —
                    // `registry.code`를 더해 번역본별로 별개 결과를 남긴다.
                    let key = "\(match.bookId)-\(match.chapter)-\(match.verse)-\(registry.code)"
                    guard !seen.contains(key), wordCandidates[key] == nil else { continue }
                    wordCandidates[key] = (
                        BibleVerse(uid: 0, versionCode: versionCode, bookId: match.bookId, chapter: match.chapter, verse: match.verse, content: match.content, paragraph: nil),
                        booksProvider.book(id: match.bookId)?.nameKo ?? "\(match.bookId)권",
                        registry.code, registry.displayName
                    )
                }
            }

            // [2026-08-25 변경] 사용자 요청 — "limit 50을 해제할 수 있는 방법도
            // 추가할 것(더보기 버튼)." 예전엔 두 경로 다 `limit: 50`을 넘겨
            // 후보 자체를 50개로 자른 뒤 재정렬했다 — FTS5 경로는 그 50개를
            // bm25 관련도 순으로 골랐던 탓에 "다윗"(953건)처럼 흔한 단어는
            // 성경순 앞쪽 결과가 통째로 후보에서 빠지는 문제가 있었다(위
            // `ReferenceDataStore.searchVersesFullText` 변경 참고). 이제 두
            // 함수 다 `limit`이 옵셔널이라, 인자를 넘기지 않으면(기본값
            // `nil`) 해당 단어의 실제 등장 전체를 후보로 모은다 — 화면에
            // 몇 개를 보여줄지는 이 함수가 아니라 `verseResults`/
            // `loadMoreVerseResults()`(더보기 버튼)가 나중에 결정한다.
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
                            // [2026-09-05 변경] 위 두 곳과 같은 이유 — 번역본별 결과 유지.
                            let key = "\(verse.bookId)-\(verse.chapter)-\(verse.verse)-\(registry.code)"
                            guard !seen.contains(key), wordCandidates[key] == nil else { continue }
                            wordCandidates[key] = (verse, booksProvider.book(id: verse.bookId)?.nameKo ?? "\(verse.bookId)권", registry.code, registry.displayName)
                        }
                    }
                }
            }
        }

        // [2026-08-25 변경] 사용자 요청 — "성경구절의 가중치가 동일한 경우 성경
        // 순서대로 장절 오름차순대로 정렬할 것. 검색어 단어가 한개인 경우는
        // 무조건 성경 순서 + 장절 오름차순 나타낼 것." `wordCandidates`는
        // Dictionary라 `.values` 순회 순서가 해시 기반이라 실행마다 달라질 수
        // 있다 — 이전엔 `$0.score > $1.score`만으로 정렬해서 점수가 같으면
        // 사실상 무작위 순서로 보였다. 이제 점수가 같을 때 (정경 순서, 장, 절)
        // 오름차순으로 명시적으로 끊는다 — `KeywordMatchScorer.Score`가 더 이상
        // 등장 반복 횟수로 가중치를 안 매기므로(그 파일 상단 주석 참고), 단어가
        // 한 개뿐인 질의는 매칭된 모든 결과의 점수가 항상 똑같아져 이 tie-break가
        // 사실상 전체 정렬을 담당하게 되고, 그 결과 "단어가 한 개인 경우는
        // 무조건 성경 순서" 요구사항도 별도 분기 없이 자동으로 충족된다.
        let scoredCandidates = wordCandidates.values
            .map { entry -> (result: VerseSearchResult, score: KeywordMatchScorer.Score, orderIndex: Int) in
                let score = KeywordMatchScorer.score(words: words, in: entry.verse.content)
                let result = VerseSearchResult(
                    bookId: entry.verse.bookId, chapter: entry.verse.chapter, verse: entry.verse.verse,
                    content: entry.verse.content, bookNameKo: entry.bookNameKo,
                    translationCode: entry.translationCode, translationDisplayName: entry.translationDisplayName,
                    highlightKeywords: words,
                    // [2026-08-26 추가, 같은 날 정정] 위 `VerseSearchResult.
                    // matchCount` 상단 주석 참고 — 처음엔 `score.totalOccurrences`
                    // 였는데, 사용자가 "중복 제거된 매칭된 검색어의 수"를 원한다고
                    // 정정해 `score.matchedWordCount`로 바꿨다. 이 값은 바로 위에서
                    // 계산한 `score`(정렬 tie-break가 쓰는 그 값)의 필드라 별도
                    // 계산이 아니라 그대로 재사용한 것이다.
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

        // [2026-08-25 변경] 예전엔 여기서 `results.count < 30`까지만 채우고
        // 나머지 scoredCandidates는 버렸다 — "50개 후보 중 상위 30개"였던
        // 예전 설계에서도 이미 실제 등장 전체를 반영하지 못했는데, 이제
        // 후보 자체가 전체(무제한)이니 여기서 자르면 "더보기"가 보여줄
        // 데이터 자체가 없어진다. 화면에 몇 개를 보여줄지는 더 이상 이
        // 함수의 책임이 아니다 — 전체를 그대로 돌려주고, `verseResults`
        // (더보기 버튼과 함께)가 그중 보여줄 개수만 결정한다.
        results.append(contentsOf: scoredCandidates.map(\.result))
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

        // [2026-09-05 추가] 위 `contentCandidateSourceIds` 선언부 주석 참고 —
        // 책 개요/장별 개요는 서로 다른 모델이라 카테고리도 따로 좁힌다.
        // `verseTerms`가 없는 카테고리(항상 `[]`로 호출, 아래 루프도 동일)라
        // `extraTerms`는 넘기지 않는다.
        let outlineContentCandidates = contentCandidateSourceIds(
            category: .outline, words: words,
            liveContentById: Dictionary(uniqueKeysWithValues: bookOutlines.map { ($0.id.uuidString, $0.contentText) })
        )
        let chapterSummaryContentCandidates = contentCandidateSourceIds(
            category: .chapterSummary, words: words,
            liveContentById: Dictionary(uniqueKeysWithValues: chapterSummaries.map { ($0.id.uuidString, $0.contentText) })
        )

        var results: [(result: OutlineSearchResult, score: Int)] = []

        for outline in bookOutlines {
            let refMatch = queryMatches.contains { $0.bookId == outline.bookId }
            // [2026-09-05 추가] 참조매치가 아니고 FTS 후보에도 없으면(=본문에
            // 매치될 가능성이 거의 없으면) 아래 `computeWordMatchScore`의
            // 전체 문자열 스캔 자체를 건너뛴다 — 결과는 그 스캔이 어차피
            // "매치 없음"을 반환했을 경우와 같다(위 헬퍼의 트레이드오프 주석
            // 참고).
            guard refMatch || outlineContentCandidates.contains(outline.id.uuidString) else { continue }
            // [2026-09-05] `maxSegmentLength: 35` — 위 `computeWordMatchScore`
            // 선언부 주석 참고. 개요 전용 확장 발췌.
            let wordScore = computeWordMatchScore(words: words, verseTerms: [], contentText: outline.contentText, maxSegmentLength: 35)
            guard refMatch || wordScore.isTextMatch else { continue }
            let result = OutlineSearchResult(
                kind: .book(outline), bodyExcerpt: wordScore.bodyExcerpt, bodyOccurrenceSum: wordScore.bodyOccurrenceSum,
                highlightKeywords: wordScore.highlightKeywords, isReferenceMatch: refMatch
            )
            results.append((result, wordScore.distinctTermMatchCount + (refMatch ? 1 : 0)))
        }
        for summary in chapterSummaries {
            let refMatch = queryMatches.contains { $0.bookId == summary.bookId && $0.chapter == summary.chapter }
            // [2026-09-05 추가] 위 책 개요 루프와 같은 이유.
            guard refMatch || chapterSummaryContentCandidates.contains(summary.id.uuidString) else { continue }
            // [2026-09-05] `maxSegmentLength: 35` — 위 `computeWordMatchScore`
            // 선언부 주석 참고. 개요 전용 확장 발췌.
            let wordScore = computeWordMatchScore(words: words, verseTerms: [], contentText: summary.contentText, maxSegmentLength: 35)
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
        // [2026-09-05 추가] 위 `contentCandidateSourceIds` 선언부 주석 참고.
        let phraseNoteContentCandidates = contentCandidateSourceIds(
            category: .phraseNote, words: words,
            liveContentById: Dictionary(uniqueKeysWithValues: notes.map { ($0.id.uuidString, $0.noteText) })
        )
        var results: [(result: PhraseNoteSearchResult, score: Int)] = []
        for note in notes {
            let refMatch = queryMatches.contains { query in
                query.bookId == note.bookId && query.chapter == note.chapter
                    && (query.verse == nil || query.verse == note.verse)
            }
            // [2026-09-05 추가] `searchOutlines`의 같은 자리와 같은 이유 —
            // 참조매치도 아니고 FTS 후보에도 없으면 전체 문자열 스캔을
            // 건너뛴다.
            guard refMatch || phraseNoteContentCandidates.contains(note.id.uuidString) else { continue }
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
        // [2026-09-05 추가] 위 `contentCandidateSourceIds` 선언부 주석 참고 —
        // `verseTerms`도 함께 후보를 좁히는 질의어에 포함해야 정확성이
        // 유지된다(`categoryWideVerseSearchTexts` 선언부 주석 참고).
        let memoContentCandidates = contentCandidateSourceIds(
            category: .memo, words: words,
            extraTerms: categoryWideVerseSearchTexts(mentions: mentions, sourceType: .memo, queryMatches: queryMatches),
            liveContentById: Dictionary(uniqueKeysWithValues: memos.map { ($0.id.uuidString, $0.contentText) })
        )
        var results: [(result: MemoSearchResult, score: Int)] = []
        for memo in memos {
            let tagNames = (memo.memoTags ?? []).compactMap { $0.tag?.name }
            let tagCount = words.filter { word in tagNames.contains { $0.localizedCaseInsensitiveContains(word) } }.count
            var seenTagNames = Set<String>()
            let matchedTagNames = tagNames.filter { name in
                words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
            }
            // [2026-09-05 추가] `searchOutlines`의 같은 자리와 같은 이유 —
            // 태그매치도 아니고 FTS 후보에도 없으면 전체 문자열 스캔을
            // 건너뛴다.
            guard tagCount > 0 || memoContentCandidates.contains(memo.id.uuidString) else { continue }
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
        // [2026-09-05 추가] `searchMemos`의 같은 자리와 같은 이유.
        let summaryContentCandidates = contentCandidateSourceIds(
            category: .wordSummary, words: words,
            extraTerms: categoryWideVerseSearchTexts(mentions: mentions, sourceType: .wordSummary, queryMatches: queryMatches),
            liveContentById: Dictionary(uniqueKeysWithValues: summaries.map { ($0.id.uuidString, $0.contentText) })
        )
        var results: [(result: SummarySearchResult, score: Int)] = []
        for summary in summaries {
            let tagNames = (summary.summaryTags ?? []).compactMap { $0.tag?.name }
            let tagCount = words.filter { word in tagNames.contains { $0.localizedCaseInsensitiveContains(word) } }.count
            var seenTagNames = Set<String>()
            let matchedTagNames = tagNames.filter { name in
                words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
            }
            // [2026-09-05 추가] `searchMemos`의 같은 자리와 같은 이유.
            guard tagCount > 0 || summaryContentCandidates.contains(summary.id.uuidString) else { continue }
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
        // [2026-09-05 추가] 사용자 요청 — "연구문서 combinedText 반복 재생성
        // 문제를 캐싱 필드로 해결(캐싱 필드 도입 OK)." 이 필드 도입 이전에
        // 이미 업로드된 문서는 `cachedCombinedText`가 기본값(빈 문자열)인 채로
        // 남아 있다 — 아래에서 그런 문서를 만나면(실제 `documentTexts`는
        // 있는데 캐시만 비어 있음) 그 자리에서 한 번만 다시 만들어 두고, 이
        // 함수가 끝날 때 한 번에 저장한다. 그래야 검색 정확성이 이 캐싱
        // 도입 전과 100% 동일하게 유지된다 — `documentTexts`가 실제로도
        // 비어 있는 문서(텍스트 추출 실패 등)는 캐시도 정당하게 비어 있는
        // 것이라 다시 만들 필요가 없다.
        //
        // [2026-09-05 이동] 이 백필을 아래 "FTS 후보 좁히기" 단계보다 먼저
        // 끝낸다 — 그 단계에 넘길 `liveContentById`가 최신 `cachedCombinedText`
        // 를 담고 있어야 하기 때문이다(로직 자체는 그대로, 실행 순서만
        // 앞으로 옮겼다).
        var needsBackfillSave = false
        for document in documents {
            if document.cachedCombinedText.isEmpty, !(document.documentTexts ?? []).isEmpty {
                document.rebuildCachedCombinedText()
                needsBackfillSave = true
            }
        }

        // [2026-09-05 추가] 위 `contentCandidateSourceIds` 선언부 주석 참고.
        let documentContentCandidates = contentCandidateSourceIds(
            category: .document, words: words,
            extraTerms: categoryWideVerseSearchTexts(mentions: mentions, sourceType: .document, queryMatches: queryMatches),
            liveContentById: Dictionary(uniqueKeysWithValues: documents.map { ($0.id.uuidString, $0.cachedCombinedText) })
        )

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

            // [2026-09-05 추가] `searchMemos`의 같은 자리와 같은 이유 — 태그/
            // 제목매치도 아니고 FTS 후보에도 없으면 전체 문자열 스캔을
            // 건너뛴다.
            guard tagCount > 0 || titleCount > 0 || documentContentCandidates.contains(document.id.uuidString) else { continue }
            let combinedText = document.cachedCombinedText
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
        if needsBackfillSave {
            try? modelContext.save()
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
    ///
    /// [2026-08-20 갱신, Phase 5] 사용자 리포트 — "'다윗의 아들들'을 검색하면
    /// 성경구절 섹션에 각 아들의 실제 절이 아니라 키워드 검색 가중치 계산값이
    /// 나오는 듯함." `intentCard`가 관계/인물·지명/예언/주제/서사 중 하나로
    /// 확정되고 그 카드에 실제 성경 좌표가 있으면(`QueryIntentCard.verseRefs`),
    /// 아래 근사 검색(임베딩+하이브리드 키워드 병합)을 아예 건너뛰고 그
    /// 좌표를 그대로 "성경구절" 섹션에 채운다 — 카드가 이미 정확한 답을
    /// 확정했는데 별도의 근사 검색으로 다른(때로는 무관한) 결과를 보여줄
    /// 이유가 없다는 판단. 카드가 없거나(`.general`) 좌표가 비어 있으면(아직
    /// 데이터가 없는 카테고리 등) 기존처럼 의미검색으로 넘어간다.
    private func performAIQuerySearch(query: String) async {
        errorDescription = nil
        // [2026-08-26 추가] AI(의미) 검색은 문장을 단어로 쪼개 검색하지 않으므로
        // (임베딩 기반 유사도) "더보기 확인창" 조건(`effectiveMatchedWordCount()`)의
        // 전제인 `lastSearchWords`가 이전 키워드 검색의 값으로 남아있으면 안
        // 된다 — 매번 명시적으로 비워, 이 함수가 채우는 결과에서는 확인창이
        // 절대 뜨지 않게 한다(위 `lastSearchWords` 선언부 주석 참고).
        lastSearchWords = []

        if let intentCard, !intentCard.verseRefs.isEmpty {
            setVerseResults(resolveVerseResults(intentCard.verseRefs))
            lastAIQueryUsed = nil
            memoResults = []; documentResults = []
            outlineResults = []; phraseNoteResults = []; summaryResults = []
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
    }

    /// [2026-08-20 신설, Phase 5] `QueryIntentCard.verseRefs`(관계/인물·지명
    /// 카드가 이미 확정한 성경 좌표)를 실제 절 본문과 함께 `VerseSearchResult`
    /// 로 바꾼다. `SearchViewModel.searchVerses`(키워드 검색)의 30개 상한과
    /// 같은 근거로 여기도 30개에서 자른다 — 관계가 많은 인물(예: 다윗의 아들
    /// 20여 명, 각자 여러 절)일 때 목록이 무한정 길어지지 않게.
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
