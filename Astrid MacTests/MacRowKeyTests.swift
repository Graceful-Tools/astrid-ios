//  MacRowKeyTests.swift
//  Regression tests for Task e949df82 — "[mac] task list allocates an id array on every render".
//
//  MacRootView used `rows.map(\.id)` as the value for BOTH `.animation(value:)` and
//  `.onChange(of:)`, so every body evaluation allocated a fresh [String] of every visible row —
//  on the hottest path in the app, growing with list size. MacRowKey hashes the same information
//  without materialising anything, and must still change for every edit the animation cares about.

import XCTest
@testable import Astrid_Mac

final class MacRowKeyTests: XCTestCase {

    private func tasks(_ ids: [String]) -> [Task] {
        ids.map { Task(id: $0, title: "T\($0)", listIds: ["l"]) }
    }

    func testSameRowsGiveTheSameKey() {
        XCTAssertEqual(MacRowKey.key(tasks(["a", "b", "c"])), MacRowKey.key(tasks(["a", "b", "c"])))
    }

    /// Insert, delete and REORDER must all move the key, or rows animate in and out of the wrong
    /// places. Reorder is the one a count+first+last shortcut would miss.
    func testEveryStructuralChangeMovesTheKey() {
        let base = MacRowKey.key(tasks(["a", "b", "c"]))
        XCTAssertNotEqual(base, MacRowKey.key(tasks(["a", "b", "c", "d"])), "insert")
        XCTAssertNotEqual(base, MacRowKey.key(tasks(["a", "c"])), "delete")
        XCTAssertNotEqual(base, MacRowKey.key(tasks(["a", "c", "b"])), "reorder (middle swap)")
        XCTAssertNotEqual(base, MacRowKey.key(tasks(["a", "b", "z"])), "replace")
    }

    /// Editing a title changes no row identity, so the list must not re-run its insert/delete
    /// animation for it.
    func testEditingAFieldLeavesTheKeyAlone() {
        var edited = tasks(["a", "b", "c"])
        edited[1].title = "renamed"
        edited[1].priority = .high
        XCTAssertEqual(MacRowKey.key(tasks(["a", "b", "c"])), MacRowKey.key(edited))
    }

    func testEmptyAndSingleRowAreDistinct() {
        XCTAssertNotEqual(MacRowKey.key([]), MacRowKey.key(tasks(["a"])))
    }

    /// The win here is the ALLOCATION, not raw CPU: `rows.map(\.id)` only copies string
    /// references, so hashing their bytes is not automatically faster. What the key must be is
    /// LINEAR — one pass, no accidental n² — because it runs on every body evaluation.
    func testKeyCostStaysLinearInRowCount() {
        func median(_ rows: [Task]) -> Double {
            var times: [Double] = []
            for _ in 0..<9 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = MacRowKey.key(rows)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start))
            }
            return times.sorted()[times.count / 2]
        }
        let small = median(tasks((0..<5_000).map { "id-\($0)" }))
        let large = median(tasks((0..<10_000).map { "id-\($0)" }))
        // Linear lands near 2x; quadratic near 4x. 3x fails well before users feel it.
        XCTAssertLessThan(large / max(small, 1), 3.0,
                          "Doubling the rows took \(large / max(small, 1))x — the key is not linear")
    }

    /// …and what it hands SwiftUI is a single Int, so the per-render COMPARISON is O(1) instead of
    /// walking an id array. That is the churn this task is about.
    func testKeyIsAScalar() {
        XCTAssertEqual(MemoryLayout.size(ofValue: MacRowKey.key(tasks(["a", "b", "c"]))),
                       MemoryLayout<Int>.size)
    }
}
