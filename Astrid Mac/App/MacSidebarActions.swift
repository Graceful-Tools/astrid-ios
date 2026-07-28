//  MacSidebarActions.swift
//  Astrid for Mac — the sidebar's own actions (Task 0fc546a8).
//
//  Creating a list and browsing public lists were unlabelled toolbar icons: a bare + and a globe.
//  iOS puts Add List as the FIRST row of the Your Lists section (ListSidebarView:280) and surfaces
//  public lists in the sidebar as well, and web does the same — so the Mac was the odd one out,
//  hiding two primary actions behind glyphs in a different place.
//
//  Labels reuse the shared iOS keys so the three platforms say the same words.

#if os(macOS)
import Foundation

enum MacSidebarActions {
    struct Action: Equatable {
        let id: String
        let titleKey: String
        let symbol: String
        var title: String { NSLocalizedString(titleKey, comment: "") }
    }

    /// Order matters: add before browse, both above the lists.
    static let all: [Action] = [
        Action(id: "sidebar.newList", titleKey: "navigation.add_list", symbol: "plus.circle.fill"),
        Action(id: "sidebar.publicLists", titleKey: "navigation.public_lists", symbol: "globe"),
    ]

    /// They belong at the top of the Lists section, not under a toolbar.
    static let appearAboveLists = true
}
#endif
