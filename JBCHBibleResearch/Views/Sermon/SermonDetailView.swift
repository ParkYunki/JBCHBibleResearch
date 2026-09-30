//
//  SermonDetailView.swift
//  JBCHBibleResearch
//
//  S-SER1a "설교 상세·이력" — 메인 설교문(Sermon) 하나의 태그와, 그 설교가 쓰인
//  모임별 활용 이력(SermonDelivery)을 보여준다. 설계 문서
//  claude/sermon-management-screens-and-schema.md 2.2 S-SER1a 참고.
//
//  ⚠️ [범위] [2026-09-28 갱신] "본문 편집"(`SermonEditorView`, 3단계)과
//  "뷰어로 보기"(`SermonViewerView`, 4단계) 모두 실제 화면으로 연결 완료됐다.
//  제목만은 이 화면에서 바로 고칠 수 있게 했다 — 새로 만든 설교가 에디터
//  없이도 최소한 이름을 붙일 수 있어야 하기 때문(그 외 본문 편집은 에디터의 몫).
//
//  태그 UI는 `Views/Memo/MemoDetailView.swift`의 태그 섹션(즉시 저장, `TagDeduplication
//  .findOrCreateTag`, `FlowLayoutHStack`)을 그대로 따른다 — 새 패턴을 만들지 않는다.
//
//  [2026-09-28 디자인 정합화] 사용자 지적 — "디자인이 목업 html과 너무 차이가
//  큼." 목업(`Detail.dc.html`/`MacDetail.dc.html`)과 맞추려 두 가지를 바꿨다:
//  (1) 태그 칩 색을 앱의 퍼스널 액센트(`Color("AccentColor")`, 서재 금박)에서
//  `SermonTheme.accent`(와인 적갈, 목업의 --accent와 정확히 같은 hex)로 바꿨다
//  — "내 설교" 기능 전체가 하나의 액센트를 쓰도록(SermonHomeView와 통일).
//  (2) 목업처럼 "본문 편집"/"뷰어로 보기"를 본문 안 눈에 띄는 버튼 두 개로
//  옮기고, 중복되는 툴바 아이콘 버튼은 없앴다(기능은 그대로, 위치만 이동).
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

/// `WindowGroup(id: "sermon-detail", for: PersistentIdentifier.self)`
/// (JBCHBibleResearchApp.swift 참고) 전용 창 콘텐츠 — Mac/iPad에서 목록의 설교
/// 행을 누르면 별도 창으로 열린다(설계 문서 2.4, `DocumentViewerWindowContent`와
/// 같은 "문서당 1개 창" 원칙). `@Query`로 대상을 찾는 이유는
/// `DocumentViewerWindowContent` 상단 주석과 동일 — 창이 떠 있는 동안 그 설교가
/// 다른 곳에서 지워져도 죽은 참조를 읽어 크래시하지 않는다.
struct SermonDetailWindowContent: View {
    @Query private var sermons: [Sermon]
    let sermonID: PersistentIdentifier?

    var body: some View {
        if let sermonID, let sermon = sermons.first(where: { $0.persistentModelID == sermonID }) {
            NavigationStack {
                SermonDetailView(sermon: sermon)
            }
            #if os(macOS)
            .frame(minWidth: 760, minHeight: 640)
            #endif
        } else {
            sermonNotFoundMessage
        }
    }

