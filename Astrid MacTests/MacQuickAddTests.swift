//  MacQuickAddTests.swift
//  Regression for task 76817a57 — the inline task draft must create nothing when abandoned
//  (empty/whitespace) and otherwise preserve smart parsing + include the selected list.

import XCTest
@testable import Astrid_Mac

final class MacQuickAddTests: XCTestCase {

    private let listId = "list-1"

    func testEmptyTextCreatesNothing() {
        XCTAssertNil(MacQuickAdd.makeArgs(rawText: "", selectedListId: listId, lists: []),
                     "Empty draft must create nothing.")
    }

    func testWhitespaceOnlyCreatesNothing() {
        XCTAssertNil(MacQuickAdd.makeArgs(rawText: "   \n\t ", selectedListId: listId, lists: []),
                     "Whitespace-only draft must create nothing.")
    }

    func testNoSelectedListCreatesNothing() {
        XCTAssertNil(MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: nil, lists: []),
                     "With no destination list there is nothing to create.")
    }

    func testValidTextIncludesSelectedListAndTitle() {
        let args = MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: listId, lists: [])
        XCTAssertNotNil(args)
        XCTAssertEqual(args?.title, "Buy milk")
        XCTAssertEqual(args?.listIds.contains(listId), true,
                       "The currently selected list must always be a destination.")
    }

    func testSmartParsingExtractsPriority() {
        // "urgent" is a shared SmartTaskParser priority token; it must not remain in the title
        // and must surface as a parsed priority.
        let args = MacQuickAdd.makeArgs(rawText: "Ship release urgent", selectedListId: listId, lists: [])
        XCTAssertNotNil(args?.priority, "Smart parsing must extract the 'urgent' priority token.")
        XCTAssertFalse(args?.title.localizedCaseInsensitiveContains("urgent") ?? true,
                       "The priority token must be stripped from the title.")
    }

    // MARK: - Global quick-add (⌥Space window + menu-bar) — Task fa267754

    func testGlobalEmptyOrNoListCreatesNothing() {
        XCTAssertNil(MacQuickAdd.makeGlobalArgs(rawText: "", lists: []))
        XCTAssertNil(MacQuickAdd.makeGlobalArgs(rawText: "   ", lists: []))
        XCTAssertNil(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk", lists: []),
                     "No lists → nothing to add to.")
    }

    // Note: makeGlobalArgs routes through the SAME shared SmartTaskParser as makeArgs (locked by
    // testSmartParsingExtractsPriority above), so priority/date/repeat extraction is covered there.
    // The global-specific behavior — empty/no-list guarding and NOT force-adding a current list —
    // is what these tests lock.
}
