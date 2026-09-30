//
//  SermonViewerView.swift
//  JBCHBibleResearch
//
//  [2026-09-28 4단계(뷰어) 신설] S-SER3 "설교 뷰어 — 전체화면 클린 리더" —
//  설계 문서 claude/sermon-management-screens-and-schema.md 2.2 S-SER3,
//  5장 확정사항 3번 참고. `SermonComingSoonView(mode: .viewer, ...)`를
//  대체한다. `SermonEditorView`(3단계)와 마찬가지로 메인 `Sermon`과 특정
//  회차 `SermonDelivery` 양쪽을 같은 화면(이 파일 하나)으로, `SermonEditingSubject`
//  로 감싸 읽기 전용으로 렌더링한다.
//
//  ⚠️ [편집 요소 없음, 확정] 설계 문서 2.2 S-SER3 — "편집 요소(툴바 스타일
//  드롭다운 등)는 전혀 없는 순수 읽기 화면 — 태그/이력 정보도 숨기고 본문만
//  크게 보여줍니다." 그래서 이 화면은 `@Environment(\.modelContext)`조차
//  갖지 않는다 — 아무것도 쓰지 않기 때문이다.
//
//  ⚠️ [문단 파싱 원리] `SermonParagraphStyleCodec.parseParagraphs(text:styles:)`
//  (`SermonParagraphEditor.swift`에 4단계에서 추가)가 저장된 `contentText`
//  (순수 문자열)를 편집기와 똑같은 `NSString.enumerateSubstrings(.byParagraphs)`
//  로 순회해 `paragraphStyles` 배열과 짝짓는다 — 에디터가 저장한 순서와
//  정확히 같은 순서를 보장한다(그 함수 상단 주석 참고).
//
//  ⚠️ [글꼴 확대, 확정] 설계 문서 5장 3번 — 스타일별 "상대 크기 비율은 유지한
//  채 전체 배율만 바뀐다." `UserSettingsStore.sermonViewerFontScale`(0.8~2.0)
//  하나가 6종 스타일의 저장된 절대 크기(3.3절)에 곱해진다
//  (`sermonFont(for:scale:)`/`sermonPlatformFont(for:scale:)`, 4단계에서
//  `UserSettingsStore`에 추가한 스케일 파라미터).
//
//  ⚠️ [동적 페이지네이션, 확정] 설계 문서 5장 3번 — "현재 글꼴 배율에서 한
//  화면에 들어가는 만큼 문단을 채우다가 넘치면 다음 페이지로 넘기는 동적
//  페이지네이션." 구현: 문단마다 실제 표시 폭(`availableWidth`)에 맞춰
//  오프스크린(`opacity(0)`)으로 한 번 렌더링해 `GeometryReader`+`PreferenceKey`
//  (이 프로젝트의 기존 관례 — `AnnotatedVerseFlowView.swift`의
//  `VerseAnchorCollectionKey` 참고)로 높이를 모으고, `computePages(...)`가
//  누적 높이가 `availableHeight`를 넘기기 직전 문단에서 페이지를 끊는다.
//  글꼴 배율이 바뀌면 `paragraphText(_:)`가 그 배율을 다시 읽어 오프스크린
//  레이어의 문단 높이가 자연히 달라지고, 그 변화가 `PreferenceKey`를 통해
//  다시 `computePages`를 트리거한다 — 별도의 "배율이 바뀌었다"는 수동 신호가
//  필요 없다.
//
//  ⚠️ [스크롤/페이지 토글 기본값] 설계 문서가 기본값을 못박지 않아, 화면을
//  처음 열었을 때 문단이 잘려 보일 걱정이 없는 세로 스크롤을 기본값으로
//  뒀다(`UserSettingsStore.sermonViewerUsesPageMode` 기본 false) — 사용자
//  피드백에 따라 바꿀 수 있음.
//
//  ⚠️ [성능/측정 비용] 오프스크린 측정 레이어는 페이지 모드일 때만 렌더링한다
//  (스크롤 모드에선 페이지 계산 자체가 필요 없으므로 — 근거 없이 상시
//  이중 렌더링하지 않기 위함). 페이지 모드로 전환하는 순간 측정 상태를
//  초기화해 새로 측정한다.
//
//  [2026-09-28 디자인 정합화] 사용자 지적 — "디자인이 목업 html과 너무 차이가
//  큼." 목업(`Viewer.dc.html`/`MacViewer.dc.html`)에 맞춰 상단 바만 바꿨다
//  (본문 렌더링·페이지네이션 로직은 그대로):
//  - 글꼴 배율: 예전엔 `Menu`로 8단계 중 하나를 펼쳐서 골랐다 — 목업은
//    "A-  100%  A+" 알약형 스테퍼다. 큐레이션된 8단계(`scaleSteps`) 자체는
//    그대로 두고, 상호작용만 "펼쳐서 고르기"에서 "한 단계씩 넘기기"로
//    바꿨다(`stepFontScale(by:)`) — 값 목록은 손대지 않아 사용자가 고를 수
//    있는 배율 범위·단계는 이전과 동일하다.
//  - 스크롤/페이지 토글: 예전엔 아이콘 하나가 상태에 따라 바뀌는 단일
//    버튼이었다 — 목업처럼 "스크롤"/"페이지" 두 글자가 각각 보이는 알약
//    토글(`SermonSegmentedPill`, SermonSupport.swift에 신설 — SermonHomeView의
//    보기 방식 토글과 같은 컴포넌트 재사용)로 바꿨다. 불리언 하나를 켜고
//    끄는 동작 자체는 그대로다.
//  - 닫기 버튼을 원형 배경으로 감쌌다(목업의 둥근 X 버튼).
//
//  ⚠️ [Xcode 확인 필요] 이 세션은 Xcode 빌드/실기기 테스트를 할 수 없어
//  코드 리뷰만으로 작성됐다 — 실제 빌드 후 반드시 확인해 주세요:
//    1. 오프스크린 측정이 실제 화면 표시와 정확히 같은 폭/줄바꿈으로
//       렌더링되는지(폰트가 기기에 없어 시스템 폰트로 대체되는 경우, 측정
//       시점과 표시 시점의 대체 폰트가 다르면 높이가 어긋날 수 있음).
//    2. 매우 긴 문단(한 페이지보다 큰 단일 문단)이 있을 때 `computePages`가
//       그 문단 하나만 담은 페이지를 만들고 넘어가는지(코드상 의도된 동작 —
//       `currentPage.isEmpty`일 땐 넘침 여부와 무관하게 무조건 담아
//       무한루프/빈 페이지를 막는다), 그리고 그 경우 페이지 하단이 잘려
//       보이는지 확인.
//    3. `@Environment(\.dismiss)`가 이 화면이 Mac/iPad의
//       `WindowGroup(id: "sermon-viewer", ...)` 안에서 열렸을 때도 창을
//       정상적으로 닫는지 — iPhone(`NavigationLink` 푸시)에서는 표준
//       뒤로가기와 동일하게 동작할 것으로 예상되나, 윈도우 컨텍스트에서의
//       동작은 확인이 필요하다.
//    4. `SF Symbol` 이름("book", "text.alignleft", "textformat.size")이
//       프로젝트의 최소 배포 타깃에서 전부 존재하는지.
//

