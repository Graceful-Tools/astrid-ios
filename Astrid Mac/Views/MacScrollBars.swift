//  MacScrollBars.swift
//  Astrid for Mac — scroll-bar visibility (task 01d8cfa1).
//
//  macOS shows overlay scrollers only while scrolling ONLY when the system setting says so; with
//  "Show scroll bars: Always" (or a mouse attached) they are permanently visible and eat into the
//  content, which looks heavy next to the web and iOS apps. Astrid hides them by default and lets
//  the user turn them back on in Settings.

#if os(macOS)
import SwiftUI

enum MacScrollBars {
    /// UserDefaults key backing the Settings toggle. Default (absent) = hidden.
    static let defaultsKey = "showScrollBars"

    /// Pure mapping so the rule is testable without a view.
    /// `.never`, not `.hidden`: with the system preference set to "Show scroll bars: Always" (or a
    /// mouse attached) macOS still draws the scroller for `.hidden`, which is why bars were still
    /// showing in the task list. `.never` suppresses them regardless of that system setting.
    static func visibility(showScrollBars: Bool) -> ScrollIndicatorVisibility {
        showScrollBars ? .automatic : .never
    }
}

extension View {
    /// Apply the user's scroll-bar preference to a scrollable surface.
    func macScrollBars(_ showScrollBars: Bool) -> some View {
        scrollIndicators(MacScrollBars.visibility(showScrollBars: showScrollBars))
    }
}
#endif
