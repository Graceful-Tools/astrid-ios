import Foundation

/// Repeating Task Handler — **canonical, single source of truth** for
/// next-occurrence calculation on iOS.
///
/// Handles the logic for calculating next occurrences of repeating tasks.
/// Implements both "Repeat from due date" and "Repeat from completion date" modes.
///
/// This mirrors the web implementation in `astrid-web/lib/repeating-task-handler.ts`
/// and `astrid-web/types/repeating.ts`. Keep the two in sync: when one changes,
/// update the other and mirror the corresponding tests.
///
/// ⚠️ Do NOT add pattern math anywhere else in the app. Call
/// `RepeatingTaskCalculator.calculateSimpleNextOccurrence` or
/// `calculateCustomNextOccurrence` from the single production entry point
/// (`TaskService.calculateNextOccurrence`). A previous inline implementation
/// in `TaskService` ignored `weekdays`, `monthRepeatType`, `monthWeekday`,
/// and the yearly `month`/`day` fields — weekly M/W/F patterns added 7 days
/// instead of picking the next selected weekday. The fix collapsed that
/// logic into this file.
///
/// When adding a new field to `CustomRepeatingPattern`:
/// 1. Teach this calculator to honor it.
/// 2. Add a test in `CustomRepeatingPatternTests.swift` that walks the
///    pattern through multiple completions.
/// 3. Add a matching test at the `TaskService.calculateNextOccurrence` level
///    so the production entry point is covered, not just the calculator in
///    isolation.
/// 4. Mirror the change in `astrid-web`.

// MARK: - Helper Extensions

extension Date {
    /// Add days to a date, preserving time (avoids DST issues by using milliseconds)
    func addingDays(_ days: Int) -> Date {
        return Date(timeIntervalSince1970: self.timeIntervalSince1970 + Double(days * 24 * 60 * 60))
    }

    /// Get the day of week (0 = Sunday, 6 = Saturday)
    var dayOfWeek: Int {
        let calendar = Calendar.current
        return calendar.component(.weekday, from: self) - 1
    }

    /// Get the day name
    var dayName: String {
        let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return days[dayOfWeek]
    }

    /// Set time components from another date while preserving the current date
    /// Uses UTC calendar to correctly handle all-day tasks (stored as UTC midnight)
    func settingTime(from other: Date) -> Date {
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        var components = utcCalendar.dateComponents([.year, .month, .day], from: self)
        let timeComponents = utcCalendar.dateComponents([.hour, .minute, .second, .nanosecond], from: other)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        components.nanosecond = timeComponents.nanosecond
        components.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: components) ?? self
    }
}

// MARK: - Simple Pattern End Condition

/// End condition data that can be used with simple repeating patterns
struct SimplePatternEndCondition {
    var endCondition: String  // "never", "after_occurrences", "until_date"
    var endAfterOccurrences: Int?
    var endUntilDate: Date?
}

// MARK: - Repeating Task Calculation

