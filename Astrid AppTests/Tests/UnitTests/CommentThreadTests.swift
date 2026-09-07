//  CommentThreadTests.swift
//  Regression guard for AITD-331 — "[ios] Dedupe incoming comment events by comment id, not by
//  author; nest flat replies". Web half: astrid-web task cb1581e0.
//
//  The server change these lock in: the comment SSE fan-out no longer removes the comment's author
//  from the audience. It used to, on the theory that the author already sees their own comment
//  optimistically — true of the one device that posted it, false for every other device that user
//  has open. A user is not a device. So this app now receives comment_created / comment_deleted for
//  comments it wrote itself, where before it received none, and every rule below has to survive its
//  own echo arriving twice, and arriving BEFORE the POST response.

import XCTest
@testable import Astrid_App

final class CommentThreadTests: XCTestCase {

    private func comment(_ id: String,
                         content: String = "hello",
                         authorId: String? = "author",
                         parent: String? = nil,
                         clientRequestId: String? = nil) -> Comment {
        Comment(id: id, content: content, type: .TEXT, authorId: authorId,
                author: nil, taskId: "t1", createdAt: nil, updatedAt: nil,
                attachmentUrl: nil, attachmentName: nil, attachmentType: nil, attachmentSize: nil,
                parentCommentId: parent, replies: nil, secureFiles: nil,
                clientRequestId: clientRequestId)
    }

    // MARK: - (1) Dedupe on comment id, never on author

    func testAnEchoOfOurOwnCommentDoesNotDuplicateIt() {
        // The comment is already in the thread under its real id; the fan-out now sends it to us
        // as well because we are its author. Applying it again must change nothing.
        let thread = [comment("c1", authorId: "me")]

        let after = CommentThread.upsert(comment("c1", authorId: "me"), into: thread)

        XCTAssertEqual(after.map(\.id), ["c1"])
    }

    func testACommentWeWroteOnAnotherDeviceIsAccepted() {
        // The bug the server change exists to fix. Skipping events authored by the current user
        // would drop this one — it is ours, but this device has never seen it.
        let thread = [comment("c1", authorId: "me")]

        let after = CommentThread.upsert(comment("c2", authorId: "me", parent: nil), into: thread)

        XCTAssertEqual(after.map(\.id), ["c1", "c2"])
    }

    // MARK: - (2) The optimistic row collapses onto the server row

    func testTheEchoArrivingBeforeThePostResponseLeavesOneRow() {
        let thread = [comment("temp_A", content: "ship it", authorId: "me")]

        let after = CommentThread.settle(
            comment("real_A", content: "ship it", authorId: "me", clientRequestId: "temp_A"),
            in: thread)

        XCTAssertEqual(after.map(\.id), ["real_A"], "the temp row must be removed, not left beside it")
    }

    func testTwoAttachmentsWithNoTextDoNotCollapseOntoEachOther() {
        // The content match this replaces would fold these together: an attachment-only comment has
        // EMPTY content, so every empty temp row looks alike. clientRequestId tells them apart.
        let thread = [comment("temp_A", content: "", authorId: "me"),
                      comment("temp_B", content: "", authorId: "me")]

        let after = CommentThread.settle(
            comment("real_B", content: "", authorId: "me", clientRequestId: "temp_B"),
            in: thread)

        XCTAssertEqual(after.map(\.id), ["temp_A", "real_B"])
    }

    func testTheSameWordPostedTwiceStaysTwoComments() {
        let thread = [comment("temp_A", content: "ok", authorId: "me"),
                      comment("temp_B", content: "ok", authorId: "me")]

        let after = CommentThread.settle(
            comment("real_B", content: "ok", authorId: "me", clientRequestId: "temp_B"),
            in: thread)

        XCTAssertEqual(after.map(\.id), ["temp_A", "real_B"])
    }

    func testAnOlderTempRowWithNoClientRequestIdStillSettlesOnContent() {
        // A comment queued by a previous build sent an Outbox UUID the display row never knew.
        let thread = [comment("temp_A", content: "queued offline", authorId: "me")]

        let after = CommentThread.settle(
            comment("real_A", content: "queued offline", authorId: "me"), in: thread)

        XCTAssertEqual(after.map(\.id), ["real_A"])
    }

    func testSettlingIsIdempotentWhenTheEchoArrivesAfterThePostResponse() {
        let settled = CommentThread.settle(
            comment("real_A", content: "ship it", authorId: "me", clientRequestId: "temp_A"),
            in: [comment("temp_A", content: "ship it", authorId: "me")])

        let again = CommentThread.settle(
            comment("real_A", content: "ship it", authorId: "me", clientRequestId: "temp_A"),
            in: settled)

        XCTAssertEqual(again.map(\.id), ["real_A"])
    }

    func testSettlingKeepsTheAttachmentThisDeviceAlreadyResolved() {
        var optimistic = comment("temp_A", content: "", authorId: "me")
        optimistic.secureFiles = [SecureFile(id: "f1", name: "shot.png", size: 10, mimeType: "image/png")]

        let after = CommentThread.settle(
            comment("real_A", content: "", authorId: "me", clientRequestId: "temp_A"),
            in: [optimistic])

        XCTAssertEqual(after.first?.secureFiles?.first?.name, "shot.png")
    }

    // MARK: - (3) Delete and edit are idempotent and reply-aware

    func testDeletingAReplyFromAnotherDeviceRemovesIt() {
        let thread = CommentThread.nest([comment("c1"), comment("r1", parent: "c1")])

        let after = CommentThread.remove(id: "r1", from: thread)

        XCTAssertEqual(after.map(\.id), ["c1"])
        XCTAssertNil(after.first?.replies, "the last reply going away should leave no empty shelf")
    }

