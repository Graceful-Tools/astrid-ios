import Foundation
import EventKit

/// Value snapshot of the reminder fields the Apple export writes
/// (`updateReminder(_:from:)`). Export compares the reminder's current
/// snapshot against the task's desired one and ONLY writes on a real
/// difference.
///
/// Why this exists: the export used to rewrite every mapped reminder on every
/// pass. Each commit fired `EKEventStoreChanged` for our own write, which
/// rescheduled auto-sync — an endless ~2s loop that runs even in airplane mode
/// (EventKit is local). Worse, every rewrite bumped `lastModifiedDate`, which
/// held the import half's "Reminders is newer" gate permanently open: a
/// disagreeing pair re-applied on every pass (a completed reminder re-completed
/// a rolled-forward repeating task, marching its due date ahead 2s at a time),
/// visibly reshuffling the task list — the "My Tasks flickers" bug.
struct AppleReminderSnapshot: Equatable {
    var title: String
    var notes: String?
    var isCompleted: Bool
    var priority: Int
    var dueKey: String?
    var recurrenceKey: String?
    var alarmKey: String?
}

enum AppleExportPlanner {

    /// A quiescent pair (snapshots equal) MUST NOT be written: no save, no
    /// commit, no `EKEventStoreChanged` echo, no `lastModifiedDate` bump.
    static func needsWrite(current: AppleReminderSnapshot, desired: AppleReminderSnapshot) -> Bool {
        current != desired
    }

    /// Normalized key for due-date components — compares exactly what
    /// `updateReminder` sets (y/m/d, plus h:m for timed dues), ignoring
    /// calendar/timezone noise EventKit attaches on read.
    static func dueKey(_ components: DateComponents?) -> String? {
        guard let components else { return nil }
        var key = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        if components.hour != nil || components.minute != nil {
            key += " \(components.hour ?? 0):\(components.minute ?? 0)"
        }
        return key
    }

    /// Fingerprint of a recurrence rule (frequency, interval, weekdays, end).
    static func recurrenceKey(_ rule: EKRecurrenceRule?) -> String? {
        guard let rule else { return nil }
        var key = "f\(rule.frequency.rawValue)i\(rule.interval)"
        if let days = rule.daysOfTheWeek, !days.isEmpty {
            key += "d" + days.map { String($0.dayOfTheWeek.rawValue) }.sorted().joined(separator: ",")
        }
        if let end = rule.recurrenceEnd {
            if end.occurrenceCount > 0 { key += "c\(end.occurrenceCount)" }
            if let until = end.endDate { key += "u\(Int(until.timeIntervalSince1970))" }
        }
        return key
    }

    /// Fingerprint of the absolute-date alarms `updateReminder` manages.
    static func alarmKey(_ alarms: [EKAlarm]?) -> String? {
        let dates = (alarms ?? []).compactMap(\.absoluteDate)
        guard !dates.isEmpty else { return nil }
        return dates.map { String(Int($0.timeIntervalSince1970)) }.sorted().joined(separator: ",")
    }

    static func alarmKey(reminderTime: Date?) -> String? {
        reminderTime.map { String(Int($0.timeIntervalSince1970)) }
    }
}
