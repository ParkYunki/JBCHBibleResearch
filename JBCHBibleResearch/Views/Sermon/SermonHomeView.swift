//
//  SermonHomeView.swift
//  JBCHBibleResearch
//
//
//  S-SER1 "내 설교 목록". [말씀 단위 묶음]/[날짜별] 두 보기 방식을 토글하며,
//  같은 데이터(Sermon + SermonDelivery)를 다르게 조회할 뿐이라 스키마 변경은 없다.
//
//  진입점: iOS는 "더보기" 목록의 "내 설교" 행에서 `.fullScreenCover`로 연다. 이 화면은
//  `.searchable`을 쓰는데, 이미 중첩된 NavigationStack 안에서 `.searchable`이 활성인 채
//  더 push하는 조합은 구조적으로 깨지기 때문이다(`SearchView.swift` 상단 주석 참고).
//  iPad/macOS는 사이드바 "연구문서" 아래 "내 설교" 항목이며, `NavigationSplitView`의
//  detail 컬럼이 단독 `NavigationStack`이라 안전하다.
//
//  레이아웃: 아이폰은 말씀단위/날짜별 토글 + 단일 목록에서 상세로 push한다. 아이패드·맥은
//  `DocumentsHomeView.splitMainContent`와 같은 패턴(HStack + 고정폭 왼쪽 열)으로
//  왼쪽 "설교함"(말씀단위 목록), 오른쪽 상세(`SermonDetailView`)를 제자리에 보여준다.
//
//  새 설교: 툴바의 "설교 작성" 아이콘으로 연다. 아이패드·맥은 새 창("sermon-new", `SermonNewWindowContent`)에서, 아이폰은 같은
//  NavigationStack에 push해 `SermonEditorView`(`isNewSermon: true`)를 보인다. 제목과 본문이
//  모두 비면 저장하지 않으며 그 검증은 `SermonEditorView.save()`가 맡는다. 수정일은
//  저장 시 `touchUpdatedAt()`이 현재 시각으로 넣는다. 설교 편집(왼쪽 설교함의 "편집")도 아이패드·맥은 새 창("sermon-editor")이다.
//
//  ⚠️ `JBCHBibleResearchApp.swift`의 `WindowGroup(id: "sermon-detail", ...)` 등록은 이
//  화면에서 더 이상 호출하지 않지만 다른 곳에서 참조할 수 있어 남겨 두었다.
//

import SwiftUI
import Combine
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

private enum SermonListViewMode: String, CaseIterable {
    case bySermon = "설교별"
    case byGathering = "모임별"
    case byDate = "날짜별"
}

/// 목록 정렬 기준 — 세 보기(설교별/모임별/날짜별) 모두 같은 기준을 쓴다. 항상 최신이 위.
/// 설교별·모임별은 `Sermon`의 `updatedAt`/`createdAt`, 날짜별은 각 사용 이력(`SermonDelivery`)의 `updatedAt`/`createdAt`.
private enum SermonListSort: String, CaseIterable {
    case recentlyEdited = "최근 수정"
    case recentlyCreated = "최근 등록"
}

/// 내 설교 목록 글자. 아이폰·아이패드는 텍스트 스타일(동적 글자 크기를 따름)을 쓰고,
/// 맥은 같은 텍스트 스타일이 훨씬 작아(footnote 10pt, callout 12pt) 읽기 어려워 고정 pt로 키운다.
private enum ListFonts {
    #if os(macOS)
    static let rowTitle = Font.system(size: 15, weight: .bold)
    static let rowTitleMedium = Font.system(size: 15, weight: .semibold)
    static let meta = Font.system(size: 13)
    static let metaBold = Font.system(size: 13, weight: .bold)
    static let control = Font.system(size: 13, weight: .semibold)
    static let pill = Font.system(size: 13, weight: .bold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let small = Font.system(size: 12)
    static let empty = Font.system(size: 14)
    static func chip(isSelected: Bool) -> Font { .system(size: 13, weight: isSelected ? .bold : .regular) }
    #else
    static let rowTitle = Font.callout.weight(.bold)
    static let rowTitleMedium = Font.callout.weight(.semibold)
    static let meta = Font.footnote
    static let metaBold = Font.footnote.weight(.bold)
    static let control = Font.footnote.weight(.semibold)
    static let pill = Font.footnote.weight(.bold)
    static let sectionTitle = Font.title3.weight(.semibold)
    static let small = Font.caption
    static let empty = Font.body
    static func chip(isSelected: Bool) -> Font { .footnote.weight(isSelected ? .bold : .regular) }
    #endif
}

/// 모임 필터 칩이 가리키는 대상. 모임은 이름 비교 키(`SermonGatheringSeeder.normalizedKey`)로 구분한다 —
/// 기기끼리 동기화로 같은 이름의 모임 행이 둘 생겨도(`deduplicate`가 정리하기 전) 한 칩으로 합쳐 센다.
private enum GatheringFilter: Hashable {
    case all
    case gathering(String)
    /// 모임이 지정되지 않은 사용 이력이 있는 설교.
    case unassigned
    /// 사용 이력이 하나도 없는 설교(설교별 보기에서만).
    case unused
}

private struct GatheringChip: Identifiable {
    let filter: GatheringFilter
    let label: String
    let count: Int
    var id: GatheringFilter { filter }
}

private struct GatheringSection: Identifiable {
    let id: String
    let title: String
    let filter: GatheringFilter
    let sermons: [Sermon]
    /// 이 모임에서 쓴 총 횟수(같은 설교를 여러 번 쓴 것 포함).
    let totalCount: Int
}

/// 행 오른쪽 아이콘 버튼 — 눌림 때 살짝 흐려지는 것 외에는 꾸밈이 없다.
private struct SermonRowIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}


