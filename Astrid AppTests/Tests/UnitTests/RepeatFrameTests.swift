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

    /// "For other users it should be larger": the arrows are drawn bigger than the 34pt square,
    /// the photo sits inside the loop, and the slot the row lays out stays 34pt so titles still line up.
    func testFrameIsLargerThanTheSquareAndHoldsThePhoto() {
        XCTAssertGreaterThan(RepeatFrameGeometry.frameSize, RepeatFrameGeometry.footprint)
        XCTAssertLessThan(RepeatFrameGeometry.innerSize, RepeatFrameGeometry.footprint)
        XCTAssertEqual(RepeatFrameGeometry.footprint, 34)
        // Web draws a 24px photo in a 40px loop; the same proportion here.
        XCTAssertEqual(RepeatFrameGeometry.innerSize / RepeatFrameGeometry.frameSize, 24.0 / 40.0, accuracy: 0.01)
    }

    /// The frame is the priority-coloured repeat art the checkbox already uses.
    func testFrameUsesThePriorityRepeatAsset() {
        XCTAssertEqual(RepeatFrameGeometry.assetName(priority: .none), "check_box_repeat_0")
        XCTAssertEqual(RepeatFrameGeometry.assetName(priority: .high), "check_box_repeat_3")
    }
}
