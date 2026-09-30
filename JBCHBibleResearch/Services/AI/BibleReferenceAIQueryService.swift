//
//  BibleReferenceAIQueryService.swift
//  JBCHBibleResearch
//
//  자유 문장을 검색에 유리한 평서문으로 다듬는 `BibleQueryRefinementService`를 제공한다.
//  정답 장절을 맞히는 일은 하지 않는다 — 온디바이스 모델(FoundationModels)은 성경 지식이
//  얕아 장절 직접 변환이 불안정했기 때문이다. 장절 검색은 `EmbeddingService`+
//  `EmbeddingIndexingService`의 코사인 유사도 검색이 맡고(실제 본문 임베딩과 비교하므로
//  없는 절을 지어낼 수 없음), 이 서비스는 그 앞단에서 질문형 껍데기만 걷어낸다.
//
//  정제는 필수 단계가 아니다. 실패하거나 Apple Intelligence를 쓸 수 없어도 원문 그대로
//  임베딩 검색을 이어가므로 `refine(query:)`는 항상 String을 돌려준다(Result/throws 아님).
//  FoundationModels 사용 패턴은 `ChapterOutlineDraftService.swift`와 같다.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum BibleQueryRefinementService {
    /// 문장 끝의 메타 꼬리표 목록. "~라는 말씀"처럼 "구절을 찾는다"는 메타 표현은 검색 대상이
    /// 아닌데, 짧은 문장에서 임베딩이 "말씀" 같은 흔한 단어에 지배되어 무관한 절이 상위를
    /// 덮는 문제가 있었다. 그래서 AI 정제 on/off와 무관하게 항상 적용한다.
    /// `QueryIntentClassifier.topicSuffixPhrases`와 같은 값을 유지한다("에 대하여"/"에 관하여" 포함).
    private static let trailingMetaPhrases: [String] = [
        "이라는 말씀", "라는 말씀", "하는 말씀", "에 대한 말씀", "에 관한 말씀",
        "이라는 구절", "라는 구절", "하는 구절", "에 대한 구절", "에 관한 구절",
        "라는 뜻", "이라는 뜻", "에 대하여", "에 관하여"
    ]

    /// 문장 끝의 "~라는 말씀"/"~하는 구절" 같은 메타 꼬리표를 기계적으로 잘라낸다.
    /// 해당 없으면 원문을 그대로 돌려준다 — 절대 빈 문자열을 반환하지 않는다.
    static func stripTrailingMetaPhrase(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 가장 긴 꼬리표부터 검사해야 "이라는 말씀"이 "라는 말씀"보다 먼저 걸린다.
        for phrase in trailingMetaPhrases.sorted(by: { $0.count > $1.count }) {
            if result.hasSuffix(phrase) {
                let trimmedResult = String(result.dropLast(phrase.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedResult.isEmpty {
                    result = trimmedResult
                }
                break
            }
        }
        return result
    }

    /// Apple Intelligence로 정제를 시도할 수 있는지. false여도 `refine(query:)`는 원문을
    /// 돌려주므로, UI에 "AI로 다듬는 중" 같은 안내를 보일지 정하는 용도로만 쓴다.
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

    /// 질문형 문장을 검색(임베딩 유사도)에 유리한 평서문으로 다듬는다. 실패하거나
    /// 이용 불가능하면 원문(`query`)을 그대로 돌려준다 — 절대 throw하지 않는다.
    static func refine(query: String) async -> String {
        let trimmed = stripTrailingMetaPhrase(query)
        guard !trimmed.isEmpty else { return query }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return query }
        guard case .available = SystemLanguageModel.default.availability else { return query }

        // 프롬프트는 "어느 절인지"를 묻지 않고 문장 다듬기만 요청한다. 질문 껍데기는
        // 성경 본문에 없는 표현이라 남겨두면 임베딩 벡터가 희석된다.
        let prompt = """
        다음 문장을 성경 구절을 찾기 위한 검색어로 쓸 수 있도록 다듬으세요.
        질문형 어미("~어디있지?", "~말씀이 뭐야?" 등)를 없애고 핵심 내용만
        간결한 평서문 한 문장으로 바꾸세요. 원래 의미를 바꾸거나 추측으로
        내용을 덧붙이지 마세요. 결과 문장 하나만 출력하고 다른 설명은
        붙이지 마세요.

        예시)
        입력: 하나님이 이 세상을 창조하셨다는 말씀이 어디있지?
        출력: 하나님이 세상을 창조하셨다

        입력: 원수를 사랑하라는 말씀이 뭐였지?
        출력: 원수를 사랑하라

        입력: 지혜가 부족하면 하나님께 구하라는 말씀
        출력: 지혜가 부족하면 하나님께 구하라

        입력: \(trimmed)
        출력:
        """

        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt)
            let refined = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return refined.isEmpty ? query : refined
        } catch {
            // 정제는 부가 단계라 실패해도 원문으로 진행한다. 콘솔에만 원인을 남기고
            // 사용자에게 에러 문구는 보여주지 않는다.
            print("[BibleQueryRefinementService] 정제 실패(원문으로 계속 진행): \(error)")
            return query
        }
        #else
        return query
        #endif
    }
}
