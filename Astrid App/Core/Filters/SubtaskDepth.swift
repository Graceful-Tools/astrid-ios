//  SubtaskDepth.swift
//  Astrid — how deeply a task is nested, for row indentation and drag re-nesting on iOS and Mac.
//
//  The splice that put subtasks under their parents lived here too (Task 3c945236); it is
//  astrid-core's `rowsForList` since AITD-460, which both apps ask through `ListRowsModel`.

import Foundation

/// Nesting depth of a task (0 = top-level), walking parentTaskId with a cycle-safe cap and O(1)
/// parent lookups. Used by iOS and Mac row indentation.
func subtaskDepth(_ task: Task, byId: [String: Task]) -> Int {
    var depth = 0
    var parentId = task.parentTaskId
    while let pid = parentId, depth < 8 {
        depth += 1
        parentId = byId[pid]?.parentTaskId
    }
    return depth
}
