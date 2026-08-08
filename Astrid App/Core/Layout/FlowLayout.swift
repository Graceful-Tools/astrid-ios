//  FlowLayout.swift
//  A row of views that wraps only when it has to.
//
//  Used by the task detail's "When" row on both platforms: date, time and
//  repeat sit on one line when there is room and wrap when there is not. The
//  packing arithmetic lives in `FlowRows` so it can be tested; this is the
//  SwiftUI shell around it.

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// Gap between wrapped rows.
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        // No width proposed (e.g. inside a scroll view sizing itself): one row.
        let maxWidth = proposal.width ?? .infinity
        let rows = FlowRows.rows(itemWidths: sizes.map(\.width),
                                 maxWidth: maxWidth,
                                 spacing: spacing)
        let rowHeight: CGFloat = sizes.map(\.height).max() ?? 0

        var widest: CGFloat = 0
        for row in rows {
            var rowWidth: CGFloat = 0
            for index in row { rowWidth += sizes[index].width }
            rowWidth += CGFloat(max(0, row.count - 1)) * spacing
            widest = max(widest, rowWidth)
        }

        let height = FlowRows.height(rowCount: rows.count,
                                     rowHeight: rowHeight,
                                     spacing: rowSpacing)
        let width: CGFloat = maxWidth == .infinity ? widest : min(widest, maxWidth)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout Void) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = FlowRows.rows(itemWidths: sizes.map(\.width),
                                 maxWidth: bounds.width,
                                 spacing: spacing)
        let rowHeight = sizes.map(\.height).max() ?? 0

        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - sizes[index].height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }
}
