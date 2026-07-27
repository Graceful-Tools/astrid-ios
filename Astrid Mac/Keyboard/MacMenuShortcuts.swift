//  MacMenuShortcuts.swift
//  Astrid for Mac — the ⌘-menu equivalents (Task e0412a64).
//
//  These are ADDITIVE to the shared bare-key contract in KeyboardShortcuts.swift (which mirrors
//  web and must not change without changing web). Every entry carries a modifier so it can never
//  collide with a bare web key.
//
//  The menu bar used to bind five of these; search, list/board/chat and the filter editor existed
//  on web but nowhere in the Mac menus — and on macOS the menu is where shortcuts are discovered,
//  so a missing item is a missing feature. Menus and the ⌘/ help sheet both read this table, so
//  they cannot drift apart again.

#if os(macOS)
import SwiftUI

enum MacMenuShortcuts {

    enum Command: String, CaseIterable {
        case newTask, completeTask, deleteTask, palette
        case search, viewList, viewBoard, viewChat, filter, shortcuts
    }

    struct Binding: Equatable {
        let command: Command
        let key: String
        let modifiers: EventModifiers
        let titleKey: String

        var title: String { NSLocalizedString(titleKey, comment: "") }
        var shortcut: KeyboardShortcut { KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: modifiers) }
    }

    static let all: [Binding] = [
        Binding(command: .newTask,      key: "n",  modifiers: .command,            titleKey: "tasks.new_task"),
        Binding(command: .completeTask, key: "\r", modifiers: .command,            titleKey: "reminders.complete"),
        Binding(command: .deleteTask,   key: "\u{8}", modifiers: .command,         titleKey: "actions.delete"),
        Binding(command: .palette,      key: "k",  modifiers: .command,            titleKey: "mac.command_palette"),
        Binding(command: .search,       key: "f",  modifiers: .command,            titleKey: "navigation.search"),
        Binding(command: .viewList,     key: "1",  modifiers: .command,            titleKey: "mac.view_list"),
        Binding(command: .viewBoard,    key: "2",  modifiers: .command,            titleKey: "mac.view_board"),
        Binding(command: .viewChat,     key: "3",  modifiers: .command,            titleKey: "mac.view_chat"),
        Binding(command: .filter,       key: "f",  modifiers: [.command, .shift],  titleKey: "mac.filter_tasks"),
        Binding(command: .shortcuts,    key: "/",  modifiers: .command,            titleKey: "mac.keyboard_shortcuts"),
    ]

    static func binding(for command: Command) -> Binding? { all.first { $0.command == command } }

    /// What the help sheet prints: ⌘F, ⌘⇧F, ⌘1, ⌘↩, ⌘⌫.
    static func display(for command: Command) -> String {
        guard let binding = binding(for: command) else { return "" }
        var out = ""
        if binding.modifiers.contains(.control) { out += "⌃" }
        if binding.modifiers.contains(.option)  { out += "⌥" }
        if binding.modifiers.contains(.shift)   { out += "⇧" }
        if binding.modifiers.contains(.command) { out += "⌘" }
        switch binding.key {
        case "\r":     out += "↩"
        case "\u{8}":  out += "⌫"
        default:       out += binding.key.uppercased()
        }
        return out
    }
}

/// Which content mode a ⌘1/⌘2/⌘3 request actually lands on. Board and chat need a real list —
/// My Tasks and Search have neither a board nor a channel — so a request for one there falls back
/// to the list view rather than switching to an empty pane (e0412a64).
enum MacViewMode {
    static func resolve(requested: MacRootView.ContentMode, isRealList: Bool) -> MacRootView.ContentMode {
        guard !isRealList else { return requested }
        return .list
    }
}

/// What the ⌘/ sheet renders. Pure, so "the sheet shows exactly what the menus bind" is testable.
enum MacShortcutsHelpModel {
    static var menuRows: [MacMenuShortcuts.Binding] { MacMenuShortcuts.all }
}
#endif
