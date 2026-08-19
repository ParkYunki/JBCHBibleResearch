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
//  ⚠️ [정직한 한계 고지] 사용자가 대화 중 예로 든 "골리앗의 형제 라흐미"는
//  지금 번들에 들어간 체크포인트 데이터(`PersonPlaceSeed.json`, 인명 681건
//  중 description이 있는 것은 229건뿐)에는 "골리앗"이라는 항목 자체가
//  없고 "라흐미"는 있지만 description이 비어 있어(build_reference_data.py
//  실행 로그 참고) 이 예시가 지금 당장 재현되지는 않는다. 이 서비스의
//  로직 자체는 더 온전한 사전 데이터가 채워지면 그대로 통하도록 설계했다
//  — 지금은 데이터가 부분적이라는 것이지 로직이 틀린 게 아니다.
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

        // 1) 인물/지명 이름 매칭 + 2) 관계 매칭
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
