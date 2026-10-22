//  MacListChrome.swift
//  Astrid for Mac — which controls sit above the task LIST rather than in the window toolbar
//  (Tasks 9998d83a and 10d2cd34).
//
//  In 3-column mode the detail area is [task list | divider | chat], but the window toolbar spans
//  the whole of it. A `.primaryAction` item therefore right-aligns at the WINDOW's trailing edge —
//  which is above the chat column. Sort and filter act on the rows, so they read as belonging to
//  the message list, and the toolbar's "+" looked like an add button for chat.
//
//  Filter, sort and the list-settings gear live in a strip at the top of the list column — the
//  list's header (AITD-522). Sort spent a while in the toolbar (AITD-509), when it was alone in
//  the strip and a row for one icon was the complaint. The "+" is gone entirely:
//  the floating quick-add bar's ⊕ adds a task AND opens it, and ⌘N is bound in AstridCommands, so
//  the toolbar copy was a third way to do the same thing — in the wrong place.

#if os(macOS)
import Foundation

enum MacListChrome {

    /// Whether `MacFilterSheet` — the popover behind the header's filter button — has a Sort
    /// section. It did (AITD-305), which is why the header had no sort menu of its own. AITD-522
    /// ("move list sort to the header") turned that round: sort is a header control, so the
    /// popover drops it and sort still has one control, not two. The List Settings window's
    /// Sort & Filters tab keeps it — that window is the complete editor, not a header control.
    static let filterSheetOffersSort = false

    /// The same for `MacMyTasksFilterSheet` (AITD-467 gave it Sort; AITD-522 moved it out).
    static let myTasksSheetOffersSort = false

    /// Whether the sheet behind the strip's filter button already sorts this selection.
    static func sheetOffersSort(isRealList: Bool, isMyTasks: Bool, isListMode: Bool) -> Bool {
        (showsFilter(isRealList: isRealList, isListMode: isListMode) && filterSheetOffersSort)
            || (isMyTasks && isListMode && myTasksSheetOffersSort)
    }

    /// Sort rides with the rows it sorts. Board and chat are not a sorted row list.
    ///
    /// …but only where nothing else already offers it. On a real list the strip drew the sort
    /// menu AND the filter button three pixels apart, and the sheet behind the filter button
    /// sorts too — so the same setting had two controls (AITD-305). The sheet is the one that has
    /// all the things (sort + six filters + saved filter + subtasks), so the standalone menu is
    /// the one that goes. My Tasks' sheet sorts as well since AITD-467. Where no such sheet stands
    /// behind the rows — a saved-filter list, a public list you only view — the menu stays, and
    /// it is the only way to sort there.
    static func showsSort(hasSelection: Bool, isListMode: Bool,
                          filterSheetOffersSort: Bool) -> Bool {
        hasSelection && isListMode && !filterSheetOffersSort
    }

    /// The filter editor writes a REAL list's saved filters. My Tasks keeps its own prefs
    /// (efd05e56) and a saved-filter list owns no filters of its own.
    static func showsFilter(isRealList: Bool, isListMode: Bool) -> Bool {
        isRealList && isListMode
    }

    /// The list's own settings menu — Edit, Sharing, Enable board, Delete (AITD-373).
    ///
    /// Sort and filter act on ROWS, so they ride with the rows and a board has neither. The
    /// settings menu is not a rows control: it configures the list itself, which a board is just
    /// as much a view of. Suppressing the whole strip in board mode therefore took the settings
    /// with it, and a board offered no route to them at all — the sidebar's right-click was the
    /// only way in, and the sidebar row is not what you are looking at while working a board.
    ///
    /// List mode is deliberately excluded rather than overlooked. Its strip already carries the
    /// filter button, the sidebar right-click is unchanged and still there, and Jon asked for the
    /// board. A third control beside sort and filter is the clutter AITD-305 just finished
    /// removing.
    ///
    /// AITD-522 asked for exactly that third control — "add gear for list settings" — once sort
    /// joined the header, so list mode shows it too. Any real list, either mode.
    static func showsListMenu(isRealList: Bool, isListMode: Bool) -> Bool {
        isRealList
    }

    /// Filter is pinned out of the window toolbar, where the trailing edge is the chat column
    /// rather than the list.
    static let toolbarOffersFilter = false

    /// Sort is NOT a window-toolbar item any more (AITD-522); it was from AITD-509 until then.
    /// Since AITD-305/467 the standalone menu showed only
    /// where no sheet sorts, so wherever it showed it was alone in the strip — a whole row above
    /// the tasks to hold one icon. Jon: "it shouldn't, add it to the top menu".
    static let toolbarOffersSort = false

    /// The toolbar's sort menu: wherever a sheet does not already sort — a list's or My Tasks'
    /// (AITD-305, AITD-467) — and there are rows to sort.
    static func toolbarShowsSort(hasSelection: Bool, isRealList: Bool, isMyTasks: Bool,
                                 isListMode: Bool) -> Bool {
        toolbarOffersSort && showsSort(hasSelection: hasSelection, isListMode: isListMode,
            filterSheetOffersSort: sheetOffersSort(isRealList: isRealList, isMyTasks: isMyTasks,
                                                   isListMode: isListMode))
    }

    /// The header's sort menu (AITD-522): wherever the toolbar does not carry it and no sheet
    /// already sorts — which, with both sheets' Sort sections gone, is every list-mode selection.
    static func headerShowsSort(hasSelection: Bool, isRealList: Bool, isMyTasks: Bool,
                                isListMode: Bool) -> Bool {
        !toolbarOffersSort && showsSort(hasSelection: hasSelection, isListMode: isListMode,
            filterSheetOffersSort: sheetOffersSort(isRealList: isRealList, isMyTasks: isMyTasks,
                                                   isListMode: isListMode))
    }

    /// Whether the strip above the rows is drawn: only when it has something in it.
    static func showsStrip(showsSort: Bool, showsFilter: Bool, showsMyTasksFilter: Bool,
                           showsListMenu: Bool) -> Bool {
        showsSort || showsFilter || showsMyTasksFilter || showsListMenu
    }

    /// Undo DOES belong in the window toolbar (AITD-374), and this constant is here beside the
    /// two below so the exception is recorded rather than looking like the row controls creeping
    /// back in.
    ///
    /// What sent sort, filter and "+" away was that they act on ROWS, while the toolbar's
    /// trailing edge is the chat column in 3-column mode — so they read as chat's controls. Undo
    /// reverses your last action wherever it happened; it is not about these rows. That is the
    /// same test the comment on Refresh applies to Refresh, calling it "the one control that DOES
    /// belong to the window rather than to the task list". Undo is the second.
    ///
    /// It is also the answer to the discoverability half of the task: ⌘Z and Edit ▸ Undo already
    /// worked, but nothing on screen said so, and a task deleted by clicking a menu item gave no
    /// visible way back.
    static let toolbarOffersUndo = true

    /// The window toolbar offers no task "+". Adding lives with the list: the quick-add bar's ⊕,
    /// or ⌘N. `MacAddTaskBar.isVisible` covers every state the removed button did.
    static let toolbarOffersNewTask = false
}
#endif
