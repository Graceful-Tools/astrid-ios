//  RepeatFrameTests.swift
//  Regression tests for AITD-602 — "make the checkbox border around faces and unassigned the
//  rotating arrow just like assigned to you … for other users it should be larger and the border
//  around the profile photo". Web shipped the same thing in AWTD-1571.
//
//  Your own repeating task already swapped its checkbox for the arrows; someone else's photo and
//  the "U" mark drew the plain priority square, so "this repeats" showed on one mark in three.

import XCTest
@testable import Astrid_App

final class RepeatFrameTests: XCTestCase {

    /// THE BUG: a repeating task assigned to someone else, or to nobody, gets the arrows frame.
    func testRepeatingAvatarAndUnassignedAreFramed() {
        for repeating in [Task.Repeating.daily, .weekly, .monthly, .yearly, .custom] {
            XCTAssertTrue(TaskLeadingControl.showsRepeatFrame(kind: .avatar("someone"), repeating: repeating),
                          "\(repeating): another person's photo sits inside the repeat arrows")
            XCTAssertTrue(TaskLeadingControl.showsRepeatFrame(kind: .unassigned, repeating: repeating),
                          "\(repeating): the U mark sits inside the repeat arrows")
        }
    }

    /// A task that does not repeat keeps the plain priority square.
    func testNonRepeatingKeepsTheSquare() {
        for repeating in [Task.Repeating?.none, .some(.never)] {
            XCTAssertFalse(TaskLeadingControl.showsRepeatFrame(kind: .avatar("someone"), repeating: repeating))
            XCTAssertFalse(TaskLeadingControl.showsRepeatFrame(kind: .unassigned, repeating: repeating))
        }
    }

    /// The checkbox already IS the arrows (`check_box_repeat_<p>`); framing it would draw them twice.
    func testCheckboxIsNeverFramed() {
        XCTAssertFalse(TaskLeadingControl.showsRepeatFrame(kind: .checkbox, repeating: .daily))
    }

    /// AITD-612 — "Repeat checkboxes with assignment should be same side [size] as non repeat on
    /// all platforms" (Jon confirmed "size", 2026-11-11). The arrows round someone else's photo or
    /// the "U" were 1.25 × the square (AITD-606) — 42.5pt round a 34pt square — so a repeating
    /// row's mark was bigger than the plain squares beside it and stuck out of the column. Web has
    /// drawn them at the checkbox's own 32px, with a 20px photo, since AWTD-1576; astrid-core's
    /// `size.repeat-frame-scale` is now 1.0 and `size.repeat-frame-inner-scale` 0.625.
    func testFrameIsTheSameSizeAsTheSquareItReplaces() {
        XCTAssertEqual(RepeatFrameGeometry.scale, 1.0)
        XCTAssertEqual(RepeatFrameGeometry.footprint, 34)
        // 34 iOS; 32 web; the Mac's row and detail sizes.
        for control: CGFloat in [34, 32, 22, 18] {
            XCTAssertEqual(RepeatFrameGeometry.frameSize(control: control), control, accuracy: 0.001,
                           "a \(control)pt square is replaced by \(control)pt arrows, no bigger")
            // Web's 20px photo inside its 32px arrows.
            XCTAssertEqual(RepeatFrameGeometry.innerSize(control: control), control * 20.0 / 32.0, accuracy: 0.001,
                           "the photo or U fits inside the loop")
        }
        XCTAssertEqual(RepeatFrameGeometry.frameSize(control: 34), 34, accuracy: 0.001,
                       "the iOS row and detail frame is 34pt, not 42.5")
    }

    /// The frame is the priority-coloured repeat art the checkbox already uses.
    func testFrameUsesThePriorityRepeatAsset() {
        XCTAssertEqual(RepeatFrameGeometry.assetName(priority: .none), "check_box_repeat_0")
        XCTAssertEqual(RepeatFrameGeometry.assetName(priority: .high), "check_box_repeat_3")
    }
}
