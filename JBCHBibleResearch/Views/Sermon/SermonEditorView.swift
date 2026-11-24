//
//  SermonEditorView.swift
//  JBCHBibleResearch
//
//  S-SER2 "설교 작성 — 프리셋 스타일 리치 에디터".
//  메인 `Sermon`과 특정 회차 `SermonDelivery` 양쪽을 같은 화면으로 편집한다
//  (대상만 다르다). `SermonDelivery`에는 title 필드가 없어 제목 입력은
//  `.sermon` 대상일 때만 보이고, 회차에서는 대주제(mainTheme) 문단이 제목 역할을 한다.
//  문단 스타일 6종은 항상 보이는 가로 pill 한 줄로 고르고, 굵게/기울임/
//  말씀구절 추가/서식 도구는 그 아래·옆에 둔다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif


/// `RichTextEditor.swift`의 `toolbarFontSizes`와 같은 목적 — 자주 쓰는 크기들. 2026-10-03 재설계 프리셋
/// 크기(대주제 28 / 중주제 22 / 소주제 18 / 본문 17)를 포함한다. 말씀구절 16.5·인용 14.5처럼 소수인 프리셋은
/// "프리셋 크기로"로 되돌린다(메뉴 라벨이 정수 표기라 넣지 않는다).
private let sermonToolbarFontSizes: [CGFloat] = [12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 28, 32, 34, 40]
/// 줄간격 메뉴의 줄 높이 배수(글자 크기 대비). 글꼴 자체의 기본 줄 높이(한글 글꼴은 대개 1.4~1.5배)보다 좁게는 만들 수 없어
/// (`SermonParagraphStyleCodec.makeParagraphStyle`은 그 초과분만 `lineSpacing`으로 준다) 1.5부터 둔다.
private let sermonToolbarLineHeights: [Double] = [1.5, 1.8, 2.0, 2.2, 2.5]

/// 에디터 저장 상태 표시 — 입력 후 2초 쉬면 자동 저장된다.
enum SermonSaveState: Equatable {
    case saved(Date?)
    case pending
    case saving
}

