//  MacRuntimeTests.swift
//  Regression for task 90fa7975 — the test-host guard must detect the XCTest environment, so
//  MacAuthGateView skips starting the Outbox/SSE/sync/hotkey loops and the run exits cleanly.

import XCTest
@testable import Astrid_Mac

final class MacRuntimeTests: XCTestCase {

    func testIsRunningTestsIsTrueUnderXCTest() {
        XCTAssertTrue(MacRuntime.isRunningTests,
                      "MacRuntime.isRunningTests must be true under XCTest so the host stays inert.")
    }
}
