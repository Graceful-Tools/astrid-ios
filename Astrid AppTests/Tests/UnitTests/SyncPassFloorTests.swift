//  SyncPassFloorTests.swift
//  Regression guard for the Mac UI stalling while the GitHub sync hammers.
//
//  Jon's log, tapping priorities in the Mac task detail:
//
//      GET  /api/v1/sync/github/task-links   219352 bytes
//      GET  /api/v1/sync/github/issues
//      PUT  /api/v1/sync/github/task-links
//      POST /api/v1/sync/github/issues
//      GET  /api/v1/sync/github/task-links   219352 bytes      … and round again, continuously
//
//  The taps themselves were fine — every `PRIODIAG` line shows the decision made and the write
//  enqueued — but the tap handler only ran AFTER that queue of requests. The passes decode
//  200-300KB payloads on the main actor, so a tap waits behind them, and it gets worse the
//  longer the app runs: "eventually it stalls".
//
//  `syncAll` re-arms itself in its own `defer` whenever a nudge arrived mid-pass, and a pass
//  makes local writes that nudge. `scheduleSync`'s 2s debounce does not bound that, because
//  each re-arm starts a fresh 2s timer rather than a fresh RATE.
//
//  So passes get a floor: however often it is asked, it may not START more than once per
//  interval. Nudges are not dropped — they wait for the floor to clear.

import XCTest
@testable import Astrid_App

final class SyncPassFloorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The first pass of a session is always allowed — nothing has run to be too soon after.
    func testTheFirstPassIsAllowed() {
        XCTAssertTrue(SyncPassFloor.mayStart(lastPassStarted: nil, now: now, floor: 30))
    }

    /// THE BUG: a pass that re-arms itself immediately must not start again immediately.
    func testAPassCannotStartAgainImmediately() {
        XCTAssertFalse(SyncPassFloor.mayStart(lastPassStarted: now, now: now, floor: 30),
                       "a re-armed pass starting at once is the loop that flooded the log")
        XCTAssertFalse(SyncPassFloor.mayStart(lastPassStarted: now,
                                              now: now.addingTimeInterval(2), floor: 30),
                       "the 2s debounce is not a rate — re-arming just restarts the timer")
    }

    /// Once the floor has passed, work resumes. This is a rate limit, not an off switch: a
    /// change made on GitHub still arrives, just not more often than the floor.
    func testAPassIsAllowedOnceTheFloorHasElapsed() {
        XCTAssertTrue(SyncPassFloor.mayStart(lastPassStarted: now,
                                             now: now.addingTimeInterval(30), floor: 30))
        XCTAssertTrue(SyncPassFloor.mayStart(lastPassStarted: now,
                                            now: now.addingTimeInterval(31), floor: 30))
    }

    /// How long to wait before the next pass may run, so a caller can re-arm ONCE at the right
    /// moment instead of spinning.
    func testItSaysHowLongToWait() {
        XCTAssertEqual(SyncPassFloor.delayUntilNextPass(lastPassStarted: now,
                                                        now: now.addingTimeInterval(10), floor: 30), 20)
        XCTAssertEqual(SyncPassFloor.delayUntilNextPass(lastPassStarted: nil, now: now, floor: 30), 0)
        XCTAssertEqual(SyncPassFloor.delayUntilNextPass(lastPassStarted: now,
                                                        now: now.addingTimeInterval(99), floor: 30), 0)
    }

    /// A clock that jumps backwards (NTP correction, timezone shift) must not lock sync out
    /// forever — the floor is a rate limit, not a trap.
    func testAClockGoingBackwardsDoesNotLockSyncOut() {
        XCTAssertTrue(SyncPassFloor.mayStart(lastPassStarted: now.addingTimeInterval(600),
                                             now: now, floor: 30),
                      "a future 'last pass' means the clock moved, not that a pass just ran")
    }
}
