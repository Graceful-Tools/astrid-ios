//  AssigneeOptionsTests.swift
//  Regression guard for Task 1484ea4a — "iOS Quick assignment picker on board view doesn't list
//  ai agents. It should make sure you reuse the same assignment as in task details and list
//  view. Code reuse please."
//
//  The three surfaces all render `InlineAssigneePicker`, but the picker built its option list
//  inline in a computed property, so "who can this be assigned to" was a view detail rather than
//  a rule — untestable, and free to behave differently depending on what the surrounding screen
//  happened to have loaded. The board is the surface that shows it, because it is the one you
//  can reach without another picker having populated the agent cache first.
//
//  The Mac already states this as data (`MacAssigneeOptions.build`). This is iOS getting the
//  same treatment so the two platforms, and the three iOS surfaces, cannot drift.

import XCTest
@testable import Astrid_App

final class AssigneeOptionsTests: XCTestCase {

    private func user(_ id: String, _ name: String, agent: Bool = false) -> User {
        var u = User(id: id, email: "\(id)@astrid.cc", name: name, image: nil)
        u.isAIAgent = agent
        return u
    }

    private func list(_ id: String, owner: User?, members: [User]) -> TaskList {
        var l = TaskList(id: id, name: "List \(id)")
        l.owner = owner
        l.listMembers = members.map { ListMember(id: "lm-\($0.id)", listId: id, userId: $0.id, role: "MEMBER", user: $0) }
        return l
    }

    // MARK: - THE BUG

    /// Agents belong in the list even when the task's lists resolve to nothing — which is the
    /// board's case: its cards carry a project list plus a status list, and neither has to be
    /// present in whatever `availableLists` the surface handed over.
    func testAgentsAreOfferedEvenWhenTheTasksListsAreNotLoaded() {
        let agent = user("agent-claude", "Claude", agent: true)

        let options = AssigneeOptions.build(availableLists: [],
                                            taskListIds: ["project-list", "status-doing"],
                                            aiAgents: [agent],
                                            currentUser: user("me", "Jon"))

        XCTAssertTrue(options.contains { $0.id == "agent-claude" },
                      "the board could not offer an AI agent at all — the whole task")
    }

    /// And when they ARE loaded, agents still come through alongside the members.
    func testAgentsAndMembersAreBothOffered() {
        let me = user("me", "Jon")
        let mate = user("dana", "Dana")
        let agent = user("agent-claude", "Claude", agent: true)
        let l = list("project-list", owner: me, members: [mate])

        let options = AssigneeOptions.build(availableLists: [l],
                                            taskListIds: ["project-list"],
                                            aiAgents: [agent],
                                            currentUser: me)

        XCTAssertEqual(Set(options.map(\.id)), ["me", "dana", "agent-claude"])
    }

    // MARK: - The order, which all three surfaces now share

    /// Agents first, then you, then everyone else by name. This was already the picker's rule;
    /// stating it here is what stops one surface sorting differently.
    func testAgentsComeFirstThenYouThenTheRestByName() {
        let me = user("me", "Jon")
        let options = AssigneeOptions.build(
            availableLists: [list("l", owner: me, members: [user("zoe", "Zoe"), user("amy", "Amy")])],
            taskListIds: ["l"],
            aiAgents: [user("agent-b", "Beta", agent: true), user("agent-a", "Alpha", agent: true)],
            currentUser: me)

        XCTAssertEqual(options.map(\.id), ["agent-a", "agent-b", "me", "amy", "zoe"])
    }

    /// A task with no lists at all still offers you — otherwise "My Tasks" has an empty picker.
    func testATaskWithNoListsStillOffersYou() {
        let me = user("me", "Jon")
        let options = AssigneeOptions.build(availableLists: [], taskListIds: [],
                                            aiAgents: [], currentUser: me)
        XCTAssertEqual(options.map(\.id), ["me"])
    }

    /// The same person on two of the task's lists appears once.
    func testAPersonOnTwoListsIsOfferedOnce() {
        let me = user("me", "Jon")
        let dana = user("dana", "Dana")
        let options = AssigneeOptions.build(
            availableLists: [list("a", owner: me, members: [dana]), list("b", owner: me, members: [dana])],
            taskListIds: ["a", "b"], aiAgents: [], currentUser: me)
        XCTAssertEqual(options.filter { $0.id == "dana" }.count, 1)
    }
}
