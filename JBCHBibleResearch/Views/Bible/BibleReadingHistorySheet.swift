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
//  [2026-09-12 3차 재설계] 사용자가 목업(history-crossref-mockup.html —
//  "조회 이력 · 관주 팝업 재설계 목업")을 검토하고 "이대로 구현할 것"이라고
//  확정한 내용을 그대로 옮겼다. 핵심은 시스템 `.navigationTitle` + `.toolbar`를
//  걷어내고 `BookmarkListPopover.header`/`TranslationPickerPopover.header`와
//  똑같은 커스텀 헤더(제목 + 개수 배지 + 원형 닫기 버튼)로 바꾼 것 — 이
//  세션에서만 `BibleReadingView`/`SearchView`/`WordNoteHomeView`/
//  `DocumentsHomeView` 네 화면이 반복해서 겪은 "시스템 내비게이션 바는 실제
//  배경이 아니라 앱 전체 라이트/다크 모드만 보고 타이틀 색을 정한다"는 문제
//  (`ThemedNavigationBarBackgroundModifier`를 화면마다 복제해 patch해 온 것)가
//  이 화면에도 그대로 나타났었는데(직전 커밋, 사용자 재보고 "타이틀 흰색
//  고정"), 두 팝업은 애초에 진짜 시스템 내비게이션 바가 아니라 평범한 `Text`를
//  직접 그리기 때문에 이 문제 자체가 없다 — 패치 대신 그 구조를 그대로
//  따라가 문제가 구조적으로 재발할 수 없게 했다. 그래서 `NavigationStack`/
//  `.navigationTitle`/`.toolbar`/`ThemedNavigationBarBackgroundModifier`
//  (직전 커밋에서 추가했던 것)를 전부 걷어냈다 — 더 쓰는 곳이 없어 그 구조체
//  정의도 이 파일에서 삭제했다. 그 외 섹션 헤더(시계 아이콘 + 가로선 추가)와
//  행(성경 구절을 `Color("AccentColor")`로 강조, 이동 가능함을 알리는
//  chevron 추가)도 목업 그대로 반영했다 — 자세한 근거는 각 프로퍼티 주석 참고.
//
//  [2026-09-12 4차 수정] 사용자 재보고 — "①상단 타이틀 위 여백을 좀더
//  여유롭게. ②타이틀 밑에 이미지 구분선 추가. ③리스트 각 행에 연구문서
//  최근문서처럼 왼쪽 색상바 추가 + 구분선을 더 흐리게." 세 가지 다 반영했다.
//  (1) `header`의 위쪽 패딩만 16→16 그대로 두지 않고 세로 패딩을 위/아래로
//  나눠 위쪽을 더 띄웠다(아래 `header` 주석 참고) — 목업(phone-statusbar
//  38pt + sheet-header 자체 패딩)에는 원래도 상태바만큼의 여유가 있었는데,
//  실제 구현은 이 헤더가 시트 맨 위에 바로 붙어(상태바가 없다) 그 여유가
//  사라져 보였다.
//  (2) `Divider()` 대신 `SearchView.menuContentOrnamentalDivider`/
//  `DocumentsHomeView.searchContentOrnamentalDivider`/`WordNoteHomeView.
//  wordNoteContentOrnamentalDivider`와 완전히 같은 모양(가로선-`sparkle`-
//  가로선, wood 톤)의 장식 구분선을 옮겨왔다 — 그 프로퍼티들은 전부
//  `private`라 이 파일에서 직접 재사용은 못 하고 그대로 옮겨 적는다.
//  (3) `row(for:)`에 `DocumentRowView.documentRowLabel`의 "책등" 패턴
//  (`RoundedRectangle().fill(색).frame(width: 3)`, 왼쪽 모서리)을 그대로
//  가져왔다 — 다만 그 파일은 색을 고를 때 배경 밝기(WCAG 상대휘도)를 다시
//  재는 별도 계산(`accentSpineColor`)을 쓰는데, 이 화면은 이미 같은 행에서
//  성경 구절 자체를 `Color("AccentColor")`로 강조하고 있어(위 3차 재설계
//  주석 참고) 책등 색도 같은 `Color("AccentColor")`로 통일했다 — 새 색을
//  하나 더 들여오는 대신, 이미 이 행 안에 있는 강조색을 재사용한 것뿐이라
//  일관성이 더 높다고 판단했다. 구분선은 기존 0.3 → 0.15로 낮춰 더 흐리게
//  했다(사용자 요청 "구분선도 좀더 흐리게").
//

import SwiftUI
import BibleResearchModels

