//  ListRowsModelTests.swift
//  AITD-460 — a list's rows are astrid-core's `rowsForList`, on iOS and the Mac. These pin iOS's
//  list as it drew before the move (the deleted Swift `filterTasksForList`,
//  `sortTasksByListSetting`, `spliceSubtasks`, `MyTasksScope`) where the core used to answer
//  differently — CONTRACTS D41–D42; D40 has since gone to web (AITD-495) — and how the model asks: in the background, again when the
//  tasks change, never with another list's rows under this one's title.

import XCTest
import Combine
import AstridCore
@testable import Astrid_App

@MainActor
final class ListRowsModelTests: XCTestCase {

    private func task(_ id: String, priority: Task.Priority = .none, listIds: [String] = ["l1"],
                      parent: String? = nil, completed: Bool = false, created: TimeInterval? = nil,
                      due: Date? = nil) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.priority = priority
        t.listIds = listIds
        t.parentTaskId = parent
        t.createdAt = created.map { Date(timeIntervalSince1970: 1_700_000_000 + $0) }
        t.dueDateTime = due
        return t
    }

    private func list(_ id: String = "l1", sortBy: String? = "auto", completion: String? = nil,
                      priority: String? = nil) -> TaskList {
        var l = TaskList(id: id, name: id)
        l.sortBy = sortBy
        l.filterCompletion = completion
        l.filterPriority = priority
        return l
    }

    // MARK: - Where the core answered differently from iOS

    /// D40, reversed by AITD-495: a list that has never been given a sort is drawn as web draws
    /// it — auto, open before completed, then priority. It was read as `manual` (newest first), so
    /// a completed task sat wherever its creation date put it: first, in the comparison shot.
    func testAITD495_aListWithNoSortIsAutoWithCompletedLastAsOnWeb() throws {
        let tasks = [task("old", priority: .high, created: 1), task("new", priority: .none, created: 2),
                     task("done", priority: .high, completed: true, created: 3)]
        XCTAssertEqual(try CoreRowsFixture.rows(tasks, list: list(sortBy: nil, completion: "all")),
                       ["old", "new", "done"])
        XCTAssertEqual(try CoreRowsFixture.rows(tasks, list: list(sortBy: "manual", completion: "all")),
                       ["done", "new", "old"], "fixture check: manual, with nothing arranged, is newest first")
    }

    /// D41: a spliced subtask obeys the view's completion filter and nothing else, as iOS's
    /// `applyContextCompletionFilter` — the list's priority filter chose its parent, not its parts.
    func testAITD460_aSubtaskShowsUnderItsParentWhateverItsPriority() throws {
        let tasks = [task("p", priority: .high), task("c", priority: .none, parent: "p", created: 1)]
        XCTAssertEqual(try CoreRowsFixture.rows(tasks, list: list(priority: "3"), subtaskDisplay: "indented"),
                       ["p", "c"])
    }

    /// D41: iOS splices from every task it holds, so a subtask that was never filed in its
    /// parent's list still shows under it; the core used to splice from the list's members only.
    func testAITD460_aSubtaskNotFiledInTheListStillShowsUnderItsParent() throws {
        let tasks = [task("p"), task("c", listIds: [], parent: "p", created: 1)]
        XCTAssertEqual(try CoreRowsFixture.rows(tasks, list: list(), subtaskDisplay: "indented"), ["p", "c"])
    }

    /// Ties fall as they fell on iOS: in its store's order (due date, then newest created), not
    /// the cache's storage order — two equal-priority undated tasks under "priority".
    func testAITD460_tiesFallInIOSStoreOrder() throws {
        let tasks = [task("older", created: 1), task("newer", created: 2),
                     task("dated", created: 0, due: Date().addingTimeInterval(86_400))]
        XCTAssertEqual(try CoreRowsFixture.rows(tasks, list: list(sortBy: "priority")), ["dated", "newer", "older"])
    }

    /// My Tasks is what is assigned to the reader, by the filters the shell holds (D25).
    func testAITD460_myTasksIsMineByTheShellsFilters() throws {
        var mine = task("mine", priority: .high, listIds: []); mine.assigneeId = "me"
        var low = task("low", priority: .low, listIds: []); low.assigneeId = "me"
        var theirs = task("theirs", listIds: []); theirs.assigneeId = "you"
        var prefs = MyTasksPreferences()
        prefs.filterPriority = [3]
        XCTAssertEqual(try CoreRowsFixture.myTasks([mine, low, theirs], userId: "me", preferences: prefs), ["mine"])
        XCTAssertEqual(try CoreRowsFixture.myTasks([mine], userId: nil, preferences: MyTasksPreferences()), [],
                       "nobody signed in: nothing is mine")
    }

    /// iOS's view with no list: every task, the default completion window, highest priority first.
    func testAITD460_theEverythingViewIsPriorityOrderedAcrossLists() throws {
        let tasks = [task("a", priority: .low, listIds: ["x"]), task("b", priority: .high, listIds: [])]
        XCTAssertEqual(try CoreRowsFixture.rows(tasks, list: ListRowsModel.everything), ["b", "a"])
    }

    /// A public list the reader is not in: its tasks travel with the question.
    func testAITD460_aPublicListsTasksTravelWithTheQuestion() throws {
        let theirs = [task("t1", priority: .low, listIds: ["pub"]), task("t2", priority: .high, listIds: ["pub"])]
        let query = ListRowsModel.Query(listId: "pub", list: list("pub"), tasks: theirs,
                                        subtaskDisplay: "indented", currentUserId: "me")
        XCTAssertEqual(try CoreRowsFixture.answer([], query: query).ids, ["t2", "t1"])
    }

    // MARK: - Search splices like the list (iOS)

    func testAITD460_searchResultsCarryTheirSubtasksOnIOS() async throws {
        let session = try CoreSearchFixture.session(seeding: [task("p"), task("c", parent: "p", created: 1)])
        let model = TaskSearchModel(session: session, tasksChanged: Empty().eraseToAnyPublisher())
        await model.search("p", splice: .init(subtaskDisplay: "indented", listShowSubtasks: nil))
        XCTAssertEqual(model.resultIds, ["p", "c"])
        await model.search("p")
        XCTAssertEqual(model.resultIds, ["p"], "without a splice the results stay flat, as on the Mac")
    }

    // MARK: - The model

    private func query(_ listId: String, _ l: TaskList) -> ListRowsModel.Query {
        .init(listId: listId, list: l, subtaskDisplay: "under_parent", currentUserId: "me")
    }

    func testAITD460_theModelAnswersAndKnowsWhatItAnswered() async throws {
        let session = try CoreSearchFixture.session(seeding: [task("a"), task("b", listIds: ["l2"])])
        let model = ListRowsModel(session: session, tasksChanged: Empty().eraseToAnyPublisher())
        XCTAssertNil(model.ids(for: "l1"), "nothing asked: not answered, which is not empty")

        await model.load(query("l1", list()))
        XCTAssertEqual(model.ids(for: "l1"), ["a"])
        XCTAssertEqual(model.rows(["a"], in: ["a": task("a")]).map(\.id), ["a"])
    }

    /// Switching lists never shows the last list's rows under the new one: unanswered until the
    /// core answers, then that list's own; switching back shows its last rows at once.
    func testAITD460_switchingListsNeverShowsAnotherListsRows() async throws {
        let session = try CoreSearchFixture.session(seeding: [task("a"), task("b", listIds: ["l2"])])
        let model = ListRowsModel(session: session, tasksChanged: Empty().eraseToAnyPublisher())
        await model.load(query("l1", list()))

        model.update(query("l2", list("l2")))
        XCTAssertNil(model.ids(for: "l2"), "l2 not answered yet")
        XCTAssertNotEqual(model.rowIds, ["a"], "l1's rows must not stand in for l2's")
        await model.load(query("l2", list("l2")))
        XCTAssertEqual(model.ids(for: "l2"), ["b"])

        model.update(query("l1", list()))
        XCTAssertEqual(model.ids(for: "l1"), ["a"], "l1's last answer, at once")
    }

    /// A change to the tasks asks again, so the rows follow an edit.
    func testAITD460_aChangeToTheTasksAsksAgain() async throws {
        let session = try CoreSearchFixture.session(seeding: [task("a"), task("b")])
        let changed = PassthroughSubject<TaskListsTouched, Never>()
        let model = ListRowsModel(session: session, tasksChanged: changed.eraseToAnyPublisher())
        await model.load(query("l1", list(priority: "0")))
        XCTAssertEqual(Set(model.rowIds), ["a", "b"])

        var command = CoreCommand(kind: "updateTask", taskId: "a")
        command.set("changes", ["priority": 3])
        try await session.run(command)
        changed.send(.anyList)

        await waitUntil(model, "the re-prioritised row to leave the filter") { model.rowIds.count != 2 }
        XCTAssertEqual(model.rowIds, ["b"])
    }

    // MARK: - A change in a list off screen reads nothing (AITD-666)

    /// Loads `listId`, then reports how many more times the model asked the core after `touched`.
    private func asksAfter(_ touched: TaskListsTouched, showing listId: String,
                           _ l: TaskList? = nil) async throws -> Int {
        let session = try CoreSearchFixture.session(seeding: [task("a"), task("b", listIds: ["l2"])])
        let changed = PassthroughSubject<TaskListsTouched, Never>()
        let model = ListRowsModel(session: session, tasksChanged: changed.eraseToAnyPublisher())
        await model.load(query(listId, l ?? list(listId)))
        let before = model.asked
        changed.send(touched)
        // The sink hops to the main queue; let it run before counting.
        await _Concurrency.Task.yield()
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        return model.asked - before
    }

    /// AITD-666: a colleague's edit in a list nobody has open costs the open list no read.
    func testAITD666_aTaskChangeInAnotherListDoesNotReadThisOne() async throws {
        let asks = try await asksAfter(.lists(["l2"]), showing: "l1")
        XCTAssertEqual(asks, 0)
    }

    func testAITD666_aTaskChangeInTheOpenListReadsIt() async throws {
        let asks = try await asksAfter(.lists(["l2", "l1"]), showing: "l1")
        XCTAssertEqual(asks, 1)
    }

    /// An empty `listIds` is "could not say", never "no list is affected".
    func testAITD666_aChangeNamingNoListReadsAnyway() async throws {
        let none = try await asksAfter(.lists([]), showing: "l1")
        XCTAssertEqual(none, 1)
        let unknown = try await asksAfter(.anyList, showing: "l1")
        XCTAssertEqual(unknown, 1)
    }

    /// My Tasks and the everything view are assembled across the account: no task names them.
    func testAITD666_aVirtualListAlwaysReads() async throws {
        let mine = try await asksAfter(.lists(["l2"]), showing: ListRowsModel.myTasksId,
                                       TaskList(id: ListRowsModel.myTasksId, name: ""))
        XCTAssertEqual(mine, 1)
        let all = try await asksAfter(.lists(["l2"]), showing: ListRowsModel.everythingId,
                                      ListRowsModel.everything)
        XCTAssertEqual(all, 1)
    }

    func testAITD666_whatTouchesWhichList() {
        XCTAssertFalse(TaskListsTouched.lists(["l2"]).touches("l1"))
        XCTAssertTrue(TaskListsTouched.lists(["l1"]).touches("l1"))
        XCTAssertTrue(TaskListsTouched.lists([]).touches("l1"))
        XCTAssertTrue(TaskListsTouched.anyList.touches("l1"))
        XCTAssertTrue(TaskListsTouched.lists(["l2"]).touches("virtual:my-tasks"))
    }

    /// TaskService's half: the core's lists, widened by where the task was and is, and "any list"
    /// for a subtask, which is spliced under its parent wherever the parent is.
    func testAITD666_theListsATaskChangeTouches() {
        var before = task("a", listIds: ["l1"])
        var after = task("a", listIds: ["l3"])
        XCTAssertEqual(TaskListsTouched.forChange(coreListIds: ["l2"], before: [before], after: [after]),
                       .lists(["l1", "l2", "l3"]))
        XCTAssertEqual(TaskListsTouched.forChange(coreListIds: [], before: [before], after: [after]),
                       .anyList, "the core could not say")
        before.parentTaskId = "p"
        XCTAssertEqual(TaskListsTouched.forChange(coreListIds: ["l2"], before: [before], after: [after]),
                       .anyList, "a subtask can show in its parent's list")
        before.parentTaskId = nil
        after.parentTaskId = "p"
        XCTAssertEqual(TaskListsTouched.forChange(coreListIds: ["l2"], before: [before], after: [after]),
                       .anyList)
        XCTAssertEqual(TaskListsTouched.forChange(coreListIds: ["l2"], before: [], after: [task("p")],
                                                  hasSubtasks: true),
                       .anyList, "a parent decides where its subtasks show")
    }
}
