import XCTest
@testable import Astrid_App

/// Regression tests for attaching a photo (a comment with an attachment) to a
/// task that was **created offline**.
///
/// An offline-created task has a temporary id (`temp_<uuid>`). The pending
/// comment carries that temp id as its `taskId`. On reconnect the task syncs
/// first (so TaskService knows temp→real), but `syncPendingCreate` was calling
/// `createComment(taskId: temp_…)` directly — the server 404s, and a 404 is
/// treated as a *permanent* failure, so the photo-comment was dropped forever.
///
/// `PendingCommentResolver` resolves the temp task id to the real one before the
/// API call, and signals "not synced yet" (retry) instead of letting it 404.
final class CommentTaskIdResolutionTests: XCTestCase {

    func testRealTaskIdPassesThroughUnchanged() {
        let result = PendingCommentResolver.resolveTaskId("real-task-1") { _ in
            XCTFail("provider must not be consulted for a non-temp id"); return nil
        }
        XCTAssertEqual(result, .ready("real-task-1"))
    }

    func testTempTaskIdResolvesToRealWhenMapped() {
        let result = PendingCommentResolver.resolveTaskId("temp_abc") { tempId in
            tempId == "temp_abc" ? "server-real-id" : nil
        }
        XCTAssertEqual(result, .ready("server-real-id"))
    }

    func testTempTaskIdNotYetMappedMeansWait() {
        let result = PendingCommentResolver.resolveTaskId("temp_abc") { _ in nil }
        XCTAssertEqual(result, .taskNotSyncedYet,
                       "must wait & retry, not 404 → permanent fail")
    }

    func testTempMappedToAnotherTempStillWaits() {
        let result = PendingCommentResolver.resolveTaskId("temp_abc") { _ in "temp_def" }
        XCTAssertEqual(result, .taskNotSyncedYet)
    }
}
