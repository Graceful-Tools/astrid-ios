//  MonkeySurvivalTests.swift
//  What the monkey calls a death and what it calls a hand-off. Pure — no app is launched — and
//  compiled into both UI-test targets with the rest of `UITestSupport`.

import XCTest

final class MonkeySurvivalTests: XCTestCase {

    func testForegroundIsAlive() {
        XCTAssertEqual(MonkeySurvival.classify(.runningForeground), .foreground)
    }

    /// AITD-580 / AITD-581: the 2026-W45 weekly run failed on both platforms with the app alive.
    /// On iOS a button opened apple.com in Safari; on the Mac TestFlight came to the front. A
    /// backgrounded app that is still running handed the screen to another app — the monkey
    /// brings it back and carries on, it does not report a crash.
    func testBackgroundedButRunningIsAHandOffNotADeath_AITD580() {
        XCTAssertEqual(MonkeySurvival.classify(.runningBackground), .handedOff)
        #if os(iOS)
        XCTAssertEqual(MonkeySurvival.classify(.runningBackgroundSuspended), .handedOff)
        #endif
    }

    func testNotRunningIsADeath() {
        XCTAssertEqual(MonkeySurvival.classify(.notRunning), .died)
        XCTAssertEqual(MonkeySurvival.classify(.unknown), .died)
    }
}
