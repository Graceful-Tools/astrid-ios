//  QuickAddMyTasksRowTests.swift
//  AITD-543 — a task added with quick add on My Tasks must show in My Tasks' rows straight away,
//  not after a relaunch. Driven the way the view drives it: `TaskService.createTask` with no list
//  and the reader as assignee, while a `ListRowsModel` already shows My Tasks.

import XCTest
@testable import Astrid_App

@MainActor
final class QuickAddMyTasksRowTests: XCTestCase {
    private let me = "quick-add-reader"

    private func myTasksQuery() -> ListRowsModel.Query {
        .init(listId: ListRowsModel.myTasksId, myTasks: MyTasksPreferences(),
              subtaskDisplay: "indented", currentUserId: me)
    }

    func testAQuickAddedTaskShowsInTheOpenMyTasksList_AITD543() async throws {
        let model = ListRowsModel()
        await model.load(myTasksQuery())

        let made = try await TaskService.shared.createTask(
            listIds: [], title: "Quick add \(UUID().uuidString)", assigneeId: me)

        // The view draws `rows(ids(for:), in: tasksById)`; wait for the model's next answer.
        var drawn: [String] = []
        for _ in 0..<50 {
            let ids = model.ids(for: ListRowsModel.myTasksId) ?? []
            drawn = model.rows(ids, in: TaskService.shared.tasksById).map(\.id)
            if drawn.contains(made.id) { break }
            try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(drawn.contains(made.id),
                      "the new task \(made.id) is not among My Tasks' rows \(drawn)")
    }
}
