//  CoreRowsScalingTests.swift
//  The list pipeline must stay sub-quadratic (Tasks ecf8f61c, 1c21489d; moved from the Mac suite,
//  AITD-539).
//
//  Since AITD-460 a list's rows are astrid-core's `rowsForList` on BOTH platforms, so these budgets
//  belong to the shared code and run once, here. They compare the pipeline against itself — 2x the
//  tasks must cost about 2x, not 4x — so they hold on any machine.
//
//  How they are timed (ADEV-5): the PROCESS's CPU time, not wall time, over interleaved runs of the
//  two sizes, the fastest of each. Wall time failed three predeploys in a row on 2026-11-15 (9.3x,
//  3.9x, 3.7x against 3.2x) and passed every time alone: xcodebuild's parallel clones are separate
//  processes competing for the same cores, so they stretched wall time, and timing all of one size
//  before the other let a busy stretch land on one size only. CPU time leaves out what other
//  processes take; interleaving gives what is left to both sizes alike.

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


    /// This process's CPU time so far, user + system. Other processes, the parallel test clones
    /// among them, cannot add to it, which is what wall time got wrong (ADEV-5). The core works on
    /// its own threads, so the calling thread's CPU time would miss the work: it is the process's.
    static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// The fastest CPU cost of `a` and of `b`, measured in turns — a, b, a, b… — so any stretch of
    /// noise reaches both, and fastest because noise only ever adds (AITD-534, ADEV-5).
    static func fastestInterleaved(iterations: Int = 9, cost: () -> Double = processCPUSeconds,
                                   _ a: () -> Void, _ b: () -> Void) -> (a: Double, b: Double) {
        var fastestA = Double.infinity, fastestB = Double.infinity
        for _ in 0..<iterations {
            let startA = cost(); a(); fastestA = min(fastestA, cost() - startA)
            let startB = cost(); b(); fastestB = min(fastestB, cost() - startB)
        }
        return (fastestA, fastestB)
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
        let (t1, t2) = Self.fastestInterleaved({ self.rows(small) }, { self.rows(large) })
        XCTAssertLessThan(t2, t1 * 3.2,
                          "Doubling to 10k cost \(t2 / max(t1, .leastNonzeroMagnitude))x — quadratic behaviour in the pipeline")
    }


    /// A subtask-heavy list (every task a child of the previous) must not blow up relative to a
    /// flat list of the same size — the splice is the part that can go quadratic.
    func testSubtaskHeavyShapeStaysLinearRelativeToFlat() throws {
        let flat = try CoreSearchFixture.session(seeding: makeTasks(10_000))
        let nested = try CoreSearchFixture.session(seeding: withSubtasks(10_000, every: 1))
        rows(flat); rows(nested)
        let (tFlat, tNested) = Self.fastestInterleaved({ self.rows(flat) }, { self.rows(nested) })
        XCTAssertLessThan(tNested, tFlat * 6.0,
                          "Subtask-heavy shape cost \(tNested / max(tFlat, .leastNonzeroMagnitude))x the flat shape — splice is not scaling")
    }

    // MARK: - The measurement itself (ADEV-5)

    /// Interleaved: a stretch of noise during one size's turn cannot settle on that size alone. A
    /// clock that adds a burst of 1.0 to whichever run is in progress on turns 2–4 (the old shape,
    /// "all the small runs, then all the large ones", gave the large size every burst) still yields
    /// each block's true cost as its fastest.
    func testInterleavedRunsLetNoiseReachBothSizes_ADEV5() {
        var clock = 0.0, turn = 0
        let measured = Self.fastestInterleaved(iterations: 6, cost: { clock },
            { turn += 1; clock += 0.010 + ((2...4).contains(turn) ? 1.0 : 0) },
            { turn += 1; clock += 0.020 + ((2...4).contains(turn) ? 1.0 : 0) })
        XCTAssertEqual(measured.a, 0.010, accuracy: 1e-9)
        XCTAssertEqual(measured.b, 0.020, accuracy: 1e-9)
    }

    /// The process clock counts work done on other threads too (the core's), and never runs
    /// backwards.
    func testTheProcessCPUClockCountsWorkOnOtherThreads_ADEV5() {
        let start = Self.processCPUSeconds()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var x = 0.0
            for i in 0..<5_000_000 { x += Double(i).squareRoot() }
            if x < 0 { print(x) }
            done.signal()
        }
        done.wait()
        XCTAssertGreaterThan(Self.processCPUSeconds() - start, 0.001,
                             "busy work on another thread shows up in the process's CPU time")
    }
}
