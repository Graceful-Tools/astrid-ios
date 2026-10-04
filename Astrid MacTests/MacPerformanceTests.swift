//  MacPerformanceTests.swift
//  Astrid for Mac — performance budgets for the hot paths (Tasks ecf8f61c, 1c21489d).
//
//  The `measure {}` blocks below RECORD timings; on their own they enforce nothing, because no
//  .xcbaseline is committed (an earlier version of this file claimed they failed CI — they did
//  not, and a 10x regression would have passed silently). The real gates are the ratio
//  assertions at the bottom: they compare the pipeline against itself, so they hold on any
//  machine and in CI, where absolute wall-clock numbers are meaningless.
//
//  Since AITD-460 the list pipeline (filter → sort → splice) is astrid-core's `rowsForList`, so
//  the pipeline budgets below measure one core call over a seeded cache — what a list costs each
//  time its rows are asked for — rather than the Swift copies, which are gone.

import AstridCore
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

    /// One list's rows from the core: the due-date filter, the sort and the subtask splice.
    private func rows(_ session: CoreSession, due: String = "this_week", sortBy: String = "auto",
                      indented: Bool = true) {
        var shape = TaskList(id: "everything", name: "")
        shape.isVirtual = true
        shape.filterCompletion = "incomplete"
        shape.filterDueDate = due
        shape.sortBy = sortBy
        let query = ListRowsModel.Query(listId: shape.id, list: shape,
                                        subtaskDisplay: indented ? "indented" : "under_parent",
                                        currentUserId: "me")
        _ = try? CoreRowsFixture.wait(session, ListRowsModel.command(for: query), as: CoreRowsFixture.Answer.self)
    }

    func testSortOver10kTasks() throws {
        let session = try CoreSearchFixture.session(seeding: makeTasks(10_000))
        measure { rows(session, due: "all", indented: false) }
    }

    func testDueDateFilterOver10kTasks() throws {
        let session = try CoreSearchFixture.session(seeding: makeTasks(10_000))
        measure { rows(session, due: "today", indented: false) }
    }

    func testMyTasksAggregationOver10kTasks() throws {
        let session = try CoreSearchFixture.session(seeding: makeTasks(10_000))
        let query = ListRowsModel.Query(listId: ListRowsModel.myTasksId, myTasks: MyTasksPreferences(),
                                        subtaskDisplay: "indented", currentUserId: "me")
        measure { _ = try? CoreRowsFixture.wait(session, ListRowsModel.command(for: query), as: CoreRowsFixture.Answer.self) }
    }

    /// The COMPOSED pipeline (sort → splice with subtasks) at 10k — what one ask of the core for a
    /// list's rows costs.
    func testComposedSortSpliceOver10kTasks() throws {
        var tasks = makeTasks(10_000)
        // Give a third of tasks a parent (subtask splice shape).
        for i in stride(from: 2, to: tasks.count, by: 3) { tasks[i].parentTaskId = tasks[i - 1].id }
        let session = try CoreSearchFixture.session(seeding: tasks)
        measure { rows(session, due: "all") }
    }

    /// FULL composed pipeline (due-date filter → sort → splice) at 10k with a subtask-heavy shape —
    /// the complete per-ask cost (Task 1c21489d).
    func testFullFilterSortSplicePipelineOver10kTasks() throws {
        let session = try CoreSearchFixture.session(seeding: withSubtasks(10_000))
        measure { rows(session) }
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

    private func withSubtasks(_ n: Int, every k: Int = 2) -> [Task] {
        var tasks = makeTasks(n)
        for i in stride(from: 1, to: tasks.count, by: k) { tasks[i].parentTaskId = tasks[i - 1].id }
        return tasks
    }

    /// Doubling the task count must not quadruple the cost. Quadratic behaviour — the classic
    /// regression here is a splice that rescans all tasks per parent — lands near 4x; sort-bound
    /// n log n lands near 2.1x. Fails well before users feel it.
    func testComposedPipelineScalesSubQuadratically() throws {
        let small = try CoreSearchFixture.session(seeding: withSubtasks(5_000))
        let large = try CoreSearchFixture.session(seeding: withSubtasks(10_000))
        rows(small); rows(large)                              // warm caches, ignore first runs
        let t1 = medianSeconds { self.rows(small) }
        let t2 = medianSeconds { self.rows(large) }
        XCTAssertLessThan(t2, t1 * 3.2,
                          "Doubling to 10k cost \(t2 / max(t1, .leastNonzeroMagnitude))x — quadratic behaviour in the pipeline")
    }

    // NOTE: there is deliberately NO "pipeline costs about one pass" gate. It was tried and it
    // does not work: the due-date filter shrinks the set before the sort, so one pipeline pass is
    // CHEAPER than sorting all 10k, and a 4x-passes regression still came in under the threshold
    // (verified by injecting exactly that regression). How often the core is asked is a view concern these
    // tests cannot observe: `ListRowsModel` asks once per change of the list or its tasks, never
    // per body evaluation (AITD-460).

    /// A subtask-heavy list (every task a child of the previous) must not blow up relative to a
    /// flat list of the same size — the splice is the part that can go quadratic.
    func testSubtaskHeavyShapeStaysLinearRelativeToFlat() throws {
        let flat = try CoreSearchFixture.session(seeding: makeTasks(10_000))
        let nested = try CoreSearchFixture.session(seeding: withSubtasks(10_000, every: 1))
        rows(flat); rows(nested)
        let tFlat = medianSeconds { self.rows(flat) }
        let tNested = medianSeconds { self.rows(nested) }
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
