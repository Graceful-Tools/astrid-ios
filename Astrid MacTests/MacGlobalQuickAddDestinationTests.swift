//  MacGlobalQuickAddDestinationTests.swift
//  Regression guard for AITD-387 — "[mac] cntr-space creates add a task, but for some reason it
//  always adds it to AStrid iOS-To. it should be to my tasks by default".
//
//  WHAT WENT WRONG. `makeGlobalArgs` had no "current list" to work from, so when the text named
//  no #list it fell back to `lists[0]` — the first list in whatever order the service happened to
//  hand over. That is not a destination anyone chose. For this account it was "Astrid iOS To-do",
//  so every task typed into the ⌥Space window landed in the iOS bug tracker, which is exactly the
//  "for some reason" in the report: the rule was invisible and the result looked arbitrary.
//
//  WHAT IT DOES NOW. No named list means MY TASKS, which is what the Mac already lands on at
//  launch (`MacLaunchSelection.landingListId`). My Tasks is a VIRTUAL selection, not a real list,
//  so the task is created with NO list ids at all — the same thing `makeArgs` does for a virtual
//  selection, and the same thing iOS does. It shows up in My Tasks because that view is "mine or
//  unassigned" (`MacMyTasks.filter`), not because it was filed anywhere.
//
//  The parser is untouched: "#Work" still sends a task to Work, and the list's defaults still
//  follow it there (Task 3d47cb62). The only thing that changed is what happens when you name
//  nothing.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacGlobalQuickAddDestinationTests: XCTestCase {

    private func list(_ id: String, _ name: String) -> TaskList {
        TaskList(id: id, name: name, privacy: .PRIVATE)
    }

    // MARK: - The bug as reported

    /// The heart of it: a plain task names no list, so it must not acquire one.
    func testAPlainTaskGoesToMyTasksRatherThanTheFirstList() throws {
        let lists = [list("l-ios", "Astrid iOS To-do"), list("l-work", "Work")]
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk", lists: lists,
                                                            currentUserId: "u-me"))
        XCTAssertEqual(args.listIds, [],
                       "AITD-387: no named list means My Tasks, which is not a real list")
        XCTAssertNotEqual(args.listIds, ["l-ios"],
                          "AITD-387: the first list is not a destination the user chose")
    }

    /// Order must not decide the destination. The same text with the lists the other way round
    /// has to produce the same task — under the old rule it produced two different ones.
    func testTheDestinationDoesNotDependOnListOrder() throws {
        let a = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(
            rawText: "Buy milk", lists: [list("l-ios", "Astrid iOS To-do"), list("l-work", "Work")],
            currentUserId: "u-me"))
        let b = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(
            rawText: "Buy milk", lists: [list("l-work", "Work"), list("l-ios", "Astrid iOS To-do")],
            currentUserId: "u-me"))
        XCTAssertEqual(a.listIds, b.listIds, "AITD-387: list order is not a destination")
    }

    /// Smart parsing off is the same promise. That path had its own `[lists[0].id]`.
    func testAPlainTaskGoesToMyTasksWithSmartParsingOff() throws {
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(
            rawText: "Buy milk", lists: [list("l-ios", "Astrid iOS To-do")],
            smartEnabled: false, currentUserId: "u-me"))
        XCTAssertEqual(args.listIds, [], "AITD-387: the non-smart path fell back to lists[0] too")
    }

    // MARK: - What must NOT change

    /// Naming a list still works, and still brings that list's defaults with it (Task 3d47cb62).
    func testNamingAListStillSendsItThere() throws {
        var work = list("l-work", "Work")
        work.defaultPriority = 3
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(
            rawText: "Buy milk #Work", lists: [list("l-ios", "Astrid iOS To-do"), work],
            currentUserId: "u-me"))
        XCTAssertEqual(args.listIds, ["l-work"])
        XCTAssertEqual(args.priority, 3, "the named list's defaults must still follow it")
    }

    /// A My Tasks task takes no LIST defaults — there is no list to take them from, and
    /// inheriting them from a list the user never named is the bug.
    ///
    /// The assignee is the exception, and deliberately so: "task_creator" is what
    /// `NewTaskDefaults.assignee` answers when nothing names an assignee, list or no list, so the
    /// task starts as YOURS. That is what the add bar does in a list with no default of its own,
    /// it is what puts the task in My Tasks on both platforms, and since AITD-382 it is also what
    /// keeps the checkbox tappable — an unassigned task opens the options popover instead.
    func testAMyTasksTaskCarriesNoListDefaults() throws {
        var opinionated = list("l-ios", "Astrid iOS To-do")
        opinionated.defaultPriority = 3
        opinionated.defaultAssigneeId = "u-someone"
        opinionated.defaultRepeating = "weekly"

        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk",
                                                            lists: [opinionated],
                                                            currentUserId: "u-me"))
        XCTAssertEqual(args.assigneeId, "u-me",
                       "AITD-387: no list means the creator default, not the first list's assignee")
        XCTAssertNotEqual(args.assigneeId, "u-someone",
                          "AITD-387: the first list's assignee must not leak into My Tasks")
        XCTAssertNil(args.repeating, "AITD-387: a task in no list must not inherit a repeat")
        XCTAssertNotEqual(args.priority, 3,
                          "AITD-387: the first list's priority must not leak into My Tasks")
    }

    /// The ⊕ options on the add bar override the defaults for one task. The global window offers
    /// the same choice (AITD-387: "should have all the same options as the add task input"), so
    /// the argument has to survive the trip.
    func testThePriorityChosenInTheOptionsIsHonoured() throws {
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk",
                                                            lists: [list("l-ios", "iOS")],
                                                            priorityOverride: 2,
                                                            currentUserId: "u-me"))
        XCTAssertEqual(args.priority, 2, "AITD-387: the picked priority must reach the task")
    }

    /// Typed still beats picked, the same way it does on the add bar — the last thing the user
    /// expressed wins.
    func testTypedPriorityStillBeatsTheChosenOne() throws {
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk urgent",
                                                            lists: [list("l-ios", "iOS")],
                                                            priorityOverride: 1,
                                                            currentUserId: "u-me"))
        XCTAssertEqual(args.priority, 3, "\"urgent\" was typed, so it wins over the picker")
    }

    /// Having no lists at all is no longer a reason to refuse. The old guard existed only because
    /// the fallback needed `lists[0]` to exist; My Tasks needs nothing, and a brand-new account
    /// with no lists yet must still be able to capture a thought.
    func testATaskCanBeAddedBeforeAnyListsExist() throws {
        let args = try XCTUnwrap(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk", lists: [],
                                                            currentUserId: "u-me"))
        XCTAssertEqual(args.title, "Buy milk")
        XCTAssertEqual(args.listIds, [])
    }

    /// Empty input still creates nothing. An abandoned draft is not a task.
    func testEmptyTextStillCreatesNothing() {
        XCTAssertNil(MacQuickAdd.makeGlobalArgs(rawText: "", lists: []))
        XCTAssertNil(MacQuickAdd.makeGlobalArgs(rawText: "   \n\t ", lists: []))
    }
}
#endif
