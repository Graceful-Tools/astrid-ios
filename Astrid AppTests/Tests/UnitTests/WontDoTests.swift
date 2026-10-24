//  WontDoTests.swift
//  Closing a task as "won't do" (AITD-496). Web has had it since task 11042ae3; the Apple apps
//  had no `closedReason` at all, so a task closed that way on web read here as plainly done.

import XCTest
@testable import Astrid_App

@MainActor
final class WontDoTests: XCTestCase {

    // MARK: - The model

    /// The server sends `closedReason`; before AITD-496 the Swift model dropped it on decode.
    func testATaskKeepsTheReasonItWasClosedFor_AITD496() throws {
        let wire = #"""
            {"id":"t1","title":"Skip it","description":"","isAllDay":true,"priority":0,
             "isPrivate":false,"completed":true,"closedReason":"canceled"}
            """#
        let task = try JSONDecoder().decode(Task.self, from: Data(wire.utf8))
        XCTAssertEqual(task.closedReason, "canceled")
    }

    // MARK: - The rule (web's `isCanceled`, lib/closed-reason.ts)

    func testWontDoIsCompletedAndClosedForAKnownReason_AITD496() {
        for reason in ["canceled", "duplicate", "not_planned"] {
            XCTAssertTrue(ClosedReason.isCanceled(Task(id: "t", title: "t", completed: true, closedReason: reason)))
        }
        XCTAssertFalse(ClosedReason.isCanceled(Task(id: "t", title: "t", completed: true)),
                       "simply completed is not won't-do")
        XCTAssertFalse(ClosedReason.isCanceled(Task(id: "t", title: "t", completed: false, closedReason: "canceled")),
                       "an open task is not won't-do, whatever reason lingers on it")
        XCTAssertFalse(ClosedReason.isCanceled(Task(id: "t", title: "t", completed: true, closedReason: "typo")))
    }

    /// The menu item names what the tap will do: close it, or reopen one already closed that way.
    func testTheMenuItemOffersReopenOnAWontDoTask_AITD496() {
        let open = Task(id: "t", title: "t")
        let closed = Task(id: "t", title: "t", completed: true, closedReason: "canceled")
        XCTAssertEqual(ClosedReason.menuLabelKey(for: open), "tasks.wont_do")
        XCTAssertEqual(ClosedReason.menuReason(for: open), "canceled")
        XCTAssertEqual(ClosedReason.menuLabelKey(for: closed), "tasks.reopen")
        XCTAssertNil(ClosedReason.menuReason(for: closed))
    }

    // MARK: - The write, through the core

    func testClosingAsWontDoCompletesWithTheReasonAndReopeningClearsBoth_AITD496() async throws {
        let service = TaskService.shared
        let made = try await service.createTask(listIds: [], title: "Won't do \(UUID().uuidString)")

        let closed = try await service.setClosedReason(taskId: made.id, reason: "canceled")
        XCTAssertTrue(closed.completed)
        XCTAssertEqual(closed.closedReason, "canceled")
        XCTAssertEqual(service.tasksById[made.id].map(ClosedReason.isCanceled), true,
                       "the row the list draws carries the chip")

        let reopened = try await service.setClosedReason(taskId: made.id, reason: nil)
        XCTAssertFalse(reopened.completed)
        XCTAssertNil(reopened.closedReason)
    }

    /// Web's rule (lib/task-update-handler.ts): a won't-do close is not an occurrence, so the
    /// series does not roll forward — the task closes, where a completion would leave it open.
    func testAWontDoCloseDoesNotRollARepeatingTaskForward_AITD496() async throws {
        let service = TaskService.shared
        let due = Date(timeIntervalSince1970: 1_790_000_000)
        let made = try await service.createTask(
            listIds: [], title: "Daily \(UUID().uuidString)", whenTime: due, repeating: "daily")

        let closed = try await service.setClosedReason(taskId: made.id, reason: "canceled")
        XCTAssertTrue(closed.completed, "a completion would have rolled it forward and left it open")
        XCTAssertEqual(closed.dueDateTime, made.dueDateTime)
    }

    /// Un-ticking the checkbox on a won't-do task reopens it properly: the reason goes too, or it
    /// would read as open and "won't do" at once.
    func testUncompletingAWontDoTaskClearsItsReason_AITD496() async throws {
        let service = TaskService.shared
        let made = try await service.createTask(listIds: [], title: "Reopen \(UUID().uuidString)")
        _ = try await service.setClosedReason(taskId: made.id, reason: "canceled")

        let reopened = try await service.completeTask(id: made.id, completed: false)
        XCTAssertFalse(reopened.completed)
        XCTAssertNil(reopened.closedReason)
    }
}
