//  MacProfileStatsTests.swift
//  Regression tests for Task 0994eabb — "[mac] add user profile (see iOS): completed, inspired,
//  supported; match web and iOS; link user names to open it".
//
//  The Mac had no profile at all, though ProfileCache and the strings were already shared. These
//  pin the parts that must match iOS exactly — card order, wording, and which names are links.

import XCTest
@testable import Astrid_Mac

final class MacProfileStatsTests: XCTestCase {

    private let stats = UserStats(completed: 12, inspired: 3, supported: 7)

    /// Same three cards, same order as iOS `statsGrid`.
    func testCardsMatchTheIOSOrderAndValues() {
        let cards = MacProfileStats.cards(stats)
        XCTAssertEqual(cards.map(\.value), [12, 3, 7])
        XCTAssertEqual(cards.map(\.labelKey), ["stats.completed", "stats.inspired", "stats.supported"])
        XCTAssertEqual(cards.map(\.symbol), ["checkmark.circle.fill", "lightbulb.fill", "heart.fill"])
    }

    /// Labels and taglines come from the SHARED keys, so the two apps cannot word this differently.
    func testLabelsAndTaglinesAreLocalized() {
        for card in MacProfileStats.cards(stats) {
            XCTAssertEqual(card.label, NSLocalizedString(card.labelKey, comment: ""))
            XCTAssertNotEqual(card.label, card.labelKey, "\(card.labelKey) does not resolve")
            XCTAssertFalse(card.tagline.isEmpty)
            XCTAssertNotEqual(card.tagline, card.taglineKey, "\(card.taglineKey) does not resolve")
        }
    }

    func testZeroStatsStillRenderAllThreeCards() {
        XCTAssertEqual(MacProfileStats.cards(UserStats(completed: 0, inspired: 0, supported: 0)).count, 3)
    }

    // MARK: which names open a profile

    /// A system comment has no author id — making it a link would give every "marked complete"
    /// line a clickable name that goes nowhere.
    func testSystemAuthorsAreNotLinks() {
        XCTAssertNil(MacProfileLink.userId(authorId: nil))
        XCTAssertEqual(MacProfileLink.userId(authorId: "u1"), "u1")
        XCTAssertNil(MacProfileLink.userId(authorId: ""), "An empty id is not a user")
    }

    /// Your own name is a link too — iOS opens your profile from your own comments.
    func testYourOwnNameIsALink() {
        XCTAssertEqual(MacProfileLink.userId(authorId: "me"), "me")
    }

    // MARK: load states

    func testStatesReuseTheIOSErrorCopy() {
        XCTAssertEqual(MacProfileState.message(forStatus: 404),
                       NSLocalizedString("profile.error_not_found", comment: ""))
        XCTAssertEqual(MacProfileState.message(forStatus: 401),
                       NSLocalizedString("profile.error_not_signed_in", comment: ""))
        XCTAssertEqual(MacProfileState.message(forStatus: 500),
                       NSLocalizedString("profile.error_load_failed", comment: ""))
        for status in [404, 401, 500] {
            XCTAssertFalse(MacProfileState.message(forStatus: status).hasPrefix("profile."),
                           "status \(status) shows an unresolved key")
        }
    }
}
