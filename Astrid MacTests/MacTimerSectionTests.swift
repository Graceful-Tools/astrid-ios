//  MacTimerSectionTests.swift
//  Regression tests for Task b2785c35 — "[mac] remove the Timer section; it should only show when
//  a timer is started".
//
//  The section sat under Comments on every task, showing 00:00:00 and a Start button whether or not
//  the task would ever be timed. iOS keeps only a "last timer" caption inline.

import XCTest
@testable import Astrid_Mac

final class MacTimerSectionTests: XCTestCase {

    func testSectionOnlyWhileRunning() {
        XCTAssertTrue(MacTimerSection.showsSection(running: true))
        XCTAssertFalse(MacTimerSection.showsSection(running: false),
                       "A stopped timer must not occupy the pane")
    }

    /// A task that HAS been timed keeps its recorded time visible — as one caption line, not a
    /// section — so hiding the section never hides the data.
    func testLoggedTimeKeepsACaptionWhenStopped() {
        XCTAssertTrue(MacTimerSection.showsLoggedCaption(running: false, loggedSeconds: 125))
        XCTAssertFalse(MacTimerSection.showsLoggedCaption(running: false, loggedSeconds: 0))
    }

    /// While running, the section already shows the clock — a caption too would be duplication.
    func testNoCaptionWhileTheSectionIsShowing() {
        XCTAssertFalse(MacTimerSection.showsLoggedCaption(running: true, loggedSeconds: 125))
    }

    /// Starting stays reachable from the ⋮ menu — otherwise hiding the section removes the feature.
    func testStartIsOfferedInTheMenuOnlyWhenNotRunning() {
        XCTAssertTrue(MacTimerSection.offersStartInMenu(running: false))
        XCTAssertFalse(MacTimerSection.offersStartInMenu(running: true))
    }
}
