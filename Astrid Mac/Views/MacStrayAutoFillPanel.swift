//  MacStrayAutoFillPanel.swift
//  Astrid for Mac — dismiss the empty Password AutoFill popover macOS parks on us at launch.
//  "[mac] wierd square appeared on app open" (AITD-333).
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
//  WHY WE CLOSE IT RATHER THAN AVOID IT. Two other routes were measured and rejected:
//    - `.textContentType(nil)`: no effect. It was already nil, and every `NSTextContentType`
//      AppKit defines is a credential type, so there is no value meaning "not a credential".
//    - Waiting for the user's first interaction before focusing: it does remove the panel, but a
//      local event monitor sees a key press BEFORE the responder chain does, while the focus change
//      lands a render later — so the first character someone types on launch is delivered to the
//      window and lost. That is b71850e6 again, quieter.
//
//  WHY THIS OWNS ITS OWN STATE. It was first written as `@State` + `.onAppear`/`.onDisappear` on
//  the quick-add field. SwiftUI rebuilds that field during launch, and the resulting `onDisappear`
//  invalidated the timer before it had ticked once — the sweep never ran, twice over, silently.
//  A launch-scoped job has no business hanging off a view's lifecycle, so it hangs off nothing.
//
//  THE NARROWNESS IS THE DESIGN. Our own popovers (priority, assignee, due date) are also child
//  windows at this level, so closing on "child window" alone would break every picker in the app.
//  Three conditions have to hold together, and each one rules out a real window we must not touch:
//    - the content view is an `NSRemoteView` — ours are SwiftUI hosting views, never this;
//    - the user has not interacted yet — every one of our popovers needs a click to open, and so
//      does anything else remote (an NSOpenPanel, a share sheet);
//    - we are still within a few seconds of the watch STARTING TO RUN.
//  Outside that window this does nothing at all, which is what keeps an OS change from turning it
//  into a picker that will not stay open.

#if os(macOS)
import AppKit
import Foundation

enum MacStrayAutoFillPanel {

    /// How long to watch. The panel arrives a second or two in; past this the app is in ordinary
    /// use and every remote view belongs to something the user asked for.
    static let watchDuration: TimeInterval = 5

    /// Sampling interval. The panel stays put for the whole watch, so this decides how quickly it
    /// goes, not whether it is caught.
    static let pollInterval: TimeInterval = 0.25

    /// The content view class of a view hosted by another process. The AutoFill panel's content is
    /// one; nothing the app itself builds is.
    static let remoteViewClassName = "NSRemoteView"

    /// Whether a child window is the stray panel and should be ordered out.
    ///
    /// Pure so the conditions can be asserted — the dangerous half is what it must NOT match, and
    /// a mistake there is a picker that closes itself, which no log would explain.
    static func isStray(contentViewClassName: String,
                        isChildOfAppWindow: Bool,
                        hasUserEngaged: Bool,
                        secondsSinceLaunch: TimeInterval) -> Bool {
        isChildOfAppWindow
            && contentViewClassName == remoteViewClassName
            && !hasUserEngaged
            && secondsSinceLaunch <= watchDuration
    }

    // MARK: - The watch

    @MainActor private static var timer: Timer?
    @MainActor private static var engagementMonitor: Any?
    @MainActor private static var hasUserEngaged = false
    @MainActor private static var hasRun = false

    /// Start the launch watch. Idempotent: the quick-add field calls this from `.onAppear`, which
    /// SwiftUI may run more than once, and a second call must not restart or cancel anything.
    @MainActor
    static func beginLaunchWatch() {
        guard !hasRun else { return }
        hasRun = true

        // Any real interaction means anything remote on screen was asked for. `.mouseMoved` is in
        // the mask for completeness, though a window only delivers it when asked to — the click,
        // key and scroll cases are what actually carry this.
        engagementMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .mouseMoved]
        ) { event in
            noteUserEngagement()
            return event          // observed, never swallowed
        }

        // Elapsed is measured from the first TICK, not from here. Launch saturates the main
        // thread, so a deadline started now can already be spent by the time the run loop
        // services this timer — which is exactly what happened while this was being written: the
        // first fire invalidated having done nothing at all.
        var watchingSince: Date?
        let sweep = Timer(timeInterval: pollInterval, repeats: true) { timer in
            MainActor.assumeIsolated {
                let now = Date()
                let startedAt = watchingSince ?? now
                watchingSince = startedAt
                let elapsed = now.timeIntervalSince(startedAt)

                guard elapsed <= watchDuration, !hasUserEngaged else {
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
    private static func dismissStrayPanels(secondsWatching: TimeInterval) {
        for window in NSApp.windows {
            guard let content = window.contentView, window.parent != nil else { continue }
            guard isStray(contentViewClassName: NSStringFromClass(type(of: content)),
                          isChildOfAppWindow: true,
                          hasUserEngaged: hasUserEngaged,
                          secondsSinceLaunch: secondsWatching) else { continue }
            window.orderOut(nil)
        }
    }

    @MainActor
    private static func noteUserEngagement() {
        hasUserEngaged = true
        endWatch()
    }

    @MainActor
    private static func endWatch() {
        timer?.invalidate()
        timer = nil
        if let engagementMonitor { NSEvent.removeMonitor(engagementMonitor) }
        engagementMonitor = nil
    }
}
#endif
