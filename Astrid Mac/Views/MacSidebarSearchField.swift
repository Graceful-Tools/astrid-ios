//  MacSidebarSearchField.swift
//  Astrid for Mac — the sidebar's list filter. (Task 00145582)
//
//  Deliberately NOT `.searchable(placement: .sidebar)`. That renders system chrome which sits
//  BENEATH the list's scrolling content, so rows slid up over the search field and stayed
//  visible — and because the field is the system's, there is no way to give it an opaque
//  backing. Both attempts to fix it in place (an opaque band in the safe area, and restoring
//  the sidebar material) left the result pixel-identical.
//
//  A `.safeAreaInset` draws ABOVE the scroll content. This sidebar already proves it: the
//  account bar has sat in a bottom inset all along and has never had this problem. So the
//  field is ours, in a top inset, with an opaque background of its own.

#if os(macOS)
import SwiftUI

struct MacSidebarSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
            TextField(NSLocalizedString("actions.search", comment: ""), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
            // Only once there is something to clear — an always-present x is a control that
            // does nothing most of the time.
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
                .macPointingHand()
                .accessibilityLabel(NSLocalizedString("actions.clear", comment: ""))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focused ? Theme.accent : Color.clear, lineWidth: 1.5)
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        // OPAQUE, and the whole point: this is what the scrolling rows disappear behind.
        .background(Theme.bgPrimary)
        .accessibilityIdentifier("sidebar.search")
    }
}
#endif