    private var sermonNotFoundMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("설교를 찾을 수 없습니다")
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


/// [2026-09-29 신설] 사용자 요청 — "설정-테마색상에 따른 디자인 색상 변화
/// 필요." `DocumentsHomeView`/`BibleReadingView`/`WordNoteHomeView`/
/// `SearchView`가 이미 각자 파일에 두고 있는 것과 완전히 같은 타입·같은
/// 구현(그 파일들 주석 — "iOS 16+ 공식 API + WCAG 상대휘도로 다크/라이트
/// 아이템 색 결정")이다.
///
/// ⚠️ [2026-09-29 수정, 빌드 에러 fix] 처음엔 "내 설교" 화면 3개가 공유하는
/// `SermonSupport.swift`에 `private` 없이 한 번만 선언했었다 — 사용자 보고,
/// Xcode 에러 "Invalid redeclaration of 'ThemedNavigationBarBackgroundModifier'"
/// (SearchView.swift:54). 원인: Swift는 파일 최상위의 `private`(=`fileprivate`)
/// 선언과 다른 파일의 `private` 아닌(= internal) 같은 이름 선언이 같은
/// 모듈 안에 있으면, 접근 범위와 무관하게 이름 충돌로 처리한다 — 기존 4개
/// 파일이 서로 충돌 없이 같은 이름을 쓸 수 있었던 건 넷 다 예외 없이
/// `private`였기 때문이다. 그래서 공유하는 대신, 그 4개 파일과 완전히 같은
/// 관례대로 이 파일에도 `private`로 다시 선언한다(기능당 하나 공유가 아니라
/// 파일마다 중복 — 이 프로젝트가 실제로 쓰는 관례는 후자였다).
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

struct SermonDetailView: View {
    @Bindable var sermon: Sermon
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// [2026-09-29 삭제] 사용자 지적 — "내 설교 - 오른쪽 영역에 태그 입력
    /// 영역 삭제." 이 화면(아이패드·맥 분할 화면의 오른쪽 패널)의 `tagSection`을
    /// 없앴다 — `SermonEditorView`(본문 편집 화면) 하단에 이미 같은 `Sermon.
    /// sermonTags`를 편집하는 태그 입력 영역이 있어(2026-09-29 신설, "태그
    /// 입력은 메인 설교문, 모임에 따른 설교문 하단에 추가할 수 있도록 할
    /// 것") 완전히 중복이었다. 관련 상태(`sermonTags`/`tagInput`/
    /// `tagSuggestions`/`hasLoadedTags`)와 `drilldownTag`(읽지 않는 채로만
    /// 있던 미완성 자리표시자)도 함께 지웠다.
    private var settings: UserSettingsStore { .shared }

