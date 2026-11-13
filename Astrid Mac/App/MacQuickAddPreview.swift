//  MacQuickAddPreview.swift
//  What the quick-add bar SHOWS about the task it is about to create (Task 3d47cb62).
//
//  The bar already previews the list's default priority, repeat and assignee on its leading
//  checkbox. The default due date was the one it applied silently: a list defaulting to "tomorrow"
//  gave no hint before you pressed Return, and the first time you found out was when the task
//  appeared with a date you did not type.
//
//  Pure and separate from the view so the label can be asserted — in particular that it describes
//  the SAME date the task will actually get. A preview that disagrees with what gets applied is
//  worse than no preview.

#if os(macOS)
import Foundation

enum MacQuickAddPreview {

    /// Short, row-style date text ("Tomorrow", "Fri", "12 Mar"), matching how a task row reads.
    static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        // The day naming is SHARED (AITD-317) rather than re-compared here. `dueDateLabel` hands
        // over a local date (an all-day default already moved onto the reader's day), so
        // `isAllDay: false` is the correct reading — but the words themselves must come from one place, or the quick-add
        // bar and the row it previews can disagree about what to call the same day.
        if let name = DueDateLabel.relativeDayName(for: date, isAllDay: false,
                                                   now: now, localCalendar: calendar),
           name != NSLocalizedString("time.yesterday", comment: "") {
            return name
        }

        let formatter = DateFormatter()
        // Inside the coming week a weekday is the most readable; beyond that it is ambiguous.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        formatter.setLocalizedDateFormatFromTemplate((1...6).contains(days) ? "EEE" : "d MMM")
        return formatter.string(from: date)
    }

    /// The label for a list's default due date, or nil when it has none — nil so the chip is absent
    /// entirely rather than showing an empty slot. `nil` list = My Tasks, which has no defaults.
    static func dueDateLabel(for list: TaskList?, now: Date = Date(),
                             calendar: Calendar = .current) -> String? {
        guard let list else { return nil }
        let defaults = ListQuickAddDefaults.resolve(list, currentUserId: nil, now: now,
                                                    timeZone: calendar.timeZone)
        guard let due = defaults.dueDateTime else { return nil }
        // An all-day answer is the day at UTC midnight; label the reader's own day for it.
        let date = defaults.isAllDay ? MacWhenDate.localDay(ofAllDay: due, calendar: calendar) : due
        return label(for: date, now: now, calendar: calendar)
    }
}
#endif