struct SermonEditorView: View {
    let subject: SermonEditingSubject
    /// `true`면 새 설교 작성 모드 — 제목 입력이 보이고, `save()`가 제목·본문 중 하나라도 있을 때만
    /// 실제로 insert한다(아무 입력 없이 닫으면 저장하지 않음). 수정일자는 `save()`의 `touchUpdatedAt()`이 채운다.
    var isNewSermon: Bool = false
    /// 아이패드·맥은 오른쪽 패널에 이 화면을 직접 얹고 아이폰은 값 기반 push라, `.sheet`/`.fullScreenCover`
    /// 전제의 `dismiss`에 기댈 수 없다(특히 아이패드·맥). 호출부가 넘긴 이 클로저로 "취소/닫기"를 구현한다.
    var onRequestClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    /// `onRequestClose`가 없는 곳(아이폰 push)에서 마인드맵 "설교문 적용" 후 이 화면을 닫는 대체 수단.
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sermonHasFixedTitle) private var hasFixedTitle

    @State private var contentHtml: String = ""
    @State private var contentText: String = ""
    @State private var paragraphStyles: String = ""
    @State private var isVersePickerPresented = false
    @State private var hasLoaded = false
    /// 새 설교 제목 입력 상태 — `isNewSermon`일 때만 쓰인다.
    @State private var title: String = ""
    /// `isNewSermon`일 때 `modelContext.insert(sermon)`을 이미 했는지 — 중복 삽입 방지.
    @State private var hasInsertedNewSermon = false
    /// 마인드맵 "설교문 적용"이 본문을 바깥에서 바꿨을 때 true — 이 편집기가 든 옛 본문 사본이
    /// `onDisappear → save()`로 적용된 내용을 덮어쓰는 것을 막는다.
    @State private var skipSaveOnDisappear = false

    // MARK: [2026-11-14 내 설교 고도화] 자동저장·찾기·개요·분량·서식 복사
    @Environment(\.scenePhase) private var scenePhase
    @State private var find = SermonFindController()
    @State private var saveState: SermonSaveState = .saved(nil)
    @State private var autosaveTask: Task<Void, Never>?
    @State private var stats = SermonTextStats()
    @State private var outline: [SermonOutlineEntry] = []
    @State private var copiedFormat: SermonCopiedFormat?
    @State private var statusMessage: String?
    @State private var statusMessageTask: Task<Void, Never>?
    @State private var isParagraphPopoverPresented = false
    @State private var isOutlineSheetPresented = false
    @State private var isResearchSheetPresented = false
    @AppStorage(SermonPrefs.outlineVisible) private var isOutlineVisible = false
    @AppStorage("sermon.editor.researchVisible") private var isResearchVisible = false
    @AppStorage(SermonPrefs.paneTab) private var paneTabRaw = "bible"
    @AppStorage(SermonPrefs.charsPerMinute) private var charsPerMinute = SermonPrefs.defaultCharsPerMinute

    /// `.sermon`이면 `Sermon.sermonTags`, `.delivery`면 회차의 `deliveryTags`(`SermonEditingSubject.tags`) —
    /// 두 태그 집합은 서로 독립이다. `SermonDetailView.tagSection`과 같은 패턴.
    @State private var tags: [Tag] = []
    @State private var tagInput = ""
    @State private var tagSuggestions: [Tag] = []
    @State private var hasLoadedTags = false

    #if os(iOS)
    // MARK: 성경 분할 화면(아이패드, `SermonBibleSplit.swift` 참고) — 켜짐 여부·비율은 기기별로 기억한다(`UserSettingsStore`가 아니라 기기 UI 값이라
    // CloudKit으로 동기화하지 않는다). 가로/세로 비율은 따로 기억한다.
    @AppStorage("sermonSplit.isPaneEnabled") private var isSplitPaneEnabled = true
    @AppStorage("sermonSplit.landscapeFraction") private var splitLandscapeFraction: Double = 1.0 / 3.0
    @AppStorage("sermonSplit.portraitFraction") private var splitPortraitFraction: Double = 0.45
    /// 분할 컨테이너(= 이 창)의 실제 크기 — 가로/세로 판정과 "패널을 둘 만큼 넓은지" 판정에 쓴다.
    @State private var splitContainerSize: CGSize = .zero
    #endif

    // `@State`로 둬 부모가 다시 그려져도 같은 프록시(= 같은 텍스트뷰 연결·찾기 상태)를 유지한다.
    @State private var proxy = SermonParagraphEditingProxy()

    private var settings: UserSettingsStore { .shared }

    /// 에디터는 뷰어와 같은 고정 미색 종이 위에 그려지므로(`SermonViewerPaper`) 강조색도 라이트 값을 쓴다.
    /// 바깥 환경의 colorScheme/테마색상을 읽으면 다크 모드·어두운 테마에서 밝은 강조색이 되어 미색 위에서 안 보인다.
    private var accent: Color { SermonTheme.accent(.light) }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// "취소"/"완료" 라벨 전환용 — 제목 또는 본문이 입력돼 있는지. `save()`의 지연 삽입 가드와
    /// 같은 기준이어야 라벨이 실제 저장 여부와 일치한다.
    private var hasEnteredContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 페이지 안 "완료/취소" 줄을 보일지. 창/시트/패널로 열려 `onRequestClose`가 있는 아이패드·맥에서만 보인다.
    /// 아이폰은 push된 화면이라 시스템 뒤로가기 "<"가 `onDisappear → save()`를 태우므로(시트일 때는 호출부가 자기
    /// 툴바에 "취소"를 둔다) 이 줄이 필요 없다. `#if os(iOS)`가 아니라 `isPhoneIdiom`으로 판단해야 아이패드에서도 보인다.
    private var showsCloseBar: Bool { onRequestClose != nil && !isPhoneIdiom }

    var body: some View {
        #if os(iOS)
        SermonBibleSplitContainer(
            isHorizontal: splitIsHorizontal,
            isPaneShown: isSplitPaneShown,
            paneFraction: splitFractionBinding,
            ratioText: splitRatioText,
            editor: { editorBody },
            pane: { splitPane }
        )
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { splitContainerSize = $0 }
        #else
        editorBody
        #endif
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            headerRow
            if let parentSermon = subject.parentSermon {
                referencedMainSermonBanner(parentSermon)
            }
            styleToolbar
            Divider()
            if find.isVisible {
                SermonFindBar(find: find, proxy: proxy, accent: accent)
                Divider()
            }
            editorArea
            Divider()
            statusBar
            Divider()
            tagSection
        }
        .navigationTitle(hasFixedTitle ? SermonFixedTitle.navigationText : (isNewSermon ? String(localized: "새 설교 작성") : String(localized: "설교 작성")))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        .toolbarBackground(SermonViewerPaper.color, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        #endif
        .sheet(isPresented: $isVersePickerPresented) {
            SermonVerseReferencePicker { text, bookId, chapter, verseStart, verseEnd in
                insertVerseQuote(text: text, bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
            }
        }
        .sheet(isPresented: $isOutlineSheetPresented) {
            NavigationStack {
                SermonOutlinePanel(entries: outline, stats: stats, accent: accent) { index in
                    isOutlineSheetPresented = false
                    proxy.scrollToParagraph(index)
                }
                .navigationTitle(String(localized: "개요"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "닫기")) { isOutlineSheetPresented = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isResearchSheetPresented) {
            NavigationStack {
                researchPane
                    .navigationTitle(String(localized: "연구 자료"))
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "닫기")) { isResearchSheetPresented = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            sceneDiagNote("편집기 onAppear")
            loadIfNeeded()
            loadTagsIfNeeded()
            proxy.onVerseSubstitute = { mode in performVerseSubstitution(mode) }
        }
        .onDisappear {
            sceneDiagNote("편집기 onDisappear")
            autosaveTask?.cancel()
            proxy.clearFind()
            // 마인드맵이 본문을 바꾼 뒤 닫히는 경우엔 저장하지 않는다(옛 사본이 새 본문을 덮어씀) —
            // 직전에 `onFlush`에서 이미 저장했다.
            if !skipSaveOnDisappear { save() }
        }
        // 입력이 있으면 2초 뒤 자동 저장, 분량·개요·찾기 결과도 같이 갱신한다.
        .onChange(of: contentHtml) { _, _ in scheduleAutosave() }
        .onChange(of: contentText) { _, _ in
            stats = SermonTextStats.compute(text: contentText)
            refreshOutline()
            find.refresh(proxy: proxy, resetCurrent: false)
        }
        .onChange(of: paragraphStyles) { _, _ in refreshOutline(); scheduleAutosave() }
        .onChange(of: isOutlineVisible) { _, _ in refreshOutline() }
        .onChange(of: title) { _, _ in scheduleAutosave() }
        // 앱이 비활성/백그라운드로 가면 기다리지 않고 바로 저장한다(씬 flush).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, hasLoaded, !skipSaveOnDisappear { save() }
        }
        // 마인드맵 "설교문 적용" 흐름: (1) `onFlush` — 적용 직전 현재 본문을 즉시 저장, (2) 마인드맵이
        // 적용·저장, (3) `onReplaced` — 저장 없이 닫는다. 닫기는 `onRequestClose`, 없으면 `dismiss()`.
        .onSermonExternalContentChange(
            onFlush: flushForExternalChange,
            onReplaced: closeForExternalChange
        )
        // 배경은 설정 테마·다크 모드와 무관하게 뷰어와 같은 미색으로 고정한다(`SermonViewerView` 참고).
        // 배경이 항상 밝으므로 SwiftUI 요소(글자·메뉴·버튼)도 라이트 외형으로 고정한다.
        .background(SermonViewerPaper.color.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        #endif
    }

    // MARK: - 성경 분할 화면 (아이패드)

    /// 헤더의 [성경 패널 켜기/끄기 | 비율 ▾]를 보일지 — 분할을 둘 만큼 넓은 아이패드 창에서만(좁은 멀티태스킹 창에서는 숨긴다).
    private var showsSplitControls: Bool {
        #if os(iOS)
        return isSplitAvailable
        #else
        return false
        #endif
    }

    #if os(iOS)
    /// 가로(좌우 분할)인지 — 컨테이너 크기 기준이라 창 모드·Split View에서도 맞다.
    private var splitIsHorizontal: Bool { splitContainerSize.width >= splitContainerSize.height }

    /// 패널을 둘 만큼 큰 창인지. 가로는 폭 820pt 이상(에디터 ≥ 약 540 + 성경 ≈ 260 이상), 세로는 높이 760pt 이상.
    /// 아직 크기를 못 잰 첫 프레임(.zero)과 아이폰은 false다.
    private var isSplitAvailable: Bool {
        guard !isPhoneIdiom, splitContainerSize != .zero else { return false }
        return splitIsHorizontal ? splitContainerSize.width >= 820 : splitContainerSize.height >= 760
    }

    private var isSplitPaneShown: Bool { isSplitPaneEnabled && isSplitAvailable }

    private var splitFractionBinding: Binding<Double> {
        Binding(
            get: { splitIsHorizontal ? splitLandscapeFraction : splitPortraitFraction },
            set: { newValue in
                if splitIsHorizontal { splitLandscapeFraction = newValue } else { splitPortraitFraction = newValue }
            }
        )
    }

    /// 분할선 칩·메뉴 글자 — 에디터 : 성경. 프리셋(1/2/3)에 가까우면 정수, 아니면 소수 한 자리.
    private var splitRatioText: String {
        let fraction = min(max(splitFractionBinding.wrappedValue, SermonBibleSplitContainer<EmptyView, EmptyView>.fractionRange.lowerBound),
                           SermonBibleSplitContainer<EmptyView, EmptyView>.fractionRange.upperBound)
        let ratio = (1 - fraction) / fraction
        if abs(ratio - ratio.rounded()) < 0.15 { return "\(Int(ratio.rounded())) : 1" }
        return String(format: "%.1f : 1", ratio)
    }

    /// 성경 패널 — 번역본 선택이 따로인 보조 성경 조회. [에디터에 인용 삽입]이 `insertVerseQuote`로 이어진다.
    private var splitPane: some View {
        let isBible = paneTabRaw != "research"
        return VStack(spacing: 0) {
            SermonSegmentedPill(
                items: [
                    .init(tag: "bible", label: String(localized: "성경")),
                    .init(tag: "research", label: String(localized: "연구 자료")),
                ],
                selection: $paneTabRaw, accent: accent
            )
            .padding(8)
            Divider()
            // 두 패널을 모두 살려 둔 채 겹쳐 놓고 투명도로 전환한다 — 탭을 오가도 성경 조회 위치·연구 자료 선택이 유지된다.
            ZStack {
                BibleReadingView(isPrimaryWindow: false)
                    .environment(\.sermonQuoteInsert, SermonQuoteInsertAction { text, bookId, chapter, verseStart, verseEnd in
                        insertVerseQuote(text: text, bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
                    })
                    .opacity(isBible ? 1 : 0)
                    .allowsHitTesting(isBible)
                    .accessibilityHidden(!isBible)
                researchPane
                    .opacity(isBible ? 0 : 1)
                    .allowsHitTesting(!isBible)
                    .accessibilityHidden(isBible)
            }
        }
    }

    private func setSplitFraction(_ fraction: Double) {
        splitFractionBinding.wrappedValue = fraction
    }
    #endif

    /// 헤더의 [성경 패널 토글 | 비율 메뉴]. 목업 `Sermon-Split-Landscape`의 헤더 오른쪽 묶음.
    @ViewBuilder
    private var splitControls: some View {
        #if os(iOS)
        if isSplitAvailable {
            HStack(spacing: 6) {
                Button {
                    isSplitPaneEnabled.toggle()
                } label: {
                    Label(String(localized: "성경"), systemImage: "book.pages")
                }
                .buttonStyle(SermonMiniPillButtonStyle(isFilled: isSplitPaneEnabled, tint: accent))
                .accessibilityLabel(isSplitPaneEnabled ? String(localized: "성경 패널 끄기") : String(localized: "성경 패널 켜기"))

                if isSplitPaneEnabled {
                    Menu {
                        Button("1 : 1") { setSplitFraction(0.5) }
                        Button(String(localized: "2 : 1 (기본)")) { setSplitFraction(1.0 / 3.0) }
                        Button("3 : 1") { setSplitFraction(0.25) }
                        Divider()
                        Button(String(localized: "성경 패널 접기")) { isSplitPaneEnabled = false }
                    } label: {
                        Text("\(splitRatioText) ▾")
                    }
                    .menuStyle(.button)
                    .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                    .accessibilityLabel(String(localized: "에디터와 성경 패널 비율"))
                }
            }
        }
        #endif
    }

    // MARK: - 완료/취소 (제목 줄 맨 오른쪽)

    /// "새 설교/설교 편집" 안내 줄을 없애고, "완료/취소" 버튼을 제목 줄 맨 오른쪽(`headerRow`)으로 옮겼다. 동작은 예전과
    /// 같다: 저장 방식은 그대로 두고 라벨만 실제 동작에 맞춘다 — 새 설교에서 제목·본문이 모두 비어 있으면 "취소"(`save()`
    /// 가드가 저장을 건너뜀), 그 외에는 "완료"(저장 후 닫기). 이미 있는 설교/회차 편집은 항상 "완료"다(제목·태그·구절은
    /// 입력 즉시 반영되므로 되돌리는 취소는 없다).
    private var closeButton: some View {
        let isCancel = isNewSermon && !hasEnteredContent
        return Button(isCancel ? String(localized: "취소") : String(localized: "완료")) {
            // 창을 닫을 때 `onDisappear → save()`가 한 번 더 돌지만, 닫힘 시점에 기대지 않고 먼저 저장한다
            // (`save()`는 중복 호출돼도 같은 값을 다시 쓸 뿐이며 새 설교의 insert는 한 번만 한다).
            if !isCancel { save() }
            sceneDiagNote("편집기 \(isCancel ? "취소" : "완료") → onRequestClose(dismissWindow) 호출")
            onRequestClose?()
        }
        .buttonStyle(SermonMiniPillButtonStyle(isFilled: !isCancel, tint: accent))
        .accessibilityLabel(isCancel ? String(localized: "취소하고 닫기") : String(localized: "저장하고 닫기"))
    }

    /// 맨 위 한 줄 — `.sermon`은 [제목 입력 ……… 완료], 제목이 없는 `.delivery`(모임 설교문)는 완료 버튼만 오른쪽에 둔다.
    /// 창/시트로 열리지 않아 `showsCloseBar`가 false인 경우(아이폰 push 화면)는 버튼 없이 제목만 보인다.
    @ViewBuilder
    private var headerRow: some View {
        switch subject {
        case .sermon:
            titleField
        case .delivery:
            HStack(spacing: 10) {
                Spacer()
                saveStateChip
                splitControls
                if showsCloseBar { closeButton }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(SermonViewerPaper.color)
            Divider()
        }
    }

    // MARK: - 새 설교 제목 (요구사항 — "새 설교 작성 레이어 팝업 제거, 본문
    /// `.sermon`(메인 설교문) 대상일 때만 보이는 제목 입력(새 설교·기존 설교 공통). `.delivery`는
    /// title 필드가 없어 제외한다. 새 설교는 아직 `modelContext`에 없는 `@State title`에, 기존 설교는
    /// `sermon.title`에 직접 바인딩하며 디스크 저장은 `save()`(제출/화면 이탈 시)가 맡는다.
    @ViewBuilder
    private var titleField: some View {
        if case .sermon(let sermon) = subject {
            VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if isNewSermon {
                    TextField("설교 제목", text: $title)
                        .font(.title3.bold())
                        .foregroundStyle(Color.primary)
                        .textFieldStyle(.plain)
                        .onSubmit { save() }
                } else {
                    TextField(
                        "설교 제목",
                        text: Binding(get: { sermon.title }, set: { sermon.title = $0 })
                    )
                    .font(.title3.bold())
                    .foregroundStyle(Color.primary)
                    .textFieldStyle(.plain)
                    .onSubmit { save() }
                }
                saveStateChip
                splitControls
                if showsCloseBar {
                    closeButton
                }
            }
            metaRow(sermon)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SermonViewerPaper.color)
            Divider()
        }
    }

    // MARK: - 메타데이터 줄 (상태 · 주 본문) / 저장 표시

    /// 상태(초안/다듬는 중/완성)와 주 본문. 주 본문을 비워 두면 본문 속 첫 성경 참조를 제안값으로 보여 준다.
    private func metaRow(_ sermon: Sermon) -> some View {
        let suggestion = sermon.effectiveMainPassage
        return HStack(spacing: 10) {
            Menu {
                Picker(String(localized: "상태"), selection: Binding(get: { sermon.status }, set: { sermon.status = $0; scheduleMetaSave() })) {
                    ForEach(SermonStatus.allCases, id: \.self) { status in Text(status.displayName).tag(status) }
                }
            } label: {
                SermonBadge(text: sermon.status.displayName, color: sermon.status.tint, systemImage: "circle.fill")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(String(localized: "설교 상태"))

            Image(systemName: "book.closed").foregroundStyle(.secondary).font(.caption)
            TextField(
                suggestion?.isSuggested == true
                    ? String(localized: "주 본문 · 제안: \(suggestion?.text ?? "")")
                    : String(localized: "주 본문 (예: 요 3:1-15)"),
                text: Binding(get: { sermon.mainPassage }, set: { sermon.mainPassage = $0; scheduleMetaSave() })
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            if sermon.mainPassage.isEmpty, let suggestion, suggestion.isSuggested {
                Button(String(localized: "제안 적용")) { sermon.mainPassage = suggestion.text; scheduleMetaSave() }
                    .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
            }
        }
    }

    private func scheduleMetaSave() {
        if case .sermon(let sermon) = subject, !isNewSermon || hasInsertedNewSermon { sermon.updatedAt = .now }
        scheduleAutosave(force: true)
    }

    private var saveStateChip: some View {
        Group {
            switch saveState {
            case .pending:
                Label(String(localized: "저장 대기"), systemImage: "ellipsis.circle")
            case .saving:
                Label(String(localized: "저장 중…"), systemImage: "arrow.triangle.2.circlepath")
            case .saved(let date):
                if let date {
                    Label(String(localized: "저장됨 \(date.formatted(date: .omitted, time: .shortened))"), systemImage: "checkmark.circle")
                } else {
                    Label(String(localized: "저장됨"), systemImage: "checkmark.circle")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(saveState == .pending ? SermonTheme.warning : Color.secondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - 태그 (요구사항 — "태그 입력은 메인 설교문, 모임에 따른 설교문
    // 하단에 추가할 수 있도록 할 것", 2026-09-29)
    //
    // ⚠️ 태그 줄은 화면 맨 아래 고정 영역에 둔다 — 문단 목록이 SwiftUI `ForEach`가 아니라
    // `SermonParagraphEditor`(UITextView/NSTextView 래퍼)라 같은 스크롤 안에 SwiftUI 콘텐츠를
    // 끼워 넣을 수 없기 때문이다.
    private var tagSectionLabel: String {
        switch subject {
        case .sermon: return String(localized: "설교 태그")
        case .delivery: return String(localized: "이 회차만의 태그 (메인 설교 태그와 별도)")
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tagSectionLabel)
                .font(.caption)
                .foregroundStyle(Color.secondary)

            FlowLayoutHStack {
                ForEach(tags) { tag in
                    HStack(spacing: 4) {
                        Text(tag.name)
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.15))
                    .foregroundStyle(accent)
                    .clipShape(Capsule())
                }
            }

            HStack {
                TextField("태그 입력 후 Enter", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit { commitTagInput() }
                    .onChange(of: tagInput) { _, newValue in
                        updateTagSuggestions(for: newValue)
                    }
                if !tagSuggestions.isEmpty {
                    Menu {
                        ForEach(tagSuggestions) { suggestion in
                            Button(suggestion.name) { addTag(suggestion) }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                }
            }
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SermonViewerPaper.color)
    }

    // MARK: - "참조한 메인 설교" 배너 (요구사항 6)

    /// `.delivery`를 편집할 때만 보인다. 누르면 S-SER3(뷰어)로만 이동하고 편집 화면으로는
    /// 연결하지 않아 메인 설교의 수정 불가를 보장한다.
    @ViewBuilder
    private func referencedMainSermonBanner(_ mainSermon: Sermon) -> some View {
        let label = bannerLabel(mainSermon)
        Group {
            if isPhoneIdiom {
                NavigationLink {
                    SermonViewerView(subject: .sermon(mainSermon))
                } label: {
                    bannerContent(label)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    openWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(mainSermon))
                } label: {
                    bannerContent(label)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bannerLabel(_ mainSermon: Sermon) -> String {
        let gatheringName = subject.gathering?.name ?? String(localized: "모임 미지정")
        let dateText = subject.deliveredAt?.formatted(date: .abbreviated, time: .omitted) ?? ""
        let title = mainSermon.title.isEmpty ? String(localized: "제목 없음") : mainSermon.title
        return String(localized: "참조한 메인 설교(읽기 전용) · \(gatheringName) \(dateText) — \(title)")
    }

    private func bannerContent(_ label: String) -> some View {
        HStack {
            Image(systemName: "arrow.up.doc")
                .foregroundStyle(accent)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(accent.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - 툴바 (2행: ① 구조·삽입·도구 ② 서식)

    /// 아이콘 버튼 한 개 — 켜진 상태는 액센트 배경으로 보인다.
    private func toolIcon(_ systemName: String, label: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 28)
                .background(isOn ? accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .foregroundStyle(isOn ? accent : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    /// 현재 값을 보여 주는 칩(글꼴·크기 등) 바탕.
    private func chipBackground<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(Color.primary)
            .contentShape(Rectangle())
    }

    private var styleToolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            structureRow
            formatToolbar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SermonViewerPaper.color)
        .tint(accent)
    }

    /// 1행 — 문단 스타일 pill 6종 · 굵게/기울임 · 말씀구절 추가 · 구절 치환 · 서식 복사/붙여넣기 · 찾기/개요/연구 자료.
    private var structureRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 단축키: F1~F6(텍스트뷰 `SermonEditor*TextView`가 처리) 및 ⌃1~6(한글 방식) = 대주제·중주제·소주제·말씀구절·인용·본문(pill 순서와 동일).
                // ⌘1~⌘5는 AppCommands(화면 전환)가 쓰고 있어 ⌘ 대신 Control을 쓴다.
                ForEach(Array(SermonParagraphStyle.allCases.enumerated()), id: \.element) { index, style in
                    Button {
                        proxy.applyParagraphStyle(style, settings: .shared)
                        proxy.activeStyle = style
                    } label: {
                        Text(styleDisplayName(style))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(style == proxy.activeStyle ? accent : Color.secondary.opacity(0.12))
                            .foregroundStyle(style == proxy.activeStyle ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
                    .help("\(styleDisplayName(style)) (F\(index + 1) · ⌃\(index + 1))")
                }

                Divider().frame(height: 18)

                toolIcon("bold", label: String(localized: "굵게")) { proxy.toggleBold() }
                toolIcon("italic", label: String(localized: "기울임")) { proxy.toggleItalic() }

                Divider().frame(height: 18)

                Button {
                    isVersePickerPresented = true
                } label: {
                    Label("말씀구절 추가", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .fixedSize()

                // 입력한 "(책 장:절)"을 앱의 설교 인용 번역본 구절로 바꾼다 — 단축키·우클릭/길게 누르기 메뉴도 같은 동작.
                Menu {
                    Button {
                        performVerseSubstitution(.verseStyle)
                    } label: {
                        Label("\(String(localized: "말씀구절 스타일로 치환"))  \(SermonShortcut.load(mode: .verseStyle).label)", systemImage: "text.quote")
                    }
                    Button {
                        performVerseSubstitution(.inline)
                    } label: {
                        Label("\(String(localized: "현재 스타일 유지하며 치환"))  \(SermonShortcut.load(mode: .inline).label)", systemImage: "text.insert")
                    }
                } label: {
                    chipBackground {
                        HStack(spacing: 4) {
                            Image(systemName: "text.badge.checkmark")
                            Text(String(localized: "구절 치환"))
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .help(String(localized: "선택하거나 커서를 둔 '요 3:16' 같은 표기를 성경 본문으로 바꿉니다."))

                Divider().frame(height: 18)

                toolIcon("paintbrush", label: String(localized: "서식 복사 (⌥⌘C)"), isOn: copiedFormat != nil) { copyFormat() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                toolIcon("paintbrush.pointed", label: String(localized: "서식 붙여넣기 (⌥⌘V)")) { pasteFormat() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                    .disabled(copiedFormat == nil)
                    .opacity(copiedFormat == nil ? 0.38 : 1)

                Divider().frame(height: 18)

                toolIcon("magnifyingglass", label: String(localized: "문서에서 찾기 (⌘F)"), isOn: find.isVisible) { toggleFind() }
                    .keyboardShortcut("f", modifiers: .command)
                toolIcon("list.bullet.indent", label: String(localized: "개요"), isOn: isOutlineVisible) { toggleOutline() }
                toolIcon("books.vertical", label: String(localized: "연구 자료"), isOn: isResearchActive) { toggleResearch() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 2행 — 현재 값을 보여 주는 글꼴·크기·색 칩, 정렬, 줄간격, 문단 모양, 목록, 강조.
    /// 각 메뉴 맨 위 "프리셋 ○○로" 항목은 `nil`을 넘겨 현재 문단 스타일의 프리셋 값으로 되돌린다(수동 지정을 취소하는 유일한 방법).
    private var formatToolbar: some View {
        let format = proxy.activeFormat
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("프리셋 글꼴로") { proxy.applyFontFamily(nil, settings: settings) }
                    Divider()
                    Menu("Paperlogy") {
                        ForEach(BundledFonts.paperlogyEntries) { entry in
                            Button(entry.displayName) { proxy.applyFontFamily(entry.postScriptName, settings: settings) }
                        }
                    }
                    Menu("고운바탕") {
                        ForEach(BundledFonts.gowunBatangEntries) { entry in
                            Button(entry.displayName) { proxy.applyFontFamily(entry.postScriptName, settings: settings) }
                        }
                    }
                    // 다국어 글꼴 — Literata(2026-10-29)는 모든 언어, 지역 전용 글꼴(태국어/키릴/베트남어, 2026-10-12)은 그 앱 언어에서만 보인다.
                    // family 이름은 고유명사라 번역하지 않는다.
                    ForEach(BundledFonts.visibleMultilingualFamilies) { family in
                        Menu(family.name) {
                            ForEach(family.entries) { entry in
                                Button(entry.displayName) { proxy.applyFontFamily(entry.postScriptName, settings: settings) }
                            }
                        }
                    }
                    if BundledFonts.isKoreanOnlyFontVisible {
                        Button("조선궁서체") { proxy.applyFontFamily(SpecialPurposeFonts.hanja, settings: settings) }
                    }
                    Divider()
                    Button("시스템 기본") { proxy.applyFontFamily("System", settings: settings) }
                } label: {
                    chipBackground {
                        HStack(spacing: 4) {
                            Text(format.fontName.isEmpty ? String(localized: "글꼴") : format.fontName)
                                .lineLimit(1)
                                .frame(maxWidth: 110, alignment: .leading)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel(String(localized: "글꼴"))

                HStack(spacing: 0) {
                    toolIcon("minus", label: String(localized: "글자 작게")) { stepFontSize(-1) }
                    Menu {
                        Button("프리셋 크기로") { proxy.applyFontSize(nil, settings: settings) }
                        Divider()
                        ForEach(sermonToolbarFontSizes, id: \.self) { size in
                            Button("\(Int(size))pt") { proxy.applyFontSize(size, settings: settings) }
                        }
                    } label: {
                        chipBackground {
                            Text(format.fontSize > 0 ? "\(formatPoints(format.fontSize))pt" : "pt")
                                .monospacedDigit()
                                .frame(minWidth: 40)
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel(String(localized: "글자 크기"))
                    toolIcon("plus", label: String(localized: "글자 크게")) { stepFontSize(1) }
                }

                Menu {
                    Button("프리셋 색상으로") { proxy.applyColor(nil, settings: settings) }
                    Divider()
                    ForEach(Color.memoTextPalette, id: \.hex) { swatch in
                        Button(swatch.name) { proxy.applyColor(swatch.hex, settings: settings) }
                    }
                } label: {
                    chipBackground {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(format.colorHex.flatMap { Color(hex: $0) } ?? Color.primary)
                                .frame(width: 13, height: 13)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel(String(localized: "글자 색"))

                Divider().frame(height: 18)

                toolIcon("text.alignleft", label: String(localized: "왼쪽 정렬"), isOn: format.alignment == .left) { proxy.applyAlignment(.left) }
                toolIcon("text.aligncenter", label: String(localized: "가운데 정렬"), isOn: format.alignment == .center) { proxy.applyAlignment(.center) }
                toolIcon("text.alignright", label: String(localized: "오른쪽 정렬"), isOn: format.alignment == .right) { proxy.applyAlignment(.right) }
                toolIcon("arrow.uturn.backward", label: String(localized: "정렬 기본값으로")) { proxy.applyAlignment(.natural) }

                Divider().frame(height: 18)

                // 줄간격 — 선택한 문단(들)에 적용하고 문단별로 저장한다. 뷰어도 같은 코드로 그린다.
                Menu {
                    Picker("줄간격", selection: Binding<Double?>(
                        get: { proxy.activeExtras.lineHeight },
                        set: { proxy.applyLineHeight($0, settings: settings) }
                    )) {
                        Text("스타일 기본값").tag(Double?.none)
                        ForEach(sermonToolbarLineHeights, id: \.self) { multiple in
                            Text(String(format: "%.1f", multiple)).tag(Double?.some(multiple))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    chipBackground {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.and.down.text.horizontal")
                            Text(proxy.activeExtras.lineHeight.map { String(format: "%.1f", $0) } ?? String(localized: "기본"))
                                .monospacedDigit()
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("줄간격")

                // 들여쓰기·문단 앞뒤 간격 — 값을 바로 보고 조절하는 작은 패널.
                toolIcon("increase.indent", label: String(localized: "문단 모양 (들여쓰기·간격)"), isOn: proxy.activeExtras.hasSpacingOverrides) {
                    isParagraphPopoverPresented.toggle()
                }
                .popover(isPresented: $isParagraphPopoverPresented) { paragraphPopover }

                Menu {
                    Picker("목록", selection: Binding<SermonListKind?>(
                        get: { proxy.activeExtras.list },
                        set: { proxy.applyList($0, settings: settings) }
                    )) {
                        Text("없음").tag(SermonListKind?.none)
                        ForEach(SermonListKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(SermonListKind?.some(kind))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 28)
                        .background(proxy.activeExtras.list != nil ? accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(proxy.activeExtras.list != nil ? accent : Color.primary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("목록")

                Divider().frame(height: 18)

                emphasisButtons
            }
            .buttonStyle(.plain)
            .font(.system(size: 15))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(accent)
    }

    private func formatPoints(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func stepFontSize(_ delta: Double) {
        let current = proxy.activeFormat.fontSize
        guard current > 0 else { return }
        let next = min(96, max(8, (current + delta).rounded()))
        proxy.applyFontSize(CGFloat(next), settings: settings)
    }

    // MARK: 문단 모양 패널

    private var paragraphPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "문단 모양")).font(.headline)
            spacingRow(String(localized: "첫 줄 들여쓰기"), \.firstLineIndent, range: 0...80, step: 4)
            spacingRow(String(localized: "왼쪽 들여쓰기"), \.leftIndent, range: 0...160, step: 4)
            spacingRow(String(localized: "오른쪽 들여쓰기"), \.rightIndent, range: 0...160, step: 4)
            spacingRow(String(localized: "문단 앞 간격"), \.spaceBefore, range: 0...80, step: 2)
            spacingRow(String(localized: "문단 뒤 간격"), \.spaceAfter, range: 0...80, step: 2)
            Divider()
            HStack {
                Text(String(localized: "'기본'은 문단 스타일 프리셋을 따릅니다.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "모두 기본값으로")) {
                    proxy.updateExtra(\.firstLineIndent, to: nil, settings: settings, actionName: String(localized: "문단 모양"))
                    proxy.updateExtra(\.leftIndent, to: nil, settings: settings, actionName: String(localized: "문단 모양"))
                    proxy.updateExtra(\.rightIndent, to: nil, settings: settings, actionName: String(localized: "문단 모양"))
                    proxy.updateExtra(\.spaceBefore, to: nil, settings: settings, actionName: String(localized: "문단 모양"))
                    proxy.updateExtra(\.spaceAfter, to: nil, settings: settings, actionName: String(localized: "문단 모양"))
                }
                .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                .disabled(!proxy.activeExtras.hasSpacingOverrides)
            }
        }
        .padding(16)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    private func spacingRow(
        _ title: String, _ keyPath: WritableKeyPath<SermonParagraphExtras, Double?>,
        range: ClosedRange<Double>, step: Double
    ) -> some View {
        let value = proxy.activeExtras[keyPath: keyPath]
        let action = String(localized: "문단 모양")
        return HStack(spacing: 8) {
            Text(title).font(.subheadline)
            Spacer()
            Text(value.map { "\(formatPoints($0))pt" } ?? String(localized: "기본"))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(value == nil ? Color.secondary : accent)
                .frame(minWidth: 52, alignment: .trailing)
            Stepper("", onIncrement: {
                let next = min(range.upperBound, (value ?? range.lowerBound) + step)
                proxy.updateExtra(keyPath, to: next, settings: settings, actionName: action)
            }, onDecrement: {
                let next = max(range.lowerBound, (value ?? range.lowerBound) - step)
                proxy.updateExtra(keyPath, to: next, settings: settings, actionName: action)
            })
            .labelsHidden()
            Button { proxy.updateExtra(keyPath, to: nil, settings: settings, actionName: action) } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .disabled(value == nil)
            .accessibilityLabel(String(localized: "기본값으로"))
        }
    }

    /// 강조 1·2·3 + 해제 — 드래그해 선택한 글자에만 적용한다(선택이 없으면 흐리게 비활성).
    /// 같은 강조를 다시 누르면 해제, 다른 강조를 누르면 교체된다. 문단 스타일과 별개의 글자 단위 서식이다.
    private var emphasisButtons: some View {
        let enabled = proxy.hasSelection
        return HStack(spacing: 8) {
            Text("강조")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(SermonEmphasis.allCases, id: \.self) { kind in
                Button {
                    proxy.applyEmphasis(kind, settings: settings)
                } label: {
                    emphasisLabel(kind)
                }
                .accessibilityLabel(kind.displayName)
            }
            Button {
                proxy.applyEmphasis(nil, settings: settings)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("강조 해제")
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }

    @ViewBuilder
    private func emphasisLabel(_ kind: SermonEmphasis) -> some View {
        switch kind {
        case .one:
            Text("강조1")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color(hex: "#753B44") ?? .red)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .two:
            Text("강조2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(hex: "#FFE08A") ?? .yellow, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .three:
            Text("강조3")
                .font(.caption.weight(.semibold))
                .underline()
                .foregroundStyle(Color(hex: "#1F5F8B") ?? .blue)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func styleDisplayName(_ style: SermonParagraphStyle) -> String {
        switch style {
        case .mainTheme: return String(localized: "대주제")
        case .midTheme: return String(localized: "중주제")
        case .subTheme: return String(localized: "소주제")
        case .verseQuote: return String(localized: "말씀구절")
        case .citation: return String(localized: "인용")
        case .body: return String(localized: "본문")
        }
    }

    // MARK: - 편집 영역 · 연구 자료 · 하단 분량 바

    private var linkTargetSermon: Sermon? {
        switch subject {
        case .sermon(let sermon): return sermon
        case .delivery(let delivery): return delivery.sermon
        }
    }

    private var researchPane: some View {
        SermonResearchPane(
            sermon: linkTargetSermon,
            suggestions: SermonChapterRef.suggestions(for: linkTargetSermon, mainPassage: linkTargetSermon?.effectiveMainPassage?.text),
            accent: accent
        )
    }

    private var editorArea: some View {
        HStack(spacing: 0) {
            if isOutlineVisible && !isPhoneIdiom {
                SermonOutlinePanel(entries: outline, stats: stats, accent: accent) { proxy.scrollToParagraph($0) }
                    .frame(width: 220)
                Divider()
            }
            SermonParagraphEditor(
                contentHtml: $contentHtml,
                contentText: $contentText,
                paragraphStyles: $paragraphStyles,
                styleFontSnapshot: subject.styleFontSnapshot,
                isEditable: true,
                proxy: proxy
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
            if isResearchVisible {
                Divider()
                researchPane.frame(width: 320)
            }
            #endif
        }
        .frame(maxHeight: .infinity)
    }

    private var statusBar: some View {
        let minutes = stats.estimatedMinutes(charsPerMinute: charsPerMinute)
        return HStack(spacing: 14) {
            Text(String(localized: "\(stats.characters)자"))
            if !isPhoneIdiom { Text(String(localized: "공백 제외 \(stats.charactersNoSpace)자")) }
            Text(String(localized: "\(stats.paragraphs)문단"))
            Label(String(localized: "예상 \(SermonTextStats.minutesLabel(minutes))"), systemImage: "clock")
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 8)
            if let statusMessage {
                Text(statusMessage)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(SermonViewerPaper.color)
    }

    private func showStatusMessage(_ message: String) {
        statusMessage = message
        statusMessageTask?.cancel()
        statusMessageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            statusMessage = nil
        }
    }

    // MARK: - 찾기 · 개요 · 연구 자료 토글

    private var isResearchActive: Bool {
        #if os(macOS)
        return isResearchVisible
        #else
        return isSplitPaneShown && paneTabRaw == "research"
        #endif
    }

    private func toggleFind() {
        if find.isVisible {
            find.close(proxy: proxy)
        } else {
            let text = proxy.documentText as NSString
            let range = proxy.selectionRange
            let selected = (range.length > 0 && NSMaxRange(range) <= text.length) ? text.substring(with: range) : nil
            find.open(with: selected, proxy: proxy)
        }
    }

    private func toggleOutline() {
        if isPhoneIdiom {
            outline = SermonTextStats.outline(text: contentText, styles: paragraphStyles)
            isOutlineSheetPresented = true
        } else {
            isOutlineVisible.toggle()
        }
    }

    private func toggleResearch() {
        #if os(macOS)
        isResearchVisible.toggle()
        #else
        if isSplitAvailable {
            if isSplitPaneShown && paneTabRaw == "research" {
                isSplitPaneEnabled = false
            } else {
                paneTabRaw = "research"
                isSplitPaneEnabled = true
            }
        } else {
            isResearchSheetPresented = true
        }
        #endif
    }

    private func refreshOutline() {
        outline = isOutlineVisible ? SermonTextStats.outline(text: contentText, styles: paragraphStyles) : []
    }

    // MARK: - 서식 복사 / 붙여넣기

    private func copyFormat() {
        guard let captured = proxy.copyFormat(settings: settings) else {
            showStatusMessage(String(localized: "복사할 서식이 없습니다."))
            return
        }
        copiedFormat = captured
        showStatusMessage(String(localized: "서식 복사됨: \(captured.summary)"))
    }

    private func pasteFormat() {
        guard let copiedFormat else { return }
        proxy.pasteFormat(copiedFormat, settings: settings)
        showStatusMessage(String(localized: "서식 붙여넣음"))
    }

    // MARK: - 구절 치환 (⌃R 말씀구절 스타일 · ⌃T 현재 스타일 유지, 설정에서 변경)

    /// 선택하거나 커서를 둔 성경 참조("요 3:16", "롬 8:28-30")를 설교 인용 번역본의 구절 본문으로 바꾼다.
    /// - 말씀구절 스타일: 참조가 있던 줄을 `말씀구절` 문단으로 만들고 `SermonVerseReference`도 함께 저장한다.
    /// - 현재 스타일 유지: 그 자리에서 “본문” 따옴표 + (출처)로 바꾼다.
    /// 출처 "(책 장:절)"은 설정의 표기 방식을 따른다(기본 표기).
    private func performVerseSubstitution(_ mode: SermonVerseSubstituteMode) {
        guard let target = SermonQuoteService.target(in: proxy.documentText, selection: proxy.selectionRange) else {
            showStatusMessage(String(localized: "치환할 성경 구절 표기가 없습니다. 예: 요 3:16"))
            return
        }
        guard let quote = SermonQuoteService.verseText(for: target, context: modelContext) else {
            showStatusMessage(String(localized: "구절 본문을 찾지 못했습니다. 설정의 설교 인용 번역본을 확인하세요."))
            return
        }
        let citation = SermonQuoteService.citation(bookId: target.bookId, chapter: target.chapter, verseStart: target.verseStart, verseEnd: target.verseEnd)
        let paragraphIndex = proxy.substituteReference(range: target.range, quote: quote, citation: citation, mode: mode, settings: settings)
        if mode == .verseStyle, let paragraphIndex {
            proxy.activeStyle = .verseQuote
            let reference = subject.makeVerseReference(
                bookId: target.bookId, chapter: target.chapter, verseStart: target.verseStart, verseEnd: target.verseEnd,
                paragraphIndex: paragraphIndex
            )
            modelContext.insert(reference)
        }
        showStatusMessage(mode == .verseStyle ? String(localized: "말씀구절로 치환했습니다.") : String(localized: "현재 스타일로 치환했습니다."))
        scheduleAutosave(force: true)
    }

    // MARK: - 자동 저장

    private var hasUnsavedChanges: Bool {
        if contentHtml != subject.contentHtml || contentText != subject.contentText || paragraphStyles != subject.paragraphStyles { return true }
        if isNewSermon, case .sermon(let sermon) = subject {
            return sermon.title != title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return false
    }

    /// 입력이 멈추고 2초 뒤 저장한다(디바운스). 닫기·앱 비활성·마인드맵 적용 직전에는 기다리지 않고 바로 저장한다.
    /// 자동 저장은 통합 검색 성경구절 인덱스를 다시 만들지 않는다(타이핑 중 부하) — 인덱스는 닫을 때·앱이 비활성이 될 때 갱신된다.
    private func scheduleAutosave(force: Bool = false) {
        guard hasLoaded, !skipSaveOnDisappear else { return }
        guard force || hasUnsavedChanges else { return }
        if isNewSermon && !hasEnteredContent { return }
        saveState = .pending
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !skipSaveOnDisappear else { return }
            saveState = .saving
            save(reindex: false)
        }
    }

    // MARK: - 로드/저장

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        contentHtml = subject.contentHtml
        contentText = subject.contentText
        paragraphStyles = subject.paragraphStyles
        if isNewSermon, case .sermon(let sermon) = subject {
            title = sermon.title
        }
        stats = SermonTextStats.compute(text: contentText)
        refreshOutline()
        hasLoaded = true
    }

    /// 마인드맵 알림이 "이 편집기의 설교"를 가리키는지 판별하는 ID — 회차 사본
    /// (`.delivery`)은 마인드맵 대상이 아니라 `nil`.
    private var externalChangeSermonID: PersistentIdentifier? {
        if case .sermon(let sermon) = subject { return sermon.persistentModelID }
        return nil
    }

    /// (1) 마인드맵이 적용하기 직전 — 지금까지 입력한 본문을 즉시 저장한다.
    /// (`body`의 타입 추론 부담을 줄이려고 클로저 대신 메서드로 뺐다.)
    private func flushForExternalChange(_ id: PersistentIdentifier) {
        guard externalChangeSermonID == id else { return }
        autosaveTask?.cancel()
        save()
    }

    /// (3) 마인드맵이 적용·저장한 뒤 — 저장하지 않고 닫는다.
    private func closeForExternalChange(_ id: PersistentIdentifier) {
        guard externalChangeSermonID == id else { return }
        autosaveTask?.cancel()
        skipSaveOnDisappear = true
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    private func save(reindex: Bool = true) {
        autosaveTask?.cancel()
        if isNewSermon, case .sermon(let sermon) = subject {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            sermon.title = trimmedTitle
            if !hasInsertedNewSermon {
                let trimmedContent = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty else { return }
                modelContext.insert(sermon)
                // 성경 조회에서 절을 골라 시작한 새 설교는 구절 참조가 설교에만 달려 있고 아직 insert되지 않았다(`SermonNewWindowContent`).
                // 이미 insert된 참조(아이폰 시트 경로)에 다시 insert해도 같은 컨텍스트 안에서는 무해하다.
                for reference in sermon.verseReferences ?? [] {
                    modelContext.insert(reference)
                }
                hasInsertedNewSermon = true
            }
        }
        subject.contentHtml = contentHtml
        subject.contentText = contentText
        subject.paragraphStyles = paragraphStyles
        // 이번 저장 시점의 프리셋 값을 스냅샷으로 저장 — 다음에 열 때 `applyStyle`이 실제 값과
        // 비교해 사용자의 수동 서식 지정을 가려낸다.
        subject.styleFontSnapshot = SermonParagraphStyleCodec.captureSnapshot(settings: settings)
        subject.touchUpdatedAt()
        try? modelContext.save()
        // 저장 직후 통합 검색용 성경구절 인덱스를 갱신한다(`reindexMemo` 등과 같은 자리).
        // 회차 사본(`.delivery`)은 인덱싱하지 않는다.
        if reindex, case .sermon(let sermon) = subject {
            BibleReferenceIndexingService.reindexSermon(sermon, context: modelContext)
        }
        saveState = .saved(.now)
    }

    // MARK: - 태그 로드/입력 (`SermonDetailView.tagSection`과 같은 패턴을
    // `SermonEditingSubject.tags`/`addTagJoin`/`removeTagJoin`을 통해 재사용)

    private func loadTagsIfNeeded() {
        guard !hasLoadedTags else { return }
        tags = subject.tags
        hasLoadedTags = true
    }

    private func updateTagSuggestions(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            tagSuggestions = []
            return
        }
        do {
            let all = try modelContext.fetch(FetchDescriptor<Tag>(
                predicate: #Predicate<Tag> { $0.mergedIntoId == nil }
            ))
            tagSuggestions = Array(
                all
                    .filter { $0.normalizedForm.contains(trimmed) }
                    .filter { candidate in !tags.contains { $0.id == candidate.id } }
                    .sorted { $0.name < $1.name }
                    .prefix(8)
            )
        } catch {
            tagSuggestions = []
        }
    }

    private func commitTagInput() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let tag = try TagDeduplication.findOrCreateTag(named: trimmed, context: modelContext)
            addTag(tag)
        } catch {
            print("[SermonEditorView] 태그 생성 실패: \(error)")
        }
        tagInput = ""
        tagSuggestions = []
    }

    private func addTag(_ tag: Tag) {
        guard !tags.contains(where: { $0.id == tag.id }) else { return }
        subject.addTagJoin(tag, context: modelContext)
        tags.append(tag)
        tagInput = ""
        tagSuggestions = []
        try? modelContext.save()
    }

    private func removeTag(_ tag: Tag) {
        subject.removeTagJoin(for: tag, context: modelContext)
        tags.removeAll { $0.id == tag.id }
        try? modelContext.save()
    }

    // MARK: - 말씀구절 삽입 (설계 문서 2.2 S-SER2 "말씀구절 스타일의 특수성")

    /// `SermonVerseReferencePicker`가 확정한 구절을 에디터 본문에 새 `.verseQuote` 문단으로 삽입하고,
    /// 그 문단 순번과 함께 `SermonVerseReference`를 저장한다(좌표가 구조적으로 정확).
    private func insertVerseQuote(text: String, bookId: Int, chapter: Int, verseStart: Int, verseEnd: Int?) {
        let paragraphIndex = proxy.insertVerseQuoteParagraph(text: text, settings: .shared)
        proxy.activeStyle = .verseQuote
        let reference = subject.makeVerseReference(
            bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd,
            paragraphIndex: paragraphIndex
        )
        modelContext.insert(reference)
        // 텍스트 스토리지를 직접 바꾸면 `didProcessEditing`이 바인딩을 비동기(`DispatchQueue.main.async`)로
        // 뒤늦게 갱신한다 — 바로 저장하면 방금 삽입한 구절이 빠질 수 있어 한 틱 미뤄 저장한다.
        DispatchQueue.main.async {
            save()
        }
    }
}
