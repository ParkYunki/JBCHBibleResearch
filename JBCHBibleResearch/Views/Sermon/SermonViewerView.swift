//
//  SermonViewerView.swift
//  JBCHBibleResearch
//
//  설교 뷰어(S-SER3) — 편집 요소가 전혀 없는 전체화면 읽기 전용 리더.
//  메인 `Sermon`과 특정 회차 `SermonDelivery`를 `SermonEditingSubject`로 감싸 같은 화면에서 보여준다.
//  아무것도 쓰지 않으므로 `modelContext`를 갖지 않는다.
//
//  - 본문은 편집기와 같은 데이터 경로(저장된 RTF → 문단 스타일 재적용)로 만든 `NSAttributedString`을
//    TextKit으로 그린다(`SermonViewerText.swift`). 굵게/기울임/색/문단 여백이 편집 화면과 같다.
//  - 스크롤 모드: 읽기 전용 텍스트뷰 하나(iOS `UITextView`, macOS `NSTextView`). 필요한 만큼만 레이아웃한다.
//  - 페이지 모드: 글자가 여러 페이지 컨테이너로 흘러가는 TextKit 페이지 나누기. iOS는 도서 앱과 같은
//    `UIPageViewController` 페이지 컬, macOS는 한 페이지씩 그리고 키보드/가장자리 클릭/트랙패드 쓸기/하단 슬라이더로 넘긴다.
//  - 상단 바(글꼴 배율·스크롤/페이지·닫기)와 하단 바(이전·쪽 슬라이더·쪽 번호·다음)는 본문 위에 겹쳐 뜬다.
//    본문 영역 크기가 바뀌지 않으므로 바를 숨기거나 보여도 글자가 다시 흐르지 않는다.
//    본문 가운데를 누르면(또는 macOS H 키) 두 바를 함께 숨기고/보이며, 상태는 설정에 저장된다.
//  - 글자 영역 좌우 여백은 넓은 화면에서 64pt(좁은 화면은 28pt). 텍스트 드래그 선택이 클릭 동작보다 우선한다.
//  - 글꼴 배율: `sermonViewerFontScale`(0.8~2.0)이 글자 크기와 줄/문단 간격에 함께 곱해진다.
//  - 화면 크기나 배율이 바뀌면 페이지를 다시 나누되, 읽던 글자 위치가 든 페이지로 돌아온다.
//  - 뷰어는 저장된 값을 보여준다. 편집기에서 아직 저장(자동 저장 포함)되지 않은 입력은 반영되지 않는다.
//

import SwiftUI
import BibleResearchModels

struct SermonViewerView: View {
    let subject: SermonEditingSubject
    /// 창(`WindowGroup`) 컨텍스트에서는 `dismiss`가 효과가 없어, 창을 연 쪽이
    /// `dismissWindow()` 클로저를 넘긴다. nil이면 `dismiss()`를 쓴다(iPhone push 등).
    var onRequestClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settings = UserSettingsStore.shared

