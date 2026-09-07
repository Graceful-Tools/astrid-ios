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

        return relativeDayName(for: date, isAllDay: isAllDay, now: now, localCalendar: localCalendar)
            ?? formatted(date, isAllDay: isAllDay)
    }

    /// "Today" / "Tomorrow" / "Yesterday" — or nil when the date is far enough out to need a real
    /// format. The caller supplies that format, because a task row, a chat separator and a date
    /// picker each want a different one; what they must NOT each supply is this decision.
    ///
    /// Five surfaces used to hand-roll it, and every one of them got the all-day case wrong or
    /// wrote the three words as English literals (AITD-317). Keys are the `time.*` family, which
    /// is the complete one — `picker.today` / `picker.tomorrow` translate identically in all 12
    /// languages but have no yesterday.
    static func relativeDayName(for date: Date,
                                isAllDay: Bool,
                                now: Date = Date(),
                                localCalendar: Calendar = .current) -> String? {
        switch dayOffset(to: date, isAllDay: isAllDay, now: now, localCalendar: localCalendar) {
        case 0:  return NSLocalizedString("time.today", comment: "Today")
        case 1:  return NSLocalizedString("time.tomorrow", comment: "Tomorrow")
        case -1: return NSLocalizedString("time.yesterday", comment: "Yesterday")
        default: return nil
        }
    }

    /// The timezone a date of this kind must be READ in.
    ///
    /// All-day dates are stored at midnight UTC, so formatting one in the user's zone prints the
    /// wrong day for everyone west of UTC — a 25 December task shows as the 24th. nil means "the
    /// user's own zone", which is right for a timed date because that is a real instant.
    static func displayTimeZone(isAllDay: Bool) -> TimeZone? {
        isAllDay ? TimeZone(identifier: "UTC") : nil
    }

    /// Compact text for a task row: a day name, else a short date ("12 Mar").
    static func rowText(for date: Date,
                        isAllDay: Bool,
                        now: Date = Date(),
                        localCalendar: Calendar = .current) -> String {
        if let name = relativeDayName(for: date, isAllDay: isAllDay, now: now, localCalendar: localCalendar) {
            return name
        }
        let formatter = DateFormatter()
        // A localized TEMPLATE, not a literal pattern, so the field order follows the locale.
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        formatter.timeZone = displayTimeZone(isAllDay: isAllDay)
        return formatter.string(from: date)
    }

    /// Fuller text for a task row that has room: a day name, else a medium date, plus the time of
    /// day when the task actually has one.
    static func rowMediumText(for date: Date,
                           isAllDay: Bool,
                           now: Date = Date(),
                           localCalendar: Calendar = .current) -> String {
        let time: String
        if isAllDay {
            time = ""
        } else {
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            time = " " + timeFormatter.string(from: date)
        }

        if let name = relativeDayName(for: date, isAllDay: isAllDay, now: now, localCalendar: localCalendar) {
            return name + time
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = displayTimeZone(isAllDay: isAllDay)
        return formatter.string(from: date) + time
    }

    /// The heading over a day's worth of chat messages: "Today", "Yesterday", else the weekday and
    /// date. Chat timestamps are real instants, so there is no all-day case here.
    static func dayHeading(for date: Date,
                           now: Date = Date(),
                           localCalendar: Calendar = .current) -> String {
        // Tomorrow cannot happen for a message that has already been sent, and reading "Tomorrow"
        // over a clock-skewed message would be worse than a date.
        if let name = relativeDayName(for: date, isAllDay: false, now: now, localCalendar: localCalendar),
           name != NSLocalizedString("time.tomorrow", comment: "Tomorrow") {
            return name
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMM d")
        return formatter.string(from: date)
    }

    /// A single chat message's timestamp: the time alone if it is from today, "Yesterday", else
    /// the date and time together.
    static func timestamp(for date: Date,
                          now: Date = Date(),
                          localCalendar: Calendar = .current) -> String {
        let offset = dayOffset(to: date, isAllDay: false, now: now, localCalendar: localCalendar)

        if offset == 0 {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        if offset == -1 {
            return NSLocalizedString("time.yesterday", comment: "Yesterday")
        }

        let formatter = DateFormatter()
        // .medium + .short joins them the way the locale does, rather than with an English "at".
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

    /// A date far enough out to need its own name.
    ///
    /// Carries the DAY OF WEEK: "Aug 12, 2026" tells you when in the abstract,
    /// but what you actually want to know when scheduling is whether that's a
    /// Wednesday or a Saturday, and nothing else on the row says so. Today,
    /// Tomorrow and Yesterday don't need it — they already answer the question.
    ///
    /// The format comes from a localised TEMPLATE, not a literal pattern, so the
    /// field order follows the user's locale rather than an American one.
    ///
    /// All-day dates format in UTC for the same reason they compare in it —
    /// otherwise a 25 December task prints as the 24th west of UTC.
    private static func formatted(_ date: Date, isAllDay: Bool) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d yyyy")
        if isAllDay { formatter.timeZone = TimeZone(identifier: "UTC") }
        return formatter.string(from: date)
    }
}
