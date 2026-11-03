//  CopyTaskAttachmentsTests.swift
//  AITD-586 — "Copy task with comments should copy attachments".
//
//  `TaskService.copyTask(includeComments: true)` re-posted each comment's text and nothing else,
//  so a comment that carried a photo arrived on the copy as an empty line, or not at all.
//  Which comments carry which files onto the copy is decided here, as a pure function, so a
//  dropped attachment is a failing test rather than something a user notices later.

import XCTest
@testable import Astrid_App

final class CopyTaskAttachmentsTests: XCTestCase {

    private func file(_ id: String) -> SecureFile {
        SecureFile(id: id, name: "\(id).jpg", size: 10, mimeType: "image/jpeg")
    }

    private func comment(_ id: String, _ content: String, author: String? = "user-a",
                         type: Comment.CommentType = .TEXT, files: [SecureFile]? = nil) -> Comment {
        Comment(id: id, content: content, type: type, authorId: author, author: nil, taskId: "t1",
                createdAt: nil, updatedAt: nil, attachmentUrl: nil, attachmentName: nil,
                attachmentType: nil, attachmentSize: nil, parentCommentId: nil, replies: nil,
                secureFiles: files, clientRequestId: nil)
    }

    /// THE BUG: an attachment comment must bring its file across.
    func testAnAttachmentCommentCarriesItsFile_AITD586() {
        let drafts = CommentAttachmentBatch.copyDrafts(of: [
            comment("c1", "", type: .ATTACHMENT, files: [file("f1")]),
        ])

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].file?.id, "f1", "the copied comment must carry the original's file")
        XCTAssertEqual(drafts[0].authorId, "user-a")
    }

    /// One comment with several files fans out the same way the composer does: one file per
    /// comment, the text on the first.
    func testSeveralFilesOnOneCommentAllCopy_AITD586() {
        let drafts = CommentAttachmentBatch.copyDrafts(of: [
            comment("c1", "receipts", type: .ATTACHMENT, files: [file("f1"), file("f2")]),
        ])

        XCTAssertEqual(drafts.map(\.file?.id), ["f1", "f2"])
        XCTAssertEqual(drafts.map(\.content), ["receipts", ""])
        XCTAssertEqual(drafts.map(\.type), [.ATTACHMENT, .ATTACHMENT])
    }

    /// Text comments copy unchanged and in order; system comments stay with the original.
    func testTextCommentsCopyAndSystemCommentsDoNot_AITD586() {
        let drafts = CommentAttachmentBatch.copyDrafts(of: [
            comment("s1", "Jon created this task", author: nil),
            comment("c1", "**first**", type: .MARKDOWN),
            comment("c2", "photo", type: .ATTACHMENT, files: [file("f1")]),
            comment("c3", "last"),
        ])

        XCTAssertEqual(drafts.map(\.content), ["**first**", "photo", "last"])
        XCTAssertEqual(drafts.map(\.type), [.MARKDOWN, .ATTACHMENT, .TEXT])
        XCTAssertEqual(drafts.map(\.file?.id), [nil, "f1", nil])
    }

    /// When a file's bytes cannot be fetched, the text still copies — as a plain comment, since
    /// an ATTACHMENT with no file is not one — and a file-only comment is dropped, not sent empty.
    func testAFileThatCannotBeFetchedKeepsItsText_AITD586() {
        let drafts = CommentAttachmentBatch.copyDrafts(of: [
            comment("c1", "photo", type: .ATTACHMENT, files: [file("f1"), file("f2")]),
        ])

        XCTAssertEqual(drafts[0].withoutFile?.content, "photo")
        XCTAssertEqual(drafts[0].withoutFile?.type, .TEXT)
        XCTAssertNil(drafts[0].withoutFile?.file)
        XCTAssertNil(drafts[1].withoutFile, "an empty comment with no file has nothing to send")
    }
}