    /// [2026-09-29 수정] 테마색상 반영 — `SermonSupport.swift`의 새 판 참고
    /// (`SermonHomeView.accent`와 같은 이유·같은 코드).
    private var accent: Color {
        SermonTheme.accent(background: settings.bibleBackgroundColor, environment: environment, fallbackScheme: colorScheme)
    }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private var sortedDeliveries: [SermonDelivery] {
        (sermon.deliveries ?? []).sorted { $0.deliveredAt > $1.deliveredAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleSection
                // [2026-09-29 수정] 사용자 지적 — "내 설교 - 왼쪽 영역으로
                // '본문편집' 버튼, '뷰어로 보기' 이동." 아이패드·맥은 이
                // 버튼 한 쌍이 이제 왼쪽 "설교함"(`SermonHomeView.
                // sermonSidebar`) 행에 있다 — 이 화면(오른쪽 패널)에 똑같은
                // 동작을 중복해 두지 않는다. 아이폰은 이 화면이 push로
                // 도달하는 유일한 경로라 그대로 남긴다.
                if isPhoneIdiom {
                    actionButtons
                }
                deliverySection
            }
            .padding(20)
        }
        .navigationTitle(sermon.title.isEmpty ? "새 설교" : sermon.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        .onDisappear { save() }
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    // MARK: - 제목

    /// [2026-09-29 수정] 사용자 요청 — "제목 수정기능은 편집에디터 화면으로
    /// 이동." 이 화면이 인라인 `TextField`로 직접 편집을 받던 것을 그만두고
    /// 읽기 전용 표시로 바꾼다 — 실제 수정은 이제 `SermonEditorView.titleField`
    /// (그 파일 참고, `.sermon` 대상이면 새 설교든 기존 설교든 항상 보임)
    /// 하나로 모인다. `editorButton`(바로 아래, 이 화면 안에선 아이폰
    /// 전용으로 남음 — `actionButtons` 주석 참고, 아이패드·맥은 왼쪽 설교함
    /// 행의 "편집" 버튼)을 누르면 그 에디터로 이동해 고칠 수 있다.
    private var titleSection: some View {
        Text(sermon.title.isEmpty ? "제목 없음" : sermon.title)
            .font(.title2.bold())
            .foregroundStyle(settings.bibleTextColor ?? .primary)
    }

    // MARK: - 본문 편집 / 뷰어로 보기 (목업 Detail.dc.html의 버튼 한 쌍)
    //
    // [2026-09-28 디자인 정합화] 예전엔 이 두 동작이 툴바 아이콘 버튼으로만
    // 있었다 — 목업은 본문 안에 눈에 띄는 버튼 두 개로 보여준다. 같은 동작을
    // 두 곳(툴바+본문)에 중복해 두지 않고 이 자리 하나로 옮겼다.
    //
    // ⚠️ 아이폰은 다중 씬(멀티 윈도우)을 지원하지 않아 `openWindow`를 부르면
    // 실기기 런타임 에러가 난다(`DocumentsHomeView.isPhoneIdiom` 상단 주석에
    // 이미 기록된 제약) — 그래서 아이폰만 `NavigationLink`로 이 화면이 속한
    // NavigationStack 안에 밀어 넣고, 나머지(맥/아이패드)는 기존
    // "document-viewer"와 같은 `openWindow`를 그대로 쓴다.

    private var actionButtons: some View {
        HStack(spacing: 10) {
            editorButton
            viewerButton
            mapButton
        }
    }

    @ViewBuilder
    private var editorButton: some View {
        // [2026-09-29 수정] 사용자 지적 — "'편집', '뷰어' 이름 변경"(아이패드·
        // 맥 쪽 버튼이 왼쪽 설교함 행으로 옮겨가며 라벨도 그 짧은 이름으로
        // 통일했다, `SermonHomeView.sermonSidebar`와 `deliveryEditorLink`/
        // `deliveryViewerLink`가 이미 쓰던 "편집"/"뷰어"와 맞춤). 이 버튼
        // 자체는 아이폰 전용으로 남았다(위 `body` 주석 참고).
        if isPhoneIdiom {
            NavigationLink {
                SermonEditorView(subject: .sermon(sermon))
            } label: {
                Label("편집", systemImage: "square.and.pencil")
            }
            .buttonStyle(SermonPillButtonStyle(isFilled: false, tint: accent))
        } else {
            Button {
                openWindow(id: "sermon-editor", value: SermonContentTarget.sermon(sermon))
            } label: {
                Label("편집", systemImage: "square.and.pencil")
            }
            .buttonStyle(SermonPillButtonStyle(isFilled: false, tint: accent))
        }
    }

    @ViewBuilder
    private var viewerButton: some View {
        if isPhoneIdiom {
            NavigationLink {
                SermonViewerView(subject: .sermon(sermon))
            } label: {
                Label("뷰어", systemImage: "eyeglasses")
            }
            .buttonStyle(SermonPillButtonStyle(isFilled: true, tint: accent))
        } else {
            Button {
                openWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(sermon))
            } label: {
                Label("뷰어", systemImage: "eyeglasses")
            }
            .buttonStyle(SermonPillButtonStyle(isFilled: true, tint: accent))
        }
    }

