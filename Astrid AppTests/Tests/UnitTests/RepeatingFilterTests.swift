//  RepeatingFilterTests.swift
//  The list-level "Repeating" filter was DEAD everywhere: iOS, Mac and web all showed the control
//  and persisted `filterRepeating`, but no filtering code ever read it, so choosing "Weekly" (or
//  "Not Repeating") changed nothing. These pin the behaviour in the shared engine.

import XCTest
@testable import Astrid_App

final class RepeatingFilterTests: XCTestCase {

    private func task(_ id: String, _ repeating: Task.Repeating?) -> Task {
        var t = Task(id: id, title: "Task \(id)")
        t.repeating = repeating
        return t
    }

    private func list(_ filter: String?) -> TaskList {
        var l = TaskList(id: "list-1", name: "List")
        l.filterRepeating = filter
        l.filterCompletion = "all"     // isolate the repeating dimension
        return l
    }

    private var sample: [Task] {
        [task("none", nil), task("never", .never), task("daily", .daily),
         task("weekly", .weekly), task("monthly", .monthly), task("yearly", .yearly),
         task("custom", .custom)]
    }

    private func ids(_ tasks: [Task]) -> Set<String> { Set(tasks.map(\.id)) }

    func testAllKeepsEveryTask() {
        let out = filterTasksForList(sample, list: list("all"), currentUserId: nil)
        XCTAssertEqual(ids(out), ids(sample))
    }

    func testNilFilterKeepsEveryTask() {
        let out = filterTasksForList(sample, list: list(nil), currentUserId: nil)
        XCTAssertEqual(ids(out), ids(sample))
    }

    /// "Not Repeating" means no rule at all — `nil` AND the explicit `.never` both qualify.
    func testNotRepeatingKeepsOnlyTasksWithoutARule() {
        let out = filterTasksForList(sample, list: list("not_repeating"), currentUserId: nil)
        XCTAssertEqual(ids(out), ["none", "never"])
    }

    func testEachCadenceKeepsOnlyThatCadence() {
        for cadence in ["daily", "weekly", "monthly", "yearly", "custom"] {
            let out = filterTasksForList(sample, list: list(cadence), currentUserId: nil)
            XCTAssertEqual(ids(out), [cadence], "Filtering by \(cadence) must keep only \(cadence) tasks")
        }
    }

    /// An unknown/future value must not silently hide everything.
    func testUnknownFilterValueKeepsEveryTask() {
        let out = filterTasksForList(sample, list: list("fortnightly"), currentUserId: nil)
        XCTAssertEqual(ids(out), ids(sample))
    }

    /// The repeating filter composes with the other dimensions rather than replacing them.
    func testComposesWithTheCompletionFilter() {
        var weeklyDone = task("weekly-done", .weekly)
        weeklyDone.completed = true
        var l = list("weekly")
        l.filterCompletion = "incomplete"
        let out = filterTasksForList(sample + [weeklyDone], list: l, currentUserId: nil)
        XCTAssertEqual(ids(out), ["weekly"], "Completed weekly task must be excluded by completion filter")
    }
}
