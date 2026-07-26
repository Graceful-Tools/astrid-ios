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
    static let detailTitleSize: CGFloat = 17    // detail header — clearly above the row title
    static let labelSize: CGFloat = 11          // field labels (Who/Date/…)

    static var rowTitle: Font { .system(size: rowTitleSize, weight: .medium) }
    static var rowMeta: Font { .system(size: rowMetaSize) }
    static var detailTitle: Font { .system(size: detailTitleSize, weight: .semibold) }
    static var label: Font { .system(size: labelSize) }
}
#endif
