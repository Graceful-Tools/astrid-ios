//  MacCommentAttachmentDisplayTests.swift
//  Regression guard for Task AITD-304 — "[mac] fix add attachment to comments. looks like it is
//  broken (not attaching)."
//
//  It was not broken. The comments posted from the Mac carry their secureFiles server-side: the
//  paperclip stages, CommentAttachmentBatch splits, and the Outbox upload→comment chain lands the
//  bytes. What was missing was any way to SEE it — `commentBubble` rendered `Text(c.content)` and
//  nothing else, so a file posted without a caption came back as an empty pill. From the outside
//  "never uploaded" and "uploaded, never drawn" are the same picture, which is what made this
//  read as a broken upload.
//
//  Two things are guarded, and the second is the one that would quietly rot: the bubble draws the
//  comment's files, and an attachment-only comment does not fall back to an empty text bubble.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacCommentAttachmentDisplayTests: XCTestCase {

    private func file(_ id: String, name: String, mime: String, size: Int = 1024) -> SecureFile {
        SecureFile(id: id, name: name, size: size, mimeType: mime)
    }

    private func comment(text: String, files: [SecureFile]) -> Comment {
        Comment(id: "c1", content: text, type: .TEXT, authorId: "u1", author: nil, taskId: "t1",
                secureFiles: files)
    }

    private func detailSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/Views/MacTaskDetailView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The body of `commentBubble(_:)` — the function that draws one comment.
    private func commentBubbleBody() throws -> String {
        let source = try detailSource()
        guard let start = source.range(of: "private func commentBubble(") else {
            XCTFail("commentBubble() not found — did it move?")
            return ""
        }
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    /// ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - The bug

    /// The whole report in one assertion: a comment's files have to be drawn in the comment.
    func testCommentBubbleDrawsTheCommentsFiles() throws {
        let body = try commentBubbleBody()
        XCTAssertTrue(body.contains("MacCommentAttachmentsView"),
                      "A comment's attachments must render in its bubble — drawing only c.content is what made a successful attach look like a failed one")
    }

    /// Attachments arrive THROUGH comments, so the comment is the only place they hang off. The
    /// task-level Attachments section lists task.attachments / task.secureFiles and would never
    /// show a file posted on a comment.
    func testAttachmentsComeFromTheCommentItself() {
        let png = file("f1", name: "shot.png", mime: "image/png")
        XCTAssertEqual(MacCommentBubble.attachments(of: comment(text: "", files: [png])), [png])
        XCTAssertTrue(MacCommentBubble.attachments(of: comment(text: "hi", files: [])).isEmpty)
    }

    /// A caption-less attachment comment must not draw an empty text bubble. That empty pill IS
    /// what a posted screenshot looked like before this fix.
    func testAttachmentOnlyCommentDrawsNoEmptyTextBubble() {
        XCTAssertFalse(MacCommentBubble.showsText(""),
                       "An attachment-only comment has no caption — an empty pill reads as a failed post")
        XCTAssertFalse(MacCommentBubble.showsText("   \n "), "Whitespace is not a caption")
        XCTAssertTrue(MacCommentBubble.showsText("send"))
    }

    /// …and the bubble actually asks. A helper nothing calls guards nothing.
    func testTheBubbleAsksBeforeDrawingText() throws {
        let body = try commentBubbleBody()
        XCTAssertTrue(body.contains("MacCommentBubble.showsText"),
                      "commentBubble must gate its Text on the shared rule, not draw it unconditionally")
    }

    /// A comment with neither text nor a file is the only genuinely empty one.
    func testEmptyMeansNeitherTextNorFile() {
        XCTAssertTrue(MacCommentBubble.isEmpty(comment(text: " ", files: [])))
        XCTAssertFalse(MacCommentBubble.isEmpty(comment(text: "", files: [file("f1", name: "a.png", mime: "image/png")])),
                       "A photo with no caption is not an empty comment")
        XCTAssertFalse(MacCommentBubble.isEmpty(comment(text: "hi", files: [])))
    }

    // MARK: - What gets drawn

    /// Screenshots are the case this was reported from, so images render as images. Everything
    /// else is a chip that opens in Quick Look — NSImage returns nil for a .mov's bytes, so
    /// guessing wider would only trade a readable chip for a grey box.
    func testImagesRenderInlineAndEverythingElseIsAChip() {
        XCTAssertTrue(MacCommentBubble.rendersInline(mimeType: "image/png"))
        XCTAssertTrue(MacCommentBubble.rendersInline(mimeType: "IMAGE/JPEG"), "Mime types are not case-sensitive")
        XCTAssertFalse(MacCommentBubble.rendersInline(mimeType: "application/pdf"))
        XCTAssertFalse(MacCommentBubble.rendersInline(mimeType: "video/quicktime"))
    }

    // MARK: - Reuse

    /// The bytes come from the SHARED ladder (staged local copy → download cache → server), not
    /// a Mac transcription of iOS's. Two copies of that ladder is how the platforms drift.
    func testThumbnailBytesUseTheSharedLadder() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac/Views/MacCommentAttachments.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("AttachmentService.shared.fileData(for:"),
                      "Thumbnail loading must go through the shared byte ladder")
        XCTAssertFalse(source.contains("secure-files"),
                       "No Mac-local copy of the secure-file download dance")
    }

    /// Opening one goes through the shared preparer, which already handles a file that is still
    /// uploading (its bytes are the local staging copy).
    func testOpeningUsesTheSharedPreviewPreparer() throws {
        let source = try detailSource()
        XCTAssertTrue(source.contains("prepareFilesForPreview"),
                      "Quick Look must reuse AttachmentService's preparer")
    }
}
#endif
