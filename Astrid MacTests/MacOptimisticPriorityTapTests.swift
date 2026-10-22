//  MacOptimisticPriorityTapTests.swift
//  The Mac priority taps must show the new priority on the tap, not after the write (AITD-532).
//  `OptimisticPriorityTests` pins `TaskService.applyOptimisticPriority`; until this task nothing
//  called it, so the keyboard shortcut and the bulk menu still waited behind earlier writes on the
//  main actor — the stall those tests describe. These drive the tap paths themselves.

import XCTest
@testable import Astrid_Mac

@MainActor
final class MacOptimisticPriorityTapTests: XCTestCase {
    private var savedSelection: Set<String> = []

    override func setUp() async throws {
        try await super.setUp()
        savedSelection = MacAppModel.shared.selectedTaskIds
    }

    override func tearDown() async throws {
        MacAppModel.shared.selectedTaskIds = savedSelection
        try await super.tearDown()
    }

    private func seed(_ priority: Task.Priority) -> Task {
        var task = Task(id: "tap-\(UUID().uuidString)", title: "Tap", listIds: [])
        task.priority = priority
        TaskService.shared.adoptForTesting(task)
        return task
    }

    private func shownPriority(_ id: String) -> Task.Priority? {
        TaskService.shared.tasks.first { $0.id == id }?.priority
    }

    /// The `3` shortcut on a selection: the row reads high before the write has had a turn.
    func testThePriorityShortcutShowsTheNewPriorityOnTheTap_AITD532() {
        let task = seed(.none)
        MacAppModel.shared.selectedTaskIds = [task.id]

        XCTAssertTrue(MacAppModel.shared.perform(.priorityHigh))

        XCTAssertEqual(shownPriority(task.id), .high, "nothing is awaited between the key and this line")
    }

    /// The bulk menu sets every selected task, each visible at once.
    func testTheBulkPriorityMenuShowsEveryTaskAtOnce_AITD532() {
        let first = seed(.none)
        let second = seed(.high)

        MacAppModel.setPriority(Task.Priority.low.rawValue, on: [first, second])

        XCTAssertEqual(shownPriority(first.id), .low)
        XCTAssertEqual(shownPriority(second.id), .low)
    }
}
