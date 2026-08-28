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
    /// 코사인 유사도(-1~1, 보통 0~1) — 후보 정렬/`BibleStructuralRerankerService.
    /// rerank`의 순위 산정에만 쓰는 내부 값이다. [2026-08-20 제거, Phase 5]
    /// 예전엔 UI가 이 값을 "유사도 xx%" 배지로 그대로 보여줬는데(`SearchViewModel.
    /// VerseSearchResult.similarityScore`가 있었음), 사용자 재검토로 뺐다 —
    /// `rerank`가 정렬은 이 값+가산치 합계로 다시 하면서 정작 이 필드 자체는
    /// 갱신하지 않아서, 화면에 최종적으로 보이는 순서와 배지에 찍히는 %가
    /// 서로 어긋날 수 있었다(`SearchView.rowLabel` 주석에 상세 근거). 지금은
    /// 내부 정렬 용도로만 쓰이고 UI엔 노출되지 않는다.
    let similarity: Float
}

/// [2026-08-19 신설] 관주(Cross Reference) 후보 확장 단계의 중복 제거용 키.
/// `BibleStructuralRerankerService.VerseKey`와 같은 목적의 타입을 이 파일
/// 안에서도 필요로 해서(서로 다른 파일이라 재사용 대신 각자 정의 — 둘 다
/// 아주 작은 값 타입이라 공용 타입으로 뽑는 비용이 더 크다고 판단, 이
/// 프로젝트의 "세 번째 사용처가 생기기 전엔 공통 헬퍼로 추출하지 않는다"
/// 원칙과 같은 논리) 별도로 둔다.
private struct VerseCoordinate: Hashable {
    let bookId: Int
    let chapter: Int
    let verse: Int
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

