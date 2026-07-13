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
    var body: some Commands {
        // File → New Task (⌘N is the additive Mac equivalent of the bare `n`).
        CommandGroup(replacing: .newItem) {
            Button("New Task") { /* TODO(M1): TaskService.createTask via CommandRegistry */ }
                .keyboardShortcut("n", modifiers: .command)
        }

        // A dedicated Task menu for the additive ⌘-equivalents.
        CommandMenu("Task") {
            Button("Complete") { /* TODO: TaskService.completeTask */ }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Delete") { /* TODO: TaskService.deleteTask */ }
                .keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Command Palette…") { /* TODO(M2): open ⌘K palette */ }
                .keyboardShortcut("k", modifiers: .command)
        }

        // Help → Keyboard Shortcuts (the shared bare-key scheme; web shows this on `?`).
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { /* TODO(M2): show shortcuts help */ }
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}
#endif
