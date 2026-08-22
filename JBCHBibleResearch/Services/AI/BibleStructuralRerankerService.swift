//
//  BibleStructuralRerankerService.swift
//  JBCHBibleResearch
//
//  [2026-08-19 신설] 사용자 요청 — "③ Apple Intelligence 미지원 기기에서
//  대체 알고리즘 — 인물/지명/관주 연결 여부를 가산 신호로 쓰는 방식."
//  `BibleSearchRerankerService`(Apple Intelligence 기반)와 정확히 같은
//  함수 시그니처(async, throw 없음, 실패해도 원래 순서 유지)를 따르는
//  대체 재순위화 경로 — `BibleSemanticSearchService`가 Apple Intelligence를
//  못 쓸 때 이 서비스로 자동 전환한다(전환 지점은 `BibleSemanticSearchService.
//  swift`에 별도로 전달하는 패치 참고).
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 실제 컴파일 확인은 못 했다 — 이
//  프로젝트의 다른 AI 서비스 파일들과 같은 caveat. `ReferenceDataStore`의
//  `personsAndPlaces(mentionedIn:)`/`personRelations(forWord:)`/
//  `personOrPlace(exactWord:)`/`crossReferenceTargets(bookId:chapter:verse:)`
//  네 메서드는 같은 배치로 전달하는 `ReferenceDataStore.swift` 확장분에서
//  새로 추가한 것이다.
//
//  판단 근거(가산 신호 3가지, 전부 결정론적 — LLM 아님이라 미지원 기기에서도
//  항상 동작한다):
//  1. 질의에 등장한 인물/지명 이름이 실제로 언급하는 절과 후보 절이
//     겹치면 가산(Persons/Places.verses).
//  2. 질의에 등장한 인물이 가진 관계(PersonRelations, 예: "~의 형제")의
//     대상 인물이 언급하는 절과 후보 절이 겹치면 더 크게 가산 — "골리앗의
//     형제" 같은 관계 질문에 직접 응답하는 신호이기 때문(이름 매칭보다
//     가중치를 높게 잡은 이유).
//  3. 후보 절이 이미 후보 목록 안에 있는 다른 절과 관주(Cross Reference)로
//     연결돼 있으면 소폭 가산 — 임베딩만으로는 못 잡는 "구조적으로 서로
//     연결된 절끼리 상호 검증"하는 효과.
//
//  ⚠️ [2026-08-20 갱신, 이전 한계 고지가 낡음] 위 문단은 데이터가 훨씬 부실하던
//  시점의 기록이다 — 그 뒤 build_reference_data.py가 여러 차례 갱신되며
//  "라흐미"는 description까지 채워졌다("골리앗(형제)... 골리앗의 아우로서...").
//  다만 실측해보니 "골리앗" 자체는 여전히 Persons 테이블에 행이 없고(성경에서
//  "형제/아우"로만 언급되고 독립 인물 사전 항목으로 뽑히지 않음), 그 결과
//  구조적으로 다른 버그가 하나 더 있었다: signal 2)가 "질의에 나온 이름이
//  Persons/Places에 있어야만" PersonRelations를 조회하는 정방향 전용
//  루프였다 — "골리앗"이 그 테이블에 없으니 이 루프에 아예 진입하지 못해,
//  PersonRelations에 실제로 있는 `라흐미 -[younger_brother_of]-> 골리앗`
//  관계까지 도달하지 못했다. 아래 2b) 블록(2026-08-20 추가)이 이 역방향
//  경로를 메운다 — "골리앗"이 target_word로 등장하는 행을 직접 찾으므로
//  "골리앗" 자신이 Persons에 없어도 동작한다. 이 수정은 아직 실기기 빌드로
//  검증되지 않았다(이 세션엔 Xcode가 없음) — 실제 검색 결과 재현은 사용자가
//  기기에서 확인해야 한다.
//

import Foundation
import BibleResearchModels

@MainActor
enum BibleStructuralRerankerService {

    /// 인물/지명 이름 매칭 가산치. 관계(2번 신호)보다 작게 잡았다 — 이름이
    /// 질의에 등장했다는 사실만으로는 "그 인물과 관련된 모든 절"이 똑같이
    /// 중요하다고 보기 어렵다(리랭킹 대상 후보 자체가 이미 E5로 걸러진
    /// 상위 50개라, 여기서는 미세 조정 정도의 역할).
    private static let nameMatchBoost: Float = 0.05
    /// 관계 매칭 가산치 — "~의 형제/아들/왕" 같은 관계 질문에 정답 절을
    /// 직접 끌어올리는 핵심 신호라 이름 매칭보다 크게 잡았다.
    private static let relationMatchBoost: Float = 0.15
    /// 관주(교차 참조) 네트워크 가산치 — 후보 목록 안에서 서로 참조하는
    /// 절이 있으면 "우연히 비슷한 단어" 이상의 근거가 있다고 보고 소폭
    /// 가산.
    private static let crossReferenceBoost: Float = 0.08

