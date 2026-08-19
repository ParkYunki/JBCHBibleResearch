//
//  BibleSemanticSearchService.swift
//  JBCHBibleResearch
//
//  [2026-08-19 신설, 이후 임베딩 모델 교체] 사용자 요청 — "애플 인텔리전스로
//  텍스트를 정제하고, 방식 A — 임베딩 기반 의미검색을 한다면?" 파이프라인
//  전체를 여기서 이어붙인다:
//  1) `BibleQueryRefinementService`로 자유 문장을 다듬는다(실패해도 원문으로
//     계속 진행 — 그 파일 상단 주석 참고).
//  2) `EmbeddingService.embedQuery(_:)`(multilingual-e5-small, Core ML)로
//     벡터화한다 — 색인 쪽(`EmbeddingIndexingService`)은 같은 모델을
//     `embedPassage(_:)`로 쓴다(E5 비대칭 검색 규약, `EmbeddingService.swift`
//     상단 주석 참고).
//  3) `EmbeddingIndexingService`가 미리 만들어 둔 개역한글 31,102절 인덱스와
//     코사인 유사도를 brute-force로 비교해 상위 K개를 고른다.
//  4) 상위 K개의 실제 절 본문을 `BibleReferenceStore`로 조회해 돌려준다.
//
//  이 서비스가 요구하는 건 `EmbeddingService`(Core ML 모델 + 토크나이저 리소스가
//  Xcode 프로젝트에 추가돼 있어야 함)뿐이다 — `BibleQueryRefinementService`
//  (FoundationModels/Apple Intelligence)는 없어도 동작한다. 즉 "AI 검색" 토글의
//  실제 가용성 기준은 Apple Intelligence 기기 자격이 아니라
//  `EmbeddingService.checkAvailability()`다(`SearchView.aiToggleButton` 참고).
//

import Foundation
import BibleResearchModels

struct SemanticVerseMatch {
    let bookId: Int
    let chapter: Int
    let verse: Int
    let content: String
    /// 코사인 유사도(-1~1, 보통 0~1). UI가 "유사도 xx%" 배지로 보여준다
    /// (`SearchView`/`SearchViewModel.VerseSearchResult.similarityScore`).
    let similarity: Float
}

/// [2026-08-19 신설] 사용자 요청 — "애플인텔리전스를 끈것과 켠것을 비교하고
/// 싶음." 결과 목록뿐 아니라 "실제로 임베딩에 넘긴 문장"까지 같이 돌려준다 —
/// 정제를 켰을 때와 껐을 때 검색어 자체가 어떻게 달라지는지 화면에 보여줘야
/// 비교가 의미 있기 때문이다(`SearchView`의 "검색에 사용된 문장" 안내 참고).
struct SemanticSearchOutcome {
    let matches: [SemanticVerseMatch]
    let queryUsedForEmbedding: String
}

@MainActor
enum BibleSemanticSearchService {
    enum SearchError: Error, CustomStringConvertible {
        case indexNotReady
        case embeddingUnavailable(String)
        case sourceUnavailable(String)
        case noResults

        var description: String {
            switch self {
            case .indexNotReady:
                return "먼저 성경 전체 색인을 만들어야 AI 검색을 쓸 수 있습니다."
            case .embeddingUnavailable(let reason):
                return reason
            case .sourceUnavailable(let message):
                return message
            case .noResults:
                return "비슷한 뜻을 가진 구절을 찾지 못했습니다."
            }
        }
    }

    /// 사용자 요청 — "결과를 5개 -> 10개로 늘릴 것"(이전 장절 변환 방식에 적용됐던
    /// 상한을 이 새 파이프라인에도 그대로 유지). 리랭커(③단계)가 순서를 다듬은
    /// 뒤 최종적으로 사용자에게 보여줄 개수다 — 후보 생성 단계의 개수와는 다르다
    /// (`candidatePoolSize` 참고).
    static let maxResults = 10

    /// [2026-08-19 v3] 사용자 지시 — "① centering 제거 → ② Top 50까지 후보
    /// 확대 → ③ reranker → ④ verse/context weight 최적화 순서로 할것." 후보
    /// 생성 단계에서는 더 이상 절대 유사도 문턱값(v2의 `minimumSimilarity`,
    /// 이제 제거)으로 거르지 않는다 — multilingual-e5-small의 이방성 때문에
    /// 절대값 자체를 신뢰하기 어렵다는 게 실사용으로 두 차례 확인됐다("지혜가
    /// 부족하면..." 사례). 대신 순위 기준(top-K)으로 넉넉히 후보를 뽑아
    /// 임베딩 랭킹이 놓칠 수 있는 정답까지 리랭커 앞까지 살려두고, 실제
    /// 관련성 판단은 ③ 리랭커(`BibleSearchRerankerService`)에게 맡긴다.
    static let candidatePoolSize = 50

