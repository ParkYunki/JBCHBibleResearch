import Foundation
import SwiftData

// [2026-09-04 신설] 사용자 요청 — "검색이력 기능 추가 ... 검색이력 최근 20개."
// `BibleReadingHistoryService.swift`와 같은 패턴 — "기록"과 "개수 상한" 정책을
// 모두 이 서비스가 책임진다(`SearchHistoryEntry` 모델 자체엔 정책 로직을 넣지
// 않는다).
//
// ⚠️ 이 파일은 Xcode에서 컴파일·테스트되지 않았습니다(다른 Support 파일들과 동일한
// 제약 승계).
public enum SearchHistoryService {
    /// 저장/조회 상한 — 사용자 요청 그대로 "최근 20개"만 의미가 있어,
    /// `BibleReadingHistoryService.maxEntries`(100, 별도 "조회 이력" 화면에서
    /// 따로 훑어볼 목적)와 달리 저장 상한 자체를 20으로 맞췄다 — 그 이상
    /// 보여줄 곳이 없어 더 갖고 있을 이유가 없다.
    public static let maxEntries = 20

    /// 검색어 하나를 기록한다. 호출부(`SearchViewModel.searchImmediately()`)가
    /// **사용자가 실제로 검색을 제출했을 때만** 불러야 한다 — 타이핑 중
    /// 자동검색은 이 프로젝트에 이미 없다(`SearchViewModel.query` 상단 주석
    /// 참고).
    ///
    /// 같은 검색어(공백 트리밍 후 대소문자 구분 없이 비교)가 이미 있으면 새로
    /// 추가하지 않고 그 항목의 시각만 지금으로 갱신해 맨 위로 올린다 — 같은
    /// 검색어를 반복 제출할 때마다 "최근 20개"가 중복으로만 채워지는 것을
    /// 막는 최소한의 방어(Safari/Spotlight 등 통상적인 "최근 검색어" UX와
    /// 같은 처리).
    public static func record(query: String, context: ModelContext) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<SearchHistoryEntry>())) ?? []
        if let existing = all.first(where: { $0.query.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            existing.searchedAt = .now
        } else {
            context.insert(SearchHistoryEntry(query: trimmed, searchedAt: .now))
        }
        trim(context: context)
    }

    /// 최신순으로 정렬된 검색 이력 최근 `maxEntries`개. 화면(통합 검색)이
    /// 열릴 때/검색창을 다시 탭할 때마다 새로 불러 쓴다(다른 창에서 쌓인
    /// 이력까지 반영되도록 캐싱하지 않는다 — 이력/책갈피와 같은 전례).
    public static func fetchRecent(context: ModelContext) -> [SearchHistoryEntry] {
        var descriptor = FetchDescriptor<SearchHistoryEntry>(sortBy: [SortDescriptor(\.searchedAt, order: .reverse)])
        descriptor.fetchLimit = maxEntries
        return (try? context.fetch(descriptor)) ?? []
    }

    /// `maxEntries`를 넘는 오래된 이력을 지운다. `record(...)` 안에서 항상
    /// 함께 호출되므로 보통 직접 부를 필요는 없다.
    public static func trim(context: ModelContext) {
        let all = (try? context.fetch(
            FetchDescriptor<SearchHistoryEntry>(sortBy: [SortDescriptor(\.searchedAt, order: .reverse)])
        )) ?? []
        guard all.count > maxEntries else { return }
        for entry in all[maxEntries...] {
            context.delete(entry)
        }
    }
}
