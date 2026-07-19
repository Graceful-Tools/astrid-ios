//  MacShortcutEffect.swift
//  Astrid for Mac — pure, testable mapping from a bare-key ShortcutAction to its effect.
//
//  Splits the 22 shared shortcut actions into two buckets:
//   • DATA effects (priority / due-date shifts / clear-due / unassign) — pure task mutations
//     that MacAppModel applies through TaskService. The date math lives here so it's unit-testable
//     without a running view (mirrors the RepeatingTaskCalculator pattern).
//   • FOCUS/navigation effects (rename, open, select prev/next, cycle list, focus a detail field)
//     — handled at the view level (MacRootView / MacTaskDetailView) since they touch UI state.
//
//  This is pure Foundation (no AppKit) so KeyboardShortcuts stays a testable contract.

import Foundation

enum MacShortcutEffect {

    /// A pure task-data mutation triggered by a bare key.
    enum DataEffect: Equatable {
        case priority(Int)        // 0/1/2/3
        case shiftDueDays(Int)    // ← -1, → +1, postpone +7
        case clearDueDate         // v  → sends the .distantPast clear sentinel
        case assignNoOne          // e  → sends "" (unassign sentinel)
    }

    /// A detail field a key should focus (jumpToDate/editLists/editDescription/addComment).
    enum FocusField: String, Equatable {
        case date, lists, description, comment
    }

    /// The data mutation for an action, or nil if the action is not a data mutation.
    static func dataEffect(for action: ShortcutAction) -> DataEffect? {
        switch action {
        case .priorityNone:   return .priority(0)
        case .priorityLow:    return .priority(1)
        case .priorityMedium: return .priority(2)
        case .priorityHigh:   return .priority(3)
        case .dueDateEarlier: return .shiftDueDays(-1)
        case .dueDateLater:   return .shiftDueDays(1)
        case .postpone:       return .shiftDueDays(7)
        case .removeDueDate:  return .clearDueDate
        case .assignNoOne:    return .assignNoOne
        default:              return nil
        }
    }

    /// The detail field an action should focus, or nil.
    static func focusField(for action: ShortcutAction) -> FocusField? {
        switch action {
        case .jumpToDate:      return .date
        case .editLists:       return .lists
        case .editDescription: return .description
        case .addComment:      return .comment
        default:               return nil
        }
    }

    /// New due date after a ±days shift. If the task has no due date, the shift is relative to
    /// `today` (web parity: shifting an undated task schedules it relative to now). All-day-safe:
    /// callers keep the task's existing `isAllDay`.
    static func shiftedDueDate(current: Date?, days: Int, calendar: Calendar = .current, today: Date) -> Date {
        let base = current ?? today
        return calendar.date(byAdding: .day, value: days, to: base) ?? base
    }
}
