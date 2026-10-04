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
    /// The core's `resolve_create` rule (`board::resolve_create`): the board's own list, the
    /// column's role for a status column and none for Inbox and Done, completed in Done. Stated
    /// here only as the create's fields — the Mac's quick-add builds its own create (smart parsing,
    /// the list's defaults), so it cannot hand the card to `addBoardCard`.
    static func newCard(in column: ProjectBoardColumn, domainListId: String) -> NewCard {
        NewCard(listIds: [domainListId],
                statusRole: column.kind == .status ? column.id : nil,
                complete: column.kind == .done)
    }

    /// A column's quick-add, built the way the list's is (AITD-431): the typed text and the
    /// list's defaults give the title, priority, date, repeat, assignee and privacy; the COLUMN
    /// gives the memberships and the role. Its lists come first, then any list the text named
    /// with #list, once each.
    static func placing(_ args: MacQuickAdd.CreateArgs, in card: NewCard) -> MacQuickAdd.CreateArgs {
        var listIds = card.listIds
        for id in args.listIds where !listIds.contains(id) { listIds.append(id) }
        return MacQuickAdd.CreateArgs(title: args.title, listIds: listIds, priority: args.priority,
                                      whenDate: args.whenDate, repeating: args.repeating,
                                      repeatingData: args.repeatingData,
                                      assigneeId: args.assigneeId, isPrivate: args.isPrivate)
    }
}
#endif
