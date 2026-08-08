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

    /// A list's default time of day, as hour and minute. nil means the list has
    /// no default time, i.e. dates on it are all-day.
    ///
    /// Split out from `dueDate` because it is needed on its own: putting a date
    /// on an EXISTING task should give it the list's default time, not whatever
    /// the clock happens to say. The Mac was reading `Date()` there, so a task
    /// dated at 4pm came out due at 4pm.
    static func timeOfDay(_ defaultDueTime: String?) -> (hour: Int, minute: Int)? {
        guard let value = defaultDueTime, !value.isEmpty else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
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

    /// Resolve a list's default assignee. `defaultAssigneeId` carries THREE meanings on the wire
    /// (see ListDefaults):
    ///   nil          → "task_creator": the new task goes to whoever creates it
    ///   "unassigned" → nobody
    ///   an id        → that person
    ///
    /// Collapsing the first two into "no assignee" is wrong: a list whose default is the creator
    /// would silently produce unassigned tasks.
    static func assignee(_ defaultAssigneeId: String?, currentUserId: String?) -> String? {
        guard let value = defaultAssigneeId, !value.isEmpty else {
            return currentUserId       // "task_creator" — nil when signed out, i.e. unassigned
        }
        return value == "unassigned" ? nil : value
    }
}
