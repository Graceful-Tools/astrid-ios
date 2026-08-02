//  MacDetailRowFit.swift
//  Astrid for Mac — does a row of controls fit the task-detail panel? (Task 42013da7)
//
//  Consolidating the detail's fields put three controls in one row and marked each `.fixedSize()`.
//  fixedSize refuses to compress, so the row demanded more width than the 380pt panel, the Form
//  overflowed, and every line of the detail was clipped off its left edge.
//
//  The panel's width is a known constant and a control's minimum width is a decision we make, so
//  whether a row fits is arithmetic — and arithmetic belongs in a test, not in a screenshot.

#if os(macOS)
import CoreGraphics

enum MacDetailRowFit {
    /// Gap between controls in a detail row.
    static var spacing: CGFloat { 10 }
    /// The row's own leading + trailing inset inside the Form.
    static var rowInsets: CGFloat { 24 }

    /// Minimum widths for the "When" row: the due-date toggle, the date picker, the repeat menu.
    /// These are MINIMUMS the controls may shrink to — not their ideal sizes, which is exactly
    /// the distinction `.fixedSize()` erased.
    /// 84 + 132 + 88 = 304, plus 20 spacing and 24 insets = 348 against a 380pt panel — 32pt of
    /// headroom. My first attempt at these numbers came to 382 and the test caught it: a "fix"
    /// that still overflowed, by two points.
    static var whenRowMinimums: [CGFloat] { [84, 132, 88] }

    /// Priority chip + assignee menu.
    static var priorityRowMinimums: [CGFloat] { [40, 140] }

    static func required(_ widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else { return rowInsets }
        return widths.reduce(0, +) + spacing * CGFloat(widths.count - 1) + rowInsets
    }

    static func fits(_ widths: [CGFloat], in panelWidth: CGFloat) -> Bool {
        required(widths) <= panelWidth
    }
}
#endif
