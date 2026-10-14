//  TaskOccurrences.swift
//  The occurrence chain of a repeating task on a board that spawns (AITD-491; web's AWTD-1219).
//
//  Where `TaskList.spawnsNextOccurrence`, completing a repeating task leaves it completed and
//  the server makes the next occurrence as a NEW task carrying `previousOccurrenceId`. Task
//  details link the two. The server says who came next only on the single-task read, so "next"
//  falls back to a derived link — once, in Core, so the phone and the Mac draw the same links.

import Foundation

/// The occurrences on either side of a task. Both nil for every task outside a chain, which is
/// almost all of them.
struct TaskOccurrenceLinks: Equatable {
    let previousId: String?
    let nextId: String?

    var isEmpty: Bool { previousId == nil && nextId == nil }
}

enum TaskOccurrences {

    /// - `previousId` is the task's own `previousOccurrenceId`, whether or not that task is
    ///   loaded: a completed occurrence often is not, and opening a task by id fetches it.
    /// - `nextId` is the server's `nextOccurrenceId` when this device has it (AITD-492), which
    ///   is the only way a successor that is not loaded gets a link. It rides the single-task
    ///   read alone, so nil there is "not known here", never "none" — and then it is the loaded
    ///   task that names this one as its previous occurrence, if there is one.
    /// - Neither link is inferred from the other.
    static func links(for task: Task, in tasks: [Task]) -> TaskOccurrenceLinks {
        let other: (String) -> String? = { $0 == task.id || $0.isEmpty ? nil : $0 }
        let previous = task.previousOccurrenceId.flatMap(other)
        let next = task.nextOccurrenceId.flatMap(other)
            ?? tasks.first { $0.previousOccurrenceId == task.id && $0.id != task.id }?.id
        return TaskOccurrenceLinks(previousId: previous, nextId: next)
    }
}
