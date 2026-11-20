//  MacCheckboxAsset.swift
//  Astrid for Mac — the shared checkbox artwork (Task ca13c94b).
//
//  The Mac drew its own rounded rect and had no notion of repeating at all, so you could not tell a
//  repeating task from a one-off. It now draws the shared `TaskCheckboxArt` (ADEV-164: astrid-core's
//  layers), and these are the shared rules under the Mac's old names.

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
