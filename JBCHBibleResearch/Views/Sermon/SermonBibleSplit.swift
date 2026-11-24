//
//  SermonBibleSplit.swift
//  JBCHBibleResearch
//
//  설교 작성 창의 "에디터 | 성경 조회" 분할 화면(2026-11-11, 목업 `Sermon-Split-Landscape/Portrait`).
//
//  - 아이패드 가로(폭 ≥ 높이): 왼쪽 에디터 | 가운데 끌 수 있는 분할선 | 오른쪽 성경 패널(기본 에디터 : 성경 = 2 : 1).
//  - 아이패드 세로: 위 에디터 / 가운데 분할선 / 아래 성경 패널.
//  - 성경 패널은 `BibleReadingView(isPrimaryWindow: false)` — 번역본 선택이 따로이고 메인 창의 사이드바·인스펙터를 건드리지 않는다.
//    그 패널에서 절을 고르면 하단 액션바에 [에디터에 인용 삽입]이 나타난다(`sermonQuoteInsert` 환경값 — 아래 선언).
//
//  ⚠️ 에디터와 패널을 `AnyLayout`으로 배치한다 — 가로 ↔ 세로가 바뀌어도 에디터 뷰가 새로 만들어지지 않아 커서·스크롤이 유지된다.
//  ⚠️ 설교 에디터는 아이패드·맥에서 항상 별도 창(`sermon-editor`/`sermon-new`)의 루트다(`SermonHomeView` 주석). 그래서 이 분할은
//  사이드바·설교 목록 칸과 겹치지 않으며, 목업 메모의 "분할을 켜면 사이드바 자동 접기"는 필요 없다.
//

import SwiftUI

/// 성경 패널이 고른 구절을 에디터 본문에 "말씀구절" 문단으로 삽입하는 동작. 에디터(`SermonEditorView`)가 성경 패널에만 넣어 주고,
/// 그 외 모든 화면(메인 성경 조회 등)은 nil이라 [에디터에 인용 삽입] 버튼이 나타나지 않는다.
struct SermonQuoteInsertAction {
    /// `SermonVerseReferencePicker.onInsert`와 같은 인자 — 조합된 본문(끝에 "(책 장:절)" 표기 포함), 책 ID, 장, 시작 절, 끝 절(한 절이면 nil).
    let insert: (_ text: String, _ bookId: Int, _ chapter: Int, _ verseStart: Int, _ verseEnd: Int?) -> Void
}

private struct SermonQuoteInsertKey: EnvironmentKey {
    static let defaultValue: SermonQuoteInsertAction? = nil
}

extension EnvironmentValues {
    var sermonQuoteInsert: SermonQuoteInsertAction? {
        get { self[SermonQuoteInsertKey.self] }
        set { self[SermonQuoteInsertKey.self] = newValue }
    }
}

#if os(iOS)
struct SermonBibleSplitContainer<Editor: View, Pane: View>: View {
    /// true = 좌우 분할(가로), false = 위아래 분할(세로). 호출부가 컨테이너 크기로 정해 넘긴다.
    let isHorizontal: Bool
    let isPaneShown: Bool
    /// 성경 패널이 차지하는 비율(0.25~0.6). 끌어서 바뀐 값은 호출부가 기억한다.
    @Binding var paneFraction: Double
    /// 분할선 위 칩 글자("2 : 1").
    let ratioText: String
    private let editor: Editor
    private let pane: Pane

    @State private var dragStartFraction: Double?

    static var fractionRange: ClosedRange<Double> { 0.25...0.6 }
    private static var handleThickness: CGFloat { 18 }

    init(
        isHorizontal: Bool,
        isPaneShown: Bool,
        paneFraction: Binding<Double>,
        ratioText: String,
        @ViewBuilder editor: () -> Editor,
        @ViewBuilder pane: () -> Pane
    ) {
        self.isHorizontal = isHorizontal
        self.isPaneShown = isPaneShown
        self._paneFraction = paneFraction
        self.ratioText = ratioText
        self.editor = editor()
        self.pane = pane()
    }

    private var clampedFraction: Double {
        min(max(paneFraction, Self.fractionRange.lowerBound), Self.fractionRange.upperBound)
    }

    var body: some View {
        GeometryReader { proxy in
            let total = isHorizontal ? proxy.size.width : proxy.size.height
            let usable = max(total - Self.handleThickness, 1)
            let paneLength = (usable * clampedFraction).rounded()
            let layout = isHorizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                editor
                if isPaneShown {
                    handle(usable: usable)
                    pane
                        .frame(
                            width: isHorizontal ? paneLength : nil,
                            height: isHorizontal ? nil : paneLength
                        )
                        .clipped()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: - 분할선

    private func handle(usable: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.14))
            Capsule()
                .fill(Color.secondary.opacity(0.55))
                .frame(width: isHorizontal ? 4 : 36, height: isHorizontal ? 36 : 4)
                .offset(y: isHorizontal ? 22 : 0)
            Text(ratioText)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5))
                .fixedSize()
                .offset(y: isHorizontal ? -14 : 0)
        }
        .frame(
            width: isHorizontal ? Self.handleThickness : nil,
            height: isHorizontal ? nil : Self.handleThickness
        )
        .zIndex(1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartFraction ?? clampedFraction
                    dragStartFraction = start
                    // 패널이 오른쪽/아래에 있으므로 오른쪽/아래로 끌수록 패널이 작아진다.
                    let delta = Double(isHorizontal ? value.translation.width : value.translation.height)
                    let next = start - delta / Double(usable)
                    paneFraction = min(max(next, Self.fractionRange.lowerBound), Self.fractionRange.upperBound)
                }
                .onEnded { _ in dragStartFraction = nil }
        )
        .accessibilityElement()
        .accessibilityLabel(String(localized: "에디터와 성경 패널 크기 조절"))
        .accessibilityValue(ratioText)
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            switch direction {
            case .increment: paneFraction = min(clampedFraction + step, Self.fractionRange.upperBound)
            case .decrement: paneFraction = max(clampedFraction - step, Self.fractionRange.lowerBound)
            @unknown default: break
            }
        }
    }
}
#endif
