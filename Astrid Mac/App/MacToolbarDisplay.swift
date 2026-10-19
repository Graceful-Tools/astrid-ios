//  MacToolbarDisplay.swift
//  Astrid for Mac — the window toolbar is icons only, with no menu to change that (AITD-510).
//
//  Right-clicking a SwiftUI window toolbar offers AppKit's display-mode menu, "Icon and Text /
//  Icon Only". SwiftUI has no modifier for it, so the window's NSToolbar is reached directly and
//  pinned: icon-only, and (macOS 15+) the menu switched off. Jon: "should only be icons only".

#if os(macOS)
import AppKit
import SwiftUI

@MainActor
enum MacToolbarDisplay {

    /// Icon-only, and nothing offered to change it.
    static func lockToIconsOnly(_ toolbar: NSToolbar) {
        if toolbar.displayMode != .iconOnly { toolbar.displayMode = .iconOnly }
        if #available(macOS 15.0, *), toolbar.allowsDisplayModeCustomization {
            toolbar.allowsDisplayModeCustomization = false
        }
    }
}

extension View {
    /// Pins the hosting window's toolbar to icons only (AITD-510).
    func macIconOnlyToolbar() -> some View {
        background(MacIconOnlyToolbarAnchor().frame(width: 0, height: 0))
    }
}

/// A zero-size view whose only job is to find its window. SwiftUI installs the toolbar after the
/// content joins the window and can rebuild it when the items change, so this re-applies on
/// every update and whenever the window becomes key rather than once.
private struct MacIconOnlyToolbarAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) { view.apply() }

    final class AnchorView: NSView {
        private var keyObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
            keyObserver = nil
            guard let window else { return }
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
            apply()
            // The toolbar may not exist yet on the first pass.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let toolbar = window?.toolbar else { return }
            MacToolbarDisplay.lockToIconsOnly(toolbar)
        }
        // No deinit: leaving the window calls viewDidMoveToWindow with nil, which removes the
        // observer, and an isolated deinit is its own hazard here.
    }
}
#endif
