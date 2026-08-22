//
//  BibleReferenceAIQueryService.swift
//  JBCHBibleResearch
//
//  [2026-08-19 전면 교체] 사용자 요청 — "애플 인텔리전스로 텍스트를 정제하고,
//  방식 A — 임베딩 기반 의미검색을 한다면?" + "이 새 파이프라인이 기존 AI
//  토글(장절 변환 방식)을 완전히 대체할까요?" → "완전 대체". 이 파일이 원래
//  갖고 있던 `BibleReferenceAIQueryService`("자유 문장 → 성경 장절 텍스트로
//  직접 변환")는 통째로 지우고, 역할이 완전히 다른 `BibleQueryRefinementService`
//  ("자유 문장을 다듬기만 함, 정답 장절을 맞히려 하지 않음")로 바꿔 썼다 — 파일
//  경로는 그대로 유지해(Xcode에서 또 수동 삭제를 요청하지 않으려고) 내용만
//  갈아염었다.
//
//  ⚠️ [왜 "장절을 직접 답하기"를 그만뒀는지] 사용자 보고 — "AI 검색을 잘 못함.
//  결과가 거의 나오지 않음." 원인은 온디바이스 모델(FoundationModels)이 성경
//  지식을 얕게만 알고 있어서였다. 이번 새 구조는 "정답이 무슨 절인지 맞히는"
//  역할을 이 모델에게 아예 맡기지 않는다 — 그 역할은 이제
//  `EmbeddingService`+`EmbeddingIndexingService`(코사인 유사도 검색, 실제
//  성경 본문 임베딩과 비교하므로 존재하지 않는 절을 지어낼 수 없음)가 맡는다.
//  이 파일은 그 앞단에서 "질문형 문장을 검색에 유리한 평서문으로 다듬는" 훨씬
//  가벼운 언어 작업만 한다 — 성경 지식이 필요 없는 순수 문장 정제라 온디바이스
//  모델이 상대적으로 잘 해내는 영역이다(`BibleSemanticSearchService.swift`가
//  이 서비스 다음 단계로 임베딩 검색을 이어붙인다).
//
//  ⚠️ [정제는 필수가 아니라 "있으면 더 좋은" 단계] `BibleSemanticSearchService`가
//  이 서비스를 호출하지만, 이 서비스가 실패하거나(Apple Intelligence 미지원
//  기기 등) 이용 불가능해도 원문 그대로 임베딩 검색을 계속 진행한다 — 정제
//  실패가 전체 AI 검색 기능을 막지 않는다(`refine(query:)`가 항상 String을
//  돌려주고 Result/throws가 아닌 이유).
//
//  `ChapterOutlineDraftService.swift`와 같은 FoundationModels 사용 패턴
//  (`#if canImport(FoundationModels)` + `@available` 이중 가드, plain-text
//  `session.respond(to:)`)을 그대로 따른다 — 이 세션엔 Xcode가 없어 실제
//  컴파일 확인은 못 했다는 같은 caveat이 적용된다.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum BibleQueryRefinementService {
    /// [2026-08-19 추가] 실사용 사례로 확인된 문제 — 사용자가 "지혜가 부족하면
    /// 하나님께 구하라는 말씀"처럼 검색하면, 정작 정답인 약 1:5 대신 "말씀"이라는
    /// 단어만 공유하는 무관한 절들(에베소서 6:17 "말씀을 가지라", 시편 119:81
    /// "말씀을 바라나이다" 등)이 90%대 유사도로 상위를 뒤덮었다. 원인은 "~라는
    /// 말씀"/"~하는 구절" 같은 꼬리표가 "나는 성경 구절을 찾고 있다"는 메타
    /// 표현일 뿐 실제 검색 대상이 아닌데, 이 짧은 문장 안에서 임베딩이 이
    /// 흔한 단어 하나에 지배당해버린 것 — 아래 few-shot 예시(질문형 어미가
    /// 있는 문장만 다룸)는 이 사례처럼 물음표 없이 "~하라는 말씀" 형태로 끝나는
    /// 문장에는 안정적으로 일반화되지 않았다. 그래서 Apple Intelligence
    /// 가용 여부/토글 상태와 무관하게 항상 적용되는 결정적(비-AI) 정규화 단계를
    /// 앞에 추가한다 — `BibleSemanticSearchService.search`가 정제 on/off와
    /// 무관하게 이 함수를 먼저 거친다.
    // [2026-08-20 신설] "에 대하여"/"에 관하여" 추가 — `QueryIntentClassifier
    // .topicSuffixPhrases`와 동일하게 유지하는 값이라, 그쪽에 추가한 이유
    // (Themes 시드 제목이 "OOO에 대하여" 형식이라 기존 목록으론 인식 못 함)
    // 그대로 여기도 갱신한다. 이 배열의 원래 목적(문장 끝 메타 꼬리표를
    // 잘라내고 임베딩)과도 자연스럽게 맞는다 — "성경에 대하여"도 "~라는
    // 말씀"과 같은 부류의 메타 표현이라 잘라내는 게 맞다.
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

    /// Apple Intelligence로 정제를 "시도"할 수 있는지. false여도
    /// `refine(query:)`는 여전히 안전하게 원문을 그대로 돌려준다 — 이 값은
    /// UI에 "AI로 다듬는 중" 같은 부가 안내를 보여줄지 결정하는 용도로만 쓴다.
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

        // [2026-08-19] 이 프롬프트는 "어느 절인지"를 절대 묻지 않는다 — 오직
        // 문장 다듬기만 요청한다. 질문형 껍데기("~어디있지?", "~말씀이 뭐야?")를
        // 걷어내면, 뒤이은 임베딩 유사도 비교가 핵심 의미에 더 집중할 수 있다는
        // 판단(질문 껍데기 자체는 성경 본문 어디에도 없는 표현이라, 남겨두면
        // 벡터가 그만큼 희석된다).
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
            // 정제는 부가 단계일 뿐이라 실패해도 원문으로 계속 진행한다 — 콘솔에만
            // 원인을 남긴다(사용자에게 영어 타입명이 섞인 에러 문구를 보여주지
            // 않는다, BibleSemanticSearchService.swift와 같은 원칙).
            print("[BibleQueryRefinementService] 정제 실패(원문으로 계속 진행): \(error)")
            return query
        }
        #else
        return query
        #endif
    }
}
