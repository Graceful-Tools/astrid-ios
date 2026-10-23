import Foundation
import EventKit

/// Recurrence mapping between Astrid's repeat settings and `EKRecurrenceRule`, both ways.
/// What one direction drops, the export planner sees as a change and writes over the user's
/// reminder — `AppleRemindersSyncTests.testRecurrenceRoundTripLeavesTheReminderUnchanged`
/// holds the two directions to each other.
extension AppleRemindersService {

    /// Map Astrid recurrence to Apple recurrence rule
    func mapRecurrenceToApple(_ repeating: Task.Repeating?, data: CustomRepeatingPattern?) -> EKRecurrenceRule? {
        guard let repeating = repeating else { return nil }

        switch repeating {
        case .never:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        case .custom:
            return buildCustomRecurrenceRule(from: data)
        }
    }

    private func buildCustomRecurrenceRule(from pattern: CustomRepeatingPattern?) -> EKRecurrenceRule? {
        guard let pattern = pattern else { return nil }

        let frequency: EKRecurrenceFrequency
        switch pattern.unit {
        case "days": frequency = .daily
        case "weeks": frequency = .weekly
        case "months": frequency = .monthly
        case "years": frequency = .yearly
        default: return nil
        }

        let interval = pattern.interval ?? 1
        var end: EKRecurrenceEnd?

        if pattern.endCondition == "after_occurrences", let count = pattern.endAfterOccurrences {
            end = EKRecurrenceEnd(occurrenceCount: count)
        } else if pattern.endCondition == "until_date", let date = pattern.endUntilDate {
            end = EKRecurrenceEnd(end: date)
        }

        let days = (pattern.weekdays ?? []).compactMap(Self.appleWeekday)
        guard frequency == .weekly, !days.isEmpty else {
            return EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: end)
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency, interval: interval,
            daysOfTheWeek: days.map { EKRecurrenceDayOfWeek($0) },
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: nil, end: end)
    }

    /// Astrid's weekday names, in `EKWeekday` order (`.sunday` is 1).
    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    private static func appleWeekday(_ name: String) -> EKWeekday? {
        weekdayNames.firstIndex(of: name).flatMap { EKWeekday(rawValue: $0 + 1) }
    }

    private static func astridWeekday(_ day: EKWeekday) -> String? {
        weekdayNames.indices.contains(day.rawValue - 1) ? weekdayNames[day.rawValue - 1] : nil
    }

    /// Map Apple recurrence rule to Astrid recurrence
    func mapRecurrenceFromApple(_ rule: EKRecurrenceRule?) -> (Task.Repeating?, CustomRepeatingPattern?) {
        guard let rule = rule else { return (.never, nil) }

        // Simple patterns — only when nothing would be lost: an end or weekdays need a
        // custom pattern, or the next export writes an endless every-day series back.
        let weekdays = (rule.daysOfTheWeek ?? []).compactMap { Self.astridWeekday($0.dayOfTheWeek) }
        if rule.interval == 1, rule.recurrenceEnd == nil, weekdays.isEmpty {
            switch rule.frequency {
            case .daily: return (.daily, nil)
            case .weekly: return (.weekly, nil)
            case .monthly: return (.monthly, nil)
            case .yearly: return (.yearly, nil)
            @unknown default: return (.never, nil)
            }
        }

        // Custom pattern
        let unit: String
        switch rule.frequency {
        case .daily: unit = "days"
        case .weekly: unit = "weeks"
        case .monthly: unit = "months"
        case .yearly: unit = "years"
        @unknown default: return (.never, nil)
        }

        var endCondition = "never"
        var endAfterOccurrences: Int?
        var endUntilDate: Date?

        if let recurrenceEnd = rule.recurrenceEnd {
            if recurrenceEnd.occurrenceCount > 0 {
                endCondition = "after_occurrences"
                endAfterOccurrences = recurrenceEnd.occurrenceCount
            } else if let endDate = recurrenceEnd.endDate {
                endCondition = "until_date"
                endUntilDate = endDate
            }
        }

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: unit,
            interval: rule.interval,
            endCondition: endCondition,
            endAfterOccurrences: endAfterOccurrences,
            endUntilDate: endUntilDate,
            weekdays: rule.frequency == .weekly && !weekdays.isEmpty ? weekdays : nil
        )

        return (.custom, pattern)
    }
}
