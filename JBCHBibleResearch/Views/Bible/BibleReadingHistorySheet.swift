//
//  BibleReadingHistorySheet.swift
//  JBCHBibleResearch
//
//  성경 조회 이력 레이어. 2026-10-02부터 책갈피 목록(`BookmarkListPopover`)과 같은 방식 — 레일/툴바 아이콘에 붙는
//  팝오버(아이폰은 시트로 자동 전환) — 으로 띄우며, 머리·구분선·행·빈 상태도 같은 공통 부품
//  (`BibleListLayerParts.swift`)을 쓴다. 타입 이름의 "Sheet"는 예전 표시 방식의 흔적이라 이름은 바꾸지 않았다.
//  항목을 탭하면 그 책/장으로 이동한 뒤 레이어를 닫는다(다시 조회한 것이므로 그 이동도 새 이력으로 기록된다 —
//  `BibleReadingViewModel.jumpToHistoryEntry` 참고).
//
//  최근 1개월 이력(`BibleReadingViewModel.fetchHistory()`가 필터링)을 오늘/어제/그저께/
//  이번주/지난주/이번달로 그룹핑해 보여준다. 그룹 판정은 `Calendar.current`의 day 기준
//  판정을 한 곳에 모아 항목 하나가 정확히 한 버킷에만 들어가게 한다
//  (`SidebarNavigationView.quickItemDateBucket(for:)`와 같은 원칙). 그룹핑은 열 때 한 번만 계산해
//  `@State`에 담는다(계산 프로퍼티로 두면 화면이 다시 그려질 때마다 항목 수 × 버킷 수만큼 날짜 판정을 반복한다).
//
//  시각 표기는 버킷에 맞춘다 — 오늘/어제/그저께는 섹션 헤더가 날짜를 알려주므로 시분초만,
//  이번주/지난주/이번달은 여러 날이 섞이므로 날짜+시분을 보여 한 줄에 들어가게 한다.

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

struct BibleReadingHistorySheet: View {
    private var settings: UserSettingsStore { .shared }
    let viewModel: BibleReadingViewModel
    var onDismiss: () -> Void

    /// 버킷별로 나눈 이력(최신순 유지). 열 때 한 번 계산한다.
    @State private var sections: [HistorySection] = []
    /// 머리 배지에 보일 전체 개수.
    @State private var totalCount = 0

    /// 오늘/어제/그저께 행처럼 섹션 헤더가 이미 날짜를 알려주는 경우, 시분초만 보여준다.
    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    /// 이번주/지난주/이번달처럼 한 섹션에 여러 날짜가 섞이는 경우, 날짜+시분을 보여준다
    /// (한 줄에 들어가야 하는 폭 제약으로 초 단위는 생략).
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    /// 항목 하나가 정확히 한 버킷에만 들어가도록 판정을 한 곳에 모은 그룹 구분.
    private enum HistoryDateBucket: CaseIterable, Hashable {
        case today, yesterday, dayBeforeYesterday, thisWeek, lastWeek, thisMonth

        var title: String {
            switch self {
            case .today: return "오늘"
            case .yesterday: return "어제"
            case .dayBeforeYesterday: return "그저께"
            case .thisWeek: return "이번 주"
            case .lastWeek: return "지난 주"
            case .thisMonth: return "이번 달"
            }
        }
    }

    private struct HistorySection: Identifiable {
        let bucket: HistoryDateBucket
        let entries: [BibleReadingHistoryEntry]
        var id: HistoryDateBucket { bucket }
    }

    private func bucket(for date: Date) -> HistoryDateBucket {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        if let dayBeforeYesterday = calendar.date(byAdding: .day, value: -2, to: .now),
           calendar.isDate(date, inSameDayAs: dayBeforeYesterday) {
            return .dayBeforeYesterday
        }
        // "이번주"는 오늘이 속한 캘린더 주(로케일의 첫 요일 기준)의 시작일 이후 전부,
        // "지난주"는 그 바로 앞 7일 구간이다.
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start
            ?? calendar.startOfDay(for: .now)
        if date >= thisWeekStart { return .thisWeek }
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
        if date >= lastWeekStart { return .lastWeek }
        return .thisMonth
    }

