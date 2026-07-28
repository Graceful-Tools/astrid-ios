//  MacDetailRevealFadeTests.swift
//  Regression tests for Task 65b81ff8 — "[mac] the task-details shrink animation should fade as it
//  shrinks, and should not slide left of the task row's right border if it didn't start there".
//
//  The pop-out scaled down at full opacity, and the arrow notch — drawn to the LEFT of the panel's
//  own leading edge — kept rendering out there while the panel collapsed.

import XCTest
@testable import Astrid_Mac

final class MacDetailRevealFadeTests: XCTestCase {

    /// Fully open is fully opaque; fully collapsed is fully gone.
    func testFadeSpansTheWholeRange() {
        XCTAssertEqual(MacDetailReveal.fade(progress: 1), 1, accuracy: 0.001)
        XCTAssertEqual(MacDetailReveal.fade(progress: 0), 0, accuracy: 0.001)
    }

    /// It fades AS it shrinks — the panel is already mostly transparent while it is still visibly
    /// collapsing, rather than snapping out at full strength.
    func testMostlyFadedWhileStillShrinking() {
        XCTAssertLessThan(MacDetailReveal.fade(progress: 0.3), 0.5,
                          "At a third of the way closed it should already be more gone than not")
        for p in stride(from: 0.0, through: 1.0, by: 0.1) {
            let f = MacDetailReveal.fade(progress: CGFloat(p))
            XCTAssertGreaterThanOrEqual(f, 0)
            XCTAssertLessThanOrEqual(f, 1)
        }
    }

    func testFadeIsMonotonic() {
        var previous = MacDetailReveal.fade(progress: 0)
        for p in stride(from: 0.05, through: 1.0, by: 0.05) {
            let f = MacDetailReveal.fade(progress: CGFloat(p))
            XCTAssertGreaterThanOrEqual(f, previous, "Opacity must not bounce at \(p)")
            previous = f
        }
    }

    /// The heart of the bug: the panel collapses onto its LEADING edge, so it never travels left
    /// of where it started. A centre anchor would drag it half a panel width across the rows —
    /// exactly the motion being complained about.
    func testCollapseConvergesOnTheLeadingEdge() {
        XCTAssertEqual(MacDetailReveal.collapseAnchorX, 0,
                       "Any other anchor sweeps the panel leftward as it shrinks")
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(MacDetailReveal.leftmostOffset(progress: CGFloat(p), panelWidth: 420), 0,
                           accuracy: 0.001, "The panel moved left of its starting edge at \(p)")
        }
    }

    /// Out-of-range progress (a spring can overshoot) must not produce a wilder overhang or a
    /// negative opacity.
    func testOvershootIsClamped() {
        XCTAssertEqual(MacDetailReveal.fade(progress: 1.2), 1, accuracy: 0.001)
        XCTAssertEqual(MacDetailReveal.fade(progress: -0.2), 0, accuracy: 0.001)
        XCTAssertEqual(MacDetailReveal.leftmostOffset(progress: 1.3, panelWidth: 420), 0, accuracy: 0.001)
        XCTAssertEqual(MacDetailReveal.leftmostOffset(progress: -0.3, panelWidth: 420), 0, accuracy: 0.001)
    }
}
