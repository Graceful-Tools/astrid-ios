//  MacRowHitArea.swift
//  Astrid for Mac — the task row's click target (Task b556c6a9).
//
//  The row's selection tap used to sit on the title block alone, so the card's padding answered no
//  click: 9pt above and below, 12pt at each edge, and the whole checkbox column including the strip
//  around the glyph. The row looked like one target and behaved like a smaller one.
//
//  The fix is structural: the paddings live INSIDE the two columns, so each column's contentShape
//  covers its share of the card and the two together cover all of it. These are the numbers both
//  columns are built from — kept here so the geometry is stated once and can be asserted.

#if os(macOS)
import SwiftUI

enum MacRowHitArea {
    /// Padding above and below the row's content, inside the tappable area.
    static let verticalPadding: CGFloat = 9
    /// Leading gutter (inside the checkbox column) and trailing gutter (inside the content column).
    static let horizontalPadding: CGFloat = 12
    /// Gap between the checkbox column and the content column.
    static let columnSpacing: CGFloat = 12
    /// Breathing room around the checkbox glyph. Clicks here select the row; the glyph itself
    /// keeps its own gesture and still completes the task (see 652edb22).
    static let checkboxMargin: CGFloat = 6

    static func checkboxColumnWidth(glyph: CGFloat) -> CGFloat {
        horizontalPadding + glyph + checkboxMargin
    }

    static func contentColumnWidth(rowWidth: CGFloat, glyph: CGFloat) -> CGFloat {
        rowWidth - checkboxColumnWidth(glyph: glyph) - columnSpacing
    }

    /// Floor for a row, so a task with only a title stands as tall as one carrying a date or a
    /// list chip and a mixed list reads as an even column (Task 7c5cd097).
    ///
    /// Derived from Mac's own type rather than copied from iOS, which pins 76 for 19pt titles —
    /// at Mac's 14pt that row would be oversized. Same arithmetic iOS used, Mac's numbers:
    /// title line (~17) + spacing (2) + metadata line (~14) + padding (18) = 51, rounded to 52.
    static let minRowHeight: CGFloat = 52

    /// A floor, not a fixed height: a wrapped two-line title still grows past it, because
    /// clamping tall rows would truncate the very titles that need the room.
    static func rowHeight(contentHeight: CGFloat) -> CGFloat {
        max(minRowHeight, contentHeight + verticalPadding * 2)
    }

    /// Per-level subtask indent, capped so deep nesting cannot squeeze the row away.
    static func indent(level: Int) -> CGFloat { CGFloat(min(level, 4)) * 16 }
}
#endif
