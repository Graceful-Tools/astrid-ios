//  MacReopen.swift
//  Opening the app when it is already running has to produce a window (task 39470057).
//
//  Jon: "first login app doesn't open. Second app open it works."
//
//  REPRODUCED, 2026-08-16, and it is worse than reported — the second open does not work either:
//
//      $ open /Applications/Astrid.app
//      $ osascript -e 'tell application "System Events" to tell process "Astrid" \
//                      to get count of windows'
//      0
//
//  WHY. The app has a `MenuBarExtra`, so closing the last window does not quit it — it keeps
//  running with no window at all. From then on every Dock click, Finder open and `open` is a
//  REOPEN, not a launch, and AppKit's default reopen behaviour is to front an existing window.
//  There is none, so nothing happens, silently and forever. The app looks broken; it is running.
//
//  A SwiftUI `WindowGroup` does not re-create its window on its own here, and nothing in the app
//  handled `applicationShouldHandleReopen`. Nothing could have: there was no app delegate.
//
//  WHY THE ACTION IS CAPTURED RATHER THAN CALLED DIRECTLY. `openWindow` is an
//  `@Environment` value, so it only exists inside a view — and at reopen time there is no view
//  alive to read it from, which is the whole problem. `OpenWindowAction` stays valid after the
//  window that provided it is gone, so the app captures it once while a window does exist and
//  uses it later.

#if os(macOS)
import SwiftUI
import AppKit

enum MacReopen {

    /// The main window's scene id. Must match the `WindowGroup(id:)` in `AstridMacApp`.
    static let mainWindowID = "main"

    /// Whether a reopen has to build a window.
    ///
    /// Split out so the rule is testable without an NSApplication: the delegate callback cannot
    /// be exercised in a unit test, but the decision it makes can.
    static func needsNewWindow(hasVisibleWindows: Bool) -> Bool {
        !hasVisibleWindows
    }

    /// The `openWindow` action, captured from a view while one exists.
    ///
    /// `nonisolated(unsafe)` matches the pattern already used for the theme cache: written and
    /// read on the main thread only (view lifecycle and the delegate callback are both main).
    nonisolated(unsafe) private static var openWindow: OpenWindowAction?

    @MainActor
    static func captureOpenWindow(_ action: OpenWindowAction) {
        openWindow = action
    }

    /// A launch with no saved window state opens no window at all — measured 2026-09-30: `open
    /// Astrid.app --args -ApplePersistenceIgnoreState YES` leaves the app running, frontmost, with
    /// zero windows, and so does a first launch on a Mac that has never run it. Only a launch that
    /// RESTORED a window showed one, which is why it looked fine on a machine in daily use. When
    /// SwiftUI has had its turn and there is still no main window, open one.
    ///
    /// `openWindow` is captured from the App when its scenes are built, before any window exists.
    /// (AppKit's `newWindowForTab:` is not answered here — the File menu's New item is replaced.)
    @MainActor
    static func ensureMainWindowAtLaunch() {
        let hasMain = NSApp.windows.contains { window in
            window.identifier?.rawValue.hasPrefix("\(mainWindowID)-") == true && window.isVisible
        }
        guard !hasMain else { return }
        // Not `restoreMainWindow()`: that fronts any key-capable window, and at launch the only
        // one may be a helper window of SwiftUI's own with nothing in it.
        NSApp.activate(ignoringOtherApps: true)
        openWindow?(id: mainWindowID)
    }

    /// Bring the app back to a usable state: a window, in front.
    ///
    /// Ordering matters. Activating first means the new window arrives in an already-frontmost
    /// app, so it cannot appear behind whatever the user was looking at — which would read as
    /// the same bug.
    @MainActor
    static func restoreMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let existing = NSApp.windows.first(where: { $0.canBecomeKey && !$0.isMiniaturized }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        openWindow?(id: mainWindowID)
    }
}

/// Kept minimal on purpose: an app delegate in a SwiftUI app is a place where behaviour
/// accumulates quietly. It has two jobs: reopen, and — under UI testing only —
/// keeping one test's windows from being restored into the next (`MacUITestWindows`).
final class MacAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !MacRuntime.isRunningTests else { return }
        MainActor.assumeIsolated {
            if MacUITestArgs.isUITesting { MacUITestWindows.stopSavingWindowState() }
            // Give SwiftUI its turn to open or restore windows first.
            DispatchQueue.main.async { MainActor.assumeIsolated { MacReopen.ensureMainWindowAtLaunch() } }
        }
    }

    /// Dock click, Finder open, `open`, or a second launch attempt while running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // The unit-test host is this app. Creating windows during a test run is what made the
        // suite hang before (task 90fa7975), so stay inert.
        guard !MacRuntime.isRunningTests else { return true }

        if MacReopen.needsNewWindow(hasVisibleWindows: hasVisibleWindows) {
            MacReopen.restoreMainWindow()
        }
        return true
    }
}
#endif
