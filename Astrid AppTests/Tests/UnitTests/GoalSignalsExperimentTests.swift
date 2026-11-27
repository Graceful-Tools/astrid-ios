//  GoalSignalsExperimentTests.swift
//  ADEV-330 (web ADEV-279/282/286): experiments on a task — link, unlink, refresh, a link out — and
//  the one-tap Pending results "Add column" offer, on iOS and Mac.
//
//  Writes go through `GoalSignalsService` (the core has no experiment writes yet), then the task's
//  experiments are read back through the core. The picker follows web `ExperimentLinkForm`: an
//  experiment needs a project connector (owner/admin only); anyone else may start a verification.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class GoalSignalsExperimentTests: XCTestCase {

    private let linkJSON = """
    { "id": "x1", "kind": "experiment", "connectorId": "c1", "externalKey": "checkout-v2",
      "url": "https://example.com/x1", "state": "running", "verdict": "improving",
      "recommendation": { "action": "ship", "reason": "Conversion is up" },
      "metrics": [
        { "metricKey": "conversion", "relDelta": 0.042, "significant": true },
        { "metricKey": "aov", "relDelta": -0.01, "significant": false },
        { "metricKey": "noDelta" }
      ],
      "decideBy": "2026-12-01T00:00:00Z", "fetchedAt": "2026-11-20T00:00:00Z", "stale": true }
    """

    private func link(_ json: String) throws -> ExperimentLink {
        try JSONDecoder().decode(ExperimentLink.self, from: Data(json.utf8))
    }

    // MARK: - Decoding and wording

    func testADEV330_decodesWhatTheRowDraws() throws {
        let link = try link(linkJSON)
        XCTAssertEqual(link.externalKey, "checkout-v2")
        XCTAssertEqual(link.recommendation, ExperimentRecommendation(action: "ship", reason: "Conversion is up"))
        // A metric without a delta has nothing to say.
        XCTAssertEqual(link.metrics.map(\.metricKey), ["conversion", "aov"])
        XCTAssertEqual(link.metrics.last?.significant, false)
        XCTAssertNotNil(link.fetchedAt)
        XCTAssertTrue(link.isOpen)
    }

    func testADEV330_concludedAndStoppedAreNotOpen() throws {
        XCTAssertFalse(try link(#"{ "id": "x", "state": "concluded" }"#).isOpen)
        XCTAssertFalse(try link(#"{ "id": "x", "state": "stopped" }"#).isOpen)
        XCTAssertTrue(try link(#"{ "id": "x", "state": "pending" }"#).isOpen)
    }

    func testADEV330_metricDeltasReadAsWebWritesThem() {
        XCTAssertEqual(GoalSignalsWording.relDelta(0.042), "+4.2%")
        XCTAssertEqual(GoalSignalsWording.relDelta(-0.01), "-1.0%")
        XCTAssertEqual(GoalSignalsWording.relDelta(0), "0.0%")
    }

    func testADEV330_theTitleIsTheKeyOrTheKind() throws {
        XCTAssertEqual(GoalSignalsWording.experimentTitle(try link(linkJSON)), "checkout-v2")
        let verification = try link(#"{ "id": "v", "kind": "verification", "state": "running" }"#)
        XCTAssertEqual(GoalSignalsWording.experimentTitle(verification),
                       NSLocalizedString("goalSignals.results.verification", comment: ""))
    }

    // MARK: - The row

    func testADEV330_theRowShowsWhereThereIsSomethingToSeeOrDo() throws {
        let none = TaskExperiments(taskId: "t1", experiments: [], inResultsColumn: false)
        let some = TaskExperiments(taskId: "t1", experiments: [try link(linkJSON)], inResultsColumn: false)
        // Refused (goal signals not granted): nothing.
        XCTAssertFalse(ExperimentRow.shows(experiments: nil, isReadOnly: false, inProject: true))
        XCTAssertTrue(ExperimentRow.shows(experiments: some, isReadOnly: true, inProject: false))
        XCTAssertTrue(ExperimentRow.shows(experiments: none, isReadOnly: false, inProject: true))
        // Nothing to say, and nobody who can change that: no row.
        XCTAssertFalse(ExperimentRow.shows(experiments: none, isReadOnly: true, inProject: true))
        XCTAssertFalse(ExperimentRow.shows(experiments: none, isReadOnly: false, inProject: false))
    }

    // MARK: - The picker

    func testADEV330_verificationDaysAreOneToNinety() {
        XCTAssertEqual(ExperimentLinkRequest.verificationDays("7"), 7)
        XCTAssertEqual(ExperimentLinkRequest.verificationDays(" 90 "), 90)
        XCTAssertNil(ExperimentLinkRequest.verificationDays("0"))
        XCTAssertNil(ExperimentLinkRequest.verificationDays("91"))
        XCTAssertNil(ExperimentLinkRequest.verificationDays("2.5"))
        XCTAssertNil(ExperimentLinkRequest.verificationDays(""))
    }

    func testADEV330_theRequestBodiesMatchTheRoute() throws {
        func body(_ request: ExperimentLinkRequest) throws -> [String: JSONValue] {
            let data = try JSONEncoder().encode(request.body(projectId: "p1"))
            return try JSONDecoder().decode([String: JSONValue].self, from: data)
        }
        XCTAssertEqual(try body(.experiment(connectorId: "c1", externalKey: " checkout-v2 ")), [
            "kind": .string("experiment"), "connectorId": .string("c1"),
            "externalKey": .string("checkout-v2"), "projectId": .string("p1"),
        ])
        XCTAssertEqual(try body(.verification(days: 7)), [
            "kind": .string("verification"), "days": .number(7), "projectId": .string("p1"),
        ])
    }

    // MARK: - Writes (the service)

    private func service(log: @escaping (String) -> Void,
                         connectors: [ProjectConnector] = [],
                         fail: Bool = false) -> GoalSignalsService {
        GoalSignalsService(
            readExperiment: { _ in log("read"); return TaskExperiments(taskId: "t1", experiments: [], inResultsColumn: false) },
            experimentWrites: ExperimentWrites(
                link: { taskId, request, projectId in
                    if fail { throw AstridAPIError.httpError(statusCode: 400, message: "{}") }
                    log("link \(taskId) \(request) \(projectId ?? "-")")
                },
                unlink: { taskId, experimentId in log("unlink \(taskId) \(experimentId)") },
                refresh: { taskId in log("refresh \(taskId)") },
                connectors: { projectId in log("connectors \(projectId)"); return connectors },
                addResultsColumn: { projectId in log("column \(projectId)") }))
    }

    func testADEV330_linkingThenReadsTheExperimentsBack() async {
        var calls: [String] = []
        let service = service(log: { calls.append($0) })
        let ok = await service.linkExperiment(taskId: "t1", request: .verification(days: 7), projectId: "p1")
        XCTAssertTrue(ok)
        XCTAssertEqual(calls, ["link t1 verification(days: 7) p1", "read"])
    }

    func testADEV330_aRefusedLinkSaysSoAndReadsNothing() async {
        var calls: [String] = []
        let service = service(log: { calls.append($0) }, fail: true)
        let ok = await service.linkExperiment(taskId: "t1", request: .verification(days: 7), projectId: "p1")
        XCTAssertFalse(ok)
        XCTAssertEqual(calls, [])
    }

    func testADEV330_unlinkAndRefreshReadBack() async {
        var calls: [String] = []
        let service = service(log: { calls.append($0) })
        _ = await service.unlinkExperiment(taskId: "t1", experimentId: "x1")
        _ = await service.refreshExperiments(taskId: "t1")
        XCTAssertEqual(calls, ["unlink t1 x1", "read", "refresh t1", "read"])
    }

    /// Only experiment connectors are offered; any other kind is not something to link.
    func testADEV330_thePickerListsExperimentConnectorsOnly() async {
        let service = service(log: { _ in }, connectors: [
            ProjectConnector(id: "c1", name: "GrowthBook", kind: "experiment"),
            ProjectConnector(id: "c2", name: "Metrics", kind: "metric"),
        ])
        let connectors = await service.experimentConnectors(projectId: "p1")
        XCTAssertEqual(connectors.map(\.id), ["c1"])
    }

    // MARK: - The Add column offer

    func testADEV330_theOfferIsTheBoardOwnersOnce() {
        let board = Project(id: "p1", name: "Fund", ownerId: "me")
        XCTAssertTrue(ResultsColumnOffer.shows(hasLinks: true, project: board, currentUserId: "me", dismissed: false))
        // Nothing linked yet: nothing to hold.
        XCTAssertFalse(ResultsColumnOffer.shows(hasLinks: false, project: board, currentUserId: "me", dismissed: false))
        // Not the owner: the statuses route would refuse.
        XCTAssertFalse(ResultsColumnOffer.shows(hasLinks: true, project: board, currentUserId: "you", dismissed: false))
        XCTAssertFalse(ResultsColumnOffer.shows(hasLinks: true, project: board, currentUserId: nil, dismissed: false))
        XCTAssertFalse(ResultsColumnOffer.shows(hasLinks: true, project: board, currentUserId: "me", dismissed: true))
        XCTAssertFalse(ResultsColumnOffer.shows(hasLinks: true, project: nil, currentUserId: "me", dismissed: false))
        // A board that has the column is never offered it.
        let withColumn = Project(id: "p1", name: "Fund", ownerId: "me",
                                 customStates: [ProjectCustomState(role: "results", name: "Pending results")])
        XCTAssertFalse(ResultsColumnOffer.shows(hasLinks: true, project: withColumn, currentUserId: "me", dismissed: false))
    }

    func testADEV330_notNowIsRememberedPerBoard() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ADEV-330-\(UUID().uuidString)"))
        let store = ResultsColumnOffer.Dismissals(defaults: defaults)
        XCTAssertFalse(store.isDismissed(projectId: "p1"))
        store.dismiss(projectId: "p1")
        XCTAssertTrue(store.isDismissed(projectId: "p1"))
        XCTAssertFalse(store.isDismissed(projectId: "p2"))
    }

    func testADEV330_addingTheColumnPostsTheResultsPreset() async {
        var calls: [String] = []
        let service = service(log: { calls.append($0) })
        let ok = await service.addResultsColumn(projectId: "p1")
        XCTAssertTrue(ok)
        XCTAssertEqual(calls, ["column p1"])
    }
}
