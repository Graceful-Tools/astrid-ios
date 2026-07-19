//  SubtaskSplicing.swift
//  Astrid — SHARED subtask display logic for the flat task list (Task 3c945236).
//
//  Mirrors iOS TaskListView's inline splice so Mac and iOS render subtasks identically:
//  in "indented" mode each visible parent's subtasks are spliced depth-first directly after it;
//  in "under_parent" mode subtasks are hidden from lists (shown only in the parent's detail).
//  Pure: the caller supplies which subtasks are visible (usually a completion check).

import Foundation

/// Splice subtasks under their parents. `topLevel` is the already-filtered/sorted top-level row
/// set (parentTaskId == nil). `allTasks` is the full store used to find subtasks at any depth.
/// `subtaskVisible` decides which subtasks show (e.g. incomplete, or completed when the list shows
/// them). Depth is capped at 10 to guard against bad-data cycles.
func spliceSubtasks(topLevel: [Task], allTasks: [Task], indented: Bool,
                    subtaskVisible: (Task) -> Bool) -> [Task] {
    guard indented else { return topLevel }

    var byParent: [String: [Task]] = [:]
    for t in allTasks {
        if let parentId = t.parentTaskId { byParent[parentId, default: []].append(t) }
    }
    guard !byParent.isEmpty else { return topLevel }

    var out: [Task] = []
    func appendSubtree(_ task: Task, depth: Int) {
        out.append(task)
        guard depth < 10, let subs = byParent[task.id] else { return }
        let visible = subs.filter(subtaskVisible)
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        for sub in visible { appendSubtree(sub, depth: depth + 1) }
    }
    for t in topLevel { appendSubtree(t, depth: 0) }
    return out
}

/// Nesting depth of a task (0 = top-level), walking parentTaskId with a cycle-safe cap and O(1)
/// parent lookups. Mirrors iOS `subtaskDepth`.
func subtaskDepth(_ task: Task, byId: [String: Task]) -> Int {
    var depth = 0
    var parentId = task.parentTaskId
    while let pid = parentId, depth < 8 {
        depth += 1
        parentId = byId[pid]?.parentTaskId
    }
    return depth
}
