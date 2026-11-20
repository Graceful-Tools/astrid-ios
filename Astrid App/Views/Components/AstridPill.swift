//  AstridPill.swift
//  The one pill (ADEV-166), on iOS and the Mac: tinted text in a capsule with a 15% wash of the
//  tint and a 40% hairline of it. The board-status pill on a list row and the completed-on pill on
//  a Done card both draw through this, so the capsule is stated once. When core's pill tokens land,
//  the numbers below read from `AstridTokens`.

import SwiftUI

struct AstridPill: View {
    /// Jon, 2026-11-20: a pill's wash is iOS's 15%.
    static let fillOpacity: Double = 0.15
    static let strokeOpacity: Double = 0.4
    static let strokeWidth: CGFloat = 1

    /// The font comes from the caller (`.font` on iOS, `.macFont` on Mac), so the pill matches the
    /// metadata beside it.
    let text: String
    let tint: Color

    var body: some View {
        Text(verbatim: text)
            .foregroundColor(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.spacing8)
            .padding(.vertical, Theme.spacing2)
            .background(Capsule().fill(tint.opacity(Self.fillOpacity)))
            .overlay(Capsule().stroke(tint.opacity(Self.strokeOpacity), lineWidth: Self.strokeWidth))
    }
}

/// A board column header's badge (ADEV-166): the column's count, or Done's "15 ✓ This week" menu
/// label, as caption text in a soft capsule. iOS's design; the Mac board draws the same one.
struct BoardHeaderBadge<Content: View>: View {
    @ThemedPalette private var palette
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            #if os(macOS)
            .macFont(.caption)
            #else
            .font(Theme.Typography.caption1())
            #endif
            .foregroundColor(palette.textSecondary)
            .padding(.horizontal, Theme.spacing8)
            .padding(.vertical, Theme.spacing4)
            .background(Capsule().fill(palette.bgTertiary))
            .contentShape(Capsule())
    }
}
