import Foundation

/// A weekly custom repeat always names a day (AITD-550).
///
/// The shared rule — web `types/repeating.ts`, astrid-core — ends a weekly series that names no
/// weekday rather than guess one, so "every 4 weeks" saved without a day completed once and never
/// came back. Web's editor refuses to save such a pattern (`isValidRepeatingPattern`); the iOS
/// editor saved it whenever no day had been tapped, and the Mac editor had no day control at all.
///
/// One answer for both editors: when no day was picked, the day is the due date's — read in UTC
/// for an all-day task, whose date is a UTC midnight and whose weekday the core reads in UTC — or
/// today's when there is no due date.
extension CustomRepeatingPattern {

    /// The wire names, Sunday first to match `Calendar`'s weekday numbering (1 = Sunday).
    static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    func requiringWeekday(dueDate: Date?, isAllDay: Bool,
                          timeZone: TimeZone = .current, now: Date = Date()) -> CustomRepeatingPattern {
        guard unit == "weeks", (weekdays ?? []).isEmpty else { return self }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dueDate != nil && isAllDay ? TimeZone(identifier: "UTC")! : timeZone
        let weekday = calendar.component(.weekday, from: dueDate ?? now)
        var filled = self
        filled.weekdays = [Self.weekdayNames[weekday - 1]]
        return filled
    }
}
