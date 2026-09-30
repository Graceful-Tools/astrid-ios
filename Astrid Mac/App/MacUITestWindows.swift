//  MacUITestWindows.swift
//  Under UI testing, every launch starts from one fresh main window.
//
//  XCUITest ends each test by killing the app with its windows open, and macOS restores what was
//  open at the next launch. So a test inherited whatever the one before it left: the monkey's
//  task window, taken full screen, covered the sign-in from a Space of its own; a second main
//  window covered the first one's "Continue without an account"; a Quick Add window came back
//  with no main window at all. Each time, every test after it failed to reach the shell
//  (2026-09-29/30). And the UI suite shares the installed app's container (same bundle id), so
//  the same saved state was also replacing the real app's window layout.
//
//  Two halves: nothing a UI-tested app opens is saved for next time, and whatever an earlier run
//  did save is closed once at launch.

#if os(macOS)
import AppKit

@MainActor
enum MacUITestWindows {

    private static var observers: [NSObjectProtocol] = []
    private static var didCloseRestoredWindows = false

    /// Mark every window unrestorable as it appears, so AppKit keeps no state for it.
    static func stopSavingWindowState() {
        forgetAll()
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { forgetAll() }
            })
        }
    }

    private static func forgetAll() {
        for window in NSApp.windows where window.isRestorable {
            window.isRestorable = false
            window.invalidateRestorableState()
        }
    }

    /// Once: close what an earlier run left open, keeping a single main window.
    static func closeWindowsRestoredFromAnEarlierRun() {
        guard !didCloseRestoredWindows else { return }
        didCloseRestoredWindows = true
        let restored = NSApp.windows.filter { window in
            guard let id = window.identifier?.rawValue else { return false }
            return id.hasPrefix("task-") || id.hasPrefix("main-") || id == "quick-add"
        }
        // The one kept is the window this launch is showing — which, when this runs from its
        // `onAppear`, may not count as visible yet. Keeping only a VISIBLE one closed it.
        let mains = restored.filter { $0.identifier?.rawValue.hasPrefix("main-") == true }
        let keep = mains.first { $0.isKeyWindow } ?? mains.first { $0.isVisible } ?? mains.first
        for window in restored where window !== keep {
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            window.close()
        }
    }
}
#endif
