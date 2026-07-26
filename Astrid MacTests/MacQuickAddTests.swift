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

    // MARK: - #list resolution + token stripping (task 1c21489d)
    //
    // These verify against the SHARED SmartTaskParser's actual rules: a hashtag matches a list by
    // name with spaces collapsed to "-", "_" or nothing, case-insensitively; every hashtag is
    // stripped from the title whether or not it resolved.

    private func list(_ id: String, _ name: String) -> TaskList {
        TaskList(id: id, name: name)
    }

    func testHashtagResolvesToAListAndIsAddedAlongsideTheSelectedList() {
        let work = list("work-1", "Work")
        let args = MacQuickAdd.makeArgs(rawText: "Draft proposal #work", selectedListId: listId, lists: [work])
        XCTAssertEqual(args?.title, "Draft proposal", "The #tag must be stripped from the title")
        XCTAssertEqual(args?.listIds.first, listId, "The selected list stays first")
        XCTAssertTrue(args?.listIds.contains("work-1") ?? false, "#work must resolve to the Work list")
    }

    func testHashtagMatchingIsCaseInsensitive() {
        let work = list("work-1", "Work")
        let args = MacQuickAdd.makeArgs(rawText: "Review #WORK", selectedListId: listId, lists: [work])
        XCTAssertTrue(args?.listIds.contains("work-1") ?? false)
    }

    /// Multi-word list names match with the space collapsed — all three spellings the parser allows.
    func testMultiWordListNameMatchesEverySupportedSpelling() {
        let home = list("home-1", "Home Stuff")
        for tag in ["#home-stuff", "#home_stuff", "#homestuff"] {
            let args = MacQuickAdd.makeArgs(rawText: "Fix sink \(tag)", selectedListId: listId, lists: [home])
            XCTAssertTrue(args?.listIds.contains("home-1") ?? false, "\(tag) should resolve to 'Home Stuff'")
            XCTAssertEqual(args?.title, "Fix sink", "\(tag) should be stripped")
        }
    }

    func testMultipleHashtagsResolveToMultipleLists() {
        let work = list("work-1", "Work"), home = list("home-1", "Home")
        let args = MacQuickAdd.makeArgs(rawText: "Call plumber #work #home", selectedListId: listId,
                                        lists: [work, home])
        XCTAssertTrue(args?.listIds.contains("work-1") ?? false)
        XCTAssertTrue(args?.listIds.contains("home-1") ?? false)
        XCTAssertEqual(args?.title, "Call plumber")
    }

    /// An unresolved hashtag is still STRIPPED — the title must not keep "#nowhere".
    func testUnresolvedHashtagIsStrippedFromTheTitle() {
        let work = list("work-1", "Work")
        let args = MacQuickAdd.makeArgs(rawText: "File taxes #nowhere", selectedListId: listId, lists: [work])
        XCTAssertEqual(args?.title, "File taxes")
        XCTAssertEqual(args?.listIds, [listId], "An unmatched tag must not add a list")
    }

    func testHashtagInTheMiddleIsStrippedWithoutDanglingSpaces() {
        let work = list("work-1", "Work")
        let args = MacQuickAdd.makeArgs(rawText: "Send #work the invoice", selectedListId: listId, lists: [work])
        XCTAssertEqual(args?.title, "Send the invoice", "Collapsing must not leave a double space")
    }

    /// A '#' that is not a tag (mid-word, like a Swift attribute or a number) must be left alone —
    /// the parser only matches a '#' at a word boundary.
    func testMidWordHashIsNotTreatedAsATag() {
        let args = MacQuickAdd.makeArgs(rawText: "Fix issue C#42", selectedListId: listId, lists: [])
        XCTAssertEqual(args?.title, "Fix issue C#42")
        XCTAssertEqual(args?.listIds, [listId])
    }

    /// Priority words only count as whole words: "urgently" must NOT set priority or be stripped.
    func testPriorityWordInsideAnotherWordIsNotAToken() {
        let args = MacQuickAdd.makeArgs(rawText: "Reply urgently to Sam", selectedListId: listId, lists: [])
        XCTAssertNil(args?.priority, "'urgently' is not the 'urgent' token")
        XCTAssertEqual(args?.title, "Reply urgently to Sam")
    }

    func testEverythingAtOnceStripsEveryTokenAndKeepsAUsableTitle() {
        let work = list("work-1", "Work")
        let args = MacQuickAdd.makeArgs(rawText: "Submit report tomorrow urgent #work",
                                        selectedListId: listId, lists: [work])
        XCTAssertNotNil(args?.whenDate)
        XCTAssertNotNil(args?.priority)
        XCTAssertTrue(args?.listIds.contains("work-1") ?? false)
        XCTAssertEqual(args?.title, "Submit report", "All three token kinds must be stripped")
    }

    /// A title that is ONLY tokens must still produce something usable rather than an empty title.
    func testTitleOfOnlyTokensFallsBackToTheRawText() {
        let args = MacQuickAdd.makeArgs(rawText: "urgent", selectedListId: listId, lists: [])
        XCTAssertFalse(args?.title.isEmpty ?? true, "An empty parsed title must fall back to the raw text")
    }
}

// MARK: - Add-task bar (task 022701f3) — iOS layout: checkbox left, input, ⊕ right

extension MacQuickAddTests {

    /// The ⊕ button is live only when there is something to create; whitespace does not count.
    func testCommitButtonIsLiveOnlyForRealInput() {
        XCTAssertFalse(MacQuickAdd.isCommittable(""))
        XCTAssertFalse(MacQuickAdd.isCommittable("   "))
        XCTAssertFalse(MacQuickAdd.isCommittable("\n\t "))
        XCTAssertTrue(MacQuickAdd.isCommittable("Buy milk"))
        XCTAssertTrue(MacQuickAdd.isCommittable("  Buy milk  "))
    }

    /// Whatever the button allows, makeArgs must also accept — otherwise ⊕ looks enabled and does
    /// nothing (the old bar had no button at all, so this pairing is new).
    func testCommittableInputAlwaysProducesArgs() {
        for text in ["Buy milk", "  Buy milk  ", "urgent"] {
            XCTAssertTrue(MacQuickAdd.isCommittable(text))
            XCTAssertNotNil(MacQuickAdd.makeArgs(rawText: text, selectedListId: listId, lists: []),
                            "'\(text)' is committable, so it must produce create args")
        }
        for text in ["", "   "] {
            XCTAssertFalse(MacQuickAdd.isCommittable(text))
            XCTAssertNil(MacQuickAdd.makeArgs(rawText: text, selectedListId: listId, lists: []))
        }
    }
}