    /// 편집기와 같은 서식의 본문. nil이면 아직 만드는 중(스피너).
    @State private var attributed: NSAttributedString?
    @State private var isEmptyDocument = false
    /// 본문을 새로 만들 때마다 올라간다 — 텍스트뷰가 같은 본문을 다시 넣지 않게 하는 표식.
    @State private var generation = 0
    @State private var paginator: SermonViewerPaginator?
    @State private var pageIndex = 0
    /// 읽던 자리(글자 위치) — 페이지를 다시 나눌 때 같은 자리의 페이지로 돌아오는 데 쓴다.
    @State private var readingLocation = 0
    /// 하단 슬라이더를 끄는 동안의 쪽(놓을 때 `pageIndex`에 반영) / 끄는 중인지.
    @State private var scrubIndex: Int?
    @State private var isScrubbing = false
    /// macOS에서 바가 숨은 상태로 마우스가 맨 위/아래에 있을 때 그 바만 잠깐 보여 주는 표시.
    @State private var peekTop = false
    @State private var peekBottom = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    /// "Aa" 스테퍼가 오가는 단계(80~200%).
    private static let scaleSteps: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
    /// 글자 영역 좌우 여백 — 넓은 화면은 64pt, 좁은 화면(iPhone 세로 등)은 28pt.
    private static let wideHorizontalInset: CGFloat = 64
    private static let compactHorizontalInset: CGFloat = 28
    private static let compactWidthThreshold: CGFloat = 600
    /// 글자 영역 위/아래 여백 — 상단·하단 바가 본문 위에 겹쳐 뜨므로 "바 높이 + 숨 쉴 여백"만큼 항상 비워 둔다.
    /// 상단 바 ≈ 51pt(세로 패딩 10×2 + 버튼 30 + 구분선), 하단 바 ≈ 55pt(패딩 10×2 + 버튼 34 + 구분선).
    private static let topInset: CGFloat = 96
    private static let bottomInset: CGFloat = 88
    /// macOS에서 바가 숨은 동안 마우스가 닿으면 바를 보여 주는 위/아래 영역 높이.
    private static let hoverRegionHeight: CGFloat = 64

    // 뷰어는 라이트 외형으로 고정이라(`SermonViewerPaper`) 강조색도 라이트 값을 쓴다. 바깥 환경의 colorScheme을 읽으면 다크 모드에서 밝은 강조색이 된다.
    private var accent: Color { SermonTheme.accent(.light) }
    private var isPageMode: Bool { settings.sermonViewerUsesPageMode }

    private static func horizontalInset(forWidth width: CGFloat) -> CGFloat {
        width < compactWidthThreshold ? compactHorizontalInset : wideHorizontalInset
    }

