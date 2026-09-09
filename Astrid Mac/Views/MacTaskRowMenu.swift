//  MacTaskRowMenu.swift
//  Astrid for Mac — the right-click actions a task offers, in ONE place so every surface that
//  draws a task offers the same ones (AITD-372).
//
//  Right-clicking a board card did nothing: the card carried no `.contextMenu` while the list row
//  carried nine actions. The fix is deliberately not "copy the menu onto the card" — this app has
//  already paid for that once, and `MacBoardView`'s leading control carries the note about it
//  ("a second implementation is exactly how the board and the panel came to disagree"). The same
//  reasoning made `MacTaskActions` a shared type.
//
//  So the ITEMS are a pure list here, and `MacTaskRowMenuContent` renders it. Each surface hands
//  over its own closures — the list row widens an action to the whole selection, a card acts on
//  itself — but neither chooses which items exist. A new action appears on both or on neither.

#if os(macOS)
import SwiftUI

enum MacTaskRowMenu {

    /// Where the task is being drawn. It selects the ACTIONS' targets, never which actions exist —
    /// hence `items(for:)` returning the same list for both. Kept as a parameter rather than
    /// dropped because it is what the parity test asserts about, and a future surface that
    /// genuinely must differ should have to change this file and fail that test loudly.
    enum Surface {
        case listRow
        case boardCard
    }

    /// One entry in the menu. `divider` is an item rather than an implicit gap so the order —
    /// including where the separator falls — is a single testable value.
    enum Item: Equatable, Hashable {
        case toggleComplete
        /// List row: begin an inline edit of the title. Board card: expand the card, whose editor
        /// holds the title field. The action is "let me change the name", and both honour it.
        case rename
        case setPriority
        case moveToList
        case copyToList
        case share
        case copy
        case openInNewWindow
        case divider
        case delete
    }

    /// The ordered menu, wherever a task is drawn.
    ///
    /// Delete sits last and behind a divider: it is the one entry that destroys someone's work,
    /// and a divider is what keeps a click aimed at the bottom of the menu from finding it.
    static func items(for surface: Surface) -> [Item] {
        [
            .toggleComplete,
            .rename,
            .setPriority,
            .moveToList,
            .copyToList,
            .share,
            .copy,
            .openInNewWindow,
            .divider,
            .delete,
        ]
    }

    /// The leading item names what the click will DO, not the state the task is in.
    static func completeLabelKey(completed: Bool) -> String {
        completed ? "mac.mark_incomplete" : "reminders.complete"
    }

    /// Destinations for "Move to list" — every list except the one the task is already in, since
    /// moving a task to where it already is is a write that changes nothing.
    ///
    /// A virtual/saved selection owns no list, so `nil` leaves every list a valid destination.
    static func moveTargets(lists: [TaskList], currentListId: String?) -> [TaskList] {
        guard let currentListId else { return lists }
        return lists.filter { $0.id != currentListId }
    }
}

// MARK: - Rendering

/// The closures a surface supplies. Which items exist is not among them — that is
/// `MacTaskRowMenu.items(for:)`, and it is the whole point of this type.
struct MacTaskRowMenuActions {
    var toggleComplete: () -> Void
    var rename: () -> Void
    var setPriority: (Task.Priority) -> Void
    var move: (String) -> Void
    var copyToList: (String?) -> Void
    var share: () -> Void
    var copyToPasteboard: () -> Void
    var openInNewWindow: () -> Void
    var delete: () -> Void
}

/// The menu body itself. Drop it inside a `.contextMenu { }` on any surface that draws a task.
///
/// It walks `MacTaskRowMenu.items(for:)` rather than listing buttons in source order, so the
/// rendered menu cannot drift from the list the tests pin.
struct MacTaskRowMenuContent: View {
    let task: Task
    let surface: MacTaskRowMenu.Surface
    let lists: [TaskList]
    let currentListId: String?
    let actions: MacTaskRowMenuActions

    var body: some View {
        ForEach(MacTaskRowMenu.items(for: surface), id: \.self) { item in
            entry(item)
        }
    }

    @ViewBuilder
    private func entry(_ item: MacTaskRowMenu.Item) -> some View {
        switch item {
        case .toggleComplete:
            Button(NSLocalizedString(MacTaskRowMenu.completeLabelKey(completed: task.completed),
                                     comment: ""), action: actions.toggleComplete)

        case .rename:
            Button(NSLocalizedString("mac.rename", comment: ""), action: actions.rename)

        case .setPriority:
            Menu(NSLocalizedString("mac.set_priority", comment: "")) {
                ForEach(MacTaskVisuals.allPriorities.reversed(), id: \.self) { p in
                    Button(MacTaskVisuals.priorityLabel(p)) { actions.setPriority(p) }
                }
            }

        case .moveToList:
            Menu(NSLocalizedString("mac.move_to_list", comment: "")) {
                ForEach(MacTaskRowMenu.moveTargets(lists: lists, currentListId: currentListId)) { list in
                    Button(list.name) { actions.move(list.id) }
                }
            }

        // Share / copy straight from the task — iOS offers these without opening it first, and on
        // Mac they were detail-only (task ea0527ef). Same shared services.
        case .copyToList:
            Menu(NSLocalizedString("lists.copy_to_list", comment: "")) {
                ForEach(MacTaskCopy.targets(lists: lists)) { t in
                    Button(t.label) { actions.copyToList(t.listId) }
                }
            }

        case .share:
            Button(NSLocalizedString("actions.share", comment: ""), action: actions.share)

        case .copy:
            Button(NSLocalizedString("actions.copy", comment: ""), action: actions.copyToPasteboard)

        case .openInNewWindow:
            Button(NSLocalizedString("mac.open_new_window", comment: ""),
                   action: actions.openInNewWindow)

        case .divider:
            Divider()

        case .delete:
            Button(NSLocalizedString("actions.delete", comment: ""),
                   role: .destructive, action: actions.delete)
        }
    }
}
#endif
