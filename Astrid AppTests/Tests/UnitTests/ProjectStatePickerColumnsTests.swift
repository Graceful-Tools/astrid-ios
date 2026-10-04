//  ProjectStatePickerColumnsTests.swift
//  Regression guard for Task 7574067b — "In the Project State Picker remove the 'Done' button.
//  And rename Make as complete. To 'Complete / Done!'"
//
//  The picker listed whatever `getProjectBoardColumns` returned, and that always ends with a
//  virtual Done column. On a BOARD, Done is a place you drag a card to. In the quick changer it
//  sat one row above an explicit Complete button that does exactly the same thing — so the
//  popover offered the same action twice, and the chip version was the one that gave no hint it
//  would finish the task.
//
//  The board keeps Done. Only the picker drops it — since AITD-461 in astrid-core's
//  `taskStatusOptions` (CONTRACTS D46), which both the iOS and Mac pickers read, so they cannot
//  disagree about what "the states you can pick" means.

import XCTest
@testable import Astrid_App

final class ProjectStatePickerColumnsTests: XCTestCase {

    private var allColumns: [ProjectBoardColumn] { CoreBoardFixture.columns([]) }

    // MARK: - The ask

    /// THE BUG: Done was one of the chips.
    func testThePickerDoesNotOfferDone() {
        let offered = CoreBoardFixture.pickerColumns()
        XCTAssertFalse(offered.contains { $0.kind == .done },
                       "Done is what the Complete button is for — a chip that silently "
                       + "completes the task is the trapdoor this removes")
    }

    /// And it drops ONLY that. Losing Inbox or a status would take away somewhere to move to.
    func testThePickerKeepsEveryOtherState() {
        let offered = CoreBoardFixture.pickerColumns()
        XCTAssertEqual(offered.map(\.id), allColumns.filter { $0.kind != .done }.map(\.id))
        XCTAssertTrue(offered.contains { $0.kind == .inbox }, "Inbox is still somewhere to move to")
        XCTAssertTrue(offered.contains { $0.kind == .status }, "the real statuses are the point")
    }

    /// The BOARD is untouched — Done is a column there, and a task has to be able to land in it.
    func testTheBoardItselfStillHasDone() {
        XCTAssertTrue(allColumns.contains { $0.kind == .done },
                      "removing Done from the board would leave completed tasks nowhere to sit")
    }

    /// A custom state named "Done" is a STATUS, not the virtual Done column, and must survive.
    /// Filtering by name rather than by kind is the obvious wrong way to write this.
    func testACustomStateNamedDoneIsNotDropped() {
        let offered = CoreBoardFixture.pickerColumns(
            customStates: [ProjectCustomState(role: "custom-done", name: "Done", order: 0)])
        XCTAssertTrue(offered.contains { $0.id == "custom-done" },
                      "a project's own column called Done is a state, not the completion column")
    }

    // MARK: - The button that replaces it

    /// The label has to carry what the removed chip used to say: this is also how a task
    /// reaches Done.
    func testTheCompleteButtonSaysCompleteSlashDone() {
        XCTAssertEqual(NSLocalizedString("tasks.complete_task", comment: ""), "Complete / Done!")
    }

    // MARK: - Both pickers must use the filter

    private func source(_ relativePath: String) throws -> String {
        let url = RepositoryLocator.root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testTheIOSPickerAsksTheSharedFilter() throws {
        XCTAssertTrue(try source("Astrid App/Views/Components/ProjectStateQuickPicker.swift")
                        .contains("TaskStatusOptions"),
                      "the iOS picker must read the core's answer")
    }

    func testTheMacPickerAsksTheSharedFilter() throws {
        XCTAssertTrue(try source("Astrid Mac/Views/MacLeadingControlButton.swift")
                        .contains("TaskStatusOptions"),
                      "the Mac picker must read the same answer, or the two drift")
    }
}
