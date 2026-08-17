//  MacMyTasksFilterTests.swift
//  My Tasks honours the saved filters on Mac too (task ebdf94a1).
//
//  Jon: "add filters to My Tasks just like they are in iOS."
//
//  Mac's My Tasks took no filters at all — it hardcoded "incomplete", so the completion filter
//  could not be expressed, and priority and due date were ignored outright. iOS has had all
//  three, saved in `MyTasksPreferences` and synced, so someone who set a filter on their phone
//  saw it do nothing on the desktop.
//
//  The filtering itself is NOT reimplemented here. `filterTasksForList` and its helpers are
//  shared and already mirror iOS; reusing them is the whole point, because a second
//  implementation of "what "today" means" is how two platforms start disagreeing about a due
//  date (ASTRID.md rule 8).
//
//  WHAT DELIBERATELY DOES NOT CHANGE: Mac includes UNASSIGNED tasks in My Tasks while iOS scopes
//  to assignee == me (task d0306aab, and the reasoning is in MacMyTasks). This task is about the
//  filters, not about that scope, so the scope is left alone and pinned below — otherwise
//  "just like iOS" quietly becomes a second, unasked-for change.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacMyTasksFilterTests: XCTestCase {

    private let me = "user-me"
    private let someoneElse = "user-other"

    private func task(_ id: String,
                      assignee: String?,
                      completed: Bool = false,
                      priority: Task.Priority = .none,
                      due: Date? = nil) -> Task {
        var t = Task(id: id, title: "Task \(id)")
        t.assigneeId = assignee
        t.completed = completed
        t.priority = priority
        t.dueDateTime = due
        return t
    }

    private func defaults(completion: String = "default",
                          priority: [Int] = [],
                          dueDate: String = "all") -> MyTasksPreferences {
        MyTasksPreferences(filterPriority: priority,
                           filterAssignee: [],
                           filterDueDate: dueDate,
                           filterCompletion: completion,
                           sortBy: "auto",
                           manualSortOrder: nil)
    }

    // MARK: - The scope, which this task does not change

    func testMineAndUnassignedAreIncludedAndOtherPeopleAreNot() {
        let tasks = [task("a", assignee: me),
                     task("b", assignee: nil),
                     task("c", assignee: someoneElse)]
        let ids = MacMyTasks.filter(tasks, userId: me, preferences: defaults()).map(\.id)
        XCTAssertEqual(ids.sorted(), ["a", "b"],
                       "Mac deliberately includes unassigned tasks — see task d0306aab")
    }

    // MARK: - Completion

    /// The default hides completed work, as before.
    func testCompletedTasksAreHiddenByDefault() {
        let tasks = [task("open", assignee: me), task("done", assignee: me, completed: true)]
        let ids = MacMyTasks.filter(tasks, userId: me, preferences: defaults()).map(\.id)
        XCTAssertEqual(ids, ["open"])
    }

    /// THE ONE THE OLD CODE COULD NOT EXPRESS. "incomplete" was hardcoded, so asking to see
    /// everything did nothing at all.
    func testTheAllFilterShowsCompletedTasksToo() {
        let tasks = [task("open", assignee: me), task("done", assignee: me, completed: true)]
        let ids = MacMyTasks.filter(tasks, userId: me,
                                    preferences: defaults(completion: "all")).map(\.id)
        XCTAssertEqual(ids.sorted(), ["done", "open"])
    }

    func testTheCompletedFilterShowsOnlyCompletedTasks() {
        let tasks = [task("open", assignee: me), task("done", assignee: me, completed: true)]
        let ids = MacMyTasks.filter(tasks, userId: me,
                                    preferences: defaults(completion: "completed")).map(\.id)
        XCTAssertEqual(ids, ["done"])
    }

    // MARK: - Priority

    func testAPriorityFilterKeepsOnlyThatPriority() {
        let tasks = [task("high", assignee: me, priority: .high),
                     task("low", assignee: me, priority: .low)]
        let ids = MacMyTasks.filter(tasks, userId: me,
                                    preferences: defaults(priority: [Task.Priority.high.rawValue])).map(\.id)
        XCTAssertEqual(ids, ["high"])
    }

    /// An empty array means "all" — it is the default value, and treating it as "match nothing"
    /// would blank the view for everyone who has never touched the filters.
    func testAnEmptyPriorityListMeansAll() {
        let tasks = [task("high", assignee: me, priority: .high),
                     task("low", assignee: me, priority: .low)]
        let ids = MacMyTasks.filter(tasks, userId: me, preferences: defaults(priority: [])).map(\.id)
        XCTAssertEqual(ids.sorted(), ["high", "low"])
    }

    // MARK: - Due date

    func testADueDateFilterNarrowsToThatWindow() {
        let farFuture = Calendar.current.date(byAdding: .day, value: 90, to: Date())!
        let tasks = [task("today", assignee: me, due: Date()),
                     task("later", assignee: me, due: farFuture),
                     task("none", assignee: me, due: nil)]
        let ids = MacMyTasks.filter(tasks, userId: me,
                                    preferences: defaults(dueDate: "today")).map(\.id)
        XCTAssertFalse(ids.contains("later"), "A task due in 90 days is not due today")
        XCTAssertFalse(ids.contains("none"), "A task with no due date is not due today")
    }

    // MARK: - Duplicates

    /// A task in two lists appeared twice before de-duplication; that must survive filtering.
    func testATaskInTwoListsAppearsOnce() {
        let duplicated = task("same", assignee: me)
        let ids = MacMyTasks.filter([duplicated, duplicated], userId: me, preferences: defaults()).map(\.id)
        XCTAssertEqual(ids, ["same"])
    }

    // MARK: - The filters are reachable

    /// Behaviour is nothing if nobody can get at it. My Tasks is virtual, so it was excluded
    /// from the list filter control and had no route of its own — the filters existed, were
    /// synced, and could only be changed from another device.
    func testTheFilterControlIsOfferedForMyTasks() throws {
        let root = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac/App/MacRootView.swift"), encoding: .utf8)
        XCTAssertTrue(root.contains("myTasksFilterButton"),
                      "My Tasks needs its own filter control — it has no TaskList to edit")
        XCTAssertTrue(root.contains("MacMyTasksFilterSheet()"),
                      "and a sheet to open")
    }

    /// The sheet must offer the same three iOS offers, read from the same synced preferences.
    func testTheSheetOffersTheSameThreeFiltersAsIOS() throws {
        let sheet = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac/Views/MacMyTasksFilterSheet.swift"), encoding: .utf8)
        XCTAssertTrue(sheet.contains("MacListFilter.completion"))
        XCTAssertTrue(sheet.contains("MacListFilter.priority"))
        XCTAssertTrue(sheet.contains("MacListFilter.dueDate"))
        XCTAssertTrue(sheet.contains("MyTasksPreferencesService.shared"),
                      "must read and write the SYNCED preferences, not a local copy")
    }

    // MARK: - Unknown values must not blank the view

    /// A newer client can save a filter value this build has never heard of. Showing nothing is
    /// the worst possible response — the same rule the repeating filter already follows.
    func testAnUnrecognisedFilterValueDoesNotEmptyTheView() {
        let tasks = [task("a", assignee: me)]
        let ids = MacMyTasks.filter(tasks, userId: me,
                                    preferences: defaults(completion: "sometime-next-decade")).map(\.id)
        XCTAssertEqual(ids, ["a"])
    }
}
#endif