import SwiftUI
import BibleResearchModels

// MARK: - 문단 높이 수집 (오프스크린 측정)

/// 문단 인덱스 → 그 문단이 `availableWidth`에서 실제로 차지하는 높이.
/// `AnnotatedVerseFlowView.swift`의 `VerseAnchorCollectionKey`와 같은
/// "여러 형제 뷰가 각자 자기 몫을 보고하고 reduce가 합친다" 관례.
private struct SermonParagraphHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - [인용] 문단 위아래 점선 (10번 항목)

/// `paragraphText(_:)`의 `.citation` 분기 전용 — 가로 폭 전체에 걸친 점선을
/// 그린다. `GeometryReader`로 그 자리에서 실제로 배정된 폭을 읽어 `Path`
/// 한 줄을 `StrokeStyle(dash:)`로 긋는, SwiftUI 표준 드로잉 조합(별도
/// 프레임워크·저수준 TextKit 불필요 — 편집기 쪽에 넣지 못한 것과의 차이는
/// 이 파일 상단 주석 참고). `GeometryReader`가 자신에게 주어진 공간을 모두
/// 채우려 하는 성질이 있어, 높이는 항상 `frame(height: 1)`로 얇게 고정해
/// 둔다.
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
    /// [2026-09-29 신설, 버그 수정] 이 파일 상단 "[Xcode 확인 필요] 3번" 주석이
    /// 미리 적어 뒀던 우려 — "`@Environment(\.dismiss)`가 Mac/iPad의
    /// `WindowGroup(id: "sermon-viewer", ...)` 안에서 열렸을 때도 창을 정상
    /// 닫는지" — 가 사용자의 실기기 보고로 확인됐다: `.dismiss`는 `.sheet`/
    /// `NavigationStack` 같은 프레젠테이션이 없으면 기댈 곳이 없어, 진짜
    /// `WindowGroup` 창 안에서는 아무 효과가 없다. `SermonEditorView.
    /// onRequestClose`와 완전히 같은 해법 — 창을 연 쪽(`SermonContentWindowContent`,
    /// `SermonSupport.swift`)이 `dismissWindow()`를 호출하는 클로저를 넘겨주면
    /// 그걸 쓰고, 안 넘겨주면(아이폰 `NavigationLink` 푸시 등 기존 경로) 기존
    /// `dismiss()`로 그대로 동작한다(아래 `header`의 닫기 버튼 참고).
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
    /// "Aa" 스테퍼가 오가는 단계 — 설계 문서 2.2 S-SER3의 예시 범위(80~200%) 그대로.
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
            // 페이지 모드로 막 전환됐다 — 스크롤 모드 동안엔 측정 레이어
            // 자체를 렌더링하지 않았으므로(성능 이유, 파일 상단 주석 참고)
            // 이전에 남은 계산 결과가 있으면 폐기하고 새로 측정한다.
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
                // [2026-09-29 수정] 위 `onRequestClose` 상단 주석 참고 — 창
                // 컨텍스트에서 열렸으면 그 클로저가, 아니면 기존 `dismiss()`가
                // 처리한다.
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

    /// 목업의 "A-  100%  A+" 알약 스테퍼. 큐레이션된 `scaleSteps` 배열은
    /// 그대로 두고 한 단계씩 넘긴다(상단 주석 "디자인 정합화" 참고).
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

    /// 목업의 "스크롤 | 페이지" 알약 토글 — `SermonHomeView`의 보기 방식
    /// 토글과 같은 `SermonSegmentedPill`(SermonSupport.swift)을 재사용한다.
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

    /// 페이지 모드일 때만 렌더링된다(파일 상단 주석 "성능/측정 비용" 참고).
    /// 실제 표시와 똑같은 폭(`width`)으로 각 문단을 한 번 그려 그 높이를
    /// `SermonParagraphHeightKey`로 보고한다 — `opacity(0)`이라 화면엔 보이지
    /// 않는다.
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

    /// 문단을 순서대로 누적하다가, 다음 문단을 더하면 `availableHeight`를
    /// 넘기는 지점에서 페이지를 끊는다(설계 문서 확정 방식). 페이지가 아직
    /// 비어 있을 땐(그 문단 하나만으로도 이미 `availableHeight`를 넘는
    /// 경우 포함) 무조건 담아 — 그러지 않으면 그 문단이 영원히 다음 페이지로
    /// 미뤄지는 무한루프/빈 페이지가 생긴다.
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
            // [2026-09-29 6-2번 항목] 목업(Editor.dc.html)의 "박스 안 왼쪽 바 +
            // 내용" — 편집기(`SermonParagraphStyleCodec.applyStyle` 상단 주석)는
            // TextKit 저수준 그리기가 필요해 배경 박스까지만 구현했지만, 이
            // 뷰어는 읽기 전용 순정 SwiftUI 렌더링이라 `HStack` + `Rectangle`로
            // 왼쪽 바까지 그대로 그릴 수 있다. 왼쪽만 각진 모서리(목업의
            // `border-radius: 0 8px 8px 0`)는 `UnevenRoundedRectangle`(iOS 16+/
            // macOS 13+ — 이 프로젝트가 이미 쓰는 `Color.resolve(in:)`가 iOS
            // 17+/macOS 14+를 요구하므로 배포 대상 안에 포함된다)로 그대로 맞춘다.
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
            // [2026-09-29 10번 항목] 사용자 요청 — "[인용] 스타일: 초록색
            // 계열의 이탤릭체 + 문단 위아래 점선(구분선) + 왼쪽여백 10pt +
            // 오른쪽여백 10pt." 색/좌우 여백은 편집기(`SermonParagraphStyleCodec.
            // applyStyle`)와 같은 값을 쓴다(폰트 색은 `settings.sermonFontColor`가
            // 이미 스타일별로 읽어 오고, 여백은 편집기의 `headIndent`/
            // `tailIndent` 10과 맞춰 `.padding(.horizontal, 10)`으로 맞췄다).
            // 위아래 점선은 `NSParagraphStyle` 표준 attribute로 표현할 방법이
            // 없어(편집기 쪽 주석 참고) 에디터엔 넣지 못했지만, 이 뷰어는 순정
            // SwiftUI라 `Path` + `StrokeStyle(dash:)`(표준 API, iOS 13+/macOS 10.15+ —
            // 이 프로젝트 배포 타깃보다 한참 낮아 버전 문제 없음)로 직접 그릴 수
            // 있다.
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
