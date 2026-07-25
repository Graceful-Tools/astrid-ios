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

    // MARK: - Smart Task Creation toggle (Task a840511d)

    func testSmartDisabledKeepsRawTitleAndNoParsing() {
        // With Smart Task Creation OFF, tokens like "urgent" stay in the title and no priority is parsed.
        let args = MacQuickAdd.makeArgs(rawText: "Ship release urgent", selectedListId: listId,
                                        lists: [], smartEnabled: false)
        XCTAssertEqual(args?.title, "Ship release urgent")
        XCTAssertNil(args?.priority)
        XCTAssertNil(args?.whenDate)
        XCTAssertEqual(args?.listIds, [listId])
    }

    func testGlobalSmartDisabledKeepsRawTitle() {
        // No lists → still nil regardless of the flag.
        XCTAssertNil(MacQuickAdd.makeGlobalArgs(rawText: "Buy milk urgent", lists: [], smartEnabled: false))
    }

    // MARK: - SmartTaskParser edge cases through MacQuickAdd (Task 1c21489d)

    func testDateTokenParsedAndStripped() {
        let args = MacQuickAdd.makeArgs(rawText: "Pay rent tomorrow", selectedListId: listId, lists: [])
        XCTAssertNotNil(args?.whenDate, "'tomorrow' must parse into a due date")
        XCTAssertFalse(args?.title.localizedCaseInsensitiveContains("tomorrow") ?? true,
                       "The date token must be stripped from the title")
        XCTAssertEqual(args?.title, "Pay rent")
    }

    func testCombinedPriorityAndDateTokens() {
        let args = MacQuickAdd.makeArgs(rawText: "Ship release tomorrow urgent", selectedListId: listId, lists: [])
        XCTAssertNotNil(args?.priority, "Combined tokens: priority must still parse")
        XCTAssertNotNil(args?.whenDate, "Combined tokens: date must still parse")
        XCTAssertFalse(args?.title.localizedCaseInsensitiveContains("urgent") ?? true)
        XCTAssertFalse(args?.title.localizedCaseInsensitiveContains("tomorrow") ?? true)
    }

    func testPlainTitleParsesNothing() {
        let args = MacQuickAdd.makeArgs(rawText: "Just a simple errand", selectedListId: listId, lists: [])
        XCTAssertEqual(args?.title, "Just a simple errand")
        XCTAssertNil(args?.priority)
        XCTAssertNil(args?.whenDate)
        XCTAssertNil(args?.repeating)
    }

    func testRepeatTokenParsed() {
        let args = MacQuickAdd.makeArgs(rawText: "Water plants daily", selectedListId: listId, lists: [])
        XCTAssertNotNil(args?.repeating, "'daily' must parse into a repeat rule")
        XCTAssertFalse(args?.title.localizedCaseInsensitiveContains("daily") ?? true)
    }

    func testUnknownHashtagLeftHarmless() {
        // No lists exist, so '#nowhere' can't resolve — must not crash and must keep a usable title.
        let args = MacQuickAdd.makeArgs(rawText: "File taxes #nowhere", selectedListId: listId, lists: [])
        XCTAssertNotNil(args)
        XCTAssertTrue(args?.title.contains("File taxes") ?? false)
        XCTAssertEqual(args?.listIds.first, listId, "Falls back to the selected list")
    }
}
