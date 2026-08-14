//  GoogleTasksPullDecisionTests.swift
//  First tests for the Google Tasks sync engine (Task ba1... see ba4c9c84).
//
//  `GoogleTasksSyncService` is 1,209 lines with no tests at all — the existing "Google Tasks" tests
//  cover feature flags and the connect callback, not the engine. This is the code that decides what
//  to create, update and delete in someone's real Google account, so the failure mode is other
//  people's data.
//
//  Starting where the task said to start: the DECISIONS, not the plumbing. Three of them lived
//  inline in a 450-line `sync(link:)` and answer the questions that actually matter —
//  "what does a remote deletion mean", "what counts as the same task on both sides", and
//  "when must we refuse to re-import something".
//
//  The nastiest of these is resurrection. Delete a task in Astrid, and the next pull still carries
//  it from Google; re-importing it would undo the user's deletion, and it would come back every
//  pass forever. That is why a tombstone exists, and why "tombstoned AND we no longer hold a link"
//  is a refusal rather than an ordinary apply.

import XCTest
@testable import Astrid_App

final class GoogleTasksPullDecisionTests: XCTestCase {

    // MARK: - A remote deletion

    func testGoogleDeletionRemovesTheLinkedLocalTwin() {
        XCTAssertEqual(
            GoogleTasksPull.outcome(isRemoteDeleted: true, hasLink: true,
                                    hasLocalTask: true, isTombstoned: false),
            .deleteLocalTwin)
    }

    /// A deletion for something we never mirrored is not an error and not an action.
    func testADeletionWeHaveNoTwinForIsIgnored() {
        XCTAssertEqual(
            GoogleTasksPull.outcome(isRemoteDeleted: true, hasLink: false,
                                    hasLocalTask: false, isTombstoned: false),
            .ignoreDeletion)
    }

    /// A link whose local task is already gone — deleted in Astrid a moment ago — has nothing left
    /// to delete. Deleting again would be a second delete of an id that no longer resolves.
    func testADeletionWhoseLocalTaskIsAlreadyGoneIsIgnored() {
        XCTAssertEqual(
            GoogleTasksPull.outcome(isRemoteDeleted: true, hasLink: true,
                                    hasLocalTask: false, isTombstoned: false),
            .ignoreDeletion)
    }

    // MARK: - Resurrection

    /// The one that would silently undo a user's deletion, every pass, forever.
    func testATombstonedItemWeNoLongerLinkIsNotReimported() {
        XCTAssertEqual(
            GoogleTasksPull.outcome(isRemoteDeleted: false, hasLink: false,
                                    hasLocalTask: false, isTombstoned: true),
            .skipResurrection)
    }

    /// …but a tombstone must NOT freeze a task that still exists and is still linked. The tombstone
    /// says "do not bring this back", not "never touch this again" — otherwise deleting a task once
    /// and recreating it would leave the new one permanently unsyncable.
    func testATombstoneDoesNotBlockAnItemWeStillLink() {
        XCTAssertEqual(
            GoogleTasksPull.outcome(isRemoteDeleted: false, hasLink: true,
                                    hasLocalTask: true, isTombstoned: true),
            .apply)
    }

    /// A remote deletion beats a tombstone: both agree the thing is gone.
    func testADeletionOfATombstonedItemIsStillADeletion() {
        XCTAssertEqual(
            GoogleTasksPull.outcome(isRemoteDeleted: true, hasLink: true,
                                    hasLocalTask: true, isTombstoned: true),
            .deleteLocalTwin)
    }

    // MARK: - The ordinary case

    func testAnUnremarkableItemIsApplied() {
        XCTAssertEqual(
            GoogleTasksPull.outcome(isRemoteDeleted: false, hasLink: true,
                                    hasLocalTask: true, isTombstoned: false),
            .apply)
        XCTAssertEqual(
            GoogleTasksPull.outcome(isRemoteDeleted: false, hasLink: false,
                                    hasLocalTask: false, isTombstoned: false),
            .apply, "a brand-new remote task is an ordinary create")
    }

    // MARK: - What counts as the same parent

    /// Parent ids are scoped to their container: Google reuses short ids across task lists, so an
    /// unscoped key would let a subtask in one list adopt a parent in another.
    func testAParentKeyIsScopedToItsContainer() {
        XCTAssertEqual(GoogleTasksPull.parentKey(containerId: "list-A", rawParent: "p1"), "list-A:p1")
        XCTAssertNotEqual(GoogleTasksPull.parentKey(containerId: "list-A", rawParent: "p1"),
                          GoogleTasksPull.parentKey(containerId: "list-B", rawParent: "p1"))
    }

    /// Google sends an empty string for "no parent", not a missing field. Treating "" as an id
    /// would make every top-level task a child of a parent that does not exist.
    func testAnEmptyParentMeansNoParent() {
        XCTAssertNil(GoogleTasksPull.parentKey(containerId: "list-A", rawParent: ""))
        XCTAssertNil(GoogleTasksPull.parentKey(containerId: "list-A", rawParent: nil))
    }

    // MARK: - The engine must ask, not re-derive

    func testTheEngineUsesTheseDecisions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let engine = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/Sync/GoogleTasksSyncService.swift"),
            encoding: .utf8)
        XCTAssertTrue(engine.contains("GoogleTasksPull.outcome("),
                      "the pull loop must ask the shared decision")
        XCTAssertTrue(engine.contains("GoogleTasksPull.parentKey("),
                      "…and the shared parent-key rule")
        // Reading the wire field is the engine's job and stays. What must NOT come back is the
        // engine deciding for itself what the field means — the resurrection guard in particular,
        // which is the one whose absence silently undoes a user's deletion.
        XCTAssertFalse(engine.contains("tombstonedRemoteIds.contains(item.remoteId), byRemoteId["),
                       "the hand-rolled resurrection guard must be gone, not merely duplicated")
    }
}
