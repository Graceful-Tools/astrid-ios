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

    /// Rounded SQUARES, like iOS. They were 28x22 — a wide rectangle that read as
    /// a different control from the phone's. Squaring them stays inside the
    /// compact bounds above, so the two decisions do not fight.
    func testPriorityButtonsAreSquare() {
        XCTAssertEqual(MacPriorityPicker.buttonWidth, MacPriorityPicker.buttonHeight)
    }
}

// MARK: - Every tap is a selection (task: a6cd1367)

extension MacTaskVisualsTests {

    /// Task a6cd1367 — "tapping on the priority for the first time isn't responsive".
    /// The picker used to report a selection only when the VALUE changed, so tapping the
    /// priority the task already had produced nothing: no save, and the popover stayed
    /// open looking dead. The first tap is exactly the one most likely to land on the
    /// current priority, which is why it read as "the first time".
    func testTapOnTheAlreadySelectedPriorityStillNotifies() {
        for p in MacTaskVisuals.allPriorities {
            XCTAssertTrue(MacPriorityTap.outcome(tapped: p, current: p).notify,
                          "Tapping \(p) while already \(p) must still count as a selection")
        }
    }

    func testTapOnADifferentPriorityNotifiesAndSelectsIt() {
        let outcome = MacPriorityTap.outcome(tapped: .high, current: .none)
        XCTAssertEqual(outcome.selection, .high)
        XCTAssertTrue(outcome.notify)
    }

    /// A tap never resolves to anything but the priority that was tapped.
    func testTapAlwaysSelectsWhatWasTapped() {
        for tapped in MacTaskVisuals.allPriorities {
            for current in MacTaskVisuals.allPriorities {
                XCTAssertEqual(MacPriorityTap.outcome(tapped: tapped, current: current).selection,
                               tapped)
            }
        }
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

    /// The box should sit WITH macOS's 13pt body text, not tower over it.
    func testCheckboxesAreDesktopScale() {
        XCTAssertLessThanOrEqual(MacTaskVisuals.rowCheckboxSize, 18,
                                 "20pt read chunky next to 13pt body text")
        XCTAssertGreaterThanOrEqual(MacTaskVisuals.rowCheckboxSize, 14, "Still a comfortable target")
        XCTAssertGreaterThan(MacTaskVisuals.detailCheckboxSize, MacTaskVisuals.rowCheckboxSize,
                             "The detail's checkbox stays a step larger, as before")
    }

    /// Row and detail must stay visually consistent — the same ratios drive both.
    func testRowAndDetailShareTheSameProportions() {
        for size in [MacTaskVisuals.rowCheckboxSize, MacTaskVisuals.detailCheckboxSize] {
            let mark = size * MacTaskVisuals.checkmarkRatio
            XCTAssertGreaterThan(mark, size * 0.7, "Mark should dominate at size \(size)")
            XCTAssertLessThan(MacTaskVisuals.checkboxStroke(size: size), size * 0.12)
        }
    }
}
