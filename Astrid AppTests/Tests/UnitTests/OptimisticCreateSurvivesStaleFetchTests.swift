//  OptimisticCreateSurvivesStaleFetchTests.swift
//  Regression tests for Task f07dff56 — "when adding a task on Mac it disappears and later
//  reappears. optimistic / client adding might be an issue".
//
//  The optimistic insert and the temp→real swap are both fine. The race is in the sync merge:
//
//    1. A sync fetch starts (Mac auto-syncs every 60s, plus wake recovery and SSE).
//    2. You add a task; the outbox creates it and reconciles temp→real, so it is now NON-temp.
//    3. The fetch from (1) predates the create and returns a snapshot without it.
//    4. The merge dropped any non-temp local task the server "does not have" → it disappeared.
//    5. The next sync included it → it came back.
//
//  `recentlyDeletedIds` already stops the mirror-image race (a stale fetch resurrecting something
//  you deleted). This is the same race in the other direction.

import XCTest
@testable import Astrid_App

final class OptimisticCreateSurvivesStaleFetchTests: XCTestCase {

    private func task(id: String, title: String, updatedAt: Date = Date()) -> Task {
        Task(id: id, title: title, description: "", assigneeId: nil, assignee: nil,
             creatorId: "me", creator: nil, dueDateTime: nil, isAllDay: false,
             reminderTime: nil, reminderSent: nil, reminderType: nil,
             repeating: .never, repeatingData: nil, priority: .none,
             lists: nil, listIds: ["list-1"], isPrivate: true, completed: false,
             completedAt: nil, completedSource: nil, attachments: nil, comments: nil,
             createdAt: updatedAt, updatedAt: updatedAt, originalTaskId: nil, sourceListId: nil)
    }

    /// THE BUG: a task we just created and reconciled must survive a fetch that predates it.
    func testAJustCreatedTaskSurvivesAFetchThatPredatesIt() async {
        let justCreated = task(id: "real-1", title: "Buy milk")
        let staleServerSnapshot = [task(id: "old-1", title: "Existing")]

        let merged = await TaskService.mergeAndSortTasksInBackground(
            newTasks: staleServerSnapshot,
            pendingTasks: [task(id: "old-1", title: "Existing"), justCreated],
            protectedIds: ["real-1"]
        )

        XCTAssertTrue(merged.contains { $0.id == "real-1" },
                      "the task we just added vanished when a stale fetch landed")
    }

    /// The guard must not become "never delete anything": a task removed on another device is
    /// still absent from the server, and outside the protected set it must go.
    func testARemotelyDeletedTaskIsStillDropped() async {
        let deletedElsewhere = task(id: "gone-1", title: "Deleted on the web")

        let merged = await TaskService.mergeAndSortTasksInBackground(
            newTasks: [task(id: "old-1", title: "Existing")],
            pendingTasks: [task(id: "old-1", title: "Existing"), deletedElsewhere],
            protectedIds: []
        )

        XCTAssertFalse(merged.contains { $0.id == "gone-1" },
                       "server absence must still mean deleted for anything we did not just create")
    }

    /// Protection is about the row existing, not about winning an edit race: once the server DOES
    /// return the task, its version is merged by the normal timestamp rule.
    func testProtectionDoesNotOverrideNewerServerData() async {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let localStale = task(id: "real-1", title: "Local title", updatedAt: old)
        let serverFresh = task(id: "real-1", title: "Server title", updatedAt: new)

        let merged = await TaskService.mergeAndSortTasksInBackground(
            newTasks: [serverFresh],
            pendingTasks: [localStale],
            protectedIds: ["real-1"]
        )

        XCTAssertEqual(merged.first { $0.id == "real-1" }?.title, "Server title",
                       "protection must not freeze a stale local copy in place")
    }

    /// A protected id the server DOES return must not be duplicated.
    func testAProtectedTaskIsNeverDuplicated() async {
        let t = task(id: "real-1", title: "Buy milk")

        let merged = await TaskService.mergeAndSortTasksInBackground(
            newTasks: [t], pendingTasks: [t], protectedIds: ["real-1"]
        )

        XCTAssertEqual(merged.filter { $0.id == "real-1" }.count, 1)
    }

    /// Temp rows are already kept by the existing clientRequestId/title matching — the new guard
    /// must not disturb that path.
    func testTempRowsStillSurviveWhenTheServerHasNotSeenThemYet() async {
        let temp = task(id: "temp_abc", title: "Not sent yet")

        let merged = await TaskService.mergeAndSortTasksInBackground(
            newTasks: [], pendingTasks: [temp], protectedIds: []
        )

        XCTAssertTrue(merged.contains { $0.id == "temp_abc" })
    }
}
