//  MacTaskFieldsTests.swift
//  The Mac task detail's field block, and the fact that the board reuses it.
//
//  Three things this pins, all reported against the shipped build:
//
//  1. Priority and assignee had their own row, restating what the leading
//     control already depicts. iOS put both behind that control — tap the
//     checkbox/photo, set either — and dropped the row. The Mac now does too.
//  2. The Lists row was READ-ONLY. It drew chips from the task and "—" when
//     there were none, with no control to change anything: "list selecting
//     isn't working on the Mac" because there was nothing to select with.
//  3. MacBoardCardEditor was a 214-line parallel implementation of the same
//     fields — its own labels, its own Who picker, and the date TOGGLE that the
//     detail had already replaced. Both now render one view, so the board
//     cannot drift behind the detail again.

import XCTest
@testable import Astrid_Mac

final class MacTaskFieldsTests: XCTestCase {

    // MARK: - Priority and assignee moved behind the leading control

    /// THE ASK: no standalone priority row. The leading control already shows
    /// priority (its colour) and assignee (its photo); a row repeating both was
    /// spending panel width to say it twice.
    func testPriorityIsNotAFieldRow() {
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true).contains(.priority))
        XCTAssertFalse(MacTaskFields.rows(showsTitle: false).contains(.priority))
    }

    func testAssigneeIsNotAFieldRow() {
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true).contains(.assignee))
    }

    /// Both live behind the leading control instead, with completion — exactly
    /// the three things iOS put there.
    func testLeadingControlOffersPriorityAssigneeAndCompletion() {
        XCTAssertEqual(MacLeadingPicker.sections, [.priority, .assignee, .complete])
    }

    // MARK: - The rows that remain

    /// The detail owns the title; a board card already shows it on the card
    /// face, so it asks for the fields without one.
    func testDetailShowsTitleThenWhenThenListsThenDescription() {
        XCTAssertEqual(MacTaskFields.rows(showsTitle: true),
                       [.title, .when, .lists, .description])
    }

    func testBoardCardOmitsTheTitleRow() {
        XCTAssertEqual(MacTaskFields.rows(showsTitle: false),
                       [.when, .lists, .description])
    }

    /// THE BUG: lists must be selectable, not decoration.
    func testTheListsRowIsEditable() {
        XCTAssertTrue(MacTaskFields.isEditable(.lists),
                      "the Lists row drew chips and a dash with no way to change them")
    }

    func testEveryFieldRowIsEditable() {
        for row in MacTaskFields.rows(showsTitle: true) {
            XCTAssertTrue(MacTaskFields.isEditable(row),
                          "\(row) is a field the user must be able to change")
        }
    }

    // MARK: - Toggling a list membership

    /// Picking a list the task is not in adds it; picking one it is in removes
    /// it. Multi-select, because a task can live in several lists.
    func testPickingAnUnselectedListAddsIt() {
        XCTAssertEqual(MacTaskFields.toggling(listId: "b", in: ["a"]), ["a", "b"])
    }

    func testPickingASelectedListRemovesIt() {
        XCTAssertEqual(MacTaskFields.toggling(listId: "a", in: ["a", "b"]), ["b"])
    }

    /// Order is preserved on add — the list chips should not reshuffle because
    /// you added a third one.
    func testTogglingPreservesTheExistingOrder() {
        XCTAssertEqual(MacTaskFields.toggling(listId: "c", in: ["a", "b"]), ["a", "b", "c"])
    }

    /// A task may end up in no lists at all (My Tasks only); that is a legal
    /// state, not something to block.
    func testRemovingTheLastListIsAllowed() {
        XCTAssertEqual(MacTaskFields.toggling(listId: "a", in: ["a"]), [])
    }

    /// The same id twice must not double-add — list membership is a set even
    /// though it is carried as an array.
    func testTogglingIsIdempotentPerId() {
        let once = MacTaskFields.toggling(listId: "b", in: ["a"])
        let twice = MacTaskFields.toggling(listId: "b", in: once)
        XCTAssertEqual(twice, ["a"])
    }

    // MARK: - The board reuses the detail's fields

    /// THE ASK: one implementation. The board card asks for the same field set,
    /// minus the title it already draws — it does not get its own list of rows.
    func testBoardAndDetailShareOneFieldSet() {
        let board = Set(MacTaskFields.rows(showsTitle: false))
        let detail = Set(MacTaskFields.rows(showsTitle: true))
        XCTAssertTrue(board.isSubset(of: detail),
                      "the board must render a subset of the detail's fields, not its own set")
        XCTAssertEqual(detail.subtracting(board), [.title])
    }

    /// The board card is a column, not a panel, so it renders denser — but the
    /// density is a parameter of the shared view, not a second implementation.
    func testBoardCardIsDenserThanTheDetailPanel() {
        XCTAssertLessThan(MacTaskFields.Density.boardCard.rowSpacing,
                          MacTaskFields.Density.detail.rowSpacing)
    }
}
