//  ProjectGoalsTests.swift
//  ADEV-183 (web ADEV-179): a project's goals and guardrails, read from and saved to
//  `/api/v1/projects/{id}/goals`. The server does all normalising; these pin what the app reads,
//  what it shows, and what it sends.

import XCTest
@testable import Astrid_App

@MainActor
final class ProjectGoalsTests: XCTestCase {

    private let contractExample = """
    {
      "projectId": "p1", "projectName": "Fund",
      "goals": [{ "id": "returns", "statement": "Maximise long-term returns", "measure": "IRR", "target": "≥ 8%/yr", "current": "6.1%" }],
      "guardrails": [
        { "id": "law", "statement": "Break no applicable laws", "kind": "stated" },
        { "id": "r1", "statement": "No more than 20% in one position", "kind": "enforced" }
      ],
      "canEdit": true,
      "meta": { "apiVersion": "v1" }
    }
    """

    func testADEV183_decodesTheContractExample() throws {
        let goals = try JSONDecoder().decode(ProjectGoals.self, from: Data(contractExample.utf8))
        XCTAssertEqual(goals.projectId, "p1")
        XCTAssertEqual(goals.goals.first?.measure, "IRR")
        XCTAssertEqual(goals.goals.first?.target, "≥ 8%/yr")
        XCTAssertEqual(goals.goals.first?.current, "6.1%")
        XCTAssertEqual(goals.guardrails.map(\.kind), [.stated, .enforced])
        XCTAssertTrue(goals.canEdit)
        XCTAssertFalse(goals.isEmpty)
    }

