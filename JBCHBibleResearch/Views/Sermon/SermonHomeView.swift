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
//  새 설교: 툴바의 "설교 작성" 아이콘으로, 시트 없이 `SermonEditorView`(`isNewSermon: true`)를 바로 연다. 제목과 본문이
//  모두 비면 저장하지 않으며 그 검증은 `SermonEditorView.save()`가 맡는다. 수정일은
//  저장 시 `touchUpdatedAt()`이 현재 시각으로 넣는다.
//
//  ⚠️ `JBCHBibleResearchApp.swift`의 `WindowGroup(id: "sermon-detail", ...)` 등록은 이
//  화면에서 더 이상 호출하지 않지만 다른 곳에서 참조할 수 있어 남겨 두었다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

private enum SermonListViewMode: String, CaseIterable {
    case bySermon = "말씀 단위 묶음"
    case byDate = "날짜별"
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

    @Query(sort: \Sermon.updatedAt, order: .reverse) private var sermons: [Sermon]
    @Query(sort: \SermonDelivery.deliveredAt, order: .reverse) private var deliveries: [SermonDelivery]

    @State private var viewMode: SermonListViewMode = .bySermon
    @State private var searchText = ""
    /// "새 설교" 버튼이 담는, 아직 `modelContext`에 insert하지 않은 `Sermon`. 아이폰은
    /// `.navigationDestination(item:)`으로 에디터를 push하고, 아이패드·맥은 `splitContent`가
    /// 오른쪽 패널에 에디터를 직접 얹는다. 실제 insert는 `SermonEditorView.save()`가 제목/본문
    /// 중 하나라도 채워졌을 때만 하므로 이 값은 화면 전환용일 뿐 데이터 등록과 무관하다.
    @State private var pendingNewSermon: Sermon?
    /// 메인 `Sermon` 삭제 확인 대화상자 대상. `Sermon.deliveries`/`verseReferences`가
    /// `.cascade`라(Sermons.swift) 삭제 시 이력·구절 레코드도 함께 사라지므로 확인 후 삭제한다.
    @State private var sermonPendingDelete: Sermon?
    /// 아이패드·맥 전용 — 왼쪽 "설교함"에서 고른 설교. 오른쪽 상세 패널이 이 값을 읽는다.
    @State private var selectedSermonID: PersistentIdentifier?
    /// "새 모임" 시트 대상. `.sheet(item:)`이라 nil이 아니면 그 설교에 대해 시트가 열린다.
    @State private var sermonPendingNewDelivery: Sermon?
    /// 아이패드·맥 전용 — 이미 있는 설교를 편집 중일 때의 대상. 값이 있으면 오른쪽 패널이
    /// `SermonDetailView` 대신 `SermonEditorView`(`isNewSermon: false`)를 보여준다.
    /// `pendingNewSermon`과 별개 상태이며 저장은 일반 경로(지연 삽입 없음)를 탄다.
    @State private var editingSermon: Sermon?

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

