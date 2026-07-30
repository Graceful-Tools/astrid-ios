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

    /// What the enclosing NSScrollView should be set to (task 1a112a44).
    ///
    /// `scrollIndicators` reaches a `List` or `ScrollView`, but NOT a `Form` with
    /// `.formStyle(.grouped)` — its NSScrollView keeps drawing a scroller regardless. The task
    /// detail is the only grouped Form that is on screen permanently, so it is the only place the
    /// difference shows. Every other one is a settings sheet, long enough that a bar is warranted.
    struct ScrollerConfig: Equatable {
        let hasVerticalScroller: Bool
        /// Hide the scroller when the content fits — "not there unless needed".
        let autohidesScrollers: Bool
        /// Overlay scrollers float over the content and fade out; legacy ones permanently eat a
        /// strip of width, which is the heavy look this preference exists to avoid.
        let usesOverlayStyle: Bool
    }

    static func scrollerConfig(showScrollBars: Bool) -> ScrollerConfig {
        ScrollerConfig(hasVerticalScroller: showScrollBars,
                       autohidesScrollers: true,
                       usesOverlayStyle: true)
    }
}

#if canImport(AppKit)
import AppKit

/// Applies `MacScrollBars.scrollerConfig` to the NSScrollView that actually draws the bar.
/// Needed because a grouped `Form` ignores `scrollIndicators` (task 1a112a44).
struct MacScrollerStyler: NSViewRepresentable {
    let showScrollBars: Bool

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let config = MacScrollBars.scrollerConfig(showScrollBars: showScrollBars)
        // The probe is a background view, so the scroll view is an ancestor — it does not exist
        // yet at make time, hence the walk on every update.
        DispatchQueue.main.async {
            var next = view.superview
            while let current = next {
                if let scrollView = current as? NSScrollView {
                    scrollView.hasVerticalScroller = config.hasVerticalScroller
                    scrollView.autohidesScrollers = config.autohidesScrollers
                    if config.usesOverlayStyle { scrollView.scrollerStyle = .overlay }
                    return
                }
                next = current.superview
            }
        }
    }
}

extension View {
    /// Hide a grouped `Form`'s scroller, which `macScrollBars` alone cannot reach (1a112a44).
    func macFormScrollBars(_ showScrollBars: Bool) -> some View {
        background(MacScrollerStyler(showScrollBars: showScrollBars))
    }
}
#endif

extension View {
    /// Apply the user's scroll-bar preference to a scrollable surface.
    func macScrollBars(_ showScrollBars: Bool) -> some View {
        scrollIndicators(MacScrollBars.visibility(showScrollBars: showScrollBars))
    }
}
#endif
