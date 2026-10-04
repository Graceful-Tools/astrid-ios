//  MacFollowsIOSTests.swift
//  AITD-follow-ios — where the Mac and iOS copies of a behaviour disagreed, the Mac now does what
//  iOS does. Jon, 2026-10-03: "on disagreement follow iOS."
//
//  Each divergence was found by mapping both apps onto astrid-core (CONTRACTS D23, D25, D28) or
//  by reading the two copies side by side (search). Each fix moves the rule into ONE shared helper
//  that both apps call, so the two cannot drift apart again.

#if os(macOS)
import XCTest
import SwiftUI
import Combine
@testable import Astrid_Mac

@MainActor
final class MacFollowsIOSTests: XCTestCase {

    private func user(_ id: String, _ name: String) -> User {
        User(id: id, email: "\(id)@astrid.cc", name: name, image: nil)
    }

    // MARK: - D23: a mention is a reference, not plain text

    /// iOS sends `@[Name](id)`, which is what draws the pill and notifies the person. The Mac
    /// inserted `@Name`, so a mention typed on the Mac reached nobody.
    func testD23_aMentionPickedOnTheMacIsAReference() throws {
        let draft = MacCommentDraft()
        draft.text = "thanks @da"
        let dana = ListMember(id: "lm-dana", listId: "l1", userId: "u-dana", role: "MEMBER",
                              user: user("u-dana", "Dana"))
        draft.updateSuggestions(members: [dana])
        let pick = try XCTUnwrap(draft.suggestions.first)

        draft.applySuggestion(pick)

        XCTAssertEqual(draft.text, "thanks @[Dana](u-dana) ")
    }

    // MARK: - D25: My Tasks is what is assigned to me

    /// iOS's My Tasks is "assigned to me" only. The Mac also showed unassigned tasks the reader
    /// could see, so the two apps counted My Tasks differently for the same account.
    func testD25_myTasksIsOnlyWhatIsAssignedToMe() {
        var mine = Task(id: "mine", title: "mine", completed: false); mine.assigneeId = "me"
        var unassigned = Task(id: "unassigned", title: "unassigned", completed: false)
        unassigned.creatorId = "me"
        var theirs = Task(id: "theirs", title: "theirs", completed: false); theirs.assigneeId = "you"

        let ids = CoreRowsFixture.myTasksTasks([mine, unassigned, theirs], userId: "me",
                                    preferences: MyTasksPreferences()).map(\.id)

        XCTAssertEqual(ids, ["mine"])
    }

    /// iOS shows nothing when nobody is signed in; the Mac showed every unassigned task.
    func testD25_noSignedInUserMeansAnEmptyMyTasks() {
        let unassigned = Task(id: "u", title: "u", completed: false)
        XCTAssertTrue(CoreRowsFixture.myTasksTasks([unassigned], userId: nil, preferences: MyTasksPreferences()).isEmpty)
    }

    // MARK: - D28: the list picker offers what iOS offers

    /// iOS's picker leaves out virtual lists (saved filters) and nothing else. The Mac's left out
    /// board-status lists and OFFERED saved filters — a destination no task can be filed in.
    func testD28_theListPickerLeavesOutSavedFiltersLikeIOS() {
        var real = TaskList(id: "real", name: "Real", privacy: .PRIVATE)
        real.isVirtual = false
        var saved = TaskList(id: "saved", name: "Saved filter", privacy: .PRIVATE)
        saved.isVirtual = true
        var status = TaskList(id: "status", name: "Doing", privacy: .PRIVATE)
        status.listType = "status"

        // Both pickers read the core's `listPicks` since AITD-461 — in the sidebar's order.
        let session = try! CoreBoardFixture.session(lists: [real, saved, status], projects: [])
        let offered = try! CoreRowsFixture.wait(session, ListPicks.command(""), as: ListToggles.self)
        XCTAssertEqual(offered.options.map(\.id), ["status", "real"])
    }

    // MARK: - Search runs iOS's search — answered by astrid-core since AITD-459

    private func task(_ id: String, _ title: String, notes: String = "",
                      priority: Task.Priority = .none) -> Task {
        var t = Task(id: id, title: title, completed: false)
        t.description = notes
        t.priority = priority
        return t
    }

    /// The ids the core's search finds among `tasks`, through the model both apps draw.
    private func results(_ tasks: [Task], query: String) async throws -> [String] {
        let model = TaskSearchModel(session: try CoreSearchFixture.session(seeding: tasks),
                                    tasksChanged: Empty().eraseToAnyPublisher())
        await model.search(query)
        return model.resultIds
    }

    /// iOS matches the query as one phrase; the Mac matched each word anywhere.
    func testFollowIOS_searchMatchesTheQueryAsOnePhrase() async throws {
        let tasks = [task("1", "Buy milk and bread"), task("2", "Buy milk")]
        let none = try await results(tasks, query: "buy bread")
        XCTAssertEqual(none, [])
        let one = try await results(tasks, query: "milk and")
        XCTAssertEqual(one, ["1"])
    }

    /// iOS also finds a task by the name of the person it is assigned to.
    func testFollowIOS_searchMatchesTheAssigneesName() async throws {
        var t = task("1", "Call the bank")
        t.assigneeId = "u-dana"
        t.assignee = user("u-dana", "Dana")
        let found = try await results([t], query: "dana")
        XCTAssertEqual(found, ["1"])
    }

    /// iOS hides completed work in search, as its lists do by default; the Mac listed every
    /// completed task ever.
    func testFollowIOS_searchHidesLongCompletedTasks() async throws {
        var done = task("done", "milk")
        done.completed = true
        done.completedAt = Date().addingTimeInterval(-30 * 86_400)
        let found = try await results([done, task("open", "milk")], query: "milk")
        XCTAssertEqual(found, ["open"])
    }

    /// iOS sorts search results by priority; the Mac by newest.
    func testFollowIOS_searchSortsByPriority() async throws {
        let tasks = [task("low", "milk", priority: .low), task("high", "milk", priority: .high)]
        let found = try await results(tasks, query: "milk")
        XCTAssertEqual(found, ["high", "low"])
    }

    /// iOS searches top-level tasks; a subtask shows under its parent, not as a result of its own.
    func testFollowIOS_searchSkipsSubtasks() async throws {
        var sub = task("sub", "milk")
        sub.parentTaskId = "parent"
        let found = try await results([sub], query: "milk")
        XCTAssertEqual(found, [])
    }
}
#endif
