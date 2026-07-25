//  MacRowPipelineTests.swift
//  Astrid for Mac — Task 0b1ee8f7: the previously-untested view-composition glue, now pure.
//  Covers: sort-override fallback, splice completion mapping + top-level prefilter, and the
//  j/k selection index math (clamping + empty-selection entry points).

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacRowPipelineTests: XCTestCase {

    private func task(_ id: String, priority: Task.Priority = .none, parent: String? = nil,
                      completed: Bool = false, created: TimeInterval = 0) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.priority = priority
        t.parentTaskId = parent
        t.createdAt = Date(timeIntervalSince1970: created)
        return t
    }

    // MARK: sort-override fallback (G1)

    func testEffectiveSortKeyFallbackChain() {
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "priority", listSortBy: "when"), "priority",
                       "A per-window override must win over the list's saved sort")
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "", listSortBy: "when"), "when")
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "", listSortBy: nil), "auto")
    }

    func testVirtualSelectionSortsWithOverride() {
        // No list (My Tasks/Search): override applies, priority ordering enforced.
        let rows = MacRowPipeline.displayed(base: [task("low", priority: .low), task("high", priority: .high)],
                                            list: nil, override: "priority", currentUserId: "me")
        XCTAssertEqual(rows.map(\.id), ["high", "low"])
    }

    // MARK: splice completion mapping + prefilter (G2)

    func testShowsCompletedSubtasksMapping() {
        XCTAssertTrue(MacRowPipeline.showsCompletedSubtasks(filterCompletion: "all"))
        XCTAssertTrue(MacRowPipeline.showsCompletedSubtasks(filterCompletion: "completed"))
        XCTAssertFalse(MacRowPipeline.showsCompletedSubtasks(filterCompletion: "default"))
        XCTAssertFalse(MacRowPipeline.showsCompletedSubtasks(filterCompletion: "incomplete"))
        XCTAssertFalse(MacRowPipeline.showsCompletedSubtasks(filterCompletion: nil))
    }

    func testRenderedSplicesAndPrefiltersTopLevel() {
        let parent = task("p"), subDone = task("s1", parent: "p", completed: true, created: 1)
        let subOpen = task("s2", parent: "p", created: 2)
        // A subtask sneaking into `displayed` must be prefiltered (only top-level rows splice).
        let displayed = [parent, subOpen]
        let all = [parent, subDone, subOpen]

        let defaultRows = MacRowPipeline.rendered(displayed: displayed, allTasks: all,
                                                  indented: true, filterCompletion: "default")
        XCTAssertEqual(defaultRows.map(\.id), ["p", "s2"], "Completed subtask hidden under 'default'")

        let allRows = MacRowPipeline.rendered(displayed: displayed, allTasks: all,
                                              indented: true, filterCompletion: "all")
        XCTAssertEqual(allRows.map(\.id), ["p", "s1", "s2"], "'all' shows the completed subtask")

        let underParent = MacRowPipeline.rendered(displayed: displayed, allTasks: all,
                                                  indented: false, filterCompletion: "all")
        XCTAssertEqual(underParent.map(\.id), ["p"], "under_parent mode hides subtasks from the list")
    }

    // MARK: j/k selection math (G7)

    func testNextSelectionClampsAndEnters() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(MacRowPipeline.nextSelection(orderedIds: ids, current: "a", direction: 1), "b")
        XCTAssertEqual(MacRowPipeline.nextSelection(orderedIds: ids, current: "c", direction: 1), "c", "Clamped at end")
        XCTAssertEqual(MacRowPipeline.nextSelection(orderedIds: ids, current: "a", direction: -1), "a", "Clamped at start")
        XCTAssertEqual(MacRowPipeline.nextSelection(orderedIds: ids, current: nil, direction: 1), "a", "Down enters at top")
        XCTAssertEqual(MacRowPipeline.nextSelection(orderedIds: ids, current: nil, direction: -1), "c", "Up enters at bottom")
        XCTAssertNil(MacRowPipeline.nextSelection(orderedIds: [], current: nil, direction: 1))
        // Unknown current id (stale selection) re-enters like no selection.
        XCTAssertEqual(MacRowPipeline.nextSelection(orderedIds: ids, current: "zz", direction: 1), "a")
    }
}
#endif
