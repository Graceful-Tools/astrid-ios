//  MacSidebarHeader.swift
//  Astrid for Mac — the top of the sidebar: the opaque strip under the window buttons, then the
//  brand header (logo and wordmark left, search far right — AITD-494).

#if os(macOS)
import SwiftUI

struct MacSidebarHeader<Background: View>: View {
    let background: Background
    /// The window's header band, carried across the sidebar's part of the title bar (ADEV-66).
    let band: Color
    let isSearchActive: Bool
    let onSearch: () -> Void
    /// The title bar's height over the sidebar — its top safe-area inset.
    @State private var titlebarHeight: CGFloat = 0

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
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { titlebarHeight = $0 }
        .background {
            VStack(spacing: 0) {
                band.frame(height: titlebarHeight).accessibilityIdentifier("sidebar.headerBand")
                background
            }
            .ignoresSafeArea(edges: .top)
        }
        .accessibilityIdentifier("sidebar.headerBackground")
    }
}
#endif
