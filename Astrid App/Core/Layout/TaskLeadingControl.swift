import Foundation

/// What the control at the leading edge of a task shows (Task 42013da7).
///
/// It answers "whose task is this?". It had only two answers — someone else's photo, or a
/// checkbox — and "unassigned" was folded in with "mine", so a task nobody owns looked exactly
/// like a task you own. Nobody-assigned is its own state and gets its own mark.
///
/// One rule, used by the task row, the task detail and quick add, so the same task cannot be
/// depicted three different ways. Web mirrors it (see the companion task).
enum TaskLeadingControl: Equatable {
    /// Yours: the checkbox, which is also how you complete it.
    case checkbox
    /// Someone else's: their photo, in a priority-coloured square.
    case avatar(String)
    /// Nobody's yet.
    case unassigned

    /// Shared with `AssigneeResolver` so the mark you PICK in the assignee list is the mark you
    /// then SEE on the task.
    static var unassignedGlyph: String { AssigneeResolver.unassignedGlyph }

    /// `displayMode` is required rather than defaulted (task 132d7b3f). The two modes disagree
    /// about exactly one case — a task assigned to YOU — and a default would let a new call
    /// site pick the old answer silently, which is the bug this parameter exists to prevent.
    ///
    /// LIST mode: your own task is the checkbox, because in list mode the checkbox is how you
    /// complete it.
    ///
    /// PROJECT mode: your own task shows YOUR photo, exactly as someone else's shows theirs.
    /// The mode's own documentation has promised this since it was added — "tasks assigned to
    /// you also show your profile photo" — and it costs nothing there, because in project mode
    /// the control opens the quick changer rather than completing, so it was never a checkbox
    /// in the sense of "click to finish". A board where every card you own is a bare checkbox
    /// and everyone else's is a face makes your own work the only thing you cannot see at a
    /// glance.
    static func kind(assigneeId: String?,
                     currentUserId: String?,
                     displayMode: TaskDisplayMode) -> TaskLeadingControl {
        guard let assigneeId, !assigneeId.isEmpty else { return .unassigned }
        if let currentUserId, assigneeId == currentUserId {
            return displayMode.usesCompactTaskDetail ? .avatar(assigneeId) : .checkbox
        }
        return .avatar(assigneeId)
    }
}

/// WHERE a task's leading control is being drawn.
///
/// The rule below used to ask ONE question — which Appearance mode is this? — and a mode
/// cannot tell a board card from a list row. So `list` mode, whose whole point is that the
/// checkbox finishes the task, handed that behaviour to board cards as well, which is exactly
/// the trapdoor task 9be8cb1b removed from the board: the click that reads as "pick this one"
/// finished the task, with no way back but hunting it down in the Done column (task f9d7ed42).
///
/// A surface is something the call site knows and the mode never can.
enum TaskLeadingControlSurface: Equatable {
    /// A card in a project board column.
    case boardCard
    /// A row in a list.
    case listRow
    /// The task detail screen or panel.
    case detail
}

/// What clicking or tapping the leading control does.
///
/// Two answers, not three. AITD-363 briefly added a `confirmCompletion` tap for someone else's
/// task in task details; AITD-375 replaced it with the options popover on every surface, moving
/// the confirmation onto that popover's Complete button, and AITD-381 dropped the confirmation
/// entirely — the popover was already the deliberate step it was asking for. A tap either
/// finishes the task or offers you the choices.
enum TaskLeadingControlAction: Equatable {
    case complete
    case openPicker
}

extension TaskLeadingControl {

