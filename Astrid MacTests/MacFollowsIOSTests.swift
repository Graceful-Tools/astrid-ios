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

        let ids = MacMyTasks.filter([mine, unassigned, theirs], userId: "me",
                                    preferences: MyTasksPreferences()).map(\.id)

        XCTAssertEqual(ids, ["mine"])
    }

    /// iOS shows nothing when nobody is signed in; the Mac showed every unassigned task.
    func testD25_noSignedInUserMeansAnEmptyMyTasks() {
        let unassigned = Task(id: "u", title: "u", completed: false)
        XCTAssertTrue(MacMyTasks.filter([unassigned], userId: nil, preferences: MyTasksPreferences()).isEmpty)
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

        let picker = MacListPicker(selectedIds: [], lists: [real, saved, status],
                                   onToggle: { _ in }, isPresented: .constant(false))

        XCTAssertEqual(picker.selectableLists.map(\.id), ["real", "status"])
    }

    // MARK: - Search runs iOS's search

    private func task(_ id: String, _ title: String, notes: String = "",
                      priority: Task.Priority = .none) -> Task {
        var t = Task(id: id, title: title, completed: false)
        t.description = notes
        t.priority = priority
        return t
    }

    /// iOS matches the query as one phrase; the Mac matched each word anywhere.
    func testFollowIOS_searchMatchesTheQueryAsOnePhrase() {
        let tasks = [task("1", "Buy milk and bread"), task("2", "Buy milk")]
        XCTAssertEqual(TaskSearch.results(tasks, query: "buy bread").map(\.id), [])
        XCTAssertEqual(TaskSearch.results(tasks, query: "milk and").map(\.id), ["1"])
    }

    /// iOS also finds a task by the name of the person it is assigned to.
    func testFollowIOS_searchMatchesTheAssigneesName() {
        var t = task("1", "Call the bank")
        t.assignee = user("u-dana", "Dana")
        XCTAssertEqual(TaskSearch.results([t], query: "dana").map(\.id), ["1"])
    }

    /// iOS hides completed work in search, as its lists do by default; the Mac listed every
    /// completed task ever.
    func testFollowIOS_searchHidesLongCompletedTasks() {
        var done = task("done", "milk")
        done.completed = true
        done.completedAt = Date().addingTimeInterval(-30 * 86_400)
        XCTAssertEqual(TaskSearch.results([done, task("open", "milk")], query: "milk").map(\.id), ["open"])
    }

    /// iOS sorts search results by priority; the Mac by newest.
    func testFollowIOS_searchSortsByPriority() {
        let tasks = [task("low", "milk", priority: .low), task("high", "milk", priority: .high)]
        XCTAssertEqual(TaskSearch.results(tasks, query: "milk").map(\.id), ["high", "low"])
    }

    /// iOS searches top-level tasks; a subtask shows under its parent, not as a result of its own.
    func testFollowIOS_searchSkipsSubtasks() {
        var sub = task("sub", "milk")
        sub.parentTaskId = "parent"
        XCTAssertEqual(TaskSearch.results([sub], query: "milk").map(\.id), [])
    }
}
#endif
