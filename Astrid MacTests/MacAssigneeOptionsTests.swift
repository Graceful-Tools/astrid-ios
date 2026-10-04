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
//  labelled with a bare id. Since AITD-461 who is offered is astrid-core's `assigneeOptions` —
//  iOS's rule, which the Mac follows (CONTRACTS D47) — so these ask a seeded in-memory core.

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

    /// The Mac picker's rows for a task in a list holding `members`, as the core answers.
    private func options(members: [ListMember], currentUserId: String?,
                         aiAgents: [User] = []) -> [MacAssigneeOption] {
        var list = TaskList(id: "list-1", name: "List")
        list.listMembers = members
        let session = try! CoreBoardFixture.session(lists: [list], projects: [])
        let me = currentUserId.map { id in
            members.first { $0.userId == id }?.user ?? User(id: id, email: nil, name: nil, image: nil)
        }
        let question = AssigneeQuestion(listIds: ["list-1"], agents: aiAgents, currentUser: me)
        let answer = try! CoreRowsFixture.wait(session, question.command, as: AssigneeAnswer.self)
        return MacAssigneeOptions.rows(answer, currentUserId: currentUserId)
    }

    /// Unassigned is a real choice and has to be offered.
    func testUnassignedIsAlwaysOffered() {
        let rows = options(members: [], currentUserId: "me")

        XCTAssertEqual(rows.first?.userId, nil, "the first option should be 'no one'")
        XCTAssertTrue(rows.first?.isUnassigned == true)
        XCTAssertTrue(MacAssigneeOptions.rows(nil, currentUserId: "me").first?.isUnassigned == true,
                      "and before the core has answered")
    }

    /// THE BUG: every person option must carry a User, so an avatar can actually be drawn.
    func testEveryPersonOptionCarriesAUserForTheAvatar() {
        let rows = options(members: [member("u1", name: "Henry Tsai"), member("u2", name: "Jon Paris")],
                           currentUserId: "u2")

        let people = rows.filter { !$0.isUnassigned }
        XCTAssertEqual(people.count, 2)
        XCTAssertTrue(people.allSatisfy { $0.user != nil },
                      "a nil user means the row renders without a photo — the reported bug")
    }

    /// A member whose `user` never hydrated is never shown as a UUID — since AITD-461 it is not
    /// offered at all, as on iOS (D47).
    func testAnUnhydratedMemberIsNeverLabelledWithARawId() {
        let rawId = "8f14e45f-ceea-467a-9f8b-2d3c7f9a1b2c"
        let rows = options(members: [member(rawId, name: nil), member("u1", name: "Adam")],
                           currentUserId: "u1")

        XCTAssertFalse(rows.contains { $0.displayName == rawId },
                       "showing a bare UUID as someone's name is what this replaces")
        XCTAssertFalse(rows.contains { $0.userId == rawId }, "iOS leaves out a member it cannot draw")
    }

    /// You assign things to yourself constantly; you should not hunt for your own name.
    func testTheCurrentUserSortsFirstAmongPeople() {
        let rows = options(members: [member("u1", name: "Adam"), member("me", name: "Zoe"), member("u2", name: "Bea")],
                           currentUserId: "me")

        let people = rows.filter { !$0.isUnassigned }
        XCTAssertEqual(people.first?.userId, "me", "the current user leads the list")
        XCTAssertTrue(people.first?.isCurrentUser == true)
        // The rest stay alphabetical so the list is scannable.
        XCTAssertEqual(people.dropFirst().map(\.displayName), ["Adam", "Bea"])
    }

    /// Who holds the task is offered only as iOS offers them (D47): a holder from outside the
    /// list is not a choice — the trigger still shows them (`MacAssigneePicker.selected`).
    func testTheCurrentAssigneeIsNotAddedToTheChoices() {
        let rows = options(members: [member("u1", name: "Adam")], currentUserId: "u1")
        XCTAssertFalse(rows.contains { $0.userId == "outsider" })
    }

    /// No duplicates when a person is on the list twice over.
    func testAMemberWhoIsAlsoTheOwnerAppearsOnce() {
        let rows = options(members: [member("u1", name: "Adam"), member("u1", name: "Adam")], currentUserId: "me")

        XCTAssertEqual(rows.filter { $0.userId == "u1" }.count, 1)
    }

    // MARK: - AITD-401: the Mac can hand work to an agent, in the order the web states

    /// THE GAP. The Mac picker could not assign a task to an AI agent at all — the same bug task
    /// 1484ea4a fixed on the iOS board.
    func testAITD401_AnAgentCanBeAssignedFromTheMacPicker() {
        var claude = User(id: "agent-claude", email: "claude@astrid.cc", name: "Claude", image: nil)
        claude.isAIAgent = true

        let rows = options(members: [member("u1", name: "Adam")], currentUserId: "u1", aiAgents: [claude])

        XCTAssertTrue(rows.contains { $0.userId == "agent-claude" },
                      "AITD-401: an agent must be offerable on the Mac too")
    }

    /// And in the order astrid-web states — "AI agents first, then current user, then
    /// alphabetically".
    func testAITD401_AgentsSortAheadOfTheCurrentUser() {
        var claude = User(id: "agent-claude", email: "claude@astrid.cc", name: "Claude", image: nil)
        claude.isAIAgent = true

        let rows = options(members: [member("u1", name: "Adam"), member("me", name: "Zoe")],
                           currentUserId: "me", aiAgents: [claude])

        let people = rows.filter { !$0.isUnassigned }
        XCTAssertEqual(people.map(\.userId), ["agent-claude", "me", "u1"])
        XCTAssertTrue(rows.first?.isUnassigned == true, "'no one' stays the first row")
    }

    func testAITD401_WithNoAgentsTheOrderIsUnchanged() {
        let rows = options(members: [member("u1", name: "Adam"), member("me", name: "Zoe"), member("u2", name: "Bea")],
                           currentUserId: "me", aiAgents: [])

        XCTAssertEqual(rows.filter { !$0.isUnassigned }.map(\.displayName), ["Zoe", "Adam", "Bea"])
    }
}
