//  ReducedMotionTests.swift
//  AITD-624: with Reduce Motion on, nothing springs or pops.

import SwiftUI
import XCTest
@testable import Astrid_App

final class ReducedMotionTests: XCTestCase {
    func testAITD624_springIsNoAnimationUnderReduceMotion() {
        XCTAssertNil(ReducedMotion.spring(response: 0.25, dampingFraction: 0.85, reduceMotion: true))
        XCTAssertNil(ReducedMotion.spring(reduceMotion: true))
        XCTAssertNil(ReducedMotion.drawerSpring(reduceMotion: true))
    }

    func testAITD624_springAnimatesWhenReduceMotionIsOff() {
        XCTAssertEqual(ReducedMotion.spring(response: 0.25, dampingFraction: 0.85, reduceMotion: false),
                       .spring(response: 0.25, dampingFraction: 0.85))
        XCTAssertEqual(ReducedMotion.drawerSpring(reduceMotion: false),
                       .spring(response: AstridTokens.Motion.drawerSpringDuration,
                               dampingFraction: AstridTokens.Motion.drawerSpringDamping))
    }

    func testAITD624_popIsSuppressedUnderReduceMotion() {
        XCTAssertFalse(ReducedMotion.allowsPop(reduceMotion: true))
        XCTAssertTrue(ReducedMotion.allowsPop(reduceMotion: false))
    }
}
