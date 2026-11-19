//  DoneSince.swift
//  Astrid — how far back a board's Done column goes, iOS and Mac alike (ADEV-131).
//
//  Jon, 2026-11-19: "add a 'since x date' on the Done count… with a quick way to tap and pick the
//  date to go back to… saved per-list-per user". The header reads "Done · 15 ✓ This week": the
//  count is the Done cards finished since the period started, and the cards are those same ones.
//  Quick picks look backwards — Today, This week (Monday–Sunday, whatever the locale's first
//  weekday), This month, This year — then a picked date, or All time. Presets roll with the clock;
//  a picked date stays until it is changed. A card's time is `CompletedOnLabel.completedAt` — the
//  stamp its date pill shows and astrid-core sorts Done by. Saved on the device, per person and
//  list, which the task allows ("can be on the interface").

import Foundation

enum DoneSince: Equatable, Hashable {
    case today
    case thisWeek
    case thisMonth
    case thisYear
    /// Since the start of this day.
    case date(Date)
    case all

    /// Where a board starts before its person picks anything.
    static let `default`: DoneSince = .thisWeek

    /// The quick picks, in menu order.
    static let presets: [DoneSince] = [.today, .thisWeek, .thisMonth, .thisYear]

    /// The first moment counted, or nil for All time.
    func start(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .thisWeek:
            var monday = calendar
            monday.firstWeekday = 2
            return monday.dateInterval(of: .weekOfYear, for: now)?.start
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)?.start
        case .date(let day):
            return calendar.startOfDay(for: day)
        case .all:
            return nil
        }
    }

    /// The Done cards finished since the start, in their order. Open tasks never count.
    func filter(_ tasks: [Task], now: Date = Date(), calendar: Calendar = .current) -> [Task] {
        let start = start(now: now, calendar: calendar)
        return tasks.filter { task in
            guard let finished = CompletedOnLabel.completedAt(task) else { return false }
            guard let start else { return true }
            return finished >= start
        }
    }

    /// "This week", "since Sun, Nov 1" (the year only when it is not this year), "All time".
    func label(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch self {
        case .today: return NSLocalizedString("time.today", comment: "")
        case .thisWeek: return NSLocalizedString("time.this_week", comment: "")
        case .thisMonth: return NSLocalizedString("time.this_month", comment: "")
        case .thisYear: return NSLocalizedString("board.done_since.this_year", comment: "")
        case .all: return NSLocalizedString("board.done_since.all_time", comment: "")
        case .date(let day):
            let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
            var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                         timeZone: calendar.timeZone)
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
            if !sameYear { style = style.year() }
            return String(format: NSLocalizedString("board.done_since.since_date", comment: ""),
                          day.formatted(style))
        }
    }

    /// The header's count: "15 ✓ This week" — the same plain U+2713 check as the card's pill.
    static func headerText(count: Int, label: String) -> String {
        String(format: NSLocalizedString("board.done_since.header", comment: ""), count, label)
    }

    /// What VoiceOver reads for the header's count: "15 done, This week".
    static func accessibilityLabel(count: Int, label: String) -> String {
        String(format: NSLocalizedString("board.done_since.accessibility", comment: ""), count, label)
    }

    // MARK: - Saved per person and list

    private static func key(listId: String, userId: String?) -> String {
        "board.doneSince.\(userId ?? "anonymous").\(listId)"
    }

    /// What is stored: a preset's name, or a picked day's seconds since 1970.
    private var stored: String {
        switch self {
        case .today: return "today"
        case .thisWeek: return "week"
        case .thisMonth: return "month"
        case .thisYear: return "year"
        case .all: return "all"
        case .date(let day): return "date:\(day.timeIntervalSince1970)"
        }
    }

    private init?(stored: String) {
        switch stored {
        case "today": self = .today
        case "week": self = .thisWeek
        case "month": self = .thisMonth
        case "year": self = .thisYear
        case "all": self = .all
        default:
            guard stored.hasPrefix("date:"),
                  let seconds = TimeInterval(stored.dropFirst("date:".count)) else { return nil }
            self = .date(Date(timeIntervalSince1970: seconds))
        }
    }

    static func load(listId: String, userId: String?, defaults: UserDefaults = .standard) -> DoneSince {
        defaults.string(forKey: key(listId: listId, userId: userId)).flatMap(DoneSince.init(stored:)) ?? .default
    }

    func save(listId: String, userId: String?, defaults: UserDefaults = .standard) {
        defaults.set(stored, forKey: Self.key(listId: listId, userId: userId))
    }
}
