//  MacSelectionStyle.swift
//  Astrid for Mac — pure selection-border styling (Task b8d1ec16). The selected state should be
//  a subtle, thin accent — not a heavy border (iOS used 2.5pt; that's too strong on desktop cards).

#if os(macOS)
import SwiftUI
import AppKit

enum MacSelectionStyle {
    static let selectedWidth: CGFloat = 1.5
    static let unselectedWidth: CGFloat = 0.5

    static func borderWidth(isSelected: Bool) -> CGFloat {
        isSelected ? selectedWidth : unselectedWidth
    }

    static func borderColor(isSelected: Bool, hovering: Bool = false) -> Color {
        if isSelected { return Theme.accent.opacity(0.55) }      // subtle accent
        if hovering { return Theme.borderHover }                 // hover: slightly stronger hairline
        return Theme.border                                      // faint hairline
    }

    /// Card fill: the SELECTED card keeps the plain card surface (white on Ocean/Light) — only the
    /// accent BORDER carries selection (0f695ef2; the old accent wash read as a dark-blue row).
    ///
    /// Hover uses `Theme.bgHover`, which is the same token the WEB uses (`--theme-bg-hover`:
    /// white on Light/Ocean, rgb(55,65,81) on Dark). The old 4% accent wash tinted rows blue,
    /// which is not what the web does.
    static func fill(isSelected: Bool, hovering: Bool = false) -> Color {
        if isSelected { return Theme.bgSecondary }
        if hovering { return Theme.bgHover }
        return Theme.bgSecondary
    }
}

/// Pointer + hover helpers for interactive elements (Task 77225941).
struct MacPointingHandOnHover: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// Subtle hover highlight for plain interactive rows (chat messages, suggestion rows).
struct MacHoverHighlight: ViewModifier {
    @State private var hovering = false
    var cornerRadius: CGFloat = 6
    func body(content: Content) -> some View {
        content
            .background(hovering ? Theme.accent.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hovering = h } }
    }
}

extension View {
    /// Pointing-hand cursor on hover — for custom tappable glyphs (checkbox, chips, icon buttons).
    func macPointingHand() -> some View { modifier(MacPointingHandOnHover()) }
    /// Subtle hover wash — for interactive rows without their own selection chrome.
    func macHoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(MacHoverHighlight(cornerRadius: cornerRadius))
    }
}
#endif
