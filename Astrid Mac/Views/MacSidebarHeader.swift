//  MacSidebarHeader.swift
//  Astrid for Mac — the top of the sidebar: the opaque strip under the window buttons, then the
//  brand header (logo and wordmark left, search far right — AITD-494).

#if os(macOS)
import SwiftUI

struct MacSidebarHeader<Background: View>: View {
    let background: Background
    let isSearchActive: Bool
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The strip that keeps list rows from scrolling up behind the sidebar toggle and the
            // red/yellow/green window buttons (task 46f66cb8). The brand header goes BELOW it:
            // "top left" on a Mac is where those buttons already are.
            Color.clear.frame(height: MacLayout.sidebarTitlebarInset)
            SidebarBrandHeader(primary: Theme.textPrimary, muted: Theme.textMuted,
                               isSearchActive: isSearchActive, onSearch: onSearch)
                .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .background(background.ignoresSafeArea(edges: .top))
        .accessibilityIdentifier("sidebar.headerBackground")
    }
}
#endif