/// 배경색에 맞춰 내비게이션 바(macOS는 창 툴바) 배경과 색 구성을 정하는 모디파이어.
/// 다른 파일의 internal 동명 선언과 충돌하지 않도록 파일마다 `private`로 중복 선언한다
/// (파일 최상위 `private`과 다른 파일의 internal 동명 선언은 같은 모듈에서 이름 충돌).
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
        } else {
            content
        }
        #elseif os(macOS)
        // macOS는 `.navigationBar`가 없어 macOS 전용 `.windowToolbar`(macOS 13+)로
        // 통합 툴바 배경을 맞춘다.
        if let color {
            content
                .toolbarBackground(color, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .windowToolbar)
        } else {
            content
        }
        #else
        content
        #endif
    }

    private static func isDarkBackground(_ color: Color, in environment: EnvironmentValues) -> Bool {
        let resolved = color.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance < 0.5
    }
}

struct SermonHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    /// 왼쪽 설교함 행의 Map/뷰어 버튼이 별도 창을 여는 데 쓴다.
    @Environment(\.openWindow) private var openWindow

    @State private var sermons: [Sermon] = []
    @State private var deliveries: [SermonDelivery] = []

    @State private var viewMode: SermonListViewMode = .bySermon
    @State private var searchText = ""
    /// (아이폰 전용) "새 설교" 버튼이 담는, 아직 `modelContext`에 insert하지 않은 `Sermon`. 아이폰은
    /// `.navigationDestination(item:)`으로 에디터를 push한다. 아이패드·맥은 새 창("sermon-new")을 열어 이 값을 쓰지 않는다.
    /// 실제 insert는 `SermonEditorView.save()`가 제목/본문 중 하나라도 채워졌을 때만 하므로 이 값은 화면 전환용일 뿐
    /// 데이터 등록과 무관하다.
    @State private var pendingNewSermon: Sermon?
    /// 메인 `Sermon` 삭제 확인 대화상자 대상. `Sermon.deliveries`/`verseReferences`가
    /// `.cascade`라(Sermons.swift) 삭제 시 이력·구절 레코드도 함께 사라지므로 확인 후 삭제한다.
    @State private var sermonPendingDelete: Sermon?
    /// 아이패드·맥 전용 — 왼쪽 "설교함"에서 고른 설교. 오른쪽 상세 패널이 이 값을 읽는다.
    @State private var selectedSermonID: PersistentIdentifier?
    /// "새 모임" 시트 대상. `.sheet(item:)`이라 nil이 아니면 그 설교에 대해 시트가 열린다.
    @State private var sermonPendingNewDelivery: Sermon?
    /// 모임 필터 칩에서 고른 대상. 보기 방식을 바꿔도 유지하되, "미사용"은 설교별 보기에만 있어 다른 보기로 가면 "전체"로 되돌린다.
    @State private var gatheringFilter: GatheringFilter = .all
    /// 정렬 기준 — 기기별로 기억한다. 처음엔 기존 순서(최근 수정)와 같다.
    @AppStorage("sermon.listSort") private var listSort: SermonListSort = .recentlyEdited
    @State private var gatherings: [SermonGathering] = []
    /// (아이패드·맥) 왼쪽 목록 폭 — 사용자가 분할선을 끌어 바꾸고 기기별로 기억한다.
    @AppStorage("sermon.listPaneWidth") private var listPaneWidth: Double = 600
    @State private var listWidthDragStart: Double?
    private static let listWidthRange: ClosedRange<Double> = 380...900
    /// 오른쪽 상세 패널이 최소한 이 폭은 갖도록 목록 폭 상한을 창 폭에 맞춰 줄인다.
    private static let detailMinWidth: Double = 320
    /// 이 폭 이상일 때만 모든 행에 아이콘 4개를 둔다(미만이면 선택한 행에서만).
    private static let rowActionsMinListWidth: Double = 440

    private var settings: UserSettingsStore { .shared }

    /// 설정의 성경 배경색에 맞춘 강조색.
    private var accent: Color {
        SermonTheme.accent(background: settings.bibleBackgroundColor, environment: environment, fallbackScheme: colorScheme)
    }

    /// 성경 배경색이 어두운지 여부(WCAG 상대휘도 < 0.5). 배경색이 없으면 시스템 colorScheme을 따른다.
    /// 아래 버튼 tint가 라이트/다크 팔레트 변형 중 어느 쪽을 쓸지 고르는 데 쓴다.
    private var isDarkSurface: Bool {
        if let background = settings.bibleBackgroundColor {
            let resolved = background.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            return luminance < 0.5
        }
        return colorScheme == .dark
    }

    /// 사이드바 행 버튼(모임/Map/편집) 전용 색. "뷰어" 버튼은 `accent`(wine)를 쓰므로 겹치지 않는
    /// `JBCHCategoryPalette` 색을 골랐다. gold는 OnDark 변형이 없어 피한다
    /// (`SermonMindMapView.resolvedColor` 주석 참고).
    private var joinButtonTint: Color { isDarkSurface ? JBCHCategoryPalette.navyOnDark : JBCHCategoryPalette.navy }
    private var mapButtonTint: Color { isDarkSurface ? JBCHCategoryPalette.slateTealOnDark : JBCHCategoryPalette.slateTeal }
    private var editButtonTint: Color { isDarkSurface ? JBCHCategoryPalette.woodOnDark : JBCHCategoryPalette.wood }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private var subtleText: Color { settings.bibleTextColor?.opacity(0.6) ?? Color.secondary }

    /// 강조색 위의 글자/아이콘색 — 어두운 배경에서는 강조색이 밝아 어두운 글자를 쓴다.
    private var onAccent: Color { isDarkSurface ? Color(white: 0.08) : Color.white }

    /// 검색어만 적용한 설교(모임 필터 전).
    private var searchFilteredSermons: [Sermon] {
        guard !searchText.isEmpty else { return sermons }
        return sermons.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.contentText.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// 정렬 기준에 따른 설교의 기준 시각.
    private func sortDate(_ sermon: Sermon) -> Date {
        listSort == .recentlyEdited ? sermon.updatedAt : sermon.createdAt
    }

    /// 정렬 기준에 따른 사용 이력의 기준 시각.
    private func sortDate(_ delivery: SermonDelivery) -> Date {
        listSort == .recentlyEdited ? delivery.updatedAt : delivery.createdAt
    }

    /// 선택한 정렬 기준(최근 수정/최근 등록, 최신이 위)으로 설교를 정렬한다.
    private func sortedSermons(_ items: [Sermon]) -> [Sermon] {
        items.sorted { sortDate($0) > sortDate($1) }
    }

    /// 검색어 + 모임 필터 + 정렬. 모임을 골라도 순서는 선택한 정렬 기준을 따른다(그 모임에 쓴 설교만 남긴다).
    private var filteredSermons: [Sermon] {
        let base = searchFilteredSermons
        let filtered: [Sermon]
        switch gatheringFilter {
        case .all:
            filtered = base
        case .unused:
            filtered = base.filter { ($0.deliveries ?? []).isEmpty }
        case .gathering, .unassigned:
            filtered = base.filter { !sermonDeliveries($0, in: gatheringFilter).isEmpty }
        }
        return sortedSermons(filtered)
    }

    private var filteredDeliveries: [SermonDelivery] {
        let base: [SermonDelivery]
        if searchText.isEmpty {
            base = deliveries
        } else {
            base = deliveries.filter { delivery in
                (delivery.sermon?.title.localizedCaseInsensitiveContains(searchText) ?? false)
                    || delivery.contentText.localizedCaseInsensitiveContains(searchText)
            }
        }
        let filtered: [SermonDelivery]
        switch gatheringFilter {
        case .all, .unused: filtered = base
        case .gathering(let key): filtered = base.filter { gatheringKey(of: $0) == key }
        case .unassigned: filtered = base.filter { gatheringKey(of: $0) == nil }
        }
        return filtered.sorted { sortDate($0) > sortDate($1) }
    }

    // MARK: 모임 필터 계산

    /// 이 사용 이력의 모임 키. 모임이 없거나 이름이 비면 nil(= 모임 미지정).
    private func gatheringKey(of delivery: SermonDelivery) -> String? {
        guard let name = delivery.gathering?.name else { return nil }
        let key = SermonGatheringSeeder.normalizedKey(name)
        return key.isEmpty ? nil : key
    }

    /// 설교의 사용 이력(최근 순)을 필터 대상에 맞게 거른다. `.unused`는 사용 이력이 없는 설교를 뜻하므로 빈 배열이다.
    private func sermonDeliveries(_ sermon: Sermon, in filter: GatheringFilter) -> [SermonDelivery] {
        let all = (sermon.deliveries ?? []).sorted { $0.deliveredAt > $1.deliveredAt }
        switch filter {
        case .all: return all
        case .gathering(let key): return all.filter { gatheringKey(of: $0) == key }
        case .unassigned: return all.filter { gatheringKey(of: $0) == nil }
        case .unused: return []
        }
    }

    /// 칩으로 보일 모임 — 같은 이름은 하나로 합치고, 시드 순서(주일설교·청년회 말씀·구역모임·조모임) 다음 만든 순서로 둔다.
    private var gatheringOptions: [(key: String, name: String)] {
        let order = SermonGatheringSeeder.defaultNames
        let sorted = gatherings.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.name) ?? Int.max
            let right = order.firstIndex(of: rhs.name) ?? Int.max
            return left != right ? left < right : lhs.createdAt < rhs.createdAt
        }
        var seen = Set<String>()
        var result: [(key: String, name: String)] = []
        for gathering in sorted {
            let key = SermonGatheringSeeder.normalizedKey(gathering.name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append((key, gathering.name))
        }
        return result
    }

    /// 칩 옆 숫자 — 설교별/모임별 보기는 해당 모임을 쓴 설교 수, 날짜별 보기는 사용 이력 수.
    private func chipCount(for filter: GatheringFilter) -> Int {
        if viewMode == .byDate {
            switch filter {
            case .all, .unused: return deliveries.count
            case .gathering(let key): return deliveries.filter { gatheringKey(of: $0) == key }.count
            case .unassigned: return deliveries.filter { gatheringKey(of: $0) == nil }.count
            }
        }
        switch filter {
        case .all: return sermons.count
        case .unused: return sermons.filter { ($0.deliveries ?? []).isEmpty }.count
        case .gathering, .unassigned: return sermons.filter { !sermonDeliveries($0, in: filter).isEmpty }.count
        }
    }

    private var gatheringChips: [GatheringChip] {
        var chips = [GatheringChip(filter: .all, label: "전체", count: chipCount(for: .all))]
        for option in gatheringOptions {
            let filter = GatheringFilter.gathering(option.key)
            chips.append(GatheringChip(filter: filter, label: option.name, count: chipCount(for: filter)))
        }
        // 모임이 지정되지 않은 사용 이력이 있을 때만 보인다(숨은 데이터가 없도록).
        let unassignedCount = chipCount(for: .unassigned)
        if unassignedCount > 0 {
            chips.append(GatheringChip(filter: .unassigned, label: "모임 미지정", count: unassignedCount))
        }
        if viewMode == .bySermon {
            chips.append(GatheringChip(filter: .unused, label: "미사용", count: chipCount(for: .unused)))
        }
        return chips
    }

    /// 모임별 보기의 구역 — 모임마다 그 모임에서 쓴 설교를 선택한 정렬 기준으로. 고른 모임 칩이 있으면 그 모임만.
    private var gatheringSections: [GatheringSection] {
        var targets: [(id: String, title: String, filter: GatheringFilter)] = gatheringOptions.map {
            (id: $0.key, title: $0.name, filter: GatheringFilter.gathering($0.key))
        }
        targets.append((id: "unassigned", title: "모임 미지정", filter: GatheringFilter.unassigned))
        var sections: [GatheringSection] = []
        for target in targets {
            if gatheringFilter != .all, gatheringFilter != target.filter { continue }
            let entries: [(sermon: Sermon, latest: Date, count: Int)] = searchFilteredSermons.compactMap { sermon in
                let list = sermonDeliveries(sermon, in: target.filter)
                guard let latest = list.first else { return nil }
                return (sermon, latest.deliveredAt, list.count)
            }
            guard !entries.isEmpty else { continue }
            sections.append(GatheringSection(
                id: target.id,
                title: target.title,
                filter: target.filter,
                sermons: sortedSermons(entries.map { $0.sermon }),
                totalCount: entries.reduce(0) { $0 + $1.count }
            ))
        }
        return sections
    }

    private var selectedSermon: Sermon? {
        guard let selectedSermonID else { return nil }
        return sermons.first { $0.persistentModelID == selectedSermonID }
    }

    var body: some View {
        Group {
            if isPhoneIdiom {
                // 아이폰에서만 `.navigationDestination(item:)`으로 에디터를 push한다. 아이패드·맥은
                // 새 설교를 별도 창("sermon-new")으로 열기 때문에 push할 일이 없다.
                phoneContent
                    .navigationDestination(item: $pendingNewSermon) { sermon in
                        SermonEditorView(
                            subject: .sermon(sermon),
                            isNewSermon: true,
                            onRequestClose: { pendingNewSermon = nil }
                        )
                    }
            } else {
                splitContent
            }
        }
        .navigationTitle(SermonFixedTitle.navigationText)
        .macSerifTitle("내 설교")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        .onAppear { reloadLists() }
        .onChange(of: CloudSyncMonitor.shared.remoteImportRevision) { _, _ in
            reloadLists()
        }
        // 원격 완료 외에도 새 창/에디터에서 이 기기에 저장한 추가・삭제를 계속 반영한다.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
            reloadLists()
        }
        .onChange(of: viewMode) { _, newMode in
            // "미사용" 칩은 설교별 보기에만 있다.
            if newMode != .bySermon, gatheringFilter == .unused { gatheringFilter = .all }
        }
        .toolbar {
            #if os(iOS)
            // iOS 26(Liquid Glass)부터 툴바 항목은 자동으로 유리 캡슐 배경이 깔려 글자만 있는 제목도 버튼처럼 보인다.
            // 이 항목은 제목일 뿐이라 공유 배경을 숨긴다(`sharedBackgroundVisibility`, iOS 26+ — 배포 타깃 26.5).
            ToolbarItem(placement: .topBarLeading) { leftAlignedTitle }
                .sharedBackgroundVisibility(.hidden)
            #endif
            ToolbarItem(placement: .primaryAction) { composeButton }
        }
        .confirmationDialog(
            "이 설교를 삭제할까요?",
            isPresented: Binding(
                get: { sermonPendingDelete != nil },
                set: { isPresented in if !isPresented { sermonPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: sermonPendingDelete
        ) { sermon in
            Button("삭제", role: .destructive) { deleteSermon(sermon) }
            Button("취소", role: .cancel) {}
        } message: { sermon in
            let count = (sermon.deliveries ?? []).count
            Text(count > 0
                ? "이 설교와 활용 이력 \(count)건이 모두 삭제됩니다. 되돌릴 수 없습니다."
                : "이 설교가 삭제됩니다. 되돌릴 수 없습니다.")
        }
    }

    /// 목록만 다시 읽는다. 선택/필터를 유지하며 설교 상세의 편집 상태를 초기화하지 않는다.
    private func reloadLists() {
        do {
            let loadedSermons = try modelContext.fetch(
                FetchDescriptor<Sermon>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            )
            let loadedDeliveries = try modelContext.fetch(
                FetchDescriptor<SermonDelivery>(sortBy: [SortDescriptor(\.deliveredAt, order: .reverse)])
            )
            let loadedGatherings = try modelContext.fetch(FetchDescriptor<SermonGathering>())
            sermons = loadedSermons
            deliveries = loadedDeliveries
            gatherings = loadedGatherings
        } catch {
            print("[SermonHomeView] 목록 로드 실패: \(error)")
        }
    }

    // MARK: - 목록 공통 — 보기 방식 3종 / 모임 필터 칩 / 컴팩트 행 (2026-10-02 목업 채택)
    //
    // 아이폰·아이패드·맥이 같은 머리(보기 방식 + 모임 칩 + 건수)와 같은 컴팩트 행을 쓴다. 차이는 행을 눌렀을 때뿐이다:
    // 아이폰은 상세로 push, 아이패드·맥은 오른쪽 상세 패널에서 고른다(행 오른쪽 아이콘 4개는 아이패드·맥 전용).
    // 데이터는 그대로다 — 모임은 `SermonDelivery.gathering`, 날짜는 `deliveredAt`을 읽을 뿐 스키마 변경이 없다.

    /// 목록 머리 — [설교별 / 모임별 / 날짜별] + 모임 필터 칩 + 건수 안내.
    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            SermonSegmentedPill(
                items: [
                    .init(tag: SermonListViewMode.bySermon, label: SermonListViewMode.bySermon.rawValue),
                    .init(tag: SermonListViewMode.byGathering, label: SermonListViewMode.byGathering.rawValue),
                    .init(tag: SermonListViewMode.byDate, label: SermonListViewMode.byDate.rawValue),
                ],
                selection: $viewMode,
                accent: accent,
                font: ListFonts.pill
            )
            FlowLayoutHStack(spacing: 6) {
                ForEach(gatheringChips) { chip in
                    gatheringChipButton(chip)
                }
            }
            HStack(spacing: 8) {
                Text(listSummaryText)
                    .font(ListFonts.meta)
                    .foregroundStyle(subtleText)
                Spacer(minLength: 8)
                sortMenu
            }
        }
    }

    /// 정렬 메뉴 — "최근 수정 / 최근 등록" 두 가지. 세 보기 모두에 적용된다.
    private var sortMenu: some View {
        Menu {
            // Picker를 Menu 안에 넣으면 아이패드·맥에서 "정렬 ▸" 하위 메뉴로 한 단계 더 들어가게 되어, 버튼으로 바로 펼친다.
            ForEach(SermonListSort.allCases, id: \.self) { option in
                Button {
                    listSort = option
                } label: {
                    if listSort == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("정렬: \(listSort.rawValue)")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(ListFonts.control)
            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .overlay(Capsule().strokeBorder((settings.bibleTextColor ?? Color.primary).opacity(0.24), lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("정렬 기준")
        .accessibilityValue(listSort.rawValue)
    }

    private var listSummaryText: String {
        switch viewMode {
        case .bySermon:
            return "설교 \(filteredSermons.count)개" + (gatheringFilter == .all ? "" : " · 필터 적용")
        case .byGathering:
            let sections = gatheringSections
            let sermonCount = Set(sections.flatMap { $0.sermons.map(\.persistentModelID) }).count
            return "모임 \(sections.count)곳 · 설교 \(sermonCount)개"
        case .byDate:
            return "사용 이력 \(filteredDeliveries.count)건"
        }
    }

    private func gatheringChipButton(_ chip: GatheringChip) -> some View {
        let isSelected = gatheringFilter == chip.filter
        let textColor = settings.bibleTextColor ?? Color.primary
        #if os(iOS)
        let height: CGFloat = 34
        #else
        let height: CGFloat = 32
        #endif
        return Button {
            gatheringFilter = chip.filter
        } label: {
            HStack(spacing: 4) {
                Text(chip.label)
                Text("\(chip.count)")
                    .foregroundStyle(isSelected ? onAccent.opacity(0.85) : subtleText)
            }
            .font(ListFonts.chip(isSelected: isSelected))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: height)
            .foregroundStyle(isSelected ? onAccent : textColor)
            .background(Capsule().fill(isSelected ? accent : Color.clear))
            .overlay(Capsule().strokeBorder(isSelected ? accent : textColor.opacity(0.24), lineWidth: 1))
            // 선택 안 된 칩은 배경이 투명이라 .plain 버튼에서 글자 위만 눌린다 — 칩 전체를 누름 영역으로 둔다.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 보기 방식에 맞는 목록 본문. `isSplit`이면 아이패드·맥(행 선택 = 오른쪽 상세), 아니면 아이폰(행 = push).
    @ViewBuilder
    private func listRows(isSplit: Bool, showsRowActions: Bool) -> some View {
        switch viewMode {
        case .bySermon:
            let items = filteredSermons
            if items.isEmpty {
                emptyState(text: emptyListMessage)
            } else {
                ForEach(items) { sermon in
                    sermonEntry(sermon, scope: gatheringFilter, showsDates: false, isSplit: isSplit, showsRowActions: showsRowActions)
                }
            }
        case .byGathering:
            let sections = gatheringSections
            if sections.isEmpty {
                emptyState(text: emptyListMessage)
            } else {
                ForEach(sections) { section in
                    gatheringHeader(section)
                    ForEach(section.sermons) { sermon in
                        sermonEntry(sermon, scope: section.filter, showsDates: true, isSplit: isSplit, showsRowActions: showsRowActions)
                    }
                }
            }
        case .byDate:
            let items = filteredDeliveries
            if items.isEmpty {
                emptyState(text: emptyListMessage)
            } else {
                ForEach(items) { delivery in
                    if isSplit {
                        splitDeliveryRow(delivery)
                    } else {
                        deliveryRow(delivery)
                    }
                }
            }
        }
    }

    private var emptyListMessage: String {
        if viewMode == .byDate {
            return deliveries.isEmpty ? "아직 사용 이력이 없습니다." : "조건에 맞는 사용 이력이 없습니다."
        }
        return sermons.isEmpty ? "아직 등록한 설교가 없습니다." : "조건에 맞는 설교가 없습니다."
    }

    // MARK: - 아이폰 본문 — 보기 3종 + 모임 칩 + 컴팩트 행(눌러서 상세로 push)

    private var phoneContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                listHeader
                    .padding(.bottom, 4)
                listRows(isSplit: false, showsRowActions: false)
            }
            .padding(16)
        }
        .searchable(text: $searchText, prompt: "제목·본문 검색")
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    // MARK: - 아이패드·맥 본문 — 왼쪽 설교 목록(폭 조절) / 오른쪽 상세
    // 에디터가 새 창으로 옮겨 가 오른쪽 패널에 에디터가 없으므로 목록을 넓게 쓴다(기본 460pt, 320~640pt에서 분할선을 끌어 조절).

    private var splitContent: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let listWidth = effectiveListWidth(totalWidth: proxy.size.width)
                HStack(spacing: 0) {
                    sermonSidebar(listWidth: listWidth)
                        .frame(width: listWidth)

                    listResizeHandle(currentWidth: listWidth, totalWidth: proxy.size.width)

                    // 새 설교 작성/설교 편집은 오른쪽 패널이 아니라 별도 창에서 한다(아래 `startNewSermon`, 행의 편집 아이콘).
                    if let selectedSermon {
                        SermonDetailView(sermon: selectedSermon, highlightedGatheringKey: detailHighlightKey)
                    } else {
                        emptySelectionPane
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "제목·본문 검색")
        // 오른쪽 패널의 상세/에디터가 자기 제목을 툴바에 올리지 않게 한다(`SermonFixedTitle` 참고).
        .environment(\.sermonHasFixedTitle, true)
        // 마인드맵 "설교문 적용" 후 해당 설교를 선택해 오른쪽 패널이 `SermonDetailView`를 보이게 한다.
        // 그 설교의 편집 창이 열려 있었다면 편집기가 스스로 저장 없이 창을 닫는다(`SermonEditorView.closeForExternalChange`).
        .onSermonExternalContentChange(onReplaced: { id in
            selectedSermonID = id
        })
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .sheet(item: $sermonPendingNewDelivery) { sermon in
            SermonDeliveryCreationSheet(sermon: sermon)
        }
    }

    /// 저장된 목록 폭을 창 폭에 맞춰 자른다 — 오른쪽 상세가 `detailMinWidth`보다 좁아지지 않게(창이 좁으면 목록이 줄어든다).
    private func effectiveListWidth(totalWidth: CGFloat) -> CGFloat {
        let range = Self.listWidthRange
        let upper = max(range.lowerBound, Double(totalWidth) - Self.detailMinWidth)
        return CGFloat(min(max(listPaneWidth, range.lowerBound), min(range.upperBound, upper)))
    }

    /// 목록과 상세 사이 분할선 — 끌어서 목록 폭을 바꾼다(기기별로 기억). 시작 폭은 첫 변화 때 한 번만 잡아 누적 오차를 막는다.
    private func listResizeHandle(currentWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let range = Self.listWidthRange
        let upper = max(range.lowerBound, min(range.upperBound, Double(totalWidth) - Self.detailMinWidth))
        return Rectangle()
            .fill(Color.clear)
            .frame(width: 12)
            .overlay(Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = listWidthDragStart ?? Double(currentWidth)
                        listWidthDragStart = start
                        listPaneWidth = min(max(start + Double(value.translation.width), range.lowerBound), upper)
                    }
                    .onEnded { _ in listWidthDragStart = nil }
            )
            .help("끌어서 목록 폭 조절")
            .accessibilityLabel("목록 폭 조절")
            .accessibilityValue("\(Int(currentWidth))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: listPaneWidth = min(Double(currentWidth) + 20, upper)
                case .decrement: listPaneWidth = max(Double(currentWidth) - 20, range.lowerBound)
                @unknown default: break
                }
            }
    }

    /// 왼쪽 목록 — 머리(보기 방식·모임 칩·건수)는 고정하고 행만 스크롤한다. 선택은 `selectedSermonID`만 바꾸고 오른쪽 `SermonDetailView`가 그 값을 읽는다.
    private func sermonSidebar(listWidth: CGFloat) -> some View {
        let showsActions = Double(listWidth) >= Self.rowActionsMinListWidth
        return VStack(spacing: 0) {
            listHeader
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    listRows(isSplit: true, showsRowActions: showsActions)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    /// 오른쪽 상세에서 강조할 모임(고른 모임 칩의 이력 행). 모임 미지정은 빈 문자열.
    private var detailHighlightKey: String? {
        switch gatheringFilter {
        case .gathering(let key): return key
        case .unassigned: return ""
        case .all, .unused: return nil
        }
    }

    private var emptySelectionPane: some View {
        VStack {
            Spacer()
            Text("왼쪽에서 설교를 선택하세요.")
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 상단 툴바(제목 + 설교 작성)

    #if os(iOS)
    /// 왼쪽 정렬 고정 제목 — "말씀 노트"(`WordNoteHomeView`)와 같은 서체·크기. 선택한 설교의 제목이 아니라
    /// 항상 "내 설교"로 고정한다(시스템 가운데 제목은 비워 둔다, `SermonFixedTitle` 참고).
    private var leftAlignedTitle: some View {
        Text("내 설교")
            .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
            .fontWeight(.semibold)
            .foregroundStyle(settings.bibleTextColor ?? .primary)
            // 같은 내비게이션 바의 검색창(`.searchable`)·툴바 버튼과 폭을 나눌 때 툴바 항목은 제목부터 줄어 "내…"로 잘린다.
            // 한 줄로 고정하고 글자 본래 폭을 요구해, 모자란 폭은 다른 항목이 양보하게 한다.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
    #endif

    /// 검색창 왼쪽의 "설교 작성" 아이콘 — 예전 "+ 새 설교" 버튼을 대체한다.
    private var composeButton: some View {
        Button {
            startNewSermon()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(accent, in: Circle())
        }
        .help("새 설교 작성")
        .accessibilityLabel("새 설교 작성")
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(ListFonts.empty)
            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    // MARK: - 설교 행 (컴팩트)

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static let shortDateWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yy. M/d"
        return formatter
    }()

    /// 올해는 "9/21", 다른 해는 "25. 9/21". 12/24시간제와 무관하게 고정 포맷을 쓴다.
    private func shortDate(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return (sameYear ? Self.shortDateFormatter : Self.shortDateWithYearFormatter).string(from: date)
    }

    @ViewBuilder
    private func sermonEntry(_ sermon: Sermon, scope: GatheringFilter, showsDates: Bool, isSplit: Bool, showsRowActions: Bool) -> some View {
        if isSplit {
            splitSermonRow(sermon, scope: scope, showsDates: showsDates, showsRowActions: showsRowActions)
        } else {
            NavigationLink {
                SermonDetailView(sermon: sermon)
            } label: {
                sermonCompactContent(sermon, scope: scope, showsDates: showsDates)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SermonTheme.cardFill))
            }
            .buttonStyle(.plain)
            // 파급력이 큰 삭제라 바로 지우지 않고 `sermonPendingDelete`를 거쳐 확인 대화상자를 띄운다.
            .contextMenu { sermonDeleteMenu(sermon) }
        }
    }

    /// 아이패드·맥 행 — 글자 영역을 누르면 선택(오른쪽 상세), 오른쪽 아이콘 4개(모임/Map/편집/뷰어)는 선택 없이 바로 쓴다.
    /// 목록이 좁으면(`rowActionsMinListWidth` 미만) 선택한 행에서만 아이콘을 보인다.
    private func splitSermonRow(_ sermon: Sermon, scope: GatheringFilter, showsDates: Bool, showsRowActions: Bool) -> some View {
        let isSelected = sermon.persistentModelID == selectedSermonID
        return HStack(spacing: 8) {
            sermonCompactContent(sermon, scope: scope, showsDates: showsDates)
                .contentShape(Rectangle())
                .onTapGesture { selectedSermonID = sermon.persistentModelID }
                .accessibilityAddTraits(.isButton)
            if showsRowActions || isSelected {
                rowActionIcons(sermon)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SermonTheme.cardFill))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accent, lineWidth: 2)
            }
        }
        .contextMenu { sermonDeleteMenu(sermon) }
    }

    @ViewBuilder
    private func sermonDeleteMenu(_ sermon: Sermon) -> some View {
        Button(role: .destructive) {
            sermonPendingDelete = sermon
        } label: {
            Label("삭제", systemImage: "trash")
        }
    }

    /// 컴팩트 행 내용 — 위 줄: 제목(한 줄), 아래 줄: 태그(2개) · 최근 모임 · 수정일(좁으면 먼저 잘림), 오른쪽: 사용 횟수.
    /// `scope`가 특정 모임이면 횟수·최근 모임이 그 모임 기준이다. `showsDates`(모임별 보기)는 최근 모임 대신 그 모임에서 쓴 날짜들을 보인다.
    private func sermonCompactContent(_ sermon: Sermon, scope: GatheringFilter, showsDates: Bool) -> some View {
        let all = sermonDeliveries(sermon, in: .all)
        let scoped = (scope == .all || scope == .unused) ? all : sermonDeliveries(sermon, in: scope)
        let tags = (sermon.sermonTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sermon.title.isEmpty ? "제목 없음" : sermon.title)
                    .font(ListFonts.rowTitle)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if showsDates {
                        // 모임별 보기: 그 모임에서 쓴 날짜(최근 4개 + 나머지 개수).
                        ForEach(Array(scoped.prefix(4).enumerated()), id: \.offset) { _, delivery in
                            Text(shortDate(delivery.deliveredAt))
                                .padding(.horizontal, 6)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundStyle(subtleText)
                        }
                        if scoped.count > 4 {
                            Text("+\(scoped.count - 4)")
                                .foregroundStyle(subtleText)
                        }
                    } else {
                        if !tags.isEmpty {
                            Text(tags.prefix(2).map { "#\($0.name)" }.joined(separator: " "))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                        }
                        if let latest = scoped.first {
                            Text("최근 \(shortDate(latest.deliveredAt)) \(latest.gathering?.name ?? "모임 미지정")")
                                .foregroundStyle(SermonTheme.success)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        } else {
                            Text("사용 이력 없음")
                                .foregroundStyle(subtleText)
                                .lineLimit(1)
                        }
                        Text("\(listSort == .recentlyEdited ? "수정" : "등록") \(shortDate(sortDate(sermon)))")
                            .foregroundStyle(subtleText)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                .font(ListFonts.meta)
            }
            Spacer(minLength: 0)
            if scoped.isEmpty {
                Text("미사용")
                    .font(ListFonts.meta)
                    .foregroundStyle(subtleText)
            } else {
                Text("\(scoped.count)회")
                    .font(ListFonts.metaBold)
                    .foregroundStyle(SermonTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(SermonTheme.success.opacity(0.15)))
            }
        }
    }

    // MARK: 행 오른쪽 아이콘 4개 (아이패드·맥)

    #if os(iOS)
    private var rowActionSide: CGFloat { 36 }
    #else
    private var rowActionSide: CGFloat { 32 }
    #endif

    private func rowActionIcons(_ sermon: Sermon) -> some View {
        HStack(spacing: 4) {
            rowActionButton(systemImage: "plus", title: "새 모임에서 사용", tint: joinButtonTint) {
                sermonPendingNewDelivery = sermon
            }
            // 아이콘은 SF Symbols 4(iOS 16+/macOS 13+)의 트리 형태에 가까운 심벌이다. 바꾸려면 이 한 곳만 수정한다.
            rowActionButton(systemImage: "point.3.connected.trianglepath.dotted", title: "마인드맵", tint: mapButtonTint) {
                openWindow(id: "sermon-mindmap", value: SermonMindMapTarget.sermon(sermon))
            }
            rowActionButton(systemImage: "square.and.pencil", title: "편집", tint: editButtonTint) {
                // 편집은 별도 창에서 한다(`SermonDetailView.editorButton`과 같은 창). 같은 설교는 창이 하나만 뜬다.
                selectedSermonID = sermon.persistentModelID
                sceneDiagNote("편집 버튼 탭(목록 행) → openWindow(sermon-editor)")
                openWindow(id: "sermon-editor", value: SermonEditorTarget.sermon(sermon))
            }
            rowActionButton(systemImage: "eyeglasses", title: "뷰어", tint: accent) {
                sceneDiagNote("뷰어 버튼 탭(목록 행) → openWindow(sermon-viewer)")
                openWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(sermon))
            }
        }
    }

    private func rowActionButton(systemImage: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(onAccent)
                .frame(width: rowActionSide, height: rowActionSide)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(SermonRowIconButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }

    /// 모임별 보기의 모임 제목 줄.
    private func gatheringHeader(_ section: GatheringSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.title)
                .font(ListFonts.sectionTitle)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            Text("설교 \(section.sermons.count)개 · \(section.totalCount)회")
                .font(ListFonts.meta)
                .foregroundStyle(subtleText)
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 날짜별 행 (아이폰 전용 — 아이패드·맥은 splitContent가 대체)

    @ViewBuilder
    private func deliveryRow(_ delivery: SermonDelivery) -> some View {
        // 날짜별은 상세/이력 화면을 거치지 않고 그 회차의 실제 본문(해당 SermonDelivery)으로 바로 진입한다.
        NavigationLink {
            SermonEditorView(subject: .delivery(delivery))
        } label: {
            deliveryRowLabel(delivery)
        }
        .buttonStyle(.plain)
        // 개별 이력은 캐스케이드로 다른 걸 끌고 내려가지 않아(Sermons.swift) 확인 없이 바로 지운다.
        .contextMenu {
            Button(role: .destructive) {
                deleteDelivery(delivery)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    private func deliveryRowLabel(_ delivery: SermonDelivery) -> some View {
        let isModified = (delivery.sermon?.contentText).map { $0 != delivery.contentText } ?? false
        return HStack(spacing: 12) {
            Text(delivery.deliveredAt.formatted(date: .abbreviated, time: .omitted))
                .font(ListFonts.control)
                .foregroundStyle(accent)
                .frame(width: 104, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(delivery.gathering?.name ?? "모임 미지정")
                    .font(ListFonts.rowTitleMedium)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Text(delivery.sermon?.title.isEmpty == false ? delivery.sermon!.title : "제목 없음")
                    .font(ListFonts.meta)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if isModified {
                    SermonBadge(text: "수정됨", color: SermonTheme.warning)
                } else {
                    SermonBadge(text: "메인과 동일", color: SermonTheme.success)
                }
                // 정렬 기준이 되는 날짜 — 사용일과 다른 순서로 정렬돼도 왜 그 자리인지 보이게 한다.
                Text("\(listSort == .recentlyEdited ? "수정" : "등록") \(shortDate(sortDate(delivery)))")
                    .font(ListFonts.small)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SermonTheme.cardCornerRadius, style: .continuous).fill(SermonTheme.cardFill))
    }

    /// 아이패드·맥 날짜별 행 — 누르면 그 설교를 오른쪽 상세에서 보인다(그 회차의 편집/뷰어는 상세의 이력 행에 있다).
    private func splitDeliveryRow(_ delivery: SermonDelivery) -> some View {
        let isSelected = delivery.sermon != nil && delivery.sermon?.persistentModelID == selectedSermonID
        return deliveryRowLabel(delivery)
            .contentShape(Rectangle())
            .onTapGesture { selectedSermonID = delivery.sermon?.persistentModelID }
            .accessibilityAddTraits(.isButton)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: SermonTheme.cardCornerRadius, style: .continuous).strokeBorder(accent, lineWidth: 2)
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    deleteDelivery(delivery)
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
    }

    // MARK: - 삭제

    /// `sermonPendingDelete` 확인 대화상자에서 "삭제"를 눌렀을 때만 호출된다.
    /// `Sermon.deliveries`/`verseReferences`가 `.cascade`라 이 한 번의 삭제로
    /// 연결된 이력·구절 레코드까지 함께 지워진다(Sermons.swift).
    private func deleteSermon(_ sermon: Sermon) {
        if selectedSermonID == sermon.persistentModelID {
            selectedSermonID = nil
        }
        // 통합 검색용 성경구절 인덱스를 지운다. `sourceId`(sermon.id)가 필요하므로 `modelContext.delete(sermon)`보다 먼저 호출한다.
        BibleReferenceIndexingService.removeMentions(sourceType: .sermon, sourceId: sermon.id.uuidString, context: modelContext)
        modelContext.delete(sermon)
        try? modelContext.save()
    }

    /// 개별 활용 이력만 지운다 — 확인 대화상자 없이 즉시 실행(Document/
    /// WordNote 컨텍스트 메뉴 삭제와 같은 관례).
    private func deleteDelivery(_ delivery: SermonDelivery) {
        modelContext.delete(delivery)
        try? modelContext.save()
    }

    // MARK: - 새 설교

    /// "새 설교" 버튼 동작. 아이폰은 아직 insert하지 않은 `Sermon`을 `pendingNewSermon`에 담아 push하고(실제 insert는
    /// `SermonEditorView.save()`), 아이패드·맥은 다중 창을 쓸 수 있어 새 창("sermon-new")을 연다. 아이폰은 다중 씬을 지원하지
    /// 않아 `openWindow`를 부르면 런타임 오류가 나므로 반드시 분기한다(`SermonDetailView.editorButton` 주석 참고).
    private func startNewSermon() {
        if isPhoneIdiom {
            pendingNewSermon = Sermon(title: "")
        } else {
            openWindow(id: "sermon-new", value: SermonNewTarget())
        }
    }
}
