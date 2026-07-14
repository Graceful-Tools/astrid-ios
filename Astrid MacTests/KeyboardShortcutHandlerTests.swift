//  KeyboardShortcutHandlerTests.swift
//  Astrid for Mac — dispatch/guard logic for the shared keyboard scheme (M2, task 6ac2968e)
//
//  Verifies KeyboardShortcutHandler mirrors web's useKeyboardShortcuts.ts guards:
//  suppressed in text fields/modals; selection-scoped actions require a selection.

import XCTest
@testable import Astrid_Mac

final class KeyboardShortcutHandlerTests: XCTestCase {
    private typealias Ctx = KeyboardShortcutHandler.Context

    func testUnselectedGlobalKeyFires() {
        // `n` (new task) needs no selection.
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "n", context: Ctx()), .newTask)
    }

    func testSelectionScopedKeySuppressedWithoutSelection() {
        // `x` (complete) requires a selected task.
        XCTAssertNil(KeyboardShortcutHandler.action(for: "x", context: Ctx(hasSelection: false)))
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "x", context: Ctx(hasSelection: true)), .completeTask)
    }

    func testSuppressedWhileTypingInTextField() {
        // Even a global key must not fire while a text field is focused (web parity).
        XCTAssertNil(KeyboardShortcutHandler.action(for: "n", context: Ctx(isTextFieldFocused: true)))
    }

    func testSuppressedWhileModalPresented() {
        XCTAssertNil(KeyboardShortcutHandler.action(for: "n", context: Ctx(isModalPresented: true)))
    }

    func testAliasKeysResolve() {
        // Arrow aliases resolve to the same nav actions as j/k.
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "↓", context: Ctx()), .selectNext)
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "j", context: Ctx()), .selectNext)
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "↑", context: Ctx()), .selectPrevious)
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "k", context: Ctx()), .selectPrevious)
    }

    func testDeleteAliasesRequireSelection() {
        XCTAssertNil(KeyboardShortcutHandler.action(for: "Backspace", context: Ctx(hasSelection: false)))
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "Delete", context: Ctx(hasSelection: true)), .deleteTask)
    }

    func testUnboundKeyReturnsNil() {
        XCTAssertNil(KeyboardShortcutHandler.action(for: "z", context: Ctx(hasSelection: true)))
    }

    func testPriorityKeysRequireSelection() {
        XCTAssertNil(KeyboardShortcutHandler.action(for: "2", context: Ctx(hasSelection: false)))
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "2", context: Ctx(hasSelection: true)), .priorityMedium)
    }
}
