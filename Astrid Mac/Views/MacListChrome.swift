//  MacListChrome.swift
//  Astrid for Mac — which controls sit above the task LIST rather than in the window toolbar
//  (Tasks 9998d83a and 10d2cd34).
//
//  In 3-column mode the detail area is [task list | divider | chat], but the window toolbar spans
//  the whole of it. A `.primaryAction` item therefore right-aligns at the WINDOW's trailing edge —
//  which is above the chat column. Sort and filter act on the rows, so they read as belonging to
//  the message list, and the toolbar's "+" looked like an add button for chat.
//
//  Sort and filter now live in a strip at the top of the list column. The "+" is gone entirely:
//  the floating quick-add bar's ⊕ adds a task AND opens it, and ⌘N is bound in AstridCommands, so
//  the toolbar copy was a third way to do the same thing — in the wrong place.

#if os(macOS)
import Foundation

enum MacListChrome {

    /// Sort rides with the rows it sorts. Board and chat are not a sorted row list.
    static func showsSort(hasSelection: Bool, isListMode: Bool) -> Bool {
        hasSelection && isListMode
    }

    /// The filter editor writes a REAL list's saved filters. My Tasks keeps its own prefs
    /// (efd05e56) and a saved-filter list owns no filters of its own.
    static func showsFilter(isRealList: Bool, isListMode: Bool) -> Bool {
        isRealList && isListMode
    }

    /// Pinned so the controls cannot drift back into the window toolbar, where the trailing edge
    /// is the chat column rather than the list.
    static let toolbarOffersSortOrFilter = false

    /// The window toolbar offers no task "+". Adding lives with the list: the quick-add bar's ⊕,
    /// or ⌘N. `MacAddTaskBar.isVisible` covers every state the removed button did.
    static let toolbarOffersNewTask = false
}
#endif
