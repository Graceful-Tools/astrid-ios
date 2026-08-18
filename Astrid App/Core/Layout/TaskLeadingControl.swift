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
    /// The DETAIL screen adds one condition: only when the face IS a checkbox. Someone else's
    /// photo is not a checkbox, and finishing their task by tapping their face is not what that
    /// tap means (task 729a190e).
    ///
    /// One function for both platforms, so a card cannot mean one thing on the Mac and another
    /// on the phone — the same reason `kind` is shared.
    static func action(surface: TaskLeadingControlSurface,
                       kind: TaskLeadingControl,
                       displayMode: TaskDisplayMode) -> TaskLeadingControlAction {
        switch surface {
        case .boardCard:
            return .openPicker
        case .listRow:
            return displayMode.checkboxCompletesTask ? .complete : .openPicker
        case .detail:
            return displayMode.checkboxCompletesTask && kind == .checkbox ? .complete : .openPicker
        }
    }
}
