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

    /// The strip says "Goals: N · Guardrails: N" and draws nothing when both are empty.
    func testADEV183_stripCountsAndHidesWhenEmpty() throws {
        let goals = try JSONDecoder().decode(ProjectGoals.self, from: Data(contractExample.utf8))
        XCTAssertEqual(ProjectGoalsStrip.countsText(goals), "Goals: 1 · Guardrails: 2")
        XCTAssertTrue(ProjectGoalsStrip.shows(goals))
        XCTAssertFalse(ProjectGoalsStrip.shows(nil))
        XCTAssertFalse(ProjectGoalsStrip.shows(ProjectGoals(goals: [], guardrails: [])))
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
