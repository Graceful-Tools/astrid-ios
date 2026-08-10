//  FlowRows.swift
//  Packing items into rows that fit a width — the arithmetic behind a wrapping
//  row of chips, kept apart from the SwiftUI layout that uses it so it can be
//  tested.
//
//  The task detail's "When" controls were first laid out as a fixed assignment:
//  date and time on line one, repeat always on line two. That fixed the reported
//  bug (the time being squeezed off) but at the cost of always spending a second
//  line, even on a panel with room to spare. Wrapping is a function of the width
//  available, not a decision to make in advance.

import CoreGraphics
import Foundation

enum FlowRows {

    /// Group items into rows that fit `maxWidth`, preserving order.
    ///
    /// Returns indices into `itemWidths`. An item wider than `maxWidth` still
    /// gets a row of its own rather than being dropped — a row that overflows is
    /// bad, but a control that vanishes is worse, which is the failure this
    /// whole area keeps producing.
    static func rows(itemWidths: [CGFloat],
                     maxWidth: CGFloat,
                     spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0

        for (index, width) in itemWidths.enumerated() {
            // The gap only exists between items, so the first item on a row is free.
            let needed = current.isEmpty ? width : used + spacing + width
            if current.isEmpty || needed <= maxWidth {
                current.append(index)
                used = needed
            } else {
                rows.append(current)
                current = [index]
                used = width
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    /// Total height of the packed rows, given a uniform row height.
    static func height(rowCount: Int, rowHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * spacing
    }
}
