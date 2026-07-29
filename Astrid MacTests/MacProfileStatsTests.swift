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

    // MARK: every place a person is shown (Task 0994eabb follow-up)

    /// The sidebar account row is how you reach your OWN profile — iOS gets there from its profile
    /// tab, and the Mac has no tab bar, so the bottom-left row has to be the door.
    func testTheAccountRowOpensYourOwnProfile() {
        let me = User(id: "me", email: "me@astrid.cc", name: "Me", image: nil)
        XCTAssertEqual(MacProfileLink.ownUserId(me), "me")
    }

    /// Signed out there is no profile to open, so the row must not look clickable.
    func testTheAccountRowIsNotALinkWhenSignedOut() {
        XCTAssertNil(MacProfileLink.ownUserId(nil))
    }

    /// An AI agent has no user profile — a link on its name or avatar 404s.
    func testAgentsAreNotLinks() {
        XCTAssertNil(MacProfileLink.userId(authorId: "agent-1", isAgent: true))
        XCTAssertEqual(MacProfileLink.userId(authorId: "u1", isAgent: false), "u1")
    }

    /// A member row resolves through the same rule as a comment author, so the members list and
    /// the comment bubble can never disagree about who is clickable.
    func testMemberRowsAreLinks() {
        let member = ListMember(id: "m1", listId: "l1", userId: "u2", role: "member",
                                user: User(id: "u2", email: "them@astrid.cc", name: "Them", image: nil))
        XCTAssertEqual(MacProfileLink.userId(authorId: member.userId,
                                             isAgent: member.user?.isAIAgent == true), "u2")
    }

    /// An agent invited to a list is still not a profile.
    func testAgentMemberRowsAreNotLinks() {
        let agent = User(id: "a1", email: "agent@astrid.cc", name: "Agent", image: nil, isAIAgent: true)
        let member = ListMember(id: "m2", listId: "l1", userId: "a1", role: "member", user: agent)
        XCTAssertNil(MacProfileLink.userId(authorId: member.userId,
                                           isAgent: member.user?.isAIAgent == true))
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
