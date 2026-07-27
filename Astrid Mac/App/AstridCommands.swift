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

    var body: some Commands {
        // File → New Task (⌘N is the additive Mac equivalent of the bare `n`).
        CommandGroup(replacing: .newItem) {
            Button(NSLocalizedString("tasks.new_task", comment: "")) { MacAppModel.shared.perform(.newTask) }
                .keyboardShortcut("n", modifiers: .command)
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

        // A dedicated Task menu for the additive ⌘-equivalents.
        CommandMenu(NSLocalizedString("tasks.task", comment: "")) {
            Button(NSLocalizedString("reminders.complete", comment: "")) { MacAppModel.shared.perform(.completeTask) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appModel.selectedTaskIds.isEmpty)
            Button(NSLocalizedString("actions.delete", comment: "")) { MacAppModel.shared.perform(.deleteTask) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appModel.selectedTaskIds.isEmpty)
            Divider()
            Button(NSLocalizedString("mac.command_palette", comment: "")) { MacAppModel.shared.openPalette() }
                .keyboardShortcut("k", modifiers: .command)
        }

        // App menu → Check for Updates (Direct/Sparkle build; no-op/hidden on App Store).
        CommandGroup(after: .appInfo) {
            if UpdaterController.shared.isAvailable {
                Button(NSLocalizedString("mac.check_updates", comment: "")) { UpdaterController.shared.checkForUpdates() }
            }
        }

        // Help → Keyboard Shortcuts (the shared bare-key scheme; web shows this on `?`).
        CommandGroup(after: .help) {
            Button(NSLocalizedString("mac.keyboard_shortcuts", comment: "")) { MacAppModel.shared.perform(.showShortcuts) }
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}
#endif
