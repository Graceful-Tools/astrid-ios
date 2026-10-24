//  CommentVisibilityTests.swift
//  First extraction out of CommentSectionViewEnhanced (Task 946c41c6).
//
//  That file is 1,898 lines and had zero test coverage. The task is deliberately ONE extraction
//  rather than a restructure: the web half of this review found its god files had *grown* after
//  being flagged, and that only tiny one-at-a-time extractions actually moved.
//
//  This one is worth doing first because it carries a caveat that is easy to lose. "A system
//  comment is one with no author" is nearly right — but OFFLINE, cached comments can come back
//  without their authorId, so applying that rule offline would hide the user's own comments in
//  their own thread. The existing code gets this right in three separate places (the displayed
//  list, the count beside the header, and each row's own styling), which is three chances for the
//  next edit to get it wrong in one of them.

import XCTest
@testable import Astrid_App

final class CommentVisibilityTests: XCTestCase {

    private func comment(_ id: String, authorId: String?) -> Comment {
        Comment(id: id, content: "c", type: .TEXT, authorId: authorId,
                author: nil, taskId: "t1", createdAt: nil, updatedAt: nil)
    }

    private var mixed: [Comment] {
        [comment("u1", authorId: "person"),
         comment("s1", authorId: nil),
         comment("u2", authorId: "person")]
    }

    // MARK: - What counts as a system comment

    func testAnAuthorlessCommentIsASystemComment() {
        XCTAssertTrue(CommentVisibility.isSystem(authorId: nil, isOffline: false))
    }

    func testAnAuthoredCommentIsNeverASystemComment() {
        XCTAssertFalse(CommentVisibility.isSystem(authorId: "person", isOffline: false))
        XCTAssertFalse(CommentVisibility.isSystem(authorId: "person", isOffline: true))
    }

    /// The caveat. Offline, a cached comment can arrive without its author, so "no author" stops
    /// being evidence of anything — and treating it as a system comment would hide the user's own
    /// words from their own thread, offline, which is exactly when they cannot check.
    func testNothingCountsAsSystemWhileOffline() {
        XCTAssertFalse(CommentVisibility.isSystem(authorId: nil, isOffline: true))
    }

    // MARK: - A GitHub commenter with no Astrid account (AITD-517)

    /// AWTD-1283 brings comments made on github.com onto the mirrored task. A commenter with no
    /// Astrid account arrives with `authorId` and `author` both null and `remoteAuthorLogin` set.
    /// That is a person talking, so it must not be hidden behind "show system comments".
    private var remote: Comment {
        var c = comment("r1", authorId: nil)
        c.remoteAuthorLogin = "octocat"
        return c
    }

    func testAITD517_aGitHubCommenterWithoutAnAccountIsNotASystemComment() {
        XCTAssertFalse(CommentVisibility.isSystem(remote, isOffline: false))
        XCTAssertEqual(CommentVisibility.displayed([remote], showSystem: false, isOffline: false).map(\.id),
                       ["r1"])
    }

    func testAITD517_theLoginDecodesAndNamesTheAuthor() throws {
        let json = #"{"id":"r1","content":"Looks good","type":"TEXT","taskId":"t1","authorId":null,"author":null,"remoteAuthorLogin":"octocat","remoteNodeId":"IC_kwDO123"}"#
        let decoded = try JSONDecoder().decode(Comment.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.remoteAuthorLogin, "octocat")
        XCTAssertEqual(decoded.remoteNodeId, "IC_kwDO123")
        XCTAssertEqual(decoded.authorDisplayName, "@octocat")
        XCTAssertEqual(decoded.authorInitials, "O")
    }

    func testAITD517_anOrdinaryCommentIsNamedByItsAuthor() {
        var c = comment("u1", authorId: "u1")
        c.author = User(id: "u1", email: "ada@example.com", name: "Ada", image: nil)
        XCTAssertEqual(c.authorDisplayName, "Ada")
        XCTAssertNil(comment("s1", authorId: nil).authorDisplayName, "the server has no name")
    }

    // MARK: - What gets shown

    func testOnlineHidesSystemCommentsByDefault() {
        let shown = CommentVisibility.displayed(mixed, showSystem: false, isOffline: false)
        XCTAssertEqual(shown.map(\.id), ["u1", "u2"])
    }

    func testOnlineShowsEverythingWhenAsked() {
        let shown = CommentVisibility.displayed(mixed, showSystem: true, isOffline: false)
        XCTAssertEqual(shown.map(\.id), ["u1", "s1", "u2"])
    }

    /// Offline shows everything regardless of the toggle — same reason as above.
    func testOfflineShowsEverythingWhateverTheToggleSays() {
        for showSystem in [true, false] {
            XCTAssertEqual(
                CommentVisibility.displayed(mixed, showSystem: showSystem, isOffline: true).map(\.id),
                ["u1", "s1", "u2"],
                "offline must not hide anything (showSystem=\(showSystem))")
        }
    }

    /// The count beside the header has to agree with the list under it. These were two separate
    /// computed properties repeating the same rule.
    func testTheCountAlwaysMatchesWhatIsShown() {
        for isOffline in [true, false] {
            for showSystem in [true, false] {
                XCTAssertEqual(
                    CommentVisibility.count(mixed, showSystem: showSystem, isOffline: isOffline),
                    CommentVisibility.displayed(mixed, showSystem: showSystem, isOffline: isOffline).count,
                    "count and list disagreed (offline=\(isOffline), showSystem=\(showSystem))")
            }
        }
    }

    func testOrderIsPreserved() {
        XCTAssertEqual(CommentVisibility.displayed(mixed, showSystem: true, isOffline: false).map(\.id),
                       mixed.map(\.id))
    }

    func testAnEmptyThreadIsEmptyInEveryCombination() {
        for isOffline in [true, false] {
            for showSystem in [true, false] {
                XCTAssertTrue(CommentVisibility.displayed([], showSystem: showSystem,
                                                          isOffline: isOffline).isEmpty)
            }
        }
    }
}