    /// Complete the task, or open the picker?
    ///
    /// A BOARD CARD always opens the picker, in both modes. A board is where a task has a
    /// status, so the control is how you set it — and completing outright from a card is the
    /// trapdoor described above (tasks 9be8cb1b, f9d7ed42).
    ///
    /// A LIST ROW completes, because that is what a checkbox means when the task is not on a
    /// board — unless project mode has turned the control into the quick changer everywhere
    /// (task 132d7b3f).
    ///
    /// SOMEONE ELSE'S TASK OPENS THE POPOVER, EVERYWHERE (AITD-375). Jon: "when not yours ...
    /// it should give the popover to show assignment, complete, priority and status options just
    /// like in project mode."
    ///
    /// This is checked before the surface, because it holds on all of them, and it settles two
    /// things that used to disagree. A list ROW completed another person's task outright on a
    /// tap — one stray touch on a small photo in a dense list, no confirmation and no obvious way
    /// back. Task DETAILS did the opposite and offered no way to complete it at all, then briefly
    /// (AITD-363) a bespoke confirm-on-tap. Neither is right, and they were not even the same
    /// wrong: one screen finished the task, another would not.
    ///
    /// The popover answers both. It cannot be triggered by accident the way an outright
    /// completion can, it carries assignment and priority and board state — which are usually
    /// what you actually wanted when you reached for someone else's task — and completion is
    /// still there, on the popover's own Complete button.
    ///
    /// NOBODY'S TASK OPENS IT TOO (AITD-382), but it arrives there by a different road. The
    /// guard above is about tasks that belong to someone — another person or an agent, both of
    /// them `.avatar(id)` with an id that is not yours. An unassigned task is deliberately NOT
    /// "someone else's", so it falls past that guard, and what catches it is the surface switch
    /// asking whether the mark is a checkbox at all. Since task 42013da7 it is not: a task
    /// nobody owns draws the "U" glyph, precisely because drawing it as a checkbox made it look
    /// like a task you own. Completing on a tap is what a checkbox means; it is not what that
    /// glyph means. Jon, AITD-382: "unassigned ... agents, and tasks assigned to others should
    /// all behave the same".
    ///
    /// One function for both platforms, so a card cannot mean one thing on the Mac and another
    /// on the phone — the same reason `kind` is shared.
    static func action(surface: TaskLeadingControlSurface,
                       kind: TaskLeadingControl,
                       displayMode: TaskDisplayMode,
                       currentUserId: String?) -> TaskLeadingControlAction {
        if kind.isSomeoneElses(currentUserId: currentUserId) { return .openPicker }

        switch surface {
        case .boardCard:
            // A board is where a task has a status, so the control is how you set it — and
            // completing outright from a card is the trapdoor tasks 9be8cb1b / f9d7ed42 removed.
            return .openPicker
        case .listRow, .detail:
            // ONLY A CHECKBOX FINISHES A TASK ON A TAP (AITD-382). One case, not two, because
            // the row and the detail screen have no business disagreeing about the same task —
            // and they did: the row asked about the display mode alone and never looked at the
            // mark it had just drawn, so an UNASSIGNED task was completed by a tap on a row
            // while the detail screen already offered the popover for it.
            return displayMode.checkboxCompletesTask && kind == .checkbox ? .complete : .openPicker
        }
    }

    /// Is this control showing a task that belongs to somebody else?
    ///
    /// Asked of the KIND, so it cannot disagree with the mark on screen — `.avatar` already
    /// carries whose face it is. Your own task in project mode is an avatar too (task 132d7b3f),
    /// which is exactly why "is it an avatar" is not the same question as "is it theirs".
    ///
    /// An unknown current user counts as someone else's: we cannot show it is yours, and the
    /// safe answer is the one that asks first.
    func isSomeoneElses(currentUserId: String?) -> Bool {
        guard case .avatar(let assigneeId) = self else { return false }
        return assigneeId != currentUserId
    }

    /// Does this task belong to somebody else, asked of the raw ids?
    ///
    /// Was `completionNeedsConfirmation` until AITD-381. It once gated a confirmation sheet on
    /// the popover's Complete button — Jon, AITD-375: "when not yours, always confirm before
    /// completing" — and that sheet is gone: the popover IS the deliberate step now, because
    /// `action` above sends someone else's task there on every surface instead of completing on a
    /// tap. Asking again on the one button inside it was asking a question already answered
    /// twice. What survives is the question itself, which still decides what the popover carries.
    ///
    /// Takes the raw ids rather than a `kind`, because the thing asking is not a leading control
    /// and has no mark to ask about — and because in project mode your own task IS an avatar, so
    /// a kind-shaped question would answer "someone else's" about your own work.
    static func isSomeoneElsesTask(assigneeId: String?, currentUserId: String?) -> Bool {
        guard let assigneeId, !assigneeId.isEmpty else { return false }  // nobody's
        return assigneeId != currentUserId
    }

    /// Does the options popover carry the board-state section?
    ///
    /// Someone else's task gets the full set — "just like in project mode" (AITD-375). The list
    /// mode omission it overrides is an argument about the DETAIL panel's own layout, where
    /// priority and assignee are already rows of their own; it was never an argument about what
    /// the popover should offer when the popover is the only thing you get.
    ///
    /// Shared so the Mac's `MacLeadingPicker` and the phone's popovers cannot offer different
    /// choices for the same task.
    static func pickerShowsProjectState(displayMode: TaskDisplayMode,
                                        surface: TaskLeadingControlSurface,
                                        isSomeoneElses: Bool) -> Bool {
        displayMode.usesCompactTaskDetail || surface == .boardCard || isSomeoneElses
    }
}
