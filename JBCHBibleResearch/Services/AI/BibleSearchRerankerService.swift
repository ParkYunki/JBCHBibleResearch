//
//  BibleSearchRerankerService.swift
//  JBCHBibleResearch
//
//  [2026-08-19 신설] 사용자 요청 — "Reranker도 고민해볼것." 임베딩 검색이 이미
//  뽑아온 상위 후보(실제로 존재하는 성경 절, 지어낸 것 아님)를 원 질문에
//  비추어 다시 순서를 매기는 마지막 단계. `BibleQueryRefinementService`와
//  똑같은 이유로 안전하다 — "이 절이 몇 장 몇 절인지"를 모델의 기억에서
//  끄집어내는 게 아니라, 이미 확정된 후보 목록 중 어느 게 더 어울리는지
//  "비교/판단"만 시키기 때문에 성경 지식을 몰라도 상대적으로 잘 해낼 수 있는
//  작업이다(`BibleSemanticSearchService.swift` 상단 주석 참고).
//
//  ⚠️ [실패해도 검색을 막지 않음] `BibleQueryRefinementService.refine`과 같은
//  원칙 — 모델이 없거나(Apple Intelligence 미지원 기기), 실패하거나, 응답을
//  파싱할 수 없으면 원래 순서(코사인 유사도 순)를 그대로 돌려준다.
//
//  ⚠️ [정제 토글과 독립적인 별도 스위치] "애플인텔리전스를 끈것과 켠것을
//  비교하고 싶음" 요청으로 만든 `isQueryRefinementEnabled` 토글과 이 리랭커를
//  같은 스위치에 묶지 않았다 — 묶으면 "정제가 도움이 되는지"와 "재순위화가
//  도움이 되는지"를 따로 비교할 수 없게 된다(`SearchViewModel.isRerankEnabled`
//  참고).
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum BibleSearchRerankerService {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
            return false
        } else {
            return false
        }
        #else
        return false
        #endif
    }

    /// `matches`(이미 임베딩 검색으로 확정된 실제 절 목록)를 `query`에 비추어
    /// 다시 정렬한다. 실패/미지원이면 입력 순서를 그대로 돌려준다 — 절대
    /// throw하지 않고, 새로운 절을 추가하거나 만들어내지 않는다(순서만 바꿈).
    static func rerank(query: String, matches: [SemanticVerseMatch]) async -> [SemanticVerseMatch] {
        guard matches.count > 1 else { return matches }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return matches }
        guard case .available = SystemLanguageModel.default.availability else { return matches }

        let numbered = matches.enumerated()
            .map { index, match in "\(index + 1). \(match.content)" }
            .joined(separator: "\n")

        let prompt = """
        아래는 "\(query)"라는 질문/주제와 관련 있을 것으로 추정되는 성경 구절
        후보 목록입니다. 이 중 실제로 질문/주제에 가장 잘 들어맞는 순서대로
        번호만 나열하세요. 관련 없다고 판단되는 번호는 빼도 됩니다. 목록에
        없는 번호나 새 구절을 지어내지 마세요. 번호를 쉼표로 구분해 한 줄로만
        출력하고 다른 설명은 붙이지 마세요.

        후보:
        \(numbered)

        출력(예: 3,1,5):
        """

        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let orderedIndices: [Int] = text
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .compactMap { number in
                    let index = number - 1
                    return (0..<matches.count).contains(index) ? index : nil
                }
            guard !orderedIndices.isEmpty else { return matches }

            var seen = Set<Int>()
            var reordered: [SemanticVerseMatch] = []
            for index in orderedIndices where !seen.contains(index) {
                seen.insert(index)
                reordered.append(matches[index])
            }
            // 모델이 언급하지 않은 나머지는 "관련 없다고 뺐다"고 단정하지 않고,
            // 원래(코사인 유사도) 순서 그대로 뒤에 이어붙인다 — 결과 개수를
            // 줄이는 결정까지는 이 단계에 맡기지 않는다.
            for (index, match) in matches.enumerated() where !seen.contains(index) {
                reordered.append(match)
            }
            return reordered
        } catch {
            print("[BibleSearchRerankerService] 재순위화 실패(원래 순서 유지): \(error)")
            return matches
        }
        #else
        return matches
        #endif
    }
}
