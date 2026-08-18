import Foundation
import SwiftData

// [2026-08-08 신설] 사용자 요청 — "조회 이력(히스토리) 기능 추가 (년월일 시분초),
// 100개의 조회한 성경과 장의 이력을 저장하고 조회할 수 있도록". "기록"과 "100개
// 캡" 정책을 모두 이 서비스가 책임진다 — `BibleReadingHistoryEntry` 모델 자체엔
// 정책 로직을 넣지 않는다(BookOutlineDeduplication.swift와 같은 이 프로젝트의
// 관례).
//
// ⚠️ 이 파일은 Xcode에서 컴파일·테스트되지 않았습니다(다른 Support 파일들과 동일한
// 제약 승계).
public enum BibleReadingHistoryService {
    /// 이력에 남기는 최대 개수. 초과분은 오래된 순으로 삭제한다.
    public static let maxEntries = 100

    /// 책/장을 하나 기록한다. 호출부(`BibleReadingViewModel.selectBook`/
    /// `goToChapter`)가 **사용자가 실제로 이동을 선택했을 때만** 불러야 한다 —
    /// `BibleReadingViewModel.init`이 `LastBiblePositionTracker`로 마지막 위치를
    /// "복원"하는 경우까지 기록하면, 다른 화면과 성경 조회를 오갈 때마다 같은
    /// 위치가 계속 이력에 쌓여 "조회 이력"이라는 취지와 어긋난다.
    ///
    /// 바로 직전 항목과 book/chapter가 완전히 같으면 새로 기록하지 않는다 —
    /// 화면 재진입 등으로 같은 좌표에 대해 `selectBook`이 반복 호출되는 경우
    /// 이력이 의미 없이 중복되는 것을 막기 위한 최소한의 방어다.
    public static func record(bookId: Int, chapter: Int, context: ModelContext) {
        var lastDescriptor = FetchDescriptor<BibleReadingHistoryEntry>(
            sortBy: [SortDescriptor(\.viewedAt, order: .reverse)]
        )
        lastDescriptor.fetchLimit = 1
        if let last = try? context.fetch(lastDescriptor).first,
           last.bookId == bookId, last.chapter == chapter {
            return
        }

        let entry = BibleReadingHistoryEntry(bookId: bookId, chapter: chapter, viewedAt: .now)
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
