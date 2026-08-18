//  MacPriorityWrite.swift
//  When a priority tap is worth a write (task e761d369).
//
//  The panel used to compare the tap against `task.priority` — the value it was HANDED when it
//  opened — and skip the write when they matched. Local state has been moving since, so: open a
//  task that is High, tap None (writes), tap High again, and the guard compares High against a
//  snapshot that still says High and returns without writing. The button lights up, nothing is
//  saved, and the next refresh pulls it back to None.
//
//  Which taps that swallows depends on what the priority happened to be when the panel opened,
//  which is why it reads as random — "sometimes unresponsive".
//
//  The only repeat worth suppressing is the one the panel can be sure about: the same button
//  tapped twice in a row, having already written it. Everything else writes. A redundant PUT is
//  idempotent and goes through the Outbox like any other write; a swallowed one is a lie.

#if os(macOS)
import Foundation

enum MacPriorityWrite {

    /// Write this tap?
    ///
    /// - Parameter lastWritten: the last priority THIS panel wrote, or nil when it has not
    ///   written yet. Deliberately not the task's current value: the point is that the panel
    ///   cannot know whether its snapshot still matches the server.
    static func shouldWrite(tapped: Task.Priority, lastWritten: Task.Priority?) -> Bool {
        tapped != lastWritten
    }
}
#endif
