//  DueDateQuickPicks.swift
//  The quick date and time choices, stated once for both platforms. (Task ea4f5124)
//
//  iOS kept these as private arrays inside InlineDatePicker and InlineTimePicker. That was fine
//  while iOS was the only place they existed — but the Mac detail offers a bare DatePicker with
//  no quick picks at all, and the obvious way to fix that is to retype the lists over there,
//  which is how two platforms come to disagree about what "Next week" means.
//
//  So they live here, shared, with the date arithmetic beside them. Both platforms read the
//  same list in the same order; a test pins the set, so adding an option on one platform cannot
//  silently skip the other.
//
//  ORDER MATTERS and is part of the contract: the CLEARING choice comes first ("No due date",
//  "All day"), because it is a choice like any other rather than a toolbar escape hatch — that
//  was a deliberate decision on iOS and the Mac has to inherit it, not re-litigate it.

import Foundation

enum DueDateQuickPicks {

    // MARK: - Dates

    struct DateOption: Equatable {
        /// Localisation key — never a literal, since these reach the screen on both platforms.
        let titleKey: String
        /// Whole days from today. 0 is today.
        let daysFromToday: Int
    }

    static let dateOptions: [DateOption] = [
        DateOption(titleKey: "picker.today", daysFromToday: 0),
        DateOption(titleKey: "picker.tomorrow", daysFromToday: 1),
        DateOption(titleKey: "picker.in_3_days", daysFromToday: 3),
        DateOption(titleKey: "picker.next_week", daysFromToday: 7)
    ]

    /// The date a quick pick means, in the USER'S calendar.
    ///
    /// Day arithmetic goes through `Calendar`, not by adding 86 400 seconds: across a DST
    /// boundary a "day" is 23 or 25 hours, and seconds-based maths lands "Tomorrow" on the wrong
    /// date twice a year. The time of day is preserved so picking a date does not silently
    /// discard a time the user already set.
    static func date(daysFromToday days: Int,
                     from now: Date,
                     calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: now) ?? now
    }

    // MARK: - Times

    struct TimeOption: Equatable {
        let titleKey: String
        /// 24-hour clock.
        let hour: Int
    }

    static let timeOptions: [TimeOption] = [
        TimeOption(titleKey: "picker.morning", hour: 9),
        TimeOption(titleKey: "picker.afternoon", hour: 14),
        TimeOption(titleKey: "picker.evening", hour: 18),
        TimeOption(titleKey: "picker.night", hour: 21)
    ]

    /// Set the hour on a date, zeroing minutes — "Morning" means 9:00, not 9:37.
    static func applying(hour: Int, to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }
}
