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

/// A control the When row may show. The cases the row must NEVER contain are
/// declared too — a test asserting the absence of something needs a name for it.
enum MacWhenControl: Equatable {
    case date
    case time
    case repeatPattern

    // Retired. Present so their absence is checkable, and so re-adding one is a
    // deliberate act with a failing test attached.
    case dueDateToggle
    case dateQuickPicks
    case timeQuickPicks
    case allDayToggle
}

enum MacWhenRow {
    /// The controls on the row, in order. Time and repeat need a date to attach
    /// to, so an undated task shows one trigger rather than three inert controls.
    static func controls(hasDate: Bool) -> [MacWhenControl] {
        hasDate ? [.date, .time, .repeatPattern] : [.date]
    }
}

// MARK: - Popover contents

/// A row in the due-date popover. Order is contractual: the CLEARING choice
/// comes first, matching iOS and the note in DueDateQuickPicks.
enum MacDueDatePopoverRow: Equatable {
    case clear
    case quickPick(DueDateQuickPicks.DateOption)
    case calendar
}

enum MacDueDatePopover {
    static var rows: [MacDueDatePopoverRow] {
        [.clear] + DueDateQuickPicks.dateOptions.map { .quickPick($0) } + [.calendar]
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
