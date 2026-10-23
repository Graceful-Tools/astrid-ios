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
// Marked `nonisolated` so its Codable conformance is usable from nonisolated contexts —
// notably where astrid-core's answers are decoded, off the main actor (AITD-320). It holds only
// value-type fields, so it is inherently thread-safe.
nonisolated enum RecentlyCompletedWindow: Equatable, Hashable, Codable {
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

    // `nonisolated` so the Codable conformance can be used from
    // nonisolated contexts — notably CDTaskList's Core Data encode/
    // decode. Under the project's default main-actor isolation a
    // *custom* init(from:)/encode(to:) would otherwise be main-actor
    // isolated (synthesized conformances are exempt; hand-written ones
    // are not), which is an error in the Swift 6 language mode.
    nonisolated init(from decoder: Decoder) throws {
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

    /// The dictionary form for an `updateListAdvanced` payload (task 545812e6).
    ///
    /// Built from the SAME kind strings and keys as `encode(to:)` below, because the two must
    /// agree: the app writes with this and reads back with that. Both platforms use it, so the
    /// Mac cannot invent a second wire shape.
    nonisolated var updatePayloadValue: [String: Any] {
        switch self {
        case .duration(let amount, let unit):
            return ["kind": "duration", "amount": amount, "unit": unit.rawValue]
        case .sinceWeekday(let weekday):
            return ["kind": "since-weekday", "weekday": weekday]
        case .sinceDayOfMonth(let day):
            return ["kind": "since-day-of-month", "day": day]
        case .sinceDate(let date):
            return ["kind": "since-date", "date": date]
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
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
