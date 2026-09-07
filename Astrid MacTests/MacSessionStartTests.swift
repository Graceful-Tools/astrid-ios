//  MacSessionStartTests.swift
//  Astrid for Mac — Task 0e0bcf69 (AITD-315): post-auth startup runs once per session.
//
//  `MacAuthGateView` reaches `startSession()` down two paths at cold launch, and with a stored
//  session it took both: `checkAuthentication()` flips `isAuthenticated`, which fires `.onChange`
//  → `startSession()`, and then the enclosing `.task` resumes and calls it again on the next line.
//  Two `performFullSync(includeUserTasks:)` passes, and since both are user-initiated the second
//  waits for the first and then runs the entire pull again — plus two GitHub status fetches and two
//  sync schedules, before the user can do anything.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

@MainActor
final class MacSessionStartTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MacSessionStart.release()   // a fresh process has not started a session
    }

    override func tearDown() {
        MacSessionStart.release()
        super.tearDown()
    }

    // MARK: - The bug

    func testTheSecondCallerAtColdLaunchDoesNotStartASecondSession() {
        // The two launch paths, in the order they actually fire: onChange first, then the .task
        // resuming on the next line.
        XCTAssertTrue(MacSessionStart.claim(), "the first caller owns the launch")
        XCTAssertFalse(MacSessionStart.claim(),
                       "the second caller must not run a second full sync (AITD-315)")
    }

    func testOnlyOneOfManyCallersEverWins() {
        let winners = (0..<25).filter { _ in MacSessionStart.claim() }
        XCTAssertEqual(winners.count, 1)
    }

    func testTheOppositeCallOrderBehavesIdentically() {
        // Whichever path arrives first should own it — the fix must not depend on which one that
        // is, because deleting a call site would have.
        XCTAssertTrue(MacSessionStart.claim())
        XCTAssertFalse(MacSessionStart.claim())
        MacSessionStart.release()
        XCTAssertTrue(MacSessionStart.claim())
    }

    // MARK: - Sign-out has to re-arm it

    func testSigningOutReArmsSoTheNextSignInStartsASession() {
        XCTAssertTrue(MacSessionStart.claim())
        MacSessionStart.release()
        XCTAssertTrue(MacSessionStart.claim(),
                      "signing out and back in must bring SSE and the sync timer back")
    }

    func testReleasingWhenNothingStartedIsHarmless() {
        MacSessionStart.release()
        MacSessionStart.release()
        XCTAssertTrue(MacSessionStart.claim())
    }

    func testHasStartedReflectsTheLatch() {
        XCTAssertFalse(MacSessionStart.hasStarted)
        _ = MacSessionStart.claim()
        XCTAssertTrue(MacSessionStart.hasStarted)
        MacSessionStart.release()
        XCTAssertFalse(MacSessionStart.hasStarted)
    }

    // MARK: - The guard: the gate must actually go through the latch

    func testStartSessionIsLatchedAndSignOutReleasesIt() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Astrid MacTests
            .deletingLastPathComponent()    // repo root
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid Mac/App/MacAuthGateView.swift"),
            encoding: .utf8)

        XCTAssertTrue(source.contains("MacSessionStart.claim()"),
                      "startSession() must claim the launch latch, or both cold-launch paths run it")
        XCTAssertTrue(source.contains("MacSessionStart.release()"),
                      "sign-out must re-arm the latch, or signing back in gets no SSE and no sync")
    }

    /// The claim must stay a check-and-set with nothing awaited in between. An `await` there is
    /// exactly what would let both launch paths through again.
    func testTheClaimHasNoSuspensionPointInsideIt() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid Mac/App/MacSessionStart.swift"),
            encoding: .utf8)

        let lines = source.components(separatedBy: .newlines)
        let start = try XCTUnwrap(lines.firstIndex { $0.contains("static func claim()") })
        let end = try XCTUnwrap(lines[(start + 1)...].firstIndex { $0.hasSuffix("    }") })
        let body = lines[start...end].joined(separator: "\n")

        XCTAssertFalse(body.contains("await"),
                       "an await between the check and the set lets both launch paths win")
    }
}
#endif
