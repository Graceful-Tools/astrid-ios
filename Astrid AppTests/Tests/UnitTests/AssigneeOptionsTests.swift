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

    func testTask8ffe30ceScopedSearchUsersFillOptionsBeforeListsLoad() {
        let teammate = user("dana", "Dana")

        let options = AssigneeOptions.build(
            availableLists: [TaskList(id: "project-list", name: "Project")],
            taskListIds: ["project-list", "status-doing"],
            discoveredUsers: [teammate],
            aiAgents: [],
            currentUser: user("me", "Jon"))

        XCTAssertTrue(options.contains { $0.id == teammate.id },
                      "the board discarded members returned by its scoped assignee search")
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

    // MARK: - AITD-401: the order is a contract with the web, not a preference

    /// astrid-web `components/priority-assignee-picker.tsx` says it outright:
    /// "Sort users: AI agents first, then current user, then alphabetically".
    /// This is the whole rule in one assertion, so a change here is a change to three platforms.
    func testAITD401_TheOrderIsAgentsThenYouThenEveryoneAlphabetically() {
        let me = user("me", "Zoe")
        let options = AssigneeOptions.build(
            roster: [user("u-adam", "Adam"), me, user("u-bea", "Bea")],
            aiAgents: [user("agent-codex", "Codex", agent: true),
                       user("agent-claude", "Claude", agent: true)],
            currentUser: me)

        XCTAssertEqual(options.map(\.id),
                       ["agent-claude", "agent-codex", "me", "u-adam", "u-bea"],
                       "AITD-401: agents (alphabetical) → you → everyone else (alphabetical)")
    }

    /// Two people with the same display name must not swap places between launches — the option
    /// list is built from a dictionary, whose iteration order is not stable.
    func testAITD401_TheOrderIsStableWhenTwoPeopleShareAName() {
        let options = AssigneeOptions.build(
            roster: [user("u-zzz", "Sam"), user("u-aaa", "Sam")],
            aiAgents: [], currentUser: nil)
        XCTAssertEqual(options.map(\.id), ["u-aaa", "u-zzz"], "id breaks the tie")
    }

    /// The same person can arrive twice — a member row the server never hydrated, and the same
    /// id again with a real name. Taking whichever came last would put a bare id where a name
    /// belongs.
    func testAITD401_AHydratedRecordBeatsABareOneWhicheverArrivesFirst() {
        let bare = User(id: "u1", email: nil, name: nil, image: nil)
        let full = user("u1", "Henry Tsai")

        for roster in [[bare, full], [full, bare]] {
            let options = AssigneeOptions.build(roster: roster, aiAgents: [], currentUser: nil)
            XCTAssertEqual(options.count, 1)
            XCTAssertEqual(options.first?.name, "Henry Tsai",
                           "AITD-401: the record with a name wins regardless of arrival order")
        }
    }

    /// The list-deriving overload must produce exactly what the core does — it is a convenience
    /// over the same rule, not a second rule.
    func testAITD401_TheListOverloadAgreesWithTheCore() {
        let me = user("me", "Zoe")
        let adam = user("u-adam", "Adam")
        let agent = user("agent-claude", "Claude", agent: true)
        let l = list("l1", owner: adam, members: [me])

        let viaLists = AssigneeOptions.build(availableLists: [l], taskListIds: ["l1"],
                                             aiAgents: [agent], currentUser: me)
        let viaCore = AssigneeOptions.build(roster: [adam, me], aiAgents: [agent], currentUser: me)
        XCTAssertEqual(viaLists.map(\.id), viaCore.map(\.id))
    }
}
