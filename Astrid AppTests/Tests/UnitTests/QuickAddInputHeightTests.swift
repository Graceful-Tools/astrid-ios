//  QuickAddInputHeightTests.swift
//  Regression tests for Task 5dd9941b-29c8-43f8-95ef-ef8e4635a869 —
//  "[ios] Allow add task input to be taller up to size of screen above keyboard.
//   Currently stops with a max height"
//
//  `QuickAddTaskView` hardcoded `maxHeight = 200`, so a long title stopped
//  growing at roughly eight lines and started scrolling inside itself — while
//  most of the screen above it sat empty. The ceiling should be the space that
//  actually exists: everything between the top safe area and the top of the
//  keyboard, minus the bar's own chrome.

import XCTest
import CoreGraphics
@testable import Astrid_App

final class QuickAddInputHeightTests: XCTestCase {

    /// iPhone 15-ish: 852pt tall, 59pt top inset, keyboard top at 516.
    private let topInset: CGFloat = 59
    private let chrome: CGFloat = 80   // vertical padding + the bar's own trim

    // MARK: - THE BUG: the old ceiling was a constant

    /// With a keyboard up on a modern phone there is well over 200pt of room, so
    /// the input must be allowed past the height it used to stop at.
    func testInputMayGrowPastTheOldHardcodedCeiling() {
        let maxHeight = quickAddMaxInputHeight(keyboardTopY: 516,
                                               topSafeAreaInset: topInset,
                                               barChromeHeight: chrome,
                                               minHeight: 36)
        XCTAssertGreaterThan(maxHeight, 200,
                             "the input stopped at a hardcoded 200pt with the screen half empty")
    }

    /// And it grows to exactly the space above the keyboard — no more (which
    /// would push the bar under the keyboard), no less.
    func testCeilingIsTheSpaceBetweenTheSafeAreaAndTheKeyboard() {
        XCTAssertEqual(quickAddMaxInputHeight(keyboardTopY: 516,
                                              topSafeAreaInset: topInset,
                                              barChromeHeight: chrome,
                                              minHeight: 36),
                       516 - 59 - 80, accuracy: 0.01)
    }

    /// Keyboard down: the whole screen below the safe area is fair game, so the
    /// ceiling grows rather than staying pinned to the keyboard-up value.
    func testCeilingGrowsWhenTheKeyboardIsDismissed() {
        let withKeyboard = quickAddMaxInputHeight(keyboardTopY: 516,
                                                  topSafeAreaInset: topInset,
                                                  barChromeHeight: chrome,
                                                  minHeight: 36)
        let withoutKeyboard = quickAddMaxInputHeight(keyboardTopY: 852,
                                                     topSafeAreaInset: topInset,
                                                     barChromeHeight: chrome,
                                                     minHeight: 36)
        XCTAssertGreaterThan(withoutKeyboard, withKeyboard)
    }

    // MARK: - The field must never collapse

    /// A floating iPad keyboard, a landscape phone, or a transient bad frame can
    /// leave almost no room. The field still has to be usable — never shorter
    /// than one line.
    func testNeverShrinksBelowTheSingleLineMinimum() {
        XCTAssertEqual(quickAddMaxInputHeight(keyboardTopY: 120,
                                              topSafeAreaInset: topInset,
                                              barChromeHeight: chrome,
                                              minHeight: 36),
                       36, accuracy: 0.01)
    }

    /// Keyboard notifications occasionally report an off-screen frame while the
    /// keyboard animates; a negative result must not reach the layout.
    func testNonsenseKeyboardGeometryFallsBackToTheMinimum() {
        XCTAssertEqual(quickAddMaxInputHeight(keyboardTopY: 0,
                                              topSafeAreaInset: topInset,
                                              barChromeHeight: chrome,
                                              minHeight: 36),
                       36, accuracy: 0.01)
        XCTAssertEqual(quickAddMaxInputHeight(keyboardTopY: -400,
                                              topSafeAreaInset: topInset,
                                              barChromeHeight: chrome,
                                              minHeight: 36),
                       36, accuracy: 0.01)
    }

    /// The ceiling is always at least the floor, whatever the inputs.
    func testCeilingIsNeverBelowTheFloor() {
        for keyboardTop in stride(from: CGFloat(-100), through: 1200, by: 37) {
            let value = quickAddMaxInputHeight(keyboardTopY: keyboardTop,
                                               topSafeAreaInset: topInset,
                                               barChromeHeight: chrome,
                                               minHeight: 36)
            XCTAssertGreaterThanOrEqual(value, 36, "keyboardTopY=\(keyboardTop)")
        }
    }
}
