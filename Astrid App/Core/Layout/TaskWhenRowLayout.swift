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
//  The controls now WRAP: they share a line while there is room and fall to the
//  next when there is not (FlowLayout / FlowRows). An earlier version of this fix
//  assigned repeat to line two unconditionally — which cured the squeeze but spent
//  a second line even on a panel with space to spare. Where a control sits is a
//  function of the width available, not something to decide in advance.

import Foundation

/// A control on the "When" row.
enum TaskWhenControl: Equatable {
    case date
    case time
    case repeatPattern
}

enum TaskWhenRowLayout {
    /// The controls the row shows, in order. How they fall across lines is the
    /// layout's job, not this function's.
    ///
    /// Time and repeat need a date to attach to, so an undated task is a single
    /// "add a date" control rather than three inert ones.
    ///
    /// Repeat is ALWAYS present for a dated task. It used to be dropped when the
    /// repeat was custom, because the pattern then had a row of its own below —
    /// but once the chip started showing the pattern itself, dropping it meant a
    /// custom-repeating task displayed no repeat control at all. Both platforms'
    /// chips render the pattern, so there is nothing left for the exception to
    /// protect.
    static func controls(hasDate: Bool) -> [TaskWhenControl] {
        hasDate ? [.date, .time, .repeatPattern] : [.date]
    }
}
