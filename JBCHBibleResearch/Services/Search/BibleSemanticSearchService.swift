//
//  BibleSemanticSearchService.swift
//  JBCHBibleResearch
//
//  AI(의미) 검색 파이프라인:
//  1) `BibleQueryRefinementService.stripTrailingMetaPhrase`로 질의 꼬리표를 결정론적으로 정리한다.
//  2) `EmbeddingService.embedQuery(_:)`(multilingual-e5-small, Core ML)로 벡터화한다 — 색인 쪽
//     (`EmbeddingIndexingService`)은 같은 모델을 `embedPassage(_:)`로 쓴다(E5 비대칭 검색 규약).
//  3) `EmbeddingIndexingService`의 개역한글 31,102절 인덱스와 코사인 유사도를 brute-force로
//     비교해 상위 K개를 고른다.
//  4) 키워드/관주 후보를 더하고 `BibleStructuralRerankerService`로 재정렬해 절 본문과 함께 돌려준다.
//
//  요구 조건은 `EmbeddingService`(Core ML 모델 + 토크나이저 리소스)뿐이라, "AI 검색" 토글의
//  가용성 기준은 `EmbeddingService.checkAvailability()`다(`SearchView.aiToggleButton` 참고).
//

import Foundation
import BibleResearchModels

struct SemanticVerseMatch {
    let bookId: Int
    let chapter: Int
    let verse: Int
    let content: String
    /// 코사인 유사도(-1~1, 보통 0~1) — 후보 정렬과 `BibleStructuralRerankerService.rerank`의 순위
    /// 산정에만 쓰는 내부 값이다. rerank가 이 필드를 갱신하지 않아 최종 순서와 어긋날 수 있으므로
    /// UI에는 노출하지 않는다.
    let similarity: Float
}

/// 관주 후보 확장 단계의 중복 제거용 키. `BibleStructuralRerankerService.VerseKey`와 같은
/// 목적이지만 아주 작은 값 타입이라 공용으로 뽑지 않고 파일별로 따로 정의한다.
private struct VerseCoordinate: Hashable {
    let bookId: Int
    let chapter: Int
    let verse: Int
}

