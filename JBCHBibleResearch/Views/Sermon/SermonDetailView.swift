//
//  SermonDetailView.swift
//  JBCHBibleResearch
//
//  S-SER1a "설교 상세·이력" — 메인 설교문(Sermon) 하나와, 그 설교가 쓰인 모임별 활용
//  이력(SermonDelivery)을 보여준다. 제목은 읽기 전용이며 수정은 `SermonEditorView`에서 한다.
//  설계 문서 claude/sermon-management-screens-and-schema.md 2.2 S-SER1a 참고.
//
//  태그 편집은 이 화면이 아니라 `SermonEditorView` 하단에 있다.
//  태그 칩 색 등 액센트는 "내 설교" 전체가 `SermonTheme.accent`를 공유한다.
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


/// 설정의 테마색상에 따라 내비게이션 바 배경/색조를 바꾸는 modifier. WCAG 상대휘도로 다크/라이트를 결정한다.
///
/// `DocumentsHomeView`/`BibleReadingView`/`WordNoteHomeView`/`SearchView`와 같은 구현을 파일마다
/// `private`로 중복 선언한다 — Swift는 같은 모듈에서 `private` 선언과 internal 선언의 이름이
/// 같으면 접근 범위와 무관하게 재선언 충돌로 처리하므로, 하나라도 `private`가 아니면 안 된다.
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

    private var settings: UserSettingsStore { .shared }

    /// 테마색상 반영 액센트 — `SermonHomeView.accent`와 같은 코드.
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
                // 아이패드·맥은 편집/뷰어 버튼이 왼쪽 설교함(`SermonHomeView.sermonSidebar`) 행에 있어 중복하지 않는다.
                // 아이폰은 이 화면이 push로 도달하는 유일한 경로라 남긴다.
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

    /// 읽기 전용 표시 — 제목 수정은 `SermonEditorView.titleField` 한 곳으로 모았다.
    private var titleSection: some View {
        Text(sermon.title.isEmpty ? "제목 없음" : sermon.title)
            .font(.title2.bold())
            .foregroundStyle(settings.bibleTextColor ?? .primary)
    }

    // MARK: - 본문 편집 / 뷰어로 보기 (목업 Detail.dc.html의 버튼 한 쌍)
    //
    // ⚠️ 아이폰은 다중 씬(멀티 윈도우)을 지원하지 않아 `openWindow`를 부르면 실기기 런타임
    // 에러가 난다(`DocumentsHomeView.isPhoneIdiom` 참고) — 아이폰만 `NavigationLink`로
    // 같은 NavigationStack에 push하고, 맥/아이패드는 `openWindow`를 쓴다.

    private var actionButtons: some View {
        HStack(spacing: 10) {
            editorButton
            viewerButton
            mapButton
        }
    }

    @ViewBuilder
    private var editorButton: some View {
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

    /// 아이폰에서만 실제로 보인다(`actionButtons` 참고). 이 화면이 아이패드·맥에서 쓰일 때를 대비해
    /// `editorButton`/`viewerButton`과 같이 두 분기를 모두 갖춘다.
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
                // "새 모임에서 사용" 버튼은 `SermonHomeView.sermonSidebar`의 설교 행에 있다.
                // 아이폰 목록 행 `sermonRow`에는 아직 없다.
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
        // `SermonDelivery` 삭제는 다른 레코드를 캐스케이드로 지우지 않는다(`verseReferences`만 함께
        // 지워지는 부속 데이터) — 확인 대화상자 없이 컨텍스트 메뉴로 삭제하는 Document/WordNote 관례를 따른다.
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

    /// 개별 활용 이력 삭제 — `deliveryRow` 컨텍스트 메뉴 전용. `Sermon` 자체 삭제와 달리 파급력이 작아 확인 없이 지운다.
    private func deleteDelivery(_ delivery: SermonDelivery) {
        modelContext.delete(delivery)
        try? modelContext.save()
    }
}

/// "새 모임에서 사용" 시트 — 모임(기존 선택 또는 새로 만들기) + 날짜를 입력받아
/// `SermonDelivery`를 만든다. 본문은 메인 `Sermon`의 현재 내용을 복사해 시작한다.
/// `SermonHomeView.sermonSidebar`에서도 쓰므로 `private`가 아니다.
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
