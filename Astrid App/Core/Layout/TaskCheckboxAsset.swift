//  TaskCheckboxAsset.swift
//  The task checkbox artwork's name, once for the phone and the Mac (ADEV-148).
//
//  `check_box[_repeat][_checked]_<priority>`, the same tokens web's `CheckboxArt` draws. The
//  task row, the task detail, the Mac row and the quick changer's "Mark as done" row all
//  show this one box, so a task looks the same wherever you reach for it.

import Foundation

enum TaskCheckboxAsset {
    static func name(priority: Int, completed: Bool, repeating: Bool) -> String {
        // Only 0…3 exist as assets; anything else would resolve to nothing at all.
        let safe = (0...3).contains(priority) ? priority : 0
        var name = "check_box"
        if repeating { name += "_repeat" }
        if completed { name += "_checked" }
        return name + "_\(safe)"
    }

    /// A task repeats unless its rule is nil or `.never`.
    static func isRepeating(_ repeating: Task.Repeating?) -> Bool {
        guard let repeating else { return false }
        return repeating != .never
    }
}
