//  MacSubtaskDrop.swift
//  Astrid for Mac — pure guard for drag-to-indent (drop a task onto another to make it a subtask).
//  Prevents self-parenting and cycles (a task cannot become a child of its own descendant).

#if os(macOS)
import Foundation

enum MacSubtaskDrop {
    /// Whether `childId` may be reparented under `parentId`, given all tasks (for the cycle walk).
    static func canParent(childId: String, parentId: String, allTasks: [Task]) -> Bool {
        guard childId != parentId else { return false }
        let byId = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Walk parentId's ancestors — if we reach childId, this drop would create a cycle.
        var cursor: String? = parentId
        var guardCount = 0
        while let id = cursor, guardCount < 100 {
            if id == childId { return false }
            cursor = byId[id]?.parentTaskId
            guardCount += 1
        }
        return true
    }
}
#endif
