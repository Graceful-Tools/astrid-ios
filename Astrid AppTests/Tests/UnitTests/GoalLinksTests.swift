//  GoalLinksTests.swift
//  ADEV-328 (core astrid-core#139; web ADEV-276 `GoalChips`): linking and unlinking goals on a task
//  and a list. The chips sort the links as web does; the writes go through the core and the server's
//  answer replaces what is held.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class GoalLinksTests: XCTestCase {

    private func link(_ goal: String, via: String = "task", project: String = "p1", statement: String? = nil) -> GoalLink {
        GoalLink(projectId: project, projectName: nil, goalId: goal, statement: statement ?? "Goal \(goal)",
                 via: via, listId: via == "list" ? "l1" : nil, source: "person")
    }

    private let goals = [
        ProjectGoal(id: "g1", statement: "Grow signups"),
        ProjectGoal(id: "g2", statement: "Keep churn low"),
        ProjectGoal(id: "g3", statement: "Ship faster"),
        ProjectGoal(id: nil, statement: "Not saved yet"),
    ]

    // MARK: - The chips

    func testADEV328_aTasksOwnLinksAreRemovable_itsListsAreInherited_theRestCanBeAdded() {
        let model = GoalChipsModel(links: [link("g1"), link("g2", via: "list"), link("g9", project: "other")],
                                   goals: goals, projectId: "p1", isList: false, canEdit: true)
        XCTAssertEqual(model.own.map(\.goalId), ["g1"])
        XCTAssertEqual(model.own.first?.statement, "Grow signups", "the project's current wording")
        XCTAssertEqual(model.inherited.map(\.goalId), ["g2"])
        XCTAssertEqual(model.addable.map(\.goalId), ["g3"], "neither linked goal, nor an unsaved one")
        XCTAssertEqual(model.ownIds(adding: "g3"), ["g1", "g3"])
        XCTAssertFalse(model.isEmpty)
    }

    func testADEV328_aListsLinksAreAllItsOwn() {
        let model = GoalChipsModel(links: [link("g2", via: "list")], goals: goals, projectId: "p1", isList: true, canEdit: true)
        XCTAssertEqual(model.own.map(\.goalId), ["g2"])
        XCTAssertTrue(model.inherited.isEmpty)
    }

    func testADEV328_withoutWriteAccessOnlyLinksDraw() {
        let none = GoalChipsModel(links: [], goals: goals, projectId: "p1", isList: false, canEdit: false)
        XCTAssertTrue(none.isEmpty, "nothing linked and nothing this person may add")
        let editable = GoalChipsModel(links: [], goals: goals, projectId: "p1", isList: false, canEdit: true)
        XCTAssertFalse(editable.isEmpty, "the Add menu")
        let linked = GoalChipsModel(links: [link("g1")], goals: goals, projectId: "p1", isList: false, canEdit: false)
        XCTAssertFalse(linked.isEmpty)
    }

    // MARK: - The writes

    private final class FakeCore {
        var calls: [String] = []
        var taskAnswer = TaskGoalLinks(taskId: "t1", links: [])
        var listAnswer = ListGoalLinks(listId: "l1", projectId: "p1", links: [])
        var fails = false

        var writes: GoalLinkWrites {
            GoalLinkWrites(
                setTask: { id, goalIds, project in
                    self.calls.append("setTask \(id) \(goalIds) \(project ?? "-")")
                    if self.fails { throw URLError(.notConnectedToInternet) }
                    return self.taskAnswer
                },
                unlinkTask: { id, goalId, project in
                    self.calls.append("unlinkTask \(id) \(goalId) \(project ?? "-")")
                    if self.fails { throw URLError(.notConnectedToInternet) }
                    return self.taskAnswer
                },
                readList: { id in
                    self.calls.append("readList \(id)")
                    return self.listAnswer
                },
                setList: { id, goalIds in
                    self.calls.append("setList \(id) \(goalIds)")
                    return self.listAnswer
                },
                unlinkList: { id, goalId in
                    self.calls.append("unlinkList \(id) \(goalId)")
                    return self.listAnswer
                })
        }
    }

    private func service(_ core: FakeCore, links: [GoalLink]) async -> GoalSignalsService {
        let held = TaskGoalLinks(taskId: "t1", links: links)
        let service = GoalSignalsService(readLinks: { _ in held },
                                         readEstimate: { _ in throw URLError(.badServerResponse) },
                                         readExperiment: { _ in throw URLError(.badServerResponse) },
                                         goalLinkWrites: core.writes)
        await service.load(taskId: "t1")
        return service
    }

    func testADEV328_linkingSendsTheOwnLinksPlusOne_andHoldsTheAnswer() async {
        let core = FakeCore()
        let service = await service(core, links: [link("g1"), link("g2", via: "list"), link("g9", project: "other")])
        core.taskAnswer = TaskGoalLinks(taskId: "t1", links: [link("g1"), link("g3"), link("g2", via: "list")])

        let ok = await service.linkGoal(taskId: "t1", goalId: "g3", projectId: "p1")
        XCTAssertTrue(ok)
        // Only this project's own links: an inherited one is the list's, another project's is not touched.
        XCTAssertEqual(core.calls, [#"setTask t1 ["g1", "g3"] p1"#])
        XCTAssertEqual(service.signals(taskId: "t1")?.links?.links.map(\.goalId), ["g1", "g3", "g2"])

        // Already linked: nothing to send.
        _ = await service.linkGoal(taskId: "t1", goalId: "g1", projectId: "p1")
        XCTAssertEqual(core.calls.count, 1)
    }

    func testADEV328_unlinkingHoldsTheAnswer_andAFailureKeepsWhatWasThere() async {
        let core = FakeCore()
        let service = await service(core, links: [link("g1"), link("g2")])
        core.taskAnswer = TaskGoalLinks(taskId: "t1", links: [link("g2")])
        let ok = await service.unlinkGoal(taskId: "t1", goalId: "g1", projectId: "p1")
        XCTAssertTrue(ok)
        XCTAssertEqual(core.calls, ["unlinkTask t1 g1 p1"])
        XCTAssertEqual(service.signals(taskId: "t1")?.links?.links.map(\.goalId), ["g2"])

        core.fails = true
        let failed = await service.unlinkGoal(taskId: "t1", goalId: "g2", projectId: "p1")
        XCTAssertFalse(failed, "offline or refused: not journalled, it fails")
        XCTAssertEqual(service.signals(taskId: "t1")?.links?.links.map(\.goalId), ["g2"])
    }

    func testADEV328_aListsLinksAreReadLinkedAndUnlinked() async {
        let core = FakeCore()
        let service = await service(core, links: [])
        core.listAnswer = ListGoalLinks(listId: "l1", projectId: "p1", links: [link("g1", via: "list")])
        await service.loadList(listId: "l1")
        XCTAssertEqual(service.listLinks(listId: "l1")?.links.map(\.goalId), ["g1"])

        core.listAnswer = ListGoalLinks(listId: "l1", projectId: "p1", links: [link("g1", via: "list"), link("g2", via: "list")])
        let linked = await service.linkListGoal(listId: "l1", goalId: "g2")
        XCTAssertTrue(linked)
        core.listAnswer = ListGoalLinks(listId: "l1", projectId: "p1", links: [link("g2", via: "list")])
        let unlinked = await service.unlinkListGoal(listId: "l1", goalId: "g1")
        XCTAssertTrue(unlinked)
        XCTAssertEqual(core.calls, ["readList l1", #"setList l1 ["g1", "g2"]"#, "unlinkList l1 g1"])
        XCTAssertEqual(service.listLinks(listId: "l1")?.links.map(\.goalId), ["g2"])
    }

    func testADEV328_aListInNoProjectDecodesWithNoProject() throws {
        let decoded = try JSONDecoder().decode(ListGoalLinks.self, from: Data(#"{ "listId": "l2", "projectId": null, "links": [] }"#.utf8))
        XCTAssertNil(decoded.projectId)
        XCTAssertTrue(decoded.links.isEmpty)
    }
}
