//  MacScrollBarsTests.swift
//  Regression for task 01d8cfa1 — scroll bars hidden by default, configurable in Settings.

import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacScrollBarsTests: XCTestCase {

    /// Default (the toggle off / key absent) hides them — that is the point of the task.
    func testHiddenWhenTheSettingIsOff() {
        XCTAssertEqual(MacScrollBars.visibility(showScrollBars: false), .hidden)
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

    /// An absent value must read as false (hidden) — the default is the hidden state.
    func testAbsentDefaultReadsAsHidden() {
        let suite = UserDefaults(suiteName: "MacScrollBarsTests")!
        suite.removePersistentDomain(forName: "MacScrollBarsTests")
        XCTAssertFalse(suite.bool(forKey: MacScrollBars.defaultsKey))
        XCTAssertEqual(MacScrollBars.visibility(showScrollBars: suite.bool(forKey: MacScrollBars.defaultsKey)),
                       .hidden)
    }
}
