import Foundation
import SwiftData

// 조회 이력 "기록"과 "100개 캡" 정책을 이 서비스가 책임진다 — `BibleReadingHistoryEntry` 모델
// 자체엔 정책 로직을 넣지 않는다(BookOutlineDeduplication.swift와 같은 관례).
public enum BibleReadingHistoryService {
    /// 이력에 남기는 최대 개수. 초과분은 오래된 순으로 삭제한다.
    public static let maxEntries = 100

    /// 책/장(선택적으로 절까지)을 하나 기록한다. 호출부는 **사용자가 실제로 이동을 선택했을 때만**
    /// 불러야 한다 — `BibleReadingViewModel.init`의 마지막 위치 "복원"까지 기록하면 화면을 오갈 때마다
    /// 같은 위치가 이력에 쌓인다.
    ///
    /// 바로 직전 항목과 book/chapter/verse가 모두 같으면 기록하지 않는다(재진입 등으로 `selectBook`이
    /// 반복 호출될 때의 중복 방지). verse도 비교해야 "3장 이동(verse=nil)" 직후의 "3장 5절 확대보기"가
    /// 무시되지 않는다.
    public static func record(bookId: Int, chapter: Int, verse: Int? = nil, context: ModelContext) {
        var lastDescriptor = FetchDescriptor<BibleReadingHistoryEntry>(
            sortBy: [SortDescriptor(\.viewedAt, order: .reverse)]
        )
        lastDescriptor.fetchLimit = 1
        if let last = try? context.fetch(lastDescriptor).first,
           last.bookId == bookId, last.chapter == chapter, last.verse == verse {
            return
        }

        let entry = BibleReadingHistoryEntry(bookId: bookId, chapter: chapter, verse: verse, viewedAt: .now)
        context.insert(entry)
        trim(context: context)
    }

    /// 100개를 넘는 오래된 이력을 지운다. `record(...)` 안에서 항상 함께 호출되므로
    /// 보통 직접 부를 필요는 없지만, 다른 경로(예: 데이터 이관)로 대량 삽입이 생길
    /// 경우에 대비해 public으로 둔다.
    public static func trim(context: ModelContext) {
        let all = (try? context.fetch(
            FetchDescriptor<BibleReadingHistoryEntry>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        )) ?? []
        guard all.count > maxEntries else { return }
        for entry in all[maxEntries...] {
            context.delete(entry)
        }
    }
}
