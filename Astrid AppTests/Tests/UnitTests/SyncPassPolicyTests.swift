import XCTest
@testable import Astrid_App

/// Red-green spec for how a sync pass admits work (Task: 3173727d — remotely
/// added tasks never appearing).
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
}
