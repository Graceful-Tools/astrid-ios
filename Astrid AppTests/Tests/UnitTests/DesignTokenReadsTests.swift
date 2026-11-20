//  DesignTokenReadsTests.swift
//  Regression guard for ADEV-163 — "[design] iOS and Mac read the tokens they already vendor:
//  radii, selection outline, motion, and the completion pop on iOS" (register DS5, DS15, DS16).
//
//  `AstridTokens.swift` was current with core, but the values were typed out next to it, so the
//  reference client could drift from its own tokens. These pin each helper to the token it reads.

import SwiftUI
import XCTest
@testable import Astrid_App

final class DesignTokenReadsTests: XCTestCase {

    /// DS5: the selection outline is the accent at `state.selection-outline-opacity` (55%), not
    /// solid accent.
    func testADEV163_selectionOutlineIsTheAccentAtTheTokenOpacity() {
        XCTAssertEqual(DetailPanelChrome.selectionOutlineOpacity, AstridTokens.State.selectionOutlineOpacity)
        XCTAssertEqual(DetailPanelChrome.selectionOutlineColor,
                       Color.accentColor.opacity(AstridTokens.State.selectionOutlineOpacity))
        XCTAssertEqual(DetailPanelChrome.selectionOutlineWidth, AstridTokens.Size.Comfortable.selectionOutline)
    }

    /// DS15: the panel and arrow durations are the motion tokens, not copies of them.
    func testADEV163_panelMotionReadsTheTokens() {
        XCTAssertEqual(DetailPanelChrome.panelDuration, AstridTokens.Motion.panelDuration)
        XCTAssertEqual(DetailPanelChrome.arrowFollowDuration, AstridTokens.Motion.fastDuration)
    }

    /// DS15: `motion.spring` and `motion.hover`, through the one place Reduce Motion is decided.
    func testADEV163_namedSpringAndHoverReadTheTokens() {
        XCTAssertEqual(ReducedMotion.standardSpring(reduceMotion: false),
                       .spring(response: AstridTokens.Motion.springDuration,
                               dampingFraction: AstridTokens.Motion.springDamping))
        XCTAssertNil(ReducedMotion.standardSpring(reduceMotion: true))
        XCTAssertEqual(ReducedMotion.hover, .easeOut(duration: AstridTokens.Motion.hoverDuration))
    }

    /// DS16: the checkbox pop is `state.complete-pop-scale` on both targets; at rest, no scale.
    func testADEV163_completionPopIsTheTokenScale() {
        XCTAssertEqual(Double(ReducedMotion.popScale(true)), AstridTokens.State.completePopScale)
        XCTAssertEqual(ReducedMotion.popScale(false), 1)
    }
}