    static var isAvailable: Bool {
        ReferenceDataProvider.shared.store != nil
    }

    /// `BibleSearchRerankerService.rerank(query:matches:)`와 동일한 계약 —
    /// 실패/미지원이면 원래 순서를 그대로 돌려준다. LLM을 쓰지 않으므로
    /// "실패"는 사실상 `ReferenceData.sqlite`를 못 열었을 때뿐이다.
    static func rerank(query: String, matches: [SemanticVerseMatch]) async -> [SemanticVerseMatch] {
        guard matches.count > 1, let store = ReferenceDataProvider.shared.store else { return matches }

        let boosts = Self.computeBoosts(query: query, candidates: matches, store: store)
        guard !boosts.isEmpty else { return matches }

        return matches.enumerated()
            .map { index, match -> (match: SemanticVerseMatch, score: Float) in
                let key = VerseKey(bookId: match.bookId, chapter: match.chapter, verse: match.verse)
                // 원래 순위를 보존하는 아주 작은 순위 페널티(index가 클수록
                // 더 깎임) 위에 구조적 가산을 얹는다 — E5 순위를 완전히
                // 무시하지 않고, 비슷한 유사도의 후보들 사이에서만 구조적
                // 신호가 순서를 바꾸도록 설계했다. 가산치(0.05~0.15)가
                // 이 페널티(index당 0.001)보다 훨씬 커서, 구조적 신호가
                // 있는 후보는 몇 계단이든 끌어올려질 수 있다.
                let rankBias = -Float(index) * 0.001
                return (match, match.similarity + rankBias + (boosts[key] ?? 0))
            }
            .sorted { $0.score > $1.score }
            .map(\.match)
    }

    private struct VerseKey: Hashable {
        let bookId: Int
        let chapter: Int
        let verse: Int
    }

    private static func computeBoosts(
        query: String, candidates: [SemanticVerseMatch], store: ReferenceDataStore
    ) -> [VerseKey: Float] {
        var boosts: [VerseKey: Float] = [:]
        let candidateKeys = Set(candidates.map { VerseKey(bookId: $0.bookId, chapter: $0.chapter, verse: $0.verse) })

        func addBoost(_ refs: [BibleVerseRef], amount: Float) {
            for ref in refs {
                let key = VerseKey(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse)
                if candidateKeys.contains(key) {
                    boosts[key, default: 0] += amount
                }
            }
        }

        // 1) 인물/지명 이름 매칭 + 2) 관계 매칭(정방향 — 질의에 나온 이름이
        // source_word 쪽인 경우, 예: "다윗의 아들" → "다윗"이 Persons에 있어
        // entity로 잡히고, 그 정방향 관계의 target 쪽 절을 가산).
        if let matchedEntities = try? store.personsAndPlaces(mentionedIn: query) {
            for entity in matchedEntities {
                addBoost(entity.verseRefs, amount: nameMatchBoost)

                guard entity.kind == .person else { continue }
                guard let relations = try? store.personRelations(forWord: entity.word) else { continue }
                for relation in relations {
                    guard relation.targetKind != nil else { continue }  // 미해결 관계는 건너뜀
                    guard let targetEntity = try? store.personOrPlace(exactWord: relation.targetWord) else { continue }
                    addBoost(targetEntity.verseRefs, amount: relationMatchBoost)
                }
            }
        }

        // 2b) 관계 매칭(역방향, 2026-08-20 추가) — 질의에 나온 이름이 관계의
        // target 쪽에만 있고 정작 그 이름 자체는 Persons/Places에 없는 경우
        // (예: "골리앗의 아우" — "골리앗"은 Persons에 행이 없어 위 1)/2) 루프가
        // entity로 잡지 못한다. 하지만 PersonRelations엔 `라흐미 -[younger_
        // brother_of]-> 골리앗` 행이 이미 있다 — target_word="골리앗"이 질의
        // 문자열에 그대로 등장하는지를 직접 찾아, source_word("라흐미")의 절을
        // 가산한다. `personRelations(targetWordMentionedIn:)`의 문서 주석
        // 참고.
        if let reverseRelations = try? store.personRelations(targetWordMentionedIn: query) {
            for relation in reverseRelations {
                guard let sourceEntity = try? store.personOrPlace(exactWord: relation.sourceWord) else { continue }
                addBoost(sourceEntity.verseRefs, amount: relationMatchBoost)
            }
        }

        // 3) 관주(Cross Reference) 네트워크 — 후보끼리 서로 참조하면 가산.
        for candidate in candidates {
            guard let targets = try? store.crossReferenceTargets(
                bookId: candidate.bookId, chapter: candidate.chapter, verse: candidate.verse
            ) else { continue }
            addBoost(targets, amount: crossReferenceBoost)
        }

        return boosts
    }
}
