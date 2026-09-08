//  GitHubSyncFetchCountTests.swift
//  Task AITD-343 — GitHub sync fetched the list's task links twice per pass.
//
//  `sync(link:)` called `getGitHubTaskLinks(listId:)` at the top to build `byRemoteId`/`byTaskId`,
//  and again in the comments phase to recover the persisted `commentMap` — because the upserts in
//  between replace entries in `byRemoteId` with locally-built DTOs that do not carry the
//  server-merged metadata. One redundant full fetch per linked list, on EVERY pass: every
//  foreground, every SSE nudge, every mutation debounce.
//
//  The data was already in hand at the first fetch. Capturing the maps there is equivalent
//  because `commentMap` is only ever written by `syncComments`, which runs later in the pass.

import XCTest
@testable import Astrid_App

final class GitHubSyncFetchCountTests: XCTestCase {

    private func syncPassBody() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/Sync/GitHubSyncService.swift"),
            encoding: .utf8)

        let start = try XCTUnwrap(source.range(of: "private func sync(link: ExternalListLinkDTO) async throws {"),
                                  "sync(link:) is gone — this guard is reading nothing")
        let rest = source[start.upperBound...]
        // Up to the next method at the same indentation.
        let end = rest.range(of: "\n    private func ") ?? rest.range(of: "\n    func ")
        let body = end.map { String(rest[..<$0.lowerBound]) } ?? String(rest)

        // Comments explain the fix and name the call being counted, so they must not be counted.
        return body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testASyncPassFetchesTheTaskLinksExactlyOnce() throws {
        let body = try syncPassBody()
        let calls = body.components(separatedBy: "getGitHubTaskLinks(").count - 1
        XCTAssertEqual(calls, 1,
                       "one full task-link fetch per linked list per pass — the second one was "
                       + "recovering metadata the first had already returned (AITD-343)")
    }

    func testTheCommentMapsStillComeFromServerMetadata() throws {
        let body = try syncPassBody()
        XCTAssertTrue(body.contains(#"CommentSyncPlanner.decodeEntries($0.metadata?["commentMap"])"#),
                      "the maps must still be decoded from the link metadata the server merged — "
                      + "dropping the second fetch must not mean dropping the data")
    }

    /// Order is the correctness argument. The maps have to be taken from the fetched links BEFORE
    /// the upserts replace those entries with local DTOs, which is the whole reason a second
    /// fetch existed.
    func testTheMapsAreCapturedBeforeTheUpsertsOverwriteTheDTOs() throws {
        let body = try syncPassBody()
        let capture = try XCTUnwrap(body.range(of: "let commentMaps = Dictionary("))
        let firstUse = try XCTUnwrap(body.range(of: "commentMaps[remoteId]"))
        XCTAssertTrue(capture.lowerBound < firstUse.lowerBound)

        let fetch = try XCTUnwrap(body.range(of: "getGitHubTaskLinks("))
        XCTAssertTrue(fetch.lowerBound < capture.lowerBound,
                      "captured from the fetch's own result, not re-derived later")
    }
}
