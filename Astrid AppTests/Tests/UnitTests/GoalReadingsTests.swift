//  GoalReadingsTests.swift
//  ADEV-321 (web ADEV-270/276/281; spec astrid-web docs/specs/GOALS_GUARDRAILS_SIGNALS.md): phase 1
//  of Goal Signals on iOS/Mac, read-only. The goals strip shows a goal's progress, where its number
//  comes from, how fresh it is and how it moved; and a list with a trade-off policy offers the
//  Policy sort, which astrid-core already answers.

import XCTest
@testable import Astrid_App

final class GoalReadingsTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-11-26T12:00:00Z")!

    private func goals(_ json: String) throws -> ProjectGoals {
        try JSONDecoder().decode(ProjectGoals.self, from: Data(json.utf8))
    }

    private func parse(_ json: String) throws -> ProjectGoal {
        try JSONDecoder().decode(ProjectGoal.self, from: Data(json.utf8))
    }

    private let signalled = """
    {
      "projectId": "p1",
      "goals": [{ "id": "g1", "statement": "Grow", "measure": "DAU", "target": "100", "current": "40",
                  "metric": { "direction": "up", "unit": "users", "target": 200, "current": 50,
                              "measuredAt": "2026-11-26T09:00:00Z",
                              "source": { "connectorId": "posthog", "metricKey": "dau" } },
                  "history": [{ "value": "30", "by": "u1", "at": "2026-11-20T00:00:00Z", "num": 30 },
                              { "value": "n/a", "by": "u1", "at": "2026-11-21T00:00:00Z" },
                              { "value": "50", "by": "agent", "at": "2026-11-26T09:00:00Z", "num": 50 }] }],
      "guardrails": [],
      "workByGoal": { "g1": 3 },
      "canEdit": false
    }
    """

    /// The metric block and history are read for display and still sent back untouched (ADEV-319).
    func testADEV321_readsTheMetricAndHistoryAndStillPassesThemThrough() throws {
        let decoded = try goals(signalled)
        let goal = try XCTUnwrap(decoded.goals.first)
        XCTAssertEqual(goal.metric?.direction, .up)
        XCTAssertEqual(goal.metric?.target, 200)
        XCTAssertEqual(goal.metric?.current, 50)
        XCTAssertEqual(goal.metric?.source?.connectorId, "posthog")
        XCTAssertEqual(goal.metric?.source?.metricKey, "dau")
        XCTAssertEqual(goal.history.count, 3)
        XCTAssertEqual(decoded.workByGoal["g1"], 3)

        let data = try JSONEncoder().encode(ProjectGoalsUpdate(goals: decoded.goals, guardrails: []))
        let sent = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["goals"] as? [[String: Any]])
        XCTAssertNotNil(sent[0]["metric"])
        XCTAssertNotNil(sent[0]["history"])
    }

    /// A metric with both numbers wins over the free text; `down` is met at or below, with no percent.
    func testADEV321_progressPrefersTheMetric() throws {
        let goal = try XCTUnwrap(try goals(signalled).goals.first)
        XCTAssertEqual(GoalReadings.progress(goal), .init(met: false, percent: 25))

        let down = try self.parse(#"{"statement":"Latency","target":"100","current":"90","metric":{"direction":"down","target":60,"current":50}}"#)
        XCTAssertEqual(GoalReadings.progress(down), .init(met: true, percent: nil))
    }

    /// With no metric the free text is read as before: the first number on each side, a "≤" target
    /// lower-is-better, the percent capped at 100, and nothing for prose.
    func testADEV321_progressFallsBackToTheText() {
        XCTAssertEqual(GoalReadings.progress(ProjectGoal(id: "g", statement: "s", target: "≥ 8%/yr", current: "6.1%")),
                       .init(met: false, percent: 76))
        XCTAssertEqual(GoalReadings.progress(ProjectGoal(id: "g", statement: "s", target: "≤ 200ms", current: "180ms")),
                       .init(met: true, percent: nil))
        XCTAssertEqual(GoalReadings.progress(ProjectGoal(id: "g", statement: "s", target: "10", current: "12")),
                       .init(met: true, percent: 100))
        XCTAssertNil(GoalReadings.progress(ProjectGoal(id: "g", statement: "s", target: "happy users", current: "some")))
    }

    /// Fresh until `staleAfterHours` (default 48) passes; the metric's reading time first, then the
    /// latest history entry; nothing without a timestamp.
    func testADEV321_freshness() throws {
        let goal = try XCTUnwrap(try goals(signalled).goals.first)
        let fresh = try XCTUnwrap(GoalReadings.freshness(goal, now: now))
        XCTAssertFalse(fresh.stale)
        XCTAssertEqual(fresh.age, 3 * 3600, accuracy: 1)

        let strict = try self.parse(#"{"statement":"s","metric":{"direction":"up","measuredAt":"2026-11-26T09:00:00Z","staleAfterHours":2}}"#)
        XCTAssertEqual(GoalReadings.freshness(strict, now: now)?.stale, true)

        let historyOnly = try self.parse(#"{"statement":"s","history":[{"value":"1","by":"u","at":"2026-11-26T11:00:00Z"}]}"#)
        XCTAssertEqual(GoalReadings.freshness(historyOnly, now: now)?.stale, false, "falls back to the last history entry")
        let old = try self.parse(#"{"statement":"s","history":[{"value":"1","by":"u","at":"2026-11-20T11:00:00Z"}]}"#)
        XCTAssertEqual(GoalReadings.freshness(old, now: now)?.stale, true, "48 hours by default")
        XCTAssertNil(GoalReadings.freshness(ProjectGoal(id: "g", statement: "prose"), now: now))
    }

    /// The sparkline draws only the numeric readings, oldest first.
    func testADEV321_sparkValuesSkipNonNumericReadings() throws {
        let goal = try XCTUnwrap(try goals(signalled).goals.first)
        XCTAssertEqual(GoalReadings.sparkValues(goal), [30, 50])
    }

    /// The strip's lines, worded as web words them.
    func testADEV321_stripWording() throws {
        let decoded = try goals(signalled)
        let goal = try XCTUnwrap(decoded.goals.first)
        let detail = try XCTUnwrap(ProjectGoalsStrip.detail(goal, workServed: decoded.workByGoal["g1"]))
        XCTAssertTrue(detail.contains("25"), detail)
        XCTAssertTrue(detail.contains("3"), detail)
        XCTAssertEqual(ProjectGoalsStrip.sourceText(goal), String(
            format: NSLocalizedString("project_goals.source_name", comment: ""), "posthog · dau"))
        XCTAssertNil(ProjectGoalsStrip.sourceText(ProjectGoal(id: "g", statement: "prose")))
    }
}

/// ADEV-321 (web ADEV-281, core ADEV-324): the Policy sort is offered only where a trade-off
/// policy applies, read from the list's effective orchestration policy.
@MainActor
final class ListTradeoffPolicyTests: XCTestCase {

    func testADEV321_aPolicyIsStatedOnlyWhenTheEffectivePolicyHasATradeoff() throws {
        let stated = #"{"listId":"l1","effective":{"autonomy":{},"tradeoff":{"thresholds":{}}}}"#
        let none = #"{"listId":"l1","effective":{"autonomy":{}}}"#
        XCTAssertTrue(try JSONDecoder().decode(ListOrchestrationPolicy.self, from: Data(stated.utf8)).tradeoffStated)
        XCTAssertFalse(try JSONDecoder().decode(ListOrchestrationPolicy.self, from: Data(none.utf8)).tradeoffStated)
    }

    func testADEV321_policySortOfferedOnlyWhenStated() async {
        struct Down: Error {}
        let service = ListTradeoffPolicyService(fetch: { id in
            if id == "l1" { return ListOrchestrationPolicy(tradeoffStated: true) }
            throw Down()
        })
        XCTAssertFalse(service.isStated(listId: "l1"), "unknown until read")
        await service.load(listId: "l1")
        await service.load(listId: "l2")
        XCTAssertTrue(service.isStated(listId: "l1"))
        XCTAssertFalse(service.isStated(listId: "l2"), "a failed read hides it")

        XCTAssertTrue(ListSortOptions.values(policyStated: true).contains("policy"))
        XCTAssertFalse(ListSortOptions.values(policyStated: false).contains("policy"))
    }
}
