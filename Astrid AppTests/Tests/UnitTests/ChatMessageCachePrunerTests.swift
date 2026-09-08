//  ChatMessageCachePrunerTests.swift
//  Task AITD-354 — cached chat messages were never pruned.
//
//  The task as filed said "mirror CommentCachePruner". These tests exist mostly to prove why that
//  would have been wrong: chat is PAGINATED, so "synced and absent ⇒ delete" would wipe every
//  message older than the newest fifty on every refresh.

import XCTest
@testable import Astrid_App

final class ChatMessageCachePrunerTests: XCTestCase {

    private func at(_ minutes: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(minutes) * 60) }

    private func row(_ id: String, _ minutes: Int?, status: String = "synced") -> ChatMessageCachePruner.CachedRow {
        ChatMessageCachePruner.CachedRow(id: id, syncStatus: status,
                                         createdAt: minutes.map { at($0) })
    }

    private func page(_ ids: [String], oldest: Int?, newest: Int? = nil,
                      whole: Bool = false) -> ChatMessageCachePruner.Page {
        ChatMessageCachePruner.Page(ids: Set(ids),
                                    oldest: oldest.map { at($0) },
                                    newest: (newest ?? oldest).map { at($0) },
                                    coversWholeChannel: whole)
    }

    // MARK: - The regression this task nearly shipped

    func testAPageDoesNotPruneAnythingOlderThanItself() {
        // The newest 50 arrive. Everything before them is still on the server, just not in this
        // response. Mirroring CommentCachePruner here would delete all of it.
        let cached = [row("ancient", 0), row("old", 10), row("recent", 100), row("newest", 110)]
        let latest = page(["recent", "newest"], oldest: 100, newest: 110)

        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: latest, cached: cached), [],
                       "a page can only speak for its own time window — pruning outside it "
                       + "silently destroys the offline history the cache exists to hold")
    }

    func testASecondPageDoesNotPruneTheFirst() {
        // `loadOlderMessages` pages backwards with a `before` cursor: this page is entirely older
        // than what is already cached, and must not take the newer rows with it.
        let cached = [row("older-a", 10), row("older-b", 20), row("newer", 500)]
        let olderPage = page(["older-a", "older-b"], oldest: 10, newest: 20)

        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: olderPage, cached: cached), [])
    }

    // MARK: - What it DOES prune

    func testAMessageDeletedInsideThePagesWindowIsPruned() {
        let cached = [row("kept", 100), row("deleted-server-side", 105), row("kept2", 110)]
        let latest = page(["kept", "kept2"], oldest: 100, newest: 110)

        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: latest, cached: cached),
                       ["deleted-server-side"],
                       "inside the window the page IS authoritative")
    }

    func testAMessageExactlyAtTheWindowEdgeIsInsideIt() {
        let cached = [row("edge", 100)]
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page(["other"], oldest: 100, newest: 100), cached: cached),
                       ["edge"], "the oldest message in the page bounds the window inclusively")
    }

    func testAWholeChannelPagePrunesEverythingAbsent() {
        // First page, nothing older behind it: this really is the entire channel, so absence
        // anywhere is deletion — the only case that behaves like the comment pruner.
        let cached = [row("gone-ancient", 0), row("gone-recent", 100), row("kept", 110)]
        let whole = page(["kept"], oldest: 110, newest: 110, whole: true)

        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: whole, cached: cached).sorted(),
                       ["gone-ancient", "gone-recent"])
    }

    // MARK: - Never take an undelivered write

    func testAPendingMessageIsNeverPruned() {
        let cached = [row("unsent", 105, status: "pending")]
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page([], oldest: 100, newest: 100, whole: true), cached: cached), [],
                       "a message the Outbox has not delivered is absent from the server by "
                       + "definition — pruning it destroys what the user typed (ASTRID.md rule 6)")
    }

    func testAFailedMessageIsNeverPruned() {
        let cached = [row("failed", 105, status: "failed")]
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page([], oldest: 100, newest: 100, whole: true), cached: cached), [])
    }

    func testAnOptimisticTempRowIsNeverPruned() {
        let cached = [row("temp_abc", 105)]
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page([], oldest: 100, newest: 100, whole: true), cached: cached), [],
                       "a temp id is an optimistic row mid-reconcile, not a deletion")
    }

    // MARK: - Degenerate inputs

    func testAnEmptyPageWithACursorPrunesNothing() {
        // Paging past the beginning legitimately returns nothing. That is not an emptied channel.
        let cached = [row("a", 10), row("b", 20)]
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page([], oldest: nil, newest: nil), cached: cached), [])
    }

    func testAnEmptiedChannelIsPrunedOnlyWhenThePageCoversIt() {
        let cached = [row("a", 10), row("b", 20)]
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page([], oldest: nil, newest: nil, whole: true), cached: cached).sorted(),
                       ["a", "b"])
    }

    func testARowWithNoCreatedAtIsKeptUnlessThePageCoversTheChannel() {
        let cached = [row("undated", nil)]
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page(["x"], oldest: 100, newest: 100), cached: cached), [],
                       "it cannot be placed in the window, and keeping a row costs disk while "
                       + "deleting a live one costs the user their history")
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page(["x"], oldest: 100, newest: 100, whole: true), cached: cached),
                       ["undated"])
    }

    func testNothingIsPrunedWhenTheServerReturnedEverythingWeHave() {
        let cached = [row("a", 100), row("b", 110)]
        XCTAssertEqual(ChatMessageCachePruner.idsToPrune(page: page(["a", "b"], oldest: 100, newest: 110, whole: true), cached: cached), [])
    }
}

/// The rule is only worth having if it is actually reached. These read `ChatService` because the
/// wiring — which fetch counts as "the whole channel" — is where a correct rule gets applied
/// wrongly, and that is invisible from the pruner's own tests.
final class ChatMessagePruneWiringTests: XCTestCase {

    private func code() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/Services/ChatService.swift"),
            encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testEveryMessageSaveSuppliesAPruningWindow() throws {
        let source = try code()
        let saves = source.components(separatedBy: "saveMessagesToCoreData(").count - 1
        // One definition plus its call sites.
        let calls = saves - 1
        let windows = source.components(separatedBy: "prune: Self.prunePage(").count - 1

        XCTAssertGreaterThan(calls, 0, "no call sites found — this guard is reading nothing")
        XCTAssertEqual(windows, calls,
                       "every fetch that writes messages must say what window it can speak for, "
                       + "or its rows are never pruned and the cache grows forever (AITD-354)")
    }

    /// The load-older path is the one that must NEVER claim to cover the channel: it pages
    /// backwards behind a `before` cursor, so treating it as authoritative would delete
    /// everything newer than it.
    func testTheLoadOlderPathDoesNotClaimToCoverTheChannel() throws {
        let source = try code()
        let start = try XCTUnwrap(source.range(of: "func loadMoreMessages(channelId: String)"))
        let body = String(source[start.upperBound...].prefix(1_200))

        XCTAssertTrue(body.contains("isFirstPage: false"),
                      "loadMoreMessages sends a `before` cursor, so its response is not the "
                      + "first page and can never be the whole channel")
    }

    func testTheFirstPagePathsReportTheirHasMore() throws {
        // `coversWholeChannel` is `isFirstPage && !hasMore`, so passing a hardcoded `hasMore:`
        // would be the way to accidentally authorise a full-channel prune.
        let source = try code()
        XCTAssertFalse(source.contains("hasMore: false)"),
                       "hasMore must come from the response, never be asserted at the call site")
        XCTAssertFalse(source.contains("hasMore: true)"))
    }
}