struct BibleReadingHistorySheet: View {
    /// [2026-09-11 추가] 사용자 보고 — "성경 - 조회이력"이 테마를 안 따름.
    private var settings: UserSettingsStore { .shared }
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
        VStack(alignment: .leading, spacing: 0) {
            header
            historyContentOrnamentalDivider
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("조회 이력이 없습니다", systemImage: "clock")
                } else {
                    // [2026-09-11 추가] 위 `settings` 선언부 주석 참고 —
                    // `BookmarkListPopover.list`와 같은 이유·같은 패턴.
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
                    // [2026-09-12 추가] 사용자 보고 — "성경-히스토리 리스트
                    // 행간 간격이 너무 넓음. 리스트 행 디자인도 통일성을
                    // 맞출 수 있도록." 원인: 이 `List`만 유일하게 `.listStyle`을
                    // 지정하지 않고 있었다 — `SearchView.swift`의 같은 날짜
                    // 주석에 있듯, 이 코드베이스의 다른 목록 화면들
                    // (`WordNoteHomeView`, `VerseMentionListView`,
                    // `BookmarkListPopover`, `CrossReferenceTargetPicker`,
                    // `OutlineTreeView`, `DocumentsHomeView`, `SearchView`)은
                    // 전부 이미 `.listStyle(.plain)`을 명시하고 있고, 이 화면만
                    // 예외였다. 지정하지 않으면 시스템 기본값(`.automatic`)이
                    // 적용되는데, `Section` 헤더가 있는 `List`에서는 이게
                    // `.insetGrouped`에 가까운 모양으로 렌더링돼(행마다/섹션마다
                    // 추가 여백 존재) 같은 44pt 행(`row(for:)`의
                    // `.padding(.vertical, 11)` — `BookmarkListPopover.row(for:)`와
                    // 동일)인데도 실제로는 훨씬 더 넓어 보였다 — 새 스타일을
                    // 만드는 대신 이미 앱 전체에 자리 잡은 규칙을 그대로
                    // 명시했다.
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(settings.bibleBackgroundColor ?? Color.clear)
                    // [2026-09-12 추가] `WordNoteHomeView`/`OutlineTreeView`/
                    // `SearchView`와 같은 이유 — 임의의 테마 배경 위에서도
                    // 행 구분선이 항상 배경과 대비되도록.
                    .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.15))
                }
            }
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .onAppear {
            // 시트를 열 때마다 새로 불러온다 — 다른 창에서 쌓인 이력까지 반영하기
            // 위해 캐싱하지 않는다(BibleReadingViewModel.fetchHistory 상단 주석 참고).
            entries = viewModel.fetchHistory()
        }
    }

    /// [2026-09-12 3차 재설계] 위 파일 상단 주석 참고 — `BookmarkListPopover.header`와
    /// 완전히 같은 구조(제목 + 개수 배지 + 원형 닫기)를 그대로 옮겼다. 개수
    /// 배지는 `BookmarkListPopover.header`와 같은 이유로 비어 있을 때는
    /// 숨긴다(0개짜리 배지는 정보 가치가 없다 — 그 자리는 이미
    /// `ContentUnavailableView`가 대신 설명한다).
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
        // [2026-09-12 4차 수정] 위 파일 상단 주석 참고 — 위쪽만 더 띄운다
        // (아래는 바로 이어지는 `historyContentOrnamentalDivider`가 자체
        // 세로 패딩을 갖고 있어 그대로 둔다).
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// [2026-09-12 4차 수정] 위 파일 상단 주석 참고 — `SearchView.
    /// menuContentOrnamentalDivider`(통합검색, 원본)와 완전히 같은 모양
    /// (가로선-`sparkle`-가로선, wood 톤)을 옮겨왔다 — 그 프로퍼티는
    /// `SearchView`에 `private`라 이 파일에서 직접 재사용은 못 하고 그대로
    /// 옮겨 적는다.
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

    /// [2026-09-12 3차 재설계] 위 파일 상단 주석 참고 — 목업의 "시계 아이콘 +
    /// 가로선"을 그대로 옮겼다. 시계 아이콘은 이미 빈 상태 안내
    /// (`ContentUnavailableView(..., systemImage: "clock")`)에 쓰고 있는
    /// 아이콘을 재사용해 "이력 화면"이라는 성격을 한 번 더 알려준다. 가로선
    /// 색은 바로 아래 `List`의 `.listRowSeparatorTint`와 정확히 같은 값
    /// (`JBCHCategoryPalette.wood.opacity(0.3)`)을 써서 구분선과 시각적으로
    /// 한 계열로 읽힌다.
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

    /// [2026-09-04 신설] `BookmarkListPopover.row(for:)`와 같은 원칙 — 제목은
    /// 왼쪽에, 시각은 오른쪽 끝으로 보내 한 줄 안에서 가로 공간을 마저 쓴다.
    ///
    /// [2026-09-12 3차 재설계] 위 파일 상단 주석 참고 — 성경 구절을
    /// `Color("AccentColor")`로 굵게 강조해 이 행의 "주인공"이 무엇인지
    /// 분명히 했다(목업의 `--app-accent`는 실제로 이 `AccentColor` 에셋
    /// 값 그대로다). 끝에 `chevron.right`를 더해 탭하면 이동한다는 걸
    /// 알린다 — 이 행이 이미 `Button`이라 실제로 탭 가능한 게 맞으므로,
    /// 없는 기능을 있는 것처럼 보이게 하는 게 아니라 이미 있는 기능을
    /// 드러내는 장치다.
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
            // [2026-09-12 4차 수정] 위 파일 상단 주석 참고 —
            // `DocumentRowView.documentRowLabel`의 "책등" 강조선 패턴을
            // 그대로 가져왔다(그 파일 주석 — 원래 `TranslationColumnView.
            // VerseRow`의 선택 강조선에서 온 것과 같은, 이미 검증된 패턴).
            // 색은 그쪽처럼 배경 밝기를 다시 재는 대신, 이 행이 이미 쓰는
            // 강조색(`Color("AccentColor")`, 위 구절 텍스트)을 그대로
            // 재사용했다 — 한 행 안에서 색이 하나로 통일된다.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color("AccentColor"))
                    .frame(width: 3)
                    .padding(.vertical, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // [2026-09-12 추가] 사용자 재보고 — "성경-히스토리 디자인도 테마에
        // 맞도록 수정할것." `OutlineTreeView`/`WordNoteHomeView`가 이미
        // 겪은 것과 같은 누락 — 위 `body`의 `.background(bibleBackgroundColor)`
        // 는 List "컨테이너"의 배경만 바꾸지, 각 행 셀 자체의 배경까지
        // 자동으로 투명하게 만들어주지는 않는다.
        .listRowBackground(Color.clear)
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
