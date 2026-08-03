//  MacAssigneeOptionsTests.swift
//  Regression tests for the Mac task detail's Who picker.
//
//  It was a plain SwiftUI `Picker` over `Text(m.user?.displayName ?? m.userId)`. Two things
//  wrong with that, both visible on screen:
//
//  1. No avatar anywhere — not on the trigger, not on the rows. The Mac already has
//     MacAssigneeAvatar; the picker simply never used it.
//  2. When a member record has not hydrated its `user`, the fallback puts a raw UUID in
//     front of the user as if it were a name.
//
//  The option list is the part of this that is decidable rather than drawn, so it is pinned
//  here: every option must carry a User an avatar can be built from, and nobody may ever be
//  labelled with a bare id.

import XCTest
@testable import Astrid_Mac

final class MacAssigneeOptionsTests: XCTestCase {

    private func member(_ id: String, name: String?, email: String? = nil) -> ListMember {
        ListMember(id: "lm-\(id)",
                   listId: "list-1",
                   userId: id,
                   role: "member",
                   user: name == nil && email == nil ? nil : User(id: id, email: email, name: name, image: nil))
    }

    /// Unassigned is a real choice and has to be offered.
    func testUnassignedIsAlwaysOffered() {
        let options = MacAssigneeOptions.build(members: [], currentUserId: "me", taskAssignee: nil)

        XCTAssertEqual(options.first?.userId, nil, "the first option should be 'no one'")
        XCTAssertTrue(options.first?.isUnassigned == true)
    }

    /// THE BUG: every person option must carry a User, so an avatar can actually be drawn.
    func testEveryPersonOptionCarriesAUserForTheAvatar() {
        let options = MacAssigneeOptions.build(
            members: [member("u1", name: "Henry Tsai"), member("u2", name: "Jon Paris")],
            currentUserId: "u2",
            taskAssignee: nil)

        let people = options.filter { !$0.isUnassigned }
        XCTAssertEqual(people.count, 2)
        XCTAssertTrue(people.allSatisfy { $0.user != nil },
                      "a nil user means the row renders without a photo — the reported bug")
    }

    /// A member whose `user` never hydrated must still be presented as a person, not a UUID.
    func testAnUnhydratedMemberIsNeverLabelledWithARawId() throws {
        let rawId = "8f14e45f-ceea-467a-9f8b-2d3c7f9a1b2c"
        let options = MacAssigneeOptions.build(
            members: [member(rawId, name: nil)], currentUserId: "me", taskAssignee: nil)

        let person = try XCTUnwrap(options.first { !$0.isUnassigned })
        XCTAssertNotNil(person.user, "must resolve to SOME user so an avatar/initials can render")
        XCTAssertNotEqual(person.displayName, rawId,
                          "showing a bare UUID as someone's name is what this replaces")
    }

    /// You assign things to yourself constantly; you should not hunt for your own name.
    func testTheCurrentUserSortsFirstAmongPeople() {
        let options = MacAssigneeOptions.build(
            members: [member("u1", name: "Adam"), member("me", name: "Zoe"), member("u2", name: "Bea")],
            currentUserId: "me",
            taskAssignee: nil)

        let people = options.filter { !$0.isUnassigned }
        XCTAssertEqual(people.first?.userId, "me", "the current user leads the list")
        XCTAssertTrue(people.first?.isCurrentUser == true)
        // The rest stay alphabetical so the list is scannable.
        XCTAssertEqual(people.dropFirst().map(\.displayName), ["Adam", "Bea"])
    }

    /// Someone assigned from outside this list (added by email, member of another list) must
    /// still appear — otherwise the picker cannot show who the task is currently assigned to.
    func testTheCurrentAssigneeAppearsEvenIfNotAListMember() {
        let outsider = User(id: "outsider", email: "x@y.com", name: "Outside Person", image: nil)
        let options = MacAssigneeOptions.build(
            members: [member("u1", name: "Adam")], currentUserId: "me", taskAssignee: outsider)

        XCTAssertTrue(options.contains { $0.userId == "outsider" },
                      "the person the task is assigned to must be in the list they are shown in")
    }

    /// No duplicates when the assignee IS a member — otherwise they show up twice.
    func testAMemberWhoIsAlsoTheAssigneeAppearsOnce() {
        let adam = User(id: "u1", email: nil, name: "Adam", image: nil)
        let options = MacAssigneeOptions.build(
            members: [member("u1", name: "Adam")], currentUserId: "me", taskAssignee: adam)

        XCTAssertEqual(options.filter { $0.userId == "u1" }.count, 1)
    }
}
