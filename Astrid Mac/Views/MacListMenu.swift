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
        /// One window with Sort & Filters, Membership and (for admins) Admin — AITD-388.
        /// It replaces the separate `edit` and `sharing` items, which opened two unrelated
        /// sheets and between them still left a plain member no way to see who else was on the
        /// list, or to leave it.
        case listSettings
        case toggleFavorite
        case enableBoard
        case divider
        case delete
    }

    /// What this user may do to this list, in order.
    ///
    /// LIST SETTINGS COMES TO EVERYONE (AITD-388), because the window decides for itself which
    /// tabs to show: a plain member gets Sort & Filters and Membership, an admin also gets Admin.
    /// It used to be two admin-only items, `edit` and `sharing`, which meant a member had no
    /// route to the roster at all — they could not see who else was on a list they were on, and
    /// could not leave it. Web has always opened its modal for them.
    ///
    /// Favourite is a personal view preference rather than a change to the list. Delete is
    /// stricter than everything else — it destroys other people's work — so an admin who may
    /// change every setting still does not see it.
    ///
    /// The divider is emitted only when Delete follows it. A separator with nothing behind it is
    /// a menu that looks truncated.
    static func items(for list: TaskList, userId: String?) -> [Item] {
        let canEdit = ListPermissions.canEditSettings(list, userId: userId)
        var items: [Item] = []

        items.append(.listSettings)
        items.append(.toggleFavorite)
        if canEdit {
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
    var listSettings: () -> Void
    var toggleFavorite: () -> Void
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
        case .listSettings:
            Button(NSLocalizedString("lists.list_settings", comment: ""), action: actions.listSettings)

        case .toggleFavorite:
            Button(NSLocalizedString(MacListMenu.favoriteLabelKey(isFavorite: list.isFavorite ?? false),
                                     comment: ""), action: actions.toggleFavorite)

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
