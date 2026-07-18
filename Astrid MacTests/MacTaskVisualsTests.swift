//  MacTaskVisualsTests.swift
//  Regression for the Mac UI mapping — the Mac task visuals must match the iOS priority
//  symbols/labels/order so the two platforms read the same.

import XCTest
@testable import Astrid_Mac

final class MacTaskVisualsTests: XCTestCase {

    func testPrioritySymbolsMatchiOS() {
        XCTAssertEqual(MacTaskVisuals.prioritySymbol(.none), "○")
        XCTAssertEqual(MacTaskVisuals.prioritySymbol(.low), "!")
        XCTAssertEqual(MacTaskVisuals.prioritySymbol(.medium), "!!")
        XCTAssertEqual(MacTaskVisuals.prioritySymbol(.high), "!!!")
    }

    func testPriorityLabels() {
        XCTAssertEqual(MacTaskVisuals.priorityLabel(.none), "None")
        XCTAssertEqual(MacTaskVisuals.priorityLabel(.high), "High")
    }

    func testAllPrioritiesOrderLowToHigh() {
        XCTAssertEqual(MacTaskVisuals.allPriorities, [.none, .low, .medium, .high])
    }
}
