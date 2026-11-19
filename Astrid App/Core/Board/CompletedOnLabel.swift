//  CompletedOnLabel.swift
//  Astrid — the completed date a Done card shows as a pill under its title, iOS and Mac alike.
//
//  Jon, 2026-11-19: "show the completed date under the title as a pill… consistent on all
//  platforms". The day is when the task was finished — `completedAt`, else `updatedAt` for a task
//  finished before the stamp existed — in the reader's zone, the same stamp astrid-core sorts the
//  Done column by (newest on top) and sends other clients as a row's `completedOn` (CONTRACTS D43).
//  Written as the locale's short month and day, with the year only when it is not this year.

import Foundation

enum CompletedOnLabel {
    /// When `task` was finished; nil while it is open.
    static func completedAt(_ task: Task) -> Date? {
        guard task.completed else { return nil }
        return task.completedAt ?? task.updatedAt
    }

    /// "Nov 19", or "Nov 19, 2025" for another year, in `locale`.
    static func text(for date: Date,
                     now: Date = Date(),
                     calendar: Calendar = .current,
                     locale: Locale = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
            .month(.abbreviated)
            .day()
        if !sameYear { style = style.year() }
        return date.formatted(style)
    }

    /// The pill's text for `task`, or nil when it has none to show.
    static func text(for task: Task, now: Date = Date(),
                     calendar: Calendar = .current, locale: Locale = .current) -> String? {
        completedAt(task).map { text(for: $0, now: now, calendar: calendar, locale: locale) }
    }

    /// What VoiceOver reads: "Completed Nov 19".
    static func accessibilityLabel(_ text: String) -> String {
        String(format: NSLocalizedString("board.card.completed_on", comment: ""), text)
    }
}
