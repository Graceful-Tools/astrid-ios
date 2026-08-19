//  MacBoardPriorityTap.swift
//  What a priority tap on a BOARD CARD does.
//
//  Jon: "tap on the priority, another priority, another priority, and eventually it stalls and
//  won't update the priority. I expect it to update instantly."
//
//  It stalled because the board asked the wrong question. `setPriority` compared the tap
//  against `t.priority` — the task as CAPTURED when the card was rendered — and on a match
//  wrote nothing AND cleared the draft, so the button snapped back to the snapshot. Whichever
//  priority the card happened to be rendered with was a dead button, which is why it took a few
//  taps to hit and looked random.
//
//  The snapshot is deliberately NOT a parameter here. It is not evidence about the server — the
//  previous tap has already moved it — and a value this rule cannot see is a value it cannot be
//  tempted back into consulting.
//
//  Same defect as task e761d369, which fixed the DETAIL panel's `savePriority` and left this
//  one. Both now go through `MacPriorityWrite`.

#if os(macOS)
import Foundation

enum MacBoardPriorityTap {

    /// What a tap should do: what the card shows, and what to send.
    struct Outcome: Equatable {
        /// The value the card shows immediately. ALWAYS what was pressed — showing anything
        /// else is what made this read as frozen rather than merely unsaved.
        var draft: Task.Priority
        /// What to write, or nil to write nothing.
        var write: Task.Priority?
    }

    /// - Parameter lastWritten: the last priority THIS board wrote for this task, or nil when it
    ///   has not written one. The only repeat worth suppressing is the same button twice in a
    ///   row, which is the one case the board can be sure about.
    static func tap(_ tapped: Task.Priority, lastWritten: Task.Priority?) -> Outcome {
        Outcome(draft: tapped,
                write: MacPriorityWrite.shouldWrite(tapped: tapped, lastWritten: lastWritten)
                    ? tapped : nil)
    }

    /// The draft a completed write leaves behind. nil means "clear it; the task is the truth
    /// again", so a later change from anywhere else is not shadowed by a stale local value.
    ///
    /// It used to clear unconditionally, which discarded a NEWER tap: press high, press medium
    /// before high's write returns, and high's completion put the card back to the task's value.
    /// That is the second half of the stall, and the one that bites hardest when tapping fast.
    static func draftAfterWriting(_ written: Task.Priority,
                                  currentDraft: Task.Priority?) -> Task.Priority? {
        currentDraft == written ? nil : currentDraft
    }
}
#endif
