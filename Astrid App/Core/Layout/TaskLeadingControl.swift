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

    static func kind(assigneeId: String?, currentUserId: String?) -> TaskLeadingControl {
        guard let assigneeId, !assigneeId.isEmpty else { return .unassigned }
        if let currentUserId, assigneeId == currentUserId { return .checkbox }
        return .avatar(assigneeId)
    }
}