    /// 본문이 준비되기 전이나 비어 있을 때는 바를 항상 보인다(숨긴 채로 갇히지 않도록).
    private var canHideChrome: Bool { attributed != nil && !isEmptyDocument }
    private var isChromeHidden: Bool { settings.sermonViewerChromeHidden && canHideChrome }
    private var isTopBarVisible: Bool { !isChromeHidden || peekTop }
    private var isBottomBarVisible: Bool { !isChromeHidden || peekBottom }
    /// 하단 바/쪽 번호는 페이지 모드에서만 있다.
    private var showsPageControls: Bool { isPageMode && canHideChrome }
    private var barAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }

    /// 페이지 나누기를 다시 해야 하는 조건 — 크기/본문/모드 중 하나라도 바뀌면 값이 달라진다.
    private struct PaginationKey: Hashable {
        let width: Int
        let height: Int
        let generation: Int
        let isPageMode: Bool
    }

    var body: some View {
        ZStack {
            // 본문 영역은 바와 무관하게 항상 전체 크기 — 바를 숨기거나 보여도 쪽 나누기를 다시 하지 않는다.
            GeometryReader { proxy in
                content(horizontalInset: Self.horizontalInset(forWidth: proxy.size.width))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(
                        of: PaginationKey(
                            width: Int(proxy.size.width), height: Int(proxy.size.height),
                            generation: generation, isPageMode: isPageMode
                        ),
                        initial: true
                    ) {
                        repaginate(size: proxy.size)
                    }
            }

            chromeOverlay
        }
        // 첫 프레임(스피너)을 먼저 그린 뒤 본문을 만든다. 배율이 바뀔 때도 다시 만든다.
        .task(id: settings.sermonViewerFontScale) { await rebuildDocument() }
        .onChange(of: pageIndex) { _, newValue in
            if let paginator { readingLocation = paginator.characterLocation(ofPage: newValue) }
        }
        // 배경은 설정 테마·다크 모드와 무관하게 부드러운 미색으로 고정한다(`SermonViewerPaper`). 배경이 항상 밝으므로
        // SwiftUI 요소(글자·버튼·스피너)도 라이트 외형으로 고정한다. `preferredColorScheme`은 이 화면을 연 창 전체에
        // 번질 수 있어 쓰지 않는다.
        .background(SermonViewerPaper.color.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .navigationTitle("설교 뷰어")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SermonViewerPaper.color, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .background { keyboardShortcuts }
        #endif
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 600)
        .background(SermonViewerKeyCatcher { handleKeyCommand($0) })
        #endif
    }

    // MARK: - 본문 영역

    @ViewBuilder
    private func content(horizontalInset: CGFloat) -> some View {
        if isEmptyDocument {
            emptyState
        } else if let attributed {
            if isPageMode {
                pagedBody(horizontalInset: horizontalInset)
            } else {
                SermonViewerScrollText(
                    attributed: attributed, generation: generation,
                    horizontalInset: horizontalInset, topInset: Self.topInset,
                    onToggleChrome: { toggleChrome() }
                )
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func pagedBody(horizontalInset: CGFloat) -> some View {
        if let paginator {
            #if os(iOS)
            SermonViewerPageCurl(
                paginator: paginator,
                insets: UIEdgeInsets(
                    top: Self.topInset, left: horizontalInset,
                    bottom: Self.bottomInset, right: horizontalInset
                ),
                currentIndex: $pageIndex,
                onCenterTap: { toggleChrome() }
            )
            #elseif os(macOS)
            SermonViewerSinglePage(
                paginator: paginator, index: pageIndex,
                insets: NSSize(width: horizontalInset, height: Self.topInset),
                onCommand: { perform($0) }
            )
            .background(SermonViewerPaper.color)
            #endif
        } else {
            ProgressView()
        }
    }

    // MARK: - 본문 만들기 / 페이지 나누기

    private func rebuildDocument() async {
        // 스피너가 먼저 그려지도록 한 번 양보한다.
        await Task.yield()
        guard !Task.isCancelled else { return }
        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        #endif
        let built = SermonViewerDocument.build(subject: subject, settings: settings, scale: settings.sermonViewerFontScale)
        #if DEBUG
        print("[SermonViewer] 본문 생성 \(built.length)자, \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
        #endif
        isEmptyDocument = built.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        attributed = built
        generation += 1
    }

    private func repaginate(size: CGSize) {
        guard isPageMode else {
            // 스크롤 모드에서는 페이지 레이아웃을 들고 있을 이유가 없다.
            if paginator != nil { paginator = nil }
            return
        }
        guard let attributed, !isEmptyDocument, size.width > 1, size.height > 1 else { return }
        let horizontalInset = Self.horizontalInset(forWidth: size.width)
        let containerSize = CGSize(
            width: max(1, size.width - horizontalInset * 2),
            height: max(1, size.height - Self.topInset - Self.bottomInset)
        )
        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        #endif
        let newPaginator = SermonViewerPaginator(attributed: attributed, containerSize: containerSize)
        #if DEBUG
        print("[SermonViewer] 페이지 나누기 \(newPaginator.pageCount)쪽, \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
        #endif
        paginator = newPaginator
        pageIndex = newPaginator.pageIndex(containingCharacter: readingLocation)
    }

    // MARK: - 바 오버레이 (상단 / 하단 / 숨김 시 쪽 표시 / 안내 토스트)

    private var chromeOverlay: some View {
        ZStack {
            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
            }
            if showsPageControls {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    bottomChrome
                }
                pageMiniIndicator
            }
            if let toast {
                Text(toast)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .padding(.top, 76)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var topChrome: some View {
        ZStack(alignment: .top) {
            #if os(macOS)
            // 바가 숨은 동안에도 이 영역에 마우스가 닿으면 바를 잠깐 보여 준다.
            Color.clear
                .frame(height: Self.hoverRegionHeight)
                .contentShape(Rectangle())
            #endif
            topBar
                .opacity(isTopBarVisible ? 1 : 0)
                .offset(y: isTopBarVisible ? 0 : -24)
                .allowsHitTesting(isTopBarVisible)
        }
        .animation(barAnimation, value: isTopBarVisible)
        #if os(macOS)
        .onHover { peekTop = $0 }
        #endif
    }

    private var bottomChrome: some View {
        ZStack(alignment: .bottom) {
            #if os(macOS)
            Color.clear
                .frame(height: Self.hoverRegionHeight)
                .contentShape(Rectangle())
            #endif
            pageFooter
                .opacity(isBottomBarVisible ? 1 : 0)
                .offset(y: isBottomBarVisible ? 0 : 24)
                .allowsHitTesting(isBottomBarVisible)
        }
        .animation(barAnimation, value: isBottomBarVisible)
        #if os(macOS)
        .onHover { peekBottom = $0 }
        #endif
    }

    /// 바가 숨었을 때 맨 아래에 남는 "n / N"과 가는 진행 막대.
    private var pageMiniIndicator: some View {
        let count = max(paginator?.pageCount ?? 1, 1)
        let current = min(pageIndex, count - 1)
        let isShown = isChromeHidden && !peekBottom
        return ZStack(alignment: .bottom) {
            Text(paginator == nil ? "–" : "\(current + 1) / \(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.trailing, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
            GeometryReader { proxy in
                Rectangle()
                    .fill(accent)
                    .frame(width: proxy.size.width * CGFloat(current + 1) / CGFloat(count), height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(isShown ? 1 : 0)
        .animation(barAnimation, value: isShown)
        .allowsHitTesting(false)
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(barAnimation) { toast = text }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(barAnimation) { toast = nil }
        }
    }

    // MARK: - 상단 바 (글꼴 배율 스테퍼 / 스크롤·페이지 토글 / 닫기)

    private var topBar: some View {
        HStack(spacing: 14) {
            Spacer()
            fontScaleStepper
            viewModeToggle
            Button {
                // 창 컨텍스트면 onRequestClose, 아니면 dismiss()
                if let onRequestClose {
                    onRequestClose()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SermonViewerPaper.color)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// "A-  100%  A+" 알약 스테퍼 — `scaleSteps`를 한 단계씩 넘긴다.
    private var fontScaleStepper: some View {
        HStack(spacing: 2) {
            Button {
                stepFontScale(by: -1)
            } label: {
                Text("A-")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 26)
            }
            Text("\(Int((settings.sermonViewerFontScale * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 34)
            Button {
                stepFontScale(by: 1)
            } label: {
                Text("A+")
                    .font(.callout.weight(.bold))
                    .frame(width: 26, height: 26)
            }
        }
        .buttonStyle(.plain)
        .padding(3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func stepFontScale(by delta: Int) {
        let steps = Self.scaleSteps
        let currentIndex = steps.firstIndex { abs($0 - settings.sermonViewerFontScale) < 0.001 } ?? (steps.count / 2)
        let newIndex = min(max(currentIndex + delta, 0), steps.count - 1)
        settings.sermonViewerFontScale = steps[newIndex]
    }

    /// "스크롤 | 페이지" 알약 토글 — `SermonHomeView`와 같은 `SermonSegmentedPill` 재사용.
    private var viewModeToggle: some View {
        SermonSegmentedPill(
            items: [
                .init(tag: false, label: "스크롤", systemImage: "text.alignleft"),
                .init(tag: true, label: "페이지", systemImage: "book"),
            ],
            selection: Binding(
                get: { settings.sermonViewerUsesPageMode },
                set: { settings.sermonViewerUsesPageMode = $0 }
            ),
            accent: accent
        )
    }

    // MARK: - 페이지 하단 바 (이전 / 쪽 슬라이더 / n·N / 다음)

    private var pageFooter: some View {
        let pageCount = max(paginator?.pageCount ?? 1, 1)
        let currentIndex = min(pageIndex, pageCount - 1)
        let shownIndex = min(scrubIndex ?? currentIndex, pageCount - 1)
        return HStack(spacing: 14) {
            Button {
                goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(currentIndex <= 0)
            .opacity(currentIndex <= 0 ? 0.4 : 1)

            Slider(
                value: Binding(
                    get: { Double(shownIndex) },
                    set: { newValue in
                        let target = min(max(Int(newValue.rounded()), 0), pageCount - 1)
                        // 끄는 동안은 표시만 바꾸고, 손을 떼면 한 번에 이동한다(페이지 컬이 매 쪽 애니메이션하지 않게).
                        if isScrubbing { scrubIndex = target } else { pageIndex = target }
                    }
                ),
                in: 0...Double(max(pageCount - 1, 1)),
                step: 1,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        if let scrubIndex { pageIndex = scrubIndex }
                        scrubIndex = nil
                    }
                }
            )
            .tint(accent)
            .disabled(pageCount <= 1)

            Text(paginator == nil ? "–" : "\(shownIndex + 1) / \(pageCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 54)

            Button {
                goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= pageCount - 1)
            .opacity(currentIndex >= pageCount - 1 ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(SermonViewerPaper.color)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - 이동 / 바 숨김 명령

    private func perform(_ command: SermonViewerCommand) {
        switch command {
        case .previousPage: goToPreviousPage()
        case .nextPage: goToNextPage()
        case .firstPage: if paginator != nil { pageIndex = 0 }
        case .lastPage: if let paginator { pageIndex = max(paginator.pageCount - 1, 0) }
        case .toggleChrome: toggleChrome()
        }
    }

    #if os(macOS)
    /// 키보드 명령. 처리했으면 true(키를 소비). 스크롤 모드에서는 H만 처리하고 방향키·Space는 텍스트뷰 기본 스크롤에 맡긴다.
    private func handleKeyCommand(_ command: SermonViewerCommand) -> Bool {
        switch command {
        case .toggleChrome:
            guard canHideChrome else { return false }
            toggleChrome()
            return true
        default:
            guard isPageMode, paginator != nil else { return false }
            perform(command)
            return true
        }
    }
    #endif

    private func goToNextPage() {
        guard let paginator else { return }
        if pageIndex < paginator.pageCount - 1 {
            pageIndex += 1
        } else {
            showToast("마지막 쪽입니다")
        }
    }

    private func goToPreviousPage() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else {
            showToast("첫 쪽입니다")
        }
    }

    private func toggleChrome() {
        guard canHideChrome else { return }
        settings.sermonViewerChromeHidden.toggle()
        peekTop = false
        peekBottom = false
        showToast(settings.sermonViewerChromeHidden ? "바를 숨겼습니다 — 가운데를 누르면 다시 보입니다" : "바를 보입니다")
    }

    #if os(iOS)
    /// 외부 키보드(iPad) 단축키 — 보이지 않는 버튼에 단축키만 연결한다. 페이지 이동은 페이지 모드에서만 켠다.
    private var keyboardShortcuts: some View {
        let pageKeysEnabled = isPageMode && paginator != nil
        return ZStack {
            Button("이전 쪽") { perform(.previousPage) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("다음 쪽") { perform(.nextPage) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("이전 쪽") { perform(.previousPage) }
                .keyboardShortcut(.pageUp, modifiers: [])
            Button("다음 쪽") { perform(.nextPage) }
                .keyboardShortcut(.pageDown, modifiers: [])
            Button("다음 쪽") { perform(.nextPage) }
                .keyboardShortcut(.space, modifiers: [])
            Button("이전 쪽") { perform(.previousPage) }
                .keyboardShortcut(.space, modifiers: .shift)
            Button("첫 쪽") { perform(.firstPage) }
                .keyboardShortcut(.home, modifiers: [])
            Button("마지막 쪽") { perform(.lastPage) }
                .keyboardShortcut(.end, modifiers: [])
        }
        .disabled(!pageKeysEnabled)
        .opacity(0)
        .frame(width: 0, height: 0)
        .overlay {
            Button("바 숨김/표시") { toggleChrome() }
                .keyboardShortcut("h", modifiers: [])
                .disabled(!canHideChrome)
                .opacity(0)
        }
        .accessibilityHidden(true)
    }
    #endif

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("본문이 없습니다")
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
