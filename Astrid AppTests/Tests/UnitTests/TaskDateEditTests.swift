import AstridCore
import XCTest
@testable import Astrid_App

/// AITD-635 — "Updating a task date to a future date is reverting back to the previously set date."
///
/// A date edit goes to the core as `updateTask { dueDateTime, isAllDay }`, through the Waiting rules
/// since core 084c2c0 (`waiting_update`: an edit touching the role or the date). These pin what the
/// core keeps for each kind of task the edit can land on.
final class TaskDateEditTests: XCTestCase {

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var lists: [TaskList] {
        var board = TaskList(id: "board-list", name: "Board")
        board.projectId = "p1"
        return [board, TaskList(id: "plain-list", name: "Plain")]
    }

    private func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: utc.startOfDay(for: Date()))!
    }

    private func task(statusRole: String? = nil, due: Date?, list: String = "plain-list",
                      repeating: Task.Repeating? = nil) -> Task {
        var t = TestHelpers.createTestTask(id: "t1", dueDateTime: due)
        t.isAllDay = due != nil
        t.statusRole = statusRole
        t.listIds = [list]
        t.lists = nil
        if let repeating { t.repeating = repeating }
        return t
    }

    /// The edit the detail view's date picker makes: an all-day date at UTC midnight.
    private func edited(_ task: Task, to due: Date) throws -> Task {
        let session = try CoreBoardFixture.session(tasks: [task], lists: lists,
                                                   projects: [Project(id: "p1", name: "Board")])
        var changes = TaskEdit()
        changes.set("dueDateTime", WireDate.dueDateString(from: due))
        changes.set("isAllDay", true)
        return try CoreRowsFixture.wait(session, CoreCommand.updateTask(taskId: task.id, changes: changes),
                                        as: Task.self)
    }

    func testAPlainTaskKeepsTheFutureDate_AITD635() throws {
        let result = try edited(task(due: day(-2)), to: day(5))
        XCTAssertEqual(result.dueDateTime, day(5))
    }

    func testATaskWithNoDateKeepsTheFutureDate_AITD635() throws {
        let result = try edited(task(due: nil), to: day(5))
        XCTAssertEqual(result.dueDateTime, day(5))
    }

    func testAReadyBoardTaskKeepsTheFutureDate_AITD635() throws {
        let result = try edited(task(statusRole: "ready", due: day(-1), list: "board-list"), to: day(5))
        XCTAssertEqual(result.dueDateTime, day(5))
    }

    func testADoingBoardTaskKeepsTheFutureDate_AITD635() throws {
        let result = try edited(task(statusRole: "doing", due: day(1), list: "board-list"), to: day(9))
        XCTAssertEqual(result.dueDateTime, day(9))
    }

    func testAWaitingTaskKeepsTheLaterDate_AITD635() throws {
        let result = try edited(task(statusRole: "waiting", due: day(2), list: "board-list"), to: day(9))
        XCTAssertEqual(result.dueDateTime, day(9))
    }

    func testARepeatingTaskKeepsTheFutureDate_AITD635() throws {
        let result = try edited(task(due: day(-1), repeating: .daily), to: day(5))
        XCTAssertEqual(result.dueDateTime, day(5))
    }
}
