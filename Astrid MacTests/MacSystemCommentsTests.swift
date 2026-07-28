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

    /// A comment with no author is the system talking — that is the iOS rule.
    func testSystemIsTheOneWithoutAnAuthor() {
        XCTAssertTrue(MacSystemComments.isSystem(comment("2", author: nil)))
        XCTAssertFalse(MacSystemComments.isSystem(comment("1", author: "u1")))
    }

    func testHiddenByDefault() {
        let shown = MacSystemComments.displayed(mixed, showingSystem: false, isOffline: false)
        XCTAssertEqual(shown.map(\.id), ["1", "3"])
    }

    func testShownWhenToggledOn() {
        let shown = MacSystemComments.displayed(mixed, showingSystem: true, isOffline: false)
        XCTAssertEqual(shown.map(\.id), ["1", "2", "3"])
    }

    /// Offline, cached comments can come back WITHOUT an authorId. Filtering then would empty the
    /// thread — far worse than showing a few status lines, so iOS shows everything and so do we.
    func testOfflineShowsEverything() {
        XCTAssertEqual(MacSystemComments.displayed(mixed, showingSystem: false, isOffline: true).count, 3)
    }

    /// The count in the header follows what is actually displayed, or it contradicts the list.
    func testCountFollowsTheFilter() {
        XCTAssertEqual(MacSystemComments.count(mixed, showingSystem: false, isOffline: false), 2)
        XCTAssertEqual(MacSystemComments.count(mixed, showingSystem: true, isOffline: false), 3)
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
