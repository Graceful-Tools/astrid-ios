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

import AstridCore
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
        case .some(0):  return NSLocalizedString("time.today", comment: "Today")
        case .some(1):  return NSLocalizedString("time.tomorrow", comment: "Tomorrow")
        case .some(-1): return NSLocalizedString("time.yesterday", comment: "Yesterday")
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
        // A localized TEMPLATE, not a literal pattern, so the field order follows the locale.
        return DateFormatterCache.formatter(.template("MMM d"), timeZone: displayTimeZone(isAllDay: isAllDay))
            .string(from: date)
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
            time = " " + DateFormatterCache.formatter(.styles(date: .none, time: .short)).string(from: date)
        }

        if let name = relativeDayName(for: date, isAllDay: isAllDay, now: now, localCalendar: localCalendar) {
            return name + time
        }

        return DateFormatterCache.formatter(.styles(date: .medium, time: .none),
                                            timeZone: displayTimeZone(isAllDay: isAllDay))
            .string(from: date) + time
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
        return DateFormatterCache.formatter(.template("EEEE MMM d")).string(from: date)
    }

    /// A single chat message's timestamp: the time alone if it is from today, "Yesterday", else
    /// the date and time together.
    static func timestamp(for date: Date,
                          now: Date = Date(),
                          localCalendar: Calendar = .current) -> String {
        let offset = dayOffset(to: date, isAllDay: false, now: now, localCalendar: localCalendar)

        if offset == 0 {
            return DateFormatterCache.formatter(.styles(date: .none, time: .short)).string(from: date)
        }
        if offset == -1 {
            return NSLocalizedString("time.yesterday", comment: "Yesterday")
        }

        // .medium + .short joins them the way the locale does, rather than with an English "at".
        return DateFormatterCache.formatter(.styles(date: .medium, time: .short)).string(from: date)
    }

    /// Whole days from today to `date`, counted in whichever calendar the date
    /// is stored in. Nil when the core could not answer — every caller then
    /// falls back to a written-out date, never a guessed "Today".
    ///
    /// Not private: a quick-pick row needs it to decide which option carries the
    /// checkmark, and comparing dates by hand there is how the tick lands on the
    /// wrong row for anyone west of UTC.
    ///
    /// Asked of astrid-core (`dayOffset`, `rows::day_offset`; AWTD2-216, AITD-622) — the same
    /// arithmetic every core-drawn due label uses. The core reads both instants at ONE offset
    /// from UTC, so a timed date on the far side of a daylight-saving change is moved by the
    /// difference first: its day is then the one the user's own calendar gives it.
    static func dayOffset(to date: Date,
                          isAllDay: Bool,
                          now: Date = Date(),
                          localCalendar: Calendar = .current) -> Int? {
        let zone = localCalendar.timeZone
        let nowOffset = zone.secondsFromGMT(for: now)
        let asked = isAllDay
            ? date
            : date.addingTimeInterval(TimeInterval(zone.secondsFromGMT(for: date) - nowOffset))
        return CoreRules.dayOffset(to: asked, isAllDay: isAllDay, now: now,
                                   utcOffsetMinutes: nowOffset / 60)
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
        DateFormatterCache.formatter(.template("EEE MMM d yyyy"), timeZone: displayTimeZone(isAllDay: isAllDay))
            .string(from: date)
    }
}
