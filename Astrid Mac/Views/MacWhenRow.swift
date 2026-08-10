//  MacWhenRow.swift
//  Astrid for Mac — the composition of the task detail's "When" row.
//
//  The row used to lead with a "Due Date" TOGGLE, so every task spent a line of
//  the panel saying the words "Due Date" whether or not it had one. Turning the
//  toggle on unfolded the apparatus INTO the pane: a date picker, a row of
//  Today/Tomorrow chips, a row of time chips and an "All day" toggle — so the
//  pane changed shape depending on a task's dates.
//
//  iOS has never worked that way. It shows a calendar glyph and ONE trigger
//  reading the date (or "No due date"), and everything else lives in the sheet
//  that trigger opens. This is that design, ported.
//
//  The composition is stated as data rather than left implicit in the view body,
//  because "the quick picks live in the popover, not the pane" is precisely the
//  kind of decision a later refactor undoes by accident. MacWhenRowTests pins it.

#if os(macOS)
import Foundation

//  The row's composition now comes from the SHARED `TaskWhenRowLayout`, which iOS
//  uses too — so the two platforms cannot disagree about what is on the row or
//  which line it sits on. The Mac's own `MacWhenControl` listed retired controls
//  (a due-date toggle, inline quick-pick rows, an All-day toggle) so their
//  absence could be asserted; the shared enum simply has no cases for them,
//  which is a stronger guarantee than a test.

// MARK: - Popover contents

/// A row in the due-date popover.
///
/// Order is contractual in one respect: among the CHOICES, clearing comes first
/// — matching iOS and the note in DueDateQuickPicks. The typed field leads the
/// popover because this is a Mac: there is a keyboard, and typing a date is
/// faster than hunting for it in a grid.
///
/// EXACTLY ONE calendar. An early version paired NSDatePicker's `.field` with a
/// graphical one, not realising `.field` brings a calendar of its own — two
/// calendars, overlapping. The typed field is now ours (MacDateEntry), so it
/// carries no calendar and the graphical one is the only one, sitting last.
enum MacDueDatePopoverRow: Equatable {
    case typedEntry
    case clear
    case quickPick(DueDateQuickPicks.DateOption)
    case calendar
}

enum MacDueDatePopover {
    static var rows: [MacDueDatePopoverRow] {
        [.typedEntry, .clear]
            + DueDateQuickPicks.dateOptions.map { .quickPick($0) }
            + [.calendar]
    }

    /// The calendars in the popover. There must be exactly one — two is a bug
    /// this control has already shipped once.
    static var calendars: [MacDueDatePopoverRow] {
        rows.filter { $0 == .calendar }
    }
}

/// The time popover, mirroring it. Clearing the time is what "all day" means
/// now — the standalone All-day toggle is gone, as on iOS, where a task with no
/// time IS an all-day task.
enum MacDueTimePopoverRow: Equatable {
    case clear
    case quickPick(DueDateQuickPicks.TimeOption)
    case clock
}

enum MacDueTimePopover {
    static var rows: [MacDueTimePopoverRow] {
        [.clear] + DueDateQuickPicks.timeOptions.map { .quickPick($0) } + [.clock]
    }
}

// MARK: - Splicing a day and a time

/// Converting between what the pickers show and what the task stores.
///
/// An ALL-DAY task stores midnight UTC (the Google Calendar convention the sync
/// layer follows); a TIMED task stores a real instant. A date picker, meanwhile,
/// always speaks the user's local calendar. Every crossing between the two needs
/// converting, and skipping one is how a task due the 8th displays as the 7th —
/// or silently moves a day when you set its time.
enum MacWhenDate {

    /// The calendar day of `day`, carrying the time of day from `timeFrom`.
    ///
    /// The date and time controls own different halves of one stored `Date`, so
    /// each must leave the other's half alone: picking "Tomorrow" on a task due
    /// at 15:00 keeps 15:00, and picking "Morning" keeps the day.
    static func combining(day: Date, timeFrom: Date?, calendar: Calendar = .current) -> Date {
        guard let timeFrom else { return day }
        let time = calendar.dateComponents([.hour, .minute, .second], from: timeFrom)
        return calendar.date(bySettingHour: time.hour ?? 0,
                             minute: time.minute ?? 0,
                             second: time.second ?? 0,
                             of: day) ?? day
    }

}

/// Whether a newly picked day should be stored as ALL-DAY.
///
/// The picker used to ask the TASK whether it was all-day. A task with no date at all
/// answered "no", so the day was combined with a time — and with no existing time to take,
/// it kept the clock time of the `Date()` it was built from. Every task you dated quietly
/// acquired a meaningless time like 3:55 AM (task 0b057b7a).
enum MacNewDueDate {
    static func isAllDay(existingDate: Date?, currentIsAllDay: Bool) -> Bool {
        // No date yet → all-day. There is no time to preserve, and inventing one from the
        // clock is never what picking a day meant.
        guard existingDate != nil else { return true }
        // Otherwise keep what the task already is: rescheduling a 9am meeting to tomorrow
        // must leave it at 9am.
        return currentIsAllDay
    }
}

extension MacWhenDate {
    private static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Storage form for an all-day task: midnight UTC on the LOCAL calendar day
    /// of `date`. Picking the 8th in the calendar must store the 8th, whatever
    /// the user's offset from UTC.
    static func utcMidnight(ofLocalDay date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return utcCalendar.date(from: components) ?? date
    }

    /// The inverse: the local-calendar date matching the UTC calendar day an
    /// all-day task is stored on, so a date picker highlights the right square.
    static func localDay(ofAllDay date: Date, calendar: Calendar = .current) -> Date {
        let day = utcCalendar.dateComponents([.year, .month, .day], from: date)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date
    }
}
#endif
