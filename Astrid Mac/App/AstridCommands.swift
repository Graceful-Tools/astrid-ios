//  AstridCommands.swift
//  Astrid for Mac — menu bar (M1) + keyboard-shortcut wiring notes
//
//  Two layers of keyboard input (see docs/MAC_APP_SPEC.md §7.1):
//   1) CANONICAL SHARED BARE-KEY scheme (n/x/j/k/0-3/…) — mirrors web
//      astrid-web/hooks/useKeyboardShortcuts.ts (KEYBOARD_SHORTCUTS). This is a
//      cross-platform CONTRACT. It is handled by a dedicated key handler that
//      ignores events while a text field/modal is focused (like web), NOT here.
//   2) ADDITIVE ⌘-menu equivalents (below) for Mac discoverability. These use a
//      modifier so they can never collide with a bare web key.
//
//  Every command must route through the shared services (TaskService, etc.) — never the API.

#if os(macOS)
import SwiftUI

struct AstridCommands: Commands {
    @ObservedObject private var appModel = MacAppModel.shared
    @ObservedObject private var undo = MacUndoCoordinator.shared

    /// One menu item, titled and bound from the shared table.
    private func item(_ command: MacMenuShortcuts.Command, action: @escaping () -> Void) -> some View {
        let binding = MacMenuShortcuts.binding(for: command)
        return Button(binding?.title ?? "", action: action)
            .keyboardShortcut(binding?.shortcut ?? KeyboardShortcut("/", modifiers: .command))
    }

    var body: some Commands {
        // File → New Task (⌘N is the additive Mac equivalent of the bare `n`).
        CommandGroup(replacing: .newItem) {
            item(.newTask) { MacAppModel.shared.perform(.newTask) }
        }

        // Edit ▸ Undo / Redo drive the app's own undo stack (Task 9b603be4). Replacing the group
        // rather than relying on @Environment(\.undoManager) is deliberate: registrations against
        // the environment manager never reached this menu. The actions still hand ⌘Z back to a
        // focused text field when it has something to undo.
        CommandGroup(replacing: .undoRedo) {
            Button(undo.undoTitle) { MacUndoCoordinator.shared.performUndo() }
                .keyboardShortcut("z", modifiers: .command)
            Button(undo.redoTitle) { MacUndoCoordinator.shared.performRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        // A dedicated Task menu for the additive ⌘-equivalents. Titles and keystrokes come from
        // MacMenuShortcuts so the menus and the ⌘/ help sheet cannot drift (e0412a64).
        CommandMenu(NSLocalizedString("tasks.task", comment: "")) {
            item(.completeTask) { MacAppModel.shared.perform(.completeTask) }
                .disabled(appModel.selectedTaskIds.isEmpty)
            item(.deleteTask) { MacAppModel.shared.perform(.deleteTask) }
                .disabled(appModel.selectedTaskIds.isEmpty)
            Divider()
            item(.palette) { MacAppModel.shared.openPalette() }
        }

        // These go INTO the standard View menu (after the sidebar item) rather than into a second
        // menu of the same name — a CommandMenu("View") sits beside AppKit's own View menu, and the
        // user finds two. Search, the three content modes and the filter editor all existed on web
        // and in the ⌘/ sheet but had no menu item at all, which on macOS means undiscoverable.
        CommandGroup(after: .sidebar) {
            Divider()
            item(.search) { MacAppModel.shared.requestSearch() }
            Divider()
            item(.viewList) { MacAppModel.shared.requestContentMode("list") }
            item(.viewBoard) { MacAppModel.shared.requestContentMode("board") }
            item(.viewChat) { MacAppModel.shared.requestContentMode("chat") }
            Divider()
            item(.filter) { MacAppModel.shared.requestFilters() }
            Divider()
            // ⌘R — the platform's refresh key. Same action as the toolbar button and the palette
            // command (0f525a89); there was no menu item, button or shortcut before.
            Button(NSLocalizedString("mac.refresh", comment: "")) { MacAppModel.shared.refreshNow() }
                .keyboardShortcut("r", modifiers: .command)
        }

        // App menu → Check for Updates (Direct/Sparkle build; no-op/hidden on App Store).
        CommandGroup(after: .appInfo) {
            if UpdaterController.shared.isAvailable {
                Button(NSLocalizedString("mac.check_updates", comment: "")) { UpdaterController.shared.checkForUpdates() }
            }
        }

        // Help → Keyboard Shortcuts (the shared bare-key scheme; web shows this on `?`).
        CommandGroup(after: .help) {
            item(.shortcuts) { MacAppModel.shared.perform(.showShortcuts) }
        }
    }
}
#endif
