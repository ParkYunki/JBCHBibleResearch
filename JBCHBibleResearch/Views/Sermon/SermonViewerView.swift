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
//    `UIPageViewController` 페이지 컬, macOS는 한 페이지씩 그리고 버튼/스와이프로 넘긴다.
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

    /// "Aa" 스테퍼가 오가는 단계(80~200%).
    private static let scaleSteps: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
    /// 페이지 모드에서 종이 가장자리와 글자 사이 여백.
    private static let pageHorizontalInset: CGFloat = 28
    private static let pageVerticalInset: CGFloat = 24

    // 뷰어는 라이트 외형으로 고정이라(`SermonViewerPaper`) 강조색도 라이트 값을 쓴다. 바깥 환경의 colorScheme을 읽으면 다크 모드에서 밝은 강조색이 된다.
    private var accent: Color { SermonTheme.accent(.light) }
    private var isPageMode: Bool { settings.sermonViewerUsesPageMode }

    /// 페이지 나누기를 다시 해야 하는 조건 — 크기/본문/모드 중 하나라도 바뀌면 값이 달라진다.
    private struct PaginationKey: Hashable {
        let width: Int
        let height: Int
        let generation: Int
        let isPageMode: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            GeometryReader { proxy in
                content
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

            if isPageMode, attributed != nil, !isEmptyDocument {
                Divider()
                pageFooter
            }
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
        #endif
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 600)
        #endif
    }

    // MARK: - 본문 영역

    @ViewBuilder
    private var content: some View {
        if isEmptyDocument {
            emptyState
        } else if let attributed {
            if isPageMode {
                pagedBody
            } else {
                SermonViewerScrollText(attributed: attributed, generation: generation)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var pagedBody: some View {
        if let paginator {
            #if os(iOS)
            SermonViewerPageCurl(
                paginator: paginator,
                insets: UIEdgeInsets(
                    top: Self.pageVerticalInset, left: Self.pageHorizontalInset,
                    bottom: Self.pageVerticalInset, right: Self.pageHorizontalInset
                ),
                currentIndex: $pageIndex
            )
            #elseif os(macOS)
            SermonViewerSinglePage(
                paginator: paginator, index: pageIndex,
                insets: NSSize(width: Self.pageHorizontalInset, height: Self.pageVerticalInset)
            )
            .background(SermonViewerPaper.color)
            .contentShape(Rectangle())
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
        let containerSize = CGSize(
            width: max(1, size.width - Self.pageHorizontalInset * 2),
            height: max(1, size.height - Self.pageVerticalInset * 2)
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

    // MARK: - 상단 바 (글꼴 배율 스테퍼 / 스크롤·페이지 토글 / 닫기)

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
        .background(SermonViewerPaper.color)
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

    // MARK: - 페이지 하단 바

    private var pageFooter: some View {
        let pageCount = paginator?.pageCount ?? 1
        let currentIndex = min(pageIndex, max(pageCount - 1, 0))
        return HStack {
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

            Text(paginator == nil ? "–" : "\(currentIndex + 1) / \(pageCount)")
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
        .background(SermonViewerPaper.color)
    }

    private func goToNextPage() {
        guard let paginator, pageIndex < paginator.pageCount - 1 else { return }
        pageIndex += 1
    }

    private func goToPreviousPage() {
        guard pageIndex > 0 else { return }
        pageIndex -= 1
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
}
