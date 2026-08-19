//  AIAgentCacheMemoTests.swift
//  Regression guard for the Mac CPU burn found on TestFlight build 901.
//
//  A `cpu_resource.diag` showed Astrid using 90s of CPU over 114s — 79% sustained, at idle.
//  The sampled stack was all SwiftUI layout, and the only Astrid frames in it were
//  `MacLeadingControlButton.face`, `.body`, `.kind` … with heavy `initializeWithCopy for Task`
//  churn underneath.
//
//  `face` resolves the assignee's avatar through
//  `AssigneeResolver.resolve(..., agents: AIAgentCache.shared.load() ?? [])`, and `load()` read
//  `UserDefaults` AND JSON-DECODED an array of `User` on every call. That is a computed view
//  property: it runs on every body evaluation, for every board card, on every layout pass.
//
//  Ten call sites use `load()`, four of them inside view bodies on both platforms, so the fix
//  belongs in the cache rather than at any one of them.
//
//  The decode still happens when the data actually changes — keyed on the stored timestamp, so
//  a write from the share extension is still picked up.

import XCTest
@testable import Astrid_App

final class AIAgentCacheMemoTests: XCTestCase {

    private func makeAgents(_ n: Int) -> [User] {
        (0..<n).map { User(id: "agent-\($0)", email: "a\($0)@astrid.cc", name: "Agent \($0)", image: nil) }
    }

    override func setUp() {
        super.setUp()
        AIAgentCache.shared.clear()
    }

    override func tearDown() {
        AIAgentCache.shared.clear()
        super.tearDown()
    }

    /// THE BUG: every call decoded the whole array again.
    ///
    /// After a save there is nothing to decode at all — `save` adopts the array it just wrote,
    /// because the next read is usually immediate and re-decoding our own value is exactly what
    /// this exists to avoid.
    func testRepeatedLoadsAfterASaveNeverDecode() {
        AIAgentCache.shared.save(makeAgents(5))
        let before = AIAgentCache.shared.decodeCount

        for _ in 0..<200 { _ = AIAgentCache.shared.load() }

        XCTAssertEqual(AIAgentCache.shared.decodeCount - before, 0,
                       "a warm cache must not decode — this ran on every SwiftUI body "
                       + "evaluation, for every board card, on every layout pass")
    }

    /// And from COLD — the app relaunched, the payload is on disk, nothing is in memory — the
    /// decode happens once and then never again.
    func testColdLoadsDecodeExactlyOnce() {
        // Write the payload without going through `save`, so nothing is memoised: this is the
        // state after a relaunch.
        let data = try! JSONEncoder().encode(makeAgents(5))
        UserDefaults.standard.set(data, forKey: "cached_ai_agents")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "cached_ai_agents_timestamp")
        let before = AIAgentCache.shared.decodeCount

        for _ in 0..<200 { _ = AIAgentCache.shared.load() }

        XCTAssertEqual(AIAgentCache.shared.decodeCount - before, 1,
                       "the first read decodes; the other 199 must not")
    }

    /// And it still returns the right thing.
    func testLoadStillReturnsWhatWasSaved() {
        AIAgentCache.shared.save(makeAgents(3))
        XCTAssertEqual(AIAgentCache.shared.load()?.map(\.id), ["agent-0", "agent-1", "agent-2"])
        XCTAssertEqual(AIAgentCache.shared.load()?.count, 3, "a second read agrees with the first")
    }

    /// A new save must be visible immediately — memoising the OLD value is the obvious way to
    /// break this.
    func testASaveIsVisibleToTheNextLoad() {
        AIAgentCache.shared.save(makeAgents(2))
        _ = AIAgentCache.shared.load()

        AIAgentCache.shared.save(makeAgents(4))
        XCTAssertEqual(AIAgentCache.shared.load()?.count, 4, "the memo must not outlive a save")
    }

    func testClearIsVisibleToTheNextLoad() {
        AIAgentCache.shared.save(makeAgents(2))
        _ = AIAgentCache.shared.load()

        AIAgentCache.shared.clear()
        XCTAssertNil(AIAgentCache.shared.load(), "the memo must not outlive a clear")
    }

    /// A write from ANOTHER process — the share extension shares this UserDefaults — must be
    /// picked up. That is why the memo is keyed on the stored timestamp rather than just held.
    func testAnExternalWriteIsPickedUp() {
        AIAgentCache.shared.save(makeAgents(2))
        XCTAssertEqual(AIAgentCache.shared.load()?.count, 2)

        // Simulate the other process: write the payload directly, bypassing save().
        let data = try! JSONEncoder().encode(makeAgents(7))
        UserDefaults.standard.set(data, forKey: "cached_ai_agents")
        UserDefaults.standard.set(Date().timeIntervalSince1970 + 1, forKey: "cached_ai_agents_timestamp")

        XCTAssertEqual(AIAgentCache.shared.load()?.count, 7,
                       "a newer timestamp must invalidate the memo")
    }
}
