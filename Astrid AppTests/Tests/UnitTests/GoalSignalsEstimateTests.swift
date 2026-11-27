//  GoalSignalsEstimateTests.swift
//  ADEV-329 (web ADEV-278/280): the one-tap Estimate and the estimate card on iOS and Mac.
//
//  Asking is `POST /api/v1/tasks/{id}/estimates` with `{ estimator, projectId }` through
//  `GoalSignalsService` (the core has no write for it yet); the card is a port of web
//  `lib/estimate-card.ts`, so both platforms put the reference line and the tiles where web does.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class GoalSignalsEstimateTests: XCTestCase {

    private let fullEstimateJSON = """
    {
      "id": "e1", "source": "service:growthbook",
      "goalImpacts": [{ "goalId": "g1", "delta": 2.5, "low": 1, "high": 4, "unit": "%" }],
      "guardrailImpacts": [{ "guardrailId": "r1", "delta": 0.5, "low": 0.2, "high": 0.8, "breachProbability": 0.2 }],
      "risk": { "level": "high", "score": 0.7, "factors": ["payments", "migration"] },
      "costMicrocents": 1800000000,
      "effortHours": 6,
      "reach": { "count": 2000, "unit": "users", "period": "month" },
      "confidence": "medium",
      "rough": false,
      "createdAt": "2026-11-26T10:00:00Z"
    }
    """

    private var goals: ProjectGoals {
        var goal = ProjectGoal(id: "g1", statement: "Grow signups")
        goal.unmodeled["metric"] = .object(["direction": .string("up"), "target": .number(12), "current": .number(9)])
        var guardrail = ProjectGuardrail(id: "r1", statement: "Error rate", kind: .enforced)
        guardrail.unmodeled["check"] = .object([
            "type": .string("metric"), "op": .string("<="), "threshold": .number(2), "current": .number(1.5), "unit": .string("%"),
        ])
        return ProjectGoals(projectId: "p1", goals: [goal], guardrails: [guardrail])
    }

    private func estimate(_ json: String) throws -> Estimate {
        try JSONDecoder().decode(Estimate.self, from: Data(json.utf8))
    }

    // MARK: - Decoding the card's sections

    func testADEV329_decodesTheSectionsTheCardDraws() throws {
        let e = try estimate(fullEstimateJSON)
        XCTAssertEqual(e.goalImpacts.first?.unit, "%")
        XCTAssertEqual(e.guardrailImpacts, [GuardrailImpact(guardrailId: "r1", delta: 0.5, low: 0.2, high: 0.8, breachProbability: 0.2)])
        XCTAssertEqual(e.risk, .high)
        XCTAssertEqual(e.riskFactors, ["payments", "migration"])
        XCTAssertEqual(e.costMicrocents, 1_800_000_000)
        XCTAssertEqual(e.effortHours, 6)
        XCTAssertEqual(e.reach, EstimateReach(count: 2000, unit: "users", period: "month"))
    }

    /// A missing section is "not estimated", never zero.
    func testADEV329_aMissingSectionIsNotEstimated() throws {
        let e = try estimate(#"{ "id": "e2", "source": "builtin_llm", "rough": true, "createdAt": "2026-11-26T10:00:00Z" }"#)
        XCTAssertNil(e.costMicrocents)
        XCTAssertNil(e.reach)
        XCTAssertTrue(e.guardrailImpacts.isEmpty)
        let card = EstimateCardModel(estimate: e, goals: goals, now: Date())
        XCTAssertNil(card.impact)
        XCTAssertNil(card.cost)
        XCTAssertNil(card.opportunity)
    }

    // MARK: - The card (web lib/estimate-card.ts)

    func testADEV329_goalRowsReferenceTheChangeThatReachesTheTarget() throws {
        let card = EstimateCardModel(estimate: try estimate(fullEstimateJSON), goals: goals, now: Date())
        let row = try XCTUnwrap(card.goalRows.first)
        XCTAssertEqual(row.statement, "Grow signups")
        XCTAssertEqual(row.low, 1)
        XCTAssertEqual(row.high, 4)
        XCTAssertEqual(row.delta, 2.5)
        XCTAssertEqual(row.reference, 3) // target 12 − current 9
        XCTAssertEqual(row.unit, "%")
    }

    func testADEV329_guardrailRowsReferenceTheHeadroomToTheThreshold() throws {
        let card = EstimateCardModel(estimate: try estimate(fullEstimateJSON), goals: goals, now: Date())
        let row = try XCTUnwrap(card.guardrailRows.first)
        XCTAssertEqual(row.statement, "Error rate")
        XCTAssertEqual(row.reference, 0.5) // threshold 2 − current 1.5
        XCTAssertEqual(row.breachProbability, 0.2)
        XCTAssertEqual(row.unit, "%")
    }

    /// A built-in estimate shows ranges only: no point delta, no breach probability.
    func testADEV329_aRoughEstimateShowsRangesOnly() throws {
        var e = try estimate(fullEstimateJSON)
        e.rough = true
        let card = EstimateCardModel(estimate: e, goals: goals, now: Date())
        XCTAssertNil(card.goalRows.first?.delta)
        XCTAssertNil(card.guardrailRows.first?.breachProbability)
    }

    /// No reference line when the goal does not state both numbers.
    func testADEV329_noReferenceWithoutTargetAndCurrent() throws {
        let card = EstimateCardModel(estimate: try estimate(fullEstimateJSON), goals: nil, now: Date())
        XCTAssertNil(card.goalRows.first?.reference)
        XCTAssertEqual(card.goalRows.first?.statement, "g1")
    }

    func testADEV329_theAxisHoldsEveryRangeZeroAndTheReference() {
        let rows = [EstimateRangeRow(id: "g1", statement: "", low: 1, high: 4, delta: nil, unit: nil, reference: 6, breachProbability: nil)]
        let domain = EstimateCardModel.domain(rows)
        // values 0…6, padded by a tenth of the span each side
        XCTAssertEqual(domain.lowerBound, -0.6, accuracy: 0.0001)
        XCTAssertEqual(domain.upperBound, 6.6, accuracy: 0.0001)
        XCTAssertEqual(EstimateCardModel.fraction(-0.6, in: domain), 0, accuracy: 0.0001)
        XCTAssertEqual(EstimateCardModel.fraction(100, in: domain), 1) // clamped
        XCTAssertEqual(EstimateCardModel.fraction(3, in: -0.0...0.0), 0.5) // no span
    }

    func testADEV329_theTilesImpactCostAndOpportunity() throws {
        let card = EstimateCardModel(estimate: try estimate(fullEstimateJSON), goals: goals, now: Date())
        XCTAssertEqual(card.impact?.low, 1)
        XCTAssertEqual(card.impact?.high, 4)
        XCTAssertEqual(card.cost, "$18")
        XCTAssertEqual(card.effortHours, 6)
        // reach × the first goal's range
        XCTAssertEqual(card.opportunity, EstimateOpportunity(low: 2000, high: 8000, unit: "%", period: "month"))
    }

    func testADEV329_dollarsAndCountsReadTheWayWebWritesThem() {
        XCTAssertEqual(EstimateCardModel.dollars(microcents: 1_800_000_000), "$18")
        XCTAssertEqual(EstimateCardModel.dollars(microcents: 250_000_000), "$2.5")
        XCTAssertEqual(EstimateCardModel.dollars(microcents: 120_000_000_000), "$1.2k")
        XCTAssertEqual(EstimateCardModel.count(41_000), "41k")
        XCTAssertEqual(EstimateCardModel.count(3_500_000), "3.5M")
        XCTAssertEqual(EstimateCardModel.count(300), "300")
    }

    func testADEV329_ageAtTheUnitThatReadsNaturally() {
        let created = "2026-11-26T10:00:00Z"
        let base = ISO8601DateFormatter().date(from: created)!
        XCTAssertEqual(EstimateCardModel.age(createdAt: created, now: base.addingTimeInterval(30)), .now)
        XCTAssertEqual(EstimateCardModel.age(createdAt: created, now: base.addingTimeInterval(5 * 60)), .minutes(5))
        XCTAssertEqual(EstimateCardModel.age(createdAt: created, now: base.addingTimeInterval(47 * 3600)), .hours(47))
        XCTAssertEqual(EstimateCardModel.age(createdAt: created, now: base.addingTimeInterval(72 * 3600)), .days(3))
    }

    func testADEV329_theSourceIsNamed() {
        XCTAssertEqual(EstimateCardModel.sourceKind("builtin_llm"), .builtin)
        XCTAssertEqual(EstimateCardModel.sourceKind("human"), .human)
        XCTAssertEqual(EstimateCardModel.sourceKind("service:growthbook"), .service("growthbook"))
    }

    // MARK: - What the deployment offers

    func testADEV329_capabilitiesListTheEstimators() throws {
        let json = #"{ "goalSignals": { "metricSources": [], "experimentSources": [], "estimators": [ { "key": "builtin", "name": "Built-in estimator" }, { "key": "acme", "name": "Acme" } ], "customEndpoints": false } }"#
        let caps = try JSONDecoder().decode(ServerCapabilities.self, from: Data(json.utf8))
        XCTAssertEqual(caps.goalSignals.estimators.map(\.key), ["builtin", "acme"])
        // Absent reads as off: nothing offered.
        XCTAssertTrue(try JSONDecoder().decode(ServerCapabilities.self, from: Data("{}".utf8)).goalSignals.estimators.isEmpty)
    }

    func testADEV329_theButtonIsOfferedOnlyWhereThereIsSomethingToEstimate() {
        let estimators = [EstimatorChoice(key: "builtin", name: "Built-in")]
        let stated = goals
        func offer(projectMode: Bool = true, goals: ProjectGoals? = stated, estimators: [EstimatorChoice] = estimators,
                   readOnly: Bool = false) -> EstimateOffer {
            EstimateOffer(projectMode: projectMode, projectId: "p1", goals: goals, estimators: estimators, isReadOnly: readOnly)
        }
        XCTAssertTrue(offer().showsButton)
        XCTAssertFalse(offer().showsPicker)
        XCTAssertTrue(offer(estimators: estimators + [EstimatorChoice(key: "acme", name: "Acme")]).showsPicker)
        XCTAssertFalse(offer(projectMode: false).showsButton)
        XCTAssertFalse(offer(goals: ProjectGoals(goals: [], guardrails: [])).showsButton)
        XCTAssertFalse(offer(goals: nil).showsButton)
        XCTAssertFalse(offer(estimators: []).showsButton)
        XCTAssertFalse(offer(readOnly: true).showsButton) // asking writes a row
    }

    /// An idea is an open card with no board status: only it gets the card's Estimate (web board-card).
    func testADEV329_onlyAnIdeaCardOffersEstimate() {
        var task = TestHelpers.createTestTask(id: "t1")
        task.statusRole = nil
        XCTAssertTrue(EstimateOffer.isIdea(task))
        task.statusRole = "doing"
        XCTAssertFalse(EstimateOffer.isIdea(task))
        task.statusRole = nil
        task.completed = true
        XCTAssertFalse(EstimateOffer.isIdea(task))
    }

    // MARK: - Asking (the service)

    func testADEV329_askingPostsTheEstimatorAndProjectThenRereadsTheSignals() async {
        var posted: [(String, String, String?)] = []
        var reads = 0
        let service = GoalSignalsService(
            readLinks: { _ in TaskGoalLinks(taskId: "t1", links: []) },
            readEstimate: { _ in reads += 1; return TaskEstimates(taskId: "t1", latest: Estimate(id: "e\(reads)"), history: []) },
            readExperiment: { _ in TaskExperiments(taskId: "t1", experiments: [], inResultsColumn: false) },
            postEstimate: { taskId, estimator, projectId in
                posted.append((taskId, estimator, projectId))
                return EstimateRequestReply(pending: nil, estimator: nil)
            })
        let outcome = await service.requestEstimate(taskId: "t1", estimator: "builtin", projectId: "p1")
        XCTAssertEqual(outcome, .landed)
        XCTAssertEqual(posted.count, 1)
        XCTAssertEqual(posted.first?.1, "builtin")
        XCTAssertEqual(posted.first?.2, "p1")
        XCTAssertEqual(service.signals(taskId: "t1")?.estimates?.latest?.id, "e1")
        XCTAssertFalse(service.isEstimating(taskId: "t1"))
    }

    func testADEV329_aServiceStillWorkingIsPending() async {
        let service = GoalSignalsService(postEstimate: { _, _, _ in EstimateRequestReply(pending: true, estimator: "acme") })
        let outcome = await service.requestEstimate(taskId: "t1", estimator: "acme", projectId: nil)
        XCTAssertEqual(outcome, .pending)
    }

    func testADEV329_refusalsMapToWhatThePersonCanDo() {
        func http(_ status: Int, _ body: String) -> Error { AstridAPIError.httpError(statusCode: status, message: body) }
        XCTAssertEqual(GoalSignalsService.outcome(for: http(403, #"{"error":"x","reason":"not_granted","featureKey":"goal_signals"}"#)), .notGranted)
        XCTAssertEqual(GoalSignalsService.outcome(for: http(409, #"{"error":"x","reason":"no_api_key"}"#)), .noKey)
        XCTAssertEqual(GoalSignalsService.outcome(for: http(502, #"{"error":"x","reason":"estimator_failed"}"#)), .failed)
        XCTAssertEqual(GoalSignalsService.outcome(for: http(403, "not json")), .failed)
        XCTAssertEqual(GoalSignalsService.outcome(for: URLError(.notConnectedToInternet)), .failed)
    }

    func testADEV329_requestingAccessAsksForTheGoalSignalsFlag() async {
        var asked: [String] = []
        let service = GoalSignalsService(postFeatureRequest: { asked.append($0) })
        let ok = await service.requestAccess()
        XCTAssertTrue(ok)
        XCTAssertEqual(asked, ["goal_signals"])
        XCTAssertTrue(service.accessRequested)
    }
}