struct RepeatingTaskCalculator {
    /// Calculate next occurrence for a simple repeating task (daily, weekly, monthly, yearly)
    ///
    /// - Parameters:
    ///   - repeatingType: The type of repetition
    ///   - currentDueDate: The current due date (for time reference)
    ///   - completionDate: When the task was completed
    ///   - repeatFrom: Whether to repeat from due date or completion date
    ///   - currentOccurrenceCount: Current count of occurrences
    ///   - endData: Optional end condition data
    /// - Returns: Result with next due date, termination status, and new count
    static func calculateSimpleNextOccurrence(
        repeatingType: Task.Repeating,
        currentDueDate: Date?,
        completionDate: Date,
        repeatFrom: Task.RepeatFromMode,
        currentOccurrenceCount: Int = 0,
        endData: SimplePatternEndCondition? = nil
    ) -> (nextDueDate: Date?, shouldTerminate: Bool, newOccurrenceCount: Int) {
        // Determine anchor date based on repeat mode
        var anchorDate: Date

        if let currentDueDate = currentDueDate {
            // Determine which date to use based on mode
            let baseDate = repeatFrom == .DUE_DATE ? currentDueDate : completionDate

            // Create anchor with base date, preserving time from currentDueDate
            anchorDate = baseDate.settingTime(from: currentDueDate)
        } else {
            // Fallback if no currentDueDate
            anchorDate = completionDate
        }

        let calendar = Calendar.current
        var nextDate = anchorDate

        switch repeatingType {
        case .daily:
            // Add 1 day
            nextDate = anchorDate.addingDays(1)

        case .weekly:
            // Add 7 days
            nextDate = anchorDate.addingDays(7)

        case .monthly:
            // Add 1 month - Calendar automatically handles month-end clamping
            // (e.g., Jan 31 → Feb 28/29 in leap year, or Feb 28 in non-leap year)
            if let newDate = calendar.date(byAdding: .month, value: 1, to: anchorDate) {
                nextDate = newDate
            }

        case .yearly:
            // Add 1 year
            if let newDate = calendar.date(byAdding: .year, value: 1, to: anchorDate) {
                nextDate = newDate
            }

        default:
            break
        }

        // Increment occurrence count
        let newOccurrenceCount = currentOccurrenceCount + 1

        // Check end conditions if provided
        if let endData = endData {
            let endResult = checkSimplePatternEndCondition(
                nextDueDate: nextDate,
                newOccurrenceCount: newOccurrenceCount,
                endData: endData
            )
            return (
                endResult.shouldTerminate ? nil : nextDate,
                endResult.shouldTerminate,
                endResult.newOccurrenceCount
            )
        }

        return (nextDate, false, newOccurrenceCount)
    }

    /// Check if a simple repeating pattern should terminate based on end conditions
    ///
    /// - Parameters:
    ///   - nextDueDate: The calculated next due date
    ///   - newOccurrenceCount: The new occurrence count after this completion
    ///   - endData: End condition data
    /// - Returns: Result indicating if pattern should terminate and the new occurrence count
    static func checkSimplePatternEndCondition(
        nextDueDate: Date,
        newOccurrenceCount: Int,
        endData: SimplePatternEndCondition
    ) -> (shouldTerminate: Bool, newOccurrenceCount: Int) {
        // Check "never" condition
        if endData.endCondition == "never" {
            return (false, newOccurrenceCount)
        }

        // Check "after X occurrences" condition
        if endData.endCondition == "after_occurrences",
           let maxOccurrences = endData.endAfterOccurrences,
           newOccurrenceCount >= maxOccurrences {
            return (true, newOccurrenceCount)
        }

        // Check "until date" condition
        if endData.endCondition == "until_date",
           let endUntilDate = endData.endUntilDate {
            let calendar = Calendar.current
            let nextDateOnly = calendar.startOfDay(for: nextDueDate)
            let endDateOnly = calendar.startOfDay(for: endUntilDate)

            // Terminate if next occurrence is AFTER the end date (comparing dates only)
            if nextDateOnly > endDateOnly {
                return (true, newOccurrenceCount)
            }
        }

        // Continue repeating
        return (false, newOccurrenceCount)
    }

