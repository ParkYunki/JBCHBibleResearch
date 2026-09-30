//
//  SermonViewerView.swift
//  JBCHBibleResearch
//
//  설교 뷰어(S-SER3) — 편집 요소가 전혀 없는 전체화면 읽기 전용 클린 리더.
//  메인 `Sermon`과 특정 회차 `SermonDelivery`를 `SermonEditingSubject`로 감싸
//  같은 화면에서 렌더링한다. 아무것도 쓰지 않으므로 `modelContext`를 갖지 않는다.
//
//  - 문단 파싱: `SermonParagraphStyleCodec.parseParagraphs(text:styles:)`가 편집기와
//    같은 `.byParagraphs` 순회로 `contentText`를 `paragraphStyles`와 짝짓는다.
//  - 글꼴 배율: `sermonViewerFontScale`(0.8~2.0)이 스타일별 절대 크기에 곱해져
//    스타일 간 상대 비율은 유지된다.
//  - 동적 페이지네이션: 문단을 실제 폭으로 오프스크린(`opacity(0)`) 렌더링해
//    PreferenceKey로 높이를 모으고, `computePages`가 넘치기 직전에 페이지를 끊는다.
//    배율이 바뀌면 높이가 달라져 자동으로 재계산된다. 측정 레이어는 페이지 모드일 때만 그린다.
//  - 기본값은 문단이 잘리지 않는 세로 스크롤(`sermonViewerUsesPageMode` 기본 false).
//  - 알려진 한계: 대체 폰트 사용 시 측정/표시 높이가 어긋날 수 있고, 한 페이지보다 큰
//    단일 문단은 단독 페이지가 되어 하단이 잘릴 수 있다.
//

import SwiftUI
import BibleResearchModels

// MARK: - 문단 높이 수집 (오프스크린 측정)

/// 문단 인덱스 → 그 문단이 `availableWidth`에서 실제로 차지하는 높이.
/// 형제 뷰들이 각자 보고하고 reduce가 합치는 방식(`VerseAnchorCollectionKey`와 동일).
private struct SermonParagraphHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - [인용] 문단 위아래 점선 (10번 항목)

/// `paragraphText(_:)`의 `.citation` 분기 전용 — 가로 폭 전체에 걸친 점선.
/// `GeometryReader`가 공간을 모두 채우려 하므로 높이는 `frame(height: 1)`로 고정한다.
private struct SermonDashedDivider: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .frame(height: 1)
    }
}

struct SermonViewerView: View {
    let subject: SermonEditingSubject
    /// 창(`WindowGroup`) 컨텍스트에서는 `dismiss`가 효과가 없어, 창을 연 쪽이
    /// `dismissWindow()` 클로저를 넘긴다. nil이면 `dismiss()`를 쓴다(iPhone push 등).
    var onRequestClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var settings = UserSettingsStore.shared

    @State private var paragraphs: [(text: String, style: SermonParagraphStyle)] = []
    @State private var measuredHeights: [Int: CGFloat] = [:]
    @State private var pages: [[Int]] = []
    @State private var currentPageIndex = 0

    private static let paragraphSpacing: CGFloat = 20
    private static let contentHorizontalPadding: CGFloat = 24
    private static let contentVerticalPadding: CGFloat = 24
    /// "Aa" 스테퍼가 오가는 단계(80~200%).
    private static let scaleSteps: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

