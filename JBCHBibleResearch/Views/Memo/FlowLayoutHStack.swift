//
//  FlowLayoutHStack.swift
//  JBCHBibleResearch
//
//  태그 칩을 흘려쓰기(flow layout)로 배치하는 최소 구현. SwiftUI 표준 `Layout`
//  프로토콜(iOS16+/macOS13+)로 만들었다 — HStack만 쓰면 태그가 많을 때 화면 밖으로
//  잘리기 때문.
//
//

import SwiftUI

struct FlowLayoutHStack: Layout {
    var spacing: CGFloat = 6
    /// [2026-11-02 interlin1] true면 한 줄보다 넓은 항목에 줄 폭을 제안해 줄 안에 맞춘다(글자는 항목 쪽 `lineLimit`으로 줄임표).
    /// 기본값 false는 예전과 같다(항목을 항상 이상 크기로 놓는다) — 원문 정보 "단어별" 칸만 켠다.
    var clampsItemsToRowWidth = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if clampsItemsToRowWidth, maxWidth.isFinite, size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
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
            var size = subview.sizeThatFits(.unspecified)
            var proposal = ProposedViewSize.unspecified
            if clampsItemsToRowWidth, size.width > bounds.width {
                proposal = ProposedViewSize(width: bounds.width, height: nil)
                size = subview.sizeThatFits(proposal)
            }
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: proposal)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
