//  CoreRowsScalingTests.swift
//  The list pipeline must stay sub-quadratic (Tasks ecf8f61c, 1c21489d; moved from the Mac suite,
//  AITD-539).
//
//  Since AITD-460 a list's rows are astrid-core's `rowsForList` on BOTH platforms, so these budgets
//  belong to the shared code and run once, here. They compare the pipeline against itself — 2x the
//  tasks must cost about 2x, not 4x — so they hold on any machine, and they time the fastest of
//  nine runs because load only ever adds time (AITD-534).

import AstridCore
import XCTest
@testable import Astrid_App

final class CoreRowsScalingTests: XCTestCase {


    private func makeTasks(_ n: Int) -> [Task] {
        (0..<n).map { i in
            var t = Task(id: "t\(i)", title: "Task number \(i) alpha beta", completed: i % 5 == 0)
            t.priority = Task.Priority(rawValue: i % 4) ?? .none
            t.dueDateTime = i % 3 == 0 ? Date().addingTimeInterval(Double(i) * 60) : nil
            t.assigneeId = i % 2 == 0 ? "me" : nil
            return t
        }
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
        let t1 = fastestSeconds { self.rows(small) }
        let t2 = fastestSeconds { self.rows(large) }
        XCTAssertLessThan(t2, t1 * 3.2,
                          "Doubling to 10k cost \(t2 / max(t1, .leastNonzeroMagnitude))x — quadratic behaviour in the pipeline")
    }


    /// A subtask-heavy list (every task a child of the previous) must not blow up relative to a
    /// flat list of the same size — the splice is the part that can go quadratic.
    func testSubtaskHeavyShapeStaysLinearRelativeToFlat() throws {
        let flat = try CoreSearchFixture.session(seeding: makeTasks(10_000))
        let nested = try CoreSearchFixture.session(seeding: withSubtasks(10_000, every: 1))
        rows(flat); rows(nested)
        let tFlat = fastestSeconds { self.rows(flat) }
        let tNested = fastestSeconds { self.rows(nested) }
        XCTAssertLessThan(tNested, tFlat * 6.0,
                          "Subtask-heavy shape cost \(tNested / max(tFlat, .leastNonzeroMagnitude))x the flat shape — splice is not scaling")
    }
}
