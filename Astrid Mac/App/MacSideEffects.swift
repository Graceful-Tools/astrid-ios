//  MacSideEffects.swift
//  Astrid for Mac — pure helpers for coalescing per-mutation side-effects (Task c38b177b).
//  Every taskService.tasks change used to reschedule ALL local notifications + the dock badge.
//  Rescheduling is only needed when the REMINDER-RELEVANT shape changed: which incomplete tasks
//  have which due dates. The signature captures exactly that.

#if os(macOS)
import Foundation

enum MacSideEffects {
    /// Debounce window for task-change side-effects (badge + notification reschedule).
    static let coalesceNanos: UInt64 = 800_000_000

    /// Order-independent signature of the reminder-relevant task state: (id, dueDateTime) of
    /// incomplete tasks with a due date. Title/notes/priority edits do NOT change it.
    static func dueSignature(_ tasks: [Task]) -> Int {
        var acc = 0
        for t in tasks where !t.completed {
            guard let due = t.dueDateTime else { continue }
            var h = Hasher()
            h.combine(t.id)
            h.combine(due)
            acc ^= h.finalize()   // XOR → order-independent
        }
        return acc
    }
}
#endif
