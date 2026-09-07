//  TaskOrdering.swift
//  The one comparator that decides task row order.
//
//  Task 63e75630 (AITD-314). This lived as an anonymous closure inside
//  `TaskService.mergeAndSortTasksInBackground`. Live SSE inserts now have to place a task in the
//  same position the next sync pull would, and the only way to guarantee that is for both to call
//  literally the same function — a second comparator that merely looks the same would show up as a
//  row jumping when the 60 s pull lands.

import Foundation

nonisolated enum TaskOrdering {

    /// Due date first (undated last), then newest-created first.
    ///
    /// The id tie-break is not cosmetic: dictionary values come out in arbitrary order and Swift's
    /// sort is not stable, so without it a batch of all-day tasks due the same day reshuffled on
    /// every background refresh — visible flicker on large lists.
    static func isOrderedBefore(_ task1: Task, _ task2: Task) -> Bool {
        if task1.dueDateTime != task2.dueDateTime {
            guard let date1 = task1.dueDateTime else { return false }
            guard let date2 = task2.dueDateTime else { return true }
            return date1 < date2
        }

        let created1 = task1.createdAt ?? .distantPast
        let created2 = task2.createdAt ?? .distantPast
        if created1 != created2 {
            return created1 > created2
        }

        return task1.id < task2.id
    }

    /// The index at which `task` belongs in an array already in this order.
    static func insertionIndex(for task: Task, in sorted: [Task]) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if isOrderedBefore(sorted[mid], task) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