    /// A list in no project answers nulls and empty lists; an unknown kind reads as stated.
    func testADEV183_aListInNoProjectIsEmpty() throws {
        let json = #"{"projectId":null,"projectName":null,"listId":"l1","goals":[],"guardrails":[{"id":"r9","statement":"x","kind":"audited"}],"canEdit":false}"#
        let goals = try JSONDecoder().decode(ProjectGoals.self, from: Data(json.utf8))
        XCTAssertNil(goals.projectId)
        XCTAssertEqual(goals.guardrails.first?.kind, .stated)
        let none = try JSONDecoder().decode(ProjectGoals.self, from: Data(#"{"goals":[],"guardrails":[]}"#.utf8))
        XCTAssertTrue(none.isEmpty)
        XCTAssertFalse(none.canEdit)
    }

    // MARK: ADEV-365 — the editor Jon described: labeled fields, a target date, no separate
    // "Measure with a metric" step, numbered cards.

    func testADEV365_targetDateIsADayAndClearingItLeavesItOut() throws {
        var goal = try JSONDecoder().decode(ProjectGoal.self,
                                            from: Data(#"{"id":"g1","statement":"MAU","targetDate":"2027-12-15"}"#.utf8))
        let day = try XCTUnwrap(goal.targetDate)
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: day),
                       DateComponents(year: 2027, month: 12, day: 15))

        goal.targetDate = Calendar.current.date(from: DateComponents(year: 2028, month: 1, day: 2, hour: 23))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(goal)) as? [String: Any])
        XCTAssertEqual(json["targetDate"] as? String, "2028-01-02", "the local day, whatever the hour")

        goal.targetDate = nil
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(goal)) as? [String: Any])
        XCTAssertNil(json["targetDate"])
    }

    func testADEV365_aNumberTargetFeedsTheMetric_proseStaysProse() {
        var goal = ProjectGoal(id: "g1", statement: "Grow MAU")
        goal.setTarget("1000")
        XCTAssertEqual(goal.target, "1000")
        XCTAssertTrue(goal.hasMetric)
        XCTAssertEqual(goal.metricTarget, 1000)

        goal.setTarget("≥ 8%/yr")
        XCTAssertEqual(goal.target, "≥ 8%/yr", "a target in words is kept as written")
        XCTAssertNil(goal.metricTarget)

        var prose = ProjectGoal(id: "g2", statement: "Be kind")
        prose.setTarget("most days")
        XCTAssertFalse(prose.hasMetric, "words alone never start a metric")
    }

    func testADEV365_choosingWhichWayIsBetterStartsTheMetric() {
        var goal = ProjectGoal(id: "g1", statement: "Spend less")
        XCTAssertFalse(goal.hasMetric)
        goal.betterWhen = .down
        XCTAssertTrue(goal.hasMetric)
        XCTAssertEqual(goal.metricDirection, .down)
        goal.unit = "USD"
        XCTAssertEqual(goal.metricUnit, "USD")
    }

    func testADEV365_cardsAreNumberedFromOne() {
        XCTAssertEqual(ProjectGoalsEditorText.goalTitle(0), "Goal 1")
        XCTAssertEqual(ProjectGoalsEditorText.guardrailTitle(1), "Guardrail 2")
    }

    /// PUT sends the whole value; a new row carries no id (the server assigns g1/r1), and an
    /// empty optional field is left out rather than sent as "".
    func testADEV183_putBodyOmitsNewIdsAndEmptyFields() throws {
        let body = ProjectGoalsUpdate(
            goals: [ProjectGoal(id: nil, statement: "Grow", measure: "", target: "10", current: nil)],
            guardrails: [ProjectGuardrail(id: "law", statement: "Legal", kind: .enforced)])
        let data = try JSONEncoder().encode(body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let goal = try XCTUnwrap((object["goals"] as? [[String: Any]])?.first)
        XCTAssertNil(goal["id"])
        XCTAssertNil(goal["measure"])
        XCTAssertNil(goal["current"])
        XCTAssertEqual(goal["statement"] as? String, "Grow")
        XCTAssertEqual(goal["target"] as? String, "10")
        let guardrail = try XCTUnwrap((object["guardrails"] as? [[String: Any]])?.first)
        XCTAssertEqual(guardrail["id"] as? String, "law")
        XCTAssertEqual(guardrail["kind"] as? String, "enforced")
    }

    func testADEV183_serviceLoadsAndSaves() async throws {
        let stored = try JSONDecoder().decode(ProjectGoals.self, from: Data(contractExample.utf8))
        var sent: ProjectGoalsUpdate?
        let service = ProjectGoalsService(
            fetch: { _ in stored },
            save: { _, update in
                sent = update
                return ProjectGoals(projectId: "p1", goals: update.goals, guardrails: update.guardrails,
                                    canEdit: true)
            })
        XCTAssertNil(service.goals(projectId: "p1"))
        await service.load(projectId: "p1")
        XCTAssertEqual(service.goals(projectId: "p1"), stored)

        let ok = await service.save(projectId: "p1",
                                    ProjectGoalsUpdate(goals: [], guardrails: stored.guardrails))
        XCTAssertTrue(ok)
        XCTAssertEqual(sent?.guardrails.count, 2)
        XCTAssertEqual(service.goals(projectId: "p1")?.goals, [])
    }

    /// A refused save keeps what was there and says so.
    func testADEV183_aFailedSaveKeepsThePreviousGoals() async throws {
        let stored = try JSONDecoder().decode(ProjectGoals.self, from: Data(contractExample.utf8))
        struct Refused: Error {}
        let service = ProjectGoalsService(fetch: { _ in stored }, save: { _, _ in throw Refused() })
        await service.load(projectId: "p1")
        let ok = await service.save(projectId: "p1", ProjectGoalsUpdate(goals: [], guardrails: []))
        XCTAssertFalse(ok)
        XCTAssertEqual(service.goals(projectId: "p1"), stored)
    }
}

/// ADEV-183 (web ADEV-178): the trade-off extremes read Decisive / Disqualifying.
final class TradeoffRatingWordsTests: XCTestCase {
    func testADEV183_extremesReadDecisiveAndDisqualifying() {
        let bundle = Bundle(for: ProjectGoalsService.self)
        let path = try? XCTUnwrap(bundle.path(forResource: "en", ofType: "lproj"))
        let en = path.flatMap(Bundle.init(path:)) ?? bundle
        XCTAssertEqual(en.localizedString(forKey: "tradeoff.very_good", value: nil, table: nil), "Decisive")
        XCTAssertEqual(en.localizedString(forKey: "tradeoff.very_poor", value: nil, table: nil), "Disqualifying")
    }
}

