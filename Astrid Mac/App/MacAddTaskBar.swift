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
}
#endif