    /// [2026-08-19 추가, 2026-08-20 Apple Intelligence 정제 제거] `contextWeight` —
    /// "0.4:0.6으로 고정... 이것도 상당히 임의적인 값입니다... 0.2/0.8 ...
    /// 0.8/0.2 이렇게만 해도 검색 결과가 상당히 달라질 수 있습니다." 고정
    /// 상수 대신 호출자가 넘기는 값으로 바꿔, `SearchView`의 슬라이더로
    /// 재빌드 없이 직접 스윕 테스트할 수 있게 했다(`SearchViewModel.
    /// contextWeight` 참고). 절 가중치는 `1 - contextWeight`로 자동 계산된다.
    ///
    /// [2026-08-20 제거] 한때 `refinementEnabled`/`rerankEnabled` 두 매개변수로
    /// Apple Intelligence 질의 정제/재순위화를 켜고 끌 수 있었으나, 사용자가
    /// "결과가 너무 이상함"(정제)/"너무 느리고 결과가 큰 차이 안 남"(재순위화)
    /// 이라는 이유로 두 기능 자체를 제거해 달라고 요청했다 — 이제 이 함수는
    /// `BibleQueryRefinementService.refine`(Apple Intelligence 재작성)와
    /// `BibleSearchRerankerService`(Apple Intelligence 재순위화)를 아예 호출하지
    /// 않는다. 다만 Apple Intelligence가 "아닌" 두 단계(`stripTrailingMetaPhrase`
    /// — 결정론적 꼬리표 제거, `BibleStructuralRerankerService` — 결정론적
    /// 규칙 기반 재순위화)는 그대로 항상 적용된다.
    static func search(
        query: String, contextWeight: Float = 0.6
    ) async -> Result<SemanticSearchOutcome, SearchError> {
        guard case .ready = EmbeddingIndexingService.shared.status else {
            return .failure(.indexNotReady)
        }

        // [2026-08-19 추가] "지혜가 부족하면 하나님께 구하라는 말씀" 실사용 사례로
        // 확인된 문제 — "~라는 말씀"/"~하는 구절" 꼬리표가 그대로 임베딩에
        // 들어가면 "말씀"이라는 흔한 단어 하나가 유사도 순위를 지배해버린다
        // (정작 정답 절 대신 "말씀"만 공유하는 무관한 절들이 상위를 차지함).
        // 이 정규화는 결정론적(Apple Intelligence 아님)이라 항상 적용한다 —
        // `BibleQueryRefinementService.stripTrailingMetaPhrase` 상단 주석 참고.
        // [2026-08-20 제거] 이 뒤에 있던 `BibleQueryRefinementService.refine`
        // (Apple Intelligence 재작성) 호출은 제거했다 — 위 함수 주석 참고.
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

        // [2026-08-20 신설, 하이브리드 검색] 사용자 보고 — "AI 검색이 키워드
        // 검색보다 결과가 못함"(예: "골리앗의 아우"). 실측으로 확인한 사실:
        // 정답 절(삼하 21:19, 대상 20:5)엔 "골리앗의 아우 라흐미"라는 문구가
        // 리터럴로 들어있는데, AI 검색은 임베딩 top-50 회수에 전적으로
        // 의존하는 별개 파이프라인이라(이 파일 상단 주석) 짧고 관계어 위주인
        // 문장을 임베딩이 잘 못 담아내면 정답이 후보 풀에 아예 없을 수 있다.
        // 리터럴 일치는 검색 방식과 무관하게 최소한으로 보장돼야 한다는
        // 원칙으로 키워드 검색 후보를 병합한다.
        //
        // [2026-08-20 v2 재작성] 최초 구현(단어별 독립 LIKE 후보를 전부
        // 병합)은 사용자 지적으로 버그가 드러났다 — "골리앗의 동생을
        // 검색하는데 왜 신약이 나오는지 모르겠음." 원인: "동생"처럼 흔한
        // 단어 하나만 일치해도 병합했더니, "골리앗"과 무관한 "동생"
        // 단독 일치 절(신약 포함 전체 성경)까지 전부 top 유사도로 끼어들어
        // 갔다. 이제는 사용자가 명시한 채점 규칙(`KeywordMatchScorer` —
        // "단어가 모두 일치해야 최고점, 일부만 일치하면 그보다 낮은 점수")을
        // 그대로 적용해 **모든 단어가(동의어 포함) 일치하는 후보만** 하이브리드
        // 병합 대상으로 삼는다 — "골리앗의"와 "동생"(동의어 "아우") 둘 다
        // 있어야 하므로, "동생"만 있고 "골리앗"이 없는 신약 구절은 이제
        // 병합되지 않는다. 동의어 처리(`RelationSynonyms` — 아우/동생,
        // 아내/처/부인 등)도 사용자 요청대로 반영했다.
        //
        // [2026-08-20 신설, FTS5 전환] 후보 회수 자체도 LIKE 대신 `ReferenceDataStore.
        // searchVersesFullText`(FTS5 unicode61, prefix 검색만 — "앞뒤 라이크
        // 대신 뒤 라이크만" 사용자 지시)를 쓴다. 이 인덱스는 개역한글 31,102절
        // 전체를 담고 있어 이 서비스가 다루는 번역본(번들 기본, 개역한글)과
        // 정확히 일치한다.
        //
        // [2026-08-25 변경] 이전엔 `limit: 50`을 넘겼는데, `searchVersesFullText`가
        // bm25 관련도 순 상위 50개만 돌려주던 시절엔 흔한 단어(예: "동생")가
        // 진짜 정답 절을 top-50 밖으로 밀어내 `allWordsMatched` 필터에서
        // 걸러지기도 전에 후보 풀에서 통째로 빠지는 경우가 있었다 — 이 코드
        // 블록이 원래 고치려던 문제("정답이 후보 풀에 아예 없을 수 있다",
        // 위 주석)와 원인만 다를 뿐 증상이 똑같다. `searchVersesFullText`가
        // 이제 (bm25가 아니라) 성경순으로 정렬하고 `limit`도 옵셔널이 됐으므로,
        // 인자를 아예 넘기지 않아(기본값 `nil` = 무제한) 후보 풀 자체를
        // 완전하게 만든다 — 어차피 최종 선택은 `hybridKeywordBudget`(20)이
        // 그대로 제한한다.
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
            // Dictionary는 순서가 없어 그냥 prefix(budget)를 뽑으면 임의의
            // 20개가 선택된다 — 동의어를 포함한 등장 횟수(`totalOccurrences`)
            // 내림차순으로 정렬해, budget을 넘는 경우에도 더 강하게 일치하는
            // 후보가 우선 포함되게 한다.
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

        // [2026-08-19 신설, Layer 3 연결] 사용자 요청 — "관주 데이터,
        // 지금은 성경 읽기 화면에서만 쓰이는데 검색 파이프라인에도 연결할
        // 것(저작권 문제없음 확인)." E5 상위 10개(전체 50개가 아니라
        // 상위권만 — 관주 조회는 SQLite 왕복이 후보 수만큼 늘어나므로
        // 비용을 상위권으로 제한)의 관주 대상 중, 아직 후보 목록에 없는
        // 절을 추가로 끌어온다. 신규 유사도는 원래 E5 유사도를 매기지
        // 않고(관주로 끌려온 절은 임베딩 유사도가 별도로 없음) 그 절을
        // 끌어온 원본 후보의 유사도에서 소폭 낮춘 값을 부여해, 순수
        // 임베딩 상위권을 밀어내지 않으면서도 리랭커(③ 단계)가 검토할
        // 후보 풀에는 포함되도록 한다 — 예시 ②(예수=메시아 예언 성취)처럼
        // 구약 예언 절이 신약 성취 절과 임베딩 유사도만으로는 잘 안
        // 엮이는 경우, 관주가 그 다리를 놓아준다.
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

        // [③ reranker, 2026-08-20 Apple Intelligence 경로 제거] 최대 70여개
        // 후보 전체를 구조적 리랭커에 넘긴다 — 임베딩 랭킹 1~10위 안에 없던
        // 정답이 그 뒤에 있었다면 여기서 앞으로 끌어올려질 수 있다. 예전엔
        // Apple Intelligence(`BibleSearchRerankerService`)를 먼저 시도하고
        // 실패/미지원일 때만 이 구조적 리랭커로 전환했지만, 사용자가 "너무
        // 느리고 결과가 큰 차이 안 남"이라며 Apple Intelligence 재순위화 자체를
        // 없애 달라고 요청해 이제 `BibleStructuralRerankerService`(인물/지명/
        // 관계/관주 연결 기반, LLM 아님 — 항상 동작하고 빠르다)만 항상 쓴다.
        let reordered = await BibleStructuralRerankerService.rerank(query: refinedQuery, matches: candidates)
        // 최종 사용자 노출은 여전히 상위 10개로 자른다.
        let finalMatches = Array(reordered.prefix(maxResults))
        return .success(SemanticSearchOutcome(matches: finalMatches, queryUsedForEmbedding: refinedQuery))
    }
}
