//  MacMenuShortcutsTests.swift
//  Regression tests for Task e0412a64 — "[mac] menu-bar shortcuts are thinner than the web's".
//
//  The menu bar defined five ⌘ commands (⌘N, ⌘⏎, ⌘⌫, ⌘K, ⌘/) while the web offers search,
//  list/board/chat switching and the filter editor as well. On macOS the menu is also where
//  shortcuts are DISCOVERED, so anything missing from it is effectively hidden. The table below
//  is the single source both the menus and the ⌘/ help sheet read, so the two cannot drift.

import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacMenuShortcutsTests: XCTestCase {

    /// Everything the web offers as a ⌘ command has a menu item here.
    func testCoversTheWebsCommandSet() {
        let commands = Set(MacMenuShortcuts.all.map(\.command))
        for expected: MacMenuShortcuts.Command in [.newTask, .completeTask, .deleteTask, .palette,
                                                   .search, .viewList, .viewBoard, .viewChat,
                                                   .filter, .shortcuts] {
            XCTAssertTrue(commands.contains(expected), "\(expected) has no menu item")
        }
    }

    /// The gap this task is about: these four were missing entirely.
    func testTheMissingFourAreBound() {
        XCTAssertEqual(MacMenuShortcuts.binding(for: .search)?.key, "f")
        XCTAssertEqual(MacMenuShortcuts.binding(for: .viewList)?.key, "1")
        XCTAssertEqual(MacMenuShortcuts.binding(for: .viewBoard)?.key, "2")
        XCTAssertEqual(MacMenuShortcuts.binding(for: .viewChat)?.key, "3")
        XCTAssertNotNil(MacMenuShortcuts.binding(for: .filter))
    }

    /// Two menu items on the same keystroke means one of them silently never fires.
    func testNoTwoCommandsShareAKeystroke() {
        var seen: Set<String> = []
        for binding in MacMenuShortcuts.all {
            let stroke = "\(binding.modifiers.rawValue):\(binding.key)"
            XCTAssertFalse(seen.contains(stroke), "\(binding.command) collides on \(stroke)")
            seen.insert(stroke)
        }
    }

    /// ⌘-menu equivalents must never collide with the shared bare-key scheme, which is a
    /// cross-platform contract — every one of them carries a modifier.
    func testEveryMenuShortcutCarriesAModifier() {
        for binding in MacMenuShortcuts.all {
            XCTAssertFalse(binding.modifiers.isEmpty,
                           "\(binding.command) is a bare key and would collide with the web scheme")
        }
    }

    /// Menu titles are user-facing, so they come from Localizable.strings.
    func testTitlesAreLocalized() {
        for binding in MacMenuShortcuts.all {
            let title = binding.title
            XCTAssertFalse(title.isEmpty)
            XCTAssertNotEqual(title, binding.titleKey, "\(binding.command) shows a raw key")
        }
    }

    /// The ⌘/ sheet advertises exactly what the menus bind — the drift this task is about ran the
    /// other way (the sheet promised more than the menu delivered).
    func testHelpSheetAdvertisesExactlyTheMenuTable() {
        XCTAssertEqual(MacShortcutsHelpModel.menuRows.map(\.command), MacMenuShortcuts.all.map(\.command))
    }

    /// The display form is what the user reads in the sheet: ⌘F, ⌘⇧F, ⌘1.
    func testDisplayFormUsesMacGlyphs() {
        XCTAssertEqual(MacMenuShortcuts.display(for: .search), "⌘F")
        XCTAssertEqual(MacMenuShortcuts.display(for: .viewList), "⌘1")
        XCTAssertEqual(MacMenuShortcuts.display(for: .filter), "⇧⌘F",
                       "Modifier glyphs follow the Mac order ⌃⌥⇧⌘")
    }
}

/// ⌘1/⌘2/⌘3 landing behaviour (Task e0412a64).
final class MacViewModeTests: XCTestCase {

    func testARealListHonoursTheRequestedMode() {
        XCTAssertEqual(MacViewMode.resolve(requested: .board, isRealList: true), .board)
        XCTAssertEqual(MacViewMode.resolve(requested: .chat, isRealList: true), .chat)
        XCTAssertEqual(MacViewMode.resolve(requested: .list, isRealList: true), .list)
    }

    /// My Tasks and Search have neither a board nor a channel, so ⌘2/⌘3 fall back to the list
    /// rather than switching to an empty pane — a menu item that appears to do nothing reads as
    /// broken, which is the complaint this task started from.
    func testVirtualSelectionsFallBackToTheList() {
        XCTAssertEqual(MacViewMode.resolve(requested: .board, isRealList: false), .list)
        XCTAssertEqual(MacViewMode.resolve(requested: .chat, isRealList: false), .list)
        XCTAssertEqual(MacViewMode.resolve(requested: .list, isRealList: false), .list)
    }
}
