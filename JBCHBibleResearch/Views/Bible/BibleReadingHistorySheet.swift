//
//  BibleReadingHistorySheet.swift
//  JBCHBibleResearch
//
//  S1 툴바에서 시트로 띄우는 성경 조회 이력 화면. 항목을 탭하면 그 책/장으로 이동한 뒤
//  시트를 닫는다(다시 조회한 것이므로 그 이동도 새 이력으로 기록된다 —
//  `BibleReadingViewModel.jumpToHistoryEntry` 참고).
//
//  최근 1개월 이력(`BibleReadingViewModel.fetchHistory()`가 필터링)을 오늘/어제/그저께/
//  이번주/지난주/이번달로 그룹핑해 보여준다. 그룹 판정은 `Calendar.current`의 day 기준
//  판정을 한 곳에 모아 항목 하나가 정확히 한 버킷에만 들어가게 한다
//  (`SidebarNavigationView.quickItemDateBucket(for:)`와 같은 원칙).
//
//  시각 표기는 버킷에 맞춘다 — 오늘/어제/그저께는 섹션 헤더가 날짜를 알려주므로 시분초만,
//  이번주/지난주/이번달은 여러 날이 섞이므로 날짜+시분을 보여 한 줄에 들어가게 한다.
//
//  헤더는 시스템 내비게이션 바 대신 `BookmarkListPopover.header`/
//  `TranslationPickerPopover.header`와 같은 커스텀 헤더(제목 + 개수 배지 + 원형 닫기 버튼)를
//  쓴다 — 시스템 내비게이션 바는 실제 배경이 아니라 앱 전체 라이트/다크 모드만 보고 타이틀
//  색을 정해 테마 배경과 어긋나기 때문이다.
//

import SwiftUI
import BibleResearchModels

struct BibleReadingHistorySheet: View {
    private var settings: UserSettingsStore { .shared }
    let viewModel: BibleReadingViewModel
    var onDismiss: () -> Void

    @State private var entries: [BibleReadingHistoryEntry] = []

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

    /// `entries`(이미 최신순 + 최근 1개월로 정리된 값)를 버킷별로 나눈다 — 각 버킷 내부에서도
    /// 최신순 정렬이 유지된다.
    private var groupedEntries: [(bucket: HistoryDateBucket, entries: [BibleReadingHistoryEntry])] {
        HistoryDateBucket.allCases.compactMap { bucket in
            let items = entries.filter { self.bucket(for: $0.viewedAt) == bucket }
            return items.isEmpty ? nil : (bucket, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            historyContentOrnamentalDivider
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("조회 이력이 없습니다", systemImage: "clock")
                } else {
                    List {
                        ForEach(groupedEntries, id: \.bucket) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    row(for: entry, bucket: group.bucket)
                                }
                            } header: {
                                sectionHeader(group.bucket.title)
                            }
                        }
                    }
                    // `.listStyle`을 지정하지 않으면 Section 헤더가 있는 List가 `.insetGrouped`에
                    // 가깝게 렌더링돼 행 여백이 넓어진다 — 다른 목록 화면과 같이 `.plain`을 명시한다.
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(settings.bibleBackgroundColor ?? Color.clear)
                    // 임의의 테마 배경 위에서도 행 구분선이 배경과 대비되도록 한다.
                    .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.15))
                }
            }
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .onAppear {
            // 시트를 열 때마다 새로 불러온다 — 다른 창에서 쌓인 이력까지 반영하기
            // 위해 캐싱하지 않는다.
            entries = viewModel.fetchHistory()
        }
    }

    /// `BookmarkListPopover.header`와 같은 구조(제목 + 개수 배지 + 원형 닫기). 개수 배지는
    /// 비어 있을 때 숨긴다 — 그 자리는 `ContentUnavailableView`가 대신 설명한다.
    private var header: some View {
        HStack(spacing: 6) {
            Text("조회 이력")
                .font(.headline)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            if !entries.isEmpty {
                Text("\(entries.count)")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(settings.bibleTextColor?.opacity(0.12) ?? Color.secondary.opacity(0.15), in: Capsule())
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        // 이 헤더는 시트 맨 위에 붙어 상태바 여유가 없으므로 위쪽만 더 띄운다
        // (아래는 이어지는 구분선이 자체 세로 패딩을 갖는다).
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// 가로선-`sparkle`-가로선(wood 톤) 장식 구분선. `SearchView.menuContentOrnamentalDivider`와
    /// 같은 모양이지만 그쪽이 `private`라 이 파일에 따로 둔다.
    private var historyContentOrnamentalDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.45) ?? Color.secondary)
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    /// 시계 아이콘 + 제목 + 가로선 형태의 섹션 헤더. 가로선 색은 `List`의
    /// `.listRowSeparatorTint`와 같은 wood 계열이다.
    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(Color("AccentColor"))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
        }
        .textCase(nil)
    }

    /// `BookmarkListPopover.row(for:)`와 같은 원칙 — 제목은 왼쪽에, 시각은 오른쪽 끝으로 보내
    /// 한 줄에 담는다. 성경 구절은 `Color("AccentColor")`로 강조하고, 탭하면 이동한다는 것을
    /// `chevron.right`로 알린다.
    private func row(for entry: BibleReadingHistoryEntry, bucket: HistoryDateBucket) -> some View {
        Button {
            viewModel.jumpToHistoryEntry(entry)
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Text(bookChapterLabel(for: entry))
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color("AccentColor"))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(timeLabel(for: entry, bucket: bucket))
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.4) ?? Color.secondary.opacity(0.6))
            }
            .padding(.vertical, 11)
            .padding(.leading, 10)
            // `DocumentRowView.documentRowLabel`의 "책등" 강조선 패턴. 색은 같은 행의 구절
            // 텍스트가 쓰는 `Color("AccentColor")`로 통일한다.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color("AccentColor"))
                    .frame(width: 3)
                    .padding(.vertical, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // `body`의 `.background(bibleBackgroundColor)`는 List 컨테이너 배경만 바꾸고 각 행
        // 셀 배경은 투명하게 만들지 않는다.
        .listRowBackground(Color.clear)
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
