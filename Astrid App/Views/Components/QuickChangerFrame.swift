//  QuickChangerFrame.swift
//  The quick changer's frame (ADEV-170), on iOS and the Mac: the popover behind a task's leading
//  control when a tap does not complete. iOS is the reference — 280 wide, 16 padding, 16 between
//  sections — and the Mac takes it. What goes inside stays each platform's own pickers
//  (`TaskQuickChanger`, `MacQuickChanger`); the frame and the section label are stated once.

import SwiftUI

enum QuickChangerLayout {
    /// Jon, 2026-11-20: iOS's 280 is the quick changer's width on both platforms.
    static let width: CGFloat = 280
    static let padding = Theme.spacing16
    /// Between the changer's sections.
    static let spacing = Theme.spacing16
    /// Between a section's label and its control.
    static let labelSpacing = Theme.spacing8
}

/// The popover's body: its sections stacked at `QuickChangerLayout`'s width and padding.
struct QuickChangerFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: QuickChangerLayout.spacing) {
            content()
        }
        .padding(QuickChangerLayout.padding)
        .frame(width: QuickChangerLayout.width)
    }
}

/// One labelled section of the quick changer: a muted label over its control.
struct QuickChangerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @ThemedPalette private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: QuickChangerLayout.labelSpacing) {
            Text(verbatim: title)
                #if os(macOS)
                .macFont(MacTypography.label)
                #else
                .font(Theme.Typography.caption1())
                #endif
                .foregroundColor(palette.textMuted)
            content()
        }
    }
}
