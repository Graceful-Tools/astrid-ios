//  SubtaskDepthTests.swift
//  `subtaskDepth` (Core/Filters/SubtaskDepth.swift) — the only test of it lived in the Mac suite
//  until AITD-539 moved it here. The splice tests it sat beside duplicated the iOS suite's.

import XCTest
@testable import Astrid_App

final class SubtaskDepthTests: XCTestCase {

    private func task(_ id: String, parent: String? = nil) -> Task {
        var t = Task(id: id, title: id, completed: false)
        t.parentTaskId = parent
        return t
    }

    func testDepth() {
        let a = task("a"); let a1 = task("a1", parent: "a"); let a1x = task("a1x", parent: "a1")
        let byId = ["a": a, "a1": a1, "a1x": a1x]
        XCTAssertEqual(subtaskDepth(a, byId: byId), 0)
        XCTAssertEqual(subtaskDepth(a1, byId: byId), 1)
        XCTAssertEqual(subtaskDepth(a1x, byId: byId), 2)
    }
}
