//  ListRosterCacheTests.swift
//  Regression guard for AITD-413 — "[iOS] Cannot assign tasks when offline".
//
//  A list rehydrated from CoreData used to come back with no `owner` and no `listMembers`,
//  because `CDTaskList` never persisted either. `AssigneeOptions` builds the assignee picker's
//  roster from exactly those two fields, so after an offline cold launch the picker had nobody
//  in it. This is the store that keeps them.

import XCTest
@testable import Astrid_App

final class ListRosterCacheTests: XCTestCase {

    private func user(_ id: String, _ name: String) -> User {
        User(id: id, email: "\(id)@astrid.cc", name: name, image: nil)
    }

    private func member(_ user: User, listId: String = "list-1") -> ListMember {
        ListMember(id: "lm-\(user.id)", listId: listId, userId: user.id, role: "MEMBER", user: user)
    }

    // MARK: - THE BUG

    /// The whole point: who the list knows survives a relaunch, with names intact — an id alone
    /// would put a bare uuid where a person's name belongs in the picker.
    func testOwnerAndMembersSurviveARoundTrip() {
        let owner = user("jon", "Jon")
        let dana = user("dana", "Dana")

        let restored = ListRosterCache.decode(
            ListRosterCache.encode(owner: owner, members: [member(dana)]))

        XCTAssertEqual(restored.owner?.id, "jon")
        XCTAssertEqual(restored.owner?.name, "Jon")
        XCTAssertEqual(restored.members?.map(\.userId), ["dana"])
        XCTAssertEqual(restored.members?.first?.user?.name, "Dana",
                       "the hydrated user is the part the picker needs — a userId cannot be shown")
    }

    /// nil means "leave what you had". A list can reach the cache unhydrated — an optimistic
    /// local create, or a minimal API response — and letting that overwrite a good roster would
    /// bring the empty picker straight back on the next launch.
    func testAListWithNoPeopleEncodesToNothingRatherThanAnEmptyRoster() {
        XCTAssertNil(ListRosterCache.encode(owner: nil, members: nil))
        XCTAssertNil(ListRosterCache.encode(owner: nil, members: []))
    }

    /// An owner with no members is still worth keeping: a private list is exactly that shape,
    /// and its owner is the one person you most want to be able to assign to offline.
    func testAnOwnerAloneIsWorthRemembering() {
        let restored = ListRosterCache.decode(
            ListRosterCache.encode(owner: user("jon", "Jon"), members: nil))

        XCTAssertEqual(restored.owner?.id, "jon")
        XCTAssertNil(restored.members)
    }

    func testGarbageDecodesToAnEmptyRosterRatherThanThrowing() {
        XCTAssertNil(ListRosterCache.decode("not json").owner)
        XCTAssertNil(ListRosterCache.decode(nil).members)
    }
}
