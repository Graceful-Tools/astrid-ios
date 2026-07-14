//  CommandAndQuickEntryTests.swift
//  Astrid for Mac — M2 palette (fuzzy + registry) and quick-entry parsing.

import XCTest
@testable import Astrid_Mac

final class CommandAndQuickEntryTests: XCTestCase {

    // MARK: FuzzyMatch
    func testFuzzyMatchesSubsequence() {
        XCTAssertNotNil(FuzzyMatch.score("nt", "New Task"))
        XCTAssertNil(FuzzyMatch.score("zzz", "New Task"))
    }

    func testFuzzyPrefixOutscoresMidword() {
        let prefix = FuzzyMatch.score("new", "New Task")!
        let mid = FuzzyMatch.score("new", "Renew Ticket")!
        XCTAssertGreaterThan(prefix, mid)
    }

    // MARK: CommandRegistry
    func testRegistrySearchRanksBestFirst() {
        let reg = CommandRegistry(commands: [
            AppCommand(id: "delete", title: "Delete Task", subtitle: nil, shortcut: nil, run: {}),
            AppCommand(id: "new", title: "New Task", subtitle: nil, shortcut: nil, run: {}),
        ])
        let results = reg.search("new")
        XCTAssertEqual(results.first?.id, "new")
    }

    func testRegistryEmptyQueryReturnsAllInOrder() {
        let reg = CommandRegistry(commands: [
            AppCommand(id: "a", title: "Alpha", subtitle: nil, shortcut: nil, run: {}),
            AppCommand(id: "b", title: "Beta", subtitle: nil, shortcut: nil, run: {}),
        ])
        XCTAssertEqual(reg.search("").map(\.id), ["a", "b"])
    }

    func testRegistryRunInvokesAction() {
        var ran = false
        let cmd = AppCommand(id: "x", title: "X", subtitle: nil, shortcut: nil, run: { ran = true })
        cmd.run()
        XCTAssertTrue(ran)
    }

    // MARK: QuickEntryParser
    func testParsesListTokensAndDueHint() {
        let r = QuickEntryParser.parse("Buy milk #groceries #home tomorrow")
        XCTAssertEqual(r.title, "Buy milk")
        XCTAssertEqual(r.listNames, ["groceries", "home"])
        XCTAssertEqual(r.due, .tomorrow)
    }

    func testParsesPlainTitle() {
        let r = QuickEntryParser.parse("  Call the dentist  ")
        XCTAssertEqual(r.title, "Call the dentist")
        XCTAssertTrue(r.listNames.isEmpty)
        XCTAssertNil(r.due)
    }

    func testTodayHintStripped() {
        let r = QuickEntryParser.parse("Standup today")
        XCTAssertEqual(r.title, "Standup")
        XCTAssertEqual(r.due, .today)
    }
}