    private var filteredSermons: [Sermon] {
        guard !searchText.isEmpty else { return sermons }
        return sermons.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.contentText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredDeliveries: [SermonDelivery] {
        guard !searchText.isEmpty else { return deliveries }
        return deliveries.filter { delivery in
            (delivery.sermon?.title.localizedCaseInsensitiveContains(searchText) ?? false)
                || delivery.contentText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedSermon: Sermon? {
        guard let selectedSermonID else { return nil }
        return sermons.first { $0.persistentModelID == selectedSermonID }
    }

    var body: some View {
        Group {
            if isPhoneIdiom {
                // 아이폰에서만 `.navigationDestination(item:)`으로 에디터를 push한다. 아이패드·맥은
                // `splitContent`가 이미 오른쪽 패널에 에디터를 직접 얹고 detail 컬럼 자체가
                // NavigationStack이라, 여기에도 걸면 에디터가 한 겹 더 push되어 "<"와 "취소"가
                // 동시에 보이는 문제가 생긴다.
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) { leftAlignedTitle }
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

    // MARK: - 아이폰 본문 (기존 그대로 — 말씀단위묶음/날짜별 토글 + 단일 목록)

    private var phoneContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                SermonSegmentedPill(
                    items: [
                        .init(tag: SermonListViewMode.bySermon, label: SermonListViewMode.bySermon.rawValue),
                        .init(tag: SermonListViewMode.byDate, label: SermonListViewMode.byDate.rawValue),
                    ],
                    selection: $viewMode,
                    accent: accent
                )

                switch viewMode {
                case .bySermon:
                    if filteredSermons.isEmpty {
                        emptyState(text: "아직 등록한 설교가 없습니다.")
                    } else {
                        ForEach(filteredSermons) { sermon in
                            sermonRow(sermon)
                        }
                    }
                case .byDate:
                    if filteredDeliveries.isEmpty {
                        emptyState(text: "아직 사용 이력이 없습니다.")
                    } else {
                        ForEach(filteredDeliveries) { delivery in
                            deliveryRow(delivery)
                        }
                    }
                }
            }
            .padding(16)
        }
        .searchable(text: $searchText, prompt: "제목·본문 검색")
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    // MARK: - 아이패드·맥 본문 — 왼쪽 설교함(말씀단위 목록) / 오른쪽 상세리스트
    // 왼쪽 설교함과 오른쪽 상세를 나란히 놓는 구성(`DocumentsHomeView.splitMainContent`와 같은 패턴).
    private var splitContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sermonSidebar
                    // 행 버튼 4개가 폭을 나눠 갖기 때문에 버튼 텍스트가 잘리지 않을 만큼의 폭이 필요하다.
                    .frame(minWidth: 150, idealWidth: 180, maxWidth: 230)

                Divider()

                if let pendingNewSermon {
                    // 새 설교는 팝업 없이 이 자리에 에디터를 바로 얹는다. 시트/창이 아니라 그냥 얹힌 뷰라
                    // `@Environment(\.dismiss)`가 기댈 프레젠테이션이 없으므로 `onRequestClose`로 값을 직접 nil로 되돌린다.
                    SermonEditorView(
                        subject: .sermon(pendingNewSermon),
                        isNewSermon: true,
                        onRequestClose: { self.pendingNewSermon = nil }
                    )
                } else if let editingSermon {
                    // 이미 있는 설교 편집. 위 분기와 같은 패턴이되 `isNewSermon: false`라 지연 삽입 없이 저장된다.
                    SermonEditorView(
                        subject: .sermon(editingSermon),
                        onRequestClose: { self.editingSermon = nil }
                    )
                } else if let selectedSermon {
                    SermonDetailView(sermon: selectedSermon)
                } else {
                    emptySelectionPane
                }
            }
        }
        .searchable(text: $searchText, prompt: "제목·본문 검색")
        // 오른쪽 패널의 상세/에디터가 자기 제목을 툴바에 올리지 않게 한다(`SermonFixedTitle` 참고).
        .environment(\.sermonHasFixedTitle, true)
        // 마인드맵 "설교문 적용" 후 해당 설교를 선택해 오른쪽 패널이 `SermonDetailView`를 보이게 한다.
        // 그 설교의 인라인 편집기가 열려 있었다면 편집기가 스스로 저장 없이 닫히므로 `editingSermon`도
        // 비운다. 새 설교 작성 중(`pendingNewSermon`)은 다른 설교라 건드리지 않는다.
        .onSermonExternalContentChange(onReplaced: { id in
            if editingSermon?.persistentModelID == id {
                editingSermon = nil
            }
            selectedSermonID = id
        })
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .sheet(item: $sermonPendingNewDelivery) { sermon in
            SermonDeliveryCreationSheet(sermon: sermon)
        }
    }

