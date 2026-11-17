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

    // MARK: - Priority and assignee are their own rows (task 729a190e)

    /// Each gets its own row — the ask on task 729a190e. The Project layout that kept them behind
    /// the leading control is gone (ADEV-70).
    func testPriorityAndAssigneeAreTheirOwnRows() {
        let rows = MacTaskFields.rows(showsTitle: true)
        XCTAssertTrue(rows.contains(.priority), "list mode shows priority as its own row")
        XCTAssertTrue(rows.contains(.assignee), "list mode shows assignee as its own row")
    }

    /// A board card has no title row but is still a task editor, so it gets the rows too.
    func testTheBoardCardAlsoGetsTheRows() {
        let rows = MacTaskFields.rows(showsTitle: false)
        XCTAssertTrue(rows.contains(.priority))
        XCTAssertTrue(rows.contains(.assignee))
        XCTAssertFalse(rows.contains(.title))
    }

    /// Your own task's detail popover does not offer board state: priority and assignee are rows
    /// of their own there, and so is board state when the task is on a board.
    func testTheDetailPickerDoesNotOfferProjectState() {
        XCTAssertEqual(MacLeadingPicker.sections(),
                       [.priority, .assignee, .complete])
    }

    /// A GitHub board with no Priority field refuses the write, so the popover does not offer
    /// it (AITD-491). Everything else it holds stays.
    func testThePickerLeavesOutPriorityWhenTheListsRefuseIt_AITD491() throws {
        XCTAssertEqual(MacLeadingPicker.sections(surface: .boardCard, refused: [.priority]),
                       [.assignee, .projectState, .complete])
        XCTAssertEqual(MacLeadingPicker.sections(refused: [.priority]),
                       [.assignee, .complete])
        XCTAssertEqual(MacLeadingPicker.sections(refused: [.dueDate]),
                       [.priority, .assignee, .complete])
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacLeadingControlButton.swift")
        XCTAssertTrue(source.contains("TaskCapabilities.refused("),
                      "the control does not ask which controls the task's lists refuse")
    }

    // MARK: - The rows that remain

    /// The detail owns the title; a board card already shows it on the card
    /// face, so it asks for the fields without one.
    func testDetailShowsTitleThenTheSharedOrderThenDescription() {
        XCTAssertEqual(MacTaskFields.rows(showsTitle: true),
                       [.title] + TaskDetailFieldOrder.listMode.map(MacTaskFieldRow.init) + [.description])
    }

    func testBoardCardOmitsTheTitleRow() {
        XCTAssertEqual(MacTaskFields.rows(showsTitle: false),
                       TaskDetailFieldOrder.listMode.map(MacTaskFieldRow.init) + [.description])
    }

    /// And it is DERIVED from the shared list, not a second copy of it — otherwise the two
    /// drift the moment one of them is edited.
    func testTheMacOrderFollowsTheSharedDeclaration() {
        let shared = TaskDetailFieldOrder.listMode.map(MacTaskFieldRow.init)
        XCTAssertEqual(MacTaskFields.rows(showsTitle: false),
                       shared + [.description])
    }

    /// THE BUG: lists must be selectable, not decoration.
    func testTheListsRowIsEditable() {
        XCTAssertTrue(MacTaskFields.isEditable(.lists),
                      "the Lists row drew chips and a dash with no way to change them")
    }

    /// In BOTH modes. A row that is shown and cannot be changed is the exact failure the
    /// Lists row had, and list mode adds two rows that would be easy to ship read-only.
    func testEveryFieldRowIsEditable() {
        do {
            for row in MacTaskFields.rows(showsTitle: true) {
                XCTAssertTrue(MacTaskFields.isEditable(row),
                              "\(row) is shown and must be changeable there")
            }
        }
    }

    // MARK: - Task ID in the header, not a row (AITD-647 on iOS, ADEV-60 on Mac)

    /// iOS moved the id into the header ("<id> Details") and dropped its row; the Mac kept both
    /// "Task Details" and a Task ID row until the design review found it (ADEV-60).
    func testNoTaskIdRow_ADEV60() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacTaskFields.swift")
        XCTAssertFalse(source.contains("case taskId"), "the id is the header's, not a field row")
    }

    func testTheHeaderTitleCarriesTheIdAsOnIOS_ADEV60() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacTaskDetailView.swift")
        XCTAssertTrue(source.contains("TaskDetailHeader.title(identifier:"), "iOS's shared title rule")
        XCTAssertTrue(source.contains("taskDetail.header.identifier"), "the id copies, as on iOS")
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
        do {
            let board = Set(MacTaskFields.rows(showsTitle: false))
            let detail = Set(MacTaskFields.rows(showsTitle: true))
            XCTAssertTrue(board.isSubset(of: detail),
                          "the board must render a subset of the detail's fields, not its own set")
            XCTAssertEqual(detail.subtracting(board), [.title])
        }
    }

    /// The board card is a column, not a panel, so it renders denser — but the
    /// density is a parameter of the shared view, not a second implementation.
    func testBoardCardIsDenserThanTheDetailPanel() {
        XCTAssertLessThan(MacTaskFields.Density.boardCard.rowSpacing,
                          MacTaskFields.Density.detail.rowSpacing)
    }
}

/// A GitHub board with no Priority or date field mapped refuses those writes (AITD-491), so the
/// editor does not offer them.
final class MacTaskFieldsCapabilitiesTests: XCTestCase {
    func testARefusedFieldIsNotARow_AITD491() {
        let list = MacTaskFields.rows(showsTitle: true, refused: [.priority, .dueDate])
        XCTAssertFalse(list.contains(.priority))
        XCTAssertFalse(list.contains(.when))
        XCTAssertTrue(list.contains(.lists))
        let dateOnly = MacTaskFields.rows(showsTitle: true, refused: [.dueDate])
        XCTAssertFalse(dateOnly.contains(.when))
        XCTAssertTrue(dateOnly.contains(.priority))
        XCTAssertEqual(MacTaskFields.rows(showsTitle: true, refused: []),
                       MacTaskFields.rows(showsTitle: true))
    }

    /// `refused` also carries controls this editor has no row for. Folding one of those into
    /// `.when` — which "priority, else .when" did — hid the date row on a board that takes dates.
    func testAControlWithNoRowHidesNothing_AITD491() {
        let all = MacTaskFields.rows(showsTitle: true)
        XCTAssertEqual(MacTaskFields.rows(showsTitle: true, refused: [.privateTasks]), all)
        let priorityOnly = MacTaskFields.rows(showsTitle: true,
                                              refused: [.priority, .privateTasks])
        XCTAssertFalse(priorityOnly.contains(.priority))
        XCTAssertTrue(priorityOnly.contains(.when), "a refused private task hid the date row")
        // The popover is unchanged by a control it does not offer either.
        XCTAssertEqual(MacLeadingPicker.sections(refused: [.privateTasks]),
                       MacLeadingPicker.sections())
    }

    /// The Mac list editor stops offering a default the list refuses (AITD-491).
    func testTheMacListEditorAsksTheRule_AITD491() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacListEditSheet.swift")
        XCTAssertTrue(source.contains("TaskCapabilities.allows(.priority"),
                      "the Mac list editor still offers a default priority a board refuses")
        XCTAssertTrue(source.contains("TaskCapabilities.allows(.dueDate"),
                      "the Mac list editor still offers a default due date a board refuses")
    }
}
