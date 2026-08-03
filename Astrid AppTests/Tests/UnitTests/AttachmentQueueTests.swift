//  AttachmentQueueTests.swift
//  Regression tests for Task a72e09ca (follow-up) — "attachments replace previous ones
//  rather than adding".
//
//  The first pass converted two comment inputs to a list of attachments but left
//  `RichTextInput` holding a single optional file — and RichTextInput is what the task
//  detail actually renders, so in the surface that matters every pick overwrote the last.
//
//  The add-vs-replace decision now lives here, in one place all three inputs call, so it
//  cannot be right in one input and wrong in another again.

import XCTest
@testable import Astrid_App

final class AttachmentQueueTests: XCTestCase {

    private func file(_ id: String, name: String = "photo.jpg", size: Int = 100) -> AttachedFileInfo {
        AttachedFileInfo(fileId: id, fileName: name, fileSize: size, mimeType: "image/jpeg", imageData: nil)
    }

    /// THE BUG: picking a second attachment must not throw away the first.
    func testASecondAttachmentAddsRatherThanReplaces() {
        var queue = AttachmentQueue.adding(file("f1"), to: [])
        queue = AttachmentQueue.adding(file("f2"), to: queue)

        XCTAssertEqual(queue.map(\.fileId), ["f1", "f2"],
                       "the second pick replaced the first instead of queueing behind it")
    }

    /// Order is pick order — the comments are sent in this order, so it is user-visible.
    func testAttachmentsKeepPickOrder() {
        var queue: [AttachedFileInfo] = []
        for id in ["a", "b", "c", "d"] {
            queue = AttachmentQueue.adding(file(id), to: queue)
        }

        XCTAssertEqual(queue.map(\.fileId), ["a", "b", "c", "d"])
    }

    /// The same file arriving twice (a re-fired onChange, a double tap) must not double-post.
    func testTheSameFileIsNotQueuedTwice() {
        var queue = AttachmentQueue.adding(file("f1"), to: [])
        queue = AttachmentQueue.adding(file("f1"), to: queue)

        XCTAssertEqual(queue.count, 1)
    }

    /// Removing takes out exactly the one asked for.
    func testRemovingTakesOutOnlyThatFile() {
        let queue = [file("f1"), file("f2"), file("f3")]
        let after = AttachmentQueue.removing(fileId: "f2", from: queue)

        XCTAssertEqual(after.map(\.fileId), ["f1", "f3"])
    }

    /// Removing something that isn't queued is a no-op, not a crash or a clear.
    func testRemovingAnUnknownFileChangesNothing() {
        let queue = [file("f1"), file("f2")]
        XCTAssertEqual(AttachmentQueue.removing(fileId: "nope", from: queue).map(\.fileId),
                       ["f1", "f2"])
    }

    /// The ceiling holds, and holds by DROPPING THE NEW ONE rather than evicting a file the
    /// user already queued — silently losing an earlier pick is the bug this suite exists for.
    func testTheQueueIsCappedWithoutEvictingEarlierPicks() {
        var queue: [AttachedFileInfo] = []
        for index in 0..<(AttachmentQueue.maxAttachments + 3) {
            queue = AttachmentQueue.adding(file("f\(index)"), to: queue)
        }

        XCTAssertEqual(queue.count, AttachmentQueue.maxAttachments)
        XCTAssertEqual(queue.first?.fileId, "f0", "the earliest pick must survive")
        XCTAssertTrue(AttachmentQueue.isFull(queue))
    }
}
