//  MacCheckboxAsset.swift
//  Astrid for Mac — the shared checkbox artwork (Task ca13c94b).
//
//  iOS (TaskRowView.checkboxImage) and web (task-checkbox.tsx) both build
//  check_box[_repeat][_checked]_<priority> from the same asset catalog, so a repeating task shows a
//  box with arrow corners. The Mac drew its own rounded rect and had no notion of repeating at all,
//  so you could not tell a repeating task from a one-off. Same names here, so the three platforms
//  cannot drift.

#if os(macOS)
import SwiftUI

enum MacCheckboxAsset {
    /// `check_box[_repeat][_checked]_<priority>` — token order matches iOS and web exactly.
    /// The shared rule (`TaskCheckboxAsset`, ADEV-148), so the Mac cannot spell it differently.
    static func name(priority: Int, completed: Bool, repeating: Bool) -> String {
        TaskCheckboxAsset.name(priority: priority, completed: completed, repeating: repeating)
    }

    /// The predicate iOS uses: a task is repeating unless it is nil or `.never`.
    static func isRepeating(_ repeating: Task.Repeating?) -> Bool {
        TaskCheckboxAsset.isRepeating(repeating)
    }
}
#endif