    /// [2026-08-19 추가] `refinementEnabled` — 사용자 요청 "애플인텔리전스를
    /// 끈것과 켠것을 비교하고 싶음." 기기 시스템 설정을 건드리지 않고 앱 안에서
    /// 바로 A/B 비교할 수 있도록, 1단계(질의 정제)를 건너뛸 수 있는 스위치를
    /// 뒀다 — 꺼져 있으면 `BibleQueryRefinementService`를 아예 호출하지 않고
    /// 사용자가 입력한 원문 그대로 임베딩한다(`SearchViewModel.
    /// isQueryRefinementEnabled`/`SearchView`의 정제 토글 참고).
    /// [2026-08-19 추가] `rerankEnabled` — "Reranker도 고민해볼것" 요청으로
    /// 추가한 마지막 단계 스위치. `refinementEnabled`(검색어 정제)와 독립적으로
    /// 켜고 끌 수 있다 — 두 AI 단계 각각이 결과에 도움이 되는지 따로 비교할
    /// 수 있어야 하기 때문이다(`BibleSearchRerankerService.swift` 상단 주석
    /// 참고).
    /// [2026-08-19 v3 추가] `contextWeight` — "0.4:0.6으로 고정... 이것도
    /// 상당히 임의적인 값입니다... 0.2/0.8 ... 0.8/0.2 이렇게만 해도 검색
    /// 결과가 상당히 달라질 수 있습니다." 고정 상수 대신 호출자가 넘기는
    /// 값으로 바꿔, `SearchView`의 슬라이더로 재빌드 없이 직접 스윕
    /// 테스트할 수 있게 했다(`SearchViewModel.contextWeight` 참고). 절
    /// 가중치는 `1 - contextWeight`로 자동 계산된다.
    static func search(
        query: String, refinementEnabled: Bool = true, rerankEnabled: Bool = true, contextWeight: Float = 0.6
    ) async -> Result<SemanticSearchOutcome, SearchError> {
        guard case .ready = EmbeddingIndexingService.shared.status else {
            return .failure(.indexNotReady)
        }

        // [2026-08-19 추가] "지혜가 부족하면 하나님께 구하라는 말씀" 실사용 사례로
        // 확인된 문제 — "~라는 말씀"/"~하는 구절" 꼬리표가 그대로 임베딩에
        // 들어가면 "말씀"이라는 흔한 단어 하나가 유사도 순위를 지배해버린다
        // (정작 정답 절 대신 "말씀"만 공유하는 무관한 절들이 상위를 차지함).
        // 이 정규화는 AI 정제 on/off와 무관하게 항상 적용한다 —
        // `BibleQueryRefinementService.stripTrailingMetaPhrase` 상단 주석 참고.
        let normalizedQuery = BibleQueryRefinementService.stripTrailingMetaPhrase(query)
        let refinedQuery = refinementEnabled ? await BibleQueryRefinementService.refine(query: normalizedQuery) : normalizedQuery

        let queryVector: [Float]
        do {
            queryVector = try await EmbeddingService.embedQuery(refinedQuery)
        } catch let error as EmbeddingService.EmbeddingError {
            return .failure(.embeddingUnavailable(error.description))
        } catch {
            return .failure(.embeddingUnavailable("검색어를 벡터로 변환하지 못했습니다."))
        }

        let loadedIndex: EmbeddingIndexingService.LoadedIndex
        do {
            loadedIndex = try EmbeddingIndexingService.shared.ensureLoaded()
        } catch let error as EmbeddingIndexingService.IndexError {
            return .failure(.sourceUnavailable(error.description))
        } catch {
            return .failure(.sourceUnavailable("색인을 읽지 못했습니다."))
        }
        guard !loadedIndex.records.isEmpty else { return .failure(.noResults) }

        // [2026-08-19 v3, ① centering 제거] 코퍼스 평균 벡터를 빼는 중심화
        // 단계를 없애고 원본 벡터로 바로 비교한다 — 사용자 지시("① centering
        // 제거")에 따름. `EmbeddingIndexingService`는 평균 벡터를 계속
        // 계산/저장한다(재색인 비용이 커서 포맷을 다시 바꾸지 않으려는
        // 목적 — 나중에 다시 켜볼 수 있도록 남겨둔 것이지, 지금 이 검색
        // 로직이 실제로 쓰는 건 아니다).
        let verseWeight = 1 - contextWeight
        let scored = loadedIndex.records
            .map { record -> (record: EmbeddingIndexingService.Record, similarity: Float) in
                let verseSim = EmbeddingService.cosineSimilarity(queryVector, record.vector)
                let contextSim = EmbeddingService.cosineSimilarity(queryVector, record.contextVector)
                let combined = verseSim * verseWeight + contextSim * contextWeight
                return (record, combined)
            }
            .sorted { $0.similarity > $1.similarity }
            .prefix(candidatePoolSize) // [② Top 50까지 후보 확대]

        guard !scored.isEmpty else { return .failure(.noResults) }

        guard let store = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedBundledDatabaseURL().path) else {
            return .failure(.sourceUnavailable("성경 본문 파일을 열지 못했습니다."))
        }

        var candidates: [SemanticVerseMatch] = []
        for item in scored {
            guard let verse = try? store.verse(
                bookId: Int(item.record.bookId), chapter: Int(item.record.chapter), verse: Int(item.record.verse)
            ) else { continue }
            candidates.append(SemanticVerseMatch(
                bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse,
                content: verse.content, similarity: item.similarity
            ))
        }
        guard !candidates.isEmpty else { return .failure(.noResults) }

        // [③ reranker] 최대 50개 후보 전체를 리랭커에 넘긴다 — 임베딩 랭킹
        // 1~10위 안에 없던 정답이 11~50위 사이에 있었다면 여기서 앞으로
        // 끌어올려질 수 있다. 리랭커가 꺼져 있으면(또는 실패하면) 후보
        // 순서(코사인 유사도 순) 그대로 유지한다.
        let reordered = rerankEnabled
            ? await BibleSearchRerankerService.rerank(query: refinedQuery, matches: candidates)
            : candidates
        // 최종 사용자 노출은 여전히 상위 10개로 자른다.
        let finalMatches = Array(reordered.prefix(maxResults))
        return .success(SemanticSearchOutcome(matches: finalMatches, queryUsedForEmbedding: refinedQuery))
    }
}
