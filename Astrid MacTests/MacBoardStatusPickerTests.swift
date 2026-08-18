//  MacBoardStatusPickerTests.swift
//  Regression guard for Task f9d7ed42 — "[mac] In List mode, not part of a board, tapping the
//  checkbox should complete the task. In board view, it should bring up a 'status' picker".
//
//  The leading control asked ONE question — which Appearance mode is this? — and a mode cannot
//  tell a board card from a list row. So `list` mode, whose whole point is that the checkbox
//  finishes the task, handed that behaviour to the board as well: a card's checkbox completed
//  outright, which is precisely the trapdoor task 9be8cb1b removed from the board. And the
//  popover it did offer in list mode carried no board state, so on the one surface where a
//  task HAS a status there was no way to set it.
//
//  The fix is to ask the surface too. These tests pin both halves of the title, because they
//  are one rule seen from two sides: a list row completes, a board card picks a status.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardStatusPickerTests: XCTestCase {

    // MARK: - "In board view, it should bring up a 'status' picker"

    /// The bug, in one line: in list mode a card's checkbox finished the task.
    func testBoardCardOpensThePickerInListMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .boardCard, kind: .checkbox, displayMode: .list),
            .openPicker,
            "A board card's checkbox must open the picker, not complete the task outright")
    }

    /// And in project mode, which already behaved — the guard has to hold for both, or the
    /// rule is only half written.
    func testBoardCardOpensThePickerInProjectMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .boardCard, kind: .checkbox, displayMode: .project),
            .openPicker)
    }

    /// The unassigned mark and someone else's photo are the same control wearing a different
    /// face. A card is a card whichever face it shows.
    func testEveryFaceOnACardOpensThePicker() {
        for kind: TaskLeadingControl in [.checkbox, .unassigned, .avatar("someone-else")] {
            for mode in TaskDisplayMode.allCases {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: .boardCard, kind: kind, displayMode: mode),
                    .openPicker,
                    "\(kind) in \(mode) must open the picker on a board card")
            }
        }
    }

    /// A "status picker" that lists no statuses is not one. The board column section is what
    /// makes the popover answer the ask, so it must be there in BOTH modes on a card — list
    /// mode omits it in the detail panel on purpose, and that omission leaked onto the board.
    func testTheBoardCardPickerOffersStatusesInBothModes() {
        for mode in TaskDisplayMode.allCases {
            XCTAssertTrue(
                MacLeadingPicker.sections(for: mode, surface: .boardCard).contains(.projectState),
                "A board card's picker must offer the board's statuses in \(mode)")
        }
    }

    /// Completing does not disappear when the picker gains statuses — it stays an explicit
    /// action in the popover, which is the whole reason taking it off the click is safe.
    func testTheBoardCardPickerStillOffersCompletion() {
        for mode in TaskDisplayMode.allCases {
            XCTAssertTrue(MacLeadingPicker.sections(for: mode, surface: .boardCard).contains(.complete),
                          "\(mode)")
        }
    }

    // MARK: - "In List mode, not part of a board, tapping the checkbox should complete the task"

    func testListRowCheckboxCompletesInListMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, displayMode: .list),
            .complete,
            "In list mode a row's checkbox completes the task — that is what a checkbox means")
    }

    /// Project mode still turns the row's control into the quick changer everywhere, which is
    /// what task 132d7b3f asked for. This task narrows the board, not the row.
    func testListRowOpensTheQuickChangerInProjectMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, displayMode: .project),
            .openPicker)
    }

    // MARK: - The detail panel is untouched

    /// Its extra condition survives: someone else's photo is not a checkbox, so clicking it
    /// opens the picker rather than finishing their task (task 729a190e).
    func testDetailKeepsItsOwnRule() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, displayMode: .list),
            .complete)
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .avatar("someone-else"), displayMode: .list),
            .openPicker)
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, displayMode: .project),
            .openPicker)
    }

    /// The detail panel's list-mode popover still leaves board state out — a board column is a
    /// project idea, and offering it in the list layout is the hybrid the setting exists to end.
    func testTheDetailPickerStillOmitsStatusesInListMode() {
        XCTAssertFalse(MacLeadingPicker.sections(for: .list, surface: .detail).contains(.projectState))
    }
}
#endif
