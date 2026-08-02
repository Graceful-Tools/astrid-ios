import CoreGraphics

/// The one set of numbers every quick-pick row in a picker sheet uses (Task 42013da7).
///
/// The date and time pickers had drifted apart — 16pt horizontal padding against 12, an 8pt gap
/// between rows against 4, a 16pt gap above the list against 12 — and the time picker had drifted
/// from ITSELF: its "All day" row used 12pt vertical padding while the options beneath it used 8,
/// so the first row stood visibly taller than the rest of the list.
///
/// Numbers repeated across two files drift. These live here and are pinned by tests.
enum PickerRowMetrics {
    /// Vertical padding on a quick-pick row. Equal top and bottom is what makes rows equal height.
    static var rowVerticalPadding: CGFloat { 12 }

    /// The "No date" / "All day" row uses the SAME padding as the options below it. It is a
    /// choice in the same list, not a header or a footer, and it must not stand taller.
    static var clearRowVerticalPadding: CGFloat { rowVerticalPadding }

    static var rowHorizontalPadding: CGFloat { 16 }

    /// Between rows within one list.
    static var rowSpacing: CGFloat { 8 }

    /// Between the list and whatever sits above or below it. Wider than `rowSpacing`, so the
    /// rows read as one set of choices rather than as separate groups.
    static var sectionSpacing: CGFloat { 16 }

    /// What a row adds to its content's height — both sides.
    static var totalVerticalPadding: CGFloat { rowVerticalPadding * 2 }
}
