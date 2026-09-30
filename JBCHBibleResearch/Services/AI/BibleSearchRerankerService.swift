//
//  BibleSearchRerankerService.swift
//  JBCHBibleResearch
//
//  임베딩 검색이 뽑아온 상위 후보(실제 존재하는 절)를 원 질문에 비추어 다시 정렬하는
//  Apple Intelligence 재순위화 서비스. 모델에게 장절을 기억해 내게 하지 않고 확정된
//  후보 중 더 어울리는 순서만 판단하게 하므로 성경 지식이 얕아도 안전하다.
//
//  모델이 없거나, 실패하거나, 응답을 파싱할 수 없으면 원래 순서(코사인 유사도 순)를
//  그대로 돌려준다.
//
//  ⚠️ 현재 검색 파이프라인에서 호출되지 않는다(속도 대비 효과가 작아 재순위화 토글과
//  호출부를 제거함). 참고용으로만 남겨 두었으며, 항상 쓰이는 리랭커는 결정론적인
//  `BibleStructuralRerankerService`다.
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

    /// `matches`를 `query`에 비추어 다시 정렬한다. 실패/미지원이면 입력 순서를 그대로
    /// 돌려주며, throw하지 않고 새 절을 만들지도 않는다(순서만 바꿈).
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
            // 모델이 언급하지 않은 나머지는 원래(코사인 유사도) 순서로 뒤에 이어붙인다.
            // 결과 개수를 줄이는 결정까지는 이 단계에 맡기지 않는다.
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
