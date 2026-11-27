//  ProjectGoalMetricEditorTests.swift
//  ADEV-331 (web ADEV-270/277): the goals editor's metric block and an enforced guardrail's metric
//  check. Until now the editor passed `metric` and `check` through untouched (ADEV-319); these
//  make them editable while still carrying the keys the server writes (`current`, `measuredAt`).

import AstridCore
import XCTest
@testable import Astrid_App

final class ProjectGoalMetricEditorTests: XCTestCase {

    private func encoded<T: Encodable>(_ value: T) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(value))
    }

    // MARK: - The goal's metric block

    func testADEV331_addingAMetricStartsItPointingUp() throws {
        var goal = ProjectGoal(id: "g1", statement: "Grow signups")
        XCTAssertFalse(goal.hasMetric)
        goal.addMetric()
        XCTAssertTrue(goal.hasMetric)
        XCTAssertEqual(goal.metricDirection, .up)
        XCTAssertEqual(try encoded(goal)["metric"], .object(["direction": .string("up")]))
    }

    func testADEV331_editingTheMetricKeepsWhatTheServerWrote() throws {
        let json = #"{ "id": "g1", "statement": "Grow", "metric": { "direction": "up", "target": 12, "current": 9, "measuredAt": "2026-11-26T00:00:00Z", "source": { "connectorId": "c1", "metricKey": "signups" } } }"#
        var goal = try JSONDecoder().decode(ProjectGoal.self, from: Data(json.utf8))
        XCTAssertEqual(goal.metricTarget, 12)
        XCTAssertEqual(goal.metricSource, MetricSource(connectorId: "c1", metricKey: "signups"))

        goal.metricDirection = .down
        goal.metricUnit = "%"
        goal.metricTarget = 15
        goal.metricBaseline = 5
        goal.metricStaleAfterHours = 24
        guard case .object(let metric)? = try encoded(goal)["metric"] else { return XCTFail("no metric") }
        XCTAssertEqual(metric["direction"], .string("down"))
        XCTAssertEqual(metric["unit"], .string("%"))
        XCTAssertEqual(metric["target"], .number(15))
        XCTAssertEqual(metric["baseline"], .number(5))
        XCTAssertEqual(metric["staleAfterHours"], .number(24))
        // The server's own keys ride along.
        XCTAssertEqual(metric["current"], .number(9))
        XCTAssertEqual(metric["measuredAt"], .string("2026-11-26T00:00:00Z"))
    }

    /// Clearing a field removes the key, rather than sending zero or "".
    func testADEV331_aClearedFieldIsLeftOut() throws {
        var goal = ProjectGoal(id: "g1", statement: "Grow")
        goal.addMetric()
        goal.metricTarget = 10
        goal.metricUnit = "users"
        goal.metricTarget = nil
        goal.metricUnit = ""
        XCTAssertEqual(try encoded(goal)["metric"], .object(["direction": .string("up")]))
    }

    func testADEV331_choosingASourceWritesConnectorAndKey() throws {
        var goal = ProjectGoal(id: "g1", statement: "Grow")
        goal.addMetric()
        goal.metricSource = MetricSource(connectorId: "c1", metricKey: "signups")
        guard case .object(let metric)? = try encoded(goal)["metric"] else { return XCTFail("no metric") }
        XCTAssertEqual(metric["source"], .object(["connectorId": .string("c1"), "metricKey": .string("signups")]))
        goal.metricSource = nil
        guard case .object(let cleared)? = try encoded(goal)["metric"] else { return XCTFail("no metric") }
        XCTAssertNil(cleared["source"])
    }

    /// An explicit null clears a stored metric (an omitted one is kept by the server).
    func testADEV331_removingTheMetricSendsAnExplicitNull() throws {
        var goal = ProjectGoal(id: "g1", statement: "Grow")
        goal.addMetric()
        goal.removeMetric()
        XCTAssertFalse(goal.hasMetric)
        let body = try encoded(goal)
        XCTAssertEqual(body["metric"], .null)
    }

    // MARK: - An enforced guardrail's metric check

    func testADEV331_aCompleteCheckIsSentAsAMetricCheck() throws {
        var rail = ProjectGuardrail(id: "r1", statement: "Error rate", kind: .enforced)
        rail.metricCheck = GuardrailMetricCheck(source: MetricSource(connectorId: "c1", metricKey: "errors"),
                                                op: .atMost, threshold: 2, unit: "%")
        let update = ProjectGoalsUpdate(goals: [], guardrails: [rail]).sanitized
        guard case .object(let check)? = try encoded(update.guardrails[0])["check"] else { return XCTFail("no check") }
        XCTAssertEqual(check["type"], .string("metric"))
        XCTAssertEqual(check["op"], .string("<="))
        XCTAssertEqual(check["threshold"], .number(2))
        XCTAssertEqual(check["unit"], .string("%"))
        XCTAssertEqual(check["source"], .object(["connectorId": .string("c1"), "metricKey": .string("errors")]))
    }

    func testADEV331_editingTheCheckKeepsItsReading() throws {
        let json = #"{ "id": "r1", "statement": "Errors", "kind": "enforced", "check": { "type": "metric", "source": { "connectorId": "c1", "metricKey": "errors" }, "op": ">=", "threshold": 1, "current": 0.4, "measuredAt": "2026-11-26T00:00:00Z" } }"#
        var rail = try JSONDecoder().decode(ProjectGuardrail.self, from: Data(json.utf8))
        XCTAssertEqual(rail.metricCheck?.op, .atLeast)
        var check = try XCTUnwrap(rail.metricCheck)
        check.threshold = 3
        rail.metricCheck = check
        guard case .object(let stored)? = try encoded(rail)["check"] else { return XCTFail("no check") }
        XCTAssertEqual(stored["threshold"], .number(3))
        XCTAssertEqual(stored["current"], .number(0.4))
        XCTAssertEqual(stored["measuredAt"], .string("2026-11-26T00:00:00Z"))
    }

    /// The server refuses a check without a source and a threshold: an unfinished one is not sent.
    func testADEV331_anUnfinishedCheckIsLeftOutOfTheSave() throws {
        var rail = ProjectGuardrail(id: "r1", statement: "Errors", kind: .enforced)
        rail.metricCheck = GuardrailMetricCheck(source: MetricSource(connectorId: "c1", metricKey: ""), op: .atMost, threshold: 2)
        XCTAssertNil(try encoded(ProjectGoalsUpdate(goals: [], guardrails: [rail]).sanitized.guardrails[0])["check"])
        rail.metricCheck = GuardrailMetricCheck(source: MetricSource(connectorId: "c1", metricKey: "errors"), op: .atMost, threshold: nil)
        XCTAssertNil(try encoded(ProjectGoalsUpdate(goals: [], guardrails: [rail]).sanitized.guardrails[0])["check"])
    }

    func testADEV331_removingTheCheck() throws {
        var rail = ProjectGuardrail(id: "r1", statement: "Errors", kind: .enforced)
        rail.metricCheck = GuardrailMetricCheck(source: MetricSource(connectorId: "c1", metricKey: "errors"), op: .atMost, threshold: 2)
        rail.metricCheck = nil
        XCTAssertNil(rail.metricCheck)
        XCTAssertNil(try encoded(rail)["check"])
    }

    // MARK: - The source picker

    @MainActor
    func testADEV331_theSourcePickerListsMetricConnectorsOnly() async {
        let service = GoalSignalsService(experimentWrites: ExperimentWrites(
            link: { _, _, _ in }, unlink: { _, _ in }, refresh: { _ in },
            connectors: { _ in [ProjectConnector(id: "c1", name: "Amplitude", kind: "metric"),
                                ProjectConnector(id: "c2", name: "GrowthBook", kind: "experiment")] },
            addResultsColumn: { _ in }))
        let connectors = await service.connectors(projectId: "p1", kind: "metric")
        XCTAssertEqual(connectors.map(\.id), ["c1"])
    }
}
