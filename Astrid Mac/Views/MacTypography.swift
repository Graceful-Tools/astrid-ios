//  MacTypography.swift
//  Astrid for Mac — desktop type ramp (Task 913216a9). iOS rows use 19pt/15pt via Theme.Typography;
//  macOS text styles render smaller (body 13 / subheadline 11), so a literal port would shrink the
//  hierarchy. These sizes keep the iOS title>meta hierarchy at native Mac proportions and replace
//  the ad-hoc 15/12/…: one ramp for rows + detail.

#if os(macOS)
import SwiftUI

enum MacTypography {
    // Sized against the MAC system ramp, not iOS's numbers. iOS body is 17pt and its row title
    // 19pt (≈1.12x body); macOS body is 13pt, so the equivalent row title is ~14pt. The previous
    // 16/13 ramp was a literal-ish port of the iOS sizes and read oversized in a Mac window —
    // the same hierarchy, just at desktop density.
    static let rowTitleSize: CGFloat = 14       // ≈ macOS body (13) + emphasis, like iOS 19 vs 17
    static let rowMetaSize: CGFloat = 11        // macOS caption density
    /// The detail's title is the SAME STRING as the row you clicked to get there, so it is
    /// not a heading over that row — it is that row's text again (task 4ce4baf9). At 17pt
    /// semibold the jump read as the text changing rather than as hierarchy, and there was
    /// nothing under it in the panel for a heading to be a heading OF. Defined as the row
    /// title rather than repeated as 14, so the two cannot drift if the ramp moves.
    static let detailTitleSize: CGFloat = rowTitleSize
    static let labelSize: CGFloat = 11          // field labels (Who/Date/…)

    /// Body text INSIDE the detail: the description, and the subtask titles that
    /// sit under it. One token for both, because "the subtasks should read like
    /// the description" is a decision, and two independent defaults are how it
    /// stops being true.
    static let detailBodySize: CGFloat = 13     // macOS body

    static var rowTitle: Font { .system(size: rowTitleSize, weight: .medium) }
    static var rowMeta: Font { .system(size: rowMetaSize) }
    static var detailTitle: Font { rowTitle }
    static var label: Font { .system(size: labelSize) }
    static var detailBody: Font { .system(size: detailBodySize, weight: .regular) }
}
#endif
