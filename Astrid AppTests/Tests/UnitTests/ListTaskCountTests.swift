//  ListTaskCountTests.swift
//  Regression guard for AITD-414 — "Offline Astrid has 0" for the per-list counts in the left
//  side menu.
//
//  `ListSidebarView` decided membership with `task.lists?.contains { $0.id == list.id }` — the
//  HYDRATED list objects. `CDTask.toDomainModel()` restores `listIds` and sets `lists: nil`, so
//  after a cold launch with no network every task was present, every task knew its list ids, and
//  the sidebar asked the one field that had not survived. Every regular list badged 0.
//
//  The rule now lives in `Core/Lists/ListTaskCount.swift`, promoted from the Mac's
//  `MacListCount`, which had already got this right. These are iOS's guards on the shared rule;
//  `MacListCountTests` covers the same rule through the Mac's forwarder.

import XCTest
@testable import Astrid_App

final class ListTaskCountTests: XCTestCase {

    private func task(_ id: String, listIds: [String]? = nil, lists: [TaskList]? = nil,
                      completed: Bool = false) -> Task {
        var t = Task(id: id, title: "Task \(id)", completed: completed)
        t.listIds = listIds
        t.lists = lists
        return t
    }

    private func list(_ id: String = "list-1", virtual: Bool = false) -> TaskList {
        var l = TaskList(id: id, name: "Work")
        l.isVirtual = virtual
        l.filterCompletion = "all"
        return l
    }

    // MARK: - THE BUG

    /// THE OFFLINE SHAPE: a task rehydrated from CoreData carries `listIds` and NOTHING in
    /// `lists`. This is the whole of AITD-414 — counting by the hydrated objects alone made
    /// every sidebar badge read 0 as soon as the app was launched without a network.
    func testAITD414TaskWithOnlyListIdsIsCounted() {
        let offlineShape = [task("a", listIds: ["list-1"]), task("b", listIds: ["list-1"])]

        XCTAssertEqual(ListTaskCount.count(offlineShape, list: list(), currentUserId: nil), 2,
                       "offline every list in the sidebar badged 0 — the whole task")
    }

    /// The other representation still counts: a task that arrived hydrated but without ids
    /// (some API responses embed `lists` only) must not vanish from the badge either.
    func testATaskWithOnlyHydratedListsIsCounted() {
        XCTAssertEqual(
            ListTaskCount.count([task("a", lists: [list()])], list: list(), currentUserId: nil), 1)
    }

    /// Both representations on one task is the COMMON case online — count it once.
    func testATaskCarryingBothRepresentationsCountsOnce() {
        let both = task("a", listIds: ["list-1"], lists: [list()])

        XCTAssertEqual(ListTaskCount.count([both], list: list(), currentUserId: nil), 1)
        XCTAssertEqual(ListTaskCount.counts([both], lists: [list()], currentUserId: nil)["list-1"], 1,
                       "the batch pass double-counted a task that carried both")
    }

    // MARK: - The rules the badge already had

    /// The point of the badge: how much is LEFT, so completed tasks do not count.
    func testCountsOnlyIncompleteTasks() {
        let tasks = [task("a", listIds: ["list-1"]),
                     task("b", listIds: ["list-1"], completed: true)]

        XCTAssertEqual(ListTaskCount.count(tasks, list: list(), currentUserId: nil), 1)
    }

    func testIgnoresTasksInOtherLists() {
        let tasks = [task("a", listIds: ["list-1"]), task("b", listIds: ["other"])]

        XCTAssertEqual(ListTaskCount.count(tasks, list: list(), currentUserId: nil), 1)
    }

    /// A public list's membership is not fully local, so the server's number wins.
    func testAPublicListTrustsTheServerCount() {
        var publicList = list()
        publicList.privacy = .PUBLIC
        publicList.taskCount = 42

        XCTAssertEqual(ListTaskCount.count([], list: publicList, currentUserId: nil), 42)
    }

    /// A saved-filter list counts whatever its filters admit — through the SHARED
    /// `filterTasksForList`, not the sidebar's old private copy, which had drifted.
    func testAVirtualListCountsWhatItsFiltersAdmit() {
        var smart = list(virtual: true)
        smart.filterCompletion = "incomplete"
        let tasks = [task("a", listIds: ["anywhere"]),
                     task("b", listIds: ["anywhere"], completed: true)]

        XCTAssertEqual(ListTaskCount.count(tasks, list: smart, currentUserId: nil), 1)
    }

    /// The drift the old private copy had: it applied no repeating filter at all, so a list
    /// filtered to repeating tasks badged every task it could see.
    func testAVirtualListHonoursTheRepeatingFilterTheOldCopyIgnored() {
        var repeatingOnly = list(virtual: true)
        repeatingOnly.isVirtual = true
        repeatingOnly.filterRepeating = "daily"
        var daily = task("a", listIds: ["anywhere"])
        daily.repeating = .daily
        let oneOff = task("b", listIds: ["anywhere"])

        XCTAssertEqual(ListTaskCount.count([daily, oneOff], list: repeatingOnly, currentUserId: nil), 1,
                       "the sidebar's private filter copy ignored filterRepeating entirely")
    }

    func testTheBatchPassAgreesWithTheSingleCount() {
        let tasks = [task("a", listIds: ["work"]), task("b", listIds: ["home"]),
                     task("c", listIds: ["work"], completed: true)]
        let work = list("work"), home = list("home")

        let batch = ListTaskCount.counts(tasks, lists: [work, home], currentUserId: nil)

        XCTAssertEqual(batch["work"], ListTaskCount.count(tasks, list: work, currentUserId: nil))
        XCTAssertEqual(batch["home"], ListTaskCount.count(tasks, list: home, currentUserId: nil))
    }

    func testNoTasksIsZeroNotAMissingBadge() {
        XCTAssertEqual(ListTaskCount.count([], list: list(), currentUserId: nil), 0)
    }
}
