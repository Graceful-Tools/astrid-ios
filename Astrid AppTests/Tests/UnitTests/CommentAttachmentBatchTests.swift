//  CommentAttachmentBatchTests.swift
//  Regression tests for Task a72e09ca — "Update attachment picker": three options
//  (From Documents / From Photos / From Camera) and multiple attachments, not singular.
//
//  The picker UI is the visible half. The half that can lose a user's data is this one:
//  `POST /api/v1/tasks/[id]/comments` accepts ONE fileId, so picking four photos has to fan
//  out into four comments. Getting that wrong drops attachments silently — the worst kind of
//  bug, because the user watched the thumbnails appear and has no reason to check.
//
//  So the fan-out is a pure function and it is pinned here before any UI moves.

import XCTest
@testable import Astrid_App

final class CommentAttachmentBatchTests: XCTestCase {

    // MARK: - The core fan-out

    /// THE BUG THIS TASK FIXES: multiple picks used to collapse to one attachment.
    /// Four files must produce four comments — not one, and not three.
    func testEveryPickedFileGetsItsOwnComment() {
        let drafts = CommentAttachmentBatch.drafts(
            text: "", fileIds: ["f1", "f2", "f3", "f4"], useMarkdown: false)

        XCTAssertEqual(drafts.count, 4, "four picks must not collapse into fewer comments")
        XCTAssertEqual(drafts.map(\.fileId), ["f1", "f2", "f3", "f4"],
                       "every file must be sent, in the order it was picked")
    }

    /// Typed text plus attachments: the text rides the first comment, the rest are
    /// attachment-only. The alternative — repeating the caption on all four — spams the thread.
    func testTextRidesTheFirstAttachmentAndIsNotRepeated() {
        let drafts = CommentAttachmentBatch.drafts(
            text: "here are the receipts", fileIds: ["f1", "f2", "f3"], useMarkdown: false)

        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts[0].content, "here are the receipts")
        XCTAssertEqual(drafts[0].fileId, "f1")
        XCTAssertEqual(drafts[1].content, "", "the caption must not repeat")
        XCTAssertEqual(drafts[2].content, "")
    }

    /// Any comment carrying a file is an ATTACHMENT comment — that is what drives rendering.
    func testFileCommentsAreTypedAsAttachments() {
        let drafts = CommentAttachmentBatch.drafts(
            text: "look", fileIds: ["f1", "f2"], useMarkdown: true)

        XCTAssertTrue(drafts.allSatisfy { $0.type == .ATTACHMENT },
                      "markdown must not override the attachment type when a file is present")
    }

    // MARK: - The no-attachment paths still work

    func testPlainTextIsASingleTextComment() {
        let drafts = CommentAttachmentBatch.drafts(text: "just talking", fileIds: [], useMarkdown: false)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertNil(drafts[0].fileId)
        XCTAssertEqual(drafts[0].type, .TEXT)
    }

    func testMarkdownIsPreservedWhenThereIsNoAttachment() {
        let drafts = CommentAttachmentBatch.drafts(text: "**bold**", fileIds: [], useMarkdown: true)

        XCTAssertEqual(drafts.first?.type, .MARKDOWN)
    }

    /// Whitespace-only text with no file must send nothing at all — not an empty comment.
    func testNothingToSendProducesNoDrafts() {
        XCTAssertTrue(CommentAttachmentBatch.drafts(text: "   \n ", fileIds: [], useMarkdown: false).isEmpty)
        XCTAssertTrue(CommentAttachmentBatch.drafts(text: "", fileIds: [], useMarkdown: false).isEmpty)
    }

    /// A file with no caption is a perfectly good comment — this is the common case
    /// (snap a photo, send it) and it must not be treated as "nothing to send".
    func testAFileWithNoTextStillSends() {
        let drafts = CommentAttachmentBatch.drafts(text: "  ", fileIds: ["f1"], useMarkdown: false)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].fileId, "f1")
        XCTAssertEqual(drafts[0].content, "", "whitespace-only text must be trimmed away, not sent")
    }

    /// Text is trimmed exactly once, and the trimmed form is what ships.
    func testTextIsTrimmed() {
        let drafts = CommentAttachmentBatch.drafts(text: "  hello  ", fileIds: [], useMarkdown: false)

        XCTAssertEqual(drafts[0].content, "hello")
    }
}
