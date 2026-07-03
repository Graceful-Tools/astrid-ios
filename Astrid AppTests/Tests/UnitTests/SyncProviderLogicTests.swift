import XCTest
@testable import Astrid_App

/// Echo suppression + Google due mapping — the pure rules behind the GitHub /
/// Google sync workers. A wrong comparison here means either an infinite echo
/// loop (our own push bounces back as an inbound edit) or silently dropped
/// edits (a real remote change mistaken for an echo).
final class SyncProviderLogicTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var t1: Date { t0.addingTimeInterval(60) }

    // MARK: - PULL suppression (remoteUpdatedAt vs remote watermark)

    func testPull_remoteNewerThanWatermark_applies() {
        XCTAssertTrue(SyncSuppression.shouldApplyRemote(remoteUpdatedAt: t1, watermark: t0))
    }

    func testPull_remoteEqualToWatermark_isEcho_skipped() {
        // Equal timestamp = the write we just recorded — must NOT re-apply.
        XCTAssertFalse(SyncSuppression.shouldApplyRemote(remoteUpdatedAt: t0, watermark: t0))
    }

    func testPull_remoteOlderThanWatermark_stale_skipped() {
        XCTAssertFalse(SyncSuppression.shouldApplyRemote(remoteUpdatedAt: t0, watermark: t1))
    }

    func testPull_missingTimestamps_applies() {
        // Can't prove it's an echo without both timestamps — err on applying.
        XCTAssertTrue(SyncSuppression.shouldApplyRemote(remoteUpdatedAt: nil, watermark: t0))
        XCTAssertTrue(SyncSuppression.shouldApplyRemote(remoteUpdatedAt: t0, watermark: nil))
        XCTAssertTrue(SyncSuppression.shouldApplyRemote(remoteUpdatedAt: nil, watermark: nil))
    }

    // MARK: - PUSH suppression (local updatedAt vs astrid watermark)

    func testPush_localNewerThanWatermark_pushes() {
        XCTAssertTrue(SyncSuppression.shouldPushLocal(localUpdatedAt: t1, watermark: t0))
    }

    func testPush_localEqualToWatermark_alreadyPushed_skipped() {
        XCTAssertFalse(SyncSuppression.shouldPushLocal(localUpdatedAt: t0, watermark: t0))
    }

    func testPush_localOlderThanWatermark_skipped() {
        XCTAssertFalse(SyncSuppression.shouldPushLocal(localUpdatedAt: t0, watermark: t1))
    }

    func testPush_missingTimestamps_pushes() {
        XCTAssertTrue(SyncSuppression.shouldPushLocal(localUpdatedAt: nil, watermark: t0))
        XCTAssertTrue(SyncSuppression.shouldPushLocal(localUpdatedAt: t0, watermark: nil))
    }

    // MARK: - Google date-only due mapping

    private var utcMidnight: Date {
        var utc = Calendar.current
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.startOfDay(for: t0)
    }

    func testDue_adoptWhenLocalHasNoDue() {
        XCTAssertEqual(
            GoogleDueMapping.adoptedDue(remoteDue: utcMidnight, localDue: nil, localIsAllDay: false),
            utcMidnight
        )
    }

    func testDue_adoptWhenLocalIsAllDayAndDiffers() {
        let localAllDay = utcMidnight.addingTimeInterval(-86_400)
        XCTAssertEqual(
            GoogleDueMapping.adoptedDue(remoteDue: utcMidnight, localDue: localAllDay, localIsAllDay: true),
            utcMidnight
        )
    }

    func testDue_neverClobbersTimedLocalDue() {
        // Google is date-only; the local task holds a TIME. Adopting would
        // silently erase the time — must be skipped.
        let timedLocal = utcMidnight.addingTimeInterval(9 * 3600)  // 09:00
        XCTAssertNil(
            GoogleDueMapping.adoptedDue(remoteDue: utcMidnight, localDue: timedLocal, localIsAllDay: false)
        )
    }

    func testDue_noOpWhenAlreadyEqual() {
        XCTAssertNil(
            GoogleDueMapping.adoptedDue(remoteDue: utcMidnight, localDue: utcMidnight, localIsAllDay: true)
        )
    }

    func testDue_nilRemoteAdoptsNothing() {
        XCTAssertNil(GoogleDueMapping.adoptedDue(remoteDue: nil, localDue: nil, localIsAllDay: true))
    }

    func testDue_pushStringIsUTCStartOfDay() {
        let nineAM = utcMidnight.addingTimeInterval(9 * 3600)
        let s = GoogleDueMapping.pushDueString(for: nineAM)
        XCTAssertTrue(s.hasSuffix("T00:00:00Z"), "expected UTC midnight, got \(s)")
        XCTAssertEqual(GoogleDueMapping.formatter.date(from: s), utcMidnight)
    }

    // MARK: - Pull ordering (parents before children)

    private struct Item { let id: String; let parent: String? }

    private func order(_ items: [Item]) -> [String] {
        SyncPullOrdering.parentsFirst(items, id: \.id, parentId: \.parent).map(\.id)
    }

    func testOrdering_parentBeforeChild_regardlessOfInputOrder() {
        let ordered = order([Item(id: "child", parent: "parent"), Item(id: "parent", parent: nil)])
        XCTAssertEqual(ordered, ["parent", "child"])
    }

    func testOrdering_threeLevels() {
        let ordered = order([
            Item(id: "grandchild", parent: "child"),
            Item(id: "child", parent: "parent"),
            Item(id: "parent", parent: nil),
        ])
        XCTAssertEqual(ordered, ["parent", "child", "grandchild"])
    }

    func testOrdering_parentOutsideWindowTreatedAsReady() {
        // The parent isn't in this pull (already linked earlier) — the child
        // must not be starved waiting for it.
        let ordered = order([Item(id: "child", parent: "already-linked-elsewhere")])
        XCTAssertEqual(ordered, ["child"])
    }

    func testOrdering_cycleEmitsEverything() {
        let ordered = order([Item(id: "a", parent: "b"), Item(id: "b", parent: "a")])
        XCTAssertEqual(Set(ordered), ["a", "b"])
    }

    func testDue_pushAndAdoptRoundTripIsStable() {
        // Push a local all-day due to Google, parse it back, and re-adopt:
        // must be a no-op (the loop-avoidance property for Google's due field).
        let s = GoogleDueMapping.pushDueString(for: utcMidnight)
        let parsedBack = GoogleDueMapping.formatter.date(from: s)
        XCTAssertNil(
            GoogleDueMapping.adoptedDue(remoteDue: parsedBack, localDue: utcMidnight, localIsAllDay: true)
        )
    }
}
