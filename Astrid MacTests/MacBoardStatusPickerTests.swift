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

    // MARK: - The detail panel is untouched

    /// The detail panel's list-mode popover still leaves board state out for YOUR OWN task — a
    /// board column is a project idea, and offering it in the list layout is the hybrid the
    /// setting exists to end.
    func testTheDetailPickerStillOmitsStatusesInListMode() {
        XCTAssertFalse(MacLeadingPicker.sections(for: .list, surface: .detail).contains(.projectState))
    }

    /// Someone else's task gets the full project-mode set, on the Mac as on the phone
    /// (AITD-375): when the popover is the only thing a click gives you, it carries everything.
    func testSomeoneElsesTaskGetsBoardStateEvenInListMode() {
        XCTAssertEqual(
            MacLeadingPicker.sections(for: .list, surface: .detail, isSomeoneElses: true),
            [.priority, .assignee, .projectState, .complete])
    }
}
#endif
