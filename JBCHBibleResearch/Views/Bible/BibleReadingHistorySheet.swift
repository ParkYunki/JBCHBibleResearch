//
//  BibleReadingHistorySheet.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설] 사용자 요청 — "조회 이력(히스토리) 기능 추가 (년월일 시분초),
//  100개의 조회한 성경과 장의 이력을 저장하고 조회할 수 있도록". S1 툴바에서 시트로
//  띄운다. 항목을 탭하면 그 책/장으로 이동한 뒤 시트를 닫는다(다시 조회한 것이므로
//  그 이동 자체도 새 이력으로 기록된다 — BibleReadingViewModel.jumpToHistoryEntry
//  상단 주석 참고).
//
//  [2026-09-04 재설계] 사용자 요청 — "성경 장절 밑에 조회 일시 시분초가 있음.
//  두줄로 표시하지 말고 한줄로 표시하되, 해당 리스트를 디자인에 맞춰서
//  심미성을 갖출것. + 조회이력은 한달까지의 이력을 보여줄것. + 조회이력을
//  오늘/어제/그저께/이번주/지난주/이번달 로 그룹핑할 것." 세 가지를 반영했다.
//  (1) 행을 `BookmarkListPopover.row(for:)`와 같은 원칙(제목 왼쪽, 시각
//  오른쪽 정렬 한 줄)으로 바꿨다 — 이 팝업과 책갈피 팝업이 같은 화면 계열
//  (S1 상단 조회 관련 목록)이라 같은 시각 언어를 쓰는 편이 일관적이다.
//  (2) 1개월 필터는 `BibleReadingViewModel.fetchHistory()`(그쪽 주석 참고)에서
//  건다 — 저장 상한(100개) 자체는 손대지 않았다.
//  (3) 그룹핑 판정은 `SidebarNavigationView.quickItemDateBucket(for:)`(오늘/
//  어제/그저께/이번주/이전 5단)과 같은 원칙(`Calendar.current`의 day 기준
//  판정을 한 곳에 모아 항목 하나가 정확히 한 버킷에만 들어가게 함)을 그대로
//  따르되, "이번주"를 "이번주/지난주"로 더 세분화하고 "이전" 대신 "이번달"로
//  마무리했다(1개월 필터와 맞물려 자연스러운 상한 역할도 겸한다).
//  행의 시각 표기도 버킷에 맞게 나눴다 — 오늘/어제/그저께는 섹션 헤더가 이미
//  날짜를 알려주므로 시분초만("18:53:02"), 이번주/지난주/이번달은 여러 날이
//  섞이므로 날짜+시분("9월 1일 18:53")을 보여준다. "년월일 시분초"라는 원래
//  요청은 살아있되(가장 최근인 오늘/어제/그저께에서 초 단위까지 정확히
//  보인다), 그룹 안에서 날짜를 반복 표시하지 않아 한 줄에 자연스럽게 들어간다.
//

import SwiftUI
import BibleResearchModels

struct BibleReadingHistorySheet: View {
    let viewModel: BibleReadingViewModel
    var onDismiss: () -> Void

    @State private var entries: [BibleReadingHistoryEntry] = []

