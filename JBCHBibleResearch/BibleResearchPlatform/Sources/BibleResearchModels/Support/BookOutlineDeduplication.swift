import Foundation
import SwiftData

// 근거: bible-research-platform-review-addendum.md 1.2(findOrCreateBookOutline)/1.4
// (BookOutline은 자유 텍스트라 Tag처럼 자동 병합하지 않고 사용자 선택에 맡긴다).
//
// ⚠️ 이 파일은 Xcode에서 컴파일·테스트되지 않았습니다(addendum 6장과 동일한 제약 승계).

public enum BookOutlineDeduplication {
    /// 13.1~13.2 패턴과 동일하게, 책 개요 화면(S8) 진입 시 이 함수 하나로
    /// "있으면 가져오고 없으면 만든다"를 처리한다. 직접 `BookOutline(...)` 생성 금지.
    public static func findOrCreateBookOutline(bookId: Int, context: ModelContext) throws -> BookOutline {
        var descriptor = FetchDescriptor<BookOutline>(
            predicate: #Predicate { $0.bookId == bookId }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let outline = BookOutline(bookId: bookId, contentHtml: "", contentText: "",
                                   createdAt: .now, updatedAt: .now)
        context.insert(outline)
        return outline
    }

    /// 동기화 후 잔여 중복(오프라인 상태의 두 기기가 같은 책에 각자 개요를 만든 경우)을
    /// 정리한다. Tag와 달리 **자동으로 하나를 승자로 정해 병합하지 않는다** — 내용이
    /// 다르면 손실이 발생할 수 있으므로 12장과 같은 방식(두 버전을 나란히 보여주고
    /// 사용자가 선택)으로 넘긴다(addendum 1.4).
    public static func deduplicateBookOutlines(context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<BookOutline>(sortBy: [SortDescriptor(\.id)]))
        var byBook: [Int: BookOutline] = [:]
        for outline in all {
            guard let existing = byBook[outline.bookId] else {
                byBook[outline.bookId] = outline
                continue
            }
            if existing.contentText == outline.contentText {
                // 내용이 완전히 같으면(둘 다 빈 채로 생성된 경우 등) 손실 없이 정리.
                context.delete(outline)
            } else {
                // 다르면 사용자 판단에 맡긴다. S8에서 conflictingOutlineId != nil이면
                // "다른 기기에서 방금 수정됨" 배너를 띄우고 두 버전을 나란히 보여준다.
                // 사용자가 선택하면 그때 패자 쪽을 삭제한다 — 확인 전까지 아무것도
                // 자동 삭제하지 않으므로 Tag와 달리 유예 기간이 필요 없다(addendum 1.4).
                existing.conflictingOutlineId = outline.id
                outline.conflictingOutlineId = existing.id
            }
        }
    }
}
