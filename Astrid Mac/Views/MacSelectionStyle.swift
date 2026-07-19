//  MacSelectionStyle.swift
//  Astrid for Mac — pure selection-border styling (Task b8d1ec16). The selected state should be
//  a subtle, thin accent — not a heavy border (iOS used 2.5pt; that's too strong on desktop cards).

#if os(macOS)
import SwiftUI

enum MacSelectionStyle {
    static let selectedWidth: CGFloat = 1.5
    static let unselectedWidth: CGFloat = 0.5

    static func borderWidth(isSelected: Bool) -> CGFloat {
        isSelected ? selectedWidth : unselectedWidth
    }

    static func borderColor(isSelected: Bool) -> Color {
        isSelected ? Theme.accent.opacity(0.55) : Theme.border   // subtle accent vs faint hairline
    }

    /// Faint accent wash behind a selected card (kept low so it reads as "selected", not "filled").
    static func fill(isSelected: Bool) -> Color {
        isSelected ? Theme.accent.opacity(0.08) : Theme.bgSecondary
    }
}
#endif
