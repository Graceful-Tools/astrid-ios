//  NewTaskDefaults.swift
//  The list's "new task" defaults — priority, due date/time, repeat, assignee — resolved in ONE
//  place for every platform.
//
//  iOS had this logic twice (private copies in QuickAddTaskView and TaskEditView) and Mac had it
//  nowhere, which is why a Mac quick-add ignored the list's defaults entirely. Adding a third copy
//  would have guaranteed the three drift apart, so it lives here and callers delegate.
//
//  The rule everywhere: a default only fills a gap. Anything the user typed or chose wins.
import Foundation

/// Named `NewTaskDefaults`, not `ListDefaults`: `ListDefaults` is already the DTO that CARRIES a
/// list's default fields. This resolves those fields into concrete values for a NEW task.
enum NewTaskDefaults {

    /// Resolve a list's `defaultDueDate` / `defaultDueTime` into a concrete date.
    ///
    /// Accepts the keywords the pickers write ("today", "tomorrow", "next_week", "next_month") or
    /// an ISO date string. "none"/empty/nil means no default. `defaultDueTime` is "HH:mm"; without
    /// it the date is all-day.
    static func dueDate(from defaultDueDate: String?, time defaultDueTime: String?,
                        now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let value = defaultDueDate, value != "none", !value.isEmpty else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        switch value {
        case "today":       break
        case "tomorrow":    components.day? += 1
        case "next_week":   components.day? += 7
        case "next_month":  components.month? += 1
        default:
            guard let parsed = ISO8601DateFormatter().date(from: value) else { return nil }
            components = calendar.dateComponents([.year, .month, .day], from: parsed)
        }

        if let time = defaultDueTime, !time.isEmpty {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                components.hour = parts[0]
                components.minute = parts[1]
            }
        }
        return calendar.date(from: components)
    }

    /// A list's default priority, or nil when unset. 0 means "no default", not "priority zero".
    static func priority(_ defaultPriority: Int?) -> Int? {
        guard let p = defaultPriority, p > 0 else { return nil }
        return p
    }

    /// A list's default repeat rule, or nil when unset/never.
    static func repeating(_ defaultRepeating: String?) -> String? {
        guard let r = defaultRepeating, !r.isEmpty, r != "never" else { return nil }
        return r
    }

    /// A list's default assignee, or nil when unset.
    static func assignee(_ defaultAssigneeId: String?) -> String? {
        guard let a = defaultAssigneeId, !a.isEmpty else { return nil }
        return a
    }
}
