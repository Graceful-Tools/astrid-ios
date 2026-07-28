//  MacAuthorDisplayTests.swift
//  Regression tests for Task 283a03df — "[mac] comments from the current user have no profile
//  photo and are listed as 'someone'".
//
//  A comment you just posted carries `authorId` but often no embedded `author`. The board editor
//  and chat panel read `author?.name ?? "Someone"` without ever asking whether the author is YOU,
//  so your own words came back attributed to a stranger with a grey "?" circle.

import XCTest
@testable import Astrid_Mac

final class MacAuthorDisplayTests: XCTestCase {

    private let me = User(id: "me", email: "me@example.com", name: "Jon Paris", image: "https://img/me.png")
    private let other = User(id: "u2", email: "her@example.com", name: "Ada", image: "https://img/ada.png")

    /// The exact shape that produced the bug: my id, no embedded author object.
    func testMyOwnCommentIsRecognisedWithoutAnEmbeddedAuthor() {
        let d = MacAuthorDisplay.of(authorId: "me", author: nil, currentUser: me)
        XCTAssertTrue(d.isCurrentUser)
        XCTAssertEqual(d.name, NSLocalizedString("assignee.you", comment: ""))
        XCTAssertEqual(d.imageURL, "https://img/me.png", "My own photo comes from the cached session, not the payload")
        XCTAssertEqual(d.initials, me.initials)
    }

    func testOtherPeopleKeepTheirNameAndPhoto() {
        let d = MacAuthorDisplay.of(authorId: "u2", author: other, currentUser: me)
        XCTAssertFalse(d.isCurrentUser)
        XCTAssertEqual(d.name, other.displayName)
        XCTAssertEqual(d.imageURL, other.cachedImageURL)
    }

    /// Falling back to the embedded author's own fields when the id is missing entirely.
    func testEmbeddedAuthorIsUsedWhenTheIdIsAbsent() {
        let d = MacAuthorDisplay.of(authorId: nil, author: other, currentUser: me)
        XCTAssertFalse(d.isCurrentUser)
        XCTAssertEqual(d.name, other.displayName)
    }

    /// A genuinely unidentifiable author still reads as a person, in the user's language — and
    /// never as the raw English word this bug was named after.
    func testUnknownAuthorIsLocalized() {
        let d = MacAuthorDisplay.of(authorId: nil, author: nil, currentUser: me)
        XCTAssertFalse(d.isCurrentUser)
        XCTAssertFalse(d.name.isEmpty)
        XCTAssertNotEqual(d.name, "mac.unknown_author")
        XCTAssertNotEqual(d.name, "Someone")
        XCTAssertNil(d.imageURL)
        XCTAssertEqual(d.initials, "?")
    }

    /// Signed out: nothing is "mine".
    func testNoSessionMeansNothingIsMine() {
        XCTAssertFalse(MacAuthorDisplay.of(authorId: "me", author: nil, currentUser: nil).isCurrentUser)
    }

    /// A system comment (authorId nil by design) must not be mistaken for the current user.
    func testSystemCommentIsNotMine() {
        XCTAssertFalse(MacAuthorDisplay.of(authorId: nil, author: nil, currentUser: me).isCurrentUser)
    }
}
