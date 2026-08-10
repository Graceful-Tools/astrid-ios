//  MacScaledLayoutTests.swift
//  Task 010a7826 — "[Mac] calendar is overlayed on buttons. It should display below buttons".
//
//  `scaleEffect` does not change layout, so a scaled calendar has to have room reserved for
//  it explicitly. `MacScaled` measures its child and reserves scale × that — but the measured
//  size starts at ZERO, and a popover sizes itself on the first layout pass. On that pass the
//  calendar reserved nothing, so the popover was built too short and the calendar drew outside
//  its bounds. Scaling about the centre sent that overflow upward, over the buttons.

import XCTest
import CoreGraphics
import SwiftUI
@testable import Astrid_Mac

final class MacScaledLayoutTests: XCTestCase {

    private let fallback = CGSize(width: 200, height: 260)

    /// The regression: before the child has been measured, the reservation must NOT be zero.
    func testAnUnmeasuredChildStillReservesRoom() {
        let reserved = MacScaledLayout.reserved(natural: .zero, scale: 1.5, fallback: fallback)
        XCTAssertGreaterThan(reserved.height, 0,
                             "Task 010a7826: reserving nothing lets the scaled calendar draw over the buttons")
        XCTAssertGreaterThan(reserved.width, 0)
    }

    /// The estimate has to account for the scale too, or the first pass is still short.
    func testTheFallbackIsScaledLikeAMeasuredChildWouldBe() {
        XCTAssertEqual(MacScaledLayout.reserved(natural: .zero, scale: 1.5, fallback: fallback),
                       CGSize(width: 300, height: 390))
    }

    /// Once measured, the real size wins — the estimate is only for the first pass.
    func testAMeasuredChildReplacesTheEstimate() {
        let natural = CGSize(width: 120, height: 140)
        XCTAssertEqual(MacScaledLayout.reserved(natural: natural, scale: 2, fallback: fallback),
                       CGSize(width: 240, height: 280))
    }

    func testAnUnscaledChildReservesExactlyItsOwnSize() {
        let natural = CGSize(width: 120, height: 140)
        XCTAssertEqual(MacScaledLayout.reserved(natural: natural, scale: 1, fallback: fallback), natural)
    }

    /// A partially-measured child (one axis still zero) must fall back on that axis alone,
    /// not throw the other one away.
    func testEachAxisFallsBackIndependently() {
        let half = CGSize(width: 120, height: 0)
        let reserved = MacScaledLayout.reserved(natural: half, scale: 2, fallback: fallback)
        XCTAssertEqual(reserved.width, 240, "The measured axis is used")
        XCTAssertEqual(reserved.height, 520, "The unmeasured axis falls back")
    }

    /// Scaling anchors to the TOP, so any residual overflow goes downward — away from the
    /// buttons above, which is the whole complaint in the task.
    func testScalingAnchorsToTheTopSoOverflowNeverGoesUpwards() {
        XCTAssertEqual(MacScaledLayout.anchor, .top)
    }
}
