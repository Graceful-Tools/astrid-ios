//  MacCommandDispatchTests.swift
//  Regression for task cdfbd79f — menus and the bare-key scheme must resolve to real actions,
//  and the key monitor must normalize events to the shared KeyboardShortcuts key tokens.

import XCTest
@testable import Astrid_Mac

final class MacCommandDispatchTests: XCTestCase {

    // The four commands the Mac app actually performs must all be handled...
    func testHandledActionsAreDispatchable() {
        for action in [ShortcutAction.newTask, .completeTask, .deleteTask, .showShortcuts] {
            XCTAssertTrue(MacAppModel.handledActions.contains(action),
                          "\(action) must be a handled command so menus and shortcuts both fire it.")
        }
    }

    // As of 9a60b697 the ENTIRE shared table is wired (no dead keys); actions that were previously
    // unclaimed (due shifts, postpone, edit-title, …) are now dispatched. See MacKeyboardDispatchTests.
    func testFullShortcutTableIsWired() {
        for action in [ShortcutAction.dueDateLater, .postpone, .editTitle,
                       .assignNoOne, .selectNext, .cycleFilters, .togglePanel, .jumpToDate] {
            XCTAssertTrue(MacAppModel.handledActions.contains(action),
                          "\(action) should be wired now that the full table is handled.")
        }
    }

    // The bare-key `x`/`Delete`/`?` resolve to the same actions the menus use.
    func testSharedKeysResolveToHandledActions() {
        let sel = KeyboardShortcutHandler.Context(hasSelection: true)
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "n", context: sel), .newTask)
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "x", context: sel), .completeTask)
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "Delete", context: sel), .deleteTask)
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "?", context: sel), .showShortcuts)
    }

    // Complete/Delete require a selection (web parity) — suppressed when nothing is selected.
    func testSelectionScopedKeysSuppressedWithoutSelection() {
        let none = KeyboardShortcutHandler.Context(hasSelection: false)
        XCTAssertNil(KeyboardShortcutHandler.action(for: "x", context: none))
        XCTAssertNil(KeyboardShortcutHandler.action(for: "Delete", context: none))
        // Non-selection commands still work.
        XCTAssertEqual(KeyboardShortcutHandler.action(for: "n", context: none), .newTask)
    }

    // Key normalization maps arrows/delete by keyCode and letters by character.
    func testKeyNormalization() {
        XCTAssertEqual(MacKeyMonitor.normalizedKey(chars: nil, keyCode: 51), "Backspace")
        XCTAssertEqual(MacKeyMonitor.normalizedKey(chars: nil, keyCode: 117), "Delete")
        XCTAssertEqual(MacKeyMonitor.normalizedKey(chars: "\u{1c}", keyCode: 123), "←")
        XCTAssertEqual(MacKeyMonitor.normalizedKey(chars: "N", keyCode: 45), "n")
        XCTAssertEqual(MacKeyMonitor.normalizedKey(chars: "?", keyCode: 44), "?")
        XCTAssertNil(MacKeyMonitor.normalizedKey(chars: "", keyCode: 999))
    }
}
