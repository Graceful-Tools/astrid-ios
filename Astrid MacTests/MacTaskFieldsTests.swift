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

    // MARK: - Priority and assignee: behind the control, or their own rows (task 729a190e)

    /// PROJECT mode keeps them behind the leading control. This was the whole of task
    /// 42013da7: the control already shows priority (its colour) and assignee (its photo),
    /// and a row repeating both spent panel width saying it twice.
    ///
    /// It was unconditional, which is the bug — it made project mode's layout the only
    /// layout, so choosing "list" in Appearance changed nothing.
    func testPriorityIsNotAFieldRowInProjectMode() {
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true, displayMode: .project).contains(.priority))
        XCTAssertFalse(MacTaskFields.rows(showsTitle: false, displayMode: .project).contains(.priority))
    }

    func testAssigneeIsNotAFieldRowInProjectMode() {
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true, displayMode: .project).contains(.assignee))
    }

    /// LIST mode gives each its own row — the ask on task 729a190e, and what the mode has
    /// promised in its own documentation since it was added.
    func testPriorityAndAssigneeAreTheirOwnRowsInListMode() {
        let rows = MacTaskFields.rows(showsTitle: true, displayMode: .list)
        XCTAssertTrue(rows.contains(.priority), "list mode shows priority as its own row")
        XCTAssertTrue(rows.contains(.assignee), "list mode shows assignee as its own row")
    }

    /// A board card has no title row but is still a task editor, so the mode applies there too.
    func testTheBoardCardAlsoGetsTheRowsInListMode() {
        let rows = MacTaskFields.rows(showsTitle: false, displayMode: .list)
        XCTAssertTrue(rows.contains(.priority))
        XCTAssertTrue(rows.contains(.assignee))
        XCTAssertFalse(rows.contains(.title))
    }

    /// PROJECT mode's popover carries board state as well — the third thing task 729a190e
    /// asks the quick changer to hold, alongside priority and assignee.
    func testTheProjectQuickChangerOffersPriorityAssigneeProjectStateAndCompletion() {
        XCTAssertEqual(MacLeadingPicker.sections(for: .project),
                       [.priority, .assignee, .projectState, .complete])
    }

    /// LIST mode does not: priority and assignee are rows of their own there, and a task's
    /// board state is a project idea. Offering it in both would rebuild the hybrid layout
    /// this setting exists to end.
    func testTheListModePickerDoesNotOfferProjectState() {
        XCTAssertEqual(MacLeadingPicker.sections(for: .list),
                       [.priority, .assignee, .complete])
    }

    // MARK: - The rows that remain

    /// The detail owns the title; a board card already shows it on the card
    /// face, so it asks for the fields without one.
    func testDetailShowsTitleThenWhenThenListsThenDescription() {
        XCTAssertEqual(MacTaskFields.rows(showsTitle: true, displayMode: .project),
                       [.title, .when, .lists, .description])
    }

    func testBoardCardOmitsTheTitleRow() {
        XCTAssertEqual(MacTaskFields.rows(showsTitle: false, displayMode: .project),
                       [.when, .lists, .description])
    }

    /// Order matters, and it is now WHO, DATE, PRIORITY, LISTS (task c8a1ff51).
    ///
    /// This used to pin `[.priority, .assignee, .when, .lists]` — priority first, assignee
    /// second — and iOS independently used the same order. The same mistake twice, which is
    /// what two views deciding for themselves produces. The order is stated once now, in
    /// `TaskDetailFieldOrder.listMode`, because the ask was continuity across the phone, the
    /// Mac and web. The test is rewritten to the new rule rather than deleted: a test that
    /// disappears when its subject changes takes the record with it.
    func testListModeOrderIsWhoDatePriorityLists() {
        XCTAssertEqual(MacTaskFields.rows(showsTitle: true, displayMode: .list),
                       [.title, .assignee, .when, .priority, .lists, .description])
    }

    /// And it is DERIVED from the shared list, not a second copy of it — otherwise the two
    /// drift the moment one of them is edited.
    func testTheMacOrderFollowsTheSharedDeclaration() {
        let shared = TaskDetailFieldOrder.listMode.map(MacTaskFieldRow.init)
        XCTAssertEqual(MacTaskFields.rows(showsTitle: false, displayMode: .list),
                       shared + [.description])
    }

    /// THE BUG: lists must be selectable, not decoration.
    func testTheListsRowIsEditable() {
        XCTAssertTrue(MacTaskFields.isEditable(.lists),
                      "the Lists row drew chips and a dash with no way to change them")
    }

    /// In BOTH modes. A row that is shown and cannot be changed is the exact failure the
    /// Lists row had, and list mode adds two rows that would be easy to ship read-only.
    func testEveryFieldRowIsEditableInEveryMode() {
        for mode in TaskDisplayMode.allCases {
            for row in MacTaskFields.rows(showsTitle: true, displayMode: mode) {
                XCTAssertTrue(MacTaskFields.isEditable(row),
                              "\(row) is shown in \(mode) and must be changeable there")
            }
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

    // MARK: - The description reads as text until you click it

    /// A real description renders as text.
    func testDescriptionWithContentShowsThatContent() {
        XCTAssertEqual(MacTaskFields.descriptionDisplay("Ship it"), .body("Ship it"))
    }

    /// Empty falls back to the prompt — otherwise the row is a blank clickable
    /// gap with nothing saying what it is.
    func testEmptyDescriptionShowsThePrompt() {
        XCTAssertEqual(MacTaskFields.descriptionDisplay(""), .placeholder)
    }

    /// THE TRAP: whitespace is not content. A description of spaces and newlines
    /// would render as an invisible body and lose the prompt entirely.
    func testWhitespaceOnlyDescriptionShowsThePrompt() {
        XCTAssertEqual(MacTaskFields.descriptionDisplay("   \n  \t "), .placeholder)
    }

    /// Content is shown verbatim, not trimmed — the user's leading indent is
    /// theirs to keep; trimming is only how we DECIDE which state to show.
    func testDescriptionContentIsNotRewritten() {
        XCTAssertEqual(MacTaskFields.descriptionDisplay("  indented"), .body("  indented"))
    }

    // MARK: - Chip spacing

    /// THE BUG: the gap between the date and time chips was wide enough to read
    /// as a gulf, and it cost the row width it did not have — enough to wrap a
    /// chip that would otherwise have fitted.
    func testChipsSitCloseEnoughNotToForceAWrap() {
        XCTAssertLessThanOrEqual(MacTaskFields.chipSpacing, 6,
                                 "a wide gap between chips buys nothing and costs a wrap")
        XCTAssertGreaterThan(MacTaskFields.chipSpacing, 0, "the chips still need separating")
    }

    /// The row is denser than the gap BETWEEN rows — chips on one line belong
    /// together more than lines do.
    func testChipsAreTighterThanTheRowsAreApart() {
        XCTAssertLessThan(MacTaskFields.chipSpacing, MacTaskFields.Density.detail.rowSpacing)
    }

    // MARK: - The board reuses the detail's fields

    /// THE ASK: one implementation. The board card asks for the same field set,
    /// minus the title it already draws — it does not get its own list of rows.
    /// In EVERY mode — list mode adds two rows, and adding them to only one of the two
    /// surfaces is exactly the drift this test exists to catch.
    func testBoardAndDetailShareOneFieldSet() {
        for mode in TaskDisplayMode.allCases {
            let board = Set(MacTaskFields.rows(showsTitle: false, displayMode: mode))
            let detail = Set(MacTaskFields.rows(showsTitle: true, displayMode: mode))
            XCTAssertTrue(board.isSubset(of: detail),
                          "the board must render a subset of the detail's fields, not its own set")
            XCTAssertEqual(detail.subtracting(board), [.title], "\(mode)")
        }
    }

    /// The board card is a column, not a panel, so it renders denser — but the
    /// density is a parameter of the shared view, not a second implementation.
    func testBoardCardIsDenserThanTheDetailPanel() {
        XCTAssertLessThan(MacTaskFields.Density.boardCard.rowSpacing,
                          MacTaskFields.Density.detail.rowSpacing)
    }
}
