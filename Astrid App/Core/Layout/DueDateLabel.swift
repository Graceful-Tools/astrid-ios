//  DueDateLabel.swift
//  What a due-date control says, stated once for both platforms.
//
//  Sibling to DueDateQuickPicks, and shared for the same reason. iOS kept this
//  as a private `formatDate` inside InlineDatePicker; porting the iOS date
//  control to the Mac would have meant retyping 70 lines of timezone-sensitive
//  arithmetic, which is how two platforms come to disagree about which day a
//  task is due.
//
//  The subtlety worth knowing: an ALL-DAY date is stored at midnight UTC (the
//  Google Calendar convention the sync layer follows), so it must be read with
//  a UTC calendar. A TIMED date is a real instant and must be read with the
//  user's own calendar. Use the wrong one and a task due today reads as
//  "Yesterday" for every user west of UTC.

import Foundation

enum DueDateLabel {

    /// Text for a due-date trigger: the words "No due date", a named day
    /// ("Today"/"Tomorrow"/"Yesterday"), or a formatted date.
    ///
    /// `now` and `localCalendar` are injectable so the timezone behaviour can be
    /// tested rather than hoped for.
    static func text(for date: Date?,
                     isAllDay: Bool,
                     now: Date = Date(),
                     localCalendar: Calendar = .current) -> String {
        guard let date else {
            return NSLocalizedString("picker.no_due_date", comment: "No due date")
        }

        switch dayOffset(to: date, isAllDay: isAllDay, now: now, localCalendar: localCalendar) {
        case 0:  return NSLocalizedString("picker.today", comment: "Today")
        case 1:  return NSLocalizedString("picker.tomorrow", comment: "Tomorrow")
        case -1: return NSLocalizedString("time.yesterday", comment: "Yesterday")
        default: return formatted(date, isAllDay: isAllDay)
        }
    }

    /// Whole days from today to `date`, counted in whichever calendar the date
    /// is stored in.
    ///
    /// Not private: a quick-pick row needs it to decide which option carries the
    /// checkmark, and comparing dates by hand there is how the tick lands on the
    /// wrong row for anyone west of UTC.
    static func dayOffset(to date: Date,
                          isAllDay: Bool,
                          now: Date = Date(),
                          localCalendar: Calendar = .current) -> Int {
        guard isAllDay else {
            // A real instant: compare in the user's calendar.
            let today = localCalendar.startOfDay(for: now)
            let target = localCalendar.startOfDay(for: date)
            return localCalendar.dateComponents([.day], from: today, to: target).day ?? 0
        }

        // Stored at UTC midnight. Take TODAY as the user sees it, re-express that
        // calendar day as UTC midnight, and compare like with like.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let todayLocal = localCalendar.dateComponents([.year, .month, .day], from: now)
        var todayComponents = DateComponents()
        todayComponents.year = todayLocal.year
        todayComponents.month = todayLocal.month
        todayComponents.day = todayLocal.day
        todayComponents.hour = 0
        todayComponents.minute = 0
        todayComponents.second = 0

        guard let todayUTC = utc.date(from: todayComponents) else { return 0 }
        let stored = utc.dateComponents([.year, .month, .day], from: date)
        let storedUTC = utc.date(from: stored) ?? date
        return utc.dateComponents([.day], from: todayUTC, to: storedUTC).day ?? 0
    }

    /// A date far enough out to need its own name. All-day dates format in UTC
    /// for the same reason they compare in it — otherwise a 25 December task
    /// prints as the 24th west of UTC.
    private static func formatted(_ date: Date, isAllDay: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if isAllDay { formatter.timeZone = TimeZone(identifier: "UTC") }
        return formatter.string(from: date)
    }
}
