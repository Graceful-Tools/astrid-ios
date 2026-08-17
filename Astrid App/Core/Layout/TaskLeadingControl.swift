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