    /// Calculate next occurrence for a custom repeating pattern
    ///
    /// - Parameters:
    ///   - pattern: The custom repeating pattern
    ///   - currentDueDate: The current due date (for time reference)
    ///   - completionDate: When the task was completed
    ///   - repeatFrom: Whether to repeat from due date or completion date
    ///   - currentOccurrenceCount: Current count of occurrences
    /// - Returns: Result with next due date, termination status, and new count
    static func calculateCustomNextOccurrence(
        pattern: CustomRepeatingPattern,
        currentDueDate: Date?,
        completionDate: Date,
        repeatFrom: Task.RepeatFromMode,
        currentOccurrenceCount: Int
    ) -> (nextDueDate: Date?, shouldTerminate: Bool, newOccurrenceCount: Int) {
        // Increment occurrence count
        let newOccurrenceCount = currentOccurrenceCount + 1

        // Check if series should terminate based on end condition
        if pattern.endCondition == "after_occurrences",
           let maxOccurrences = pattern.endAfterOccurrences,
           newOccurrenceCount >= maxOccurrences {
            return (nil, true, newOccurrenceCount)
        }

        // Determine anchor date based on repeat mode
        var anchorDate: Date

        if let currentDueDate = currentDueDate {
            // Determine which date to use based on mode
            let baseDate = repeatFrom == .DUE_DATE ? currentDueDate : completionDate

            // Create anchor with base date, preserving time from currentDueDate
            anchorDate = baseDate.settingTime(from: currentDueDate)
        } else {
            // Fallback if no currentDueDate
            anchorDate = completionDate
        }

        // Calculate next occurrence based on pattern unit
        guard let unit = pattern.unit,
              let interval = pattern.interval else {
            return (nil, true, newOccurrenceCount)
        }

        var nextDate: Date?

        switch unit {
        case "days":
            nextDate = anchorDate.addingDays(interval)

        case "weeks":
            if let weekdays = pattern.weekdays {
                nextDate = getNextWeekdayOccurrence(from: anchorDate, weekdays: weekdays, interval: interval)
            }

        case "months":
            nextDate = getNextMonthOccurrence(from: anchorDate, pattern: pattern)

        case "years":
            nextDate = getNextYearOccurrence(from: anchorDate, pattern: pattern)

        default:
            break
        }

        guard let nextDueDate = nextDate else {
            return (nil, true, newOccurrenceCount)
        }

        // Check if next occurrence is past the until date
        // Compare dates only (not times) for "until date" condition
        // "Repeat until Dec 15" means tasks ON Dec 15 should still run
        if pattern.endCondition == "until_date",
           let endUntilDate = pattern.endUntilDate {
            let calendar = Calendar.current
            let nextDateOnly = calendar.startOfDay(for: nextDueDate)
            let endDateOnly = calendar.startOfDay(for: endUntilDate)

            // Terminate if next occurrence is AFTER the end date (comparing dates only)
            if nextDateOnly > endDateOnly {
                return (nil, true, newOccurrenceCount)
            }
        }

        return (nextDueDate, false, newOccurrenceCount)
    }

    // MARK: - Private Helpers

    private static func getNextWeekdayOccurrence(
        from date: Date,
        weekdays: [String],
        interval: Int
    ) -> Date {
        var currentDate = date

        // Find the next occurrence of any of the selected weekdays
        // Start from i=1 to skip the current day (for repeating tasks, we want the NEXT occurrence)
        for i in 1...7 {
            let testDate = currentDate.addingDays(i)
            if weekdays.contains(testDate.dayName) {
                return testDate
            }
        }

        // If no match found in current week, move to next week
        currentDate = currentDate.addingDays(7)
        return getNextWeekdayOccurrence(from: currentDate, weekdays: weekdays, interval: interval)
    }

    private static func getNextMonthOccurrence(
        from date: Date,
        pattern: CustomRepeatingPattern
    ) -> Date {
        let calendar = Calendar.current
        var result = date

        if pattern.monthRepeatType == "same_date" {
            // Same date every month
            if let newDate = calendar.date(byAdding: .month, value: pattern.interval ?? 1, to: result) {
                result = newDate
            }
        } else if pattern.monthRepeatType == "same_weekday",
                  let monthWeekday = pattern.monthWeekday {
            // Same weekday and week of month
            let targetDay = getDayNumber(for: monthWeekday.weekday)
            let weekOfMonth = monthWeekday.weekOfMonth

            // Move to next month
            if let newDate = calendar.date(byAdding: .month, value: pattern.interval ?? 1, to: result) {
                // Find the target weekday in the target week
                var components = calendar.dateComponents([.year, .month], from: newDate)
                components.day = 1
                if let firstDayOfMonth = calendar.date(from: components) {
                    let firstDayWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 1
                    let daysToAdd = (targetDay - firstDayWeekday + 7) % 7 + (weekOfMonth - 1) * 7
                    if let targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: firstDayOfMonth) {
                        result = targetDate
                    }
                }
            }
        }

        return result
    }

    private static func getNextYearOccurrence(
        from date: Date,
        pattern: CustomRepeatingPattern
    ) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        if let interval = pattern.interval {
            components.year = (components.year ?? 0) + interval
        }
        if let month = pattern.month {
            components.month = month
        }
        if let day = pattern.day {
            components.day = day
        }

        return calendar.date(from: components) ?? date
    }

    private static func getDayNumber(for dayName: String) -> Int {
        let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return days.firstIndex(of: dayName.lowercased()) ?? 0
    }
}
