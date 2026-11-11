//  TaskBoardStatusPillTests.swift
//  AITD-613: a list row shows the task's board status as a coloured pill — red Inbox, green
//  Ready, a second green for Doing, yellow Waiting, blue Done — and nothing for a task that is
//  on no board.

import XCTest
@testable import Astrid_App

final class TaskBoardStatusPillTests: XCTestCase {

    private let projectList = TaskList(id: "l1", name: "iOS", projectId: "p1")
    private let plainList = TaskList(id: "l2", name: "Groceries", projectId: nil)

    private func task(listIds: [String] = ["l1"], statusRole: String? = nil,
                      completed: Bool = false) -> Task {
        var t = Task(id: "t1", title: "t", completed: completed)
        t.listIds = listIds
        t.statusRole = statusRole
        return t
    }

    private func status(_ t: Task, projects: [Project] = []) -> TaskBoardStatus? {
        TaskBoardStatus.of(t, lists: [projectList, plainList], projects: projects)
    }

    func testAITD613_aTaskOnNoBoardHasNoPill() {
        XCTAssertNil(status(task(listIds: ["l2"])))
        XCTAssertNil(status(task(listIds: ["l2"], completed: true)))
    }

    func testAITD613_eachBuiltInColumnHasItsOwnKind() {
        XCTAssertEqual(status(task())?.kind, .inbox)
        XCTAssertEqual(status(task(statusRole: ""))?.kind, .inbox)
        XCTAssertEqual(status(task(statusRole: "ready"))?.kind, .ready)
        XCTAssertEqual(status(task(statusRole: "doing"))?.kind, .doing)
        XCTAssertEqual(status(task(statusRole: "waiting"))?.kind, .waiting)
    }

    func testAITD613_aCompletedBoardTaskIsDoneWhateverItsRole() {
        XCTAssertEqual(status(task(statusRole: "doing", completed: true))?.kind, .done)
        XCTAssertEqual(status(task(completed: true))?.kind, .done)
    }

    func testAITD613_theBuiltInNamesAreLocalizedKeys() {
        XCTAssertEqual(status(task(statusRole: "ready"))?.name,
                       NSLocalizedString("board.status.ready", comment: ""))
        XCTAssertNotEqual(status(task(statusRole: "ready"))?.name, "board.status.ready")
    }

    func testAITD613_aRenamedColumnShowsTheBoardsName() {
        var project = Project(id: "p1", name: "iOS")
        project.customStates = [ProjectCustomState(role: "ready", name: "Up next"),
                                ProjectCustomState(role: "custom-review", name: "Review")]
        XCTAssertEqual(status(task(statusRole: "ready"), projects: [project])?.name, "Up next")
        let review = status(task(statusRole: "custom-review"), projects: [project])
        XCTAssertEqual(review?.kind, .custom)
        XCTAssertEqual(review?.name, "Review")
    }

    func testAITD613_aCustomColumnWithNoKnownNameDrawsNothing() {
        // Never show a raw `custom-…` role to a person.
        XCTAssertNil(status(task(statusRole: "custom-review")))
    }
}
