//
//  FlowLayoutHStack.swift
//  JBCHBibleResearch
//
//  태그 칩을 흘려쓰기(flow layout)로 배치하는 최소 구현. SwiftUI 표준 `Layout`
//  프로토콜(iOS16+/macOS13+)로 만들었다 — HStack만 쓰면 태그가 많을 때 화면 밖으로
//  잘리기 때문.
//
//  [2026-08-14 분리] 원래 `MemoDetailView.swift`에 `private struct`로 있던 것을,
//  `WordSummaryEditorView`도 태그 UI를 갖게 되면서(사용자 요청 — "말씀 요약의
//  글을 클릭했을 때에도 개인 묵상 유형의 글처럼 태그를 입력할 수 있게") 두
//  화면이 공유할 수 있도록 별도 파일로 뺐다. 구현 자체는 전혀 바뀌지 않았다.
//

import SwiftUI

struct FlowLayoutHStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
