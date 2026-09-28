//  CoreTaskServiceTests.swift
//  TaskService over astrid-core (docs/CORE_MIGRATION.md), driven the way the views drive it. The
//  unit-test host runs the core in memory with no network, so every write lands in its cache and
//  journal and nothing leaves the machine.

import XCTest
@testable import Astrid_App

@MainActor
final class CoreTaskServiceTests: XCTestCase {
    /// The views pass the task as they show it (rule 3). The core has to read that task — every
    /// field the Swift model encodes — or the completion fails and the row never changes.
    func testCompletingWithTheTaskOnScreenCompletesIt() async throws {
        let service = TaskService.shared
        let made = try await service.createTask(listIds: [], title: "Complete me \(UUID().uuidString)")
        let onScreen = try XCTUnwrap(service.tasksById[made.id])

        let done = try await service.completeTask(id: made.id, completed: true, task: onScreen)
        XCTAssertTrue(done.completed)
        XCTAssertEqual(service.tasksById[made.id]?.completed, true,
                       "the row the list draws must be the completed one")
    }

    /// A comment posted from a view is the row that view drew (AITD-331), and an edit and a delete
    /// reach the thread at once — all through the core's cache and journal.
    func testACommentIsPostedEditedAndDeletedThroughTheCore() async throws {
        let task = try await TaskService.shared.createTask(listIds: [], title: "Discuss \(UUID().uuidString)")
        let comments = CommentService.shared
        let rowId = "temp_\(UUID().uuidString)"

        let posted = try await comments.createComment(taskId: task.id, content: "first", clientRequestId: rowId)
        XCTAssertEqual(posted.id, rowId, "the comment is the row the view already drew")
        XCTAssertEqual(comments.cachedComments[task.id]?.map(\.content), ["first"])

        _ = try await comments.updateComment(id: rowId, content: "edited")
        XCTAssertEqual(comments.cachedComments[task.id]?.first?.content, "edited")

        try await comments.deleteComment(id: rowId)
        XCTAssertEqual(comments.cachedComments[task.id]?.count, 0)
        let reread = try await comments.fetchComments(taskId: task.id)
        XCTAssertTrue(reread.isEmpty, "the core's cache agrees")
    }

    /// A photo staged by AttachmentService goes to the core with the id its thumbnail is drawn
    /// under, so the new comment shows the picture it was made with (AITD-308).
    func testAStagedPhotoKeepsItsThumbnailIdOnTheComment() async throws {
        let task = try await TaskService.shared.createTask(listIds: [], title: "Photo \(UUID().uuidString)")
        let tempFileId = AttachmentService.shared.saveLocallyAndUploadAsync(
            fileData: Data("not really a jpeg".utf8), fileName: "IMG_0001.jpg", mimeType: "image/jpeg",
            taskId: task.id)

        let posted = try await CommentService.shared.createComment(
            taskId: task.id, content: "", type: .ATTACHMENT, fileId: tempFileId)
        XCTAssertEqual(posted.secureFiles?.first?.id, tempFileId)
        XCTAssertEqual(posted.secureFiles?.first?.name, "IMG_0001.jpg")
    }

    /// A local edit nudges the external mirrors (Google Tasks, GitHub) to push it. The nudge used
    /// to come from the Swift Outbox's enqueue, so when task writes moved into the core it went
    /// silent and an edit reached Google only on the next foreground. It carries the write's
    /// source, so a provider still ignores the echo of its own pass.
    func testATaskWriteNudgesTheExternalMirrorsWithItsSource() async throws {
        var sources: [String?] = []
        let observer = NotificationCenter.default.addObserver(
            forName: LocalMutation.didHappen, object: nil, queue: nil
        ) { note in sources.append(note.userInfo?[LocalMutation.sourceKey] as? String) }
        defer { NotificationCenter.default.removeObserver(observer) }

        let made = try await TaskService.shared.createTask(listIds: [], title: "Mirror me \(UUID().uuidString)")
        _ = try await TaskService.shared.updateTask(taskId: made.id, title: "Mirrored", source: .google)
        _ = try await TaskService.shared.completeTask(id: made.id, completed: true)
        try await TaskService.shared.deleteTask(id: made.id)

        XCTAssertEqual(sources, [nil, "google", nil, nil])
    }

    /// Deleting a task mirrored to Google Tasks queues the deletion of its Google twin. The call
    /// was dropped when task writes moved into the core (on the assumption that the core's own
    /// ledger covered it — but the Google pass the Apple apps run reads this one), so a deleted
    /// task's twin stayed in Google.
    func testDeletingAGoogleMirroredTaskQueuesItsTwinsDeletion() async throws {
        let task = try await TaskService.shared.createTask(listIds: [], title: "Mirrored \(UUID().uuidString)")
        let remoteId = "g-\(UUID().uuidString)"
        GoogleTasksSyncService.shared.noteTaskLink(taskId: task.id, remoteId: remoteId, containerId: "tl1")
        let ledger = SyncDeletionLedger(provider: "google")
        defer { ledger.clearPending(remoteId: remoteId) }

        try await TaskService.shared.deleteTask(id: task.id)
        XCTAssertEqual(ledger.pending[remoteId], "tl1")
    }
}
