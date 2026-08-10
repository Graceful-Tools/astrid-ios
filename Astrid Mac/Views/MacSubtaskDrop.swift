//  MacSubtaskDrop.swift
//  Astrid for Mac — pure guard for drag-to-indent (drop a task onto another to make it a subtask).
//
//  The rule itself now lives in the SHARED `DragNesting`, so Mac and iOS cannot disagree about
//  what a cycle is. This stays as the Mac's call shape (an array of tasks rather than a
//  dictionary), because the callers already hold the array.

#if os(macOS)
import Foundation

enum MacSubtaskDrop {
    /// Whether `childId` may be reparented under `parentId`, given all tasks (for the cycle walk).
    static func canParent(childId: String, parentId: String, allTasks: [Task]) -> Bool {
        let byId = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return DragNesting.canParent(childId: childId, parentId: parentId, byId: byId)
    }
}
#endif
