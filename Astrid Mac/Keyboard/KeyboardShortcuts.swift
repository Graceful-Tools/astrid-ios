//  KeyboardShortcuts.swift
//  Astrid for Mac — canonical keyboard-shortcut table (M2)
//
//  CROSS-PLATFORM CONTRACT. This mirrors the web app's canonical set in
//  astrid-web/hooks/useKeyboardShortcuts.ts (`KEYBOARD_SHORTCUTS`). The scheme is
//  single-key / modifier-less (Gmail-style) and muscle-memory must transfer 1:1
//  between web and Mac. Changing a binding means changing BOTH platforms in the same
//  PR, and updating `KeyboardShortcutsParityTests` (which locks this table against the
//  web set). See docs/MAC_APP_SPEC.md §7.1 / §10.2.
//
//  This file is pure data (no UIKit/AppKit). ⌘-menu equivalents and the ⌘K palette are
//  ADDITIVE and live in AstridCommands.swift — they are NOT part of this shared contract.

import Foundation

/// One logical action a key can trigger. `rawValue` is stable and used by the parity test.
public enum ShortcutAction: String, CaseIterable, Sendable {
    case newTask
    case completeTask
    case dueDateEarlier
    case dueDateLater
    case jumpToDate
    case postpone
    case removeDueDate
    case editLists
    case editTitle
    case editDescription
    case addComment
    case assignNoOne
    case priorityNone
    case priorityLow
    case priorityMedium
    case priorityHigh
    case deleteTask
    case togglePanel
    case cycleFilters
    case selectPrevious
    case selectNext
    case showShortcuts
}

/// A bare-key binding. `keys` holds the canonical key first, then any aliases
/// (e.g. `j` and `↓`). `requiresSelection` mirrors web's `if (selectedTask)` guard.
/// `webAction` is the exact handler name in useKeyboardShortcuts.ts, for traceability.
public struct KeyBinding: Equatable, Sendable {
    public let keys: [String]
    public let action: ShortcutAction
    public let requiresSelection: Bool
    public let webAction: String
    public let title: String
}

public enum KeyboardShortcuts {

    /// The canonical shared table. Order/keys/guards mirror web `KEYBOARD_SHORTCUTS`.
    public static let all: [KeyBinding] = [
        KeyBinding(keys: ["n"],          action: .newTask,         requiresSelection: false, webAction: "onNewTask",              title: "New task"),
        KeyBinding(keys: ["x"],          action: .completeTask,    requiresSelection: true,  webAction: "onCompleteTask",         title: "Complete selected task"),
        KeyBinding(keys: ["←"],          action: .dueDateEarlier,  requiresSelection: true,  webAction: "onMakeDueDateEarlier",   title: "Make due date one day earlier"),
        KeyBinding(keys: ["→"],          action: .dueDateLater,    requiresSelection: true,  webAction: "onMakeDueDateLater",     title: "Make due date one day later"),
        KeyBinding(keys: ["d"],          action: .jumpToDate,      requiresSelection: false, webAction: "onJumpToDate",           title: "Jump to 'Date'"),
        KeyBinding(keys: ["p"],          action: .postpone,        requiresSelection: true,  webAction: "onPostponeTask",         title: "Postpone task by one week"),
        KeyBinding(keys: ["v"],          action: .removeDueDate,   requiresSelection: true,  webAction: "onRemoveDueDate",        title: "Remove task due date"),
        KeyBinding(keys: ["i"],          action: .editLists,       requiresSelection: true,  webAction: "onEditTaskLists",        title: "Edit task lists"),
        KeyBinding(keys: ["t"],          action: .editTitle,       requiresSelection: true,  webAction: "onEditTaskTitle",        title: "Edit task title"),
        KeyBinding(keys: ["s"],          action: .editDescription, requiresSelection: true,  webAction: "onEditTaskDescription",  title: "Edit task description"),
        KeyBinding(keys: ["c"],          action: .addComment,      requiresSelection: true,  webAction: "onAddTaskComment",       title: "Add a new task comment"),
        KeyBinding(keys: ["e"],          action: .assignNoOne,     requiresSelection: true,  webAction: "onAssignToNoOne",        title: "Assign task to 'No One'"),
        KeyBinding(keys: ["0"],          action: .priorityNone,    requiresSelection: true,  webAction: "onSetPriority(0)",       title: "Set priority to None"),
        KeyBinding(keys: ["1"],          action: .priorityLow,     requiresSelection: true,  webAction: "onSetPriority(1)",       title: "Set priority to Low"),
        KeyBinding(keys: ["2"],          action: .priorityMedium,  requiresSelection: true,  webAction: "onSetPriority(2)",       title: "Set priority to Medium"),
        KeyBinding(keys: ["3"],          action: .priorityHigh,    requiresSelection: true,  webAction: "onSetPriority(3)",       title: "Set priority to High"),
        KeyBinding(keys: ["Delete", "Backspace"], action: .deleteTask, requiresSelection: true, webAction: "onDeleteTask",       title: "Delete selected task"),
        KeyBinding(keys: ["o"],          action: .togglePanel,     requiresSelection: false, webAction: "onToggleTaskPanel",      title: "Open/close task edit panel"),
        KeyBinding(keys: ["l"],          action: .cycleFilters,    requiresSelection: false, webAction: "onCycleListFilters",     title: "Cycle through list filters/tags"),
        KeyBinding(keys: ["k", "↑"],     action: .selectPrevious,  requiresSelection: false, webAction: "onSelectPreviousTask",   title: "Select previous task"),
        KeyBinding(keys: ["j", "↓"],     action: .selectNext,      requiresSelection: false, webAction: "onSelectNextTask",       title: "Select next task"),
        KeyBinding(keys: ["?"],          action: .showShortcuts,   requiresSelection: false, webAction: "onShowHotkeyMenu",       title: "Show hotkey listing"),
    ]

    /// Lookup by pressed key (canonical or alias). Returns nil if the key isn't bound.
    public static func binding(for key: String) -> KeyBinding? {
        all.first { $0.keys.contains(key) }
    }
}
