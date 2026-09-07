//  MacBoardAdd.swift
//  Astrid for Mac — what a NEW card added in a board column should be created as (Task db8aacda,
//  fixed AITD-328).
//
//  The first version turned a `MacBoardMove.Plan` into `(listIds, complete)` — and DROPPED the
//  status role on the way through. That is the exact failure `MacBoardMove.Plan` documents for
//  the drag path: "a plan that described only the membership left the role behind, and the
//  resolver put the card straight back where it came from." The board resolves a card's column
//  from `Task.statusRole` first (AWTD-562/566), so a card typed into Doing was created with no
//  role, resolved to Inbox, and appeared there — in every column except Inbox itself.
//
//  It is now stated as what to CREATE rather than as a move to apply afterwards, because a card
//  that does not exist yet is not moving from anywhere. That also means the card is born in the
//  right column instead of appearing in Inbox and hopping, and it costs one request instead of
//  two.

#if os(macOS)
import Foundation

enum MacBoardAdd {

    /// The fields a new card needs to land in the column it was typed into.
    struct NewCard: Equatable {
        let listIds: [String]
        /// The role to write, or nil for Inbox and Done — neither carries a status.
        let statusRole: String?
        /// Done: created, then completed through `completeTask` (never `updateTask(completed:)`).
        let complete: Bool
    }

    /// What to create for a card typed into `column` on the board backed by `domainListId`.
    ///
    /// Derived from the SHARED planner rather than from the column's kind spelled out here, so
    /// "what does this column mean" keeps one implementation across the drag path, the quick
    /// changer and this. The task handed to it is a blank standing in for the card about to
    /// exist: no status, and no memberships beyond the board's own list.
    static func newCard(in column: ProjectBoardColumn,
                        domainListId: String,
                        lists: [TaskList]) -> NewCard {
        let blank = Task(id: "", title: "", listIds: [domainListId])
        let move = resolveProjectColumnMove(blank, targetColumn: column, lists: lists)
        return NewCard(listIds: move.listIds,
                       statusRole: move.statusRole,
                       complete: move.completed)
    }
}
#endif
