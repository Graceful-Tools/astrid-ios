import Foundation

/// Which board columns the QUICK STATE PICKER offers (task 7574067b).
///
/// Not the same question as "what columns does the board have". The board needs a Done column —
/// a completed task has to sit somewhere, and dragging a card there is how you finish it. The
/// picker does not: it appears in the quick changer, one row above an explicit Complete button
/// that does exactly the same thing. So the popover offered the same action twice, and the chip
/// version was the one that gave no hint it would finish the task.
///
/// A shared filter rather than a `filter` written at each call site: the iOS picker and the Mac
/// picker are two views by necessity — their chip styling and pointer affordances differ — but
/// "which states can I pick" is one decision, and a decision written twice is one that drifts.
///
/// Matched on `kind`, never on the name. A project may have its own column called "Done", and
/// that one is a real state a task can be moved to.
enum ProjectStatePicker {

    /// The board's columns, minus the completion column.
    static func columns(from boardColumns: [ProjectBoardColumn]) -> [ProjectBoardColumn] {
        boardColumns.filter { $0.kind != .done }
    }
}
