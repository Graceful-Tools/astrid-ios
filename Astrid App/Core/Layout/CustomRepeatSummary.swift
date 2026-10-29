import Foundation

/// Renders a custom repeating pattern as a sentence — "Every 2 weeks on Mon, Wed, from due date".
///
/// Extracted from `InlineRepeatPicker` (Task 42013da7) because the task detail needs the same
/// sentence: a custom repeat cannot describe itself in a chip. "Custom" says nothing, and the real
/// pattern does not fit beside a date and a time, so the detail gives it its own row — and that row
/// must word it EXACTLY as the picker does, or the same repeat reads two ways in one screen.
///
/// Mirrors `RepeatingTaskCalculator`'s vocabulary; the next-occurrence maths stays there.
enum CustomRepeatSummary {

    static func text(for pattern: CustomRepeatingPattern,
                     repeatFrom: Task.RepeatFromMode? = nil) -> String {
        let interval = pattern.interval ?? 1
        let unit = pattern.unit ?? "days"

        var summary = "Every \(interval) \(unit)"

        switch unit {
        case "weeks":
            if let weekdays = pattern.weekdays, !weekdays.isEmpty {
                summary += " on \(weekdays.map { $0.capitalized }.joined(separator: ", "))"
            }

        case "months":
            if pattern.monthRepeatType == "same_date", let day = pattern.monthDay {
                summary += " on the \(ordinal(day))"
            } else if pattern.monthRepeatType == "same_weekday", let monthWeekday = pattern.monthWeekday {
                summary += " on the \(weekOfMonth(monthWeekday.weekOfMonth)) \(monthWeekday.weekday.capitalized)"
            }

        case "years":
            if let month = pattern.month, let day = pattern.day {
                let months = [
                    "January", "February", "March", "April", "May", "June",
                    "July", "August", "September", "October", "November", "December"
                ]
                // Bounds-checked inline rather than via the `[safe:]` subscript — that extension
                // is not compiled into the Mac target, and this helper is shared with it.
                let index = month - 1
                let monthName = months.indices.contains(index) ? months[index] : "January"
                summary += " on \(monthName) \(ordinal(day))"
            }

        default:
            break
        }

        if pattern.endCondition == "after_occurrences", let count = pattern.endAfterOccurrences {
            summary += " (\(count)x)"
        } else if pattern.endCondition == "until_date", let endDate = pattern.endUntilDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            summary += " until \(formatter.string(from: endDate))"
        }

        if repeatFrom == .DUE_DATE {
            summary += ", from due date"
        }

        return summary
    }

    /// `weekOfMonth` -1 is "the last" (AITD-562, astrid-core AWTD-1295): it counts back from the
    /// month's last day. "The -1th Thursday" is not a sentence, so it reads as a word, not an ordinal.
    static let lastWeekOfMonth = -1

    static func weekOfMonth(_ week: Int) -> String {
        week == lastWeekOfMonth ? "last" : ordinal(week)
    }

    /// The week-of-month menu, in order. "Last" writes -1 and never 5: 5 walks into the next month
    /// when the month has only four of that weekday, -1 never leaves it.
    static let weekOfMonthChoices: [(value: Int, labelKey: String)] = [
        (1, "repeating.1st"), (2, "repeating.2nd"), (3, "repeating.3rd"),
        (4, "repeating.4th"), (5, "repeating.5th"), (lastWeekOfMonth, "repeating.last"),
    ]

    static func ordinal(_ num: Int) -> String {
        if num >= 11 && num <= 13 { return "\(num)th" }
        switch num % 10 {
        case 1: return "\(num)st"
        case 2: return "\(num)nd"
        case 3: return "\(num)rd"
        default: return "\(num)th"
        }
    }
}
