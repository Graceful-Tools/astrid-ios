//  Astrid_MacTests.swift
//  Astrid MacTests — shared-layer smoke tests (Task df40c2e9).
//  Replaces the empty Xcode template tests. Broader coverage lives in the focused suites
//  (MacTaskDetailUpdate, MacFeatureFlagGating, MacQuickAdd, MacCommandDispatch, MacRuntime,
//  MacPaletteSearch, MacDeepLink, MacCustomRepeat, MacErrorCenter, MacMyTasks, MacBoardMove,
//  MacTaskVisuals, MacListTaskFiltering, SharedServiceLayer, …).

import XCTest
@testable import Astrid_Mac

final class Astrid_MacTests: XCTestCase {

    /// The shared singletons the Mac app depends on are reachable from the Mac target.
    func testSharedServicesReachableOnMac() {
        XCTAssertNotNil(TaskService.shared)
        XCTAssertNotNil(ListService.shared)
        XCTAssertNotNil(AuthManager.shared)
        XCTAssertNotNil(SyncManager.shared)
        XCTAssertNotNil(FeatureFlagService.shared)
    }

    /// The shared Task model round-trips through Codable on macOS (wire-shape parity with iOS/web).
    func testTaskCodableRoundTripsOnMac() throws {
        var t = Task(id: "t1", title: "Round trip", completed: false)
        t.priority = .high
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Task.self, from: data)
        XCTAssertEqual(decoded.id, "t1")
        XCTAssertEqual(decoded.title, "Round trip")
        XCTAssertEqual(decoded.priority, .high)
    }
}
