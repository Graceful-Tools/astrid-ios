//  MacThemedSurface.swift
//  Astrid for Mac — one modifier that carries the theme onto secondary surfaces (Task 55f435c2):
//  Settings tabs, sheets, and auth screens previously rendered stock system chrome next to a
//  themed (e.g. Ocean-cyan) main window.

#if os(macOS)
import SwiftUI

extension View {
    /// Themed surface for Forms/sheets: hide the system scroll background and paint Theme.bgPrimary.
    func macThemedSurface() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.bgPrimary)
    }
}
#endif
