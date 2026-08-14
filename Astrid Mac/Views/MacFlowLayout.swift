//  MacFlowLayout.swift
//  A row of chips that wraps BETWEEN chips (Task 459caa56).
//
//  The list pills sat in a plain `HStack`, which never wraps — with several lists it squeezed them
//  instead, and because the pill's own text had no line limit the squeeze pushed the name onto a
//  second line. A two-line pill inside a one-line row is the "multiline within the list" symptom.
//
//  SwiftUI has no built-in flow layout, so the break maths lives in `MacFlowRows` where it can be
//  asserted, and `MacFlowLayout` is the thin `Layout` that applies it.

#if os(macOS)
import SwiftUI

/// Where the line breaks fall. Pure, so wrapping can be tested without laying out a view.
enum MacFlowRows {

    /// Group item indices into rows that fit `maxWidth`, preserving order.
    ///
    /// Spacing is charged BETWEEN items only — charging it before the first would break a row that
    /// exactly fits, which is the off-by-one that makes wrapping look arbitrary.
    static func rows(itemWidths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        guard !itemWidths.isEmpty else { return [] }

        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0

        for (index, width) in itemWidths.enumerated() {
            let needed = current.isEmpty ? width : used + spacing + width
            // An item wider than the row still gets placed — on a row of its own if one is already
            // started. Never drop it, and never leave an empty row behind.
            if !current.isEmpty, needed > maxWidth {
                rows.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

/// Lays subviews out left to right, wrapping to a new line when the next one will not fit.
struct MacFlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? .infinity
        let rows = MacFlowRows.rows(itemWidths: sizes.map(\.width), maxWidth: maxWidth,
                                    spacing: spacing)
        guard !rows.isEmpty else { return .zero }

        // Split out rather than written as one expression: the combined form takes the type
        // checker an unreasonable amount of time.
        var widest: CGFloat = 0
        var height: CGFloat = 0
        for row in rows {
            var rowWidth: CGFloat = 0
            var rowHeight: CGFloat = 0
            for index in row {
                rowWidth += sizes[index].width
                rowHeight = max(rowHeight, sizes[index].height)
            }
            rowWidth += spacing * CGFloat(max(0, row.count - 1))
            widest = max(widest, rowWidth)
            height += rowHeight
        }
        height += lineSpacing * CGFloat(max(0, rows.count - 1))

        let width = maxWidth.isFinite ? min(widest, maxWidth) : widest
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = MacFlowRows.rows(itemWidths: sizes.map(\.width), maxWidth: bounds.width,
                                    spacing: spacing)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            for index in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - sizes[index].height) / 2),
                    proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}
#endif
