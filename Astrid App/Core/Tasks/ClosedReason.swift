//  ClosedReason.swift
//  Terminal states other than "done" (AITD-496) — web's `lib/closed-reason.ts`, for the Apple apps.
//
//  `Task.completed` is a flag, so there was no way to close something as NOT done; people said
//  "we're not doing this" by deleting the task, and lost the title and the discussion with it.
//  Closing as won't-do still sets `completed`, so every query and filter keeps working. Only the
//  rendering differs: the row carries a chip, and the detail menu offers Reopen.

import Foundation

enum ClosedReason {
    /// The reasons the server knows. The menu only ever writes `canceled`; the other two arrive
    /// from web's importers (a GitHub issue closed as not planned, a duplicate).
    static let canceled = "canceled"
    static let all = [canceled, "duplicate", "not_planned"]

    /// Was this task closed as anything other than done? Completed AND a known reason — a reason
    /// lingering on an open task, or one this build does not know, is not a won't-do.
    static func isCanceled(_ task: Task) -> Bool {
        guard task.completed, let reason = task.closedReason else { return false }
        return all.contains(reason)
    }

    /// The detail menu's item names what the tap will do, as web's does: close the task, or reopen
    /// one already closed that way.
    static func menuLabelKey(for task: Task) -> String {
        isCanceled(task) ? "tasks.reopen" : "tasks.wont_do"
    }

    static func menuSymbol(for task: Task) -> String {
        isCanceled(task) ? "arrow.counterclockwise" : "nosign"
    }

    /// What that tap writes: `nil` reopens.
    static func menuReason(for task: Task) -> String? {
        isCanceled(task) ? nil : canceled
    }

    static let chipLabelKey = "tasks.wont_do_chip"
}
