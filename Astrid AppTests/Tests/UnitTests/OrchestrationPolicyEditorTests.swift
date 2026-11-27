//  OrchestrationPolicyEditorTests.swift
//  ADEV-333 (web AWTD-1693 `OrchestrationPolicySection`): the agent policy editor on iOS and Mac.
//  The override edits follow web's `with*` helpers; what a field inherits is the core's answer.

import AstridCore
import XCTest
@testable import Astrid_App

final class OrchestrationPolicyEditorTests: XCTestCase {

    private func json(_ document: PolicyDocument?) throws -> JSONValue {
        guard let document else { return .null }
        return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(document))
    }

    private func doc(_ text: String) throws -> PolicyDocument {
        try JSONDecoder().decode(PolicyDocument.self, from: Data(text.utf8))
    }

    // MARK: - Autonomy

    func testADEV333_settingAnActionWritesIt_andInheritingRemovesTheGroup() throws {
        let set = PolicyDocument().withAutonomy(.merge, .allowed)
        XCTAssertEqual(try json(set), .object(["autonomy": .object(["merge": .string("allowed")])]))
        XCTAssertEqual(set?.autonomy(.merge), .allowed)
        XCTAssertNil(set?.autonomy(.deploy))
        // Back to inherit: nothing left, so nothing stored.
        XCTAssertNil(set?.withAutonomy(.merge, nil))
    }

    func testADEV333_migrationsLiveUnderMigrate() throws {
        let set = PolicyDocument().withAutonomy(.migrateDestructive, .ask)?.withAutonomy(.promoteIdea, .never)
        XCTAssertEqual(try json(set), .object(["autonomy": .object([
            "migrate": .object(["destructive": .string("ask")]),
            "promoteIdea": .string("never"),
        ])]))
        let cleared = set?.withAutonomy(.migrateDestructive, nil)
        XCTAssertEqual(try json(cleared), .object(["autonomy": .object(["promoteIdea": .string("never")])]))
    }

    // MARK: - Routing and escalation

    /// `null` is a value — any agent — that overrides an inherited agent; only an absent key inherits.
    func testADEV333_anyAgentIsAnExplicitNull() throws {
        let any = PolicyDocument().withAssignTo(.some(nil))
        XCTAssertEqual(try json(any), .object(["routing": .object(["assignTo": .null])]))
        XCTAssertEqual(any?.assignTo, .some(nil))
        let claude = any?.withAssignTo("claude")
        XCTAssertEqual(claude?.assignTo, .some("claude"))
        XCTAssertNil(claude?.withAssignTo(nil))
        XCTAssertNil(PolicyDocument().assignTo as String??)
    }

    func testADEV333_escalationReadsAndWritesEachTarget() throws {
        XCTAssertEqual(try json(PolicyDocument().withEscalation(.taskCreator)),
                       .object(["escalation": .object(["to": .string("taskCreator")])]))
        let person = PolicyDocument().withEscalation(.people(["u1"]))
        XCTAssertEqual(person?.escalation, .people(["u1"]))
        XCTAssertEqual(try json(person), .object(["escalation": .object(["to": .string("people"), "userIds": .array([.string("u1")])])]))
        XCTAssertNil(person?.withEscalation(nil))
    }

    // MARK: - The trade-off policy

    func testADEV333_theSwitchStatesAnEmptyPolicy_andTakesItAway() throws {
        let stated = PolicyDocument().withTradeoffStated(true)
        XCTAssertEqual(try json(stated), .object(["tradeoff": .object([:])]))
        XCTAssertTrue(stated?.tradeoffStated ?? false)
        XCTAssertNil(stated?.withTradeoffStated(false))
    }

    /// Setting a threshold states a policy; clearing the last leaves `{}`, which still states one.
    func testADEV333_thresholdsLiveInTheirGroups_andClearingTheLastKeepsThePolicy() throws {
        let set = PolicyDocument().withLevel(.riskReviewAt, .low)?.withProbability(.guardrailRefuse, 0.25)
        XCTAssertEqual(try json(set), .object(["tradeoff": .object([
            "risk": .object(["reviewAt": .string("low")]),
            "guardrail": .object(["refuseAtBreachProbability": .number(0.25)]),
        ])]))
        XCTAssertEqual(set?.level(.riskReviewAt), .low)
        XCTAssertEqual(set?.probability(.guardrailRefuse), 0.25)
        let cleared = set?.withLevel(.riskReviewAt, nil)?.withProbability(.guardrailRefuse, nil)
        XCTAssertEqual(try json(cleared), .object(["tradeoff": .object([:])]))
        XCTAssertEqual(try json(PolicyDocument().withLevel(.minConfidenceToAct, .high)),
                       .object(["tradeoff": .object(["minConfidenceToAct": .string("high")])]))
        XCTAssertEqual(try json(PolicyDocument().withLevel(.experimentRiskAtLeast, .medium)),
                       .object(["tradeoff": .object(["experimentFirst": .object(["riskAtLeast": .string("medium")])])]))
    }

    func testADEV333_goalOrder() throws {
        let ordered = PolicyDocument().withGoalOrder(["g2", "g1"])
        XCTAssertEqual(ordered?.goalOrder, ["g2", "g1"])
        XCTAssertEqual(try json(ordered?.withGoalOrder(nil)), .object(["tradeoff": .object([:])]))
    }

    /// Editing one field keeps everything else the override says.
    func testADEV333_anEditKeepsTheRest() throws {
        let stored = try doc(#"{ "routing": { "assignTo": "claude" }, "autonomy": { "deploy": "ask" }, "escalation": { "to": "listOwner" } }"#)
        let next = stored.withAutonomy(.merge, .never)
        XCTAssertEqual(next?.assignTo, .some("claude"))
        XCTAssertEqual(next?.autonomy(.deploy), .ask)
        XCTAssertEqual(next?.autonomy(.merge), .never)
        XCTAssertEqual(next?.escalation, .listOwner)
    }

    // MARK: - The write body

    func testADEV333_clearingSendsAnExplicitNull() throws {
        let cleared = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(OrchestrationPolicyWrite(policy: nil)))
        XCTAssertEqual(cleared, .object(["policy": .null]))
        let set = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(
            OrchestrationPolicyWrite(policy: PolicyDocument().withAutonomy(.spend, .ask))))
        XCTAssertEqual(set, .object(["policy": .object(["autonomy": .object(["spend": .string("ask")])])]))
    }

    // MARK: - The view

    private let viewJSON = #"""
    { "listId": "l1", "projectId": "p1",
      "list": { "autonomy": { "merge": "allowed" } },
      "project": null,
      "effective": { "routing": { "assignTo": null, "agents": null },
                     "autonomy": { "merge": "allowed", "deploy": "never", "migrate": { "additive": "never", "destructive": "never" },
                                   "release": "never", "spend": "never", "promoteIdea": "never", "experimentStart": "never", "experimentStop": "never" },
                     "escalation": { "to": "listOwner" } },
      "engine": "core",
      "canEdit": { "list": true, "project": false } }
    """#

    func testADEV333_decodesTheListView() throws {
        let view = try JSONDecoder().decode(ListOrchestrationPolicyView.self, from: Data(viewJSON.utf8))
        XCTAssertEqual(view.scopes, [.project, .list])
        XCTAssertNil(view.project)
        XCTAssertEqual(view.override(.list)?.autonomy(.merge), .allowed)
        XCTAssertEqual(view.effective.autonomy(.deploy), .never)
        XCTAssertEqual(view.effective.assignTo, .some(nil))
        XCTAssertFalse(view.effective.tradeoffStated)
        XCTAssertTrue(view.canEdit(.list))
        XCTAssertFalse(view.canEdit(.project))
        XCTAssertTrue(view.editsAnything)
    }

    // MARK: - What a field inherits (the core)

    func testADEV333_theCoreResolvesTheDefault() throws {
        let resolved = try XCTUnwrap(OrchestrationPolicyRules.resolve(project: nil, list: nil))
        for field in PolicyAutonomyField.allCases {
            XCTAssertEqual(resolved.autonomy(field), .never, field.rawValue)
        }
        XCTAssertEqual(resolved.escalation, .listOwner)
        XCTAssertEqual(resolved.assignTo, .some(nil))
        XCTAssertFalse(resolved.tradeoffStated)
    }

    func testADEV333_aListInheritsTheProjectsPolicy() throws {
        let view = try JSONDecoder().decode(ListOrchestrationPolicyView.self, from: Data(viewJSON.utf8))
        var withProject = view
        withProject.project = PolicyDocument().withAutonomy(.deploy, .ask)
        XCTAssertEqual(OrchestrationPolicyRules.inherited(by: .list, in: withProject)?.autonomy(.deploy), .ask)
        // A project's unset field falls back to the default, whatever the list says.
        XCTAssertEqual(OrchestrationPolicyRules.inherited(by: .project, in: withProject)?.autonomy(.deploy), .never)
    }

    func testADEV333_aStatedPolicyTakesTheCoresDefaults() throws {
        let defaults = try XCTUnwrap(OrchestrationPolicyRules.tradeoffDefaults())
        XCTAssertTrue(defaults.tradeoffStated)
        XCTAssertEqual(defaults.level(.riskReviewAt), .medium)
        XCTAssertEqual(defaults.level(.riskRefuseAt), .high)
        XCTAssertEqual(defaults.probability(.guardrailReview), 0.1)
        XCTAssertEqual(defaults.probability(.guardrailRefuse), 0.5)
        XCTAssertEqual(defaults.level(.minConfidenceToAct), .medium)
    }

    // MARK: - The service

    /// What the fake server was asked, and what it answers; the tests run one call at a time.
    private final class FakeServer: @unchecked Sendable {
        var calls: [String] = []
        var view: ListOrchestrationPolicyView
        var listAnswer: ListOrchestrationPolicyView?
        init(view: ListOrchestrationPolicyView) { self.view = view }

        var service: OrchestrationPolicyService {
            get async {
                await OrchestrationPolicyService(calls: .init(
                    read: { id in self.calls.append("read \(id)"); return self.view },
                    putList: { id, policy in
                        self.calls.append("list \(id) \(policy?.autonomy(.merge)?.rawValue ?? "null")")
                        return self.listAnswer ?? self.view
                    },
                    putProject: { id, policy in self.calls.append("project \(id) \(policy == nil ? "null" : "set")") }))
            }
        }
    }

    @MainActor
    func testADEV333_aListWriteStoresWhatTheServerAnswers() async throws {
        let view = try JSONDecoder().decode(ListOrchestrationPolicyView.self, from: Data(viewJSON.utf8))
        let server = FakeServer(view: view)
        var answered = view
        answered.list = PolicyDocument().withAutonomy(.merge, .ask)
        server.listAnswer = answered
        let service = await server.service
        await service.load(listId: "l1")
        let ok = await service.save(listId: "l1", scope: .list, policy: PolicyDocument().withAutonomy(.merge, .ask))
        XCTAssertTrue(ok)
        XCTAssertEqual(server.calls, ["read l1", "list l1 ask"])
        XCTAssertEqual(service.view(listId: "l1")?.list?.autonomy(.merge), .ask)
    }

    @MainActor
    func testADEV333_aProjectWriteReadsTheListAgain_andIsRefusedWithoutTheRight() async throws {
        let server = FakeServer(view: try JSONDecoder().decode(ListOrchestrationPolicyView.self, from: Data(viewJSON.utf8)))
        let service = await server.service
        await service.load(listId: "l1")
        // canEdit.project is false: nothing is sent.
        let refused = await service.save(listId: "l1", scope: .project, policy: nil)
        XCTAssertFalse(refused)
        XCTAssertEqual(server.calls, ["read l1"])

        server.view.canEdit.project = true
        await service.load(listId: "l1")
        let ok = await service.save(listId: "l1", scope: .project, policy: nil)
        XCTAssertTrue(ok)
        XCTAssertEqual(server.calls, ["read l1", "read l1", "project p1 null", "read l1"])
    }
}
