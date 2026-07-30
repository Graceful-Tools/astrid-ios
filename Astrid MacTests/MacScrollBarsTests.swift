//  MacScrollBarsTests.swift
//  Regression for task 01d8cfa1 — scroll bars hidden by default, configurable in Settings.

import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacScrollBarsTests: XCTestCase {

    /// Default (the toggle off / key absent) hides them — that is the point of the task.
    func testHiddenWhenTheSettingIsOff() {
        // `.never`, not `.hidden` — macOS still draws the scroller for `.hidden` when the system
        // preference is "always show scroll bars", which is exactly what was still appearing.
        XCTAssertEqual(MacScrollBars.visibility(showScrollBars: false), .never)
    }

    /// Turning it on restores the SYSTEM behaviour (.automatic), not "always visible" — macOS
    /// still honours the user's global "Show scroll bars" preference from there.
    func testSystemBehaviourWhenTheSettingIsOn() {
        XCTAssertEqual(MacScrollBars.visibility(showScrollBars: true), .automatic)
    }

    /// The Settings toggle and every scroll surface must read the SAME key, or the preference
    /// silently applies to nothing.
    func testDefaultsKeyIsStable() {
        XCTAssertEqual(MacScrollBars.defaultsKey, "showScrollBars")
    }

    // MARK: the detail pane's grouped Form (task 1a112a44)

    /// `scrollIndicators` reaches a List or a ScrollView but not a grouped Form, so the task
    /// detail kept a bar down its right edge whether or not anything overflowed. The AppKit
    /// config is what actually lands on that Form's NSScrollView.
    func testDetailFormHasNoScrollerWhenTheSettingIsOff() {
        let config = MacScrollBars.scrollerConfig(showScrollBars: false)
        XCTAssertFalse(config.hasVerticalScroller)
    }

    /// "Not there unless needed" — even with the setting ON the scroller autohides when the
    /// content fits, and floats over the content instead of eating a permanent strip of width.
    func testScrollerIsOnlyThereWhenNeeded() {
        for showScrollBars in [true, false] {
            let config = MacScrollBars.scrollerConfig(showScrollBars: showScrollBars)
            XCTAssertTrue(config.autohidesScrollers,
                          "setting=\(showScrollBars): a scroller must hide when nothing overflows")
            XCTAssertTrue(config.usesOverlayStyle,
                          "setting=\(showScrollBars): legacy scrollers permanently eat width")
        }
    }

    /// The AppKit path and the SwiftUI path must agree, or the detail pane disagrees with the
    /// task list about the same preference.
    func testAppKitAndSwiftUIPathsAgree() {
        XCTAssertEqual(MacScrollBars.visibility(showScrollBars: false), .never)
        XCTAssertFalse(MacScrollBars.scrollerConfig(showScrollBars: false).hasVerticalScroller)

        XCTAssertEqual(MacScrollBars.visibility(showScrollBars: true), .automatic)
        XCTAssertTrue(MacScrollBars.scrollerConfig(showScrollBars: true).hasVerticalScroller)
    }

    /// An absent value must read as false (hidden) — the default is the hidden state.
    func testAbsentDefaultReadsAsHidden() {
        let suite = UserDefaults(suiteName: "MacScrollBarsTests")!
        suite.removePersistentDomain(forName: "MacScrollBarsTests")
        XCTAssertFalse(suite.bool(forKey: MacScrollBars.defaultsKey))
        XCTAssertEqual(MacScrollBars.visibility(showScrollBars: suite.bool(forKey: MacScrollBars.defaultsKey)),
                       .never)
    }
}
