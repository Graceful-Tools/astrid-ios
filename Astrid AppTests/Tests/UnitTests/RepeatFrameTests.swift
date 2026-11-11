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

    /// AITD-612 (reopened 2026-11-11) — "Still see smaller checkbox for repeating tasks assigned to
    /// a person or agent when repeating. We need to redraw or use a larger box. The same size as
    /// the default profile photo." The first fix made the arrows the square's size but shrank the
    /// photo inside them to 0.625 × (21pt in a 34pt slot), so on the iPad board a repeating
    /// task's face was visibly smaller than the face on the non-repeating row below it. Now the
    /// photo or "U" fills the whole square, exactly as the non-repeating mark does, and the
    /// arrows are drawn AS its border in place of the plain priority outline.
    func testPhotoIsTheSameSizeAsTheNonRepeatingPhoto() {
        XCTAssertEqual(RepeatFrameGeometry.footprint, 34)
        for control: CGFloat in [34, 32, 22, 18] {
            XCTAssertEqual(RepeatFrameGeometry.innerSize(control: control), control, accuracy: 0.001,
                           "a repeating \(control)pt mark's photo is as big as the plain \(control)pt photo")
            XCTAssertEqual(RepeatFrameGeometry.frameSize(control: control), control, accuracy: 0.001,
                           "the arrows border the photo at the square's own size, no bigger")
        }
        XCTAssertEqual(RepeatFrameGeometry.innerSize(control: 34), 34, accuracy: 0.001,
                       "the iOS photo is 34pt, not 21.25")
        // The same rounded square the non-repeating photo is clipped to (cornerRadius 8 at 34pt).
        XCTAssertEqual(RepeatFrameGeometry.cornerRadius(control: 34), 8, accuracy: 0.001)
    }

    /// The redrawn arrows still read as the repeat mark: each arrowhead stops short of the
    /// opposite bracket's corner, so there is a visible gap on the top and bottom edges.
    func testArrowheadsLeaveAGapBeforeTheCorner() {
        for control: CGFloat in [34, 22, 18] {
            let tip = control * (0.5 + RepeatFrameGeometry.headLength)
            let corner = control - RepeatFrameGeometry.cornerRadius(control: control)
            XCTAssertLessThan(tip, corner - control * 0.05, "\(control)pt: a gap between arrowhead and bracket")
        }
    }
}
