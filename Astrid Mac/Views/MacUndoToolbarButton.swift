//  MacUndoToolbarButton.swift
//  Astrid for Mac — the visible Undo affordance (AITD-374).
//
//  ⌘Z and Edit ▸ Undo already worked (task 9b603be4). What was missing was anything ON SCREEN
//  saying so: delete a task by clicking a menu item and nothing offered a way back unless you
//  already knew the keystroke or went looking in the Edit menu.
//
//  It sits in the window toolbar beside Refresh, which is the exception `MacListChrome` records
//  in `toolbarOffersUndo`: sort, filter and "+" were taken out of the toolbar because they act on
//  ROWS and the toolbar's trailing edge is the chat column in 3-column mode. Undo reverses the
//  last action wherever it happened, so it passes the same test Refresh does.
//
//  Its own file rather than another twenty lines of MacRootView, which is on the AITD-346 ratchet.

#if os(macOS)
import SwiftUI

struct MacUndoToolbarButton: View {
    @ObservedObject private var undo = MacUndoCoordinator.shared

    var body: some View {
        Button { MacUndoCoordinator.shared.performUndo() } label: {
            // The same title Edit ▸ Undo shows, so the two cannot call one action by two names:
            // it reads "Undo Delete Task", not a bare "Undo".
            Label(undo.undoTitle, systemImage: "arrow.uturn.backward")
        }
        // The task stack only. Unlike the menu item this never falls through to a focused text
        // field, so it can honestly go grey when there is nothing to undo.
        .disabled(!MacUndoMenu.toolbarButtonIsEnabled(stackCanUndo: undo.canUndo))
        .help(undo.undoTitle)
        .accessibilityIdentifier("tasks.undo")
    }
}
#endif
