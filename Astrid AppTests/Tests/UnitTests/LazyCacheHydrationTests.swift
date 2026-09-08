//  LazyCacheHydrationTests.swift
//  Tasks AITD-341 and AITD-335 — launch materialised every cached chat message and every cached
//  comment before the UI was usable.
//
//  From Jon's launch log: "Comments loaded: 284340 comments for 27 tasks in 4451ms". The main
//  thread was blocked long enough that a 5 s Timer armed in `.onAppear` had already expired by
//  the time the run loop serviced its first fire.
//
//  Hydration is a startup side effect with no return value, so what these assert is the SHAPE of
//  the two services: no whole-table fetch at init, and the scoped per-task / per-channel loaders
//  still in place and still what the fetch ladder uses. Delete the lazy path and these fail;
//  reintroduce the eager one and these fail.

import XCTest
@testable import Astrid_App

final class LazyCacheHydrationTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Code only — comments here explain what was removed and name the very calls being banned.
    private func code(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private let chat = "Astrid App/Core/Services/ChatService.swift"
    private let comments = "Astrid App/Core/Services/CommentService.swift"

    // MARK: - Nothing fetches the whole table

    func testChatDoesNotMaterialiseEveryStoredMessage() throws {
        XCTAssertFalse(try code(chat).contains("CDChatMessage.fetchAll"),
                       "every stored chat message was turned into a domain model at launch, "
                       + "before any chat panel had been opened (AITD-341)")
    }

    func testCommentsDoNotMaterialiseEveryStoredComment() throws {
        XCTAssertFalse(try code(comments).contains("CDComment.fetchAll"),
                       "284,340 comments in 4,451 ms of blocked launch (AITD-335)")
    }

    // MARK: - Because the scoped path already exists

    func testChatStillHasItsPerChannelLoader() throws {
        let source = try code(chat)
        XCTAssertTrue(source.contains("func loadMessagesFromCoreData(channelId: String)"),
                      "the scoped loader IS the replacement — without it, dropping the eager pass "
                      + "would lose the offline cache rather than defer it")
        XCTAssertTrue(source.contains("CDChatMessage.fetchByChannelId"),
                      "scoped to one channel, which is the whole point")
    }

    func testCommentsStillHaveTheirPerTaskLoader() throws {
        XCTAssertTrue(try code(comments).contains("func loadCommentsFromCoreData(taskId: String)"))
    }

    /// The ladder is what makes the deletion safe: a cold memory cache falls through to a scoped
    /// CoreData read, and only then to the network.
    func testTheFetchLadderStillReachesCoreDataBeforeTheNetwork() throws {
        let source = try code(chat)
        let start = try XCTUnwrap(source.range(of: "func fetchMessages(channelId: String"))
        let body = String(source[start.upperBound...].prefix(1_500))

        let memory = try XCTUnwrap(body.range(of: "cachedMessages[channelId]"))
        let coreData = try XCTUnwrap(body.range(of: "loadMessagesFromCoreData(channelId: channelId)"))
        XCTAssertTrue(memory.lowerBound < coreData.lowerBound,
                      "memory first, then CoreData — a cold cache must not skip straight to the network")
    }

    // MARK: - The startup work that genuinely belongs at startup

    func testTheCorruptedCommentCleanupStillRunsAtLaunch() throws {
        let source = try code(comments)
        let start = try XCTUnwrap(source.range(of: "func prepareCacheAtLaunch()"))
        let body = String(source[start.upperBound...].prefix(400))
        XCTAssertTrue(body.contains("cleanupCorruptedComments()"),
                      "dropping the hydration must not drop the corrupted-row cleanup with it — "
                      + "that one does have to happen at startup")
    }

    func testChatStillLoadsItsChannelMappingAtLaunch() throws {
        let source = try code(chat)
        XCTAssertTrue(source.contains("await self.loadCachedChannels()"),
                      "the list→channel id mapping is small and is what lets a panel know which "
                      + "channel to ask for at all — it is not the thing that was slow")
        XCTAssertFalse(source.contains("await self.loadCachedMessages()"),
                       "the message hydration is what had to go")
    }
}
