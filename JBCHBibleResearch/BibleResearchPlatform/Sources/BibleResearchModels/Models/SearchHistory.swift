import Foundation
import SwiftData

// 기록 정책(시점/개수 상한/중복 처리)은 모델이 아니라 `SearchHistoryService`(앱 레이어)가 책임지고,
// 이 모델은 순수 데이터만 담는다.

/// 통합 검색에서 사용자가 실제로 제출한(엔터/검색 버튼, 또는 이력 목록에서 다시 탭한) 검색어 한 건.
/// 타이핑 중간값은 기록하지 않는다(`SearchHistoryService.record` 참고).
@Model
public final class SearchHistoryEntry {
    public var id: UUID = UUID()
    public var query: String = ""
    public var searchedAt: Date = Date.now

    public init(id: UUID = UUID(), query: String, searchedAt: Date = .now) {
        self.id = id
        self.query = query
        self.searchedAt = searchedAt
    }
}