/// ADEV-319: a save keeps what this build does not model.
final class ProjectGoalsPassThroughTests: XCTestCase {

    /// Web shapes this app does not edit: an enforced guardrail's `check` (ADEV-182/277), a goal's
    /// `metric` and `history` (ADEV-270), and whatever comes next.
    private let signalsExample = """
    {
      "projectId": "p1",
      "goals": [{ "id": "g1", "statement": "Grow", "current": "5",
                  "metric": { "direction": "up", "unit": "users", "target": 100, "source": { "connectorId": "c1", "metricKey": "dau" } },
                  "history": [{ "value": "4", "by": "u1", "at": "2026-11-20T00:00:00Z" }],
                  "futureGoalField": { "x": [1, true, null] } }],
      "guardrails": [
        { "id": "r1", "statement": "Agents never merge alone", "kind": "enforced",
          "check": { "type": "policy", "field": "merge", "atLeast": "ask" } },
        { "id": "r2", "statement": "Error rate", "kind": "enforced",
          "check": { "type": "metric", "source": { "connectorId": "c1", "metricKey": "err" }, "op": "<=", "threshold": 0.5 } }
      ],
      "canEdit": true
    }
    """

    private func putBody(after edit: (inout ProjectGoals) -> Void) throws -> [String: Any] {
        var goals = try JSONDecoder().decode(ProjectGoals.self, from: Data(signalsExample.utf8))
        edit(&goals)
        let data = try JSONEncoder().encode(ProjectGoalsUpdate(goals: goals.goals, guardrails: goals.guardrails))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The bug: editing a goal on iOS/Mac and saving PUT the guardrails without their checks, and
    /// the server (which keeps an omitted metric but not an omitted check) dropped them, unblocking
    /// what the guardrail blocked.
    func testADEV319_savingKeepsEnforcedGuardrailChecks() throws {
        let body = try putBody { $0.goals[0].statement = "Grow faster" }
        let rails = try XCTUnwrap(body["guardrails"] as? [[String: Any]])
        let policy = try XCTUnwrap(rails[0]["check"] as? [String: Any])
        XCTAssertEqual(policy["type"] as? String, "policy")
        XCTAssertEqual(policy["field"] as? String, "merge")
        XCTAssertEqual(policy["atLeast"] as? String, "ask")
        let metric = try XCTUnwrap(rails[1]["check"] as? [String: Any])
        XCTAssertEqual(metric["op"] as? String, "<=")
        XCTAssertEqual(metric["threshold"] as? Double, 0.5)
        XCTAssertEqual((metric["source"] as? [String: Any])?["metricKey"] as? String, "err")
    }

    /// A goal's metric and any field a later web adds go back as they came.
    func testADEV319_savingKeepsGoalFieldsThisBuildDoesNotModel() throws {
        let body = try putBody { $0.goals[0].target = "200" }
        let goal = try XCTUnwrap((body["goals"] as? [[String: Any]])?.first)
        XCTAssertEqual(goal["target"] as? String, "200")
        let metric = try XCTUnwrap(goal["metric"] as? [String: Any])
        XCTAssertEqual(metric["direction"] as? String, "up")
        XCTAssertEqual(metric["target"] as? Int, 100)
        XCTAssertNotNil(goal["futureGoalField"])
        XCTAssertNotNil(goal["history"])
    }

    /// The server refuses a check on a stated guardrail (400), so turning one to stated drops it.
    func testADEV319_aGuardrailMadeStatedSendsNoCheck() throws {
        let body = try putBody { $0.guardrails[0].kind = .stated }
        let rails = try XCTUnwrap(body["guardrails"] as? [[String: Any]])
        XCTAssertEqual(rails[0]["kind"] as? String, "stated")
        XCTAssertNil(rails[0]["check"])
        XCTAssertNotNil(rails[1]["check"])
    }
}
