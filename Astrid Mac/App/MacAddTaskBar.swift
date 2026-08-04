//  MacAddTaskBar.swift
//  Astrid for Mac — pure rule for the floating Add-task bar (Task bf998f4e).

#if os(macOS)
import Foundation

enum MacAddTaskBar {
    /// The bottom quick-add bar shows for a real list AND for My Tasks, matching iOS: adding from
    /// My Tasks creates a task with NO list (unless the text names one with #list), which still
    /// lands in My Tasks because that view shows tasks that are mine or unassigned.
    ///
    /// Search is not a list — there is nothing to add into — and a saved-filter list owns no real
    /// tasks either, so both stay hidden.
    static func isVisible(isVirtualSelection: Bool, hasSelection: Bool, isMyTasks: Bool = false) -> Bool {
        guard hasSelection else { return false }
        return isMyTasks || !isVirtualSelection
    }

    /// Whether the quick-add field should take the caret. (Task b71850e6)
    ///
    /// The view had a `@FocusState` bound to the field that nothing ever set, so the only way to
    /// get a cursor was to click directly into it — "add task didn't always have a cursor
    /// prompt". When focus is taken is a rule rather than a gesture, so it lives here with
    /// `isVisible` where it can be asserted.
    ///
    /// Search is the exception that matters: grabbing the caret while someone is typing a query
    /// would be worse than never focusing at all.
    static func shouldTakeFocus(isVisible: Bool, isSearchActive: Bool) -> Bool {
        isVisible && !isSearchActive
    }

    /// The caret stays in the field after a task is added, so several can be typed in a row
    /// without clicking back in each time.
    static let retainsFocusAfterCommit = true
}
#endif
