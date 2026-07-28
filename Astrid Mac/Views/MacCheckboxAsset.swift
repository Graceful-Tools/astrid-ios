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
    static func name(priority: Int, completed: Bool, repeating: Bool) -> String {
        // Only 0…3 exist as assets; anything else would resolve to nothing at all.
        let safe = (0...3).contains(priority) ? priority : 0
        var name = "check_box"
        if repeating { name += "_repeat" }
        if completed { name += "_checked" }
        return name + "_\(safe)"
    }

    /// The predicate iOS uses: a task is repeating unless it is nil or `.never`.
    static func isRepeating(_ repeating: Task.Repeating?) -> Bool {
        guard let repeating else { return false }
        return repeating != .never
    }
}
#endif
