//  MacPerformanceTests.swift
//  Astrid for Mac — performance budgets for the hot paths (Task ecf8f61c).
//  These measure the pure business logic that runs on every render at scale (10k tasks):
//  command-palette search, per-list filter+sort, and the My Tasks aggregation. XCTest records a
//  baseline; a large regression fails CI. (Launch / 10k-row rendering budgets need UI automation
//  and are tracked with the UI-automation task 6c30df95.)

import XCTest
@testable import Astrid_Mac

final class MacPerformanceTests: XCTestCase {

    private func makeTasks(_ n: Int) -> [Task] {
        (0..<n).map { i in
            var t = Task(id: "t\(i)", title: "Task number \(i) alpha beta", completed: i % 5 == 0)
            t.priority = Task.Priority(rawValue: i % 4) ?? .none
            t.dueDateTime = i % 3 == 0 ? Date().addingTimeInterval(Double(i) * 60) : nil
            t.assigneeId = i % 2 == 0 ? "me" : nil
            return t
        }
    }

    func testPaletteSearchOver10kTasks() {
        let tasks = makeTasks(10_000)
        measure { _ = MacPaletteSearch.matchingTasks("alpha", tasks: tasks, limit: 6) }
    }

    func testSortOver10kTasks() {
        let tasks = makeTasks(10_000)
        measure { _ = sortTasksByListSetting(tasks, sortBy: "auto", manualOrder: nil) }
    }

    func testDueDateFilterOver10kTasks() {
        let tasks = makeTasks(10_000)
        measure { _ = applyListDueDateFilter(tasks, filter: "today") }
    }

    func testMyTasksAggregationOver10kTasks() {
        let tasks = makeTasks(10_000)
        measure { _ = MacMyTasks.filter(tasks, userId: "me") }
    }
}
