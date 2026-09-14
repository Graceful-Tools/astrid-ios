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

    // MARK: - AITD-402: quick entry asks the SHARED parser

    /// `QuickEntryParser` used to live in `Astrid Mac/Support/`: 43 lines that understood
    /// `#list` plus the words "today" and "tomorrow", and nothing else. Task fa267754 moved every
    /// caller to `SmartTaskParser` — which already compiled for this target — but left the old
    /// struct and three tests behind, so a dead parser stayed green and looked maintained.
    ///
    /// The guard is not "that file is gone". It is that Mac quick-add keeps asking the one
    /// engine, so the hotkey window can never quietly grow a weaker parse than the sidebar.
    func testAITD402_MacQuickAddParsesThroughTheSharedSmartTaskParser() throws {
        let root = RepositoryLocator.root.appendingPathComponent("Astrid Mac")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))

        var sawSharedParser = false
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains("SmartTaskParser.parse(") { sawSharedParser = true }

            for line in source.components(separatedBy: .newlines) {
                let code = line.trimmingCharacters(in: .whitespaces)
                // The surviving comment in QuickEntryView records why it went — not a call site.
                guard !code.hasPrefix("//") else { continue }
                XCTAssertFalse(code.contains("QuickEntryParser"),
                               "\(url.lastPathComponent): quick entry parses with SmartTaskParser now")
            }
        }
        XCTAssertTrue(sawSharedParser, "AITD-402: the Mac must still reach the shared parser")
    }
}
