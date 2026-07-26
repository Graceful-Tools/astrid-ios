//  MacThemedSurface.swift
//  Astrid for Mac — one modifier that carries the theme onto secondary surfaces (Task 55f435c2):
//  Settings tabs, sheets, and auth screens previously rendered stock system chrome next to a
//  themed (e.g. Ocean-cyan) main window.

#if os(macOS)
import SwiftUI
import AppKit

/// Which color scheme a themed surface must impose so SYSTEM-drawn text (Form labels, Toggle
/// titles, Picker text) stays legible on the painted background.
///
/// Painting `Theme.bgPrimary` alone is not enough: with the app theme set to Light while macOS
/// itself is in Dark mode, the surface turned white while the system kept drawing white labels on
/// it — settings text was invisible (task b365f261). Same failure mode as MacDetailChrome's
/// white-on-white detail card. Pure + testable.
enum MacSurfaceScheme {
    /// nil = follow the system (only correct for "auto", where background and text agree already).
    static func colorScheme(mode: String) -> ColorScheme? {
        switch mode {
        case "dark":            return .dark
        case "light", "ocean":  return .light   // both paint light surfaces (white / cyan)
        default:                return nil      // auto — system appearance already matches
        }
    }
}

extension View {
    /// Themed surface for Forms/sheets: hide the system scroll background, paint Theme.bgPrimary,
    /// and pin the color scheme so system-drawn text contrasts with it.
    func macThemedSurface() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.bgPrimary)
            .preferredColorScheme(MacSurfaceScheme.colorScheme(mode: Theme.currentThemeMode))
    }
}
#endif
