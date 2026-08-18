import Foundation
import SwiftData

// 근거: bible-research-platform-screens.md 6.6(ChapterSummary) — S9(장 단위 개요) 진입 시
// "있으면 가져오고 없으면 만든다"를 한 곳에서 처리한다. BookOutlineDeduplication.swift와
// 동일한 find-or-create 패턴을 따른다.
//
// ⚠️ [BookOutline과의 의도적 차이, 확인 필요] BookOutline은 addendum 1.1/1.4에서
// "book_id UNIQUE 제약을 CloudKit이 지원하지 않아 오프라인 두 기기가 각자 만들면
// 중복 레코드가 생길 수 있다"는 문제를 `conflictingOutlineId` 필드로 명시적으로
// 해결했다. ChapterSummary도 원리상 동일한 위험(오프라인 두 기기가 같은 (book_id,
// chapter)에 대해 각자 레코드를 만드는 경우)이 있지만, schema.md/addendum
// 어디에도 ChapterSummary에 이 처리를 요구하는 문구가 없다 — 그래서 이 파일은
// BookOutline과 달리 충돌 필드(conflictingId 등)를 추가하지 않았다(근거 없는
// 스키마 확장을 피하기 위함, review-addendum "오버엔지니어링 금지" 원칙). 대신
// 이 함수는 "같은 세션 안에서" 중복 생성만 막는다(가장 흔한 경우). 오프라인
// 멀티기기 시나리오까지 BookOutline과 동일하게 보호할지는 제품 결정이 필요하다.
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

    /// 동기화 후 잔여 중복 정리 — BookOutlineDeduplication.deduplicateBookOutlines와
    /// 동일한 보수적 규칙(완전히 같은 내용의 빈 중복만 자동 정리, 내용이 다르면
    /// 아무것도 하지 않고 그대로 둔다). BookOutline과 달리 conflictingId로 표시해
    /// 사용자에게 선택을 맡기는 UI가 아직 없으므로(위 ⚠️ 참고), 내용이 다른 중복은
    /// 여기서 그대로 남는다 — 조용히 데이터를 잃지 않기 위한 보수적 선택이다.
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
            // 내용이 다르면 addendum 1.4의 BookOutline 처리와 달리 아무 표시도 하지
            // 않고 둘 다 남긴다 — 위 파일 상단 ⚠️ 참고.
        }
    }
}
