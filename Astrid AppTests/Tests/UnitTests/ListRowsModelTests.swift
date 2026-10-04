//  ListRowsModelTests.swift
//  AITD-460 — a list's rows are astrid-core's `rowsForList`, on iOS and the Mac. These pin iOS's
//  list as it drew before the move (the deleted Swift `filterTasksForList`,
//  `sortTasksByListSetting`, `spliceSubtasks`, `MyTasksScope`) where the core used to answer
//  differently — CONTRACTS D40–D42 — and how the model asks: in the background, again when the
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

    /// D40: a list that has never been given a sort is in iOS's `sortBy ?? "manual"` order —
    /// newest first with nothing arranged — where the core (and web, and the Mac) read auto.
    func testAITD460_aListWithNoSortIsNewestFirstAsOnIOS() throws {
        let tasks = [task("old", priority: .high, created: 1), task("new", priority: .none, created: 2)]
        XCTAssertEqual(try CoreRowsFixture.rows(tasks, list: list(sortBy: nil)), ["new", "old"])
        XCTAssertEqual(try CoreRowsFixture.rows(tasks, list: list(sortBy: "auto")), ["old", "new"],
                       "fixture check: auto would put the high-priority task first")
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
        let changed = PassthroughSubject<Void, Never>()
        let model = ListRowsModel(session: session, tasksChanged: changed.eraseToAnyPublisher())
        await model.load(query("l1", list(priority: "0")))
        XCTAssertEqual(Set(model.rowIds), ["a", "b"])

        var command = CoreCommand(kind: "updateTask", taskId: "a")
        command.set("changes", ["priority": 3])
        try await session.run(command)
        changed.send(())

        let deadline = Date().addingTimeInterval(5)
        while model.rowIds.count == 2, Date() < deadline {
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.rowIds, ["b"])
    }

    // MARK: - The Swift copies are gone

    func testAITD460_theListViewsAskTheCore() throws {
        for path in ["Astrid App/Views/Tasks/TaskListView.swift", "Astrid Mac/App/MacRootView.swift"] {
            let text = try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(text.contains("ListRowsModel()"), "\(path) does not ask the core for its rows")
            for gone in ["filterTasksForList", "sortTasksByListSetting", "spliceSubtasks", "MyTasksScope",
                         "applyCompletionFilterWithWindow", "applyListDueDateFilter"] {
                XCTAssertFalse(text.contains(gone), "\(path) still calls the Swift \(gone)")
            }
        }
    }
}
