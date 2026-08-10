//  MacCommentPostTests.swift
//  Task a3f868b4 — "when commenting on a task the first comment doesn't appear but the
//  second one does".
//
//  MacSystemComments hides any comment with no authorId, because that is how the server
//  marks its own status chatter ("marked complete", "moved to …"). The Mac posted comments
//  WITHOUT an author, so the optimistic comment it appended to the cache was filtered
//  straight back out — your own comment vanished. It reappeared only once the Outbox synced
//  and a network refresh returned the server copy, which does carry an author. Posting a
//  second comment triggered exactly that refresh, which is why the second one "worked".

import XCTest
@testable import Astrid_Mac

final class MacCommentPostTests: XCTestCase {

    private func posted(authorId: String?) -> Comment {
        Comment(id: "temp_1",
                content: "hello",
                type: .TEXT,
                authorId: authorId,
                author: nil,
                taskId: "task_1",
                createdAt: Date(),
                updatedAt: Date(),
                attachmentUrl: nil,
                attachmentName: nil,
                attachmentType: nil,
                attachmentSize: nil,
                parentCommentId: nil,
                replies: nil,
                secureFiles: nil)
    }

    /// The regression: a comment you just posted must show up in the thread immediately.
    func testAJustPostedCommentIsVisibleInTheThread() {
        let comment = posted(authorId: MacCommentPost.authorId(currentUserId: "user_1"))
        XCTAssertFalse(MacSystemComments.isSystem(comment),
                       "Your own comment must never be mistaken for system chatter")
        XCTAssertEqual(MacSystemComments.displayed([comment], showingSystem: false, isOffline: false).count, 1,
                       "Task a3f868b4: the first comment must appear without waiting for a refresh")
    }

    /// The trap itself, pinned so nobody reintroduces it: post without an author and the
    /// comment is hidden. This is what the Mac was doing.
    func testACommentPostedWithoutAnAuthorIsHiddenAsSystemChatter() {
        let comment = posted(authorId: nil)
        XCTAssertTrue(MacSystemComments.isSystem(comment))
        XCTAssertTrue(MacSystemComments.displayed([comment], showingSystem: false, isOffline: false).isEmpty,
                      "Authorless comments are filtered — which is why posting without one lost the comment")
    }

    func testPostCarriesTheSignedInUser() {
        XCTAssertEqual(MacCommentPost.authorId(currentUserId: "user_1"), "user_1")
        XCTAssertTrue(MacCommentPost.isVisibleInThread(authorId: MacCommentPost.authorId(currentUserId: "user_1")))
        XCTAssertFalse(MacCommentPost.isVisibleInThread(authorId: nil))
    }
}
