import Foundation
import SwiftData

// 말씀 요약(VerseSummary)의 같은 id 중복을 다룬다.
//
// CloudKit은 UNIQUE 제약을 지원하지 않아, 동기화 중 같은 UUID의 레코드가 서로 다른 CKRecord로 따로 생길 수 있다
// (2026-10-07 저장소 점검에서 6개 id가 2건씩 확인됨). 두 가지를 제공한다.
//  - `uniqueById`: 화면 표시용. 레코드를 건드리지 않고 id당 하나만 골라 준다(검색 결과/말씀노트 목록).
//  - `deduplicate`: 정리용. 내용이 완전히 같은 중복만 삭제한다(`ChapterSummaryDeduplication`과 같은 원칙).
//
// 남길 쪽 기준: ① 태그 연결이 더 많은 쪽 ② 더 최근에 수정된(updatedAt) 쪽.
// 태그가 붙은 쪽을 먼저 보는 이유 — `SummaryTag.summary`는 cascade라 태그가 붙은 쪽을 지우면 태그 연결이 함께 사라진다.
public enum VerseSummaryDeduplication {
    private static func isBetter(_ a: VerseSummary, than b: VerseSummary) -> Bool {
        let tagsA = a.summaryTags?.count ?? 0
        let tagsB = b.summaryTags?.count ?? 0
        if tagsA != tagsB { return tagsA > tagsB }
        return a.updatedAt > b.updatedAt
    }

    /// 같은 id가 둘 이상이면 `isBetter`가 가리키는 쪽만 남기고, 입력 순서는 유지한다. 레코드는 삭제하지 않는다.
    public static func uniqueById(_ summaries: [VerseSummary]) -> [VerseSummary] {
        var best: [UUID: VerseSummary] = [:]
        for summary in summaries {
            if let kept = best[summary.id], !isBetter(summary, than: kept) { continue }
            best[summary.id] = summary
        }
        var emitted = Set<UUID>()
        return summaries.filter { best[$0.id] === $0 && emitted.insert($0.id).inserted }
    }

    /// 같은 id의 중복 중 좌표(책·장·절)와 본문(`contentHtml`/`contentText`)이 모두 같은 것만 삭제한다.
    /// 내용이 다르면 데이터를 잃지 않도록 둘 다 남긴다(표시는 `uniqueById`가 맡는다).
    /// 삭제 전에 지워질 쪽에만 있는 태그 연결은 남길 쪽으로 옮기고, 고정(isPinned)은 한쪽이라도 켜져 있으면 유지한다.
    /// 실패해도 앱 부트스트랩을 막지 않도록 throw하지 않는다. 삭제한 개수를 돌려준다.
    @discardableResult
    public static func deduplicate(in context: ModelContext) -> Int {
        do {
            let all = try context.fetch(FetchDescriptor<VerseSummary>())
            let groups = Dictionary(grouping: all, by: { $0.id }).filter { $0.value.count > 1 }
            guard !groups.isEmpty else { return 0 }

            var removed = 0
            for (_, group) in groups {
                let ordered = group.sorted { isBetter($0, than: $1) }
                guard let keeper = ordered.first else { continue }
                for other in ordered.dropFirst() {
                    guard other.bookId == keeper.bookId, other.chapter == keeper.chapter, other.verse == keeper.verse,
                          other.contentHtml == keeper.contentHtml, other.contentText == keeper.contentText else {
                        continue
                    }
                    for link in Array(other.summaryTags ?? []) {
                        guard let tag = link.tag else { continue }
                        let keeperHasTag = (keeper.summaryTags ?? []).contains { $0.tag?.persistentModelID == tag.persistentModelID }
                        if !keeperHasTag { link.summary = keeper }
                    }
                    if other.isPinned { keeper.isPinned = true }
                    context.delete(other)
                    removed += 1
                }
            }
            if removed > 0 { try context.save() }
            return removed
        } catch {
            print("[VerseSummaryDeduplication] 중복 말씀 요약 정리 실패: \(error)")
            return 0
        }
    }
}
