//  OptimisticPriorityTests.swift
//  Regression guard for the Mac priority stall.
//
//  Jon: "it seems like it might be waiting for the server call back and not updating the UI
//  optimistically for the priority update."
//
//  He is right about the symptom, and the wait is not the server. `TaskService` is `@MainActor`
//  and `updateTask` is `async`: its optimistic in-memory write happens before any network, but
//  AFTER the previous call's awaits — `saveTaskToCoreData` and the Outbox journal persist, both
//  disk. Tap several priorities quickly and each tap's optimistic update queues behind the
//  previous tap's disk work on the main actor. The journal grows as you tap, so it degrades:
//  fine at first, then visibly stuck, which is exactly "eventually it stalls".
//
//  So the DISPLAYED priority must not depend on that queue at all. `applyOptimisticPriority` is
//  synchronous: it returns having already updated what the views read, with nothing awaited.

import XCTest
@testable import Astrid_App

@MainActor
final class OptimisticPriorityTests: XCTestCase {

    private func seed(_ priority: Task.Priority) -> Task {
        let t = Task(id: "opt-\(UUID().uuidString)", title: "Optimistic", listIds: [])
        var seeded = t
        seeded.priority = priority
        TaskService.shared.adoptForTesting(seeded)
        return seeded
    }

    /// THE ASK: the value the views read changes on the tap, not after a round trip.
    func testTheDisplayedPriorityChangesSynchronously() {
        let task = seed(.none)

        let applied = TaskService.shared.applyOptimisticPriority(taskId: task.id, priority: .high)

        XCTAssertTrue(applied)
        XCTAssertEqual(TaskService.shared.tasks.first { $0.id == task.id }?.priority, .high,
                       "the array the views render from must already hold the new priority — "
                       + "nothing is awaited between the tap and this line")
    }

    /// Rapid taps: every one lands, in order, with no await between them. This is the sequence
    /// that stalled — each tap used to queue behind the previous tap's disk work.
    func testEveryTapInARapidSequenceLands() {
        let task = seed(.none)

        for p in [Task.Priority.high, .low, .medium, .high, .none, .medium] {
            XCTAssertTrue(TaskService.shared.applyOptimisticPriority(taskId: task.id, priority: p))
            XCTAssertEqual(TaskService.shared.tasks.first { $0.id == task.id }?.priority, p,
                           "tap \(p) must be visible immediately")
        }
    }

    /// Re-tapping the priority it already holds still reports applied, so a caller cannot use
    /// the return value to decide the tap "did nothing" and skip its own update.
    func testReapplyingTheSamePriorityStillCounts() {
        let task = seed(.medium)
        XCTAssertTrue(TaskService.shared.applyOptimisticPriority(taskId: task.id, priority: .medium))
    }

    /// An unknown task is the one case it cannot apply — and it says so rather than inventing
    /// a task.
    func testAnUnknownTaskIsNotApplied() {
        XCTAssertFalse(TaskService.shared.applyOptimisticPriority(taskId: "no-such-task", priority: .high))
    }
}
