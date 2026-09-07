//  MacSidebarChrome.swift
//  Astrid for Mac — the colour of the sidebar's top and bottom strips (AITD-307).
//
//  TWO views paint this strip: the `safeAreaInset` container in MacRootView, and the
//  MacSidebarAccountBar drawn on top of it, which covers the whole footer. Task 6531e684 fixed
//  the container and left the bar reading `Theme.bgPrimary` — so the correct colour underneath
//  was hidden by a stale one, and the footer read white in every theme.
//
//  `Theme.bgPrimary` is the trap. It resolves through `Theme.currentThemeMode`, a cached global
//  invalidated asynchronously by a `UserDefaults.didChangeNotification` observer: it gives a body
//  no reason to re-run on a theme change, and it can hand back the previous theme even to a body
//  that IS re-running. So the mode has to be OBSERVED by each view and passed in — and, since two
//  views need the same answer, the mapping lives here once rather than being written twice and
//  drifting, which is how the two layers disagreed in the first place.

#if os(macOS)
import SwiftUI

enum MacSidebarChrome {
    /// The sidebar's surface colour, as a pure function of a mode the caller observes.
    static func background(mode: String) -> Color {
        Theme.themed(mode: mode,
                     light: .white,
                     dark: Theme.Dark.bgPrimary,
                     ocean: Theme.Ocean.bgPrimary)
    }
}
#endif
