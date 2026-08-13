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
        if calendar.isDateInToday(date) { return NSLocalizedString("time.today", comment: "") }
        if calendar.isDateInTomorrow(date) { return NSLocalizedString("time.tomorrow", comment: "") }

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
        guard let list,
              let date = NewTaskDefaults.dueDate(from: list.defaultDueDate,
                                                 time: list.defaultDueTime,
                                                 now: now, calendar: calendar)
        else { return nil }
        return label(for: date, now: now, calendar: calendar)
    }
}
#endif
