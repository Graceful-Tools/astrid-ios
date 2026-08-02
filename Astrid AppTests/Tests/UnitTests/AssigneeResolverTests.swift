//  AssigneeResolverTests.swift
//  Regression tests for Task 42013da7 — "sometimes when choosing the assignee the profile photo
//  in assignee doesn't change".
//
//  The avatar was resolved by looking the id up in `availableMembers` ALONE. That list is the
//  current list's members, so picking anyone it does not hold — someone just added by email, a
//  member of a different list, an AI agent fetched separately — found nothing and fell back to a
//  photoless placeholder. The previously-rendered person stayed on screen until something else
//  forced a redraw, which is exactly "the photo didn't change".
//
//  Resolution now walks every source it has, in order of how much it knows.

import XCTest
@testable import Astrid_App

final class AssigneeResolverTests: XCTestCase {

    private func user(_ id: String, name: String? = nil, image: String? = nil) -> User {
        User(id: id, email: "\(id)@astrid.cc", name: name, image: image)
    }

    /// THE BUG: an id that is not in `availableMembers` must still resolve to that person, not to
    /// nothing — otherwise the view keeps whoever it drew last.
    func testResolvesSomeoneMissingFromTheMemberList() {
        let resolved = AssigneeResolver.resolve(id: "new-person",
                                                members: [user("someone-else")],
                                                taskAssignee: nil)
        XCTAssertEqual(resolved?.id, "new-person",
                       "an unknown id must still produce a user, or the old avatar persists")
    }

    /// The richest source wins: a full member record carries the name and photo.
    func testPrefersTheFullMemberRecord() {
        let member = user("u1", name: "Dana", image: "https://example.com/dana.jpg")
        let resolved = AssigneeResolver.resolve(id: "u1",
                                                members: [member],
                                                taskAssignee: user("u1"))
        XCTAssertEqual(resolved?.name, "Dana")
        XCTAssertEqual(resolved?.image, "https://example.com/dana.jpg")
    }

    /// Falls back to the task's embedded assignee when the member list has not loaded.
    func testFallsBackToTheTasksOwnAssignee() {
        let embedded = user("u2", name: "Sam", image: "https://example.com/sam.jpg")
        let resolved = AssigneeResolver.resolve(id: "u2", members: [], taskAssignee: embedded)
        XCTAssertEqual(resolved?.name, "Sam")
    }

    /// A STALE embedded assignee must never win over the id being asked for — that is the exact
    /// shape of "the photo shows the previous person".
    func testAStaleEmbeddedAssigneeIsIgnored() {
        let previous = user("old-person", name: "Previous", image: "https://example.com/old.jpg")
        let resolved = AssigneeResolver.resolve(id: "new-person", members: [], taskAssignee: previous)
        XCTAssertEqual(resolved?.id, "new-person")
        XCTAssertNotEqual(resolved?.name, "Previous", "the previous assignee is still on screen")
    }

    /// Unassigned resolves to nobody, so the caller shows its unassigned state.
    func testUnassignedResolvesToNil() {
        XCTAssertNil(AssigneeResolver.resolve(id: nil, members: [user("u1")], taskAssignee: user("u1")))
        XCTAssertNil(AssigneeResolver.resolve(id: "", members: [], taskAssignee: nil),
                     "an empty id is unassigned, not a user whose id is empty string")
    }

    /// The identity the view keys its avatar on has to CHANGE when the assignee changes, or
    /// SwiftUI reuses the previous image view and the photo appears stuck.
    func testAvatarIdentityChangesWithTheAssignee() {
        XCTAssertNotEqual(AssigneeResolver.avatarIdentity(for: "u1"),
                          AssigneeResolver.avatarIdentity(for: "u2"))
        XCTAssertEqual(AssigneeResolver.avatarIdentity(for: "u1"),
                       AssigneeResolver.avatarIdentity(for: "u1"))
        XCTAssertNotEqual(AssigneeResolver.avatarIdentity(for: nil),
                          AssigneeResolver.avatarIdentity(for: "u1"))
    }
}
