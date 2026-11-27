//  GoalSignalsTests.swift
//  ADEV-323 (core ADEV-285, astrid-core#131): a task's goal links, estimate and experiment results,
//  read from astrid-core's `getTaskGoalLinks` / `getTaskEstimate` / `getTaskExperiment` and
//  refreshed when the core announces `taskGoalSignals`. Nothing here computes: the label, its
//  reasons and the verdict are the server's, worded from `Localizable.strings`.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class GoalSignalsTests: XCTestCase {

    private let estimateJSON = """
    {
      "taskId": "t1",
      "latest": {
        "id": "e1", "source": "service:growthbook",
        "goalImpacts": [{ "goalId": "g1", "delta": 2.5, "low": 1, "high": 4 }],
        "guardrailImpacts": [{ "guardrailId": "r1", "breachProbability": 0.2 }],
        "risk": { "level": "medium", "score": 0.4 },
        "confidence": "high",
        "rationale": "Shorter onboarding",
        "rough": false,
        "label": "needs-review",
        "labelReasons": [
          { "code": "guardrailAtReview", "guardrailId": "r1", "breachProbability": 0.2, "threshold": 0.1 },
          { "code": "riskAtReview", "level": "medium", "threshold": "medium" },
          { "code": "somethingNewer" }
        ],
        "createdAt": "2026-11-26T10:00:00Z",
        "futureField": 1
      },
      "history": []
    }
    """

    private let linksJSON = """
    { "taskId": "t1", "links": [
      { "projectId": "p1", "projectName": "Fund", "goalId": "g1", "statement": "Grow signups", "via": "task", "source": "person" },
      { "projectId": "p1", "goalId": "g2", "statement": "Keep churn low", "via": "list", "listId": "l1", "source": "agent" }
    ] }
    """

    private let experimentJSON = """
    { "taskId": "t1", "inResultsColumn": true, "experiments": [
      { "id": "x1", "kind": "experiment", "state": "running", "verdict": "improving",
        "decideBy": "2026-12-01T00:00:00Z", "stale": false, "url": "https://example.com/x1" },
      { "id": "x2", "kind": "verification", "state": "pending", "stale": true }
    ] }
    """

    // MARK: - The announcement

    func testADEV323_theCoreAnnouncesTaskGoalSignals() {
        XCTAssertEqual(CoreChange(json: #"{"change":"taskGoalSignals","id":"t1"}"#), .taskGoalSignals(taskId: "t1"))
        // No id is something this build cannot place: read everything again.
        XCTAssertEqual(CoreChange(json: #"{"change":"taskGoalSignals"}"#), .unknown(#"{"change":"taskGoalSignals"}"#))
    }

    func testADEV323_theAnnouncementGoesToGoalSignalsOnly() {
        XCTAssertEqual(AppCore.audiences(for: .taskGoalSignals(taskId: "t1")), [.goalSignals])
        XCTAssertTrue(AppCore.audiences(for: .unknown("{}")).contains(.goalSignals))
    }

    // MARK: - Decoding what the core answers

    func testADEV323_decodesTheEstimate() throws {
        let estimates = try JSONDecoder().decode(TaskEstimates.self, from: Data(estimateJSON.utf8))
        let latest = try XCTUnwrap(estimates.latest)
        XCTAssertEqual(latest.label, .needsReview)
        XCTAssertEqual(latest.risk, .medium)
        XCTAssertEqual(latest.confidence, .high)
        XCTAssertEqual(latest.goalImpacts, [GoalImpact(goalId: "g1", delta: 2.5, low: 1, high: 4)])
        XCTAssertEqual(latest.reasons.map(\.code), ["guardrailAtReview", "riskAtReview", "somethingNewer"])
        XCTAssertFalse(latest.rough)
    }

    /// A label this build does not know draws no chip, rather than failing the whole estimate.
    func testADEV323_anUnknownLabelDrawsNoChip() throws {
        let json = #"{"taskId":"t1","latest":{"id":"e1","label":"maybe-later","rough":true},"history":[]}"#
        let estimates = try JSONDecoder().decode(TaskEstimates.self, from: Data(json.utf8))
        XCTAssertNil(estimates.latest?.label)
        XCTAssertEqual(estimates.latest?.rough, true)
        XCTAssertNil(estimates.latest?.risk)
    }

    func testADEV323_decodesLinksAndExperiments() throws {
        let links = try JSONDecoder().decode(TaskGoalLinks.self, from: Data(linksJSON.utf8))
        XCTAssertEqual(links.links.map(\.statement), ["Grow signups", "Keep churn low"])
        XCTAssertEqual(links.statement(goalId: "g2"), "Keep churn low")
        XCTAssertNil(links.statement(goalId: "nope"))

        let results = try JSONDecoder().decode(TaskExperiments.self, from: Data(experimentJSON.utf8))
        XCTAssertTrue(results.inResultsColumn)
        XCTAssertEqual(results.experiments.map(\.state), ["running", "pending"])
        XCTAssertEqual(results.experiments.first?.verdict, "improving")
        XCTAssertEqual(results.experiments.last?.stale, true)
    }

    // MARK: - Wording

    func testADEV323_labelsAndReasonsAreWordedFromStrings() throws {
        XCTAssertEqual(GoalSignalsWording.label(.doNow), "Do now")
        XCTAssertEqual(GoalSignalsWording.label(.experimentFirst), "Experiment first")
        XCTAssertEqual(GoalSignalsWording.label(.needsReview), "Needs review")
        XCTAssertEqual(GoalSignalsWording.label(.dont), "Don’t")

        let estimates = try JSONDecoder().decode(TaskEstimates.self, from: Data(estimateJSON.utf8))
        let links = try JSONDecoder().decode(TaskGoalLinks.self, from: Data(linksJSON.utf8))
        let reasons = try XCTUnwrap(estimates.latest?.reasons)
        let words = reasons.compactMap { GoalSignalsWording.reason($0, links: links) }
        // The guardrail is named by id when the links do not carry it; an unknown code says nothing.
        XCTAssertEqual(words, ["Guardrail r1 may be breached (20%)", "Risk is medium"])

        let improves = EstimateReason(code: "goalImproves", values: ["goalId": .string("g1"), "delta": .number(2)])
        XCTAssertEqual(GoalSignalsWording.reason(improves, links: links), "Improves “Grow signups”")
        XCTAssertEqual(GoalSignalsWording.reason(EstimateReason(code: "builtinCapped", values: [:]), links: links),
                       "A rough estimate cannot recommend building")
    }

    func testADEV323_impactReadsAsARange() {
        let impact = GoalImpact(goalId: "g1", delta: 2.5, low: 1, high: 4)
        XCTAssertEqual(GoalSignalsWording.impact(impact, statement: "Grow signups"), "Grow signups: +2.5 (+1 to +4)")
        XCTAssertEqual(GoalSignalsWording.impact(GoalImpact(goalId: "g9", delta: -1, low: nil, high: nil), statement: nil),
                       "g9: −1")
    }

    func testADEV323_pendingResultsWording() throws {
        let results = try JSONDecoder().decode(TaskExperiments.self, from: Data(experimentJSON.utf8))
        let running = try XCTUnwrap(results.experiments.first)
        XCTAssertEqual(GoalSignalsWording.resultLine(running), "Experiment · Running · Improving")
        let pending = try XCTUnwrap(results.experiments.last)
        XCTAssertEqual(GoalSignalsWording.resultLine(pending), "Verification · Not started")
        // The board card adds when to decide and the stale note, the same line on iOS and Mac.
        XCTAssertTrue(GoalSignalsWording.cardLine(running).hasPrefix("Experiment · Running · Improving · "))
        XCTAssertEqual(GoalSignalsWording.cardLine(pending),
                       "Verification · Not started · " + NSLocalizedString("goalSignals.results.stale", comment: ""))
        XCTAssertEqual(GoalSignalsWording.resultsColumnRole, "results")
    }

    // MARK: - The service

    func testADEV323_serviceHoldsAnswersPerTaskAndARefusalDrawsNothing() async throws {
        let estimates = try JSONDecoder().decode(TaskEstimates.self, from: Data(estimateJSON.utf8))
        struct Refused: Error {}
        let service = GoalSignalsService(
            readLinks: { _ in throw Refused() },
            readEstimate: { _ in estimates },
            readExperiment: { _ in throw Refused() })
        XCTAssertNil(service.signals(taskId: "t1"))
        await service.load(taskId: "t1")
        let signals = try XCTUnwrap(service.signals(taskId: "t1"))
        XCTAssertEqual(signals.estimates, estimates)
        XCTAssertNil(signals.links)
        XCTAssertNil(signals.experiments)
        XCTAssertTrue(signals.hasDetail)
        XCTAssertFalse(GoalSignals().hasDetail)
    }

    /// The announcement re-reads a task the app holds, and only that one.
    func testADEV323_theAnnouncementReReadsAHeldTask() async throws {
        var reads: [String] = []
        let service = GoalSignalsService(
            readLinks: { id in reads.append(id); return TaskGoalLinks(taskId: id, links: []) },
            readEstimate: { id in TaskEstimates(taskId: id, latest: nil, history: []) },
            readExperiment: { id in TaskExperiments(taskId: id, experiments: [], inResultsColumn: false) })
        await service.load(taskId: "t1")
        XCTAssertEqual(reads, ["t1"])
        await service.refresh(for: .taskGoalSignals(taskId: "t1"))
        await service.refresh(for: .taskGoalSignals(taskId: "not-held"))
        XCTAssertEqual(reads, ["t1", "t1"])
    }
}
