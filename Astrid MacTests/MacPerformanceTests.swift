//  MacPerformanceTests.swift
//  Astrid for Mac — performance budgets for the hot paths (Tasks ecf8f61c, 1c21489d).
//
//  The `measure {}` blocks below RECORD timings; on their own they enforce nothing, because no
//  .xcbaseline is committed (an earlier version of this file claimed they failed CI — they did
//  not, and a 10x regression would have passed silently). The real gates are the ratio
//  assertions at the bottom: they compare the pipeline against itself, so they hold on any
//  machine and in CI, where absolute wall-clock numbers are meaningless.
//
//  The list pipeline (filter → sort → splice) is astrid-core's `rowsForList` on both platforms
//  since AITD-460, so its budgets moved to the iOS suite's `CoreRowsScalingTests` (AITD-539). What
//  stays here is the Mac's own hot path: the command palette's search.

import XCTest
@testable import Astrid_Mac

final class MacPerformanceTests: XCTestCase {

    private func makeTasks(_ n: Int) -> [Task] {
        (0..<n).map { i in
            var t = Task(id: "t\(i)", title: "Task number \(i) alpha beta", completed: i % 5 == 0)
            t.priority = Task.Priority(rawValue: i % 4) ?? .none
            t.dueDateTime = i % 3 == 0 ? Date().addingTimeInterval(Double(i) * 60) : nil
            t.assigneeId = i % 2 == 0 ? "me" : nil
            return t
        }
    }

    func testPaletteSearchOver10kTasks() {
        let tasks = makeTasks(10_000)
        measure { _ = MacPaletteSearch.matchingTasks("alpha", tasks: tasks, limit: 6) }
    }


    // MARK: - Enforced budgets (ratios, not wall-clock — machine-independent)

    /// Median wall time of `block`, to damp scheduler noise.
    /// The FASTEST of several runs, not the median (AITD-534). Load on a shared runner only ever
    /// adds time, so the fastest run is the one closest to what the code costs; a median still
    /// moved with whatever else the machine was doing, and the 2x-vs-4x ratios below flaked on it.
    private func fastestSeconds(iterations: Int = 9, _ block: () -> Void) -> Double {
        var fastest = Double.infinity
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            block()
            fastest = min(fastest, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000)
        }
        return fastest
    }

    // NOTE: there is deliberately NO "pipeline costs about one pass" gate. It was tried and it
    // does not work: the due-date filter shrinks the set before the sort, so one pipeline pass is
    // CHEAPER than sorting all 10k, and a 4x-passes regression still came in under the threshold
    // (verified by injecting exactly that regression). How often the core is asked is a view concern these
    // tests cannot observe: `ListRowsModel` asks once per change of the list or its tasks, never
    // per body evaluation (AITD-460).

    /// Palette search runs on every keystroke, so it must stay linear in the task count.
    func testPaletteSearchScalesLinearly() {
        let small = makeTasks(5_000), large = makeTasks(10_000)
        _ = MacPaletteSearch.matchingTasks("alpha", tasks: small, limit: 6)
        let t1 = fastestSeconds { _ = MacPaletteSearch.matchingTasks("alpha", tasks: small, limit: 6) }
        let t2 = fastestSeconds { _ = MacPaletteSearch.matchingTasks("alpha", tasks: large, limit: 6) }
        XCTAssertLessThan(t2, t1 * 3.2,
                          "Palette search cost \(t2 / max(t1, .leastNonzeroMagnitude))x for 2x the tasks — not linear")
    }
}
