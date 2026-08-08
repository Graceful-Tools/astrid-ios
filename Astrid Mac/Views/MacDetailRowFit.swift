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

/// Where a detail row's leading icon and its content sit.
///
/// The title row is `[checkbox][gap][title]`; every field row below it is
/// `[icon][gap][content]`. Both are built from THESE constants, so the icons sit
/// in the checkbox's column and the content starts exactly where the title text
/// does. Written down because the previous layout used an 80pt text label —
/// "Priority", "When", "Lists" — which lined up with nothing and cost the row
/// 51pt of the 380pt panel.
enum MacDetailRowMetrics {
    /// The leading column. Exactly the checkbox's width, which is the point.
    static var leadingColumnWidth: CGFloat { MacTaskVisuals.detailCheckboxSize }
    /// Gap between the leading column and the content.
    static var columnGap: CGFloat { 10 }
    /// Where content begins, measured from the row's leading edge.
    static var contentInset: CGFloat { leadingColumnWidth + columnGap }
}

enum MacDetailRowFit {
    /// Gap between controls in a detail row.
    static var spacing: CGFloat { 10 }
    /// Everything a row spends before its controls get any width: the Form's own
    /// leading + trailing inset, plus the leading icon column.
    ///
    /// This used to be 24 — the Form insets alone — which quietly ignored the
    /// 80pt label column the controls actually had to share the row with. The
    /// arithmetic was optimistic by the width of the label.
    static var rowInsets: CGFloat { 24 + MacDetailRowMetrics.contentInset }

    /// Minimum widths for the "When" row: the date trigger, the time trigger, the repeat menu.
    /// These are MINIMUMS the controls may shrink to — not their ideal sizes, which is exactly
    /// the distinction `.fixedSize()` erased.
    /// 110 + 80 + 88 = 278, plus 20 spacing and 24 insets = 322 against a 380pt panel — 58pt of
    /// headroom. My first attempt at these numbers came to 382 and the test caught it: a "fix"
    /// that still overflowed, by two points.
    /// The date trigger is the widest because it renders a full date ("Dec 25, 2026"); the toggle
    /// it replaced only ever had to fit the words "Due Date".
    static var whenRowMinimums: [CGFloat] { [110, 80, 88] }

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
