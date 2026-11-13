import Foundation

/// A new DAY picked for a task that has a TIME: the task moves to that day and keeps its time
/// (AITD-635).
///
/// The date picker's quick picks are astrid-core's answer, and each one is the reader's calendar
/// day stored the way an all-day date is stored: UTC midnight. Task details used to put that value
/// straight into a TIMED task's date. West of UTC, "Tomorrow" at UTC midnight is still this
/// afternoon locally, so the date chip went on showing the old day, and the next time edit took its
/// day from it and wrote the old day back to the server. That was the reported revert.
nonisolated enum DayPick {

    /// The instant a timed task moves to when `day` is picked: that calendar day, at the hour and
    /// minute `existing` already had, in `calendar`'s time zone.
    ///
    /// - Parameter dayIsUTCMidnight: true for a quick pick (the day is read in UTC, where it was
    ///   written); false for the calendar's own pick, a local instant whose day is read locally.
    static func keepingTime(of existing: Date, on day: Date, dayIsUTCMidnight: Bool,
                            calendar: Calendar = .current) -> Date {
        var dayCalendar = Calendar(identifier: .gregorian)
        dayCalendar.timeZone = dayIsUTCMidnight ? TimeZone(identifier: "UTC")! : calendar.timeZone
        let picked = dayCalendar.dateComponents([.year, .month, .day], from: day)
        let time = calendar.dateComponents([.hour, .minute, .second], from: existing)

        var combined = DateComponents()
        combined.year = picked.year
        combined.month = picked.month
        combined.day = picked.day
        combined.hour = time.hour
        combined.minute = time.minute
        combined.second = time.second
        return calendar.date(from: combined) ?? day
    }
}