    /// [2026-09-04 신설] 위 파일 상단 재설계 주석 참고 — 오늘/어제/그저께
    /// 행처럼 섹션 헤더가 이미 날짜를 알려주는 경우, 시분초만 보여준다.
    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    /// [2026-09-04 신설] 이번주/지난주/이번달처럼 한 섹션에 여러 날짜가
    /// 섞이는 경우, 날짜+시분을 보여준다(초 단위는 오늘/어제/그저께만큼
    /// 중요하지 않아 생략 — 한 줄에 들어가야 하는 폭 제약도 있다).
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    /// [2026-09-04 신설] `SidebarNavigationView.SidebarQuickItemDateBucket`과
    /// 같은 원칙(항목 하나가 정확히 한 버킷에만 들어가도록 판정을 한 곳에
    /// 모음)이되, 이 화면 요구사항(오늘/어제/그저께/이번주/지난주/이번달
    /// 6단)에 맞춰 케이스를 다시 짰다.
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
        // [2026-09-04 신설] "이번주"는 오늘이 속한 캘린더 주(로케일의 첫 요일
        // 기준, `Calendar.current`가 이미 사용자 설정을 반영한다)의 시작일
        // 이후 전부, "지난주"는 그 바로 앞 7일 구간이다.
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start
            ?? calendar.startOfDay(for: .now)
        if date >= thisWeekStart { return .thisWeek }
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
        if date >= lastWeekStart { return .lastWeek }
        return .thisMonth
    }

    /// `entries`(이미 `BibleReadingViewModel.fetchHistory()`가 최신순 +
    /// 최근 1개월로 정리해 준 값)를 버킷별로 나눈다 — 각 버킷 내부에서도
    /// `entries`의 최신순 정렬이 그대로 유지된다.
    private var groupedEntries: [(bucket: HistoryDateBucket, entries: [BibleReadingHistoryEntry])] {
        HistoryDateBucket.allCases.compactMap { bucket in
            let items = entries.filter { self.bucket(for: $0.viewedAt) == bucket }
            return items.isEmpty ? nil : (bucket, items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("조회 이력이 없습니다", systemImage: "clock")
                } else {
                    List {
                        ForEach(groupedEntries, id: \.bucket) { group in
                            // [2026-09-05 수정] 사용자 요청 — "조회이력 -
                            // 그룹핑하는 타이틀 크기를 좀더 크고 명확하게
                            // 하되 디자인 가이드를 준수하여 심미성을 갖춰
                            // 디자인하라." 기존 `Section(group.bucket.title)`
                            // (문자열 이니셜라이저)은 시스템 기본 헤더 스타일
                            // (작고 옅은 회색, iOS에서는 대문자 변환)이라
                            // "오늘/어제/이번주" 같은 그룹 구분이 눈에 잘 안
                            // 띄었다 — `BookChapterPicker.testamentSection`이
                            // 이미 쓰는 "제목 텍스트 + 커스텀 폰트" 패턴을
                            // 재사용하되(근거 없는 새 스타일 발명 대신 기존
                            // 패턴 재사용), 그 화면의 `.headline`보다 한 단계
                            // 큰 `.title3`으로 올려 "더 크고 명확하게"라는
                            // 요청을 반영했다. `.textCase(nil)`로 시스템
                            // 기본 대문자 변환을 꺼서 지정한 폰트 크기·굵기가
                            // 그대로 보이게 했다.
                            Section {
                                ForEach(group.entries) { entry in
                                    row(for: entry, bucket: group.bucket)
                                }
                            } header: {
                                Text(group.bucket.title)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("조회 이력")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: onDismiss)
                }
            }
        }
        .onAppear {
            // 시트를 열 때마다 새로 불러온다 — 다른 창에서 쌓인 이력까지 반영하기
            // 위해 캐싱하지 않는다(BibleReadingViewModel.fetchHistory 상단 주석 참고).
            entries = viewModel.fetchHistory()
        }
    }

    /// [2026-09-04 신설] `BookmarkListPopover.row(for:)`와 같은 원칙 — 제목은
    /// 왼쪽에, 시각은 오른쪽 끝으로 보내 한 줄 안에서 가로 공간을 마저 쓴다.
    private func row(for entry: BibleReadingHistoryEntry, bucket: HistoryDateBucket) -> some View {
        Button {
            viewModel.jumpToHistoryEntry(entry)
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Text(bookChapterLabel(for: entry))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(timeLabel(for: entry, bucket: bucket))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// [2026-09-04 신설] 위 파일 상단 재설계 주석 참고 — 오늘/어제/그저께는
    /// 섹션 헤더가 날짜를 이미 알려주므로 시분초만, 이번주/지난주/이번달은
    /// 날짜+시분을 보여준다.
    private func timeLabel(for entry: BibleReadingHistoryEntry, bucket: HistoryDateBucket) -> String {
        switch bucket {
        case .today, .yesterday, .dayBeforeYesterday:
            return Self.timeOnlyFormatter.string(from: entry.viewedAt)
        case .thisWeek, .lastWeek, .thisMonth:
            return Self.dateTimeFormatter.string(from: entry.viewedAt)
        }
    }

    /// [2026-08-26 수정] 사용자 요청 — "히스토리 이력에 장절까지 기록을 남겨둘것."
    /// `entry.verse`가 있으면(확대보기/사이드바 검색으로 절까지 직접 이동한 경우)
    /// "장:절"로, 없으면(책/장 단위 이동) 기존처럼 "장"으로 보여준다.
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
