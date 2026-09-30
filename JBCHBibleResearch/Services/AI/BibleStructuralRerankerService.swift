//
//  BibleStructuralRerankerService.swift
//  JBCHBibleResearch
//
//  Apple Intelligence를 쓸 수 없는 기기를 위한 결정론적(LLM 아님) 재순위화 서비스.
//  `BibleSearchRerankerService`와 같은 계약(async, throw 없음, 실패 시 원래 순서 유지)이다.
//
//  가산 신호 3가지:
//  1. 질의에 등장한 인물/지명이 언급하는 절과 후보 절이 겹치면 가산(Persons/Places.verses).
//  2. 질의에 등장한 인물의 관계(PersonRelations, 예: "~의 형제") 대상이 언급하는 절과
//     겹치면 더 크게 가산 — 관계 질문에 직접 응답하는 신호라 이름 매칭보다 가중치가 높다.
//  3. 후보 절이 후보 목록 안의 다른 절과 관주(Cross Reference)로 연결돼 있으면 소폭 가산.
//
//  ⚠️ 신호 2는 질의의 이름이 Persons/Places에 있어야만 정방향으로 진입한다. "골리앗"처럼
//  Persons에 행이 없고 PersonRelations의 target_word로만 존재하는 이름은 2b)의 역방향
//  조회가 처리한다.
//

import Foundation
import BibleResearchModels

@MainActor
enum BibleStructuralRerankerService {

    /// 인물/지명 이름 매칭 가산치. 후보가 이미 E5로 걸러진 상위 50개라 미세 조정 역할이며,
    /// 이름 등장만으로는 관련 절이 모두 똑같이 중요하다고 보기 어려워 관계 가산치보다 작다.
    private static let nameMatchBoost: Float = 0.05
    /// 관계 매칭 가산치. "~의 형제/아들/왕" 같은 관계 질문의 정답 절을 끌어올리는 핵심 신호라
    /// 이름 매칭보다 크다.
    private static let relationMatchBoost: Float = 0.15
    /// 관주(교차 참조) 네트워크 가산치. 후보끼리 서로 참조하면 소폭 가산한다.
    private static let crossReferenceBoost: Float = 0.08

    static var isAvailable: Bool {
        ReferenceDataProvider.shared.store != nil
    }

    /// `BibleSearchRerankerService.rerank(query:matches:)`와 동일한 계약. 실패하면 원래
    /// 순서를 돌려주며, LLM을 쓰지 않으므로 실패는 `ReferenceData.sqlite`를 못 열었을 때뿐이다.
    static func rerank(query: String, matches: [SemanticVerseMatch]) async -> [SemanticVerseMatch] {
        guard matches.count > 1, let store = ReferenceDataProvider.shared.store else { return matches }

        let boosts = Self.computeBoosts(query: query, candidates: matches, store: store)
        guard !boosts.isEmpty else { return matches }

        return matches.enumerated()
            .map { index, match -> (match: SemanticVerseMatch, score: Float) in
                let key = VerseKey(bookId: match.bookId, chapter: match.chapter, verse: match.verse)
                // 원래 순위를 보존하는 작은 페널티(index당 0.001) 위에 구조적 가산을 얹는다.
                // 가산치(0.05~0.15)가 페널티보다 훨씬 커서, 구조적 신호가 있는 후보는
                // 몇 계단이든 끌어올려질 수 있다.
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

        // 1) 인물/지명 이름 매칭 + 2) 관계 매칭(정방향: 질의의 이름이 source_word 쪽인 경우,
        // 예: "다윗의 아들" → 관계의 target 쪽 절을 가산).
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

        // 2b) 관계 매칭(역방향) — 질의의 이름이 관계의 target 쪽에만 있고 Persons/Places에는
        // 없는 경우(예: "골리앗의 아우"는 `라흐미 -[younger_brother_of]-> 골리앗`)를 위해,
        // target_word가 질의에 등장하는 행을 직접 찾아 source_word의 절을 가산한다.
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
