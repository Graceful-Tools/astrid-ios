//  MacStrayAutoFillPanelTests.swift
//  Regression guard for AITD-333 — "[mac] wierd square appeared on app open".
//
//  The square is macOS's Password AutoFill popover, parked empty on the quick-add field when it
//  takes focus and never dismissed. We close it. AITD-436 is the same panel escaping the watch.
//
//  Almost every assertion here is about what must NOT be closed. Our own pickers — priority,
//  assignee, due date, list — are child windows at the very same window level, so a rule that
//  matched on "child window" alone would make every popover in the app close itself the instant it
//  opened. That failure would look like nothing at all in a log, so the conditions are pinned.

import XCTest
import AppKit
@testable import Astrid_Mac

final class MacStrayAutoFillPanelTests: XCTestCase {

    /// The panel exactly as measured on a running build: an SPRoundedWindow child hosting an
    /// NSRemoteView, shortly after the quick-add took focus.
    func testClosesTheEmptyAutoFillPanelAtLaunch() {
        XCTAssertTrue(MacStrayAutoFillPanel.isStray(
            windowClassName: "SPRoundedWindow",
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: true,
            secondsSinceWatchStarted: 1.5))
    }

    // MARK: - What it must never close

    /// OUR pickers. They sit at the same level and are also child windows — the content view is
    /// what separates them, because SwiftUI hosts its own views in-process.
    func testNeverClosesOurOwnPopovers() {
        for ours in ["NSHostingView", "_NSHostingView", "NSVisualEffectView", "NSView"] {
            XCTAssertFalse(MacStrayAutoFillPanel.isStray(
                windowClassName: "SPRoundedWindow",
                contentViewClassName: ours,
                isChildOfAppWindow: true,
                secondsSinceWatchStarted: 1.5),
                "\(ours) is one of our own popovers — closing it breaks the picker")
        }
    }

    /// And past the launch window it stops entirely. This is the condition that keeps an OS change
    /// from turning this into a permanent hostility toward system panels.
    func testStopsWatchingAfterTheLaunchWindow() {
        XCTAssertFalse(MacStrayAutoFillPanel.isStray(
            windowClassName: "SPRoundedWindow",
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: true,
            secondsSinceWatchStarted: MacStrayAutoFillPanel.watchDuration + 0.01))
    }

    /// Boundary: still watching right up to the deadline.
    func testStillWatchingAtTheDeadline() {
        XCTAssertTrue(MacStrayAutoFillPanel.isStray(
            windowClassName: "SPRoundedWindow",
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: true,
            secondsSinceWatchStarted: MacStrayAutoFillPanel.watchDuration))
    }

    /// A window that is not ours to manage is never touched, whatever it contains.
    func testNeverClosesAWindowThatIsNotOurChild() {
        XCTAssertFalse(MacStrayAutoFillPanel.isStray(
            windowClassName: "SPRoundedWindow",
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: false,
            secondsSinceWatchStarted: 1.0))
    }

    /// The watch is short — it exists for a panel that appears 1–2s in, not as a standing policy.
    func testTheWatchIsShort() {
        XCTAssertLessThanOrEqual(MacStrayAutoFillPanel.watchDuration, 10,
                                 "A long watch turns a launch fix into a standing fight with AppKit")
        XCTAssertGreaterThan(MacStrayAutoFillPanel.watchDuration, 2,
                             "The panel arrives 1–2s after launch — stopping sooner would miss it")
    }

    // MARK: - AITD-436: the panel came back

    /// "[mac] we get a wierd popover on app open on mac" (AITD-436). The AITD-333 rule let any
    /// click, key or scroll end the watch — but the panel arrives 1–1.5s after the field takes
    /// focus, so clicking into the window as it opens ended the watch BEFORE the panel existed,
    /// and it then sat there for good. What identifies the panel is its window class, not
    /// whether the user has touched anything.
    func testClosesTheAutoFillPanelEvenAfterAnEarlyClick_AITD436() {
        XCTAssertTrue(MacStrayAutoFillPanel.isStray(
            windowClassName: "SPRoundedWindow",
            contentViewClassName: "NSRemoteView",
            isChildOfAppWindow: true,
            secondsSinceWatchStarted: 1.5),
            "A click before the panel appeared did not ask for it")
    }

    /// Other remote panels — an open panel, a share sheet — share the NSRemoteView content but
    /// not the AutoFill window class, so the class is what keeps them safe now.
    func testNeverClosesAnotherRemotePanel_AITD436() {
        for other in ["NSRemoteOpenPanel", "NSWindow", "NSPanel", "_NSPopoverWindow"] {
            XCTAssertFalse(MacStrayAutoFillPanel.isStray(
                windowClassName: other,
                contentViewClassName: "NSRemoteView",
                isChildOfAppWindow: true,
                secondsSinceWatchStarted: 1.5),
                "\(other) hosting a remote view is not the AutoFill panel")
        }
    }

    /// The watch ran once per PROCESS. The app lives on in the menu bar when its window closes,
    /// so reopening it (Dock, "Open Astrid") builds a new window whose quick-add takes focus and
    /// summons the panel — and the watch refused to start again.
    @MainActor
    func testTheWatchRearmsForALaterFocus_AITD436() {
        MacStrayAutoFillPanel.beginWatch()
        XCTAssertTrue(MacStrayAutoFillPanel.isWatching)
        MacStrayAutoFillPanel.endWatch()
        XCTAssertFalse(MacStrayAutoFillPanel.isWatching)

        MacStrayAutoFillPanel.beginWatch()
        XCTAssertTrue(MacStrayAutoFillPanel.isWatching,
                      "A second focus — a reopened window — must be watched too")
        MacStrayAutoFillPanel.endWatch()
    }

    // MARK: - AITD-443: avoid the panel, not just close it

    /// "[mac] Popover now closes on add task (which is good) but is there a more elegant fix to
    /// avoid that showing up in the first place?" (AITD-443). The quick-add had NO content type,
    /// and with `webcredentials:astrid.cc` declared an untyped field is a Password AutoFill
    /// candidate. AITD-333 believed every `NSTextContentType` was a credential type; the macOS 14
    /// SDK (our deployment target) also has non-AutoFill semantic types, so the field now says
    /// what it is.
    func testQuickAddDeclaresANonAutoFillContentType_AITD443() {
        let type = MacStrayAutoFillPanel.quickAddContentType
        let autoFill: [NSTextContentType] = [
            .username, .password, .newPassword, .oneTimeCode,
            .name, .givenName, .familyName, .emailAddress, .telephoneNumber, .fullStreetAddress,
            .creditCardNumber, .creditCardName,
        ]
        XCTAssertFalse(autoFill.contains(type),
                       "\(type.rawValue) is an AutoFill category — it would summon a picker, not stop one")
    }
}