    /// 왼쪽 "설교함" — 늘 말씀단위 목록만 보여준다(토글 없음). 고르면 `selectedSermonID`만 바뀌고
    /// 오른쪽 `SermonDetailView`가 그 값을 읽어 다시 그린다.
    private var sermonSidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if filteredSermons.isEmpty {
                    emptyState(text: "아직 등록한 설교가 없습니다.")
                } else {
                    ForEach(filteredSermons) { sermon in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                // 새 설교 작성 중에 다른 설교를 고르면 만들던 설교는 버려진다(제목/본문이 비어 있으면
                                // 뷰가 사라질 때 호출되는 `SermonEditorView.save()`의 검증이 저장하지 않음).
                                pendingNewSermon = nil
                                editingSermon = nil
                                selectedSermonID = sermon.persistentModelID
                            } label: {
                                sermonRowLabel(sermon)
                                    .overlay(alignment: .leading) {
                                        if sermon.persistentModelID == selectedSermonID {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(accent)
                                                .frame(width: 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)

                            // 고르지 않고도 곧장 쓸 수 있도록 행 아래에 모임/Map/편집/뷰어 버튼을 둔다.
                            HStack(spacing: 4) {

                                Button {
                                    sermonPendingNewDelivery = sermon
                                } label: {
                                    sermonRowActionLabel(title: "모임", systemImage: "plus.circle")
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: joinButtonTint))
                                // 아이콘은 SF Symbols 4(iOS 16+/macOS 13+)의 트리 형태에 가까운 심벌이다. 바꾸려면 이 한 곳만 수정한다.
                                Button {
                                    openWindow(id: "sermon-mindmap", value: SermonMindMapTarget.sermon(sermon))
                                } label: {
                                    sermonRowActionLabel(title: "Map", systemImage: "point.3.connected.trianglepath.dotted")
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: mapButtonTint))
                                Button {
                                    // 별도 창 대신 `editingSermon`을 채워 오른쪽 패널이 그 자리에서 에디터를 보이게 한다(`splitContent` 참고).
                                    pendingNewSermon = nil
                                    selectedSermonID = sermon.persistentModelID
                                    editingSermon = sermon
                                } label: {
                                    sermonRowActionLabel(title: "편집", systemImage: "square.and.pencil")
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: editButtonTint))
                                Button {
                                    openWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(sermon))
                                } label: {
                                    sermonRowActionLabel(title: "뷰어", systemImage: "eyeglasses")
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: accent))
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                        }
                        // `sermonRowLabel`이 이미 자기 카드 배경을 갖고 있어 VStack 전체를 또 카드로 감싸지 않는다
                        // (이중 배경 방지). 버튼 줄은 그 카드 바로 아래에 붙는다.
                        .contextMenu {
                            Button(role: .destructive) {
                                sermonPendingDelete = sermon
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(16)
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
            .font(.callout)
            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    // MARK: - 말씀 단위 묶음 행 (아이폰 전용 — push로 상세 화면 이동)

    @ViewBuilder
    private func sermonRow(_ sermon: Sermon) -> some View {
        NavigationLink {
            SermonDetailView(sermon: sermon)
        } label: {
            sermonRowLabel(sermon)
        }
        .buttonStyle(.plain)
        // 파급력이 큰 삭제라 바로 지우지 않고 `sermonPendingDelete`를 거쳐 확인 대화상자를 띄운다.
        .contextMenu {
            Button(role: .destructive) {
                sermonPendingDelete = sermon
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    /// 기기의 12/24시간제 설정과 무관하게 항상 24시간제(HH)로 표시하려고, 로케일 종속인
    /// `Date.FormatStyle` 대신 고정 포맷의 `DateFormatter`를 쓴다.
    private static let gatheringDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d (E)"
        return formatter
    }()

    private static let updatedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d (E) HH:mm"
        return formatter
    }()

    /// 행 하단 버튼(모임/Map/편집/뷰어) 라벨. 아이콘(위)/텍스트(아래) 두 줄이며, 좁은 폭에서
    /// 한글이 음절 단위로 줄바꿈되지 않도록 `.lineLimit(1)`을 건다. 크기는 버튼 바깥이 아니라
    /// 라벨 안에 걸어야 한다 — `SermonMiniPillButtonStyle`이 라벨 크기에 맞춰 알약 배경을 그리므로
    /// 바깥 프레임으로는 4개 버튼의 폭·높이가 통일되지 않는다.
    private func sermonRowActionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.callout)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }

    private func sermonRowLabel(_ sermon: Sermon) -> some View {
        let sortedDeliveries = (sermon.deliveries ?? []).sorted { $0.deliveredAt > $1.deliveredAt }
        let tags = (sermon.sermonTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        return VStack(alignment: .leading, spacing: 10) {
            Text(sermon.title.isEmpty ? "제목 없음" : sermon.title)
                .font(.headline)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .multilineTextAlignment(.leading)

            if !tags.isEmpty {
                FlowLayoutHStack {
                    ForEach(tags) { tag in
                        SermonBadge(text: "#\(tag.name)", color: accent)
                    }
                }
            }

            if !sortedDeliveries.isEmpty {
                Divider()
            }

            // 사용 횟수 / 최근 모임 / 수정일을 한 세로 블록으로 둔다. 수정일 줄만 회색이고 나머지는
            // 사용 이력 유무에 따라 `SermonTheme.success`(초록) 또는 secondary 색이다.
            VStack(alignment: .leading, spacing: 4) {
                if let latest = sortedDeliveries.first {
                    Text("\(sortedDeliveries.count)회 사용")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SermonTheme.success)
                    Text("최근 : \(Self.gatheringDateFormatter.string(from: latest.deliveredAt)) \(latest.gathering?.name ?? "모임 미지정")")
                        .font(.caption)
                        .foregroundStyle(SermonTheme.success)
                } else {
                    Text("사용 이력 없음")
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                Text("수정 : \(Self.updatedAtFormatter.string(from: sermon.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SermonTheme.cardCornerRadius, style: .continuous).fill(SermonTheme.cardFill))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(delivery.gathering?.name ?? "모임 미지정")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Text(delivery.sermon?.title.isEmpty == false ? delivery.sermon!.title : "제목 없음")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            Spacer()
            if isModified {
                SermonBadge(text: "수정됨", color: SermonTheme.warning)
            } else {
                SermonBadge(text: "메인과 동일", color: SermonTheme.success)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SermonTheme.cardCornerRadius, style: .continuous).fill(SermonTheme.cardFill))
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

    /// "새 설교" 버튼 동작 — 아직 insert하지 않은 `Sermon`을 `pendingNewSermon`에 담기만 한다.
    /// 화면 전환은 `body`/`splitContent`가, 실제 insert는 `SermonEditorView.save()`가 맡는다.
    private func startNewSermon() {
        pendingNewSermon = Sermon(title: "")
    }
}
