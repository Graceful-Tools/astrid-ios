//  MacStrayAutoFillPanelTests.swift
//  Regression guard for AITD-333 — "[mac] wierd square appeared on app open".
//
//  The square is macOS's Password AutoFill popover, parked empty on the quick-add field at launch
//  and never dismissed because the user has not interacted with anything yet. We close it.
//
//  Almost every assertion here is about what must NOT be closed. Our own pickers — priority,
//  assignee, due date, list — are child windows at the very same window level, so a rule that
//  matched on "child window" alone would make every popover in the app close itself the instant it
//  opened. That failure would look like nothing at all in a log, so the conditions are pinned.

import XCTest
@testable import Astrid_Mac

final class MacStrayAutoFillPanelTests: XCTestCase {

    /// The panel exactly as measured on a running build: an NSRemoteView-backed child window, at
    /// launch, before the user has touched anything.
    func testClosesTheEmptyAutoFillPanelAtLaunch() {
        XCTAssertTrue(MacStrayAutoFillPanel.isStray(
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: true,
            hasUserEngaged: false,
            secondsSinceLaunch: 1.5))
    }

    // MARK: - What it must never close

    /// OUR pickers. They sit at the same level and are also child windows — the content view is
    /// what separates them, because SwiftUI hosts its own views in-process.
    func testNeverClosesOurOwnPopovers() {
        for ours in ["NSHostingView", "_NSHostingView", "NSVisualEffectView", "NSView"] {
            XCTAssertFalse(MacStrayAutoFillPanel.isStray(
                contentViewClassName: ours,
                isChildOfAppWindow: true,
                hasUserEngaged: false,
                secondsSinceLaunch: 1.5),
                "\(ours) is one of our own popovers — closing it breaks the picker")
        }
    }

    /// Once the user has interacted, a remote view is something they ASKED for — an open panel, a
    /// share sheet, an AutoFill they actually invoked by clicking into a field.
    func testNeverClosesARemoteViewTheUserAskedFor() {
        XCTAssertFalse(MacStrayAutoFillPanel.isStray(
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: true,
            hasUserEngaged: true,
            secondsSinceLaunch: 1.5),
            "After an interaction the user opened this themselves")
    }

    /// And past the launch window it stops entirely. This is the condition that keeps an OS change
    /// from turning this into a permanent hostility toward system panels.
    func testStopsWatchingAfterTheLaunchWindow() {
        XCTAssertFalse(MacStrayAutoFillPanel.isStray(
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: true,
            hasUserEngaged: false,
            secondsSinceLaunch: MacStrayAutoFillPanel.watchDuration + 0.01))
    }

    /// Boundary: still watching right up to the deadline.
    func testStillWatchingAtTheDeadline() {
        XCTAssertTrue(MacStrayAutoFillPanel.isStray(
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: true,
            hasUserEngaged: false,
            secondsSinceLaunch: MacStrayAutoFillPanel.watchDuration))
    }

    /// A window that is not ours to manage is never touched, whatever it contains.
    func testNeverClosesAWindowThatIsNotOurChild() {
        XCTAssertFalse(MacStrayAutoFillPanel.isStray(
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: false,
            hasUserEngaged: false,
            secondsSinceLaunch: 1.0))
    }

    /// The watch is short — it exists for a panel that appears 1–2s in, not as a standing policy.
    func testTheWatchIsShort() {
        XCTAssertLessThanOrEqual(MacStrayAutoFillPanel.watchDuration, 10,
                                 "A long watch turns a launch fix into a standing fight with AppKit")
        XCTAssertGreaterThan(MacStrayAutoFillPanel.watchDuration, 2,
                             "The panel arrives 1–2s after launch — stopping sooner would miss it")
    }
}
