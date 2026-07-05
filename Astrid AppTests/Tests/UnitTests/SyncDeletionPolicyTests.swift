import XCTest
@testable import Astrid_App

/// Red-green spec for deletion sync. The two invariants under test:
/// tombstone-driven remote deletions (never absence-of-local), and
/// complete-listing-guarded local deletions (a failed or truncated remote
/// fetch must never mass-delete local tasks).
final class SyncDeletionPolicyTests: XCTestCase {
    private typealias Link = SyncDeletionPolicy.Link
    private let l1 = Link(taskId: "t1", remoteId: "r1")
    private let l2 = Link(taskId: "t2", remoteId: "r2")

    // MARK: - Local task deleted → remote twin deleted

    func testTombstonedTaskDeletesItsRemoteTwin() {
        XCTAssertEqual(
            SyncDeletionPolicy.remoteDeletions(links: [l1, l2], tombstonedTaskIds: ["t1"]),
            [l1])
    }

    func testNoTombstones_noRemoteDeletions() {
        XCTAssertTrue(SyncDeletionPolicy.remoteDeletions(links: [l1], tombstonedTaskIds: []).isEmpty)
    }

    // MARK: - Remote item deleted → local twin deleted

    func testAbsentRemoteDeletesLocalTwin() {
        XCTAssertEqual(
            SyncDeletionPolicy.localDeletions(
                links: [l1, l2], fullRemoteIds: ["r2"], truncated: false,
                explicitlyDeletedRemoteIds: []),
            [l1])
    }

    func testFailedFullFetch_neverDeletesLocally() {
        XCTAssertTrue(SyncDeletionPolicy.localDeletions(
            links: [l1], fullRemoteIds: nil, truncated: false,
            explicitlyDeletedRemoteIds: []).isEmpty)
    }

    func testTruncatedFetch_noAbsenceBasedDeletions() {
        // Page limit hit: absence may just mean "beyond the page".
        XCTAssertTrue(SyncDeletionPolicy.localDeletions(
            links: [l1], fullRemoteIds: [], truncated: true,
            explicitlyDeletedRemoteIds: []).isEmpty)
    }

    func testExplicitDeletedFlagWorksEvenWhenTruncated() {
        XCTAssertEqual(
            SyncDeletionPolicy.localDeletions(
                links: [l1], fullRemoteIds: [], truncated: true,
                explicitlyDeletedRemoteIds: ["r1"]),
            [l1])
    }

    func testPresentRemote_noDeletion() {
        XCTAssertTrue(SyncDeletionPolicy.localDeletions(
            links: [l1], fullRemoteIds: ["r1"], truncated: false,
            explicitlyDeletedRemoteIds: []).isEmpty)
    }

    // MARK: - Completion drift policy (flood repair + safe uncomplete)

    func testDrift_remoteCompletedAdoptsWhenLocalNeverCompleted() {
        XCTAssertTrue(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: true, localCompleted: false,
            localCompletedAt: nil, localUnchanged: false))
    }

    func testDrift_remoteCompletedAdoptsWhenLocalUntouched() {
        XCTAssertTrue(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: true, localCompleted: false,
            localCompletedAt: nil, localUnchanged: true))
    }

    func testDrift_userReopenedTask_remoteCompletedDoesNotOverride() {
        XCTAssertFalse(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: true, localCompleted: false,
            localCompletedAt: Date(timeIntervalSince1970: 1_700_000_000), localUnchanged: false))
    }

    func testDrift_remoteOpenNeverUncompletesEditedTask() {
        XCTAssertFalse(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: false, localCompleted: true,
            localCompletedAt: Date(timeIntervalSince1970: 1_700_000_000), localUnchanged: false))
    }

    func testDrift_remoteOpenUncompletesOnlyUntouchedTask() {
        XCTAssertTrue(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: false, localCompleted: true,
            localCompletedAt: Date(timeIntervalSince1970: 1_700_000_000), localUnchanged: true))
    }

    // MARK: - Repeating tasks (review P1: drift double-rollover)

    /// A repeating task that just rolled forward has completedAt == nil and is
    /// locally incomplete. Against a STALE "still completed" remote snapshot,
    /// the completedAt==nil escape would re-complete it → a second rollover
    /// (due date marches). For repeating tasks the escape must NOT apply.
    func testDrift_repeatingRolledForward_notReCompletedFromStaleSnapshot() {
        XCTAssertFalse(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: true, localCompleted: false,
            localCompletedAt: nil, localUnchanged: false, isRepeating: true))
    }

    /// But a genuinely untouched repeating task still adopts remote completion.
    func testDrift_repeatingUntouched_stillAdoptsRemoteCompletion() {
        XCTAssertTrue(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: true, localCompleted: false,
            localCompletedAt: nil, localUnchanged: true, isRepeating: true))
    }

    /// Non-repeating flood repair is unchanged: completedAt==nil still adopts.
    func testDrift_nonRepeatingFloodRepair_unchanged() {
        XCTAssertTrue(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: true, localCompleted: false,
            localCompletedAt: nil, localUnchanged: false, isRepeating: false))
    }

    func testDrift_agreementIsNoOp() {
        XCTAssertFalse(CompletionDriftPolicy.shouldAdoptRemote(
            remoteCompleted: true, localCompleted: true,
            localCompletedAt: nil, localUnchanged: true))
    }

    // MARK: - Apple field-edit pull rule

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testNewerReminderPullsFields() {
        XCTAssertTrue(AppleEditPull.shouldPullFields(
            reminderModified: t0.addingTimeInterval(60), lastSyncedReminderStamp: t0))
    }

    func testUnchangedReminderIsEchoSkipped() {
        XCTAssertFalse(AppleEditPull.shouldPullFields(
            reminderModified: t0, lastSyncedReminderStamp: t0))
    }

    func testNoStampYetPulls() {
        XCTAssertTrue(AppleEditPull.shouldPullFields(reminderModified: t0, lastSyncedReminderStamp: nil))
    }

    func testNoModificationDateSkips() {
        XCTAssertFalse(AppleEditPull.shouldPullFields(reminderModified: nil, lastSyncedReminderStamp: t0))
    }
}
