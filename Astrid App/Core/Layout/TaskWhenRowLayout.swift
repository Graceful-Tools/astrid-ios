//  TaskWhenRowLayout.swift
//  How the task detail's "When" controls are arranged across lines.
//
//  Date, time and repeat used to be one HStack. Each chip sizes to its own
//  content and refuses to compress, so the row demanded the sum of all three —
//  and on a phone, inside a labelled row, that is more width than exists. The
//  last chip was pushed off.
//
//  It survived only because the text happened to be short. Giving the date its
//  weekday ("Wed, Aug 12, 2026") is what tipped it over, and the TIME vanished.
//  A layout that holds only while the content stays small is not holding.
//
//  Repeat now wraps to its own line — the way a custom repeat's pattern already
//  did — so date and time keep the first line and the time can't be crowded out.

import Foundation

/// A control on the "When" row.
enum TaskWhenControl: Equatable {
    case date
    case time
    case repeatPattern
}

enum TaskWhenRowLayout {
    /// The controls, grouped into lines.
    ///
    /// Time and repeat need a date to attach to, so an undated task is a single
    /// "add a date" control rather than three inert ones. A CUSTOM repeat is
    /// omitted here: it already has a row of its own below showing the real
    /// pattern, and a "Custom" chip would be a second, less informative control
    /// for the same thing (42013da7).
    static func lines(hasDate: Bool, isCustomRepeat: Bool) -> [[TaskWhenControl]] {
        guard hasDate else { return [[.date]] }
        let first: [TaskWhenControl] = [.date, .time]
        return isCustomRepeat ? [first] : [first, [.repeatPattern]]
    }
}
