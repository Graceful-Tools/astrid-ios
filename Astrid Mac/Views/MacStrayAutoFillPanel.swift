//  MacStrayAutoFillPanel.swift
//  Astrid for Mac — dismiss the empty Password AutoFill popover macOS parks on the quick-add field.
//  "[mac] wierd square appeared on app open" (AITD-333), and again as "[mac] we get a wierd
//  popover on app open on mac" (AITD-436).
//
//  WHAT IT IS. Not ours. Measured on a running build: an `SPRoundedWindow` from
//  SafariPlatformSupport, hosting an `NSRemoteView` whose service is
//  `com.apple.SafariPlatformSupport.Helper`, added as a CHILD of the app's main window at
//  `NSWindow.Level.popUpMenu`. 183 × 110pt of empty frosted glass over the task rows.
//
//  WHY IT APPEARS. The app declares `webcredentials:astrid.cc` because passkey sign-in requires
//  it, and that makes every text field in the app a Password AutoFill candidate. The quick-add bar
//  takes the caret on launch (task b71850e6, "add task didn't always have a cursor prompt"), macOS
//  offers the credential picker for that focused field, has nothing to put in it — and because the
//  user has not touched anything, no interaction ever dismisses it. It just sits there.
//
//  AVOIDING IT FIRST (AITD-443). The quick-add now declares `quickAddContentType`, a
//  non-AutoFill semantic type, so the field is no longer an untyped credential candidate and the
//  panel should not be summoned at all. The watch below stays as the backstop: if a macOS release
//  offers the picker anyway, it still closes. Once builds show the panel never appears, the watch
//  can go.
//
//  WHY THE WATCH CAME FIRST. Two routes were measured and rejected at the time:
//    - `.textContentType(nil)`: no effect — it was already nil. AITD-333 read that as "every
//      `NSTextContentType` is a credential type", which was true of the macOS 11 set only; the
//      macOS 14 SDK (our deployment target) added non-AutoFill types such as `.dateTime`.
//    - Waiting for the user's first interaction before focusing: it does remove the panel, but a
//      local event monitor sees a key press BEFORE the responder chain does, while the focus change
//      lands a render later — so the first character someone types on launch is delivered to the
//      window and lost. That is b71850e6 again, quieter.
//
//  WHY THIS OWNS ITS OWN STATE. It was first written as `@State` + `.onAppear`/`.onDisappear` on
//  the quick-add field. SwiftUI rebuilds that field during launch, and the resulting `onDisappear`
//  invalidated the timer before it had ticked once — the sweep never ran, twice over, silently.
//  A watch that must outlive the view that armed it has no business hanging off that view's
//  lifecycle, so it hangs off nothing.
//
//  THE NARROWNESS IS THE DESIGN. Our own popovers (priority, assignee, due date) are also child
//  windows at this level, so closing on "child window" alone would break every picker in the app.
//  Three conditions have to hold together, and each one rules out a real window we must not touch:
//    - the window is an `SPRoundedWindow` — AutoFill's own class; an open panel or a share sheet
//      hosts a remote view too, but in a different window;
//    - the content view is an `NSRemoteView` — ours are SwiftUI hosting views, never this;
//    - we are still within a few seconds of the quick-add TAKING FOCUS.
//  Outside that window this does nothing at all, which is what keeps an OS change from turning it
//  into a picker that will not stay open. If Apple renames the class, the panel simply stays — the
//  failure is the old bug, never a broken picker.
//
//  WHY IT CAME BACK (AITD-436). AITD-333 identified the panel by "the user has not interacted
//  yet" and ran once per process. Both were holes:
//    - The panel arrives 1–1.5s after focus. Clicking into the window as it opens ended the watch
//      BEFORE the panel existed, and it then stayed for good. A click that precedes the panel did
//      not ask for it; the window class says what it is, so engagement no longer decides.
//    - The app lives on in the menu bar when its window closes. Reopening it (Dock, "Open Astrid")
//      builds a new window whose quick-add takes focus and summons the panel again, and the watch
//      refused to run twice. It is now armed by every focus the quick-add takes.

#if os(macOS)
import AppKit
import Foundation

enum MacStrayAutoFillPanel {

    /// How long to watch after a focus. The panel arrives a second or two in; past this every
    /// remote view belongs to something the user asked for.
    static let watchDuration: TimeInterval = 5

    /// Sampling interval. The panel stays put for the whole watch, so this decides how quickly it
    /// goes, not whether it is caught.
    static let pollInterval: TimeInterval = 0.25

    /// What the quick-add field declares itself to be (AITD-443). Task titles carry dates ("call
    /// Sam tomorrow") and `.dateTime` is not an AutoFill category — unlike the credential, contact
    /// and card types, it summons no picker — so it answers "not a credential" truthfully.
    static let quickAddContentType: NSTextContentType = .dateTime

    /// The window AutoFill parks on us — SafariPlatformSupport's `SPRoundedWindow`.
    static let autoFillWindowClassName = "SPRoundedWindow"

    /// The content view class of a view hosted by another process. The AutoFill panel's content is
    /// one; nothing the app itself builds is.
    static let remoteViewClassName = "NSRemoteView"

    /// Whether a child window is the stray panel and should be ordered out.
    ///
    /// Pure so the conditions can be asserted — the dangerous half is what it must NOT match, and
    /// a mistake there is a picker that closes itself, which no log would explain.
    static func isStray(windowClassName: String,
                        contentViewClassName: String,
                        isChildOfAppWindow: Bool,
                        secondsSinceWatchStarted: TimeInterval) -> Bool {
        isChildOfAppWindow
            && windowClassName == autoFillWindowClassName
            && contentViewClassName == remoteViewClassName
            && secondsSinceWatchStarted <= watchDuration
    }

    // MARK: - The watch

    @MainActor private static var timer: Timer?

    /// Whether a watch is running now.
    @MainActor static var isWatching: Bool { timer != nil }

    /// Watch for the panel after the quick-add takes focus. A call while a watch is running is a
    /// no-op — SwiftUI rebuilds the field during launch and runs `.onAppear` more than once, and
    /// that must not restart or cancel anything — but once a watch has ended, the next focus
    /// starts a new one (AITD-436).
    @MainActor
    static func beginWatch() {
        guard timer == nil else { return }

        // Elapsed is measured from the first TICK, not from here. Launch saturates the main
        // thread, so a deadline started now can already be spent by the time the run loop
        // services this timer — which is exactly what happened while AITD-333 was being written:
        // the first fire invalidated having done nothing at all.
        var watchingSince: Date?
        let sweep = Timer(timeInterval: pollInterval, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = Date()
                let startedAt = watchingSince ?? now
                watchingSince = startedAt
                let elapsed = now.timeIntervalSince(startedAt)

                guard elapsed <= watchDuration else {
                    endWatch()
                    return
                }
                dismissStrayPanels(secondsWatching: elapsed)
            }
        }
        // `.common` so it keeps firing through the tracking and animation modes the main loop
        // enters while the window is coming up.
        RunLoop.main.add(sweep, forMode: .common)
        timer = sweep
    }

    @MainActor
    static func endWatch() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private static func dismissStrayPanels(secondsWatching: TimeInterval) {
        for window in NSApp.windows {
            guard let content = window.contentView, window.parent != nil else { continue }
            guard isStray(windowClassName: NSStringFromClass(type(of: window)),
                          contentViewClassName: NSStringFromClass(type(of: content)),
                          isChildOfAppWindow: true,
                          secondsSinceWatchStarted: secondsWatching) else { continue }
            window.orderOut(nil)
        }
    }
}
#endif
