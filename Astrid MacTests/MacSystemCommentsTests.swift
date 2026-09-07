//  MacSystemCommentsTests.swift
//  Regression tests for Task 9c24d16c — "[mac] add show/hide system comments in task details".
//
//  iOS hides authorId == nil comments by default and offers a toggle only when there are some.
//  The Mac showed every status line all the time, burying the actual conversation.

import XCTest
@testable import Astrid_Mac

final class MacSystemCommentsTests: XCTestCase {

    private func comment(_ id: String, author: String?) -> Comment {
        Comment(id: id, content: "c\(id)", type: .TEXT, authorId: author, author: nil, taskId: "t")
    }

    private var mixed: [Comment] {
        [comment("1", author: "u1"), comment("2", author: nil), comment("3", author: "u2")]
    }

    // These cases still describe Mac behaviour — the thread the Mac renders. What changed under
    // task 41abea5f (AITD-318) is that there is now ONE implementation of the rule behind them:
    // `CommentVisibility` in shared Core, which is what the Mac view calls directly. The Mac copy
    // they used to exercise had already lost the offline guard.

    /// A comment with no author is the system talking — that is the shared rule.
    func testSystemIsTheOneWithoutAnAuthor() {
        XCTAssertTrue(CommentVisibility.isSystem(authorId: nil, isOffline: false))
        XCTAssertFalse(CommentVisibility.isSystem(authorId: "u1", isOffline: false))
    }

    func testHiddenByDefault() {
        let shown = CommentVisibility.displayed(mixed, showSystem: false, isOffline: false)
        XCTAssertEqual(shown.map(\.id), ["1", "3"])
    }

    func testShownWhenToggledOn() {
        let shown = CommentVisibility.displayed(mixed, showSystem: true, isOffline: false)
        XCTAssertEqual(shown.map(\.id), ["1", "2", "3"])
    }

    /// Offline, cached comments can come back WITHOUT an authorId. Filtering then would empty the
    /// thread — far worse than showing a few status lines, so iOS shows everything and so do we.
    func testOfflineShowsEverything() {
        XCTAssertEqual(CommentVisibility.displayed(mixed, showSystem: false, isOffline: true).count, 3)
    }

    /// The count in the header follows what is actually displayed, or it contradicts the list.
    func testCountFollowsTheFilter() {
        XCTAssertEqual(CommentVisibility.count(mixed, showSystem: false, isOffline: false), 2)
        XCTAssertEqual(CommentVisibility.count(mixed, showSystem: true, isOffline: false), 3)
    }

    /// The drift this task removed, pinned from the Mac side: `showsToggle` is Mac presentation,
    /// but the "what is a system comment?" underneath it is the SHARED rule, offline guard and
    /// all. The deleted Mac `isSystem` had no offline guard, so any future Mac caller reaching for
    /// it directly would have classified every offline comment as system chatter.
    func testTheToggleAsksTheSharedRuleIncludingItsOfflineGuard() {
        let offlineCached = [comment("1", author: nil), comment("2", author: nil)]

        XCTAssertFalse(MacSystemComments.showsToggle(offlineCached, isOffline: true),
                       "offline, an authorless comment is not evidence of anything")
        XCTAssertTrue(MacSystemComments.showsToggle(offlineCached, isOffline: false),
                      "online, the same comments are system chatter and the toggle has work to do")

        for c in offlineCached {
            XCTAssertFalse(CommentVisibility.isSystem(authorId: c.authorId, isOffline: true),
                           "the shared rule is what the toggle must agree with")
        }
    }

    /// No system comments → no toggle. An affordance that reveals nothing is noise.
    func testToggleOnlyWhenThereIsSomethingToReveal() {
        XCTAssertTrue(MacSystemComments.showsToggle(mixed, isOffline: false))
        XCTAssertFalse(MacSystemComments.showsToggle([comment("1", author: "u1")], isOffline: false))
        XCTAssertFalse(MacSystemComments.showsToggle(mixed, isOffline: true),
                       "Offline everything is already shown, so the toggle would do nothing")
    }

    func testToggleTitleIsLocalizedAndStateful() {
        let show = MacSystemComments.toggleTitle(showingSystem: false)
        let hide = MacSystemComments.toggleTitle(showingSystem: true)
        XCTAssertNotEqual(show, hide)
        for title in [show, hide] {
            XCTAssertFalse(title.isEmpty)
            XCTAssertFalse(title.hasPrefix("mac.system_comments"), "\(title) is an unresolved key")
        }
    }
}
