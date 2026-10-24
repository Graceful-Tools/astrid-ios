//  TaskSyncStateTests.swift
//  The pending-sync mark (AITD-491). A task made on a GitHub Projects board can exist in Astrid
//  before GitHub has all of it; the server marks it `pending` until its write-back job finishes.
//  The key reached the wire on 2026-10-10 and both the core's model and the Swift one dropped it.

import XCTest
@testable import Astrid_App

@MainActor
final class TaskSyncStateTests: XCTestCase {

    private func decode(_ extra: String) throws -> Task {
        let wire = #"{"id":"t1","title":"x","description":"","priority":0,"isAllDay":true,"isPrivate":false,"completed":false\#(extra)}"#
        return try JSONDecoder().decode(Task.self, from: Data(wire.utf8))
    }

    // MARK: - The model

    func testATaskKeepsItsSyncStateThroughDecodeAndEncode_AITD491() throws {
        let task = try decode(#","syncState":"pending""#)
        XCTAssertEqual(task.syncState, "pending")
        let again = try JSONDecoder().decode(Task.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(again.syncState, "pending")
    }

    // MARK: - The rule

    func testPendingAndErrorAreMarked_AITD491() throws {
        XCTAssertEqual(TaskSyncState.mark(for: try decode(#","syncState":"pending""#)), .pending)
        XCTAssertEqual(TaskSyncState.mark(for: try decode(#","syncState":"error""#)), .failed)
    }

    /// Null is what the server sends for every settled task and every classic list, so it must
    /// draw nothing — as must `synced` and a value this build has never heard of.
    func testNullAbsentSyncedAndUnknownAreSettled_AITD491() throws {
        XCTAssertNil(TaskSyncState.mark(for: try decode(#","syncState":null"#)))
        XCTAssertNil(TaskSyncState.mark(for: try decode("")))
        XCTAssertNil(TaskSyncState.mark(for: Task(id: "t", title: "t", syncState: "synced")))
        XCTAssertNil(TaskSyncState.mark(for: Task(id: "t", title: "t", syncState: "queued")))
    }

    /// A completed task can still be waiting on its write-back; the mark does not depend on it.
    func testACompletedTaskStillCarriesItsMark_AITD491() {
        XCTAssertEqual(TaskSyncState.mark(for: Task(id: "t", title: "t", completed: true, syncState: "pending")), .pending)
    }
}
