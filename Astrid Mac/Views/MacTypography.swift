//  MacTypography.swift
//  Astrid for Mac — desktop type ramp (Task 913216a9). iOS rows use 19pt/15pt via Theme.Typography;
//  macOS text styles render smaller (body 13 / subheadline 11), so a literal port would shrink the
//  hierarchy. These sizes keep the iOS title>meta hierarchy at native Mac proportions and replace
//  the ad-hoc 15/12/…: one ramp for rows + detail.

#if os(macOS)
import SwiftUI

enum MacTypography {
    static let rowTitleSize: CGFloat = 16       // iOS 19pt equivalent at desktop density
    static let rowMetaSize: CGFloat = 13        // iOS 15pt metadata equivalent
    static let detailTitleSize: CGFloat = 20    // detail header
    static let labelSize: CGFloat = 12          // field labels (Who/Date/…)

    static var rowTitle: Font { .system(size: rowTitleSize, weight: .medium) }
    static var rowMeta: Font { .system(size: rowMetaSize) }
    static var detailTitle: Font { .system(size: detailTitleSize, weight: .semibold) }
    static var label: Font { .system(size: labelSize) }
}
#endif
