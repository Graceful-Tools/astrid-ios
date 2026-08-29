import XCTest
@testable import Astrid_App

/// Red-green spec for how a sync pass admits work and how it treats a failed
/// local push (Task: 3173727d — remotely added tasks never appearing).
///
/// Both rules exist because the old shapes fail SILENTLY: a pull-to-refresh
/// that lands while a background pass is running used to return instantly and
/// fetch nothing, and one failing pending-comment push aborted the whole
/// incremental pass BEFORE it fetched tasks — so remote changes stopped
/// arriving with nothing on screen to say so.
final class SyncPassPolicyTests: XCTestCase {

    // MARK: - Admission

    func testIdlePass_startsImmediately_3173727d() {
        XCTAssertEqual(SyncPassPolicy.admission(isSyncing: false, isUserInitiated: true), .start)
        XCTAssertEqual(SyncPassPolicy.admission(isSyncing: false, isUserInitiated: false), .start)
    }

    func testUserRefresh_waitsForTheInFlightPass_ratherThanDoingNothing_3173727d() {
        XCTAssertEqual(
            SyncPassPolicy.admission(isSyncing: true, isUserInitiated: true),
            .waitForInFlight,
            "a refresh the user asked for must not be a silent no-op")
    }

    func testBackgroundPass_skipsWhileAnotherIsInFlight_3173727d() {
        XCTAssertEqual(SyncPassPolicy.admission(isSyncing: true, isUserInitiated: false), .skip)
    }

    // MARK: - Local pushes are best-effort

    func testFailedPushStep_doesNotStopTheLaterSteps_3173727d() async {
        var ran: [String] = []
        let failed = await SyncPassPolicy.runPushSteps([
            .init(name: "tasks", run: { ran.append("tasks"); throw TestError.boom }),
            .init(name: "comments", run: { ran.append("comments") }),
            .init(name: "members", run: { ran.append("members"); throw TestError.boom }),
        ])
        XCTAssertEqual(ran, ["tasks", "comments", "members"], "every step must run")
        XCTAssertEqual(failed, ["tasks", "members"], "and the failures must be reported, not swallowed")
    }

    func testAllPushStepsSucceeding_reportsNoFailures_3173727d() async {
        let failed = await SyncPassPolicy.runPushSteps([
            .init(name: "tasks", run: {}),
            .init(name: "comments", run: {}),
        ])
        XCTAssertTrue(failed.isEmpty)
    }

    private enum TestError: Error { case boom }
}