    /// [2026-09-29 신설] "마인드맵" 기능 — 아이패드·맥은 이미 `SermonHomeView.
    /// sermonSidebar`의 "모임" 버튼 오른쪽에 이 동작이 있어(위 `actionButtons`
    /// 주석의 "중복해 두지 않는다" 원칙과 같은 이유로 이 화면에선 원래
    /// `if isPhoneIdiom`일 때만 보인다), 실제로 새로 쓰이는 건 아이폰
    /// 분기(`NavigationLink`)뿐이다 — 다만 `editorButton`/`viewerButton`과
    /// 똑같이 두 분기를 다 갖춰 둔다(이 화면이 나중에 아이패드·맥에서도
    /// 직접 쓰이게 되면 그대로 동작하도록).
    @ViewBuilder
    private var mapButton: some View {
        if isPhoneIdiom {
            NavigationLink {
                SermonMindMapView(sermon: sermon)
            } label: {
                Label("Map", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(SermonPillButtonStyle(isFilled: false, tint: accent))
        } else {
            Button {
                openWindow(id: "sermon-mindmap", value: SermonMindMapTarget.sermon(sermon))
            } label: {
                Label("Map", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(SermonPillButtonStyle(isFilled: false, tint: accent))
        }
    }

    // MARK: - 활용 이력

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("이 설교가 쓰인 모임 (\(sortedDeliveries.count))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Spacer()
                // [2026-09-29 이동] 사용자 요청 — "'이 설교를 새 모임에서
                // 사용' 버튼을 왼쪽 설교 리스트로 이동." 여기 있던 버튼(과
                // 그 상태 `isAddDeliveryPresented`/시트)을 없애고
                // `SermonHomeView.sermonSidebar`의 각 설교 행(편집/뷰어
                // 버튼 줄)에 "새 모임" 버튼으로 옮겼다 — 아이패드·맥은 그
                // 왼쪽 행에서, 아이폰은 이 화면(이 섹션)이 유일한 경로라
                // 그 화면의 목록 행에도 같은 방식으로 필요하면 후속으로
                // 추가할 수 있다(현재 아이폰 목록 행 `sermonRow`엔 아직
                // 없음 — 아래 참고).
            }

            if sortedDeliveries.isEmpty {
                Text("아직 이 설교를 사용한 모임이 없습니다.")
                    .font(.callout)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedDeliveries) { delivery in
                        deliveryRow(delivery)
                    }
                }
            }
        }
    }

    private func deliveryRow(_ delivery: SermonDelivery) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(delivery.gathering?.name ?? "모임 미지정")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Text(delivery.deliveredAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            Spacer()
            statusBadge(for: delivery)
            deliveryEditorLink(delivery)
            deliveryViewerLink(delivery)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SermonTheme.cardCornerRadius, style: .continuous).fill(SermonTheme.cardFill))
        // [2026-09-28 삭제 기능] 개별 이력(SermonDelivery) 삭제 — `Sermon.deliveries`와
        // 달리 이 레코드는 다른 무언가를 캐스케이드로 끌고 내려가지 않는다
        // (Sermons.swift에 `SermonDelivery` 자신을 대상으로 한 `.cascade`
        // 관계가 없음 — `verseReferences`만 이 레코드 삭제 시 함께 지워짐,
        // 그건 이 이력 하나에 속한 부속 데이터라 자연스러움). 파급력이 작아
        // Document/WordNote의 컨텍스트 메뉴 삭제(확인 대화상자 없음) 관례를
        // 그대로 따른다.
        .contextMenu {
            Button(role: .destructive) {
                deleteDelivery(delivery)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    /// "메인과 동일"/"내용 수정됨" — 별도 저장 필드 없이 매번 본문을 비교해
    /// 계산한다(설계 문서 2.2 S-SER1a — 저장 시점마다 플래그를 갱신하는 동기화
    /// 부담을 피하기 위함).
    private func statusBadge(for delivery: SermonDelivery) -> some View {
        let isSame = delivery.contentText == sermon.contentText
        return SermonBadge(text: isSame ? "메인과 동일" : "내용 수정됨", color: isSame ? SermonTheme.success : SermonTheme.warning)
    }

    // MARK: - 에디터/뷰어 진입 (3·4단계 완료 — 에디터는 SermonEditorView, 뷰어는 SermonViewerView)

    @ViewBuilder
    private func deliveryEditorLink(_ delivery: SermonDelivery) -> some View {
        if isPhoneIdiom {
            NavigationLink {
                SermonEditorView(subject: .delivery(delivery))
            } label: {
                Text("편집")
            }
            .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
        } else {
            Button {
                openWindow(id: "sermon-editor", value: SermonContentTarget.delivery(delivery))
            } label: {
                Text("편집")
            }
            .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
        }
    }

    @ViewBuilder
    private func deliveryViewerLink(_ delivery: SermonDelivery) -> some View {
        if isPhoneIdiom {
            NavigationLink {
                SermonViewerView(subject: .delivery(delivery))
            } label: {
                Text("뷰어")
            }
            .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: accent))
        } else {
            Button {
                openWindow(id: "sermon-viewer", value: SermonViewerTarget.delivery(delivery))
            } label: {
                Text("뷰어")
            }
            .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: accent))
        }
    }

    // MARK: - 로드/저장

    private func save() {
        sermon.updatedAt = .now
        try? modelContext.save()
    }

    /// 개별 활용 이력 삭제 — `deliveryRow` 컨텍스트 메뉴 전용. `Sermon` 자체
    /// 삭제(파급력 큼, 확인 대화상자 필요)와 달리 이건 `SermonHomeView`의
    /// "이대로 진행" 승인안대로 확인 없이 바로 지운다.
    private func deleteDelivery(_ delivery: SermonDelivery) {
        modelContext.delete(delivery)
        try? modelContext.save()
    }
}

