import XCTest
@testable import Astrid_App

/// Echo suppression + Google due mapping — the pure rules behind the GitHub /
/// Google sync workers. A wrong comparison here means either an infinite echo
/// loop (our own push bounces back as an inbound edit) or silently dropped
/// edits (a real remote change mistaken for an echo).
final class SyncProviderLogicTests: XCTestCase {
    private actor CommitRecorder {
        private(set) var cursors: [String] = []
        func record(_ cursor: String) { cursors.append(cursor) }
    }
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var t1: Date { t0.addingTimeInterval(60) }

    // MARK: - Pass acknowledgement safety

    func testAcknowledgement_cleanPullPassCanCommitCursor() {
        var acknowledgement = SyncPassAcknowledgement()
        acknowledgement.recordAppliedItem()
        acknowledgement.recordAppliedItem()
        XCTAssertTrue(acknowledgement.canCommitCursor)
        XCTAssertEqual(acknowledgement.appliedItemCount, 2)
    }

    func testAcknowledgement_anyRequiredApplyFailurePreventsCursorCommit() {
        var acknowledgement = SyncPassAcknowledgement()
        acknowledgement.recordAppliedItem()
        acknowledgement.recordFailure()
        acknowledgement.recordAppliedItem()
        XCTAssertFalse(acknowledgement.canCommitCursor)
    }

    func testCursorCommitter_commitsExactlyOnceForCleanPass() async throws {
        let recorder = CommitRecorder()
        let committed = try await ProviderCursorCommitter.commitIfSafe(
            acknowledgement: SyncPassAcknowledgement(), cursor: "cursor-1"
        ) { cursor in await recorder.record(cursor) }
        XCTAssertTrue(committed)
        let cursors = await recorder.cursors
        XCTAssertEqual(cursors, ["cursor-1"])
    }

    func testCursorCommitter_failedApplyNeverCallsCommit() async throws {
        var acknowledgement = SyncPassAcknowledgement()
        acknowledgement.recordFailure()
        let recorder = CommitRecorder()
        let committed = try await ProviderCursorCommitter.commitIfSafe(
            acknowledgement: acknowledgement, cursor: "cursor-1"
        ) { cursor in await recorder.record(cursor) }
        XCTAssertFalse(committed)
        let cursors = await recorder.cursors
        XCTAssertTrue(cursors.isEmpty)
    }

    // MARK: - Push-side adoption safety

    func testAdoptionSafety_completeListingAllowsCreateWhenNoTwinExists() {
        XCTAssertTrue(SyncAdoptionSafety.mayCreateRemote(
            fullListingAvailable: true, listingTruncated: false, matchingTwinExists: false))
    }

    func testAdoptionSafety_failedListingNeverAllowsCreate() {
        XCTAssertFalse(SyncAdoptionSafety.mayCreateRemote(
            fullListingAvailable: false, listingTruncated: false, matchingTwinExists: false))
    }

    func testAdoptionSafety_truncatedListingNeverAllowsCreate() {
        XCTAssertFalse(SyncAdoptionSafety.mayCreateRemote(
            fullListingAvailable: true, listingTruncated: true, matchingTwinExists: false))
    }

    func testAdoptionSafety_existingTwinNeverAllowsCreate() {
        XCTAssertFalse(SyncAdoptionSafety.mayCreateRemote(
            fullListingAvailable: true, listingTruncated: false, matchingTwinExists: true))
    }

    // MARK: - Provider mutation nudges

    func testMutationNudge_ignoresEchoFromSameProvider() {
        XCTAssertFalse(SyncMutationNudge.shouldSchedule(provider: .github, mutationSource: "github"))
        XCTAssertFalse(SyncMutationNudge.shouldSchedule(provider: .google, mutationSource: "google"))
    }

    func testMutationNudge_userAndOtherProviderChangesStillSchedule() {
        XCTAssertTrue(SyncMutationNudge.shouldSchedule(provider: .github, mutationSource: nil))
        XCTAssertTrue(SyncMutationNudge.shouldSchedule(provider: .github, mutationSource: "google"))
        XCTAssertTrue(SyncMutationNudge.shouldSchedule(provider: .google, mutationSource: "github"))
    }

    // MARK: - Full pull throttle

    func testFullPullThrottle_firstAndExpiredPullsRun() {
        XCTAssertTrue(FullPullThrottle.isDue(lastSuccess: nil, now: t1, interval: 300))
        XCTAssertTrue(FullPullThrottle.isDue(lastSuccess: t0, now: t0.addingTimeInterval(300), interval: 300))
    }

    func testFullPullThrottle_recentSuccessfulPullIsSkipped() {
        XCTAssertFalse(FullPullThrottle.isDue(lastSuccess: t0, now: t0.addingTimeInterval(299), interval: 300))
    }

    // MARK: - Backfill twin index

    func testBackfillIndex_returnsOnlyUnambiguousCandidateAndConsumesIt() {
        var index = BackfillAdoptionIndex(candidates: [
            .init(taskId: "a", title: "One"), .init(taskId: "b", title: "Two")
        ])
        XCTAssertEqual(index.takeUniqueTaskId(title: "One"), "a")
        XCTAssertNil(index.takeUniqueTaskId(title: "One"), "consumed candidates cannot be reused")
    }

    func testBackfillIndex_ambiguousTitleDoesNotAdopt() {
        var index = BackfillAdoptionIndex(candidates: [
            .init(taskId: "a", title: "Same"), .init(taskId: "b", title: "Same")
        ])
        XCTAssertNil(index.takeUniqueTaskId(title: "Same"))
    }

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

