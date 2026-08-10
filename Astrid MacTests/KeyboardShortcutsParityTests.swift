//  KeyboardShortcutsParityTests.swift
//  Astrid for Mac — cross-platform keyboard-shortcut contract test (M2)
//
//  Regression guard for task 6ac2968e (Mac keyboard model with web parity).
//  Locks `KeyboardShortcuts.all` against the canonical web set in
//  astrid-web/hooks/useKeyboardShortcuts.ts (`KEYBOARD_SHORTCUTS`). If web changes a
//  binding, this test fails until BOTH the Mac table AND the `expectedFromWeb` literal
//  below are updated in the same PR — same discipline as CanonicalControlPointsTests.
//
//  This is authored to run in the macOS test target once it exists (see MAC_M0_NOTES.md).
//  Until then it is un-targeted; it does not compile into the iOS build.

import XCTest
@testable import Astrid_Mac   // adjust to the macOS target's module name when created

final class KeyboardShortcutsParityTests: XCTestCase {

    /// Ground truth transcribed from astrid-web/hooks/useKeyboardShortcuts.ts
    /// (key → web handler name, requiresSelection). Keep in sync with web.
    private struct WebShortcut { let key: String; let webAction: String; let requiresSelection: Bool }
    private let expectedFromWeb: [WebShortcut] = [
        .init(key: "n", webAction: "onNewTask", requiresSelection: false),
        .init(key: "x", webAction: "onCompleteTask", requiresSelection: true),
        .init(key: "←", webAction: "onMakeDueDateEarlier", requiresSelection: true),
        .init(key: "→", webAction: "onMakeDueDateLater", requiresSelection: true),
        .init(key: "d", webAction: "onJumpToDate", requiresSelection: false),
        .init(key: "p", webAction: "onPostponeTask", requiresSelection: true),
        .init(key: "v", webAction: "onRemoveDueDate", requiresSelection: true),
        .init(key: "i", webAction: "onEditTaskLists", requiresSelection: true),
        .init(key: "t", webAction: "onEditTaskTitle", requiresSelection: true),
        .init(key: "s", webAction: "onEditTaskDescription", requiresSelection: true),
        .init(key: "c", webAction: "onAddTaskComment", requiresSelection: true),
        .init(key: "e", webAction: "onAssignToNoOne", requiresSelection: true),
        .init(key: "0", webAction: "onSetPriority(0)", requiresSelection: true),
        .init(key: "1", webAction: "onSetPriority(1)", requiresSelection: true),
        .init(key: "2", webAction: "onSetPriority(2)", requiresSelection: true),
        .init(key: "3", webAction: "onSetPriority(3)", requiresSelection: true),
        .init(key: "Delete", webAction: "onDeleteTask", requiresSelection: true),
        .init(key: "Backspace", webAction: "onDeleteTask", requiresSelection: true),
        .init(key: "o", webAction: "onToggleTaskPanel", requiresSelection: false),
        .init(key: "l", webAction: "onCycleListFilters", requiresSelection: false),
        .init(key: "k", webAction: "onSelectPreviousTask", requiresSelection: false),
        .init(key: "↑", webAction: "onSelectPreviousTask", requiresSelection: false),
        .init(key: "j", webAction: "onSelectNextTask", requiresSelection: false),
        .init(key: "↓", webAction: "onSelectNextTask", requiresSelection: false),
        .init(key: "[", webAction: "onOutdentTask", requiresSelection: true),
        .init(key: "]", webAction: "onIndentTask", requiresSelection: true),
        .init(key: "?", webAction: "onShowHotkeyMenu", requiresSelection: false),
    ]

    /// Every web key resolves to a Mac binding with the same handler + selection guard.
    func testEveryWebKeyIsMirroredOnMac() {
        for expected in expectedFromWeb {
            guard let binding = KeyboardShortcuts.binding(for: expected.key) else {
                XCTFail("Web key '\(expected.key)' (\(expected.webAction)) has no Mac binding")
                continue
            }
            XCTAssertEqual(binding.webAction, expected.webAction,
                           "Key '\(expected.key)' maps to \(binding.webAction) on Mac but \(expected.webAction) on web")
            XCTAssertEqual(binding.requiresSelection, expected.requiresSelection,
                           "Key '\(expected.key)' selection-guard differs between Mac and web")
        }
    }

    /// No Mac-only bare keys crept in (would collide with future web keys / break parity).
    func testMacHasNoExtraBareKeys() {
        let webKeys = Set(expectedFromWeb.map { $0.key })
        let macKeys = Set(KeyboardShortcuts.all.flatMap { $0.keys })
        XCTAssertEqual(macKeys, webKeys, "Mac bare-key set diverged from web: \(macKeys.symmetricDifference(webKeys))")
    }

    /// Action coverage is exactly the web set (no orphan/missing actions).
    func testActionCountMatchesWeb() {
        // 27 web keys across 24 actions (Delete+Backspace share deleteTask; j/↓ and k/↑ alias).
        XCTAssertEqual(KeyboardShortcuts.all.count, 24, "Unexpected number of Mac bindings")
        XCTAssertEqual(Set(KeyboardShortcuts.all.map { $0.action }).count, 24, "Duplicate actions in Mac table")
    }
}