/// "+ 이 설교로 새 모임에서 사용" 시트 — 모임(기존 선택 또는 새로 만들기) +
/// 날짜를 입력받아 `SermonDelivery`를 만든다. 본문은 메인 `Sermon`의 현재
/// 내용을 그대로 복사해 시작한다(설계 문서 2.2 S-SER1a).
// [2026-09-29 수정] 사용자 요청 — "'이 설교를 새 모임에서 사용' 버튼을
// 왼쪽 설교 리스트로 이동." 그 버튼(과 여기로 이어지는 시트)이
// `SermonHomeView.sermonSidebar`(다른 파일)로 옮겨가며, 그 파일에서도 이
// 타입을 쓸 수 있어야 한다 — 지금까지 `private`(파일 전용)였던 걸 이름
// 충돌 걱정 없이(모듈 전체에 이 이름을 쓰는 선언이 이 파일 하나뿐임을
// grep으로 확인) 기본 접근수준(internal)으로 넓힌다. `ThemedNavigationBar
// BackgroundModifier`처럼 여러 파일에 "같은 이름을 각자 private로 중복
// 선언"하는 관례와는 다른 경우다 — 그건 화면마다 다른 구현이 필요해서
// 일부러 나눈 것이고, 이건 완전히 같은 시트를 두 파일이 그대로 공유하는
// 것이라 원래 있던 하나를 그대로 재사용하는 쪽이 맞다.
struct SermonDeliveryCreationSheet: View {
    let sermon: Sermon

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \SermonGathering.name) private var allGatherings: [SermonGathering]
    @State private var selectedGatheringID: PersistentIdentifier?
    @State private var isCreatingNewGathering = false
    @State private var newGatheringName = ""
    @State private var deliveredAt: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("모임") {
                    Picker("모임 종류", selection: $selectedGatheringID) {
                        Text("선택 안 함").tag(PersistentIdentifier?.none)
                        ForEach(allGatherings) { gathering in
                            Text(gathering.name).tag(Optional(gathering.persistentModelID))
                        }
                    }
                    Button("새 모임 이름 추가…") { isCreatingNewGathering = true }
                }
                Section("날짜") {
                    DatePicker("날짜", selection: $deliveredAt, displayedComponents: .date)
                }
            }
            .navigationTitle("새 모임에서 사용")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("만들기") { createDelivery() }
                }
            }
            .alert("새 모임", isPresented: $isCreatingNewGathering) {
                TextField("모임 이름", text: $newGatheringName)
                Button("취소", role: .cancel) { newGatheringName = "" }
                Button("추가") { createGathering() }
            }
        }
    }

    private func createGathering() {
        let trimmed = newGatheringName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let gathering = SermonGathering(name: trimmed)
        modelContext.insert(gathering)
        try? modelContext.save()
        selectedGatheringID = gathering.persistentModelID
        newGatheringName = ""
    }

    private func createDelivery() {
        let gathering = selectedGatheringID.flatMap { id in
            allGatherings.first { $0.persistentModelID == id }
        }
        let delivery = SermonDelivery(
            deliveredAt: deliveredAt,
            contentHtml: sermon.contentHtml,
            contentText: sermon.contentText,
            paragraphStyles: sermon.paragraphStyles,
            sermon: sermon,
            gathering: gathering
        )
        modelContext.insert(delivery)
        try? modelContext.save()
        dismiss()
    }
}
