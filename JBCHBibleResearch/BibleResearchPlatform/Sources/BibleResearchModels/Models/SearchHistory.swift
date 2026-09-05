import Foundation
import SwiftData

// [2026-09-04 신설] 사용자 요청 — "검색이력 기능 추가 - 아이폰 - 통합검색을
// 클릭했을 때 검색창 밑으로 검색이력 최근 20개가 나올 수 있도록 한다. macos,
// ipados는 UI/UX 관점에 검색이력이 나올 수 있도록 통일성있는 디자인으로
// 레이아웃을 제안하라." `BibleReadingHistory.swift`/`BibleBookmark.swift`와
// 같은 이 프로젝트의 관례 — 정책(기록 시점/개수 상한/중복 처리)은 모델이
// 아니라 `SearchHistoryService`(앱 레이어)가 책임지고, 이 모델은 순수 데이터
// 구조체 역할만 한다.

/// 통합 검색(S11)에서 사용자가 실제로 제출한(엔터/검색 버튼, 또는 이 이력
/// 목록에서 다시 탭한 검색어) 검색어 한 건. 타이핑 중간값은 기록하지
/// 않는다 — `SearchViewModel.searchImmediately()`가 실제 검색을 실행할 때만
/// 기록된다(`SearchHistoryService.record` 참고).
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
