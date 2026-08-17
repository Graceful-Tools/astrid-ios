//  TaskDisplayModeTests.swift
//  The task-detail layout preference (task 8ef7d89d).
//
//  `taskDisplayMode` is a nullable string on the user's settings with exactly two values,
//  "list" and "project". The web half is live on production; nothing read it on any platform,
//  so adopting it is additive.
//
//  These pin the three cases the task calls out as easy to get wrong, because each one fails
//  quietly rather than loudly:
//
//   1. NULL IS NOT A THIRD MODE. Rows written before the column read back null, and a build
//      that meets a value it does not know must still show a usable screen.
//   2. READS NORMALIZE, WRITES REJECT. The server returns 400 for anything but the two
//      literals, so a coerced value must never be sent back.
//   3. LOAD BEFORE SAVE. A picker that saves correctly but initialises to the default looks
//      right until the screen is revisited — and then re-saving from the stale control writes
//      "list" over "project". Web has a regression test for exactly this.

import XCTest
@testable import Astrid_App

final class TaskDisplayModeTests: XCTestCase {

    // MARK: - 1. Null is not an error, and not a third mode

    func testNullIsList() {
        XCTAssertEqual(TaskDisplayMode(stored: nil), .list)
    }

    func testAnUnrecognisedValueIsList() {
        // A build that does not know a newer mode must show the safe layout, not an empty one.
        XCTAssertEqual(TaskDisplayMode(stored: "kanban"), .list)
        XCTAssertEqual(TaskDisplayMode(stored: ""), .list)
    }

    func testTheTwoRealValuesDecode() {
        XCTAssertEqual(TaskDisplayMode(stored: "list"), .list)
        XCTAssertEqual(TaskDisplayMode(stored: "project"), .project)
    }

    /// The server's own values are lowercase; be forgiving on read, since read normalizes.
    func testDecodingIsCaseInsensitiveAndTrims() {
        XCTAssertEqual(TaskDisplayMode(stored: "PROJECT"), .project)
        XCTAssertEqual(TaskDisplayMode(stored: " project "), .project)
    }

    // MARK: - 2. Writes reject — send only the two literals

    func testTheWireValueIsAlwaysOneOfTheTwoLiterals() {
        XCTAssertEqual(TaskDisplayMode.list.wireValue, "list")
        XCTAssertEqual(TaskDisplayMode.project.wireValue, "project")
    }

    /// THE ONE THAT PROTECTS THE SERVER CONTRACT. Whatever came in, what goes back out is a
    /// value the server accepts — a coerced string must never be echoed.
    func testAnUnknownStoredValueIsNeverSentBack() {
        let resolved = TaskDisplayMode(stored: "kanban")
        XCTAssertTrue(["list", "project"].contains(resolved.wireValue),
                      "PATCH with anything else returns 400 Invalid taskDisplayMode value")
    }

    // MARK: - What each mode means, named once

    /// Call sites ask these questions rather than comparing the enum themselves — the same
    /// reason astrid-web exposes `checkboxCompletesTask` and `usesCompactTaskDetail` from
    /// `lib/task-display-mode.ts`. A comparison spelled at ten call sites is ten chances to
    /// spell it differently, and the bug this setting exists to end is a HYBRID of the two
    /// layouts.
    func testListModeCompletesFromTheCheckbox() {
        XCTAssertTrue(TaskDisplayMode.list.checkboxCompletesTask)
        XCTAssertFalse(TaskDisplayMode.list.usesCompactTaskDetail)
    }

    func testProjectModeOpensAPickerInsteadOfCompleting() {
        XCTAssertFalse(TaskDisplayMode.project.checkboxCompletesTask,
                       "In project mode the checkbox reveals the popover; it does not complete")
        XCTAssertTrue(TaskDisplayMode.project.usesCompactTaskDetail)
    }

    // MARK: - What the layouts actually do (task 729a190e)

    /// The two questions the detail screens ask. Until task 729a190e nothing read them, so
    /// the setting was a picker that changed nothing — which is worse than no setting,
    /// because it looks like it worked.
    func testListModeShowsAssigneeAndPriorityAsSeparateRows() {
        XCTAssertTrue(TaskDisplayMode.list.showsSeparateAssigneeAndPriorityRows)
    }

    /// Project mode keeps them behind the leading control, which already depicts both.
    func testProjectModeKeepsAssigneeAndPriorityBehindTheControl() {
        XCTAssertFalse(TaskDisplayMode.project.showsSeparateAssigneeAndPriorityRows)
    }

    /// The two halves must never both be true: the rows exist precisely when the popover
    /// does not. A build where both are on is the HYBRID layout this setting exists to end.
    func testARowAndAPopoverAreNeverBothOffered() {
        for mode in TaskDisplayMode.allCases {
            XCTAssertNotEqual(mode.showsSeparateAssigneeAndPriorityRows,
                              mode.usesCompactTaskDetail,
                              "\(mode) offers priority and assignee twice, or not at all")
        }
    }

    /// And the checkbox follows the same split: it completes exactly where the rows are.
    func testTheCheckboxCompletesExactlyWhereTheRowsAre() {
        for mode in TaskDisplayMode.allCases {
            XCTAssertEqual(mode.checkboxCompletesTask,
                           mode.showsSeparateAssigneeAndPriorityRows,
                           "\(mode) disagrees about what its checkbox is for")
        }
    }

    // MARK: - 3. Load before save

    /// The stale-control trap, as a rule a control can consult: until settings have actually
    /// loaded, a picker must not be allowed to write. Otherwise revisiting the screen re-saves
    /// the default over whatever the user chose.
    func testAControlMayNotSaveBeforeSettingsHaveLoaded() {
        XCTAssertFalse(TaskDisplayMode.mayPersistSelection(hasLoadedSettings: false))
        XCTAssertTrue(TaskDisplayMode.mayPersistSelection(hasLoadedSettings: true))
    }

    // MARK: - Settings round-trip

    /// The decode must survive a payload that omits the field entirely — every row written
    /// before the column exists.
    func testSettingsDecodeWithoutTheFieldAtAll() throws {
        let json = #"{"smartTaskCreationEnabled":true,"subtaskDisplay":"indented"}"#
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.taskDisplayMode)
        XCTAssertEqual(TaskDisplayMode(stored: settings.taskDisplayMode), .list)
    }

    func testSettingsDecodeWithAnExplicitNull() throws {
        let json = #"{"taskDisplayMode":null}"#
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(json.utf8))
        XCTAssertEqual(TaskDisplayMode(stored: settings.taskDisplayMode), .list)
    }

    func testSettingsCarryProjectThrough() throws {
        let json = #"{"taskDisplayMode":"project"}"#
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(json.utf8))
        XCTAssertEqual(TaskDisplayMode(stored: settings.taskDisplayMode), .project)
    }

    /// `updateSettings` merges field by field, and it already drops `subtaskDisplay` on the
    /// floor — a write that looks saved and is not. A new field added without a merge line
    /// would fail exactly the same way, so pin it.
    func testUpdatingTheModeSurvivesTheMerge() {
        let merged = UserSettings.merging(UserSettings(taskDisplayMode: "project"),
                                          into: UserSettings(taskDisplayMode: "list"))
        XCTAssertEqual(merged.taskDisplayMode, "project")
    }

    /// And an update that says nothing about the mode must not erase it.
    func testAnUnrelatedUpdateLeavesTheModeAlone() {
        let merged = UserSettings.merging(UserSettings(smartTaskCreationEnabled: false),
                                          into: UserSettings(taskDisplayMode: "project"))
        XCTAssertEqual(merged.taskDisplayMode, "project")
    }
}
