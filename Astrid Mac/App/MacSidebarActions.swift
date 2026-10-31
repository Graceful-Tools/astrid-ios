//  MacSidebarActions.swift
//  Astrid for Mac — the sidebar's own actions (Task 0fc546a8).
//
//  Creating a list and browsing public lists were unlabelled toolbar icons: a bare + and a globe.
//  iOS puts Add List as the FIRST row of the Your Lists section (ListSidebarView:280) and surfaces
//  public lists in the sidebar as well, and web does the same — so the Mac was the odd one out,
//  hiding two primary actions behind glyphs in a different place.
//
//  Labels reuse the shared iOS keys so the three platforms say the same words.
//
//  AITD-569 moved the Public Lists entry out of the Lists section: above your own lists it pushed
//  them down and read as one of them. It now closes the public lists it leads to.

#if os(macOS)
import Foundation

enum MacSidebarActions {
    struct Action: Equatable {
        let id: String
        let titleKey: String
        let symbol: String
        var title: String { NSLocalizedString(titleKey, comment: "") }
    }

    static let addList = Action(id: "sidebar.newList", titleKey: "navigation.add_list",
                                symbol: "plus.circle.fill")
    static let browsePublicLists = Action(id: "sidebar.publicLists", titleKey: "navigation.public_lists",
                                          symbol: "globe")

    /// The top of the Lists section, not a toolbar.
    static let aboveLists: [Action] = [addList]

    /// The last row of the Public Lists section, below the popular lists it opens onto (AITD-569).
    static let afterPublicLists: [Action] = [browsePublicLists]
}
#endif
