//  TaskListHydrationTests.swift
//  Regression guard for AITD-415 — the ROOT of the offline bugs behind AITD-413 and AITD-414.
//
//  `CDTask.toDomainModel()` restores `listIds` and sets `lists: nil`, so after an offline cold
//  launch every cached task knew its list ids and carried no list objects. `listIds` answers
//  membership; it cannot answer name, colour, privacy or members — which is what the UI reads.
//
//  These tests pin the join itself, and then pin it THROUGH the downstream helpers that were
//  broken, so the failure is described where it was actually felt rather than only where it was
//  caused.

import XCTest
@testable import Astrid_App

final class TaskListHydrationTests: XCTestCase {

    /// Exactly what `CDTask.toDomainModel()` hands back: ids, no list objects.
    private func cachedTask(_ id: String, listIds: [String]) -> Task {
        var t = Task(id: id, title: "Task \(id)")
        t.listIds = listIds
        t.lists = nil
        return t
    }

    private func list(_ id: String, name: String, privacy: TaskList.Privacy = .PRIVATE) -> TaskList {
        var l = TaskList(id: id, name: name)
        l.privacy = privacy
        return l
    }

    // MARK: - THE BUG

    /// The join: a task that came out of the cache gets its lists back, with the names and
    /// colours the ids alone could never carry.
    func testAITD415CachedTaskGetsItsListsBack() {
        let groceries = list("l1", name: "Groceries")

        let hydrated = TaskListHydration.hydrated([cachedTask("a", listIds: ["l1"])],
                                                  using: [groceries])

        XCTAssertEqual(hydrated.first?.lists?.map(\.id), ["l1"])
        XCTAssertEqual(hydrated.first?.lists?.first?.name, "Groceries",
                       "the name is the whole point — listIds could already answer membership")
    }

    /// WHERE IT WAS FELT (1): the list chips on every task row. `chipListsForTaskRow` takes
    /// `task.lists`, so offline it drew nothing at all.
    func testAITD415TheListChipsOnATaskRowComeBack() {
        let cached = cachedTask("a", listIds: ["l1"])

        XCTAssertTrue(chipListsForTaskRow(cached.lists).isEmpty,
                      "precondition: this is the offline bug — no chips from a cached task")

        let hydrated = TaskListHydration.hydrated([cached], using: [list("l1", name: "Groceries")])
        XCTAssertEqual(chipListsForTaskRow(hydrated.first?.lists).map(\.name), ["Groceries"])
    }

    /// WHERE IT WAS FELT (2): "is this task on a public list", which drives the public badge and
    /// the share affordances. A cached task answered "no" for everything.
    func testAITD415PublicListMembershipIsAnswerableAgain() {
        let cached = cachedTask("a", listIds: ["l1"])
        let isPublic: (Task) -> Bool = { $0.lists?.contains { $0.privacy == .PUBLIC } ?? false }

        XCTAssertFalse(isPublic(cached), "precondition: the offline bug")

        let hydrated = TaskListHydration.hydrated([cached],
                                                  using: [list("l1", name: "Town", privacy: .PUBLIC)])
        XCTAssertTrue(isPublic(hydrated[0]))
    }

    // MARK: - The rules the join has to keep

    /// SERVER DATA WINS. A task from the API carries lists hydrated deeper than the cache may be
    /// — with members, invitations, settings. Re-joining it against a shallower cached copy would
    /// be a downgrade, and is exactly how a roster would go missing again.
    func testHydratedListsAreNeverOverwritten() {
        var fromServer = Task(id: "a", title: "A")
        fromServer.listIds = ["l1"]
        var rich = list("l1", name: "Groceries")
        rich.listMembers = [ListMember(id: "m1", listId: "l1", userId: "u1", role: "MEMBER")]
        fromServer.lists = [rich]

        let result = TaskListHydration.hydrated([fromServer], using: [list("l1", name: "STALE")])

        XCTAssertEqual(result[0].lists?.first?.name, "Groceries")
        XCTAssertEqual(result[0].lists?.first?.listMembers?.count, 1,
                       "the cached copy is shallower — joining over the server's would lose the roster")
    }

    /// Order follows `listIds`, so the first chip on a row does not shuffle between launches.
    func testOrderFollowsListIds() {
        let hydrated = TaskListHydration.hydrated(
            [cachedTask("a", listIds: ["l2", "l1"])],
            using: [list("l1", name: "One"), list("l2", name: "Two")])

        XCTAssertEqual(hydrated[0].lists?.map(\.id), ["l2", "l1"])
    }

    /// A list we have not cached is "we don't know", not "no lists" — `lists` must stay nil so a
    /// view cannot confidently draw an empty state over missing data.
    func testAnUnresolvableListLeavesListsNilRatherThanEmpty() {
        let result = TaskListHydration.hydrated([cachedTask("a", listIds: ["gone"])],
                                                using: [list("l1", name: "One")])

        XCTAssertNil(result[0].lists)
    }

    /// Partial knowledge is still worth having: one resolvable id out of two hydrates that one.
    func testPartiallyResolvableMembershipHydratesWhatItCan() {
        let result = TaskListHydration.hydrated([cachedTask("a", listIds: ["l1", "gone"])],
                                                using: [list("l1", name: "One")])

        XCTAssertEqual(result[0].lists?.map(\.id), ["l1"])
    }

    func testATaskWithNoListsIsLeftAlone() {
        var loose = Task(id: "a", title: "A")
        loose.listIds = []

        XCTAssertNil(TaskListHydration.hydrated([loose], using: [list("l1", name: "One")])[0].lists)
    }

    /// No cached lists at all — first launch, nothing synced — must be a no-op, not a crash or
    /// an empty-array downgrade.
    func testNoCachedListsIsANoOp() {
        let cached = cachedTask("a", listIds: ["l1"])

        XCTAssertNil(TaskListHydration.hydrated([cached], using: [])[0].lists)
    }

    /// Duplicate ids in the cache (a merge that went wrong) must not make the join ambiguous.
    func testDuplicateCachedListsResolveDeterministically() {
        let index = TaskListHydration.index([list("l1", name: "First"), list("l1", name: "Second")])

        XCTAssertEqual(index["l1"]?.name, "First")
    }
}

// MARK: - The join on its own

extension TaskListHydrationTests {

    /// `TaskService.createTask` resolves its optimistic row's lists this way. It used to do the
    /// compactMap inline — one of the four copies AITD-415 retired.
    func testTheJoinAnswersDirectlyForACallerHoldingOnlyIds() {
        let index = TaskListHydration.index([list("l1", name: "Groceries")])

        XCTAssertEqual(TaskListHydration.lists(forListIds: ["l1"], using: index)?.map(\.name),
                       ["Groceries"])
        XCTAssertNil(TaskListHydration.lists(forListIds: ["gone"], using: index),
                     "nothing resolvable is 'we don't know', not 'no lists'")
        XCTAssertNil(TaskListHydration.lists(forListIds: [], using: index))
    }
}
