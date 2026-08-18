import Foundation
import SwiftData

// 근거: bible-research-platform-review-addendum.md 1.2/1.3.
// Tag.name UNIQUE는 CloudKit과 함께 쓸 수 없으므로(addendum 1.1), 2단계로 대응한다.
//   1단계 — findOrCreateTag: 같은 세션·같은 기기의 순차 생성 중복을 원천 차단.
//   2단계 — deduplicateTags: 두 기기가 오프라인 상태에서 각자 만든 뒤 동기화되어
//           생기는 잔여 중복을 결정론적 규칙(id 오름차순)으로 병합.
// 1단계만으로는 오프라인 동시 생성을 막을 수 없다 — 이건 클라이언트 코드로 원천 차단이
// 불가능한 CloudKit 구조적 한계다(addendum 1.2 말미).
//
// ✅ 2026-08-06: #Predicate 옵셔널 Date 비교 문법은 실기기 빌드에서 정상 컴파일
// 확인됨. 다만 아래 to-many 관계 접근부는 Tags.swift가 `[T]? = []`로 바뀐 것에 맞춰
// 전부 `?? []`로 옵셔널 처리했다(CloudKit이 to-many 관계도 Optional 타입을 요구해서
// 생긴 변경 — Tags.swift 상단 주석 참고).

public enum TagDeduplication {
    /// 병합된 태그를 즉시 하드 삭제하지 않고 남겨두는 유예기간.
    /// 이유: 병합 스윕이 도는 순간 다른 화면에서 방금 "패자"가 된 태그를
    /// 편집·참조 중일 수 있다. 관계는 즉시 winner로 재배정하되 레코드 자체는
    /// 유예기간 동안 남겨두면, 그 사이 새로 생긴 참조도 다음 스윕에서 winner로
    /// 흡수되어 댕글링 참조가 발생하지 않는다. (addendum 1.3)
    public static let gracePeriod: TimeInterval = 60 * 60 * 24 * 3 // 3일

    /// 13.3(태그 확정), 14.6(AI 태그 확정) 등 태그 생성이 일어나는 모든 진입점이
    /// 반드시 이 함수 하나를 공유해야 한다 (직접 `Tag(...)` 생성 금지).
    public static func findOrCreateTag(named rawName: String, context: ModelContext) throws -> Tag {
        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.normalizedForm == normalized && $0.mergedIntoId == nil }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: rawName, normalizedForm: normalized, createdAt: .now)
        context.insert(tag)
        return tag
    }

    /// 동기화 후 잔여 중복을 병합한다. 앱 실행 시(원격 변경 알림 수신 시 등) 주기적으로
    /// 호출하는 것을 전제로 한다 — 호출 시점은 이 파일의 책임 범위 밖(앱 레이어에서 결정).
    public static func deduplicateTags(context: ModelContext) throws {
        // 1) 아직 병합되지 않은 태그만 정규화 이름별로 그룹핑.
        //    id 오름차순 정렬 = 결정론적 승자 선정(모든 기기가 같은 결론에 수렴).
        let active = try context.fetch(FetchDescriptor<Tag>(
            predicate: #Predicate { $0.mergedIntoId == nil },
            sortBy: [SortDescriptor(\.id)]
        ))
        var winners: [String: Tag] = [:]
        let now = Date.now
        for tag in active {
            guard let winner = winners[tag.normalizedForm] else {
                winners[tag.normalizedForm] = tag
                continue
            }
            try reassignRelationships(from: tag, to: winner, context: context)
            tag.mergedIntoId = winner.id
            tag.pendingDeletionAt = now.addingTimeInterval(gracePeriod)
        }

        // 2) 유예기간이 지난 것만 실제로 삭제.
        let cutoff = Date.now
        let expired = try context.fetch(FetchDescriptor<Tag>(
            predicate: #Predicate { $0.pendingDeletionAt != nil && $0.pendingDeletionAt! < cutoff }
        ))
        expired.forEach(context.delete)
    }

    /// loser의 모든 관계를 winner로 재배정한다.
    /// ⚠️ 현재 알려진 네 관계(MemoTag, SummaryTag, DocumentAnchor, TagRelation)만
    /// 처리한다. 향후 Tag를 참조하는 새 관계 타입이 추가되면 이 함수도 함께
    /// 갱신해야 한다. (addendum 6장)
    static func reassignRelationships(from loser: Tag, to winner: Tag, context: ModelContext) throws {
        // MemoTag — 같은 메모가 winner에도 이미 연결돼 있으면 중복 조인 로우이므로 loser 쪽만 삭제.
        // ⚠️ addendum 원안은 `memoTag.memoId`(원시 UUID)를 비교했지만, 이 구현은
        // Tags.swift에서 확정한 대로 `memo: UserMemo?` 관계를 직접 비교한다.
        for memoTag in loser.memoTags ?? [] {
            if (winner.memoTags ?? []).contains(where: { $0.memo?.id == memoTag.memo?.id }) {
                context.delete(memoTag)
            } else {
                memoTag.tag = winner
            }
        }

        // SummaryTag — [2026-08-14 신설] `MemoTag`와 완전히 같은 규칙.
        for summaryTag in loser.summaryTags ?? [] {
            if (winner.summaryTags ?? []).contains(where: { $0.summary?.id == summaryTag.summary?.id }) {
                context.delete(summaryTag)
            } else {
                summaryTag.tag = winner
            }
        }

        // DocumentAnchor — 문서 내 위치(bbox/offset)를 가진 개별 인스턴스이므로 그대로 재배정.
        for anchor in loser.documentAnchors ?? [] {
            anchor.linkedTag = winner
        }

        // TagRelation — tagA/tagB 양쪽 다 처리. 자기참조/중복엣지 정리 포함.
        // ⚠️ 반드시 스냅샷을 먼저 만든 뒤 순회해야 한다. 순회 중에 relation.tagA = winner로
        // 바꾸면 그 즉시 원본 컬렉션(loser.relationsAsA)이 변형되어 일부 항목을 건너뛸 수
        // 있다(addendum 1.3 경고). `?? []`가 이미 새 배열을 만들어 반환하므로 별도
        // Array(...) 래핑 없이도 스냅샷 조건은 만족한다.
        for relation in loser.relationsAsA ?? [] {
            reassignTagRelationSide(relation, isSideA: true, winner: winner, context: context)
        }
        for relation in loser.relationsAsB ?? [] {
            reassignTagRelationSide(relation, isSideA: false, winner: winner, context: context)
        }
    }

    private static func reassignTagRelationSide(
        _ relation: TagRelation, isSideA: Bool, winner: Tag, context: ModelContext
    ) {
        guard let other = isSideA ? relation.tagB : relation.tagA else {
            // 반대편이 이미 nil(데이터 정합성 이상) — 안전하게 폐기.
            context.delete(relation)
            return
        }
        if other.id == winner.id {
            context.delete(relation) // winner-loser 사이 기존 연결 → 자기참조가 되므로 폐기.
            return
        }
        let alreadyExists = ((winner.relationsAsA ?? []) + (winner.relationsAsB ?? [])).contains {
            ($0.tagA?.id == winner.id && $0.tagB?.id == other.id) ||
            ($0.tagB?.id == winner.id && $0.tagA?.id == other.id)
        }
        if alreadyExists {
            context.delete(relation) // winner-other 사이에 이미 같은 엣지가 있으면 중복 제거.
        } else if isSideA {
            relation.tagA = winner
        } else {
            relation.tagB = winner
        }
    }
}
