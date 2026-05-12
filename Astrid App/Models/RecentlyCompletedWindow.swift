import Foundation

/// Per-list "Recently completed" window configuration. Mirrors
/// `lib/recently-completed-window.ts` on the web. The same setting drives
/// both the list view's default completion filter and the board's Done
/// column, so the two views never disagree.
///
/// Stored on `TaskList.recentlyCompletedWindow` as JSON; `nil` means the
/// legacy 24-hour default.
///
/// JSON shapes (discriminated by `kind`):
/// - `{ "kind": "duration", "amount": Int, "unit": "hour"|"day"|"week"|"month" }`
/// - `{ "kind": "since-weekday", "weekday": 0...6 }`  (0 = Sunday)
/// - `{ "kind": "since-day-of-month", "day": 1...31 }`
/// - `{ "kind": "since-date", "date": "YYYY-MM-DD" }`
enum RecentlyCompletedWindow: Equatable, Hashable, Codable {
    enum DurationUnit: String, Codable, Equatable, Hashable {
        case hour, day, week, month
    }

    case duration(amount: Int, unit: DurationUnit)
    case sinceWeekday(weekday: Int)
    case sinceDayOfMonth(day: Int)
    case sinceDate(date: String)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind
        case amount
        case unit
        case weekday
        case day
        case date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "duration":
            let amount = try container.decode(Int.self, forKey: .amount)
            let unit = try container.decode(DurationUnit.self, forKey: .unit)
            self = .duration(amount: amount, unit: unit)
        case "since-weekday":
            let weekday = try container.decode(Int.self, forKey: .weekday)
            self = .sinceWeekday(weekday: weekday)
        case "since-day-of-month":
            let day = try container.decode(Int.self, forKey: .day)
            self = .sinceDayOfMonth(day: day)
        case "since-date":
            let date = try container.decode(String.self, forKey: .date)
            self = .sinceDate(date: date)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown RecentlyCompletedWindow kind: \(kind)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .duration(let amount, let unit):
            try container.encode("duration", forKey: .kind)
            try container.encode(amount, forKey: .amount)
            try container.encode(unit, forKey: .unit)
        case .sinceWeekday(let weekday):
            try container.encode("since-weekday", forKey: .kind)
            try container.encode(weekday, forKey: .weekday)
        case .sinceDayOfMonth(let day):
            try container.encode("since-day-of-month", forKey: .kind)
            try container.encode(day, forKey: .day)
        case .sinceDate(let date):
            try container.encode("since-date", forKey: .kind)
            try container.encode(date, forKey: .date)
        }
    }
}

// MARK: - Cutoff resolution

/// Returns the timestamp BEFORE which completed tasks should be hidden by
/// the "default" completion filter. `nil` window falls back to "24 hours
/// ago from now". Mirrors `getRecentlyCompletedCutoff` in
/// `lib/recently-completed-window.ts`.
func getRecentlyCompletedCutoff(
    _ window: RecentlyCompletedWindow?,
    now: Date = Date(),
    calendar: Calendar = .current
) -> Date {
    guard let window = window else {
        // Legacy 24h default
        return now.addingTimeInterval(-24 * 60 * 60)
    }

    switch window {
    case .duration(let amount, let unit):
        let seconds: TimeInterval
        switch unit {
        case .hour:
            seconds = TimeInterval(amount) * 60 * 60
        case .day:
            seconds = TimeInterval(amount) * 24 * 60 * 60
        case .week:
            seconds = TimeInterval(amount) * 7 * 24 * 60 * 60
        case .month:
            // Same approximation the web uses: 30 days.
            seconds = TimeInterval(amount) * 30 * 24 * 60 * 60
        }
        return now.addingTimeInterval(-seconds)

    case .sinceWeekday(let weekday):
        // Scroll back to the most-recent matching weekday at midnight.
        // weekday is 0=Sun..6=Sat (mirroring web). Calendar.component(.weekday)
        // returns 1=Sun..7=Sat, so we map: targetSwift = weekday + 1.
        let targetSwift = weekday + 1
        var components = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let currentWeekday = components.weekday else { return now }
        var delta = currentWeekday - targetSwift
        if delta < 0 { delta += 7 }
        // Midnight local time
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        let midnight = calendar.date(from: components) ?? now
        return calendar.date(byAdding: .day, value: -delta, to: midnight) ?? now

    case .sinceDayOfMonth(let day):
        // Most recent occurrence of the given day-of-month at midnight.
        // If today's day-of-month is < `day`, walk back to the previous month.
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        let currentDay = components.day ?? 1
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        if currentDay < day {
            // Roll back one month
            if let firstOfThisMonth = calendar.date(from: components),
               let previous = calendar.date(byAdding: .month, value: -1, to: firstOfThisMonth) {
                return previous
            }
        }
        return calendar.date(from: components) ?? now

    case .sinceDate(let dateString):
        // Parse YYYY-MM-DD as local midnight.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.date(from: dateString) ?? now
    }
}

/// True iff `task.completedAt` (falling back to `task.updatedAt` when the
/// dedicated column is nil) is on or after the cutoff. Mirrors
/// `isTaskRecentlyCompleted` on web.
func isTaskRecentlyCompleted(
    completedAt: Date?,
    updatedAt: Date?,
    window: RecentlyCompletedWindow?,
    now: Date = Date(),
    calendar: Calendar = .current
) -> Bool {
    let cutoff = getRecentlyCompletedCutoff(window, now: now, calendar: calendar)
    let timestamp = completedAt ?? updatedAt
    guard let timestamp = timestamp else { return false }
    return timestamp >= cutoff
}

/// Decides whether a completed task should appear under the given filter
/// mode. Mirrors `shouldShowCompletedByFilter` on web. Filter modes:
/// - "default": apply the recently-completed window
/// - "show": always show
/// - "hide": never show
/// - "all" / nil: defer to caller (return true)
func shouldShowCompletedByFilter(
    filterMode: String?,
    completedAt: Date?,
    updatedAt: Date?,
    window: RecentlyCompletedWindow?,
    now: Date = Date(),
    calendar: Calendar = .current
) -> Bool {
    switch filterMode {
    case "show", "all", nil:
        return true
    case "hide":
        return false
    case "default":
        return isTaskRecentlyCompleted(
            completedAt: completedAt,
            updatedAt: updatedAt,
            window: window,
            now: now,
            calendar: calendar
        )
    default:
        return true
    }
}
