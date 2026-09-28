//  LazyCacheHydrationTests.swift
//  Tasks AITD-341 and AITD-335 — launch materialised every cached chat message and every cached
//  comment before the UI was usable.
//
//  From Jon's launch log: "Comments loaded: 284340 comments for 27 tasks in 4451ms". The main
//  thread was blocked long enough that a 5 s Timer armed in `.onAppear` had already expired by
//  the time the run loop serviced its first fire.
//
//  Comments and chat live in astrid-core's cache now (docs/CORE_MIGRATION.md), which reads one
//  task's comments or one channel's messages by index. What these assert is that the two services
//  stayed that way: scoped reads through the core, and no Core Data table to hydrate at all.

import XCTest
@testable import Astrid_App

final class LazyCacheHydrationTests: XCTestCase {

    /// Code only — comments here explain what was removed and name the very calls being banned.
    private func code(_ path: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private let chat = "Astrid App/Core/Services/ChatService.swift"
    private let comments = "Astrid App/Core/Services/CommentService.swift"

    /// Neither service holds a Core Data cache to hydrate — the table that took 4.5 s at launch.
    func testNeitherServiceKeepsACoreDataCache() throws {
        for path in [chat, comments] {
            let source = try code(path)
            XCTAssertFalse(source.contains("import CoreData"), "\(path) went back to Core Data")
            XCTAssertFalse(source.contains("CDComment") || source.contains("CDChatMessage"),
                           "\(path) reads a Core Data table again (AITD-335/341)")
        }
    }

    /// Reads are per task and per channel — what a panel opening asks for, nothing more.
    func testReadsAreScopedToOneTaskOrOneChannel() throws {
        XCTAssertTrue(try code(comments).contains(#"CoreCommand(kind: "comments", taskId: taskId)"#))
        XCTAssertTrue(try code(chat).contains(#"CoreCommand(kind: "chatMessages", ["channelId": .value(channelId)])"#))
    }

    /// Nothing reads a whole channel set or every task's comments at init.
    func testNothingLoadsAtInit() throws {
        for path in [chat, comments] {
            let source = try code(path)
            let start = try XCTUnwrap(source.range(of: "init() {"), path)
            XCTAssertTrue(source[start.upperBound...].hasPrefix("}"), "\(path) does work at init again")
        }
    }
}