    func testDeletingTwiceIsANoOp() {
        let thread = CommentThread.nest([comment("c1"), comment("r1", parent: "c1")])

        let once = CommentThread.remove(id: "r1", from: thread)
        let twice = CommentThread.remove(id: "r1", from: once)

        XCTAssertEqual(CommentThread.flatten(twice).map(\.id), ["c1"])
    }

    func testDeletingOurOwnCommentAppliesRatherThanBeingSkippedAsOurEcho() {
        let thread = [comment("c1", authorId: "me")]

        XCTAssertEqual(CommentThread.remove(id: "c1", from: thread).count, 0)
    }

    func testEditingAReplyFromAnotherDeviceUpdatesIt() {
        let thread = CommentThread.nest([comment("c1"), comment("r1", content: "before", parent: "c1")])

        let after = CommentThread.applyEdit(
            comment("r1", content: "after", parent: "c1"), to: thread)

        XCTAssertEqual(after.first?.replies?.first?.content, "after")
    }

    func testEditingDoesNotBlankTheAuthorTheServerOmitted() {
        var local = comment("c1", content: "before")
        local.author = User(id: "author", email: "a@b.c", name: "Ada", image: nil)

        let after = CommentThread.applyEdit(comment("c1", content: "after", authorId: nil), to: [local])

        XCTAssertEqual(after.first?.content, "after")
        XCTAssertEqual(after.first?.author?.name, "Ada")
    }

    // MARK: - (4) Replies come back flat

    func testFlatRepliesAreGroupedUnderTheirParent() {
        let flat = [comment("c1"), comment("c2"), comment("r1", parent: "c1")]

        let thread = CommentThread.nest(flat)

        XCTAssertEqual(thread.map(\.id), ["c1", "c2"])
        XCTAssertEqual(thread.first?.replies?.map(\.id), ["r1"])
    }

    func testAReplyWhoseParentIsMissingStaysVisible() {
        // The 500-row response cap can cut the parent off. Dropping the orphan would silently
        // delete somebody's words from the thread.
        let thread = CommentThread.nest([comment("r1", parent: "gone")])

        XCTAssertEqual(thread.map(\.id), ["r1"])
    }

    func testAReplyToAReplyHangsOffTheTopLevelAncestor() {
        // The row view renders exactly one level, so a deeper tree would be built and never drawn.
        let thread = CommentThread.nest([comment("c1"), comment("r1", parent: "c1"), comment("r2", parent: "r1")])

        XCTAssertEqual(thread.map(\.id), ["c1"])
        XCTAssertEqual(thread.first?.replies?.map(\.id), ["r1", "r2"])
    }

    func testNestingIsStableWhenAppliedToAnAlreadyNestedThread() {
        let once = CommentThread.nest([comment("c1"), comment("r1", parent: "c1")])

        let twice = CommentThread.nest(CommentThread.flatten(once))

        XCTAssertEqual(twice.map(\.id), ["c1"])
        XCTAssertEqual(twice.first?.replies?.map(\.id), ["r1"])
    }

    func testANewReplyFromAnotherDeviceLandsUnderItsParent() {
        let thread = CommentThread.nest([comment("c1")])

        let after = CommentThread.upsert(comment("r1", parent: "c1"), into: thread)

        XCTAssertEqual(after.map(\.id), ["c1"])
        XCTAssertEqual(after.first?.replies?.map(\.id), ["r1"])
    }

    func testFlattenReturnsRepliesAlongsideTheirParents() {
        let thread = CommentThread.nest([comment("c1"), comment("r1", parent: "c1"), comment("c2")])

        XCTAssertEqual(CommentThread.flatten(thread).map(\.id), ["c1", "r1", "c2"])
    }

    func testACycleInTheDataTerminatesAndLosesNothing() {
        // Neither row can be anyone's child, so both fall back to the orphan rule and stay visible.
        // The point of the test is that the parent walk is bounded — a cycle must not hang.
        var a = comment("a"); a.parentCommentId = "b"
        var b = comment("b"); b.parentCommentId = "a"

        XCTAssertEqual(Set(CommentThread.nest([a, b]).map(\.id)), ["a", "b"])
    }
}

/// (5) The new `data.userId` is for presentation only — never for deciding whether to apply an
/// event. Its one consumer on iOS is the local notification, and that check became load-bearing
/// the moment the server stopped excluding a comment's author from the fan-out (AITD-331).
final class CommentNotificationPolicyTests: XCTestCase {

    func testWeAreNeverNotifiedAboutOurOwnComment() {
        XCTAssertFalse(CommentNotificationPolicy.shouldNotify(
            authorId: "me", currentUserId: "me", isMentioned: true, isAssignee: true),
            "the echo of our own comment must not buzz our other devices")
    }

    func testAMentionFromSomeoneElseNotifies() {
        XCTAssertTrue(CommentNotificationPolicy.shouldNotify(
            authorId: "them", currentUserId: "me", isMentioned: true, isAssignee: false))
    }

    func testACommentOnOurAssignedTaskNotifies() {
        XCTAssertTrue(CommentNotificationPolicy.shouldNotify(
            authorId: "them", currentUserId: "me", isMentioned: false, isAssignee: true))
    }

    func testAnUnrelatedCommentDoesNotNotify() {
        XCTAssertFalse(CommentNotificationPolicy.shouldNotify(
            authorId: "them", currentUserId: "me", isMentioned: false, isAssignee: false))
    }

    func testASystemCommentIsJudgedOnMentionAndAssignmentLikeAnyOther() {
        XCTAssertTrue(CommentNotificationPolicy.shouldNotify(
            authorId: nil, currentUserId: "me", isMentioned: false, isAssignee: true))
    }
}
