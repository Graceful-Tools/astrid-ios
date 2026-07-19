//  MacAddTaskBar.swift
//  Astrid for Mac — pure rule for the floating Add-task bar (Task bf998f4e).

#if os(macOS)
import Foundation

enum MacAddTaskBar {
    /// The bottom quick-add bar is shown only for a real list — not My Tasks, Search, or a
    /// saved-filter (virtual) list, which own no real tasks to add into.
    static func isVisible(isVirtualSelection: Bool, hasSelection: Bool) -> Bool {
        hasSelection && !isVirtualSelection
    }
}
#endif