    private var accent: Color { SermonTheme.accent(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            GeometryReader { proxy in
                let availableWidth = max(0, proxy.size.width - Self.contentHorizontalPadding * 2)
                let availableHeight = max(0, proxy.size.height - Self.contentVerticalPadding * 2)

                ZStack {
                    if settings.sermonViewerUsesPageMode {
                        measuringLayer(width: availableWidth)
                    }

                    if paragraphs.isEmpty {
                        emptyState
                    } else if settings.sermonViewerUsesPageMode {
                        pagedContentBody(availableWidth: availableWidth, availableHeight: availableHeight)
                    } else {
                        scrollContent
                    }
                }
                .onPreferenceChange(SermonParagraphHeightKey.self) { heights in
                    measuredHeights = heights
                    recomputePages(availableHeight: availableHeight)
                }
                .onChange(of: availableHeight) { _, newValue in
                    recomputePages(availableHeight: newValue)
                }
            }

            if !paragraphs.isEmpty, settings.sermonViewerUsesPageMode {
                Divider()
                pageFooter(
                    pageCount: max(pages.count, 1),
                    currentIndex: min(currentPageIndex, max(pages.count - 1, 0))
                )
            }
        }
        .onAppear { loadParagraphsIfNeeded() }
        .onChange(of: settings.sermonViewerUsesPageMode) { _, isPageMode in
            guard isPageMode else { return }
            // 스크롤 모드 동안 측정 레이어가 없었으므로 남은 계산 결과를 폐기하고 새로 측정한다.
            measuredHeights = [:]
            pages = []
            currentPageIndex = 0
        }
        .navigationTitle("설교 뷰어")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 600)
        #endif
    }

    // MARK: - 상단 바 (글꼴 배율 스테퍼 / 스크롤·페이지 토글 / 닫기) — 목업 Viewer.dc.html

    private var header: some View {
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
        .background(.bar)
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

    // MARK: - 세로 스크롤 모드

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.paragraphSpacing) {
                ForEach(paragraphs.indices, id: \.self) { index in
                    paragraphText(index)
                }
            }
            .padding(.horizontal, Self.contentHorizontalPadding)
            .padding(.vertical, Self.contentVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 좌우 페이지 넘기기 모드

    @ViewBuilder
    private func pagedContentBody(availableWidth: CGFloat, availableHeight: CGFloat) -> some View {
        if pages.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let safeIndex = min(currentPageIndex, pages.count - 1)
            VStack(alignment: .leading, spacing: Self.paragraphSpacing) {
                ForEach(pages[safeIndex], id: \.self) { paragraphIndex in
                    paragraphText(paragraphIndex)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.contentHorizontalPadding)
            .padding(.vertical, Self.contentVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .id(safeIndex)
            .transition(.opacity)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        if value.translation.width < -60 {
                            goToNextPage()
                        } else if value.translation.width > 60 {
                            goToPreviousPage()
                        }
                    }
            )
            .animation(.default, value: safeIndex)
        }
    }

    private func pageFooter(pageCount: Int, currentIndex: Int) -> some View {
        HStack {
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

            Spacer()

            Text("\(currentIndex + 1) / \(pageCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

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
        .background(.bar)
    }

    private func goToNextPage() {
        guard currentPageIndex < pages.count - 1 else { return }
        currentPageIndex += 1
    }

    private func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
    }

    // MARK: - 오프스크린 높이 측정

    /// 페이지 모드일 때만 렌더링된다. 실제 표시와 같은 폭으로 각 문단을 그려 높이를
    /// `SermonParagraphHeightKey`로 보고한다(`opacity(0)`이라 보이지 않음).
    @ViewBuilder
    private func measuringLayer(width: CGFloat) -> some View {
        if width > 0 {
            VStack(alignment: .leading, spacing: Self.paragraphSpacing) {
                ForEach(paragraphs.indices, id: \.self) { index in
                    paragraphText(index)
                        .frame(width: width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SermonParagraphHeightKey.self,
                                    value: [index: proxy.size.height]
                                )
                            }
                        )
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func recomputePages(availableHeight: CGFloat) {
        guard !paragraphs.isEmpty, availableHeight > 0, measuredHeights.count == paragraphs.count else { return }
        let newPages = Self.computePages(
            count: paragraphs.count, heights: measuredHeights,
            availableHeight: availableHeight, spacing: Self.paragraphSpacing
        )
        guard newPages != pages else { return }
        pages = newPages
        if currentPageIndex >= newPages.count {
            currentPageIndex = max(0, newPages.count - 1)
        }
    }

    /// 문단을 누적하다가 다음 문단을 더하면 `availableHeight`를 넘는 지점에서 페이지를 끊는다.
    /// 페이지가 비어 있을 땐(단일 문단이 이미 넘치는 경우 포함) 무조건 담아, 그 문단이
    /// 계속 미뤄지는 무한루프/빈 페이지를 막는다.
    private static func computePages(
        count: Int, heights: [Int: CGFloat], availableHeight: CGFloat, spacing: CGFloat
    ) -> [[Int]] {
        guard count > 0 else { return [] }
        var pages: [[Int]] = []
        var currentPage: [Int] = []
        var currentHeight: CGFloat = 0
        for index in 0..<count {
            let height = heights[index] ?? 0
            let addition = currentPage.isEmpty ? height : height + spacing
            if !currentPage.isEmpty, currentHeight + addition > availableHeight {
                pages.append(currentPage)
                currentPage = [index]
                currentHeight = height
            } else {
                currentPage.append(index)
                currentHeight += addition
            }
        }
        if !currentPage.isEmpty { pages.append(currentPage) }
        return pages
    }

    // MARK: - 문단 렌더링 / 로드

    @ViewBuilder
    private func paragraphText(_ index: Int) -> some View {
        let paragraph = paragraphs[index]
        if paragraph.style == .verseQuote {
            // 박스 안 왼쪽 바 + 내용. 뷰어는 읽기 전용 SwiftUI 렌더링이라 `HStack` + `Rectangle`로
            // 왼쪽 바까지 그린다(편집기는 배경 박스까지만). 오른쪽만 둥근 모서리는
            // `UnevenRoundedRectangle`(iOS 16+/macOS 13+)로 맞춘다.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(settings.sermonVerseQuoteBarColor)
                    .frame(width: 3)
                Text(paragraph.text)
                    .font(settings.sermonFont(for: paragraph.style, scale: settings.sermonViewerFontScale))
                    .foregroundStyle(settings.sermonFontColor(for: paragraph.style))
                    .lineSpacing(lineSpacing(for: paragraph.style))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(settings.sermonVerseQuoteBackgroundColor)
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 8, topTrailingRadius: 8)
            )
        } else if paragraph.style == .citation {
            // 초록 계열 이탤릭 + 위아래 점선 + 좌우 여백 10pt. 색/여백은 편집기
            // (`applyStyle`의 `headIndent`/`tailIndent` 10)와 같은 값이다. 위아래 점선은
            // `NSParagraphStyle`로 표현할 수 없어 편집기엔 없고, 뷰어에서만 `Path` +
            // `StrokeStyle(dash:)`로 직접 그린다.
            Text(paragraph.text)
                .font(settings.sermonFont(for: paragraph.style, scale: settings.sermonViewerFontScale))
                .italic()
                .foregroundStyle(settings.sermonFontColor(for: paragraph.style))
                .lineSpacing(lineSpacing(for: paragraph.style))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(alignment: .top) {
                    SermonDashedDivider(color: settings.sermonFontColor(for: .citation))
                }
                .overlay(alignment: .bottom) {
                    SermonDashedDivider(color: settings.sermonFontColor(for: .citation))
                }
        } else {
            Text(paragraph.text)
                .font(settings.sermonFont(for: paragraph.style, scale: settings.sermonViewerFontScale))
                .foregroundStyle(settings.sermonFontColor(for: paragraph.style))
                .lineSpacing(lineSpacing(for: paragraph.style))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `SermonParagraphStyleCodec.applyStyle`과 같은 공식
    /// (`typographicLineHeight * max(0, 배수 - 1)`)이나, 뷰어는 현재 글꼴
    /// 배율이 적용된 폰트 기준으로 계산해 배율이 커지면 줄간격도 비례해서
    /// 늘어난다.
    private func lineSpacing(for style: SermonParagraphStyle) -> CGFloat {
        let scaledFont = settings.sermonPlatformFont(for: style, scale: settings.sermonViewerFontScale)
        return scaledFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: style) - 1)
    }

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

    private func loadParagraphsIfNeeded() {
        guard paragraphs.isEmpty else { return }
        paragraphs = SermonParagraphStyleCodec.parseParagraphs(text: subject.contentText, styles: subject.paragraphStyles)
    }
}
