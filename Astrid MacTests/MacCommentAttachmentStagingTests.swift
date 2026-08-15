//  MacCommentAttachmentStagingTests.swift
//  Regression guard for Task 3b3d70ce — "[mac] attach screenshot or file from computer should show
//  preview in comments and post when pressing post."
//
//  The Mac paperclip used to open a file panel and then POST a comment immediately, with the
//  filename as the body. So it was not "attach to this comment" — it was "post a comment that is
//  a file", with no preview and no way to type anything alongside it.
//
//  Two things are guarded here, and the second is the one that rots quietly.
//
//  1. The file is STAGED, not posted. `attachComment` must not reach `createComment` — if it
//     does, the preview never gets a chance to exist.
//  2. Posting goes through the SHARED `CommentAttachmentBatch` and `AttachmentQueue` rather than
//     Mac-local arithmetic. `AttachmentQueue`'s own header records why: the first pass at this
//     got the "pick a second file" rule right in two inputs and wrong in the third, so a second
//     pick silently discarded the first. A fourth hand-rolled copy on Mac is that bug waiting.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacCommentAttachmentStagingTests: XCTestCase {

    private func detailSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/Views/MacTaskDetailView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The body of `attachComment()`, which is the function the paperclip calls.
    private func attachCommentBody() throws -> String {
        let source = try detailSource()
        guard let start = source.range(of: "private func attachComment()") else {
            XCTFail("attachComment() not found — did it move?")
            return ""
        }
        // Up to the next top-level `private func`, which is close enough to bound one function.
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    private func")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - The bug

    /// Attaching must STAGE. The moment it posts, there is nothing left to preview.
    func testAttachingStagesRatherThanPosting() throws {
        let body = try attachCommentBody()
        XCTAssertFalse(body.contains("createComment"),
                       "attachComment() still posts directly — staging is what gives the preview something to show")
    }

    /// Staging goes through the shared queue, which owns the cap and the duplicate rule.
    func testStagingUsesTheSharedQueue() throws {
        let body = try attachCommentBody()
        XCTAssertTrue(body.contains("AttachmentQueue"),
                      "attachComment() must stage via AttachmentQueue, not a bare array append")
    }

    // MARK: - Posting

    /// One comment per file is an API constraint, not a preference: the comments endpoint takes a
    /// single fileId. The shared splitter already encodes that, including putting the typed text
    /// on the first comment only rather than repeating it.
    func testPostingUsesTheSharedSplitter() throws {
        let source = try detailSource()
        XCTAssertTrue(source.contains("CommentAttachmentBatch.drafts"),
                      "Posting must fan out through CommentAttachmentBatch, not a Mac-local loop")
    }

    /// A preview the user cannot dismiss is a trap — a mis-picked file would have to be posted.
    func testAStagedFileCanBeRemoved() throws {
        let source = try detailSource()
        XCTAssertTrue(source.contains("AttachmentQueue.removing"),
                      "Each staged file needs a remove affordance backed by the shared rule")
    }

    // MARK: - The shared rules themselves

    /// Cheap proof the Mac is inheriting real behaviour rather than a lookalike: the queue caps,
    /// and at the cap it drops the NEW file rather than evicting one the user can see.
    func testTheSharedQueueCapsWithoutDiscardingWhatIsVisible() {
        let staged = (0..<AttachmentQueue.maxAttachments).map {
            AttachedFileInfo(fileId: "f\($0)", fileName: "f\($0).png", fileSize: 1,
                             mimeType: "image/png", imageData: nil)
        }
        XCTAssertTrue(AttachmentQueue.isFull(staged))
        let after = AttachmentQueue.adding(
            AttachedFileInfo(fileId: "new", fileName: "new.png", fileSize: 1,
                             mimeType: "image/png", imageData: nil),
            to: staged)
        XCTAssertEqual(after.map(\.fileId), staged.map(\.fileId),
                       "At the cap the new file is dropped; the staged ones stay visible")
    }
}
#endif
