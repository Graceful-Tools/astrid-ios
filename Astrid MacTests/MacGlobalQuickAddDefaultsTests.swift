//  MacGlobalQuickAddDefaultsTests.swift
//  Regression guard for Task 3d47cb62. Companion to MacQuickAddDefaultsTests, which
//  covers the in-list add bar; this covers the GLOBAL paths and the bar's preview.
//  Regression guard for Task 3d47cb62 — "[mac] list defaults should change the quick add task bar
//  to match default. and make sure defaults are applied".
//
//  Two halves, and the gap was in different places for each.
//
//  APPLIED: the add bar at the bottom of a list already resolved every default through the shared
//  `NewTaskDefaults`. The GLOBAL quick-add — the menu-bar item and the ⌥Space window — did not. It
//  parsed the text and created the task raw, so adding to a list from the menu bar produced a task
//  missing that list's priority, due date, repeat, assignee and privacy. Two paths that create a
//  task in the same list must agree about what that task starts as.
//
//  SHOWN: the leading checkbox previews priority, repeat and assignee. The default DUE DATE was not
//  previewed anywhere, so a list defaulting to "tomorrow" gave no hint before you pressed Return.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacGlobalQuickAddDefaultsTests: XCTestCase {

    /// A list that defines every default, so a path that drops them is unmistakable.
    private func opinionatedList(id: String = "l1") -> TaskList {
        var list = TaskList(id: id, name: "Work", privacy: .PRIVATE)
        list.defaultPriority = 3
        list.defaultDueDate = "tomorrow"
        list.defaultDueTime = "09:00"
        list.defaultRepeating = "weekly"
        list.defaultAssigneeId = "u-me"
        list.defaultIsPrivate = true
        return list
    }

    // MARK: - Applied: the global quick-add is not a second set of rules

    /// The bug: the menu-bar / ⌥Space path created a bare task.
    func testTheGlobalQuickAddAppliesTheListDefaults() throws {
        let list = opinionatedList()
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk", lists: [list],
                                                            currentUserId: "u-me"))
        XCTAssertEqual(args.listIds, [list.id])
        XCTAssertEqual(args.priority, 3, "the list's default priority must survive")
        XCTAssertEqual(args.repeating, "weekly")
        XCTAssertEqual(args.assigneeId, "u-me")
        XCTAssertEqual(args.isPrivate, true)
        XCTAssertNotNil(args.whenDate, "a list defaulting to tomorrow must produce a due date")
    }

    /// It must reach the list the text names, not just the first one.
    func testDefaultsComeFromTheListTheTextNames() throws {
        var plain = TaskList(id: "l0", name: "Inbox", privacy: .PRIVATE)
        plain.defaultPriority = 0
        let work = opinionatedList(id: "l-work")

        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk #Work",
                                                            lists: [plain, work],
                                                            currentUserId: "u-me"))
        XCTAssertTrue(args.listIds.contains("l-work"))
        XCTAssertEqual(args.priority, 3, "defaults must follow the destination, not the first list")
    }

    /// A default fills a gap; it never overwrites what the user said. Same rule as the add bar.
    /// The list defaults LOW here so the typed value is distinguishable — priority tops out at 3.
    func testTypedValuesStillBeatTheDefaults() throws {
        var list = opinionatedList()
        list.defaultPriority = 1
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk urgent",
                                                            lists: [list],
                                                            currentUserId: "u-me"))
        XCTAssertEqual(args.priority, 3, "\"urgent\" was typed, so it wins over the list's low")
    }

    /// With smart parsing off there is no parsed text to respect — but the list's defaults still
    /// apply, exactly as they do in the add bar.
    func testDefaultsApplyEvenWithSmartParsingOff() throws {
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk",
                                                            lists: [opinionatedList()],
                                                            smartEnabled: false,
                                                            currentUserId: "u-me"))
        XCTAssertEqual(args.priority, 3)
        XCTAssertEqual(args.repeating, "weekly")
        XCTAssertNotNil(args.whenDate)
    }

    /// The two paths must not disagree about what a task in this list starts as.
    func testTheGlobalPathAgreesWithTheAddBar() throws {
        let list = opinionatedList()
        let bar = try XCTUnwrap(MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: list.id,
                                                      lists: [list], currentUserId: "u-me"))
        let global = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk #Work",
                                                              lists: [list], currentUserId: "u-me"))
        XCTAssertEqual(bar.priority, global.priority)
        XCTAssertEqual(bar.repeating, global.repeating)
        XCTAssertEqual(bar.assigneeId, global.assigneeId)
        XCTAssertEqual(bar.isPrivate, global.isPrivate)
        XCTAssertEqual(bar.whenDate, global.whenDate)
    }

    // MARK: - Shown: the bar previews the due date it is about to apply

    /// What the add bar should display for the list's default due date — nil when there is none,
    /// so the chip does not appear at all rather than showing an empty slot.
    func testTheBarPreviewsNothingWhenTheListHasNoDefaultDate() {
        var list = TaskList(id: "l1", name: "L", privacy: .PRIVATE)
        list.defaultDueDate = "none"
        XCTAssertNil(MacQuickAddPreview.dueDateLabel(for: list))
        XCTAssertNil(MacQuickAddPreview.dueDateLabel(for: nil), "My Tasks has no list defaults")
    }

    func testTheBarPreviewsTheDefaultDueDate() throws {
        let label = try XCTUnwrap(MacQuickAddPreview.dueDateLabel(for: opinionatedList()),
                                  "a list defaulting to tomorrow must be previewed in the bar")
        XCTAssertFalse(label.isEmpty)
    }

    /// The preview must describe the SAME date the task will actually get, or it is a lie.
    func testThePreviewMatchesTheDateThatWillBeApplied() throws {
        let list = opinionatedList()
        let applied = try XCTUnwrap(NewTaskDefaults.dueDate(from: list.defaultDueDate,
                                                            time: list.defaultDueTime))
        XCTAssertEqual(MacQuickAddPreview.dueDateLabel(for: list),
                       MacQuickAddPreview.label(for: applied))
    }
}
#endif
