//  MacListMenu.swift
//  Astrid for Mac — a list's settings menu, in ONE place so every surface that draws a list
//  offers the same one (AITD-373).
//
//  It lived inline in `MacRootView`'s sidebar row and nowhere else, which was fine while the
//  sidebar was the only way in. A board has no sidebar row in front of you while you are looking
//  at the columns, and its chrome strip was suppressed outright — so a board offered no route to
//  list settings at all. Two renderers of one menu is how they drift, which is the argument
//  `MacTaskRowMenu` and `MacTaskActions` already make for tasks.
//
//  The permission gating is asked of `ListPermissions`, never restated. That rule is a
//  cross-platform contract with Web (astrid-web `docs/PRODUCT_CONTRACT.md`), and it was written
//  out three separate times before — one of them wrongly — which is the whole reason it is shared.

#if os(macOS)
import SwiftUI

enum MacListMenu {

    /// One entry. `divider` is an item rather than an implicit gap so the order — including
    /// whether a separator is even warranted — is a single testable value.
    enum Item: Equatable, Hashable {
        case edit
        case toggleFavorite
        case sharing
        case enableBoard
        case divider
        case delete
    }

    /// What this user may do to this list, in order.
    ///
    /// Favourite comes to everyone: it is a personal view preference, not a change to the list,
    /// so it survives where Edit and Sharing do not. Delete is stricter than Edit — it destroys
    /// other people's work — so an admin who may change everything else still does not see it.
    ///
    /// The divider is emitted only when Delete follows it. A separator with nothing behind it is
    /// a menu that looks truncated.
    static func items(for list: TaskList, userId: String?) -> [Item] {
        let canEdit = ListPermissions.canEditSettings(list, userId: userId)
        var items: [Item] = []

        // "Edit", not "Rename": the sheet edits image, task defaults, due time and the
        // recently-completed window too, so "Rename" undersold it.
        if canEdit { items.append(.edit) }
        items.append(.toggleFavorite)
        if canEdit {
            items.append(.sharing)
            if MacViewMode.offersEnableBoard(projectId: list.projectId) {
                items.append(.enableBoard)
            }
        }
        if ListPermissions.canDelete(list, userId: userId) {
            items.append(.divider)
            items.append(.delete)
        }
        return items
    }

    /// The label names what the click will DO, not the state the list is in.
    static func favoriteLabelKey(isFavorite: Bool) -> String {
        isFavorite ? "mac.remove_favorite" : "lists.favorite"
    }
}

/// The closures a surface supplies. Which items exist is not among them — that is
/// `MacListMenu.items(for:userId:)`, and it is the point of this type.
struct MacListMenuActions {
    var edit: () -> Void
    var toggleFavorite: () -> Void
    var sharing: () -> Void
    var enableBoard: () -> Void
    var delete: () -> Void
}

/// The pull-down that opens the menu above a board's columns, in the place sort occupies in list
/// mode (AITD-373). The sidebar needs no equivalent — a right-click is its affordance.
///
/// Here rather than in `MacRootView` because it is presentation of this menu, and because that
/// file is on the AITD-346 ratchet: the extraction is the answer the ratchet asks for.
struct MacListSettingsButton: View {
    let list: TaskList
    let userId: String?
    let actions: MacListMenuActions

    var body: some View {
        Menu {
            MacListMenuContent(list: list, userId: userId, actions: actions)
        } label: {
            Label(NSLocalizedString("lists.list_settings", comment: ""),
                  systemImage: "slider.horizontal.3")
        }
        .fixedSize()
        .help(NSLocalizedString("lists.list_settings", comment: ""))
        .accessibilityIdentifier("board.listSettings")
    }
}

/// The menu body. Drop it in a `.contextMenu { }` on a sidebar row, or in a `Menu { }` above a
/// board's columns — it renders the same items either way.
struct MacListMenuContent: View {
    let list: TaskList
    let userId: String?
    let actions: MacListMenuActions

    var body: some View {
        ForEach(MacListMenu.items(for: list, userId: userId), id: \.self) { item in
            entry(item)
        }
    }

    @ViewBuilder
    private func entry(_ item: MacListMenu.Item) -> some View {
        switch item {
        case .edit:
            Button(NSLocalizedString("mac.edit_list", comment: ""), action: actions.edit)

        case .toggleFavorite:
            Button(NSLocalizedString(MacListMenu.favoriteLabelKey(isFavorite: list.isFavorite ?? false),
                                     comment: ""), action: actions.toggleFavorite)

        case .sharing:
            Button(NSLocalizedString("mac.sharing", comment: ""), action: actions.sharing)

        case .enableBoard:
            Button(NSLocalizedString("mac.enable_board", comment: ""), action: actions.enableBoard)

        case .divider:
            Divider()

        case .delete:
            Button(NSLocalizedString("actions.delete", comment: ""),
                   role: .destructive, action: actions.delete)
        }
    }
}
#endif
