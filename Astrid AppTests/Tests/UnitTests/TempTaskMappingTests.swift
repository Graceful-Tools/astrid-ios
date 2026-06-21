import XCTest
@testable import Astrid_App

/// Locks the temp→real task-id mapping contract that the offline photo/comment
/// attach depends on.
///
/// When a task created offline syncs, TaskService must record
/// `temp_<uuid> → realServerId` so CommentService can re-target a pending
/// photo-comment from the temp task to the real one. The online create path
/// always recorded this; the offline sync path didn't — which is why a photo
/// attached to an offline-created task never posted (the comment 404'd against
/// the temp id and was dropped).
@MainActor
final class TempTaskMappingTests: XCTestCase {

    func testRecordsAndResolvesTempToRealMapping() {
        let temp = "temp_\(UUID().uuidString)"
        XCTAssertNil(TaskService.shared.mappedRealTaskId(for: temp),
                     "unknown temp id should not resolve")

        TaskService.shared.recordTempTaskMapping(tempId: temp, realId: "real-server-id")

        XCTAssertEqual(TaskService.shared.mappedRealTaskId(for: temp), "real-server-id",
                       "after sync records the mapping, the real id must be resolvable")
    }
}
