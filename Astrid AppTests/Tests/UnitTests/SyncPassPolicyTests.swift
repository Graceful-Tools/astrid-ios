import AstridCore
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

    // MARK: - A failed pass (ADEV-250)

    /// ADEV-250: a task on Mac and web never reached iOS, even on a manual sync, until a sign-out
    /// and sign-in. Every failed pass was logged as "offline?" and dropped, so a session the server
    /// had stopped accepting looked like no news. A rejected session must be recognised as such.
    func testRejectedSession_isNotTreatedAsOffline_ADEV250() {
        let rejected = CoreFailure(kind: .unauthorized, message: "session expired", status: 401, id: nil)
        XCTAssertEqual(SyncPassPolicy.outcome(of: rejected), .sessionRejected)
    }

    func testA401OfAnyKind_isARejectedSession_ADEV250() {
        let refused = CoreFailure(kind: .refused, message: "Unauthorized", status: 401, id: nil)
        XCTAssertEqual(SyncPassPolicy.outcome(of: refused), .sessionRejected)
        XCTAssertEqual(SyncPassPolicy.outcome(of: AstridAPIError.unauthorized), .sessionRejected)
    }

    func testOffline_staysQuiet_ADEV250() {
        let offline = CoreFailure(kind: .offline, message: "no route", status: nil, id: nil)
        XCTAssertEqual(SyncPassPolicy.outcome(of: offline), .offline)
        XCTAssertEqual(SyncPassPolicy.outcome(of: URLError(.notConnectedToInternet)), .offline)
    }

    func testAnyOtherFailure_isAFailureNotOffline_ADEV250() {
        let server = CoreFailure(kind: .refused, message: "boom", status: 500, id: nil)
        XCTAssertEqual(SyncPassPolicy.outcome(of: server), .failed)
    }
}
