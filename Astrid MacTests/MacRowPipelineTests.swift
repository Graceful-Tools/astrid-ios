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

    /// A REAL LIST'S OWN SORT ALWAYS WINS (AITD-389).
    ///
    /// This used to assert the opposite — "a per-window override must win over the list's saved
    /// sort" — which was true before task 2b886104 made a real list's sort persist and sync, and
    /// was never revisited afterwards. The result: pick a sort on My Tasks, walk to a real list,
    /// and your device-local override silently reordered a list whose sort every member shares.
    /// The toolbar menu made it worse by reading `list.sortBy` — so the control showed one sort
    /// while the rows were in another.
    ///
    /// The override exists for selections that own no list row to write to. That is the whole of
    /// its job.
    func testARealListsOwnSortBeatsTheLocalOverride() {
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "priority", list: list(sortBy: "when")),
                       "when",
                       "AITD-389: the list's shared sort is authoritative, not a per-window override")
    }

    /// The ambiguity that made the bug hard to see: a real list with NO sort set and no list at
    /// all both used to arrive as `listSortBy: nil`, so the rule could not tell them apart.
    func testAListWithNoSortIsStillAListNotAnAbsentOne() {
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "priority", list: list(sortBy: nil)),
                       "auto",
                       "AITD-389: a list that has never set a sort still outranks the override")
    }

    /// What the override is actually for.
    func testTheOverrideAppliesWhenThereIsNoList() {
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "priority", list: nil), "priority")
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "", list: nil), "auto")
    }

    func testEffectiveSortKeyFallbackChain() {
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "", list: list(sortBy: "when")), "when")
        XCTAssertEqual(MacRowPipeline.effectiveSortKey(override: "", list: nil), "auto")
    }

    private func list(sortBy: String?) -> TaskList {
        var l = TaskList(id: "l1", name: "Work", privacy: .PRIVATE)
        l.sortBy = sortBy
        return l
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