/// 검색 결과와 함께 실제로 임베딩에 넘긴 문장을 돌려준다(화면의 "검색에 사용된 문장" 안내용,
/// `SearchView` 참고).
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

    /// 리랭커가 순서를 다듬은 뒤 사용자에게 보여줄 최종 개수. 후보 생성 개수와 다르다
    /// (`candidatePoolSize` 참고).
    static let maxResults = 10

    /// 임베딩 후보 풀 크기. 절대 유사도 문턱값으로 거르지 않고 순위(top-K)로 넉넉히 뽑는다 —
    /// multilingual-e5-small의 이방성 때문에 절대값을 신뢰하기 어렵고, 실제 관련성 판단은
    /// 뒤의 재순위화 단계에 맡긴다.
    static let candidatePoolSize = 50

    /// `contextWeight`: 문맥 유사도의 가중치(절 본문 가중치는 `1 - contextWeight`). `SearchView`
    /// 슬라이더로 재빌드 없이 조정할 수 있도록 호출자가 넘긴다(`SearchViewModel.contextWeight` 참고).
    /// Apple Intelligence 질의 정제/재순위화는 쓰지 않고, 결정론적 꼬리표 제거
    /// (`stripTrailingMetaPhrase`)와 규칙 기반 `BibleStructuralRerankerService`만 항상 적용한다.
    static func search(
        query: String, contextWeight: Float = 0.6
    ) async -> Result<SemanticSearchOutcome, SearchError> {
        guard case .ready = EmbeddingIndexingService.shared.status else {
            return .failure(.indexNotReady)
        }

        // "~라는 말씀"/"~하는 구절" 꼬리표가 임베딩에 들어가면 "말씀" 같은 흔한 단어가 유사도
        // 순위를 지배해 무관한 절이 상위를 차지한다. 결정론적 정규화라 항상 적용한다
        // (`BibleQueryRefinementService.stripTrailingMetaPhrase` 참고).
        let normalizedQuery = BibleQueryRefinementService.stripTrailingMetaPhrase(query)
        let refinedQuery = normalizedQuery

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

        // 코퍼스 평균 벡터 중심화 없이 원본 벡터로 비교한다. `EmbeddingIndexingService`는 평균
        // 벡터를 계속 저장하지만(재색인 비용 때문에 포맷 유지) 이 검색 로직은 쓰지 않는다.
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

        // 하이브리드: 임베딩 top-50 회수에만 의존하면 짧고 관계어 위주인 질의(예: "골리앗의 아우")에서
        // 리터럴로 일치하는 정답 절이 후보 풀에서 빠질 수 있어 키워드 일치 후보를 병합한다.
        // 단어 하나만 일치해도 병합하면 흔한 단어("동생")만 공유하는 무관한 절이 끼어들므로,
        // `KeywordMatchScorer`로 동의어(`RelationSynonyms`) 포함 모든 단어가 일치하는 후보만 병합한다.
        // 후보 회수는 `ReferenceDataStore.searchVersesFullText`(FTS5 unicode61, 뒤쪽 prefix 검색만)를
        // 쓴다. 이 인덱스는 개역한글 31,102절 전체라 이 서비스가 다루는 번역본과 일치한다.
        // `limit`을 넘기지 않아(nil = 무제한, 성경순) 흔한 단어가 정답을 후보 풀 밖으로 밀어내지
        // 않게 하고, 최종 개수는 `hybridKeywordBudget`이 제한한다.
        let hybridKeywordBudget = 20
        let hybridSimilarity = candidates.first?.similarity ?? 1.0
        var hybridSeen = Set(candidates.map { VerseCoordinate(bookId: $0.bookId, chapter: $0.chapter, verse: $0.verse) })
        let keywordWords = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        if !keywordWords.isEmpty, let fullTextStore = ReferenceDataProvider.shared.store {
            var hybridPool: [VerseCoordinate: String] = [:]  // 좌표 -> 본문(중복 조회 방지)
            for word in keywordWords {
                for variant in RelationSynonyms.expanded(word) {
                    guard let matches = try? fullTextStore.searchVersesFullText(matching: variant) else { continue }
                    for match in matches {
                        let key = VerseCoordinate(bookId: match.bookId, chapter: match.chapter, verse: match.verse)
                        guard !hybridSeen.contains(key), hybridPool[key] == nil else { continue }
                        hybridPool[key] = match.content
                    }
                }
            }
            // Dictionary는 순서가 없어 prefix(budget)가 임의의 후보를 고르게 되므로, 동의어 포함
            // 등장 횟수 내림차순으로 정렬해 더 강하게 일치하는 후보를 우선한다.
            let allMatchedCandidates = hybridPool
                .compactMap { key, content -> (key: VerseCoordinate, content: String, score: KeywordMatchScorer.Score)? in
                    let score = KeywordMatchScorer.score(words: keywordWords, in: content)
                    guard score.allWordsMatched else { return nil }
                    return (key, content, score)
                }
                .sorted { $0.score.totalOccurrences > $1.score.totalOccurrences }
                .prefix(hybridKeywordBudget)
            for candidate in allMatchedCandidates {
                guard hybridSeen.insert(candidate.key).inserted else { continue }
                candidates.append(SemanticVerseMatch(
                    bookId: candidate.key.bookId, chapter: candidate.key.chapter, verse: candidate.key.verse,
                    content: candidate.content, similarity: hybridSimilarity
                ))
            }
        }
        candidates.sort { $0.similarity > $1.similarity }

        // 관주 연결: E5 상위 10개(관주 조회는 SQLite 왕복이라 상위권으로 제한)의 관주 대상 중
        // 후보에 없는 절을 추가한다. 관주로 끌려온 절은 원본 후보 유사도에서 소폭(0.05) 낮춘 값을
        // 부여해, 임베딩 상위권을 밀어내지 않으면서 리랭커 후보 풀에는 들게 한다 — 구약 예언 절과
        // 신약 성취 절처럼 임베딩만으로는 잘 안 엮이는 경우를 잇는다.
        if let refStore = ReferenceDataProvider.shared.store {
            var seen = Set(candidates.map { VerseCoordinate(bookId: $0.bookId, chapter: $0.chapter, verse: $0.verse) })
            let originalCount = candidates.count
            let expansionBudget = 20  // 무한정 늘어나지 않도록 상한
            let sourceCandidates = Array(candidates.prefix(10))
            outer: for source in sourceCandidates {
                guard let targets = try? refStore.crossReferenceTargets(
                    bookId: source.bookId, chapter: source.chapter, verse: source.verse
                ) else { continue }
                for target in targets {
                    let key = VerseCoordinate(bookId: target.bookId, chapter: target.chapter, verse: target.verse)
                    guard !seen.contains(key) else { continue }
                    guard let verse = try? store.verse(bookId: target.bookId, chapter: target.chapter, verse: target.verse) else { continue }
                    seen.insert(key)
                    candidates.append(SemanticVerseMatch(
                        bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse,
                        content: verse.content, similarity: source.similarity - 0.05
                    ))
                    if candidates.count >= originalCount + expansionBudget { break outer }
                }
            }
        }

        // 최대 70여개 후보 전체를 구조적 리랭커(`BibleStructuralRerankerService` — 인물/지명/관계/
        // 관주 연결 기반, LLM 아님)에 넘긴다. 임베딩 1~10위 밖의 정답도 여기서 앞으로 올라올 수 있다.
        let reordered = await BibleStructuralRerankerService.rerank(query: refinedQuery, matches: candidates)
        // 최종 사용자 노출은 여전히 상위 10개로 자른다.
        let finalMatches = Array(reordered.prefix(maxResults))
        return .success(SemanticSearchOutcome(matches: finalMatches, queryUsedForEmbedding: refinedQuery))
    }
}
