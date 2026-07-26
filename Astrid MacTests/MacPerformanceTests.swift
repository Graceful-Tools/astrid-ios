//  MacPerformanceTests.swift
//  Astrid for Mac — performance budgets for the hot paths (Tasks ecf8f61c, 1c21489d).
//
//  The `measure {}` blocks below RECORD timings; on their own they enforce nothing, because no
//  .xcbaseline is committed (an earlier version of this file claimed they failed CI — they did
//  not, and a 10x regression would have passed silently). The real gates are the ratio
//  assertions at the bottom: they compare the pipeline against itself, so they hold on any
//  machine and in CI, where absolute wall-clock numbers are meaningless.

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

    func testSortOver10kTasks() {
        let tasks = makeTasks(10_000)
        measure { _ = sortTasksByListSetting(tasks, sortBy: "auto", manualOrder: nil) }
    }

    func testDueDateFilterOver10kTasks() {
        let tasks = makeTasks(10_000)
        measure { _ = applyListDueDateFilter(tasks, filter: "today") }
    }

    func testMyTasksAggregationOver10kTasks() {
        let tasks = makeTasks(10_000)
        measure { _ = MacMyTasks.filter(tasks, userId: "me") }
    }

    /// The COMPOSED per-render pipeline (sort → splice with subtasks) at 10k — the actual work
    /// MacRootView does per body eval. Budgeted as a single pass now that rows are computed once
    /// per eval (Task 4e0ce183); a regression to multiple passes shows up as a multiple here.
    func testComposedSortSpliceOver10kTasks() {
        var tasks = makeTasks(10_000)
        // Give a third of tasks a parent (subtask splice shape).
        for i in stride(from: 2, to: tasks.count, by: 3) { tasks[i].parentTaskId = tasks[i - 1].id }
        measure {
            let sorted = sortTasksByListSetting(tasks, sortBy: "auto", manualOrder: nil)
            _ = spliceSubtasks(topLevel: sorted.filter { $0.parentTaskId == nil },
                               allTasks: tasks, indented: true, subtaskVisible: { !$0.completed })
        }
    }

    /// FULL composed pipeline (due-date filter → sort → splice) at 10k with a subtask-heavy shape —
    /// the complete per-render cost (Task 1c21489d).
    func testFullFilterSortSplicePipelineOver10kTasks() {
        var tasks = makeTasks(10_000)
        for i in stride(from: 1, to: tasks.count, by: 2) { tasks[i].parentTaskId = tasks[i - 1].id }
        measure {
            let filtered = applyListDueDateFilter(tasks, filter: "this_week")
            let sorted = sortTasksByListSetting(filtered, sortBy: "auto", manualOrder: nil)
            _ = spliceSubtasks(topLevel: sorted.filter { $0.parentTaskId == nil },
                               allTasks: tasks, indented: true, subtaskVisible: { !$0.completed })
        }
    }

    // MARK: - Enforced budgets (ratios, not wall-clock — machine-independent)

    /// Median wall time of `block`, to damp scheduler noise.
    private func medianSeconds(iterations: Int = 7, _ block: () -> Void) -> Double {
        var times: [Double] = []
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            block()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000)
        }
        return times.sorted()[times.count / 2]
    }

    private func pipeline(_ tasks: [Task]) {
        let filtered = applyListDueDateFilter(tasks, filter: "this_week")
        let sorted = sortTasksByListSetting(filtered, sortBy: "auto", manualOrder: nil)
        _ = spliceSubtasks(topLevel: sorted.filter { $0.parentTaskId == nil },
                           allTasks: tasks, indented: true, subtaskVisible: { !$0.completed })
    }

    private func withSubtasks(_ n: Int, every k: Int = 2) -> [Task] {
        var tasks = makeTasks(n)
        for i in stride(from: 1, to: tasks.count, by: k) { tasks[i].parentTaskId = tasks[i - 1].id }
        return tasks
    }

    /// Doubling the task count must not quadruple the cost. Quadratic behaviour — the classic
    /// regression here is a splice that rescans all tasks per parent — lands near 4x; sort-bound
    /// n log n lands near 2.1x. Fails well before users feel it.
    func testComposedPipelineScalesSubQuadratically() {
        let small = withSubtasks(5_000), large = withSubtasks(10_000)
        pipeline(small); pipeline(large)                      // warm caches, ignore first runs
        let t1 = medianSeconds { self.pipeline(small) }
        let t2 = medianSeconds { self.pipeline(large) }
        XCTAssertLessThan(t2, t1 * 3.2,
                          "Doubling to 10k cost \(t2 / max(t1, .leastNonzeroMagnitude))x — quadratic behaviour in the pipeline")
    }

    // NOTE: there is deliberately NO "pipeline costs about one pass" gate. It was tried and it
    // does not work: the due-date filter shrinks the set before the sort, so one pipeline pass is
    // CHEAPER than sorting all 10k, and a 4x-passes regression still came in under the threshold
    // (verified by injecting exactly that regression). How many times the view evaluates the
    // pipeline per render is a view concern these pure tests cannot observe — MacRowPipeline's
    // "compute rows once" contract is enforced by MacRowPipelineTests instead.

    /// A subtask-heavy list (every task a child of the previous) must not blow up relative to a
    /// flat list of the same size — the splice is the part that can go quadratic.
    func testSubtaskHeavyShapeStaysLinearRelativeToFlat() {
        let flat = makeTasks(10_000)
        let nested = withSubtasks(10_000, every: 1)
        pipeline(flat); pipeline(nested)
        let tFlat = medianSeconds { self.pipeline(flat) }
        let tNested = medianSeconds { self.pipeline(nested) }
        XCTAssertLessThan(tNested, tFlat * 6.0,
                          "Subtask-heavy shape cost \(tNested / max(tFlat, .leastNonzeroMagnitude))x the flat shape — splice is not scaling")
    }

    /// Palette search runs on every keystroke, so it must stay linear in the task count.
    func testPaletteSearchScalesLinearly() {
        let small = makeTasks(5_000), large = makeTasks(10_000)
        _ = MacPaletteSearch.matchingTasks("alpha", tasks: small, limit: 6)
        let t1 = medianSeconds { _ = MacPaletteSearch.matchingTasks("alpha", tasks: small, limit: 6) }
        let t2 = medianSeconds { _ = MacPaletteSearch.matchingTasks("alpha", tasks: large, limit: 6) }
        XCTAssertLessThan(t2, t1 * 3.2,
                          "Palette search cost \(t2 / max(t1, .leastNonzeroMagnitude))x for 2x the tasks — not linear")
    }
}
