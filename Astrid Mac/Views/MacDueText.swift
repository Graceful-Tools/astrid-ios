//  MacDueText.swift
//  The due date as a Mac list row or board card shows it — one helper for both (AITD-520).

import Foundation

enum MacDueText {

    /// Text for the due date on a row or a card: a day name, else the medium date
    /// ("Oct 3, 2027"), plus the time when the task has one.
    static func text(for due: Date?,
                     isAllDay: Bool,
                     now: Date = Date(),
                     localCalendar: Calendar = .current) -> String? {
        guard let due else { return nil }
        // The board card used to draw `Text(due, style: .date)` — the long style ("October 3, 2027"),
        // read in the user's zone, so an all-day card showed the day before west of UTC (AITD-520).
        return DueDateLabel.rowMediumText(for: due, isAllDay: isAllDay, now: now, localCalendar: localCalendar)
    }
}
