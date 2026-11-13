//  ListQuickAddDefaults.swift
//  A new task's defaults — priority, due date/time, repeat, assignee, privacy — for every platform,
//  answered by astrid-core's `quickAddDefaults` rule (AITD-646).
//
//  This replaced `NewTaskDefaults.swift`, the Swift copy of the rule. What is left here is the
//  `TaskList` → wire mapping and nothing that decides: a default only fills a gap, and anything the
//  person typed or chose wins — the core's rule, not this file's.
import AstridCore
import Foundation

enum ListQuickAddDefaults {

    /// What a task added to `list` starts out as. `nil` list = My Tasks and the other views, which
    /// have no defaults; the creator is still the fallback assignee there.
    ///
    /// Pass `priority` / `assigneeId` only when the person has picked one — passing it is what
    /// makes the field said. `"unassigned"` is a choice of nobody.
    static func resolve(_ list: TaskList?, currentUserId: String?, priority: Int? = nil,
                        assigneeId: String? = nil, now: Date = Date(),
                        timeZone: TimeZone = .current) -> QuickAddDefaults {
        do {
            return try CoreRules.quickAddDefaults(
                list: list.map(wire), userId: currentUserId, now: now, timeZone: timeZone,
                priority: priority, assigneeId: assigneeId)
        } catch {
            // Only an impossible UTC offset is refused. Add the task with nothing filled in rather
            // than refuse to add it.
            AppLog.debug("❌ [ListQuickAddDefaults] quickAddDefaults failed: \(error)")
            return QuickAddDefaults(priority: priority ?? 0, assigneeId: nil, dueDateTime: nil,
                                    isAllDay: true, repeating: nil, isPrivate: false)
        }
    }

    /// The list's default time of day, for putting a FIRST date on an existing task — which takes
    /// the list's time, not the clock's. `nil` when the list has none (dates on it are all-day).
    ///
    /// Asked of the same rule: a list with only a time default makes a task due today at that
    /// time, so the core's reading of `HH:mm` is the one used and no Swift parser survives.
    static func timeOfDay(_ defaultDueTime: String?, now: Date = Date(),
                          timeZone: TimeZone = .current) -> (hour: Int, minute: Int)? {
        guard let defaultDueTime, !defaultDueTime.isEmpty else { return nil }
        let probe = QuickAddList(id: "time-of-day", name: "", defaultDueTime: defaultDueTime)
        guard let answer = try? CoreRules.quickAddDefaults(list: probe, userId: nil, now: now,
                                                           timeZone: timeZone),
              let due = answer.dueDateTime, !answer.isAllDay else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: due)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return (hour, minute)
    }

    /// The assignee a list whose default is `defaultAssigneeId` gives a new task — for a control
    /// that holds only that field. `nil` is the creator, `"unassigned"` nobody (the core's reading).
    static func assignee(listDefault defaultAssigneeId: String?, currentUserId: String?) -> String? {
        let probe = QuickAddList(id: "assignee", name: "", defaultAssigneeId: defaultAssigneeId)
        return (try? CoreRules.quickAddDefaults(list: probe, userId: currentUserId))?.assigneeId
    }

    private static func wire(_ list: TaskList) -> QuickAddList {
        QuickAddList(id: list.id, name: list.name, defaultPriority: list.defaultPriority,
                     defaultRepeating: list.defaultRepeating, defaultAssigneeId: list.defaultAssigneeId,
                     defaultDueDate: list.defaultDueDate, defaultDueTime: list.defaultDueTime,
                     defaultIsPrivate: list.defaultIsPrivate)
    }
}
