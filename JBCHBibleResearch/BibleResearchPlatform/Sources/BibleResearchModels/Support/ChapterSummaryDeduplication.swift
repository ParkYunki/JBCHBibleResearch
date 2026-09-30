import Foundation
import SwiftData

// S9(장 단위 개요) 진입 시 "있으면 가져오고 없으면 만든다"를 한 곳에서 처리한다.
// BookOutlineDeduplication.swift와 동일한 find-or-create 패턴을 따른다.
//
// ⚠️ BookOutline과 달리 충돌 필드(conflictingId 등)는 두지 않았다. CloudKit은 UNIQUE 제약을
// 지원하지 않아 오프라인 두 기기가 같은 (book_id, chapter)로 각자 레코드를 만들 수 있지만,
// 스키마 문서에 ChapterSummary에 대한 처리 요구가 없어 근거 없는 스키마 확장을 피했다.
// 따라서 이 함수는 "같은 세션 안에서"의 중복 생성만 막는다. 오프라인 멀티기기 시나리오까지
// 보호할지는 제품 결정이 필요하다.
public enum ChapterSummaryDeduplication {
    /// S9 화면 진입 시 이 함수 하나로 "있으면 가져오고 없으면 만든다"를 처리한다.
    /// 직접 `ChapterSummary(...)` 생성 금지.
    public static func findOrCreateChapterSummary(
        bookId: Int,
        chapter: Int,
        context: ModelContext
    ) throws -> ChapterSummary {
        var descriptor = FetchDescriptor<ChapterSummary>(
            predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let summary = ChapterSummary(bookId: bookId, chapter: chapter, contentHtml: "", contentText: "",
                                      createdAt: .now, updatedAt: .now)
        context.insert(summary)
        return summary
    }

    /// 동기화 후 잔여 중복 정리 — 내용이 완전히 같은 중복만 삭제하고, 내용이 다르면
    /// 조용히 데이터를 잃지 않도록 둘 다 남긴다(사용자에게 선택을 맡기는 UI는 아직 없다).
    public static func deduplicateChapterSummaries(context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<ChapterSummary>(sortBy: [SortDescriptor(\.id)]))
        var seen: [String: ChapterSummary] = [:]
        for summary in all {
            let key = "\(summary.bookId)-\(summary.chapter)"
            guard let existing = seen[key] else {
                seen[key] = summary
                continue
            }
            if existing.contentText == summary.contentText {
                context.delete(summary)
            }
            // 내용이 다르면 표시 없이 둘 다 남긴다(위 ⚠️ 참고).
        }
    }
}