    // MARK: - Conflict rule (last-write-wins on pull-apply)

    func testConflict_newerRemoteWins() {
        XCTAssertTrue(SyncSuppression.remoteWins(remoteUpdatedAt: t1, localUpdatedAt: t0))
    }

    func testConflict_newerLocalWins_staleRemoteMustNotClobber() {
        // The Google completion-revert bug: a pull carrying pre-completion
        // remote state raced a completion made locally seconds earlier.
        XCTAssertFalse(SyncSuppression.remoteWins(remoteUpdatedAt: t0, localUpdatedAt: t1))
    }

    func testConflict_tieKeepsLocal() {
        XCTAssertFalse(SyncSuppression.remoteWins(remoteUpdatedAt: t0, localUpdatedAt: t0))
    }

    func testConflict_unprovableRemoteNeverClobbers() {
        XCTAssertFalse(SyncSuppression.remoteWins(remoteUpdatedAt: nil, localUpdatedAt: t0))
    }

    func testConflict_noLocalStampAppliesRemote() {
        XCTAssertTrue(SyncSuppression.remoteWins(remoteUpdatedAt: t0, localUpdatedAt: nil))
    }

    // MARK: - Pull watermark policy

    func testPullWatermark_isTheTasksOwnStamp_notWallClock() {
        // A now() watermark swallows edits made during the sync pass; the
        // watermark must be the task's own updatedAt so a later edit always
        // exceeds it.
        XCTAssertEqual(SyncSuppression.pullWatermark(taskUpdatedAt: t0), t0)
        XCTAssertNil(SyncSuppression.pullWatermark(taskUpdatedAt: nil))
        let editAfterPass = t0.addingTimeInterval(0.5)
        XCTAssertTrue(SyncSuppression.shouldPushLocal(
            localUpdatedAt: editAfterPass,
            watermark: SyncSuppression.pullWatermark(taskUpdatedAt: t0)))
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

    func testDue_allDayPushKeepsItsUTCDay_regardlessOfLocalZone() {
        // All-day dues are stored AT UTC midnight — the wire string must be
        // that same instant even when the device sits west of UTC (where the
        // local day is the previous date).
        let s = GoogleDueMapping.pushDueString(
            for: utcMidnight, isAllDay: true, localTimeZone: TimeZone(secondsFromGMT: -7 * 3600)!)
        XCTAssertEqual(GoogleDueMapping.formatter.date(from: s), utcMidnight)
    }

    func testDue_timedPushUsesTheLocalDay() {
        // 03:00Z on day N = 20:00 the PREVIOUS day at UTC-7 — the user sees
        // the earlier date, so that's the date-only value Google must get.
        let threeAMUTC = utcMidnight.addingTimeInterval(3 * 3600)
        let s = GoogleDueMapping.pushDueString(
            for: threeAMUTC, isAllDay: false, localTimeZone: TimeZone(secondsFromGMT: -7 * 3600)!)
        XCTAssertEqual(
            GoogleDueMapping.formatter.date(from: s),
            utcMidnight.addingTimeInterval(-86_400))
        // And in a UTC household the same instant keeps day N.
        let sUTC = GoogleDueMapping.pushDueString(
            for: threeAMUTC, isAllDay: false, localTimeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(GoogleDueMapping.formatter.date(from: sUTC), utcMidnight)
    }

    // MARK: - Completed backfill (history trickles in, never delays live sync)

    private func cand(_ id: String, completed: Bool = true, deleted: Bool = false, at: String) -> CompletedBackfill.Candidate {
        .init(remoteId: id, completed: completed, deleted: deleted, updatedAt: at)
    }

    func testBackfill_selectsOnlyCompletedExisting_newestFirst() {
        let batch = CompletedBackfill.select(
            [cand("a", at: "2026-01-03"), cand("b", at: "2026-01-01"), cand("c", at: "2026-01-02"),
             cand("open", completed: false, at: "2026-01-04"), cand("gone", deleted: true, at: "2026-01-05")],
            linkedRemoteIds: [], tombstoned: [], budget: 10)
        XCTAssertEqual(batch.map(\.remoteId), ["a", "c", "b"])
    }

    func testBackfill_skipsLinkedAndTombstoned() {
        let batch = CompletedBackfill.select(
            [cand("a", at: "3"), cand("b", at: "1"), cand("c", at: "2")],
            linkedRemoteIds: ["a"], tombstoned: ["c"], budget: 10)
        XCTAssertEqual(batch.map(\.remoteId), ["b"])
    }

    func testBackfill_budgetKeepsNewest() {
        let batch = CompletedBackfill.select(
            [cand("a", at: "3"), cand("b", at: "1"), cand("c", at: "2")],
            linkedRemoteIds: [], tombstoned: [], budget: 2)
        XCTAssertEqual(batch.map(\.remoteId), ["a", "c"])
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
        // must be a no-op in ANY timezone (the loop-avoidance property).
        for offset in [-7, 0, 9] {
            let s = GoogleDueMapping.pushDueString(
                for: utcMidnight, isAllDay: true,
                localTimeZone: TimeZone(secondsFromGMT: offset * 3600)!)
            let parsedBack = GoogleDueMapping.formatter.date(from: s)
            XCTAssertNil(
                GoogleDueMapping.adoptedDue(remoteDue: parsedBack, localDue: utcMidnight, localIsAllDay: true),
                "round-trip drifted at UTC\(offset >= 0 ? "+" : "")\(offset)"
            )
        }
    }
}