    /// `entries`(이미 최신순 + 최근 1개월로 정리된 값)를 버킷별로 나눈다 — 항목마다 한 번만 판정하고,
    /// 각 버킷 내부의 최신순 정렬은 입력 순서 그대로 유지된다.
    private func makeSections(from entries: [BibleReadingHistoryEntry]) -> [HistorySection] {
        var byBucket: [HistoryDateBucket: [BibleReadingHistoryEntry]] = [:]
        for entry in entries {
            byBucket[bucket(for: entry.viewedAt), default: []].append(entry)
        }
        return HistoryDateBucket.allCases.compactMap { bucket in
            byBucket[bucket].map { HistorySection(bucket: bucket, entries: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BibleListLayerHeader(title: "조회 이력", count: totalCount, topInset: headerTopInset, onDismiss: onDismiss)
            BibleListLayerDivider()
            if sections.isEmpty {
                BibleListLayerEmptyState(
                    systemImage: "clock",
                    title: "조회 이력이 없습니다",
                    message: "책과 장을 열면 여기에 쌓입니다."
                )
            } else {
                list
            }
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // 아이폰은 `.popover`가 시트로 바뀌므로 폭·높이를 시트에 맡긴다(이전 `.sheet`와 같은 크기).
        .frame(
            width: isPhone ? nil : BibleListLayerMetrics.historyWidth,
            height: isPhone ? nil : popoverHeight
        )
        .onAppear {
            // 레이어를 열 때마다 새로 불러온다 — 다른 창에서 쌓인 이력까지 반영하기 위해 캐싱하지 않는다.
            let fetched = viewModel.fetchHistory()
            totalCount = fetched.count
            sections = makeSections(from: fetched)
        }
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                BibleListLayerSectionHeader(title: section.bucket.title, count: section.entries.count)
                    .bibleListLayerRowChrome()
                    .listRowSeparator(.hidden)
                ForEach(section.entries) { entry in
                    BibleListLayerRow(
                        title: bookChapterLabel(for: entry),
                        meta: timeLabel(for: entry, bucket: section.bucket),
                        onSelect: {
                            viewModel.jumpToHistoryEntry(entry)
                            onDismiss()
                        }
                    )
                    .bibleListLayerRowChrome()
                }
            }
        }
        .bibleListLayerListStyle()
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// 머리 위 여백 — 팝오버 14, 아이폰 시트는 18(`BookmarkListPopover`와 같은 값).
    private var headerTopInset: CGFloat { isPhone ? 18 : 14 }

    /// 팝오버 높이. `List`는 내용 높이를 스스로 알리지 않아 행/섹션 수로 근사하고 상한(500)으로 자른다 —
    /// 근사가 모자라면 목록 안에서 스크롤되고, 남으면 여백이 생길 뿐 잘리지는 않는다.
    private var popoverHeight: CGFloat {
        let chrome = BibleListLayerMetrics.headerHeight(topInset: headerTopInset) + BibleListLayerMetrics.dividerHeight
        let content: CGFloat
        if sections.isEmpty {
            content = BibleListLayerMetrics.emptyStateHeight
        } else {
            let rows = CGFloat(totalCount) * BibleListLayerMetrics.rowHeight
            let headers = CGFloat(sections.count) * BibleListLayerMetrics.sectionHeaderHeight
            content = rows + headers + BibleListLayerMetrics.listVerticalPadding
        }
        return min(chrome + content, BibleListLayerMetrics.historyMaxHeight)
    }

    /// 오늘/어제/그저께는 시분초만, 이번주/지난주/이번달은 날짜+시분을 보여준다.
    private func timeLabel(for entry: BibleReadingHistoryEntry, bucket: HistoryDateBucket) -> String {
        switch bucket {
        case .today, .yesterday, .dayBeforeYesterday:
            return Self.timeOnlyFormatter.string(from: entry.viewedAt)
        case .thisWeek, .lastWeek, .thisMonth:
            return Self.dateTimeFormatter.string(from: entry.viewedAt)
        }
    }

    /// `entry.verse`가 있으면(확대보기/사이드바 검색으로 절까지 직접 이동한 경우) "장:절",
    /// 없으면(책/장 단위 이동) "장"으로 보여준다.
    private func bookChapterLabel(for entry: BibleReadingHistoryEntry) -> String {
        guard let book = BooksProvider.shared.book(id: entry.bookId) else {
            if let verse = entry.verse {
                return "책 \(entry.bookId) \(entry.chapter):\(verse)"
            }
            return "책 \(entry.bookId) \(entry.chapter)장"
        }
        if let verse = entry.verse {
            return "\(book.nameKo) \(entry.chapter):\(verse)"
        }
        return "\(book.nameKo) \(entry.chapter)장"
    }
}
