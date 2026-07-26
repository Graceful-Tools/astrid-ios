//  MacTaskVisualsTests.swift
//  Regression for the Mac UI mapping — the Mac task visuals must match the iOS priority
//  symbols/labels/order so the two platforms read the same.

import XCTest
import SwiftUI
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

    /// Priority buttons stay desktop-compact (0c1c83d4) — no touch-target-sized 36×30 buttons.
    func testPriorityButtonsAreCompact() {
        XCTAssertLessThanOrEqual(MacPriorityPicker.buttonWidth, 30)
        XCTAssertLessThanOrEqual(MacPriorityPicker.buttonHeight, 24)
        XCTAssertGreaterThanOrEqual(MacPriorityPicker.buttonHeight, 18, "Still clickable")
    }
}

// MARK: - Checkbox proportions (task: "checkbox size should be smaller relative to checkmark")

extension MacTaskVisualsTests {

    /// The mark must dominate the box, like the iOS asset — it used to sit at 0.62, which read as
    /// a small tick inside a chunky box.
    func testCheckmarkFillsMostOfTheBox() {
        XCTAssertGreaterThanOrEqual(MacTaskVisuals.checkmarkRatio, 0.75)
        XCTAssertLessThan(MacTaskVisuals.checkmarkRatio, 1.0, "The mark must still fit inside the box")
    }

    /// The stroke scales with the box instead of being 2pt at every size, so a small checkbox
    /// doesn't look chunkier than a large one.
    func testStrokeScalesWithTheBox() {
        XCTAssertLessThan(MacTaskVisuals.checkboxStroke(size: 20), MacTaskVisuals.checkboxStroke(size: 40))
        XCTAssertGreaterThanOrEqual(MacTaskVisuals.checkboxStroke(size: 12), 1.5,
                                    "Never thinner than a visible hairline")
    }

    /// Row (20) and detail (22) must stay visually consistent — the same ratios drive both.
    func testRowAndDetailShareTheSameProportions() {
        for size in [CGFloat(20), CGFloat(22)] {
            let mark = size * MacTaskVisuals.checkmarkRatio
            XCTAssertGreaterThan(mark, size * 0.7, "Mark should dominate at size \(size)")
            XCTAssertLessThan(MacTaskVisuals.checkboxStroke(size: size), size * 0.12)
        }
    }
}
